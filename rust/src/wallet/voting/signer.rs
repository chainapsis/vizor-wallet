//! The wallet-side seed boundary for delegation signing.
//!
//! `zcash_voting` never receives seed material. It hands the wallet a
//! [`DelegationSigningRequest`] (account index, network, seed fingerprint,
//! sighash, randomizer) and takes back only the detached SpendAuth signature.

use ff::PrimeField;
use secrecy::{ExposeSecret, SecretVec};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_voting::delegate::DelegationSigningRequest;
use zcash_voting::{SpendAuthSigner, VotingError};
use zip32::{fingerprint::SeedFingerprint, AccountId};

/// Signs delegation requests with a software wallet seed.
pub struct SeedSpendAuthSigner {
    seed: SecretVec<u8>,
}

impl SeedSpendAuthSigner {
    pub fn new(seed: SecretVec<u8>) -> Self {
        Self { seed }
    }
}

impl SpendAuthSigner for SeedSpendAuthSigner {
    fn sign(&self, request: DelegationSigningRequest) -> Result<[u8; 64], VotingError> {
        sign_delegation_request(&self.seed, request)
            .map(|(sig, _)| sig)
            .map_err(|message| VotingError::InvalidInput { message })
    }
}

/// Signs a delegation request with the Orchard spend authorizing key derived from
/// the wallet seed and account in the request.
///
/// Returns the detached signature bytes plus the original sighash when the seed,
/// account index, and randomizer all validate.
pub fn sign_delegation_request(
    seed: &SecretVec<u8>,
    request: DelegationSigningRequest,
) -> Result<([u8; 64], [u8; 32]), String> {
    let seed = seed.expose_secret();
    // Bind the request to this exact wallet seed before deriving any keys.
    let seed_fingerprint = SeedFingerprint::from_seed(seed)
        .ok_or_else(|| "wallet seed length is not valid for ZIP-32".to_string())?;
    if seed_fingerprint.to_bytes() != request.seed_fingerprint {
        return Err(
            "wallet seed fingerprint does not match delegation signing request".to_string(),
        );
    }

    // Derive the account Orchard signing key specified by the request metadata.
    let account = AccountId::try_from(request.account_index)
        .map_err(|_| format!("invalid account_index {}", request.account_index))?;
    let usk = UnifiedSpendingKey::from_seed(&request.network, seed, account)
        .map_err(|e| format!("derive account unified spending key failed: {e}"))?;
    let sk = *usk.orchard();
    let ask = orchard::keys::SpendAuthorizingKey::from(&sk);
    // The alpha randomizer must decode as a canonical Pallas scalar.
    let alpha = Option::<pasta_curves::pallas::Scalar>::from(
        pasta_curves::pallas::Scalar::from_repr(request.alpha),
    )
    .ok_or_else(|| "delegation alpha is not a valid Pallas scalar".to_string())?;
    // Sign the request-specific sighash with the randomized spend auth key.
    let rsk = ask.randomize(&alpha);
    let rng = voting_crypto_deps::rand::rngs::OsRng;
    let sig = rsk.sign(rng, &request.sighash);
    Ok(((&sig).into(), request.sighash))
}

#[cfg(test)]
mod tests {
    use super::*;
    use orchard::{
        keys::SpendAuthorizingKey,
        primitives::redpallas::{Signature, SpendAuth, VerificationKey},
    };

    #[test]
    fn sign_delegation_request_happy_path_signs_and_verifies() {
        let seed = SecretVec::new(vec![0x42; 32]);
        let account_index = 0u32;
        let account = AccountId::try_from(account_index).unwrap();
        let usk = UnifiedSpendingKey::from_seed(
            &zcash_voting::Network::Testnet,
            seed.expose_secret(),
            account,
        )
        .unwrap();
        let ask = SpendAuthorizingKey::from(usk.orchard());
        let alpha = pasta_curves::pallas::Scalar::from(7);
        let sighash = [0xAB; 32];
        let request = DelegationSigningRequest {
            account_index,
            network: zcash_voting::Network::Testnet,
            seed_fingerprint: SeedFingerprint::from_seed(seed.expose_secret())
                .unwrap()
                .to_bytes(),
            sighash,
            alpha: alpha.to_repr(),
        };

        let (sig_bytes, returned_sighash) = sign_delegation_request(&seed, request).unwrap();

        let verification_key = VerificationKey::from(&ask.randomize(&alpha));
        verification_key
            .verify(&sighash, &Signature::<SpendAuth>::from(sig_bytes))
            .unwrap();
        assert_eq!(returned_sighash, sighash);
    }
}
