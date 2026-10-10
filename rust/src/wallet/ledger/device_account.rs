//! Verify the connected seed/account before disclosing transaction fields.
//!
//! The expected key comes from the account's stored UFVK, at
//! `m/44'/coin_type'/account'/0/0`. This needs no new pairing metadata and no
//! viewing-key approval. It identifies account key material, not a physical
//! device serial number or authenticated hardware attestation.

use super::{apdu::ApduCommand, serializer::pack_derivation_path, signature_mismatch};

#[derive(Clone, Copy)]
pub(crate) struct DeviceAccountKey {
    pub account_index: u32,
    pub coin_type: u32,
    pub public_key: [u8; 33],
}

impl DeviceAccountKey {
    pub fn request(&self) -> Result<ApduCommand, String> {
        const HARDENED: u32 = 1 << 31;
        if self.account_index >= HARDENED || self.coin_type >= HARDENED {
            return Err("Ledger account and coin type must be below 2^31".into());
        }
        Ok(ApduCommand {
            cla: super::apdu::ZCASH_CLA,
            ins: 0x40,
            p1: 0, // No address review or status screen.
            p2: 0,
            data: pack_derivation_path(&[
                HARDENED | 44,
                HARDENED | self.coin_type,
                HARDENED | self.account_index,
                0,
                0,
            ])?,
        })
    }

    pub fn verify(&self, response: &[u8]) -> Result<(), String> {
        verify_public_key(&self.public_key, response)
    }
}

/// Decode `GET_WALLET_PUBLIC_KEY`: length, uncompressed public key, address
/// length/address, and 32-byte chain code. Never log or retain the address.
pub(crate) fn verify_public_key(expected: &[u8; 33], response: &[u8]) -> Result<(), String> {
    let malformed = || "Ledger account-key response is malformed".to_owned();
    if response.len() < 99 || response[0] != 65 {
        return Err(malformed());
    }
    let address_len = usize::from(response[66]);
    if response.len() != 67 + address_len + 32 || !response[67..67 + address_len].is_ascii() {
        return Err(malformed());
    }
    let public_key = secp256k1::PublicKey::from_slice(&response[1..66])
        .map_err(|_| malformed())?
        .serialize();
    if &public_key != expected {
        return Err(signature_mismatch(
            "Connect the Ledger that holds this account".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(seed: u8) -> secp256k1::PublicKey {
        secp256k1::PublicKey::from_secret_key(
            &secp256k1::Secp256k1::new(),
            &secp256k1::SecretKey::from_slice(&[seed; 32]).unwrap(),
        )
    }

    fn response(key: secp256k1::PublicKey) -> Vec<u8> {
        let mut bytes = vec![65];
        bytes.extend_from_slice(&key.serialize_uncompressed());
        bytes.push(3);
        bytes.extend_from_slice(b"t1x");
        bytes.extend_from_slice(&[0; 32]);
        bytes
    }

    #[test]
    fn account_probe_uses_the_selected_account_and_coin_type_without_review() {
        let command = DeviceAccountKey {
            account_index: 7,
            coin_type: 133,
            public_key: key(1).serialize(),
        }
        .request()
        .unwrap();
        assert_eq!((command.ins, command.p1, command.p2), (0x40, 0, 0));
        assert_eq!(
            command.data,
            hex::decode("058000002c80000085800000070000000000000000").unwrap()
        );
    }

    #[test]
    fn another_seed_is_rejected_without_exposing_either_key_in_the_error() {
        let expected = key(1).serialize();
        verify_public_key(&expected, &response(key(1))).unwrap();
        let error = verify_public_key(&expected, &response(key(2))).unwrap_err();
        assert!(error.starts_with("ledger_signature_mismatch:"));
        assert!(!error.contains(&hex::encode(expected)));
    }

    #[test]
    fn malformed_and_padded_key_responses_are_rejected() {
        let expected = key(1).serialize();
        let valid = response(key(1));
        for len in 0..valid.len() {
            assert!(verify_public_key(&expected, &valid[..len]).is_err());
        }
        let mut padded = valid.clone();
        padded.push(0);
        assert!(verify_public_key(&expected, &padded).is_err());
        let mut invalid_point = valid;
        invalid_point[1..66].fill(0);
        assert!(verify_public_key(&expected, &invalid_point).is_err());
    }
}
