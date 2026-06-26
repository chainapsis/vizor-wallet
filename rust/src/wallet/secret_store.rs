use secrecy::SecretVec;
use zeroize::Zeroizing;

use crate::wallet::{keys, network::WalletNetwork, secret_payload};

const SECURE_STORE_SALT_KEY: &str = "zcash_secure_store_salt";
const ACCOUNT_MNEMONIC_KEY_PREFIX: &str = "zcash_account_mnemonic_";

pub fn seed_from_macos_stored_mnemonic(
    network: WalletNetwork,
    account_uuid: &str,
    password: Zeroizing<Vec<u8>>,
    local_test_profile: Option<&str>,
) -> Result<SecretVec<u8>, String> {
    let account_key = account_mnemonic_key(account_uuid);
    let salt_raw = macos_read_secure_store_value(
        &secure_store_service_for_network(network, local_test_profile)?,
        SECURE_STORE_SALT_KEY,
    )?
    .ok_or_else(|| "Secure storage salt not found".to_string())?;
    let payload_raw = macos_read_secure_store_value(
        &mnemonic_store_service_for_network(network, local_test_profile)?,
        &account_key,
    )?
    .ok_or_else(|| "Mnemonic not found for account".to_string())?;

    let salt = secret_payload::decode_base64(salt_raw.as_slice(), "secure storage salt")?;
    drop(salt_raw);
    let mnemonic_bytes = secret_payload::decrypt_payload(
        payload_raw.as_slice(),
        password.as_slice(),
        salt.as_slice(),
    )?;
    drop(password);
    drop(salt);
    drop(payload_raw);
    let seed = keys::mnemonic_bytes_to_seed(mnemonic_bytes.as_slice())?;
    drop(mnemonic_bytes);
    Ok(seed)
}

fn secure_store_service_for_network(
    network: WalletNetwork,
    local_test_profile: Option<&str>,
) -> Result<String, String> {
    let service = match network {
        WalletNetwork::Main => "com.keplr.vizor.secure_store".to_string(),
        WalletNetwork::Test => "com.keplr.vizor.test.secure_store".to_string(),
        WalletNetwork::Regtest => "com.keplr.vizor.regtest.secure_store".to_string(),
    };
    apply_local_test_profile_to_service_name(service, local_test_profile)
}

fn mnemonic_store_service_for_network(
    network: WalletNetwork,
    local_test_profile: Option<&str>,
) -> Result<String, String> {
    Ok(format!(
        "{}.mnemonic",
        secure_store_service_for_network(network, local_test_profile)?
    ))
}

fn account_mnemonic_key(account_uuid: &str) -> String {
    format!("{ACCOUNT_MNEMONIC_KEY_PREFIX}{account_uuid}")
}

fn apply_local_test_profile_to_service_name(
    service: String,
    local_test_profile: Option<&str>,
) -> Result<String, String> {
    if let Some(profile) = normalize_local_test_profile(local_test_profile)? {
        return Ok(format!("{service}.local.{profile}"));
    }

    Ok(service)
}

fn normalize_local_test_profile(raw: Option<&str>) -> Result<Option<String>, String> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }

    let profile = trimmed.to_ascii_lowercase();
    let mut chars = profile.chars();
    let first_valid = chars.next().is_some_and(|ch| ch.is_ascii_alphanumeric());
    let rest_valid = chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '-');
    if profile.len() > 32 || !first_valid || !rest_valid {
        return Err(
            "ZCASH_LOCAL_TEST_PROFILE must start with a letter or digit and contain only letters, digits, underscores, or hyphens."
                .to_string(),
        );
    }

    Ok(Some(profile))
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

    #[test]
    fn local_test_profile_suffixes_service_when_supplied() {
        assert_eq!(
            apply_local_test_profile_to_service_name(
                "com.keplr.vizor.regtest.secure_store".to_string(),
                Some(" Alice-1 ")
            )
            .unwrap(),
            "com.keplr.vizor.regtest.secure_store.local.alice-1"
        );
    }

    #[test]
    fn local_test_profile_ignores_empty_profile() {
        assert_eq!(
            apply_local_test_profile_to_service_name(
                "com.keplr.vizor.secure_store".to_string(),
                Some(" ")
            )
            .unwrap(),
            "com.keplr.vizor.secure_store"
        );
    }

    #[test]
    fn local_test_profile_rejects_unsafe_profile() {
        assert!(apply_local_test_profile_to_service_name(
            "com.keplr.vizor.secure_store".to_string(),
            Some("../alice")
        )
        .is_err());
    }
}
