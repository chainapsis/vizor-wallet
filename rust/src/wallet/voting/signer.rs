//! The wallet-side seed boundary for delegation signing.
//!
//! `zcash_voting` never receives seed material. It hands the wallet a
//! [`DelegationSigningRequest`] (account index, network, seed fingerprint,
//! sighash, randomizer) and takes back only the detached SpendAuth signature.

use orchard::primitives::redpallas::SpendAuthRandomizer;
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
    let alpha = Option::<SpendAuthRandomizer>::from(SpendAuthRandomizer::from_bytes(request.alpha))
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
    use ff::PrimeField;
    use orchard::{
        keys::SpendAuthorizingKey,
        primitives::redpallas::{Signature, SpendAuth, VerificationKey},
    };

    const ACCOUNT_INDEX: u32 = 0;
    const SIGHASH: [u8; 32] = [0xAB; 32];

    fn seed() -> SecretVec<u8> {
        SecretVec::new(vec![0x42; 32])
    }

    fn alpha_bytes() -> [u8; 32] {
        pasta_curves::pallas::Scalar::from(7).to_repr()
    }

    fn request(seed: &SecretVec<u8>, alpha: [u8; 32]) -> DelegationSigningRequest {
        DelegationSigningRequest {
            account_index: ACCOUNT_INDEX,
            network: zcash_voting::Network::Testnet,
            seed_fingerprint: SeedFingerprint::from_seed(seed.expose_secret())
                .unwrap()
                .to_bytes(),
            sighash: SIGHASH,
            alpha,
        }
    }

    fn spend_authorizing_key(seed: &SecretVec<u8>) -> SpendAuthorizingKey {
        let usk = UnifiedSpendingKey::from_seed(
            &zcash_voting::Network::Testnet,
            seed.expose_secret(),
            AccountId::try_from(ACCOUNT_INDEX).unwrap(),
        )
        .unwrap();
        SpendAuthorizingKey::from(usk.orchard())
    }

    fn randomized_key(seed: &SecretVec<u8>, alpha: [u8; 32]) -> VerificationKey<SpendAuth> {
        let alpha = SpendAuthRandomizer::from_bytes(alpha).unwrap();
        VerificationKey::from(&spend_authorizing_key(seed).randomize(&alpha))
    }

    #[test]
    fn sign_delegation_request_happy_path_signs_and_verifies() {
        let seed = seed();
        let (sig_bytes, returned_sighash) =
            sign_delegation_request(&seed, request(&seed, alpha_bytes())).unwrap();

        randomized_key(&seed, alpha_bytes())
            .verify(&SIGHASH, &Signature::<SpendAuth>::from(sig_bytes))
            .unwrap();
        assert_eq!(returned_sighash, SIGHASH);
    }

    #[test]
    fn the_signature_binds_the_sighash_and_the_randomizer() {
        let seed = seed();
        let (sig_bytes, _) = sign_delegation_request(&seed, request(&seed, alpha_bytes())).unwrap();
        let signature = Signature::<SpendAuth>::from(sig_bytes);

        assert!(randomized_key(&seed, alpha_bytes())
            .verify(&[0xAC; 32], &signature)
            .is_err());
        let other_alpha = pasta_curves::pallas::Scalar::from(8).to_repr();
        assert!(randomized_key(&seed, other_alpha)
            .verify(&SIGHASH, &signature)
            .is_err());
    }

    #[test]
    fn a_noncanonical_alpha_is_refused() {
        let seed = seed();
        // The Pallas scalar modulus is below 2^255, so all-ones bytes are out of range.
        let error = sign_delegation_request(&seed, request(&seed, [0xFF; 32])).unwrap_err();
        assert_eq!(error, "delegation alpha is not a valid Pallas scalar");
    }

    #[test]
    fn another_wallets_request_is_refused() {
        let seed = seed();
        let mut other = request(&seed, alpha_bytes());
        other.seed_fingerprint = SeedFingerprint::from_seed(&[0x43; 32]).unwrap().to_bytes();
        let error = sign_delegation_request(&seed, other).unwrap_err();
        assert_eq!(
            error,
            "wallet seed fingerprint does not match delegation signing request"
        );
    }
}
