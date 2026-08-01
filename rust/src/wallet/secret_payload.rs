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

/// A payload key derived once for one `(password, salt)` pair.
///
/// [`derive_key`] runs `KDF_ITERATIONS` PBKDF2-HMAC-SHA256 iterations, which
/// measures ~27ms per derivation on an M-series Mac in release. Loops handling
/// one payload per row re-derived the same key on every iteration; build this
/// once outside the loop instead.
///
/// Deliberately not a process-wide cache. The key lives exactly as long as the
/// call that needs it, so this does not widen the window in which key material
/// is resident relative to the password the caller already holds.
pub struct PayloadKey {
    key: Zeroizing<[u8; KEY_LEN]>,
}

impl PayloadKey {
    pub fn new(password: &[u8], salt: &[u8]) -> Self {
        Self {
            key: derive_key(password, salt),
        }
    }

    fn cipher(&self) -> Result<Aes256Gcm, String> {
        Aes256Gcm::new_from_slice(self.key.as_slice())
            .map_err(|e| format!("Failed to initialize AES-GCM: {e}"))
    }

    pub fn encrypt(&self, clear_text: Zeroizing<Vec<u8>>) -> Result<String, String> {
        encrypt_with_cipher(self.cipher()?, clear_text)
    }

    pub fn decrypt(&self, raw_payload: &[u8]) -> Result<Zeroizing<Vec<u8>>, String> {
        decrypt_with_cipher(self.cipher()?, raw_payload)
    }
}

pub fn encrypt_payload(
    clear_text: Zeroizing<Vec<u8>>,
    password: &[u8],
    salt: &[u8],
) -> Result<String, String> {
    PayloadKey::new(password, salt).encrypt(clear_text)
}

fn encrypt_with_cipher(
    cipher: Aes256Gcm,
    clear_text: Zeroizing<Vec<u8>>,
) -> Result<String, String> {
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
    PayloadKey::new(password, salt).decrypt(raw_payload)
}

fn decrypt_with_cipher(
    cipher: Aes256Gcm,
    raw_payload: &[u8],
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

    const BENCH_PASSWORD: &[u8] = b"correct horse battery staple";
    const BENCH_SALT: [u8; 16] = [7u8; 16];

    /// A `PayloadKey` and the free functions must be interchangeable, so
    /// converting a loop cannot change what it reads or writes.
    #[test]
    fn payload_key_matches_the_free_functions() {
        let clear = Zeroizing::new(b"migration payload".to_vec());
        let key = PayloadKey::new(BENCH_PASSWORD, &BENCH_SALT);

        // Written by the loop helper, read by the free function.
        let via_key = key.encrypt(clear.clone()).unwrap();
        let back = decrypt_payload(via_key.as_bytes(), BENCH_PASSWORD, &BENCH_SALT).unwrap();
        assert_eq!(back.as_slice(), clear.as_slice());

        // Written by the free function, read by the loop helper.
        let via_free = encrypt_payload(clear.clone(), BENCH_PASSWORD, &BENCH_SALT).unwrap();
        let back = key.decrypt(via_free.as_bytes()).unwrap();
        assert_eq!(back.as_slice(), clear.as_slice());
    }

    #[test]
    fn payload_key_rejects_a_wrong_password() {
        let clear = Zeroizing::new(b"migration payload".to_vec());
        let sealed = encrypt_payload(clear, BENCH_PASSWORD, &BENCH_SALT).unwrap();

        let wrong = PayloadKey::new(b"not the password", &BENCH_SALT);

        assert!(wrong.decrypt(sealed.as_bytes()).is_err());
    }

    /// Cost of one migration read that decrypts a payload per row.
    ///
    /// Run with:
    /// `cargo test --release -p zcash_wallet kdf_reuse -- --ignored --nocapture`
    #[test]
    #[ignore = "timing benchmark; run explicitly"]
    fn kdf_reuse_benchmark() {
        use std::time::Instant;

        // `denomination_stages_for_run` decrypts three payloads per stage.
        const ROWS: usize = 20;
        const PER_ROW: usize = 3;

        let clear = Zeroizing::new(vec![0x5au8; 512]);
        let sealed = encrypt_payload(clear, BENCH_PASSWORD, &BENCH_SALT).unwrap();

        let started = Instant::now();
        for _ in 0..ROWS * PER_ROW {
            decrypt_payload(sealed.as_bytes(), BENCH_PASSWORD, &BENCH_SALT).unwrap();
        }
        let per_call = started.elapsed();

        let started = Instant::now();
        let key = PayloadKey::new(BENCH_PASSWORD, &BENCH_SALT);
        for _ in 0..ROWS * PER_ROW {
            key.decrypt(sealed.as_bytes()).unwrap();
        }
        let derived_once = started.elapsed();

        println!(
            "kdf: {ROWS} rows x {PER_ROW} payloads ({} derivations -> 1)",
            ROWS * PER_ROW
        );
        println!("  per-call derivation : {per_call:?}");
        println!("  derived once        : {derived_once:?}");
        println!(
            "  saved               : {:?} ({:.1}x)",
            per_call.saturating_sub(derived_once),
            per_call.as_secs_f64() / derived_once.as_secs_f64().max(f64::MIN_POSITIVE),
        );
        assert!(derived_once < per_call);
    }

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
