use orchard::keys::{FullViewingKey, SpendingKey};
use rand::RngCore;
use zcash_keys::keys::UnifiedSpendingKey;
use zeroize::Zeroizing;
use zip32::{AccountId, Scope};

use crate::types::{Network, VotingError, VotingHotkey};

/// Byte length of stored voting hotkey secret material returned by
/// [`VotingHotkey::stored_secret`].
pub const VOTING_HOTKEY_STORED_SECRET_LEN: usize = 64;

/// ZIP-32 account index used for voting hotkey signing keys.
pub const VOTING_HOTKEY_ACCOUNT_INDEX: u32 = 0;

/// Orchard address index used for the delegation output target.
pub const VOTING_HOTKEY_ADDRESS_INDEX: u32 = 0;

/// Generates a random app-owned voting hotkey for v2 integrations.
///
/// Wallets should generate this secret once per local voting identity and round
/// and store [`VotingHotkey::stored_secret`] in platform secure storage. This
/// keeps wallet root seed and mnemonic material out of the voting hotkey API.
/// The resulting hotkey is not deterministic across fresh app installs unless
/// the stored hotkey secret is restored.
///
/// # Errors
///
/// Returns [`VotingError::InvalidInput`] when the generated seed cannot produce
/// an Orchard key for `network`.
pub fn generate_random_voting_hotkey(network: Network) -> Result<VotingHotkey, VotingError> {
    let mut secret = Zeroizing::new(vec![0u8; VOTING_HOTKEY_STORED_SECRET_LEN]);
    rand::rngs::OsRng.fill_bytes(secret.as_mut_slice());
    voting_hotkey_from_stored_secret(&secret, network)
}

pub(crate) fn voting_hotkey_from_stored_secret(
    stored_secret: &[u8],
    network: Network,
) -> Result<VotingHotkey, VotingError> {
    if stored_secret.len() != VOTING_HOTKEY_STORED_SECRET_LEN {
        return Err(VotingError::InvalidInput {
            message: format!(
                "stored hotkey secret must be exactly {} bytes, got {}",
                VOTING_HOTKEY_STORED_SECRET_LEN,
                stored_secret.len(),
            ),
        });
    }

    let raw_orchard_address = raw_orchard_address_from_seed(
        stored_secret,
        network,
        VOTING_HOTKEY_ACCOUNT_INDEX,
        VOTING_HOTKEY_ADDRESS_INDEX,
    )?;

    Ok(VotingHotkey::from_parts(
        stored_secret.to_vec(),
        raw_orchard_address,
        VOTING_HOTKEY_ADDRESS_INDEX,
        network,
    ))
}

pub(crate) fn spending_key_from_hotkey_seed(
    seed: &[u8],
    network: Network,
    account_index: u32,
) -> Result<SpendingKey, VotingError> {
    if seed.len() < 32 {
        return Err(VotingError::InvalidInput {
            message: format!("seed must be at least 32 bytes, got {}", seed.len()),
        });
    }

    let account = AccountId::try_from(account_index).map_err(|_| VotingError::InvalidInput {
        message: format!("invalid account_index {account_index}"),
    })?;

    let usk = UnifiedSpendingKey::from_seed(&network, seed, account).map_err(|e| {
        VotingError::InvalidInput {
            message: format!("failed to derive UnifiedSpendingKey from seed: {e}"),
        }
    })?;

    Ok(*usk.orchard())
}

