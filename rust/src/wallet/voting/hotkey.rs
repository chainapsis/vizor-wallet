use secrecy::{ExposeSecret, SecretVec};
use zcash_keys::keys::UnifiedSpendingKey;
use zeroize::Zeroizing;
use zip32::Scope;

use crate::wallet::network::WalletNetwork;

const HOTKEY_CONTEXT_PREFIX: &[u8] = b"VizorWalletVotingHotkeyV1";

/// Derives opaque voting hotkey bytes for a wallet account in a voting round.
///
/// `seed` is the platform-owned secret seed material, while `round_id` and
/// `account_uuid` are UTF-8 context strings. The same tuple always returns the
/// same hotkey bytes; changing any tuple member produces independent material.
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
) -> Result<SecretVec<u8>, String> {
    generate_contextual_hotkey(seed, round_id, account_uuid)
        .map(|hotkey| SecretVec::new(hotkey.secret_key))
}

/// Derives the Orchard raw address used as the governance PCZT output target.
///
/// The address is deterministically derived from the contextual hotkey for
/// `seed`, `round_id`, `account_uuid`, and the requested wallet `network`.
/// The returned bytes are the raw Orchard address bytes expected by voting
/// transaction construction.
///
/// # Errors
///
/// Returns an error if hotkey derivation fails, the hotkey cannot be converted
/// into a Zcash spending key for `network`, or the resulting UFVK has no Orchard
/// receiver.
pub fn derive_hotkey_raw_orchard_address(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<Vec<u8>, String> {
    let hotkey = generate_contextual_hotkey(seed, round_id, account_uuid)?;
    let hotkey_secret = SecretVec::new(hotkey.secret_key);
    hotkey_raw_orchard_address_from_secret(&hotkey_secret, network)
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
pub fn generate_random_hotkey() -> Result<SecretVec<u8>, String> {
    use rand::RngCore;

    let mut seed = Zeroizing::new(vec![0u8; 64]);
    rand::rngs::OsRng.fill_bytes(&mut seed);
    zcash_voting::hotkey::generate_hotkey(&seed)
        .map(|hotkey| SecretVec::new(hotkey.secret_key))
        .map_err(|e| format!("Voting hotkey generation failed: {e}"))
}

/// Derives the Orchard raw address for an already-generated voting hotkey.
///
/// This supports hardware voting, where the app stores only the per-round
/// voting hotkey bytes and never has access to the Keystone account seed.
///
/// # Errors
///
/// Returns an error if the hotkey cannot be converted into a Zcash spending key
/// for `network`, or if the resulting UFVK has no Orchard receiver.
pub fn hotkey_raw_orchard_address_from_secret(
    hotkey_secret: &SecretVec<u8>,
    network: WalletNetwork,
) -> Result<Vec<u8>, String> {
    let address = {
        // `UnifiedSpendingKey` does not expose a zeroizing wrapper here, so keep
        // its lifetime limited to the address derivation scope.
        let usk = UnifiedSpendingKey::from_seed(
            &network,
            hotkey_secret.expose_secret(),
            zip32::AccountId::ZERO,
        )
        .map_err(|e| format!("Hotkey USK derivation failed: {e:?}"))?;
        let ufvk = usk.to_unified_full_viewing_key();
        let orchard_fvk = ufvk
            .orchard()
            .ok_or_else(|| "Hotkey UFVK has no Orchard component".to_string())?;
        orchard_fvk.address_at(0u32, Scope::External)
    };
    Ok(address.to_raw_address_bytes().to_vec())
}

fn generate_contextual_hotkey(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
) -> Result<zcash_voting::VotingHotkey, String> {
    let hotkey_seed = contextual_hotkey_seed(seed, round_id, account_uuid);
    zcash_voting::hotkey::generate_hotkey(&hotkey_seed)
        .map_err(|e| format!("Voting hotkey derivation failed: {e}"))
}

/// Builds deterministic, domain-separated seed material for `zcash_voting`.
///
/// The context prefix separates Vizor voting hotkeys from other seed uses.
/// Length-prefixing keeps the `(seed, round_id, account_uuid)` tuple
/// unambiguous even when adjacent parts contain overlapping byte sequences.
/// TODO: evaluate if we should move this to zcash_voting
/// https://linear.app/zcale/issue/ZCA-403/review-round-id-usage-in-generate-hotkey-api
fn contextual_hotkey_seed(
    seed: &SecretVec<u8>,
    round_id: &str,
    account_uuid: &str,
) -> Zeroizing<Vec<u8>> {
    let seed_bytes = seed.expose_secret();
    let round_bytes = round_id.as_bytes();
    let account_bytes = account_uuid.as_bytes();

    let mut material = Zeroizing::new(Vec::with_capacity(
        HOTKEY_CONTEXT_PREFIX.len()
            + encoded_part_len(seed_bytes)
            + encoded_part_len(round_bytes)
            + encoded_part_len(account_bytes),
    ));
    material.extend_from_slice(HOTKEY_CONTEXT_PREFIX);
    append_context_part(&mut material, seed_bytes);
    append_context_part(&mut material, round_bytes);
    append_context_part(&mut material, account_bytes);

    material
}

/// Returns the number of bytes needed to length-prefix and store a context part.
fn encoded_part_len(part: &[u8]) -> usize {
    std::mem::size_of::<u32>() + part.len()
}

/// Appends one length-prefixed context part to the hotkey seed material.
///
/// # Panics
///
/// Panics if `part.len()` exceeds `u32::MAX`; voting context strings and wallet
/// seed material are expected to be far below that bound.
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
                derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID)
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
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID)
                .unwrap()
                .expose_secret(),
            derive_hotkey(&seed, OTHER_ROUND_ID, ACCOUNT_UUID)
                .unwrap()
                .expose_secret()
        );
    }

    #[test]
    fn hotkey_account_independence() {
        let seed = test_seed();

        assert_ne!(
            derive_hotkey(&seed, ROUND_ID, ACCOUNT_UUID)
                .unwrap()
                .expose_secret(),
            derive_hotkey(&seed, ROUND_ID, OTHER_ACCOUNT_UUID)
                .unwrap()
                .expose_secret()
        );
    }

    #[test]
    fn random_hotkey_returns_storable_secret_bytes() {
        let first = generate_random_hotkey().unwrap();
        let second = generate_random_hotkey().unwrap();

        assert_eq!(first.expose_secret().len(), 32);
        assert_eq!(second.expose_secret().len(), 32);
        assert_ne!(first.expose_secret(), second.expose_secret());
    }

    #[test]
    fn raw_orchard_address_can_be_derived_from_stored_hotkey_secret() {
        let hotkey = derive_hotkey(&test_seed(), ROUND_ID, ACCOUNT_UUID).unwrap();

        let address =
            hotkey_raw_orchard_address_from_secret(&hotkey, WalletNetwork::Regtest).unwrap();

        assert!(!address.is_empty());
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
