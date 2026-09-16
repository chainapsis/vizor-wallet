//! Device and USB protocol entry points for the Ledger Zcash app.

use crate::wallet::ledger;
use flutter_rust_bridge::frb;

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
    use super::{ledger_export_ufvk, require_mainnet};

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
