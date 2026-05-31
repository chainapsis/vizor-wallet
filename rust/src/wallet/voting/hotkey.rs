use blake2b_simd::Params;
use secrecy::{ExposeSecret, SecretVec};
use zeroize::Zeroizing;

use crate::wallet::network::WalletNetwork;
use crate::wallet::voting::network::voting_network;

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
    zcash_voting::hotkey::voting_hotkey_from_seed(
        hotkey_secret.expose_secret(),
        voting_network(network),
    )
    .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))?;
    Ok(hotkey_secret)
}

/// Wraps hotkey seed bytes and verifies they reconstruct for `network`.
///
/// Returns the seed as a `SecretVec` when it is accepted by `zcash_voting`.
///
/// # Errors
///
/// Returns an error if the seed bytes are not valid hotkey material for the
/// supplied voting network.
pub fn validated_hotkey_seed(
    hotkey_seed: Vec<u8>,
    network: zcash_voting::Network,
) -> Result<SecretVec<u8>, String> {
    let hotkey_secret = SecretVec::new(hotkey_seed);
    zcash_voting::hotkey::voting_hotkey_from_seed(hotkey_secret.expose_secret(), network)
        .map_err(|e| format!("Voting hotkey reconstruction failed: {e}"))?;
    Ok(hotkey_secret)
}

/// Derives deterministic, round-scoped hotkey seed material from wallet context.
///
/// The returned seed is bound to the wallet seed, round ID, account UUID, and
/// network. It is suitable only after reconstruction succeeds through
/// `validated_hotkey_seed` or the caller's equivalent validation.
///
/// # Errors
///
/// Returns an error if the wallet seed is too short or any context field cannot
/// be length-prefixed for domain-separated hashing.
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
