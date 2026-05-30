use secrecy::{ExposeSecret, SecretVec};

use crate::wallet::network::WalletNetwork;

use super::voting_network;

/// Derives opaque voting hotkey bytes for a wallet account in a voting round.
///
/// `seed` is the platform-owned wallet seed material, while `round_id`,
/// `account_uuid`, and `network` are the voting context. The same tuple always
/// returns the same hotkey bytes; changing any tuple member produces
/// independent material.
///
/// The returned secret is not persisted by Rust.
///
/// # Errors
///
/// Returns an error when `zcash_voting` rejects the contextual seed material.
pub fn derive_hotkey(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<SecretVec<u8>, String> {
    derive_voting_hotkey(seed, round_id, account_uuid, network)
        .map(|hotkey| SecretVec::new(hotkey.secret_seed().to_vec()))
}

/// Derives the crate-owned voting hotkey for a wallet account in a round.
pub fn derive_voting_hotkey(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<zcash_voting::VotingHotkey, String> {
    zcash_voting::hotkey::derive_voting_hotkey(
        seed.expose_secret(),
        zcash_voting::hotkey::HotkeyDerivationContext {
            round_id,
            account_id: account_uuid,
        },
        voting_network(network),
    )
    .map_err(|e| format!("Voting hotkey derivation failed: {e}"))
}

/// Generates opaque voting hotkey bytes for hardware-account voting.
///
/// Hardware accounts do not expose wallet seed material to the app, so the
/// voting hotkey is random app-owned material that gets persisted in secure
/// storage and reused for the round.
///
/// # Errors
///
/// Returns an error if random hotkey material cannot be converted into the
/// voting hotkey format.
pub fn generate_random_hotkey(network: WalletNetwork) -> Result<SecretVec<u8>, String> {
    zcash_voting::hotkey::generate_random_voting_hotkey(voting_network(network))
        .map(|hotkey| SecretVec::new(hotkey.secret_seed().to_vec()))
        .map_err(|e| format!("Voting hotkey generation failed: {e}"))
}

/// Reconstructs the voting hotkey for an already-generated secret seed.
///
/// This supports hardware voting, where the app stores only the per-round
/// voting hotkey bytes and never has access to the Keystone account seed.
///
/// # Errors
///
/// Returns an error if `zcash_voting` rejects the stored hotkey seed material.
pub fn voting_hotkey_from_secret(
    hotkey_secret: &SecretVec<u8>,
    network: WalletNetwork,
) -> Result<zcash_voting::VotingHotkey, String> {
    zcash_voting::hotkey::voting_hotkey_from_seed(
        hotkey_secret.expose_secret(),
        voting_network(network),
    )
    .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const ACCOUNT_UUID: &str = "550e8400-e29b-41d4-a716-446655440000";
    const OTHER_ACCOUNT_UUID: &str = "550e8400-e29b-41d4-a716-446655440001";
    const ROUND_ID: &str = "round-1";
    const OTHER_ROUND_ID: &str = "round-2";

    fn test_seed() -> SecretVec<u8> {
        SecretVec::new(vec![0xAB; 64])
    }

    #[test]
    fn hotkey_determinism() {
        let seed = test_seed();
        let expected =
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap();

        for _ in 0..100 {
            assert_eq!(
                derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest)
                    .unwrap()
                    .expose_secret(),
                expected.expose_secret()
            );
        }
    }

    #[test]
    fn hotkey_round_independence() {
        let seed = test_seed();

        assert_ne!(
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest)
                .unwrap()
                .expose_secret(),
            derive_hotkey(&seed, OTHER_ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest)
                .unwrap()
                .expose_secret()
        );
    }

    #[test]
    fn hotkey_account_independence() {
        let seed = test_seed();

        assert_ne!(
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest)
                .unwrap()
                .expose_secret(),
            derive_hotkey(&seed, ROUND_ID, OTHER_ACCOUNT_UUID, WalletNetwork::Regtest)
                .unwrap()
                .expose_secret()
        );
    }

    #[test]
    fn random_hotkey_returns_storable_secret_bytes() {
        let first = generate_random_hotkey(WalletNetwork::Regtest).unwrap();
        let second = generate_random_hotkey(WalletNetwork::Regtest).unwrap();

        assert_eq!(first.expose_secret().len(), 64);
        assert_eq!(second.expose_secret().len(), 64);
        assert_ne!(first.expose_secret(), second.expose_secret());
    }

    #[test]
    fn stored_hotkey_seed_reconstructs_typed_hotkey() {
        let hotkey =
            derive_hotkey(&test_seed(), ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap();

        let reconstructed = voting_hotkey_from_secret(&hotkey, WalletNetwork::Regtest).unwrap();

        assert_eq!(reconstructed.secret_seed(), hotkey.expose_secret());
        assert_eq!(reconstructed.raw_orchard_address().len(), 43);
    }

    #[test]
    fn hotkey_raw_orchard_address_is_deterministic_and_address_sized() {
        let seed = test_seed();
        let first =
            derive_voting_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap();
        let second =
            derive_voting_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap();

        assert_eq!(first.raw_orchard_address(), second.raw_orchard_address());
        assert_eq!(first.raw_orchard_address().len(), 43);
    }

    #[test]
    fn hotkey_is_bound_to_network() {
        let seed = test_seed();
        let regtest = derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap();
        let mainnet = derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Main).unwrap();

        assert_ne!(regtest.expose_secret(), mainnet.expose_secret());
    }
}
