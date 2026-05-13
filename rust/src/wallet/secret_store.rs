use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use pbkdf2::pbkdf2_hmac;
use secrecy::SecretVec;
use serde::Deserialize;
use sha2::Sha256;
use zeroize::Zeroizing;

use crate::wallet::{keys, network::WalletNetwork};

const SECURE_STORE_SALT_KEY: &str = "zcash_secure_store_salt";
const ACCOUNT_MNEMONIC_KEY_PREFIX: &str = "zcash_account_mnemonic_";
const KDF_ITERATIONS: u32 = 100_000;

#[derive(Debug, Deserialize)]
struct EncryptedPayload<'a> {
    #[serde(rename = "v")]
    version: u8,
    #[serde(rename = "n", borrow)]
    nonce: &'a str,
    #[serde(rename = "c", borrow)]
    cipher_text: &'a str,
    #[serde(rename = "m", borrow)]
    mac: &'a str,
}

pub fn seed_from_macos_stored_mnemonic(
    network: WalletNetwork,
    account_uuid: &str,
    password: Zeroizing<Vec<u8>>,
) -> Result<SecretVec<u8>, String> {
    let account_key = account_mnemonic_key(account_uuid);
    let salt_raw = macos_read_secure_store_value(
        &secure_store_service_for_network(network),
        SECURE_STORE_SALT_KEY,
    )?
    .ok_or_else(|| "Secure storage salt not found".to_string())?;
    let payload_raw =
        macos_read_secure_store_value(&mnemonic_store_service_for_network(network), &account_key)?
            .ok_or_else(|| "Mnemonic not found for account".to_string())?;

    let salt = decode_base64(salt_raw.as_slice(), "secure storage salt")?;
    drop(salt_raw);
    let mnemonic_bytes =
        decrypt_payload(payload_raw.as_slice(), password.as_slice(), salt.as_slice())?;
    drop(password);
    drop(salt);
    drop(payload_raw);
    keys::mnemonic_bytes_to_seed(mnemonic_bytes.as_slice())
}

fn decrypt_payload(
    raw_payload: &[u8],
    password: &[u8],
    salt: &[u8],
) -> Result<Zeroizing<Vec<u8>>, String> {
    let payload: EncryptedPayload<'_> = serde_json::from_slice(raw_payload)
        .map_err(|e| format!("Failed to parse encrypted payload: {e}"))?;
    if payload.version != 1 {
        return Err(format!(
            "Unsupported encrypted payload version: {}",
            payload.version
        ));
    }

    let nonce = decode_base64(payload.nonce.as_bytes(), "encrypted payload nonce")?;
    if nonce.len() != 12 {
        return Err(format!(
            "Invalid encrypted payload nonce length: {}",
            nonce.len()
        ));
    }
    let cipher_text = decode_base64(
        payload.cipher_text.as_bytes(),
        "encrypted payload cipher text",
    )?;
    let mac = decode_base64(payload.mac.as_bytes(), "encrypted payload mac")?;
    if mac.len() != 16 {
        return Err(format!(
            "Invalid encrypted payload mac length: {}",
            mac.len()
        ));
    }

    let mut key = Zeroizing::new([0u8; 32]);
    pbkdf2_hmac::<Sha256>(password, salt, KDF_ITERATIONS, key.as_mut());

    let cipher = Aes256Gcm::new_from_slice(key.as_slice())
        .map_err(|e| format!("Failed to initialize AES-GCM: {e}"))?;
    let mut ciphertext_and_tag = Zeroizing::new(Vec::with_capacity(cipher_text.len() + mac.len()));
    ciphertext_and_tag.extend_from_slice(cipher_text.as_slice());
    ciphertext_and_tag.extend_from_slice(mac.as_slice());

    let clear_text = cipher
        .decrypt(
            Nonce::from_slice(nonce.as_slice()),
            ciphertext_and_tag.as_slice(),
        )
        .map_err(|_| "Failed to decrypt secure-storage payload".to_string())?;
    Ok(Zeroizing::new(clear_text))
}

