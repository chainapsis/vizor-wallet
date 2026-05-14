use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use pbkdf2::pbkdf2_hmac;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use zeroize::Zeroizing;

const KDF_ITERATIONS: u32 = 100_000;
const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const MAC_LEN: usize = 16;

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

#[derive(Serialize)]
struct EncryptedPayloadOwned {
    #[serde(rename = "v")]
    version: u8,
    #[serde(rename = "n")]
    nonce: String,
    #[serde(rename = "c")]
    cipher_text: String,
    #[serde(rename = "m")]
    mac: String,
}

pub fn encrypt_payload_with_base64_salt(
    clear_text: Zeroizing<Vec<u8>>,
    password: Zeroizing<Vec<u8>>,
    salt_base64: &str,
) -> Result<String, String> {
    let salt = decode_base64(salt_base64.as_bytes(), "secure storage salt")?;
    encrypt_payload(clear_text, password.as_slice(), salt.as_slice())
}

pub fn decrypt_payload_with_base64_salt(
    raw_payload: &[u8],
    password: Zeroizing<Vec<u8>>,
    salt_base64: &str,
) -> Result<Zeroizing<Vec<u8>>, String> {
    let salt = decode_base64(salt_base64.as_bytes(), "secure storage salt")?;
    decrypt_payload(raw_payload, password.as_slice(), salt.as_slice())
}

pub fn derive_password_verifier_base64(
    password: Zeroizing<Vec<u8>>,
    salt_base64: &str,
) -> Result<String, String> {
    let salt = decode_base64(salt_base64.as_bytes(), "password verifier salt")?;
    let key = derive_key(password.as_slice(), salt.as_slice());
    Ok(STANDARD.encode(key.as_slice()))
}

pub fn encrypt_payload(
    clear_text: Zeroizing<Vec<u8>>,
    password: &[u8],
    salt: &[u8],
) -> Result<String, String> {
    let key = derive_key(password, salt);
    let cipher = Aes256Gcm::new_from_slice(key.as_slice())
        .map_err(|e| format!("Failed to initialize AES-GCM: {e}"))?;
    drop(key);
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
    let cipher_text_and_tag = Zeroizing::new(
        cipher
            .encrypt(&nonce, clear_text.as_slice())
            .map_err(|_| "Failed to encrypt secure-storage payload".to_string())?,
    );
    drop(cipher);
    drop(clear_text);
    if cipher_text_and_tag.len() < MAC_LEN {
        return Err("Encrypted payload is shorter than AES-GCM tag".to_string());
    }

    let split_at = cipher_text_and_tag.len() - MAC_LEN;
    let (cipher_text, mac) = cipher_text_and_tag.split_at(split_at);
    let payload = EncryptedPayloadOwned {
        version: 1,
        nonce: STANDARD.encode(nonce.as_slice()),
        cipher_text: STANDARD.encode(cipher_text),
        mac: STANDARD.encode(mac),
    };
    drop(cipher_text_and_tag);
    serde_json::to_string(&payload)
        .map_err(|e| format!("Failed to serialize encrypted payload: {e}"))
}

pub fn decrypt_payload(
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
    if nonce.len() != NONCE_LEN {
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
    if mac.len() != MAC_LEN {
        return Err(format!(
            "Invalid encrypted payload mac length: {}",
            mac.len()
        ));
    }

    let key = derive_key(password, salt);
    let cipher = Aes256Gcm::new_from_slice(key.as_slice())
        .map_err(|e| format!("Failed to initialize AES-GCM: {e}"))?;
    drop(key);
    let mut ciphertext_and_tag = Zeroizing::new(Vec::with_capacity(cipher_text.len() + mac.len()));
    ciphertext_and_tag.extend_from_slice(cipher_text.as_slice());
    ciphertext_and_tag.extend_from_slice(mac.as_slice());

    let clear_text = cipher
        .decrypt(
            Nonce::from_slice(nonce.as_slice()),
            ciphertext_and_tag.as_slice(),
        )
        .map_err(|_| "Failed to decrypt secure-storage payload".to_string())?;
    drop(cipher);
    drop(ciphertext_and_tag);
    drop(cipher_text);
    drop(mac);
    drop(nonce);
    Ok(Zeroizing::new(clear_text))
}

pub fn decode_base64(input: &[u8], label: &str) -> Result<Zeroizing<Vec<u8>>, String> {
    STANDARD
        .decode(input)
        .map(Zeroizing::new)
        .map_err(|e| format!("Failed to decode {label}: {e}"))
}

fn derive_key(password: &[u8], salt: &[u8]) -> Zeroizing<[u8; KEY_LEN]> {
    let mut key = Zeroizing::new([0u8; KEY_LEN]);
    pbkdf2_hmac::<Sha256>(password, salt, KDF_ITERATIONS, key.as_mut());
    key
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decrypt_payload_accepts_dart_generated_fixture() {
        const PASSWORD: &[u8] = b"correct horse battery staple";
        const SALT_BASE64: &str = "AQIDBAUGBwgJCgsMDQ4PEA==";
        const MNEMONIC: &[u8] = b"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        const PAYLOAD: &str = r#"{"v":1,"n":"ERITFBUWFxgZGhsc","c":"J72zWbdISI5fRMoTmiYhHCtXt7xdqwJ4zQfwMp693QwRSwsMX3ooQibazT49sdYPzjV5+7B7cbwvGPH0AKbAkK+5mjoFbPxziTpqUNC1VMacrlnDyB7wY4k7Iwqh","m":"Wnf1YadalnPgYjiH0MyJlg=="}"#;

        let salt = STANDARD.decode(SALT_BASE64).unwrap();
        let clear = decrypt_payload(PAYLOAD.as_bytes(), PASSWORD, salt.as_slice()).unwrap();

        assert_eq!(clear.as_slice(), MNEMONIC);
    }

    #[test]
    fn encrypt_and_decrypt_payload_round_trips() {
        let password = Zeroizing::new(b"correct horse battery staple".to_vec());
        let salt = b"0123456789abcdef";
        let mnemonic = b"abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

        let payload =
            encrypt_payload(Zeroizing::new(mnemonic.to_vec()), password.as_slice(), salt).unwrap();
        let clear = decrypt_payload(payload.as_bytes(), password.as_slice(), salt).unwrap();

        assert_eq!(clear.as_slice(), mnemonic);
    }

    #[test]
    fn decrypt_payload_rejects_wrong_password() {
        let salt = b"0123456789abcdef";
        let payload =
            encrypt_payload(Zeroizing::new(b"secret".to_vec()), b"good password", salt).unwrap();

        let error = decrypt_payload(payload.as_bytes(), b"bad password", salt).unwrap_err();

        assert!(error.contains("Failed to decrypt"));
    }

    #[test]
    fn derive_password_verifier_matches_dart_fixture() {
        let verifier = derive_password_verifier_base64(
            Zeroizing::new(b"correct horse battery staple".to_vec()),
            "AQIDBAUGBwgJCgsMDQ4PEA==",
        )
        .unwrap();

        assert_eq!(verifier, "ftOFRW9rEf44G4LTTpOER237yEdk9NMG/2LcdIRmFaQ=");
    }
}
