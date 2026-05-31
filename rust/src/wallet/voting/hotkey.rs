use blake2b_simd::Params;
use secrecy::{ExposeSecret, SecretVec};
use zeroize::Zeroizing;

use crate::api::voting::voting_network;
use crate::wallet::network::WalletNetwork;

const HOTKEY_CONTEXT_PREFIX: &[u8] = b"ZcashVotingHotkeyV1";
const HOTKEY_SEED_PERSONALIZATION: &[u8] = b"ZcashVotingHotKy";
const HOTKEY_SEED_LEN: usize = 64;

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
/// Returns an error when `seed` or the voting context cannot be converted into
/// scoped hotkey material.
pub fn derive_hotkey(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<SecretVec<u8>, String> {
    let hotkey_secret =
        derive_contextual_hotkey_seed(seed.expose_secret(), round_id, account_uuid, network)?;
    voting_hotkey_from_secret(&hotkey_secret, network)?;
    Ok(hotkey_secret)
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

fn derive_contextual_hotkey_seed(
    seed: &[u8],
    round_id: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<SecretVec<u8>, String> {
    if seed.len() < 32 {
        return Err(format!(
            "wallet seed must be at least 32 bytes, got {}",
            seed.len()
        ));
    }

    let mut material = Zeroizing::new(Vec::new());
    material.extend_from_slice(HOTKEY_CONTEXT_PREFIX);
    append_context_part(&mut material, seed)?;
    append_context_part(&mut material, round_id.as_bytes())?;
    append_context_part(&mut material, account_uuid.as_bytes())?;
    append_context_part(&mut material, network_tag(network))?;

    let hash = Params::new()
        .hash_length(HOTKEY_SEED_LEN)
        .personal(HOTKEY_SEED_PERSONALIZATION)
        .hash(&material);

    Ok(SecretVec::new(hash.as_bytes().to_vec()))
}

fn append_context_part(material: &mut Vec<u8>, part: &[u8]) -> Result<(), String> {
    let len = u32::try_from(part.len())
        .map_err(|_| "voting hotkey context part length exceeds u32::MAX".to_string())?;
    material.extend_from_slice(&len.to_be_bytes());
    material.extend_from_slice(part);
    Ok(())
}

fn network_tag(network: WalletNetwork) -> &'static [u8] {
    match network {
        WalletNetwork::Main => b"mainnet",
        WalletNetwork::Test => b"testnet",
        WalletNetwork::Regtest => b"regtest",
    }
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
        let first = voting_hotkey_from_secret(
            &derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap(),
            WalletNetwork::Regtest,
        )
        .unwrap();
        let second = voting_hotkey_from_secret(
            &derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap(),
            WalletNetwork::Regtest,
        )
        .unwrap();

        assert_eq!(first.raw_orchard_address(), second.raw_orchard_address());
        assert_eq!(first.raw_orchard_address().len(), 43);
    }

    #[test]
    fn local_hotkey_seed_matches_legacy_vector() {
        let seed = test_seed();
        let local = derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap();
        let expected = hex::decode(
            "20e3dada1183f1ef8c797348fd543c7e8f63d9f776ec84183f66845ee2a0b0ec\
             0a6efc9c803785bb8f07106428e71e1f65066e40052b15844813a1de82f65c7c",
        )
        .unwrap();

        assert_eq!(local.expose_secret(), expected.as_slice());
    }

    #[test]
    fn hotkey_is_bound_to_network() {
        let seed = test_seed();
        let regtest = derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Regtest).unwrap();
        let mainnet = derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID, WalletNetwork::Main).unwrap();

        assert_ne!(regtest.expose_secret(), mainnet.expose_secret());
    }
}