fn raw_orchard_address_from_seed(
    seed: &[u8],
    network: Network,
    account_index: u32,
    address_index: u32,
) -> Result<[u8; 43], VotingError> {
    let spending_key = spending_key_from_hotkey_seed(seed, network, account_index)?;
    let full_viewing_key = FullViewingKey::from(&spending_key);
    let address = full_viewing_key.address_at(u64::from(address_index), Scope::External);

    Ok(address.to_raw_address_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stored_hotkey_secret_reconstructs_address() {
        let hotkey = VotingHotkey::from_stored_secret(&[0xAB; 64], Network::Regtest).unwrap();
        let reconstructed =
            VotingHotkey::from_stored_secret(hotkey.stored_secret(), Network::Regtest).unwrap();

        assert_eq!(hotkey.stored_secret(), reconstructed.stored_secret());
        assert_eq!(
            hotkey.raw_orchard_address(),
            reconstructed.raw_orchard_address()
        );
        assert_eq!(hotkey.address_index(), VOTING_HOTKEY_ADDRESS_INDEX);
        assert_eq!(hotkey.network(), Network::Regtest);
    }

    #[test]
    fn stored_hotkey_secret_is_bound_to_network() {
        let testnet = VotingHotkey::from_stored_secret(&[0xAB; 64], Network::Testnet).unwrap();
        let mainnet = VotingHotkey::from_stored_secret(&[0xAB; 64], Network::Mainnet).unwrap();

        assert_ne!(testnet.raw_orchard_address(), mainnet.raw_orchard_address());
    }

    #[test]
    fn random_hotkey_returns_storable_secret() {
        let first = generate_random_voting_hotkey(Network::Regtest).unwrap();
        let second = generate_random_voting_hotkey(Network::Regtest).unwrap();

        assert_eq!(first.stored_secret().len(), VOTING_HOTKEY_STORED_SECRET_LEN);
        assert_eq!(
            second.stored_secret().len(),
            VOTING_HOTKEY_STORED_SECRET_LEN
        );
        assert_ne!(first.stored_secret(), second.stored_secret());
    }

    #[test]
    fn hotkey_feeds_typed_delegation_and_vote_signer_paths() {
        use zcash_protocol::consensus::{NetworkConstants, Parameters};

        let hotkey = VotingHotkey::from_stored_secret(&[0xAB; 64], Network::Regtest).unwrap();
        let keys = crate::delegate::DelegationKeys::with_voting_hotkey(
            vec![8; 96],
            &hotkey,
            [9; 32],
            0,
            "Demo Round".to_string(),
        )
        .unwrap();

        assert_eq!(&keys.hotkey_raw_address, hotkey.raw_orchard_address());
        assert_eq!(keys.address_index, hotkey.address_index());
        assert_eq!(keys.coin_type, Network::Regtest.network_type().coin_type());

        match crate::vote::VoteSigner::hotkey(&hotkey) {
            crate::vote::VoteSigner::Hotkey {
                hotkey: signer_hotkey,
            } => {
                assert_eq!(signer_hotkey.stored_secret(), hotkey.stored_secret());
                assert_eq!(signer_hotkey.network(), hotkey.network());
            }
        }
    }

    #[test]
    fn hotkey_spending_key_uses_zip32_account_index() {
        let seed = [0x42; 64];

        let default =
            spending_key_from_hotkey_seed(&seed, Network::Regtest, VOTING_HOTKEY_ACCOUNT_INDEX)
                .unwrap();
        let account_0 = spending_key_from_hotkey_seed(&seed, Network::Regtest, 0).unwrap();
        let account_1 = spending_key_from_hotkey_seed(&seed, Network::Regtest, 1).unwrap();

        assert_eq!(
            FullViewingKey::from(&default).to_bytes(),
            FullViewingKey::from(&account_0).to_bytes()
        );
        assert_ne!(
            FullViewingKey::from(&account_0).to_bytes(),
            FullViewingKey::from(&account_1).to_bytes()
        );
    }

    #[test]
    fn short_stored_hotkey_secret_is_rejected() {
        let err = VotingHotkey::from_stored_secret(&[0x01; 16], Network::Regtest)
            .unwrap_err()
            .to_string();

        assert!(err.contains("stored hotkey secret must be exactly 64 bytes"));
    }

    #[test]
    fn long_stored_hotkey_secret_is_rejected() {
        let err = VotingHotkey::from_stored_secret(&[0x01; 65], Network::Regtest)
            .unwrap_err()
            .to_string();

        assert!(err.contains("stored hotkey secret must be exactly 64 bytes"));
    }
}
