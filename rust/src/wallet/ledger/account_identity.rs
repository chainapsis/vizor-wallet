//! Compare an approved Ledger export with a stored account without losing keys.

use zcash_address::unified::{Container, Encoding, Fvk, Ufvk};
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_protocol::consensus::NetworkType;

/// Ledger exports Orchard and transparent keys. A stored account can additionally
/// hold Sapling material that the device cannot export. Permit only that omission;
/// every other item (including unknown items) must match in full.
pub(crate) fn viewing_keys_match(expected: &str, exported: &str) -> Result<bool, String> {
    let decode = |encoded: &str| {
        // Decoder errors can contain key bytes. Return no key material to callers.
        let invalid = || "Invalid Ledger account viewing key".to_owned();
        let (network, key) = Ufvk::decode(encoded).map_err(|_| invalid())?;
        if network != NetworkType::Main {
            return Err(invalid());
        }
        UnifiedFullViewingKey::parse(&key).map_err(|_| invalid())?;
        Ok(key.items())
    };
    let mut expected = decode(expected)?;
    let exported = decode(exported)?;
    for items in [&expected, &exported] {
        if !items.iter().any(|item| matches!(item, Fvk::Orchard(_)))
            || !items.iter().any(|item| matches!(item, Fvk::P2pkh(_)))
        {
            return Ok(false);
        }
    }
    if !exported.iter().any(|item| matches!(item, Fvk::Sapling(_))) {
        expected.retain(|item| !matches!(item, Fvk::Sapling(_)));
    }
    Ok(expected == exported)
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_keys::keys::UnifiedSpendingKey;
    use zcash_protocol::consensus::MAIN_NETWORK;

    fn full(seed: u8, index: u32) -> Vec<Fvk> {
        let key = UnifiedSpendingKey::from_seed(
            &MAIN_NETWORK,
            &[seed; 32],
            zip32::AccountId::try_from(index).unwrap(),
        )
        .unwrap()
        .to_unified_full_viewing_key()
        .encode(&MAIN_NETWORK);
        Ufvk::decode(&key).unwrap().1.items()
    }

    fn ledger(items: &[Fvk]) -> Vec<Fvk> {
        items
            .iter()
            .filter(|item| !matches!(item, Fvk::Sapling(_)))
            .cloned()
            .collect()
    }

    fn encode(items: Vec<Fvk>) -> String {
        Ufvk::try_from_items(items)
            .unwrap()
            .encode(&NetworkType::Main)
    }

    #[test]
    fn stored_sapling_is_optional_only_in_the_device_export() {
        let stored = full(1, 0);
        let device = ledger(&stored);
        for (expected, exported) in [
            (stored.clone(), stored.clone()),
            (device.clone(), device.clone()),
            (stored.clone(), device.clone()),
        ] {
            assert!(viewing_keys_match(&encode(expected), &encode(exported)).unwrap());
        }
        assert!(!viewing_keys_match(&encode(device), &encode(stored)).unwrap());
    }

    #[test]
    fn another_seed_or_account_is_rejected() {
        let stored = encode(full(1, 0));
        for other in [full(2, 0), full(1, 1)] {
            assert!(!viewing_keys_match(&stored, &encode(ledger(&other))).unwrap());
        }
    }

    #[test]
    fn each_required_component_must_match_independently() {
        let stored = full(1, 0);
        let other = ledger(&full(2, 0));
        for replace_orchard in [true, false] {
            let mut device = ledger(&stored);
            for item in &mut device {
                if matches!(item, Fvk::Orchard(_)) && replace_orchard
                    || matches!(item, Fvk::P2pkh(_)) && !replace_orchard
                {
                    *item = other
                        .iter()
                        .find(|candidate| {
                            std::mem::discriminant(*candidate) == std::mem::discriminant(item)
                        })
                        .unwrap()
                        .clone();
                }
            }
            assert!(!viewing_keys_match(&encode(stored.clone()), &encode(device)).unwrap());
        }
    }

    #[test]
    fn missing_required_components_never_match_even_identical_keys() {
        let full = full(1, 0);
        for items in [
            full.iter()
                .filter(|i| !matches!(i, Fvk::P2pkh(_)))
                .cloned()
                .collect(),
            full.iter()
                .filter(|i| !matches!(i, Fvk::Orchard(_)))
                .cloned()
                .collect(),
        ] {
            let incomplete = encode(items);
            assert!(!viewing_keys_match(&incomplete, &incomplete).unwrap());
        }
    }

    #[test]
    fn sapling_must_match_when_both_keys_include_it() {
        let stored = full(1, 0);
        let mut device = ledger(&stored);
        device.extend(
            full(2, 0)
                .into_iter()
                .filter(|i| matches!(i, Fvk::Sapling(_))),
        );
        assert!(!viewing_keys_match(&encode(stored), &encode(device)).unwrap());
    }

    #[test]
    fn unknown_components_are_preserved_and_compared() {
        let mut stored = full(1, 0);
        stored.push(Fvk::Unknown {
            typecode: 0xff,
            data: vec![42; 32],
        });
        let device = ledger(&stored);
        assert!(viewing_keys_match(&encode(stored.clone()), &encode(device.clone())).unwrap());
        let mut changed = device.clone();
        changed.retain(|i| !matches!(i, Fvk::Unknown { .. }));
        assert!(!viewing_keys_match(&encode(stored.clone()), &encode(changed.clone())).unwrap());
        assert!(!viewing_keys_match(&encode(changed), &encode(device.clone())).unwrap());
        *stored.last_mut().unwrap() = Fvk::Unknown {
            typecode: 0xff,
            data: vec![43; 32],
        };
        assert!(!viewing_keys_match(&encode(stored), &encode(device)).unwrap());
    }

    #[test]
    fn malformed_wrong_network_and_invalid_key_material_fail_without_key_disclosure() {
        let items = ledger(&full(1, 0));
        let valid = encode(items.clone());
        let testnet = Ufvk::try_from_items(items.clone())
            .unwrap()
            .encode(&NetworkType::Test);
        let mut corrupt = items.clone();
        for item in &mut corrupt {
            if matches!(item, Fvk::P2pkh(_)) {
                *item = Fvk::P2pkh([0; 65]);
            }
        }
        let mut invalid_orchard = items;
        for item in &mut invalid_orchard {
            if matches!(item, Fvk::Orchard(_)) {
                *item = Fvk::Orchard([0xff; 96]);
            }
        }
        let mut bad_checksum = valid.clone();
        bad_checksum.pop();
        bad_checksum.push(if valid.ends_with('q') { 'p' } else { 'q' });
        for invalid in [
            String::new(),
            "uview-broken".into(),
            testnet,
            encode(corrupt),
            encode(invalid_orchard),
            bad_checksum,
        ] {
            for (a, b) in [(&valid, &invalid), (&invalid, &valid), (&invalid, &invalid)] {
                assert_eq!(
                    viewing_keys_match(a, b).unwrap_err(),
                    "Invalid Ledger account viewing key"
                );
            }
        }
    }
}