fn decode_base64(input: &[u8], label: &str) -> Result<Zeroizing<Vec<u8>>, String> {
    STANDARD
        .decode(input)
        .map(Zeroizing::new)
        .map_err(|e| format!("Failed to decode {label}: {e}"))
}

fn secure_store_service_for_network(network: WalletNetwork) -> String {
    match network {
        WalletNetwork::Main => "com.keplr.vizor.secure_store".to_string(),
        WalletNetwork::Test => "com.keplr.vizor.test.secure_store".to_string(),
        WalletNetwork::Regtest => "com.keplr.vizor.regtest.secure_store".to_string(),
    }
}

fn mnemonic_store_service_for_network(network: WalletNetwork) -> String {
    format!("{}.mnemonic", secure_store_service_for_network(network))
}

fn account_mnemonic_key(account_uuid: &str) -> String {
    format!("{ACCOUNT_MNEMONIC_KEY_PREFIX}{account_uuid}")
}

#[cfg(target_os = "macos")]
fn macos_read_secure_store_value(
    service: &str,
    key: &str,
) -> Result<Option<Zeroizing<Vec<u8>>>, String> {
    use security_framework::item::{ItemClass, ItemSearchOptions, SearchResult};

    const ERR_SEC_ITEM_NOT_FOUND: i32 = -25300;

    let mut search = ItemSearchOptions::new();
    search
        .class(ItemClass::generic_password())
        .service(service)
        .account(key)
        .ignore_legacy_keychains()
        .load_data(true);

    match search.search() {
        Ok(results) => {
            if results.is_empty() {
                return Ok(None);
            }
            match results.into_iter().next() {
                Some(SearchResult::Data(data)) => Ok(Some(Zeroizing::new(data))),
                Some(other) => Err(format!(
                    "Unexpected keychain search result for service={service} key={key}: {other:?}"
                )),
                None => Ok(None),
            }
        }
        Err(error) if error.code() == ERR_SEC_ITEM_NOT_FOUND => Ok(None),
        Err(error) => Err(format!(
            "Keychain read failed for service={service} key={key}: {error}"
        )),
    }
}

#[cfg(not(target_os = "macos"))]
fn macos_read_secure_store_value(
    _service: &str,
    _key: &str,
) -> Result<Option<Zeroizing<Vec<u8>>>, String> {
    Err("macOS stored mnemonic path is unsupported on this platform".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use aes_gcm::aead::{Aead, AeadCore, OsRng};

    fn encrypted_payload_json(password: &[u8], salt: &[u8], clear_text: &[u8]) -> String {
        let mut key = [0u8; 32];
        pbkdf2_hmac::<Sha256>(password, salt, KDF_ITERATIONS, &mut key);
        let cipher = Aes256Gcm::new_from_slice(&key).unwrap();
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        let cipher_text_and_tag = cipher.encrypt(&nonce, clear_text).unwrap();
        let split_at = cipher_text_and_tag.len() - 16;
        let (cipher_text, mac) = cipher_text_and_tag.split_at(split_at);

        serde_json::json!({
            "v": 1,
            "n": STANDARD.encode(nonce),
            "c": STANDARD.encode(cipher_text),
            "m": STANDARD.encode(mac),
        })
        .to_string()
    }

    #[test]
    fn decrypt_payload_round_trips_flutter_secure_storage_format() {
        let password = b"correct horse battery staple";
        let salt = b"0123456789abcdef";
        let mnemonic = b"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let payload = encrypted_payload_json(password, salt, mnemonic);

        let clear = decrypt_payload(payload.as_bytes(), password, salt).unwrap();

        assert_eq!(clear.as_slice(), mnemonic);
    }

    #[test]
    fn decrypt_payload_rejects_wrong_password() {
        let salt = b"0123456789abcdef";
        let payload = encrypted_payload_json(b"good password", salt, b"secret");

        let error = decrypt_payload(payload.as_bytes(), b"bad password", salt).unwrap_err();

        assert!(error.contains("Failed to decrypt"));
    }
}
