use secrecy::{ExposeSecret, SecretVec};

const HOTKEY_CONTEXT_PREFIX: &[u8] = b"VizorWalletVotingHotkeyV1";

/// Derives opaque voting hotkey bytes for a single wallet account and voting round.
///
/// The caller supplies the platform-owned secret seed; Rust only derives and returns
/// the hotkey bytes and does not persist them.
pub fn derive_hotkey(seed: &SecretVec<u8>, round_id: &str, account_uuid: &str) -> Vec<u8> {
    let hotkey_seed = contextual_hotkey_seed(seed, round_id, account_uuid);
    zcash_voting::hotkey::generate_hotkey(hotkey_seed.expose_secret())
        .expect("contextual voting hotkey seed must be valid")
        .secret_key
}

/// Returns the secure-storage key used by Dart for a round/account hotkey.
pub fn hotkey_storage_key(account_uuid: &str, round_id: &str) -> String {
    format!("zcash_account_voting_hotkey_{account_uuid}_{round_id}")
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
        let expected = derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID);

        for _ in 0..100 {
            assert_eq!(derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID), expected);
        }
    }

    #[test]
    fn hotkey_round_independence() {
        let seed = test_seed();

        assert_ne!(
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID),
            derive_hotkey(&seed, OTHER_ROUND_ID, ACCOUNT_UUID)
        );
    }

    #[test]
    fn hotkey_account_independence() {
        let seed = test_seed();

        assert_ne!(
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID),
            derive_hotkey(&seed, ROUND_ID, OTHER_ACCOUNT_UUID)
        );
    }

    #[test]
    fn hotkey_storage_key_format() {
        assert_eq!(
            hotkey_storage_key(ACCOUNT_UUID, ROUND_ID),
            "zcash_account_voting_hotkey_550e8400-e29b-41d4-a716-446655440000_round-1"
        );
    }
}
