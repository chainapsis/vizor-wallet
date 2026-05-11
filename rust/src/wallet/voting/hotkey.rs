use secrecy::{ExposeSecret, SecretVec};
use zcash_keys::keys::UnifiedSpendingKey;
use zip32::Scope;

use crate::wallet::network::WalletNetwork;

const HOTKEY_CONTEXT_PREFIX: &[u8] = b"VizorWalletVotingHotkeyV1";

/// Derives opaque voting hotkey bytes for a single wallet account and voting round.
///
/// The caller supplies the platform-owned secret seed; Rust only derives and returns
/// the hotkey bytes and does not persist them.
pub fn derive_hotkey(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
) -> Result<Vec<u8>, String> {
    generate_contextual_hotkey(seed, round_id, account_uuid).map(|hotkey| hotkey.secret_key)
}

/// Derives the Orchard raw address used as the governance PCZT output target.
pub fn derive_hotkey_raw_orchard_address(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<Vec<u8>, String> {
    let hotkey = generate_contextual_hotkey(seed, round_id, account_uuid)?;
    let usk = UnifiedSpendingKey::from_seed(&network, &hotkey.secret_key, zip32::AccountId::ZERO)
        .map_err(|e| format!("Hotkey USK derivation failed: {e:?}"))?;
    let ufvk = usk.to_unified_full_viewing_key();
    let orchard_fvk = ufvk
        .orchard()
        .ok_or_else(|| "Hotkey UFVK has no Orchard component".to_string())?;
    let address = orchard_fvk.address_at(0u32, Scope::External);
    Ok(address.to_raw_address_bytes().to_vec())
}

fn generate_contextual_hotkey(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
) -> Result<zcash_voting::VotingHotkey, String> {
    let hotkey_seed = contextual_hotkey_seed(seed, round_id, account_uuid);
    zcash_voting::hotkey::generate_hotkey(hotkey_seed.expose_secret())
        .map_err(|e| format!("Voting hotkey derivation failed: {e}"))
}

/// Builds the deterministic seed material passed to `zcash_voting`.
///
/// Length-prefixing keeps the `(seed, round_id, account_uuid)` tuple unambiguous.
/// TODO: evaluate if we should move this to zcash_voting
/// https://linear.app/zcale/issue/ZCA-403/review-round-id-usage-in-generate-hotkey-api
fn contextual_hotkey_seed(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
) -> SecretVec<u8> {
    let seed_bytes = seed.expose_secret();
    let round_bytes = round_id.as_bytes();
    let account_bytes = account_uuid.as_bytes();

    let mut material = Vec::with_capacity(
        HOTKEY_CONTEXT_PREFIX.len()
            + encoded_part_len(seed_bytes)
            + encoded_part_len(round_bytes)
            + encoded_part_len(account_bytes),
    );
    material.extend_from_slice(HOTKEY_CONTEXT_PREFIX);
    append_context_part(&mut material, seed_bytes);
    append_context_part(&mut material, round_bytes);
    append_context_part(&mut material, account_bytes);

    SecretVec::new(material)
}

/// Returns the number of bytes needed to encode a context part.
fn encoded_part_len(part: &[u8]) -> usize {
    std::mem::size_of::<u32>() + part.len()
}

/// Appends one length-prefixed context part to the hotkey seed material.
fn append_context_part(material: &mut Vec<u8>, part: &[u8]) {
    let len = u32::try_from(part.len()).expect("voting hotkey context part must fit in u32");
    material.extend_from_slice(&len.to_be_bytes());
    material.extend_from_slice(part);
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
        let expected = derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID).unwrap();

        for _ in 0..100 {
            assert_eq!(
                derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID).unwrap(),
                expected
            );
        }
    }

    #[test]
    fn hotkey_round_independence() {
        let seed = test_seed();

        assert_ne!(
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID).unwrap(),
            derive_hotkey(&seed, OTHER_ROUND_ID, ACCOUNT_UUID).unwrap()
        );
    }

    #[test]
    fn hotkey_account_independence() {
        let seed = test_seed();

        assert_ne!(
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID).unwrap(),
            derive_hotkey(&seed, ROUND_ID, OTHER_ACCOUNT_UUID).unwrap()
        );
    }

    #[test]
    fn hotkey_raw_orchard_address_is_deterministic_and_address_sized() {
        let seed = test_seed();
        let first = derive_hotkey_raw_orchard_address(
            &seed,
            ROUND_ID,
            ACCOUNT_UUID,
            WalletNetwork::Regtest,
        )
        .unwrap();
        let second = derive_hotkey_raw_orchard_address(
            &seed,
            ROUND_ID,
            ACCOUNT_UUID,
            WalletNetwork::Regtest,
        )
        .unwrap();

        assert_eq!(first, second);
        assert_eq!(first.len(), 43);
    }
}
