use secrecy::SecretVec;
use zeroize::Zeroizing;

use crate::wallet::{keys, network::WalletNetwork, secret_payload};

const SECURE_STORE_SALT_KEY: &str = "zcash_secure_store_salt";
const ACCOUNT_MNEMONIC_KEY_PREFIX: &str = "zcash_account_mnemonic_";

pub fn seed_from_macos_stored_mnemonic(
    network: WalletNetwork,
    account_uuid: &str,
    password: Zeroizing<Vec<u8>>,
) -> Result<SecretVec<u8>, String> {
    let account_key = account_mnemonic_key(account_uuid);
    let base_service = secure_store_service_for_network(network)?;
    let mnemonic_service = mnemonic_store_service(&base_service);
    let salt_raw = macos_read_secure_store_value(&base_service, SECURE_STORE_SALT_KEY)?
        .ok_or_else(|| "Secure storage salt not found".to_string())?;
    let payload_raw = macos_read_secure_store_value(&mnemonic_service, &account_key)?
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

fn secure_store_service_for_network(network: WalletNetwork) -> Result<String, String> {
    let namespace = match std::env::var("VIZOR_E2E_NAMESPACE") {
        Ok(value) => Some(value),
        Err(std::env::VarError::NotPresent) => None,
        Err(std::env::VarError::NotUnicode(_)) => {
            return Err("VIZOR_E2E_NAMESPACE must be valid UTF-8".to_string());
        }
    };
    secure_store_service(network, namespace.as_deref(), cfg!(debug_assertions))
}

fn secure_store_service(
    network: WalletNetwork,
    namespace: Option<&str>,
    debug_assertions: bool,
) -> Result<String, String> {
    let base = match network {
        WalletNetwork::Main => "com.keplr.vizor.secure_store".to_string(),
        WalletNetwork::Test => "com.keplr.vizor.test.secure_store".to_string(),
        WalletNetwork::Regtest => "com.keplr.vizor.regtest.secure_store".to_string(),
    };
    let Some(namespace) = namespace.filter(|value| !value.is_empty()) else {
        return Ok(base);
    };
    if !debug_assertions {
        return Err("VIZOR_E2E_NAMESPACE is only supported in debug builds".to_string());
    }
    if network != WalletNetwork::Regtest {
        return Err("VIZOR_E2E_NAMESPACE is only supported for regtest".to_string());
    }
    if namespace.len() > 64
        || !namespace.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_' || byte == b'-'
        })
    {
        return Err(
            "VIZOR_E2E_NAMESPACE must contain 1-64 lowercase ASCII letters, digits, underscores, or hyphens"
                .to_string(),
        );
    }
    Ok(format!("{base}.e2e.{namespace}"))
}

fn mnemonic_store_service(base_service: &str) -> String {
    format!("{base_service}.mnemonic")
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

    #[test]
    fn baseline_services_are_unchanged_for_every_network() {
        for (network, expected) in [
            (WalletNetwork::Main, "com.keplr.vizor.secure_store"),
            (WalletNetwork::Test, "com.keplr.vizor.test.secure_store"),
            (
                WalletNetwork::Regtest,
                "com.keplr.vizor.regtest.secure_store",
            ),
        ] {
            assert_eq!(
                secure_store_service(network, None, false).unwrap(),
                expected
            );
            assert_eq!(
                secure_store_service(network, Some(""), false).unwrap(),
                expected
            );
        }
    }

    #[test]
    fn valid_debug_regtest_namespace_suffixes_the_service() {
        assert_eq!(
            secure_store_service(WalletNetwork::Regtest, Some("vizor_a1b2c3d4e5_w2_17"), true)
                .unwrap(),
            "com.keplr.vizor.regtest.secure_store.e2e.vizor_a1b2c3d4e5_w2_17"
        );
    }

    #[test]
    fn invalid_or_non_ascii_namespaces_are_rejected() {
        for namespace in ["Uppercase", "contains.dot", "vizor_실행"] {
            assert!(secure_store_service(WalletNetwork::Regtest, Some(namespace), true).is_err());
        }
        let too_long = "a".repeat(65);
        assert!(secure_store_service(WalletNetwork::Regtest, Some(&too_long), true).is_err());
    }

    #[test]
    fn namespace_is_rejected_outside_debug_regtest() {
        assert!(secure_store_service(WalletNetwork::Regtest, Some("vizor_run"), false).is_err());
        assert!(secure_store_service(WalletNetwork::Main, Some("vizor_run"), true).is_err());
        assert!(secure_store_service(WalletNetwork::Test, Some("vizor_run"), true).is_err());
    }

    #[test]
    fn mnemonic_service_uses_the_namespaced_base_service() {
        let base = secure_store_service(WalletNetwork::Regtest, Some("vizor_run"), true).unwrap();
        assert_eq!(
            mnemonic_store_service(&base),
            "com.keplr.vizor.regtest.secure_store.e2e.vizor_run.mnemonic"
        );
    }
}
