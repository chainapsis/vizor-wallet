//! Device and USB protocol entry points for the Ledger Zcash app.

use crate::wallet::ledger;
use flutter_rust_bridge::frb;
use sha2::{Digest, Sha256};

/// Viewing-key material for one approved Ledger account; never a spending key.
pub struct LedgerAccountExport {
    pub ufvk: String,
    /// Synthetic account-scoped DB metadata, not the real ZIP-32 seed fingerprint.
    pub seed_fingerprint: Vec<u8>,
    pub account_index: u32,
    /// USB product name, for display only; not a device identity.
    pub device_model: Option<String>,
}

/// The application currently running on the connected Ledger device.
pub struct LedgerDeviceApp {
    pub app_name: String,
    pub app_version: String,
}

/// Read the application currently running on the connected Ledger device.
pub fn ledger_device_app() -> Result<LedgerDeviceApp, String> {
    ledger::get_device_app().map(to_device_app)
}

/// Open the Zcash app when needed, reconnect, and verify it is running.
pub fn ledger_open_zcash_app() -> Result<LedgerDeviceApp, String> {
    ledger::open_zcash_app().map(to_device_app)
}

/// Cancel the Ledger operation currently waiting for device interaction.
/// Runs on the caller's FFI invocation so busy device workers cannot delay it.
#[frb(sync)]
pub fn ledger_cancel_operation() {
    ledger::cancel_operation();
}

/// Export the UFVK for the selected mainnet account after device approval.
///
/// The request includes the shielded `m/32'/133'/account'` and transparent
/// `m/44'/133'/account'` derivation paths. This does not import an account into
/// the wallet or return seed/spending keys.
pub fn ledger_export_ufvk(account_index: u32, network: String) -> Result<String, String> {
    require_mainnet(&network)?;
    ledger::get_ufvk(account_index)
}

/// Export an account's UFVK and derivation metadata after device approval.
/// The Ledger app does not export the ZIP-32 seed fingerprint. The synthetic
/// hash here fills the DB derivation slot; it cannot identify a seed or device.
pub fn ledger_export_account(
    account_index: u32,
    network: String,
) -> Result<LedgerAccountExport, String> {
    require_mainnet(&network)?;
    zip32::AccountId::try_from(account_index)
        .map_err(|_| "Ledger account index must be less than 2^31")?;
    let (ufvk, device_model) = ledger::get_ufvk_with_device_model(account_index)?;
    zcash_keys::keys::UnifiedFullViewingKey::decode(
        &crate::wallet::keys::parse_network(&network)?,
        &ufvk,
    )
    .map_err(|error| format!("Failed to parse Ledger UFVK: {error}"))?;
    Ok(LedgerAccountExport {
        seed_fingerprint: ledger_account_fingerprint(&ufvk, account_index).to_vec(),
        ufvk,
        account_index,
        device_model,
    })
}

fn ledger_account_fingerprint(ufvk: &str, account_index: u32) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"vizor-ledger-account-fingerprint-v1\0");
    hasher.update(account_index.to_be_bytes());
    hasher.update(ufvk.as_bytes());
    hasher.finalize().into()
}

fn to_device_app(app: ledger::DeviceAppInfo) -> LedgerDeviceApp {
    LedgerDeviceApp {
        app_name: app.name,
        app_version: app.version,
    }
}

fn require_mainnet(network: &str) -> Result<(), String> {
    if network.trim() == "main" {
        Ok(())
    } else {
        Err("Ledger is currently supported only for Zcash mainnet".into())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        ledger_account_fingerprint, ledger_export_account, ledger_export_ufvk, require_mainnet,
    };

    #[test]
    fn account_fingerprint_is_stable_and_account_scoped() {
        let first = ledger_account_fingerprint("uview-test", 0);
        assert_eq!(first, ledger_account_fingerprint("uview-test", 0));
        assert_ne!(first, ledger_account_fingerprint("uview-test", 1));
        assert_ne!(first, ledger_account_fingerprint("uview-other", 0));
    }

    #[test]
    fn export_account_rejects_invalid_inputs_before_device_access() {
        assert!(ledger_export_account(0, "test".into())
            .err()
            .unwrap()
            .contains("mainnet"));
        assert!(ledger_export_account(1 << 31, "main".into())
            .err()
            .unwrap()
            .contains("index"));
    }

    #[test]
    fn ledger_network_gate_rejects_non_mainnet_before_device_access() {
        assert!(require_mainnet("main").is_ok());
        for network in ["test", "regtest", "", "unknown"] {
            assert!(ledger_export_ufvk(0, network.into())
                .unwrap_err()
                .contains("mainnet"));
        }
    }
}
