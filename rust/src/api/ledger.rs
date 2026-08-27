//! Flutter Rust Bridge surface for the experimental Ledger integration.

use crate::wallet::ledger;
use sha2::{Digest, Sha256};

/// Public account material approved by the user on the Ledger device.
pub struct LedgerAccountExport {
    pub ufvk: String,
    pub seed_fingerprint: Vec<u8>,
    pub account_index: u32,
}

/// One transport-neutral APDU command. Mobile native code owns only the BLE
/// session and byte exchange; Rust remains the Zcash protocol authority.
pub struct LedgerApduCommand {
    pub cla: u8,
    pub ins: u8,
    pub p1: u8,
    pub p2: u8,
    pub data: Vec<u8>,
}

pub struct LedgerUfvkApduPlan {
    pub first: LedgerApduCommand,
    pub continuation: LedgerApduCommand,
}

/// Complete ordered APDU exchange for one PCZT signing operation.
pub struct LedgerPcztApduPlan {
    pub commands: Vec<LedgerApduCommand>,
}

/// The application currently running on the connected Ledger device.
pub struct LedgerDeviceApp {
    pub app_name: String,
    pub app_version: String,
}

/// A Ledger-produced spend authorization signature. `pool` is `0` for
/// Orchard and `1` for Ironwood; `sig` is always 64 bytes.
pub struct LedgerActionSig {
    pub pool: u8,
    pub action_index: u32,
    pub sig: Vec<u8>,
}

/// Durable Ledger operation metadata. Signed PCZT bytes never cross this API.
pub struct LedgerSignedOperation {
    pub operation_id: String,
    pub account_uuid: String,
    pub kind: String,
    pub external_ref: Option<String>,
    pub expiry_height: Option<u32>,
    pub state: String,
    pub txid: Option<String>,
    pub status: Option<String>,
    pub message: Option<String>,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
}

