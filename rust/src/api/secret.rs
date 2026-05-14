use std::panic;

use zeroize::Zeroizing;

use crate::wallet::secret_payload;

fn catch<T>(f: impl FnOnce() -> Result<T, String> + panic::UnwindSafe) -> Result<T, String> {
    match panic::catch_unwind(f) {
        Ok(result) => result,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "Unknown panic".to_string()
            };
            Err(format!("Rust panic: {msg}"))
        }
    }
}

/// Encrypt bytes into the app secure-storage payload format.
pub fn encrypt_secret_payload(
    plain_bytes: Vec<u8>,
    password: String,
    salt_base64: String,
) -> Result<String, String> {
    catch(|| {
        secret_payload::encrypt_payload_with_base64_salt(
            Zeroizing::new(plain_bytes),
            Zeroizing::new(password.into_bytes()),
            &salt_base64,
        )
    })
}

/// Decrypt the app secure-storage payload format into plaintext bytes.
pub fn decrypt_secret_payload(
    payload_json: String,
    password: String,
    salt_base64: String,
) -> Result<Vec<u8>, String> {
    catch(|| {
        let clear_text = secret_payload::decrypt_payload_with_base64_salt(
            payload_json.as_bytes(),
            Zeroizing::new(password.into_bytes()),
            &salt_base64,
        )?;
        Ok(clear_text.to_vec())
    })
}

/// Derive the base64-encoded password verifier used by Dart secure storage.
pub fn derive_secret_password_verifier(
    password: String,
    salt_base64: String,
) -> Result<String, String> {
    catch(|| {
        secret_payload::derive_password_verifier_base64(
            Zeroizing::new(password.into_bytes()),
            &salt_base64,
        )
    })
}
