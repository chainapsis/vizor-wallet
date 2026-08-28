//! Experimental macOS transport for the Ledger Zcash Ironwood app.
//!
//! Every operation opens a fresh HID session. The current unsigned device app
//! can leave a session in a stale state after UFVK approval, so reusing that
//! handle for PCZT signing is intentionally avoided in this PoC.

pub(crate) mod apdu;
mod operations;
mod parse;
mod serializer;

pub(crate) use operations::{
    acknowledge as acknowledge_signed_operation, broadcast as broadcast_signed_operation,
    checkpoint as checkpoint_signed_operation,
    checkpoint_batch as checkpoint_signed_operation_batch,
    delete_for_account_with_tx as delete_signed_operations_for_account_with_tx,
    list as list_signed_operations, SignedOperationMetadata,
};

#[cfg(target_os = "macos")]
mod transport;

use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex,
    },
    thread,
    time::{Duration, Instant},
};

use orchard::ValuePool;
use pczt::roles::signer::{Signer, SpendAuthSignature};
use sha2::{Digest, Sha256};

use self::{
    apdu::{ApduCommand, ZCASH_CLA},
    serializer::{packet_p1, packet_p2},
};
use self::{parse::parse_pczt, serializer::serialize_pczt};

static LEDGER_OPERATION: Mutex<()> = Mutex::new(());
static LEDGER_OPERATION_STATE: OperationState = OperationState::new();
#[cfg(target_os = "macos")]
static LEDGER_SIGNING_READY_AT: Mutex<Option<Instant>> = Mutex::new(None);
const LEDGER_OPERATION_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const APP_TRANSITION_TIMEOUT: Duration = Duration::from_secs(10);
const APP_TRANSITION_POLL_INTERVAL: Duration = Duration::from_millis(200);
#[cfg(target_os = "macos")]
const SIGNING_STATUS_COOLDOWN: Duration = Duration::from_secs(4);
#[cfg(target_os = "macos")]
const SIGNING_STATUS_POLL_INTERVAL: Duration = Duration::from_millis(100);
const ZCASH_APP_NAME: &str = "Zcash";
const DASHBOARD_APP_NAMES: [&str; 3] = ["BOLOS", "OLOS", "OLOS\0"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceAppInfo {
    pub name: String,
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WalletIdentity {
    pub fingerprint: String,
    pub verification_address: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct ExpectedAccount {
    pub account_index: u32,
    pub coin_type: u32,
    pub seed_fingerprint: [u8; 32],
}

struct OperationState {
    next: AtomicU64,
    active: AtomicU64,
    cancelled: AtomicU64,
}

impl OperationState {
    const fn new() -> Self {
        Self {
            next: AtomicU64::new(0),
            active: AtomicU64::new(0),
            cancelled: AtomicU64::new(0),
        }
    }

    fn begin(&self) -> u64 {
        let generation = self.next.fetch_add(1, Ordering::SeqCst).wrapping_add(1);
        assert_ne!(generation, 0, "Ledger operation generation exhausted");
        self.active.store(generation, Ordering::SeqCst);
        generation
    }

    fn finish(&self, generation: u64) {
        let _ = self
            .active
            .compare_exchange(generation, 0, Ordering::SeqCst, Ordering::SeqCst);
    }

    fn cancel_active(&self) {
        let generation = self.active.load(Ordering::SeqCst);
        if generation != 0 {
            self.cancelled.store(generation, Ordering::SeqCst);
        }
    }

    fn is_cancelled(&self, generation: u64) -> bool {
        self.cancelled.load(Ordering::SeqCst) == generation
    }
}

#[derive(Clone, Copy)]
pub(super) struct OperationContext {
    generation: u64,
    deadline: Instant,
}

impl OperationContext {
    pub(super) fn check(&self) -> Result<(), String> {
        classify_operation_state(
            LEDGER_OPERATION_STATE.is_cancelled(self.generation),
            Instant::now() >= self.deadline,
        )
    }

    pub(super) fn remaining(&self) -> Duration {
        self.deadline.saturating_duration_since(Instant::now())
    }
}

struct OperationGuard {
    _lock: std::sync::MutexGuard<'static, ()>,
    context: OperationContext,
}

#[cfg(target_os = "macos")]
struct SigningStatusCooldownGuard;

#[cfg(target_os = "macos")]
impl Drop for SigningStatusCooldownGuard {
    fn drop(&mut self) {
        if let Ok(mut ready_at) = LEDGER_SIGNING_READY_AT.lock() {
            *ready_at = Some(Instant::now() + SIGNING_STATUS_COOLDOWN);
        }
    }
}

impl OperationGuard {
    fn context(&self) -> OperationContext {
        self.context
    }
}

impl Drop for OperationGuard {
    fn drop(&mut self) {
        LEDGER_OPERATION_STATE.finish(self.context.generation);
    }
}

#[derive(Debug, Clone)]
struct TransparentInputSignature {
    signature: Vec<u8>,
    sighash_type: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SignatureRequest {
    Transparent {
        input_index: usize,
    },
    Shielded {
        pool: ValuePool,
        action_index: usize,
        instruction: u8,
    },
}

pub(crate) fn validate_pczt_account(
    pczt_bytes: &[u8],
    expected: ExpectedAccount,
) -> Result<(), String> {
    let parsed = parse_pczt(pczt_bytes)?;
    if parsed.global.coin_type != expected.coin_type {
        return Err(format!(
            "Ledger PCZT coin type {} does not match expected coin type {}",
            parsed.global.coin_type, expected.coin_type
        ));
    }

    for (index, input) in parsed.transparent_inputs.iter().enumerate() {
        validate_transparent_derivation(
            &input.derivation,
            expected,
            &format!("transparent input {index}"),
            true,
        )?;
    }
    for (index, output) in parsed.transparent_outputs.iter().enumerate() {
        if let Some(derivation) = output.derivation.as_ref() {
            validate_transparent_derivation(
                derivation,
                expected,
                &format!("transparent output {index}"),
                false,
            )?;
        }
    }
    if let Some(bundle) = parsed.orchard_bundle.as_ref() {
        for (index, action) in bundle.actions.iter().enumerate() {
            validate_shielded_derivation(
                &action.signing_path,
                &action.seed_fingerprint,
                expected,
                &format!("Orchard action {index}"),
            )?;
        }
    }
    if let Some(bundle) = parsed.ironwood_bundle.as_ref() {
        for (index, action) in bundle.actions.iter().enumerate() {
            validate_shielded_derivation(
                &action.action.signing_path,
                &action.action.seed_fingerprint,
                expected,
                &format!("Ironwood action {index}"),
            )?;
        }
    }
    Ok(())
}

fn validate_transparent_derivation(
    derivation: &parse::Bip32Derivation,
    expected: ExpectedAccount,
    label: &str,
    allow_ephemeral_scope: bool,
) -> Result<(), String> {
    const HARDENED: u32 = 0x8000_0000;
    let expected_path = [
        HARDENED | 44,
        HARDENED | expected.coin_type,
        HARDENED | expected.account_index,
    ];
    let path = &derivation.signing_path;
    let valid_scope = path
        .get(3)
        .is_some_and(|scope| matches!(*scope, 0 | 1) || (allow_ephemeral_scope && *scope == 2));
    let valid_suffix = path.len() == 5 && valid_scope && path[4] & HARDENED == 0;
    if path.get(..3) != Some(expected_path.as_slice()) || !valid_suffix {
        return Err(format!(
            "Ledger {label} derivation path does not belong to account {}",
            expected.account_index
        ));
    }
    validate_fingerprint(&derivation.seed_fingerprint, expected, label)
}

fn validate_shielded_derivation(
    path: &[u32],
    fingerprint: &[u8; 32],
    expected: ExpectedAccount,
    label: &str,
) -> Result<(), String> {
    const HARDENED: u32 = 0x8000_0000;
    let expected_path = [
        HARDENED | 32,
        HARDENED | expected.coin_type,
        HARDENED | expected.account_index,
    ];
    if path != expected_path {
        return Err(format!(
            "Ledger {label} derivation path does not belong to account {}",
            expected.account_index
        ));
    }
    validate_fingerprint(fingerprint, expected, label)
}

fn validate_fingerprint(
    fingerprint: &[u8; 32],
    expected: ExpectedAccount,
    label: &str,
) -> Result<(), String> {
    if fingerprint != &expected.seed_fingerprint {
        Err(format!(
            "Ledger {label} seed fingerprint does not match the selected account"
        ))
    } else {
        Ok(())
    }
}

/// Builds the complete ordered APDU exchange for compact shielded signing.
pub(crate) fn build_pczt_signing_plan(pczt_bytes: &[u8]) -> Result<Vec<ApduCommand>, String> {
    build_signing_plan(pczt_bytes, false).map(|(commands, _)| commands)
}

/// Builds the complete ordered APDU exchange for a fully signed PCZT.
pub(crate) fn build_pczt_full_signing_plan(pczt_bytes: &[u8]) -> Result<Vec<ApduCommand>, String> {
    build_signing_plan(pczt_bytes, true).map(|(commands, _)| commands)
}

/// Validates raw status-bearing responses and returns compact shielded signatures.
pub fn finalize_pczt_signing(
    pczt_bytes: &[u8],
    responses: &[Vec<u8>],
) -> Result<Vec<SpendAuthSignature>, String> {
    let (commands, requests) = build_signing_plan(pczt_bytes, false)?;
    let (_, shielded) = decode_signing_responses(&commands, &requests, responses)?;
    crate::wallet::sync::preflight_orchard_spend_auth_signatures(pczt_bytes, &shielded)?;
    Ok(shielded)
}

/// Validates raw status-bearing responses, applies every signature, and returns a signed PCZT.
pub fn finalize_pczt_full_signing(
    pczt_bytes: &[u8],
    responses: &[Vec<u8>],
) -> Result<Vec<u8>, String> {
    let parsed = parse_pczt(pczt_bytes)?;
    let (commands, requests) = build_signing_plan(pczt_bytes, true)?;
    let (transparent, shielded) = decode_signing_responses(&commands, &requests, responses)?;
    apply_signatures(pczt_bytes, &parsed, &transparent, &shielded)
}

fn build_signing_plan(
    pczt_bytes: &[u8],
    include_transparent: bool,
) -> Result<(Vec<ApduCommand>, Vec<SignatureRequest>), String> {
    let parsed = parse_pczt(pczt_bytes)?;
    if !include_transparent && !parsed.transparent_inputs.is_empty() {
        return Err(
            "PCZT has transparent inputs; use sign_pczt_full so Ledger produces every signature after one review"
                .into(),
        );
    }

    let serialized = serialize_pczt(&parsed)?;
    let mut commands = Vec::new();
    for command in serialized {
        let total = command.packets.len();
        if total == 0 {
            return Err("Ledger PCZT command has no packets".into());
        }
        for (index, data) in command.packets.into_iter().enumerate() {
            commands.push(ApduCommand {
                cla: ZCASH_CLA,
                ins: command.instruction,
                p1: packet_p1(index, total),
                p2: packet_p2(index, total, command.finishes_pczt),
                data,
            });
        }
    }

    let mut requests = Vec::new();
    if include_transparent {
        requests.extend(
            (0..parsed.transparent_inputs.len())
                .map(|input_index| SignatureRequest::Transparent { input_index }),
        );
    }
    if let Some(bundle) = &parsed.orchard_bundle {
        requests.extend(
            bundle
                .actions
                .iter()
                .enumerate()
                .filter(|(_, action)| action.spend_value != 0)
                .map(|(action_index, _)| SignatureRequest::Shielded {
                    pool: ValuePool::Orchard,
                    action_index,
                    instruction: 0x57,
                }),
        );
    }
    if let Some(bundle) = &parsed.ironwood_bundle {
        requests.extend(
            bundle
                .actions
                .iter()
                .enumerate()
                .filter(|(_, action)| action.action.spend_value != 0)
                .map(|(action_index, _)| SignatureRequest::Shielded {
                    pool: ValuePool::Ironwood,
                    action_index,
                    instruction: 0x59,
                }),
        );
    }
    if requests.is_empty() {
        return Err(if include_transparent {
            "PCZT has no real transparent, Orchard, or Ironwood spends for Ledger to sign".into()
        } else {
            "PCZT has no real Orchard or Ironwood spends for Ledger to sign".into()
        });
    }

    for request in &requests {
        let (ins, p2) = match request {
            SignatureRequest::Transparent { input_index } => (0x55, *input_index),
            SignatureRequest::Shielded {
                action_index,
                instruction,
                ..
            } => (*instruction, *action_index),
        };
        commands.push(ApduCommand {
            cla: ZCASH_CLA,
            ins,
            p1: 0,
            p2: u8::try_from(p2).map_err(|_| "Ledger signing index exceeds the APDU range")?,
            data: Vec::new(),
        });
    }
    Ok((commands, requests))
}

fn decode_signing_responses(
    commands: &[ApduCommand],
    requests: &[SignatureRequest],
    responses: &[Vec<u8>],
) -> Result<(Vec<TransparentInputSignature>, Vec<SpendAuthSignature>), String> {
    let payloads = responses
        .iter()
        .enumerate()
        .map(|(index, response)| {
            if index >= commands.len() {
                return Err(format!(
                    "Ledger returned {} APDU response(s); expected {}",
                    responses.len(),
                    commands.len()
                ));
            }
            apdu::decode_raw_response(response)
        })
        .collect::<Result<Vec<_>, _>>()?;
    if responses.len() != commands.len() {
        return Err(format!(
            "Ledger returned {} APDU response(s); expected {}",
            responses.len(),
            commands.len()
        ));
    }
    let packet_count = commands.len() - requests.len();
    for (index, payload) in payloads[..packet_count].iter().enumerate() {
        if !payload.is_empty() {
            return Err(format!(
                "Ledger PCZT APDU {} returned unexpected response data",
                index + 1
            ));
        }
    }

    let mut transparent = Vec::new();
    let mut shielded = Vec::new();
    for (request, payload) in requests.iter().zip(&payloads[packet_count..]) {
        match request {
            SignatureRequest::Transparent { input_index } => transparent.push(
                decode_transparent_signature(payload.clone()).map_err(|error| {
                    format!("Ledger transparent signature {input_index} is invalid: {error}")
                })?,
            ),
            SignatureRequest::Shielded {
                pool, action_index, ..
            } => {
                let signature: [u8; 64] = payload.as_slice().try_into().map_err(|_| {
                    format!(
                        "Ledger returned a {}-byte spend authorization signature; expected 64",
                        payload.len()
                    )
                })?;
                if signature.iter().all(|byte| *byte == 0) {
                    return Err("Ledger returned an all-zero spend authorization signature".into());
                }
                shielded.push(SpendAuthSignature::from_parts(
                    *pool,
                    *action_index,
                    signature,
                ));
            }
        }
    }
    Ok((transparent, shielded))
}

fn decode_transparent_signature(response: Vec<u8>) -> Result<TransparentInputSignature, String> {
    if !(9..=73).contains(&response.len()) {
        return Err(format!(
            "returned {} bytes; expected DER plus sighash type",
            response.len()
        ));
    }
    let (signature, sighash_type) = response.split_at(response.len() - 1);
    if signature[0] & 0xfe != 0x30 {
        return Err("invalid DER sequence tag".into());
    }
    if signature[1] as usize + 2 != signature.len() {
        return Err("invalid DER length".into());
    }
    Ok(TransparentInputSignature {
        signature: signature.to_vec(),
        sighash_type: sighash_type[0],
    })
}

#[cfg(target_os = "macos")]
pub fn get_device_app() -> Result<DeviceAppInfo, String> {
    let operation = lock_operation()?;
    read_device_app(operation.context())
}

#[cfg(not(target_os = "macos"))]
pub fn get_device_app() -> Result<DeviceAppInfo, String> {
    Err(unsupported_platform())
}

#[cfg(target_os = "macos")]
pub fn open_zcash_app() -> Result<DeviceAppInfo, String> {
    let operation = lock_operation()?;
    let context = operation.context();
    let current = read_device_app(context)?;
    if current.name == ZCASH_APP_NAME {
        return Ok(current);
    }

    if !is_dashboard_app(&current.name) {
        let transport = transport::LedgerTransport::connect(context)?;
        transport.close_app()?;
        drop(transport);
        wait_for_device_app(context, is_dashboard_app, "Ledger dashboard")?;
    }

    let transport = transport::LedgerTransport::connect(context)?;
    transport.open_app(ZCASH_APP_NAME)?;
    drop(transport);
    wait_for_device_app(context, |name| name == ZCASH_APP_NAME, "Zcash app")
}

#[cfg(not(target_os = "macos"))]
pub fn open_zcash_app() -> Result<DeviceAppInfo, String> {
    Err(unsupported_platform())
}

#[cfg(target_os = "macos")]
fn read_device_app(context: OperationContext) -> Result<DeviceAppInfo, String> {
    let app = transport::LedgerTransport::connect(context)?.current_app()?;
    Ok(DeviceAppInfo {
        name: app.name,
        version: app.version,
    })
}

#[cfg(target_os = "macos")]
fn wait_for_device_app(
    context: OperationContext,
    matches: impl Fn(&str) -> bool,
    expected: &str,
) -> Result<DeviceAppInfo, String> {
    let deadline = Instant::now() + APP_TRANSITION_TIMEOUT;

    loop {
        context.check()?;
        let observation = match read_device_app(context) {
            Ok(app) if matches(&app.name) => return Ok(app),
            Ok(app) => format!("the device reported {} {}", app.name, app.version),
            Err(error) if is_terminal_app_transition_error(&error) => return Err(error),
            Err(error) => error,
        };

        if Instant::now() >= deadline {
            return Err(format!(
                "Ledger did not become ready in {expected} after switching apps: {observation}"
            ));
        }
        thread::sleep(APP_TRANSITION_POLL_INTERVAL);
    }
}

fn is_dashboard_app(name: &str) -> bool {
    DASHBOARD_APP_NAMES.contains(&name)
}

fn is_terminal_app_transition_error(error: &str) -> bool {
    error.contains("locked")
        || error.contains("PIN is not set")
        || error.contains("not installed")
        || error.contains("rejected")
        || error.contains("does not support this command")
}

#[cfg(target_os = "macos")]
pub fn get_ufvk(account_index: u32) -> Result<String, String> {
    let operation = lock_operation()?;
    transport::LedgerTransport::connect_ufvk(operation.context())?.ufvk(account_index)
}

#[cfg(not(target_os = "macos"))]
pub fn get_ufvk(_account_index: u32) -> Result<String, String> {
    Err(unsupported_platform())
}

#[cfg(target_os = "macos")]
pub fn get_wallet_identity(
    verification_account_index: Option<u32>,
) -> Result<WalletIdentity, String> {
    let operation = lock_operation()?;
    let (identity, verification) = transport::LedgerTransport::connect_ufvk(operation.context())?
        .wallet_identity(verification_account_index)?;
    Ok(WalletIdentity {
        fingerprint: wallet_fingerprint(&identity),
        verification_address: verification.map(|key| key.address),
    })
}

#[cfg(not(target_os = "macos"))]
pub fn get_wallet_identity(
    _verification_account_index: Option<u32>,
) -> Result<WalletIdentity, String> {
    Err(unsupported_platform())
}

pub(crate) fn wallet_fingerprint(key: &apdu::WalletPublicKey) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"vizor-ledger-wallet-fingerprint-v1\0");
    hasher.update(key.public_key);
    hasher.update(key.chain_code);
    hex::encode(hasher.finalize())
}

#[cfg(target_os = "macos")]
pub fn sign_pczt(pczt_bytes: &[u8]) -> Result<Vec<SpendAuthSignature>, String> {
    let parsed = parse_pczt(pczt_bytes)?;
    if !parsed.transparent_inputs.is_empty() {
        return Err(
            "PCZT has transparent inputs; use sign_pczt_full so Ledger produces every signature after one review"
                .into(),
        );
    }
    let commands = serialize_pczt(&parsed)?;

    let mut requests = Vec::new();
    if let Some(bundle) = &parsed.orchard_bundle {
        requests.extend(
            bundle
                .actions
                .iter()
                .enumerate()
                .filter(|(_, action)| action.spend_value != 0)
                .map(|(index, _)| (ValuePool::Orchard, index, 0x57)),
        );
    }
    if let Some(bundle) = &parsed.ironwood_bundle {
        requests.extend(
            bundle
                .actions
                .iter()
                .enumerate()
                .filter(|(_, action)| action.action.spend_value != 0)
                .map(|(index, _)| (ValuePool::Ironwood, index, 0x59)),
        );
    }
    if requests.is_empty() {
        return Err("PCZT has no real Orchard or Ironwood spends for Ledger to sign".into());
    }

    let operation = lock_operation()?;
    wait_for_signing_status(operation.context())?;
    let _signing_status_cooldown = SigningStatusCooldownGuard;
    let transport = transport::LedgerTransport::connect_signing(operation.context())?;
    transport.send_pczt(&commands)?;

    let signatures = requests
        .into_iter()
        .map(|(pool, action_index, instruction)| {
            transport
                .sign_action(instruction, action_index)
                .map(|signature| SpendAuthSignature::from_parts(pool, action_index, signature))
        })
        .collect::<Result<Vec<_>, _>>()?;

    crate::wallet::sync::preflight_orchard_spend_auth_signatures(pczt_bytes, &signatures)?;
    Ok(signatures)
}

#[cfg(not(target_os = "macos"))]
pub fn sign_pczt(_pczt_bytes: &[u8]) -> Result<Vec<SpendAuthSignature>, String> {
    Err(unsupported_platform())
}

/// Streams one PCZT to Ledger for a single transaction review, requests every
/// transparent and Orchard-family signature it requires, verifies those
/// signatures through the PCZT Signer role, and returns the signed PCZT.
#[cfg(target_os = "macos")]
pub fn sign_pczt_full(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    let parsed = parse_pczt(pczt_bytes)?;
    let commands = serialize_pczt(&parsed)?;

    let transparent_requests = 0..parsed.transparent_inputs.len();
    let mut shielded_requests = Vec::new();
    if let Some(bundle) = &parsed.orchard_bundle {
        shielded_requests.extend(
            bundle
                .actions
                .iter()
                .enumerate()
                .filter(|(_, action)| action.spend_value != 0)
                .map(|(index, _)| (ValuePool::Orchard, index, 0x57)),
        );
    }
    if let Some(bundle) = &parsed.ironwood_bundle {
        shielded_requests.extend(
            bundle
                .actions
                .iter()
                .enumerate()
                .filter(|(_, action)| action.action.spend_value != 0)
                .map(|(index, _)| (ValuePool::Ironwood, index, 0x59)),
        );
    }

    if transparent_requests.is_empty() && shielded_requests.is_empty() {
        return Err(
            "PCZT has no real transparent, Orchard, or Ironwood spends for Ledger to sign".into(),
        );
    }

    let operation = lock_operation()?;
    wait_for_signing_status(operation.context())?;
    let _signing_status_cooldown = SigningStatusCooldownGuard;
    let transport = transport::LedgerTransport::connect_signing(operation.context())?;
    transport.send_pczt(&commands)?;

    // Request transparent signatures first, matching the order in which the app
    // receives the PCZT bundles. The device resets its signing state only after
    // every requested transparent and shielded signature has been produced.
    let transparent_signatures = transparent_requests
        .map(|input_index| {
            transport
                .sign_transparent_input(input_index)
                .map(|signature| TransparentInputSignature {
                    signature: signature.signature,
                    sighash_type: signature.sighash_type,
                })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let shielded_signatures = shielded_requests
        .into_iter()
        .map(|(pool, action_index, instruction)| {
            transport
                .sign_action(instruction, action_index)
                .map(|signature| SpendAuthSignature::from_parts(pool, action_index, signature))
        })
        .collect::<Result<Vec<_>, _>>()?;

    apply_signatures(
        pczt_bytes,
        &parsed,
        &transparent_signatures,
        &shielded_signatures,
    )
}

#[cfg(not(target_os = "macos"))]
pub fn sign_pczt_full(_pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    Err(unsupported_platform())
}

fn apply_signatures(
    pczt_bytes: &[u8],
    parsed: &parse::ParsedPczt,
    transparent_signatures: &[TransparentInputSignature],
    shielded_signatures: &[SpendAuthSignature],
) -> Result<Vec<u8>, String> {
    if transparent_signatures.len() != parsed.transparent_inputs.len() {
        return Err(format!(
            "Ledger returned {} transparent signature(s); expected {}",
            transparent_signatures.len(),
            parsed.transparent_inputs.len()
        ));
    }

    crate::wallet::sync::preflight_orchard_spend_auth_signatures(pczt_bytes, shielded_signatures)?;

    let pczt = pczt::Pczt::parse(pczt_bytes)
        .map_err(|e| format!("Parse PCZT for Ledger signatures: {e:?}"))?;

    // The upstream transparent Signer locates the validating pubkey for a P2PKH
    // input through its hash160 preimage map. Ledger already required exactly one
    // BIP-32 pubkey per input, so provide that same public data to the Signer role.
    let mut updater = pczt::roles::updater::Updater::new(pczt);
    if !parsed.transparent_inputs.is_empty() {
        updater = updater
            .update_transparent_with(|mut bundle| {
                for (index, input) in parsed.transparent_inputs.iter().enumerate() {
                    bundle.update_input_with(index, |mut input_updater| {
                        input_updater.set_hash160_preimage(input.derivation.pubkey.to_vec());
                        Ok(())
                    })?;
                }
                Ok(())
            })
            .map_err(|e| format!("Prepare transparent PCZT signature validation: {e:?}"))?;
    }

    let mut signer =
        Signer::new(updater.finish()).map_err(|e| format!("Create Ledger PCZT signer: {e:?}"))?;

    for (input_index, (input, ledger_signature)) in parsed
        .transparent_inputs
        .iter()
        .zip(transparent_signatures)
        .enumerate()
    {
        if ledger_signature.sighash_type != input.sighash_type {
            return Err(format!(
                "Ledger transparent signature {input_index} used sighash type {:#04x}; expected {:#04x}",
                ledger_signature.sighash_type, input.sighash_type
            ));
        }

        let mut der = ledger_signature.signature.clone();
        let Some(sequence_tag) = der.first_mut() else {
            return Err(format!(
                "Ledger transparent signature {input_index} is empty"
            ));
        };
        // Ledger stores the derived public key's Y parity in the low bit of the
        // usual 0x30 DER sequence tag. It is metadata, not part of the signature.
        *sequence_tag &= 0xfe;
        let signature = secp256k1::ecdsa::Signature::from_der(&der)
            .map_err(|e| format!("Parse Ledger transparent signature {input_index} as DER: {e}"))?;

        signer
            .append_transparent_signature(input_index, signature)
            .map_err(|e| format!("Validate Ledger transparent signature {input_index}: {e:?}"))?;
    }

    for signature in shielded_signatures {
        signer
            .apply_orchard_spend_auth_signature(signature)
            .map_err(|e| {
                format!(
                    "Apply Ledger {:?} signature at action {}: {e:?}",
                    signature.value_pool(),
                    signature.action_index()
                )
            })?;
    }

    signer
        .finish()
        .serialize()
        .map_err(|e| format!("Serialize Ledger-signed PCZT: {e:?}"))
}

pub fn cancel_operation() {
    LEDGER_OPERATION_STATE.cancel_active();
}

fn lock_operation() -> Result<OperationGuard, String> {
    let lock = LEDGER_OPERATION
        .lock()
        .map_err(|_| "Ledger operation lock was poisoned".to_string())?;
    let generation = LEDGER_OPERATION_STATE.begin();
    Ok(OperationGuard {
        _lock: lock,
        context: OperationContext {
            generation,
            deadline: Instant::now() + LEDGER_OPERATION_TIMEOUT,
        },
    })
}

#[cfg(target_os = "macos")]
fn wait_for_signing_status(operation: OperationContext) -> Result<(), String> {
    loop {
        operation.check()?;
        let remaining = {
            let ready_at = LEDGER_SIGNING_READY_AT
                .lock()
                .map_err(|_| "Ledger signing cooldown lock was poisoned".to_string())?;
            signing_status_cooldown_remaining(*ready_at, Instant::now())
        };
        if remaining.is_zero() {
            return Ok(());
        }
        thread::sleep(remaining.min(SIGNING_STATUS_POLL_INTERVAL));
    }
}

#[cfg(target_os = "macos")]
fn signing_status_cooldown_remaining(ready_at: Option<Instant>, now: Instant) -> Duration {
    ready_at
        .map(|ready_at| ready_at.saturating_duration_since(now))
        .unwrap_or_default()
}

fn classify_operation_state(cancelled: bool, timed_out: bool) -> Result<(), String> {
    if cancelled {
        Err("Ledger operation was cancelled. Retry when ready.".into())
    } else if timed_out {
        Err(
            "Ledger operation timed out waiting for the device. Reopen the Zcash app and retry."
                .into(),
        )
    } else {
        Ok(())
    }
}

#[cfg(not(target_os = "macos"))]
fn unsupported_platform() -> String {
    "Ledger desktop PoC is currently supported only on macOS".into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use pczt::roles::{
        creator::Creator, io_finalizer::IoFinalizer, updater::Updater, verifier::Verifier,
    };
    use transparent::{
        address::TransparentAddress,
        bundle::{OutPoint, TxOut},
    };
    use voting_crypto_deps::rand::rngs::OsRng;
    use zcash_primitives::transaction::{
        builder::{BuildConfig, Builder, BundlePadding, PcztResult},
        fees::zip317,
    };
    use zcash_protocol::{
        consensus::{BlockHeight, NetworkType, NetworkUpgrade, Parameters},
        value::Zatoshis,
    };

    #[test]
    fn cancellation_targets_only_the_active_operation_generation() {
        let state = OperationState::new();
        let first = state.begin();
        state.cancel_active();
        assert!(state.is_cancelled(first));
        state.finish(first);

        let retry = state.begin();
        assert_ne!(retry, first);
        assert!(!state.is_cancelled(retry));
        state.cancel_active();
        assert!(state.is_cancelled(retry));
        state.finish(retry);
    }

    #[test]
    fn cancellation_with_no_active_operation_does_not_cancel_the_next_one() {
        let state = OperationState::new();
        state.cancel_active();
        let generation = state.begin();
        assert!(!state.is_cancelled(generation));
        state.finish(generation);
    }

    #[test]
    fn operation_abort_errors_are_actionable_and_prefer_cancellation() {
        assert_eq!(classify_operation_state(false, false), Ok(()));
        assert!(classify_operation_state(true, false)
            .unwrap_err()
            .contains("cancelled"));
        assert!(classify_operation_state(false, true)
            .unwrap_err()
            .contains("timed out"));
        assert!(classify_operation_state(true, true)
            .unwrap_err()
            .contains("cancelled"));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn signing_status_cooldown_only_waits_until_the_device_can_receive_apdus() {
        let now = Instant::now();
        assert_eq!(signing_status_cooldown_remaining(None, now), Duration::ZERO);
        assert_eq!(
            signing_status_cooldown_remaining(Some(now + Duration::from_secs(4)), now),
            Duration::from_secs(4)
        );
        assert_eq!(
            signing_status_cooldown_remaining(Some(now), now + Duration::from_millis(1)),
            Duration::ZERO
        );
    }

    #[test]
    fn recognizes_all_dashboard_names_used_by_ledger_os() {
        assert!(is_dashboard_app("BOLOS"));
        assert!(is_dashboard_app("OLOS"));
        assert!(is_dashboard_app("OLOS\0"));
        assert!(!is_dashboard_app("Zcash"));
        assert!(!is_dashboard_app("Bitcoin"));
    }

    #[test]
    fn app_transition_retries_transport_and_busy_errors_only() {
        assert!(!is_terminal_app_transition_error("No Ledger device found"));
        assert!(!is_terminal_app_transition_error(
            "Ledger device is busy switching apps; retry shortly"
        ));
        assert!(is_terminal_app_transition_error("Ledger device is locked"));
        assert!(is_terminal_app_transition_error(
            "The Zcash app is not installed on this Ledger"
        ));
        assert!(is_terminal_app_transition_error(
            "Ledger request was rejected on the device"
        ));
    }

    #[derive(Clone, Copy, Debug)]
    struct PreNu6_3TestNetwork;

    impl Parameters for PreNu6_3TestNetwork {
        fn network_type(&self) -> NetworkType {
            NetworkType::Test
        }

        fn activation_height(&self, nu: NetworkUpgrade) -> Option<BlockHeight> {
            match nu {
                NetworkUpgrade::Nu6_3 => None,
                _ => Some(BlockHeight::from_u32(1)),
            }
        }
    }

    fn transparent_pczt() -> (Vec<u8>, secp256k1::SecretKey, [u8; 33]) {
        let sk = secp256k1::SecretKey::from_slice(&[7; 32]).unwrap();
        let secp = secp256k1::Secp256k1::new();
        let pubkey = sk.public_key(&secp);
        let pubkey_bytes = pubkey.serialize();
        let address = TransparentAddress::from_pubkey(&pubkey);

        let mut builder = Builder::new(
            PreNu6_3TestNetwork,
            100.into(),
            BuildConfig::Standard {
                sapling_anchor: None,
                orchard_anchor: None,
                ironwood_anchor: None,
                orchard_padding: BundlePadding::DEFAULT,
                ironwood_padding: BundlePadding::DEFAULT,
            },
        );
        builder
            .add_transparent_p2pkh_input(
                pubkey,
                OutPoint::new([1; 32], 0),
                TxOut::new(Zatoshis::const_from_u64(1_000_000), address.script().into()),
            )
            .unwrap();
        builder
            .add_transparent_output(&address, Zatoshis::const_from_u64(990_000))
            .unwrap();
        let PcztResult { pczt_parts, .. } = builder
            .build_for_pczt(OsRng, &zip317::FeeRule::standard())
            .unwrap();
        let pczt = IoFinalizer::new(Creator::build_from_parts(pczt_parts).unwrap())
            .finalize_io()
            .unwrap();

        let derivation = transparent::pczt::Bip32Derivation::parse(
            [0x22; 32],
            vec![0x8000_002c, 0x8000_0001, 0x8000_0000, 0, 0],
        )
        .unwrap();
        let pczt = Updater::new(pczt)
            .update_transparent_with(|mut bundle| {
                bundle.update_input_with(0, |mut input| {
                    input.set_bip32_derivation(pubkey_bytes, derivation);
                    Ok(())
                })
            })
            .unwrap()
            .finish();

        (pczt.serialize().unwrap(), sk, pubkey_bytes)
    }

    #[test]
    fn applies_and_validates_transparent_signature() {
        let (pczt_bytes, sk, pubkey) = transparent_pczt();
        let parsed = parse_pczt(&pczt_bytes).unwrap();
        let sighash = Signer::new(pczt::Pczt::parse(&pczt_bytes).unwrap())
            .unwrap()
            .transparent_sighash(0)
            .unwrap();
        let secp = secp256k1::Secp256k1::new();
        let signature = secp.sign_ecdsa(&secp256k1::Message::from_digest(sighash), &sk);
        let mut ledger_der = signature.serialize_der().to_vec();
        ledger_der[0] |= 1;

        let signed_bytes = apply_signatures(
            &pczt_bytes,
            &parsed,
            &[TransparentInputSignature {
                signature: ledger_der,
                sighash_type: 1,
            }],
            &[],
        )
        .unwrap();

        let signed = pczt::Pczt::parse(&signed_bytes).unwrap();
        let mut stored_signature = None;
        Verifier::new(signed)
            .with_transparent::<String, _>(|bundle| {
                stored_signature = bundle.inputs()[0]
                    .partial_signatures()
                    .get(&pubkey)
                    .cloned();
                Ok(())
            })
            .unwrap();
        let stored_signature = stored_signature.expect("transparent signature is stored");
        assert_eq!(stored_signature.last(), Some(&1));
    }

    #[test]
    fn pczt_signing_is_bound_to_the_selected_account() {
        let (pczt_bytes, _, _) = transparent_pczt();
        let expected = ExpectedAccount {
            account_index: 0,
            coin_type: 1,
            seed_fingerprint: [0x22; 32],
        };
        validate_pczt_account(&pczt_bytes, expected).unwrap();

        let wrong_account = ExpectedAccount {
            account_index: 1,
            ..expected
        };
        assert!(validate_pczt_account(&pczt_bytes, wrong_account)
            .unwrap_err()
            .contains("does not belong to account 1"));

        let wrong_fingerprint = ExpectedAccount {
            seed_fingerprint: [0x23; 32],
            ..expected
        };
        assert!(validate_pczt_account(&pczt_bytes, wrong_fingerprint)
            .unwrap_err()
            .contains("fingerprint"));
    }

    #[test]
    fn zip320_ephemeral_scope_is_allowed_only_for_transparent_inputs() {
        let expected = ExpectedAccount {
            account_index: 0,
            coin_type: 1,
            seed_fingerprint: [0x22; 32],
        };
        let derivation = parse::Bip32Derivation {
            pubkey: [0x02; 33],
            signing_path: vec![0x8000_002c, 0x8000_0001, 0x8000_0000, 2, 7],
            seed_fingerprint: [0x22; 32],
        };

        validate_transparent_derivation(&derivation, expected, "transparent input 0", true)
            .unwrap();
        assert!(validate_transparent_derivation(
            &derivation,
            expected,
            "transparent output 0",
            false,
        )
        .unwrap_err()
        .contains("does not belong"));

        let mut unrelated = derivation.clone();
        unrelated.signing_path[3] = 3;
        assert!(
            validate_transparent_derivation(&unrelated, expected, "transparent input 0", true,)
                .is_err()
        );
    }

    #[test]
    fn rejects_transparent_signature_with_wrong_sighash_type() {
        let (pczt_bytes, _, _) = transparent_pczt();
        let parsed = parse_pczt(&pczt_bytes).unwrap();
        let error = apply_signatures(
            &pczt_bytes,
            &parsed,
            &[TransparentInputSignature {
                signature: vec![0x30],
                sighash_type: 2,
            }],
            &[],
        )
        .unwrap_err();
        assert!(error.contains("used sighash type"));
    }

    #[test]
    fn shielded_only_api_rejects_transparent_inputs_before_transport() {
        let (pczt_bytes, _, _) = transparent_pczt();
        assert!(sign_pczt(&pczt_bytes)
            .unwrap_err()
            .contains("use sign_pczt_full"));
    }

    #[test]
    fn full_plan_flattens_pczt_packets_before_transparent_requests() {
        let (pczt_bytes, _, _) = transparent_pczt();
        let commands = build_pczt_full_signing_plan(&pczt_bytes).unwrap();

        assert_eq!(commands.first().map(|command| command.ins), Some(0x52));
        assert_eq!(commands.last().map(|command| command.ins), Some(0x55));
        assert_eq!(commands.last().map(|command| command.p2), Some(0));
        assert!(commands[..commands.len() - 1]
            .iter()
            .all(|command| matches!(command.ins, 0x52 | 0x53 | 0x54 | 0x56)));
    }

    #[test]
    fn short_mobile_exchange_preserves_terminal_status_error() {
        let (pczt_bytes, _, _) = transparent_pczt();
        let commands = build_pczt_full_signing_plan(&pczt_bytes).unwrap();
        let mut responses = vec![vec![0x90, 0]; commands.len() - 2];
        responses.push(vec![0x69, 0x85]);

        let error = finalize_pczt_full_signing(&pczt_bytes, &responses).unwrap_err();
        assert!(error.contains("rejected"), "{error}");
        assert!(!error.contains("response(s)"), "{error}");
    }

    #[test]
    fn short_successful_mobile_exchange_reports_response_count() {
        let (pczt_bytes, _, _) = transparent_pczt();
        let commands = build_pczt_full_signing_plan(&pczt_bytes).unwrap();
        let responses = vec![vec![0x90, 0]; commands.len() - 1];

        assert!(finalize_pczt_full_signing(&pczt_bytes, &responses)
            .unwrap_err()
            .contains("response(s)"));
    }

    #[test]
    fn decodes_ordered_transparent_orchard_and_ironwood_responses() {
        let commands = vec![
            ApduCommand {
                cla: ZCASH_CLA,
                ins: 0x52,
                p1: 0,
                p2: 0,
                data: vec![1],
            },
            ApduCommand {
                cla: ZCASH_CLA,
                ins: 0x55,
                p1: 0,
                p2: 0,
                data: vec![],
            },
            ApduCommand {
                cla: ZCASH_CLA,
                ins: 0x57,
                p1: 0,
                p2: 2,
                data: vec![],
            },
            ApduCommand {
                cla: ZCASH_CLA,
                ins: 0x59,
                p1: 0,
                p2: 3,
                data: vec![],
            },
        ];
        let requests = vec![
            SignatureRequest::Transparent { input_index: 0 },
            SignatureRequest::Shielded {
                pool: ValuePool::Orchard,
                action_index: 2,
                instruction: 0x57,
            },
            SignatureRequest::Shielded {
                pool: ValuePool::Ironwood,
                action_index: 3,
                instruction: 0x59,
            },
        ];
        let mut der = vec![0x30, 0x06, 0x02, 0x01, 1, 0x02, 0x01, 1, 1];
        der.extend_from_slice(&[0x90, 0]);
        let mut orchard = vec![0x11; 64];
        orchard.extend_from_slice(&[0x90, 0]);
        let mut ironwood = vec![0x22; 64];
        ironwood.extend_from_slice(&[0x90, 0]);

        let (transparent, shielded) = decode_signing_responses(
            &commands,
            &requests,
            &[vec![0x90, 0], der, orchard, ironwood],
        )
        .unwrap();

        assert_eq!(transparent.len(), 1);
        assert_eq!(transparent[0].sighash_type, 1);
        assert_eq!(shielded.len(), 2);
        assert_eq!(shielded[0].value_pool(), ValuePool::Orchard);
        assert_eq!(shielded[0].action_index(), 2);
        assert_eq!(shielded[1].value_pool(), ValuePool::Ironwood);
        assert_eq!(shielded[1].action_index(), 3);
    }
}