/// Result of broadcasting a checkpointed Ledger operation.
pub struct LedgerSignedOperationBroadcastResult {
    pub operation_id: String,
    pub txid: String,
    pub status: String,
    pub message: Option<String>,
    pub requires_ack: bool,
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
pub fn ledger_cancel_operation() {
    ledger::cancel_operation();
}

/// Export a Unified Full Viewing Key for `m/32'/133'/account'` after the user
/// approves the request on the Ledger device.
pub fn ledger_export_ufvk(account_index: u32, network: String) -> Result<String, String> {
    require_mainnet(&network)?;
    ledger::get_ufvk(account_index)
}

/// Export the UFVK and the stable derivation metadata Vizor needs to import
/// the corresponding watch-only account. The current Ledger APDU does not
/// expose the ZIP-32 seed fingerprint, so the PoC uses a domain-separated hash
/// of the approved UFVK as non-secret account metadata.
pub fn ledger_export_account(
    account_index: u32,
    network: String,
) -> Result<LedgerAccountExport, String> {
    require_mainnet(&network)?;
    let ufvk = ledger::get_ufvk(account_index)?;
    Ok(LedgerAccountExport {
        seed_fingerprint: ledger_account_fingerprint(&ufvk, account_index).to_vec(),
        ufvk,
        account_index,
    })
}

/// Build the Zcash app's UFVK request without opening a desktop transport.
pub fn ledger_build_ufvk_apdu_plan(account_index: u32) -> Result<LedgerUfvkApduPlan, String> {
    let (first, continuation) = ledger::apdu::ufvk_commands(account_index)?;
    Ok(LedgerUfvkApduPlan {
        first: to_apdu_command(first),
        continuation: to_apdu_command(continuation),
    })
}

/// Parse status-bearing DMK responses, validate the UFVK using the existing
/// Zcash decoder, and produce the same import metadata as the macOS path.
pub fn ledger_parse_mobile_ufvk_responses(
    account_index: u32,
    network: String,
    responses: Vec<Vec<u8>>,
) -> Result<LedgerAccountExport, String> {
    require_mainnet(&network)?;
    let ufvk = ledger::apdu::decode_raw_ufvk_responses(&responses)?;
    let network = crate::wallet::keys::parse_network(&network)?;
    zcash_keys::keys::UnifiedFullViewingKey::decode(&network, &ufvk)
        .map_err(|error| format!("Failed to parse Ledger UFVK: {error}"))?;
    Ok(LedgerAccountExport {
        seed_fingerprint: ledger_account_fingerprint(&ufvk, account_index).to_vec(),
        ufvk,
        account_index,
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

fn ledger_account_fingerprint(ufvk: &str, account_index: u32) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"vizor-ledger-account-fingerprint-v1\0");
    hasher.update(account_index.to_be_bytes());
    hasher.update(ufvk.as_bytes());
    hasher.finalize().into()
}

/// Stream an Orchard/Ironwood PCZT into the Ledger app and return only the
/// spend authorization signatures after on-device review and approval.
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

/// Stream a PCZT into Ledger, validate every returned transparent and
/// Orchard-family signature, and return the fully signed PCZT clone.
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

/// Durably checkpoint a Ledger-signed PCZT pair before any broadcast attempt.
pub fn ledger_checkpoint_signed_operation(
    db_path: String,
    network: String,
    operation_id: String,
    account_uuid: String,
    kind: String,
    external_ref: Option<String>,
    pczt_with_proofs_bytes: Vec<u8>,
    pczt_with_signatures_bytes: Vec<u8>,
) -> Result<LedgerSignedOperation, String> {
    let network = parse_ledger_db_network(&db_path, &network)?;
    ledger::checkpoint_signed_operation(
        &db_path,
        network,
        &operation_id,
        &account_uuid,
        &kind,
        external_ref.as_deref(),
        &pczt_with_proofs_bytes,
        &pczt_with_signatures_bytes,
    )
    .map(to_signed_operation)
}

/// List checkpointed Ledger operations without exposing either PCZT blob.
pub fn ledger_list_signed_operations(
    db_path: String,
    network: String,
    account_uuid: Option<String>,
) -> Result<Vec<LedgerSignedOperation>, String> {
    let network = parse_ledger_db_network(&db_path, &network)?;
    ledger::list_signed_operations(&db_path, network, account_uuid.as_deref())
        .map(|operations| operations.into_iter().map(to_signed_operation).collect())
}

/// Broadcast one checkpointed operation. Its signed bytes are loaded only in Rust.
pub async fn ledger_broadcast_signed_operation(
    db_path: String,
    lightwalletd_url: String,
    network: String,
    operation_id: String,
    spend_params_path: Option<String>,
    output_params_path: Option<String>,
) -> Result<LedgerSignedOperationBroadcastResult, String> {
    let network = parse_ledger_db_network(&db_path, &network)?;
    ledger::broadcast_signed_operation(
        &db_path,
        &lightwalletd_url,
        network,
        &operation_id,
        spend_params_path.as_deref(),
        output_params_path.as_deref(),
    )
    .await
    .map(|result| LedgerSignedOperationBroadcastResult {
        operation_id: result.operation_id,
        txid: result.txid,
        status: result.status,
        message: result.message,
        requires_ack: result.requires_ack,
    })
}

/// Acknowledge and delete an operation whose broadcast result is pending.
pub fn ledger_ack_signed_operation(
    db_path: String,
    network: String,
    operation_id: String,
) -> Result<(), String> {
    let network = parse_ledger_db_network(&db_path, &network)?;
    ledger::acknowledge_signed_operation(&db_path, network, &operation_id)
}

fn to_signed_operation(operation: ledger::SignedOperationMetadata) -> LedgerSignedOperation {
    LedgerSignedOperation {
        operation_id: operation.operation_id,
        account_uuid: operation.account_uuid,
        kind: operation.kind,
        external_ref: operation.external_ref,
        expiry_height: operation.expiry_height,
        state: operation.state,
        txid: operation.txid,
        status: operation.status,
        message: operation.message,
        created_at_ms: operation.created_at_ms,
        updated_at_ms: operation.updated_at_ms,
    }
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
    let metadata =
        crate::wallet::keys::get_ledger_account_signing_metadata(db_path, network, account_uuid)?;
    Ok(ledger::ExpectedAccount {
        account_index: metadata.account_index,
        coin_type: 133,
        seed_fingerprint: metadata.seed_fingerprint,
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
    use super::{ledger_account_fingerprint, require_mainnet};

    #[test]
    fn account_fingerprint_is_stable_and_account_scoped() {
        let first = ledger_account_fingerprint("uview-test", 0);
        assert_eq!(first, ledger_account_fingerprint("uview-test", 0));
        assert_ne!(first, ledger_account_fingerprint("uview-test", 1));
        assert_ne!(first, ledger_account_fingerprint("uview-other", 0));
    }

    #[test]
    fn ledger_network_gate_rejects_non_mainnet_before_device_access() {
        assert!(require_mainnet("main").is_ok());
        assert!(require_mainnet("test").unwrap_err().contains("mainnet"));
        assert!(require_mainnet("regtest").unwrap_err().contains("mainnet"));
    }
}
