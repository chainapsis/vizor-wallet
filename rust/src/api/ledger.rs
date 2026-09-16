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

/// One transport-neutral APDU command. Native Bluetooth adapters own only the
/// session and byte exchange; Rust remains the Zcash protocol authority.
pub struct LedgerApduCommand {
    pub cla: u8,
    pub ins: u8,
    pub p1: u8,
    pub p2: u8,
    pub data: Vec<u8>,
}

/// The first UFVK request and its continuation command.
pub struct LedgerUfvkApduPlan {
    pub first: LedgerApduCommand,
    pub continuation: LedgerApduCommand,
}

/// Complete ordered APDU exchange for one PCZT signing operation.
pub struct LedgerPcztApduPlan {
    pub commands: Vec<LedgerApduCommand>,
}

/// A Ledger-produced spend authorization signature. `pool` is `0` for
/// Orchard and `1` for Ironwood; `sig` is always 64 bytes.
pub struct LedgerActionSig {
    pub pool: u8,
    pub action_index: u32,
    pub sig: Vec<u8>,
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

/// Export an account's UFVK and derivation metadata after device approval.
/// The Ledger app does not export the ZIP-32 seed fingerprint. The synthetic
/// hash here fills the DB derivation slot; it cannot identify a seed or device.
pub fn ledger_export_account(
    account_index: u32,
    network: String,
) -> Result<LedgerAccountExport, String> {
    require_mainnet(&network)?;
    require_account_index(account_index)?;
    let (ufvk, device_model) = ledger::get_ufvk_with_device_model(account_index)?;
    validate_ufvk(&network, &ufvk)?;
    Ok(LedgerAccountExport {
        seed_fingerprint: ledger_account_fingerprint(&ufvk, account_index).to_vec(),
        ufvk,
        account_index,
        device_model,
    })
}

/// Build the Zcash app's UFVK request without opening a desktop transport.
pub fn ledger_build_ufvk_apdu_plan(account_index: u32) -> Result<LedgerUfvkApduPlan, String> {
    require_account_index(account_index)?;
    let (first, continuation) = ledger::apdu::ufvk_commands(account_index)?;
    Ok(LedgerUfvkApduPlan {
        first: to_apdu_command(first),
        continuation: to_apdu_command(continuation),
    })
}

/// Parse status-bearing Bluetooth responses and produce the same public
/// account metadata as the USB export path.
pub fn ledger_parse_mobile_ufvk_responses(
    account_index: u32,
    network: String,
    responses: Vec<Vec<u8>>,
) -> Result<LedgerAccountExport, String> {
    require_mainnet(&network)?;
    require_account_index(account_index)?;
    let ufvk = ledger::apdu::decode_raw_ufvk_responses(&responses)?;
    validate_ufvk(&network, &ufvk)?;
    Ok(LedgerAccountExport {
        seed_fingerprint: ledger_account_fingerprint(&ufvk, account_index).to_vec(),
        ufvk,
        account_index,
        device_model: None,
    })
}

/// Build the transport-neutral compact shielded PCZT signing exchange.
pub fn ledger_build_pczt_signing_apdu_plan(
    db_path: String,
    account_uuid: String,
    pczt_bytes: Vec<u8>,
    network: String,
) -> Result<LedgerPcztApduPlan, String> {
    let expected = expected_ledger_account(&db_path, &network, &account_uuid)?;
    ledger::validate_pczt_account(&pczt_bytes, expected)?;
    Ok(LedgerPcztApduPlan {
        commands: ledger::build_pczt_signing_plan(&pczt_bytes)?
            .into_iter()
            .map(to_apdu_command)
            .collect(),
    })
}

/// Build the transport-neutral full PCZT signing exchange.
pub fn ledger_build_pczt_full_signing_apdu_plan(
    db_path: String,
    account_uuid: String,
    pczt_bytes: Vec<u8>,
    network: String,
) -> Result<LedgerPcztApduPlan, String> {
    let expected = expected_ledger_account(&db_path, &network, &account_uuid)?;
    ledger::validate_pczt_account(&pczt_bytes, expected)?;
    Ok(LedgerPcztApduPlan {
        commands: ledger::build_pczt_full_signing_plan(&pczt_bytes)?
            .into_iter()
            .map(to_apdu_command)
            .collect(),
    })
}

/// Validate raw compact-signing responses and return shielded signatures.
pub fn ledger_finalize_mobile_pczt_signing(
    db_path: String,
    account_uuid: String,
    pczt_bytes: Vec<u8>,
    network: String,
    responses: Vec<Vec<u8>>,
) -> Result<Vec<LedgerActionSig>, String> {
    let expected = expected_ledger_account(&db_path, &network, &account_uuid)?;
    ledger::validate_pczt_account(&pczt_bytes, expected)?;
    to_action_sigs(ledger::finalize_pczt_signing(&pczt_bytes, &responses)?)
}

/// Validate raw full-signing responses and return the signed PCZT.
pub fn ledger_finalize_mobile_pczt_full_signing(
    db_path: String,
    account_uuid: String,
    pczt_bytes: Vec<u8>,
    network: String,
    responses: Vec<Vec<u8>>,
) -> Result<Vec<u8>, String> {
    let expected = expected_ledger_account(&db_path, &network, &account_uuid)?;
    ledger::validate_pczt_account(&pczt_bytes, expected)?;
    ledger::finalize_pczt_full_signing(&pczt_bytes, &responses)
}

fn to_apdu_command(command: ledger::apdu::ApduCommand) -> LedgerApduCommand {
    LedgerApduCommand {
        cla: command.cla,
        ins: command.ins,
        p1: command.p1,
        p2: command.p2,
        data: command.data,
    }
}

fn require_account_index(account_index: u32) -> Result<(), String> {
    zip32::AccountId::try_from(account_index)
        .map(|_| ())
        .map_err(|_| "Ledger account index must be less than 2^31".into())
}

fn validate_ufvk(network: &str, ufvk: &str) -> Result<(), String> {
    zcash_keys::keys::UnifiedFullViewingKey::decode(
        &crate::wallet::keys::parse_network(network)?,
        ufvk,
    )
    .map(|_| ())
    .map_err(|error| format!("Failed to parse Ledger UFVK: {error}"))
}

/// Reject a PCZT shape that the supported Ledger app cannot sign safely.
pub fn ledger_validate_supported_pczt(pczt_bytes: Vec<u8>) -> Result<(), String> {
    ledger::validate_pczt_release_support(&pczt_bytes)
}

/// Stream a shielded PCZT into Ledger and return spend authorization signatures.
pub fn ledger_sign_pczt(
    db_path: String,
    account_uuid: String,
    pczt_bytes: Vec<u8>,
    network: String,
) -> Result<Vec<LedgerActionSig>, String> {
    let expected = expected_ledger_account(&db_path, &network, &account_uuid)?;
    ledger::validate_pczt_account(&pczt_bytes, expected)?;
    to_action_sigs(ledger::sign_pczt(&pczt_bytes)?)
}

fn to_action_sigs(
    signatures: Vec<pczt::roles::signer::SpendAuthSignature>,
) -> Result<Vec<LedgerActionSig>, String> {
    signatures
        .iter()
        .map(|signature| {
            let pool = match signature.value_pool() {
                orchard::ValuePool::Orchard => 0,
                orchard::ValuePool::Ironwood => 1,
            };
            let action_index = u32::try_from(signature.action_index())
                .map_err(|_| "Ledger signature action index exceeds u32")?;
            Ok(LedgerActionSig {
                pool,
                action_index,
                sig: signature.signature().to_vec(),
            })
        })
        .collect()
}

/// Stream one PCZT into Ledger and return a fully verified signed clone.
pub fn ledger_sign_pczt_full(
    db_path: String,
    account_uuid: String,
    pczt_bytes: Vec<u8>,
    network: String,
) -> Result<Vec<u8>, String> {
    let expected = expected_ledger_account(&db_path, &network, &account_uuid)?;
    ledger::validate_pczt_account(&pczt_bytes, expected)?;
    ledger::sign_pczt_full(&pczt_bytes).map_err(|error| {
        log::error!(
            "ledger: PCZT signing failed ({} bytes): {error}",
            pczt_bytes.len()
        );
        error
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

fn parse_ledger_db_network(
    db_path: &str,
    network: &str,
) -> Result<crate::wallet::network::WalletNetwork, String> {
    require_mainnet(network)?;
    let network = crate::wallet::keys::parse_network(network)?;
    crate::wallet::keys::ensure_db_migrated_once(db_path, network)?;
    Ok(network)
}

fn expected_ledger_account(
    db_path: &str,
    network: &str,
    account_uuid: &str,
) -> Result<ledger::ExpectedAccount, String> {
    let network = parse_ledger_db_network(db_path, network)?;
    let account = crate::wallet::keys::list_accounts(db_path, network)?
        .into_iter()
        .find(|account| account.uuid == account_uuid)
        .ok_or_else(|| format!("Ledger account not found: {account_uuid}"))?;
    if account.hardware_signer_kind != Some(crate::wallet::keys::HardwareSignerKind::Ledger) {
        return Err(format!("Account {account_uuid} is not backed by Ledger"));
    }
    let metadata =
        crate::wallet::keys::get_account_export_metadata(db_path, network, account_uuid)?;
    let account_index = metadata
        .zip32_account_index
        .ok_or("Ledger account derivation index is unavailable")?;
    let seed_fingerprint: [u8; 32] = metadata
        .seed_fingerprint
        .ok_or("Ledger account seed fingerprint is unavailable")?
        .try_into()
        .map_err(|_| "Ledger account seed fingerprint must be 32 bytes")?;
    Ok(ledger::ExpectedAccount {
        account_index,
        coin_type: 133,
        seed_fingerprint,
    })
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
        ledger_account_fingerprint, ledger_build_ufvk_apdu_plan, ledger_export_account,
        ledger_parse_mobile_ufvk_responses, require_mainnet,
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
    fn mobile_ufvk_helpers_reject_invalid_indexes_before_exchange_or_decode() {
        assert!(ledger_build_ufvk_apdu_plan(1 << 31)
            .err()
            .unwrap()
            .contains("index"));
        assert!(
            ledger_parse_mobile_ufvk_responses(1 << 31, "main".into(), vec![])
                .err()
                .unwrap()
                .contains("index")
        );
        assert!(ledger_parse_mobile_ufvk_responses(0, "test".into(), vec![])
            .err()
            .unwrap()
            .contains("mainnet"));
        assert!(ledger_parse_mobile_ufvk_responses(
            0,
            "main".into(),
            vec![vec![0, 3, b'b', b'a', b'd', 0x90, 0]],
        )
        .err()
        .unwrap()
        .contains("parse Ledger UFVK"));
    }

    #[test]
    fn ledger_network_gate_rejects_non_mainnet_before_device_access() {
        assert!(require_mainnet("main").is_ok());
        for network in ["test", "regtest", "", "unknown"] {
            assert!(ledger_export_account(0, network.into())
                .err()
                .unwrap()
                .contains("mainnet"));
        }
    }
}
