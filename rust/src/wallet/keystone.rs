//! Keystone hardware wallet integration.
//!
//! Provides UR encoding/decoding for QR-based Keystone communication.
//! Uses PCZT (ZIP-332) for transaction signing.

use ur_registry::traits::RegistryItem;
use ur_registry::zcash::zcash_accounts::ZcashAccounts;
use ur_registry::zcash::zcash_pczt::ZcashPczt;

// ==================== Data Types ====================

#[derive(Debug, Clone)]
pub struct KeystoneAccountInfo {
    pub name: String,
    pub ufvk: String,
    pub index: u32,
    pub seed_fingerprint: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct ZcashBatchMessageInput {
    pub id: String,
    pub pczt_bytes: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct ZcashBatchSignResult {
    pub version: u32,
    pub request_id: String,
    pub results: Vec<ZcashBatchSignedMessage>,
}

#[derive(Debug, Clone)]
pub struct ZcashBatchSignedMessage {
    pub id: String,
    pub status: u32,
    pub kind: u32,
    pub signed_pczt_bytes: Vec<u8>,
    pub payload_digest_hex: String,
}

/// Pool discriminant for a decoded [`DecodedActionSig`]: an Orchard action
/// signature. Mirrors the `zcash-batch-sig-result` wire value, narrowed to the `u8`
/// the wallet uses internally.
pub(crate) const DECODED_SIG_POOL_ORCHARD: u8 = 0;
/// Pool discriminant for a decoded [`DecodedActionSig`]: an Ironwood action
/// signature. Mirrors the `zcash-batch-sig-result` wire value, narrowed to the `u8`
/// the wallet uses internally.
pub(crate) const DECODED_SIG_POOL_IRONWOOD: u8 = 1;

/// A wallet-layer decoding of a Keystone "signatures-only" response
/// (`zcash-batch-sig-result`, UR tag 49207). Unlike [`ZcashBatchSignResult`], which
/// echoes whole redacted PCZTs back, this carries only the produced
/// signatures, correlated to each request message by id and to each spend by
/// pool and action index. The wallet re-applies these to the proofs-PCZTs it
/// already holds (see `sync::pczt::apply_sigs_and_extract`).
#[derive(Debug, Clone)]
pub struct DecodedSigResult {
    pub version: u32,
    pub request_id: Vec<u8>,
    pub results: Vec<DecodedMsgSig>,
}

/// The signatures produced for a single request message, correlated by
/// `message_id` (the same id the wallet assigned when it built the batch).
#[derive(Debug, Clone)]
pub struct DecodedMsgSig {
    pub message_id: Vec<u8>,
    pub sigs: Vec<DecodedActionSig>,
}

/// A single spend-authorization signature located by `pool`
/// ([`DECODED_SIG_POOL_ORCHARD`] / [`DECODED_SIG_POOL_IRONWOOD`]) and the spend
/// action's index within that pool's bundle.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodedActionSig {
    pub pool: u8,
    pub action_index: u32,
    pub sig: [u8; 64],
}

/// Fixed serialized size of one [`DecodedActionSig`] in the compact storage
/// blob: `pool` (1) + `action_index` little-endian u32 (4) + `sig` (64).
const COMPACT_ACTION_SIG_LEN: usize = 1 + 4 + ZCASH_SIG_LEN;

/// Serialize a per-message signature list to a compact, self-describing byte
/// blob for the encrypted migration DB column.
///
/// The migration store already encrypts an opaque `Vec<u8>` per signed child;
/// this lets the "signatures-only" round-trip persist just the produced
/// signatures (a handful of 69-byte records) in place of a full signed PCZT,
/// shrinking that column substantially. The wire layout is a u32 little-endian
/// count followed by that many `[pool:u8][action_index:u32 le][sig:64]` records.
pub(crate) fn encode_compact_action_sigs(sigs: &[DecodedActionSig]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + sigs.len() * COMPACT_ACTION_SIG_LEN);
    out.extend_from_slice(&(sigs.len() as u32).to_le_bytes());
    for sig in sigs {
        out.push(sig.pool);
        out.extend_from_slice(&sig.action_index.to_le_bytes());
        out.extend_from_slice(&sig.sig);
    }
    out
}

/// Decode a compact signature blob produced by [`encode_compact_action_sigs`].
pub(crate) fn decode_compact_action_sigs(bytes: &[u8]) -> Result<Vec<DecodedActionSig>, String> {
    if bytes.len() < 4 {
        return Err("Compact signature blob is too short for its count header".to_string());
    }
    let count = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as usize;
    let body = &bytes[4..];
    let expected = count
        .checked_mul(COMPACT_ACTION_SIG_LEN)
        .ok_or("Compact signature blob length overflow")?;
    if body.len() != expected {
        return Err(format!(
            "Compact signature blob has {} body bytes, expected {expected} for {count} signatures",
            body.len()
        ));
    }

    let mut sigs = Vec::with_capacity(count);
    for record in body.chunks_exact(COMPACT_ACTION_SIG_LEN) {
        let pool = record[0];
        let action_index = u32::from_le_bytes([record[1], record[2], record[3], record[4]]);
        let sig: [u8; ZCASH_SIG_LEN] = record[5..]
            .try_into()
            .map_err(|_| "Compact signature record has wrong signature length".to_string())?;
        sigs.push(DecodedActionSig {
            pool,
            action_index,
            sig,
        });
    }
    Ok(sigs)
}

const ZCASH_SIGN_BATCH_TYPE: &str = "zcash-sign-batch";
const ZCASH_SIGN_BATCH_VERSION: u32 = 1;
const ZCASH_SIGN_BATCH_NETWORK_MAINNET: u32 = 1;
const ZCASH_SIGN_MESSAGE_KIND_PCZT_V1: u32 = 1;
const ZCASH_SIGN_STATUS_SIGNED: u32 = 0;
pub(crate) const ZCASH_SIGN_BATCH_MAX_MESSAGES: usize = 35;

// `zcash-batch-sig-result` (UR tag 49207) wire constants. The registry CBOR shape is
// `{1: version, 2: request_id, 3: results: [{1: message_id, 2: sigs:
// [{1: pool, 2: action_index, 3: sig}]}]}`.
const ZCASH_SIG_RESULT_VERSION: u32 = 1;
const ZCASH_SIG_POOL_ORCHARD: u32 = 0;
const ZCASH_SIG_POOL_IRONWOOD: u32 = 1;
/// A Zcash spend-authorization signature is a 64-byte RedPallas signature.
const ZCASH_SIG_LEN: usize = 64;

// ==================== UR Encoding/Decoding ====================

/// Decode a single-part UR string into the raw CBOR bytes for the given
/// registry type. Wraps `ur::decode` and enforces that the decoded UR is
/// single-part (multi-part handled by `decode_ur_part`).
fn decode_single_part_ur(ur_string: &str) -> Result<Vec<u8>, String> {
    // ur crate requires lowercase scheme
    let (kind, cbor) =
        ur::decode(&ur_string.to_lowercase()).map_err(|e| format!("UR decode failed: {e}"))?;
    match kind {
        ur::ur::Kind::SinglePart => Ok(cbor),
        ur::ur::Kind::MultiPart => Err("Expected single-part UR, got multi-part".into()),
    }
}

/// Encode PCZT bytes as a single-part UR string for QR display.
pub fn encode_pczt_to_ur(pczt_bytes: &[u8]) -> Result<String, String> {
    let zcash_pczt = ZcashPczt::new(pczt_bytes.to_vec());
    let cbor_bytes: Vec<u8> = zcash_pczt
        .try_into()
        .map_err(|e: ur_registry::error::URError| format!("CBOR encode failed: {e:?}"))?;
    let mut encoder = ur::Encoder::new(
        &cbor_bytes,
        cbor_bytes.len(), // single part
        ZcashPczt::get_registry_type().get_type(),
    )
    .map_err(|e| format!("UR encode failed: {e}"))?;
    let ur_string = encoder
        .next_part()
        .map_err(|e| format!("UR next_part failed: {e}"))?;
    Ok(ur_string.to_uppercase())
}

/// Decode a single-part UR string from QR scan to PCZT bytes.
pub fn decode_ur_to_pczt(ur_string: &str) -> Result<Vec<u8>, String> {
    let cbor = decode_single_part_ur(ur_string)?;
    let pczt: ZcashPczt = cbor
        .try_into()
        .map_err(|e: ur_registry::error::URError| format!("CBOR decode failed: {e:?}"))?;
    Ok(pczt.get_data())
}

/// Decode a single-part UR string containing ZcashAccounts.
pub fn decode_accounts_ur(ur_string: &str) -> Result<(Vec<u8>, Vec<KeystoneAccountInfo>), String> {
    let cbor = decode_single_part_ur(ur_string)?;
    let accounts: ZcashAccounts = cbor
        .try_into()
        .map_err(|e: ur_registry::error::URError| format!("CBOR decode failed: {e:?}"))?;

    let seed_fp = accounts.get_seed_fingerprint();
    let infos: Vec<KeystoneAccountInfo> = accounts
        .get_accounts()
        .iter()
        .map(|a| KeystoneAccountInfo {
            name: a
                .get_name()
                .unwrap_or_else(|| format!("Keystone {}", a.get_index())),
            ufvk: a.get_ufvk(),
            index: a.get_index(),
            seed_fingerprint: seed_fp.clone(),
        })
        .collect();

    Ok((seed_fp, infos))
}

/// Return the shielded input nullifiers used by a PCZT.
///
/// Batch debug flows use this to catch conflicting proposals before the user
/// signs multiple transactions that would double-spend each other.
pub fn pczt_spend_nullifiers(pczt_bytes: &[u8]) -> Result<Vec<String>, String> {
    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("PCZT parse: {e:?}"))?;
    let mut nullifiers = Vec::new();

    for spend in pczt.sapling().spends() {
        nullifiers.push(format!("sapling:{}", hex::encode(spend.nullifier())));
    }
    for action in pczt.orchard().actions() {
        nullifiers.push(format!(
            "orchard:{}",
            hex::encode(action.spend().nullifier())
        ));
    }

    Ok(nullifiers)
}

// ==================== Multi-part UR (Animated QR) ====================

use std::sync::Mutex;

/// In-flight multi-part UR scan session. Holds both the decoder and the
/// UR type it was initialized with so we can detect (and auto-reset on) a
/// fresh scan of a different type.
struct UrSession {
    decoder: ur::Decoder,
    ur_type: String,
}

/// Global stateful UR scan session. `None` means no session in flight.
/// Uses ur::Decoder directly instead of KeystoneURDecoder to avoid
/// URType registration issues (zcash-accounts not in URType::from()).
static UR_SESSION: std::sync::LazyLock<Mutex<Option<UrSession>>> =
    std::sync::LazyLock::new(|| Mutex::new(None));

pub struct UrDecodeResult {
    pub complete: bool,
    pub progress: u32,
    pub data: Option<Vec<u8>>,
    pub ur_type: Option<String>,
}

/// Extract the UR type (e.g. `"zcash-pczt"`) from a lowercased UR string.
fn parse_ur_type(part_lower: &str) -> Option<&str> {
    part_lower
        .strip_prefix("ur:")
        .and_then(|s| s.split('/').next())
}

/// Discard any in-flight multi-part UR decode state. Called by the scan
/// screen on entry so each new scan starts from a clean slate regardless
/// of how the previous scan ended (cancel, back button, mid-stream error).
pub fn reset_ur_session() {
    if let Ok(mut guard) = UR_SESSION.lock() {
        *guard = None;
    }
}

/// Feed one UR part from a QR frame into the active scan session.
///
/// `expected_ur_type` pins the scan to one UR registry type (e.g.
/// `"zcash-pczt"` or `"zcash-accounts"`). If a part arrives with a different
/// type, this returns an error — catching scan-of-wrong-code up front instead
/// of producing a confusing CBOR decode failure later.
///
/// The session auto-resets when (a) a new scan starts, (b) the expected type
/// changes from the in-flight one, or (c) the multi-part decoder completes.
/// Callers never need to reset manually.
pub fn decode_ur_part(part: &str, expected_ur_type: &str) -> Result<UrDecodeResult, String> {
    let mut session_guard = UR_SESSION.lock().map_err(|e| format!("Lock: {e}"))?;

    // ur crate requires lowercase scheme
    let part_lower = part.to_lowercase();

    let part_type =
        parse_ur_type(&part_lower).ok_or_else(|| "Invalid UR: missing type prefix".to_string())?;

    if part_type != expected_ur_type {
        return Err(format!(
            "Unexpected UR type: got {part_type:?}, expected {expected_ur_type:?}"
        ));
    }

    // If there's an in-flight session for a different type, discard it —
    // we're starting a new scan.
    if session_guard
        .as_ref()
        .is_some_and(|s| s.ur_type != expected_ur_type)
    {
        *session_guard = None;
    }

    // Initialize decoder on the first part of a new session.
    if session_guard.is_none() {
        let (kind, cbor) = ur::decode(&part_lower).map_err(|e| format!("UR decode: {e}"))?;

        match kind {
            ur::ur::Kind::SinglePart => {
                log::info!(
                    "keystone: single-part UR decoded ({} bytes, type={expected_ur_type})",
                    cbor.len()
                );
                return Ok(UrDecodeResult {
                    complete: true,
                    progress: 100,
                    data: Some(cbor),
                    ur_type: Some(expected_ur_type.to_string()),
                });
            }
            ur::ur::Kind::MultiPart => {
                let mut decoder = ur::Decoder::default();
                decoder
                    .receive(&part_lower)
                    .map_err(|e| format!("UR receive: {e}"))?;
                let progress = decoder.progress();
                log::info!(
                    "keystone: multi-part UR started (type={expected_ur_type}, progress={progress}%)"
                );
                *session_guard = Some(UrSession {
                    decoder,
                    ur_type: expected_ur_type.to_string(),
                });
                return Ok(UrDecodeResult {
                    complete: false,
                    progress: progress as u32,
                    data: None,
                    ur_type: Some(expected_ur_type.to_string()),
                });
            }
        }
    }

    // Subsequent parts — feed to existing decoder. If the decoder rejects a
    // same-type fragment, treat the session as corrupted and force the caller
    // to restart from a clean fountain-code state.
    let receive_result = {
        let session = session_guard.as_mut().unwrap();
        session.decoder.receive(&part_lower)
    };
    if let Err(e) = receive_result {
        *session_guard = None;
        return Err(format!("UR session reset: UR receive: {e}"));
    }

    if session_guard.as_ref().unwrap().decoder.complete() {
        let message_result = {
            let session = session_guard.as_mut().unwrap();
            session.decoder.message()
        };
        let cbor = match message_result {
            Ok(Some(cbor)) => cbor,
            Ok(None) => {
                *session_guard = None;
                return Err("UR session reset: Decoder complete but no message".to_string());
            }
            Err(e) => {
                *session_guard = None;
                return Err(format!("UR session reset: UR message: {e}"));
            }
        };
        log::info!(
            "keystone: multi-part UR complete ({} bytes, type={expected_ur_type})",
            cbor.len()
        );
        *session_guard = None; // auto-reset for next scan
        return Ok(UrDecodeResult {
            complete: true,
            progress: 100,
            data: Some(cbor),
            ur_type: Some(expected_ur_type.to_string()),
        });
    }

    let progress = session_guard.as_ref().unwrap().decoder.progress();
    Ok(UrDecodeResult {
        complete: false,
        progress: progress as u32,
        data: None,
        ur_type: Some(expected_ur_type.to_string()),
    })
}

/// Number of animated-QR parts to emit for a UR whose payload spans
/// `fragment_count` fragments. The encoder emits the pure fragments first; using
/// a short fountain tail lets the scanner recover from a missed frame without
/// forcing the user to wait for a full loop.
fn ur_part_count(fragment_count: usize) -> usize {
    if fragment_count <= 1 {
        return fragment_count;
    }

    let redundant_parts = fragment_count.div_ceil(10).max(2);
    fragment_count + redundant_parts
}

/// Encode PCZT bytes into multiple UR parts for animated QR display.
pub fn encode_pczt_ur_parts(
    pczt_bytes: &[u8],
    max_fragment_len: usize,
) -> Result<Vec<String>, String> {
    let zcash_pczt = ZcashPczt::new(pczt_bytes.to_vec());
    let cbor_bytes: Vec<u8> = zcash_pczt
        .try_into()
        .map_err(|e: ur_registry::error::URError| format!("CBOR encode: {e:?}"))?;

    let mut encoder = ur::Encoder::new(
        &cbor_bytes,
        max_fragment_len,
        ZcashPczt::get_registry_type().get_type(),
    )
    .map_err(|e| format!("UR encoder: {e}"))?;

    let count = ur_part_count(encoder.fragment_count());
    let mut parts = Vec::with_capacity(count);
    for _ in 0..count {
        let part = encoder
            .next_part()
            .map_err(|e| format!("UR next_part: {e}"))?;
        parts.push(part.to_uppercase());
    }

    log::info!("keystone: encoded PCZT into {} UR parts", parts.len());
    Ok(parts)
}

/// Encode several redacted PCZTs into the local `zcash-sign-batch` UR used by
/// the Keystone batch-signing firmware branch.
pub fn encode_zcash_sign_batch_ur_parts(
    request_id: &str,
    messages: &[ZcashBatchMessageInput],
    max_fragment_len: usize,
) -> Result<Vec<String>, String> {
    if request_id.is_empty() {
        return Err("Zcash batch request id must not be empty".to_string());
    }
    if messages.is_empty() || messages.len() > ZCASH_SIGN_BATCH_MAX_MESSAGES {
        return Err(format!(
            "Zcash batch requires 1 to {ZCASH_SIGN_BATCH_MAX_MESSAGES} messages"
        ));
    }

    let mut ids = std::collections::HashSet::new();
    let mut payloads = std::collections::HashSet::new();
    for message in messages {
        if message.id.is_empty() {
            return Err("Zcash batch message id must not be empty".to_string());
        }
        if !ids.insert(message.id.as_bytes().to_vec()) {
            return Err(format!("Duplicate Zcash batch message id {}", message.id));
        }
        if message.pczt_bytes.is_empty() {
            return Err(format!(
                "Zcash batch message {} has an empty PCZT payload",
                message.id
            ));
        }
        if !payloads.insert(message.pczt_bytes.clone()) {
            return Err("Duplicate Zcash batch PCZT payload".to_string());
        }
    }

    let mut cbor = Vec::new();
    let mut encoder = minicbor::Encoder::new(&mut cbor);
    encoder
        .map(4)
        .map_err(|e| format!("CBOR encode batch map: {e}"))?
        .u8(1)
        .map_err(|e| format!("CBOR encode batch version key: {e}"))?
        .u32(ZCASH_SIGN_BATCH_VERSION)
        .map_err(|e| format!("CBOR encode batch version: {e}"))?
        .u8(2)
        .map_err(|e| format!("CBOR encode batch request id key: {e}"))?
        .bytes(request_id.as_bytes())
        .map_err(|e| format!("CBOR encode batch request id: {e}"))?
        .u8(3)
        .map_err(|e| format!("CBOR encode batch network key: {e}"))?
        .u32(ZCASH_SIGN_BATCH_NETWORK_MAINNET)
        .map_err(|e| format!("CBOR encode batch network: {e}"))?
        .u8(4)
        .map_err(|e| format!("CBOR encode batch messages key: {e}"))?
        .array(messages.len() as u64)
        .map_err(|e| format!("CBOR encode batch messages array: {e}"))?;

    for message in messages {
        encoder
            .map(3)
            .map_err(|e| format!("CBOR encode message map: {e}"))?
            .u8(1)
            .map_err(|e| format!("CBOR encode message id key: {e}"))?
            .bytes(message.id.as_bytes())
            .map_err(|e| format!("CBOR encode message id: {e}"))?
            .u8(2)
            .map_err(|e| format!("CBOR encode message kind key: {e}"))?
            .u32(ZCASH_SIGN_MESSAGE_KIND_PCZT_V1)
            .map_err(|e| format!("CBOR encode message kind: {e}"))?
            .u8(3)
            .map_err(|e| format!("CBOR encode message payload key: {e}"))?
            .bytes(&message.pczt_bytes)
            .map_err(|e| format!("CBOR encode message payload: {e}"))?;
    }

    let mut ur_encoder = ur::Encoder::new(&cbor, max_fragment_len, ZCASH_SIGN_BATCH_TYPE)
        .map_err(|e| format!("UR encoder: {e}"))?;
    let count = ur_part_count(ur_encoder.fragment_count());
    let mut parts = Vec::with_capacity(count);
    for _ in 0..count {
        let part = ur_encoder
            .next_part()
            .map_err(|e| format!("UR next_part: {e}"))?;
        parts.push(part.to_uppercase());
    }

    log::info!(
        "keystone: encoded Zcash sign batch into {} UR parts",
        parts.len()
    );
    Ok(parts)
}

/// Decode the raw CBOR payload from a `zcash-sign-result` UR.
pub fn decode_zcash_sign_result_cbor(cbor: &[u8]) -> Result<ZcashBatchSignResult, String> {
    let mut decoder = minicbor::Decoder::new(cbor);
    let len = required_len(decoder.map(), "zcash-sign-result map")?;
    let mut version = None;
    let mut request_id = None;
    let mut results = None;

    for _ in 0..len {
        match decoder
            .u8()
            .map_err(|e| format!("CBOR decode result key: {e}"))?
        {
            1 => {
                version = Some(
                    decoder
                        .u32()
                        .map_err(|e| format!("CBOR decode result version: {e}"))?,
                );
            }
            2 => {
                request_id = Some(decode_bytes_string(&mut decoder, "result request id")?);
            }
            3 => {
                results = Some(decode_signed_messages(&mut decoder)?);
            }
            _ => decoder
                .skip()
                .map_err(|e| format!("CBOR skip unknown result field: {e}"))?,
        }
    }

    if decoder.position() != cbor.len() {
        return Err("Trailing data after zcash-sign-result".to_string());
    }

    let version = version.ok_or_else(|| "Missing zcash-sign-result version".to_string())?;
    if version != ZCASH_SIGN_BATCH_VERSION {
        return Err(format!("Unsupported zcash-sign-result version {version}"));
    }

    Ok(ZcashBatchSignResult {
        version,
        request_id: request_id.ok_or_else(|| "Missing zcash-sign-result request id".to_string())?,
        results: results.ok_or_else(|| "Missing zcash-sign-result results".to_string())?,
    })
}

/// Decode the raw CBOR payload from a compact `zcash-batch-sig-result` UR (tag
/// 49207) into flat wallet structs.
///
/// The decode is hand-rolled with `minicbor`, mirroring
/// [`decode_zcash_sign_result_cbor`], because the pinned upstream `ur_registry`
/// has no container for this type. CBOR shape validation matches the registry
/// definition (required fields, duplicate map keys rejected, indefinite
/// lengths rejected, trailing data rejected, unknown keys skipped), and
/// wallet-side policy is enforced on top: a supported version, a known pool
/// discriminant (Orchard/Ironwood), the exact 64-byte spend-authorization
/// signature length, and no duplicate (pool, action index) within a message.
/// The result is correlated back to the wallet's held proofs-PCZTs by
/// `message_id` and applied via `sync::pczt::apply_sigs_and_extract`.
pub fn decode_zcash_sig_result_cbor(cbor: &[u8]) -> Result<DecodedSigResult, String> {
    let mut decoder = minicbor::Decoder::new(cbor);
    let len = required_len(decoder.map(), "zcash-batch-sig-result map")?;
    let mut version = None;
    let mut request_id = None;
    let mut results = None;

    let mut seen_keys = Vec::new();
    for _ in 0..len {
        let key = decoder
            .u8()
            .map_err(|e| format!("CBOR decode sig result key: {e}"))?;
        reject_duplicate_cbor_key(&mut seen_keys, key, "zcash-batch-sig-result map")?;
        match key {
            1 => {
                version = Some(
                    decoder
                        .u32()
                        .map_err(|e| format!("CBOR decode sig result version: {e}"))?,
                );
            }
            2 => {
                request_id = Some(
                    decoder
                        .bytes()
                        .map_err(|e| format!("CBOR decode sig result request id: {e}"))?
                        .to_vec(),
                );
            }
            3 => {
                results = Some(decode_msg_sigs(&mut decoder)?);
            }
            _ => decoder
                .skip()
                .map_err(|e| format!("CBOR skip unknown sig result field: {e}"))?,
        }
    }

    if decoder.position() != cbor.len() {
        return Err("Trailing data after zcash-batch-sig-result".to_string());
    }

    let version = version.ok_or_else(|| "Missing zcash-batch-sig-result version".to_string())?;
    if version != ZCASH_SIG_RESULT_VERSION {
        return Err(format!(
            "Unsupported zcash-batch-sig-result version {version}"
        ));
    }

    Ok(DecodedSigResult {
        version,
        request_id: request_id
            .ok_or_else(|| "Missing zcash-batch-sig-result request id".to_string())?,
        results: results.ok_or_else(|| "Missing zcash-batch-sig-result results".to_string())?,
    })
}

/// Decode the `results` array of a `zcash-batch-sig-result`: one [`DecodedMsgSig`]
/// per signed request message.
fn decode_msg_sigs(decoder: &mut minicbor::Decoder<'_>) -> Result<Vec<DecodedMsgSig>, String> {
    let len = required_len(decoder.array(), "zcash-batch-sig-result results array")?;

    // Do not pre-allocate from the wire-claimed length; a malformed length
    // fails on the first missing element instead of reserving memory.
    let mut results = Vec::new();
    for _ in 0..len {
        results.push(decode_msg_sig(decoder)?);
    }
    Ok(results)
}

/// Decode one per-message signature map (`{1: message_id, 2: sigs}`),
/// enforcing the wallet policy documented on [`decode_zcash_sig_result_cbor`].
fn decode_msg_sig(decoder: &mut minicbor::Decoder<'_>) -> Result<DecodedMsgSig, String> {
    let len = required_len(decoder.map(), "zcash-msg-sig map")?;
    let mut message_id = None;
    let mut sigs = None;

    let mut seen_keys = Vec::new();
    for _ in 0..len {
        let key = decoder
            .u8()
            .map_err(|e| format!("CBOR decode msg sig key: {e}"))?;
        reject_duplicate_cbor_key(&mut seen_keys, key, "zcash-msg-sig map")?;
        match key {
            1 => {
                message_id = Some(
                    decoder
                        .bytes()
                        .map_err(|e| format!("CBOR decode msg sig message id: {e}"))?
                        .to_vec(),
                );
            }
            2 => {
                sigs = Some(decode_action_sigs(decoder)?);
            }
            _ => decoder
                .skip()
                .map_err(|e| format!("CBOR skip unknown msg sig field: {e}"))?,
        }
    }

    Ok(DecodedMsgSig {
        message_id: message_id.ok_or_else(|| "Missing zcash-msg-sig message id".to_string())?,
        sigs: sigs.ok_or_else(|| "Missing zcash-msg-sig sigs".to_string())?,
    })
}

/// Decode the `sigs` array of one message, rejecting duplicate
/// (pool, action index) entries — a device must produce at most one
/// spend-authorization signature per spend action.
fn decode_action_sigs(
    decoder: &mut minicbor::Decoder<'_>,
) -> Result<Vec<DecodedActionSig>, String> {
    let len = required_len(decoder.array(), "zcash-msg-sig sigs array")?;

    let mut seen_sigs = std::collections::HashSet::new();
    let mut sigs = Vec::new();
    for _ in 0..len {
        let sig = decode_action_sig(decoder)?;
        if !seen_sigs.insert((sig.pool, sig.action_index)) {
            return Err(format!(
                "Duplicate zcash-batch-sig-result signature for pool {} action {}",
                sig.pool, sig.action_index
            ));
        }
        sigs.push(sig);
    }
    Ok(sigs)
}

/// Decode one action-signature map (`{1: pool, 2: action_index, 3: sig}`),
/// enforcing a known pool discriminant and the exact 64-byte signature length.
fn decode_action_sig(decoder: &mut minicbor::Decoder<'_>) -> Result<DecodedActionSig, String> {
    let len = required_len(decoder.map(), "zcash-action-sig map")?;
    let mut pool = None;
    let mut action_index = None;
    let mut sig = None;

    let mut seen_keys = Vec::new();
    for _ in 0..len {
        let key = decoder
            .u8()
            .map_err(|e| format!("CBOR decode action sig key: {e}"))?;
        reject_duplicate_cbor_key(&mut seen_keys, key, "zcash-action-sig map")?;
        match key {
            1 => {
                pool = Some(
                    decoder
                        .u32()
                        .map_err(|e| format!("CBOR decode action sig pool: {e}"))?,
                );
            }
            2 => {
                action_index = Some(
                    decoder
                        .u32()
                        .map_err(|e| format!("CBOR decode action sig index: {e}"))?,
                );
            }
            3 => {
                sig = Some(
                    decoder
                        .bytes()
                        .map_err(|e| format!("CBOR decode action sig bytes: {e}"))?
                        .to_vec(),
                );
            }
            _ => decoder
                .skip()
                .map_err(|e| format!("CBOR skip unknown action sig field: {e}"))?,
        }
    }

    let pool = match pool.ok_or_else(|| "Missing zcash-action-sig pool".to_string())? {
        ZCASH_SIG_POOL_ORCHARD => DECODED_SIG_POOL_ORCHARD,
        ZCASH_SIG_POOL_IRONWOOD => DECODED_SIG_POOL_IRONWOOD,
        other => return Err(format!("Unsupported zcash-batch-sig-result pool {other}")),
    };
    let action_index =
        action_index.ok_or_else(|| "Missing zcash-action-sig action index".to_string())?;
    let sig_bytes = sig.ok_or_else(|| "Missing zcash-action-sig sig".to_string())?;
    let sig: [u8; ZCASH_SIG_LEN] = sig_bytes.as_slice().try_into().map_err(|_| {
        format!(
            "zcash-batch-sig-result signature must be {ZCASH_SIG_LEN} bytes, got {}",
            sig_bytes.len()
        )
    })?;

    Ok(DecodedActionSig {
        pool,
        action_index,
        sig,
    })
}

/// Reject a duplicate CBOR map key, recording each seen key. The registry
/// definition of `zcash-batch-sig-result` rejects duplicate map keys so a re-sent
/// field can never silently overwrite an earlier value.
fn reject_duplicate_cbor_key(seen_keys: &mut Vec<u8>, key: u8, label: &str) -> Result<(), String> {
    if seen_keys.contains(&key) {
        return Err(format!("Duplicate key {key} in {label}"));
    }
    seen_keys.push(key);
    Ok(())
}

fn decode_signed_messages(
    decoder: &mut minicbor::Decoder<'_>,
) -> Result<Vec<ZcashBatchSignedMessage>, String> {
    let len = required_len(decoder.array(), "zcash-sign-result results array")?;
    if len == 0 || len as usize > ZCASH_SIGN_BATCH_MAX_MESSAGES {
        return Err(format!(
            "zcash-sign-result must contain 1 to {ZCASH_SIGN_BATCH_MAX_MESSAGES} results"
        ));
    }

    let mut results = Vec::with_capacity(len as usize);
    for _ in 0..len {
        results.push(decode_signed_message(decoder)?);
    }
    Ok(results)
}

fn decode_signed_message(
    decoder: &mut minicbor::Decoder<'_>,
) -> Result<ZcashBatchSignedMessage, String> {
    let len = required_len(decoder.map(), "zcash-sign-message-result map")?;
    let mut id = None;
    let mut status = None;
    let mut kind = None;
    let mut payload = None;
    let mut digest = None;

    for _ in 0..len {
        match decoder
            .u8()
            .map_err(|e| format!("CBOR decode message result key: {e}"))?
        {
            1 => id = Some(decode_bytes_string(decoder, "message result id")?),
            2 => {
                status = Some(
                    decoder
                        .u32()
                        .map_err(|e| format!("CBOR decode message result status: {e}"))?,
                );
            }
            3 => {
                kind = Some(
                    decoder
                        .u32()
                        .map_err(|e| format!("CBOR decode message result kind: {e}"))?,
                );
            }
            4 => {
                payload = Some(
                    decoder
                        .bytes()
                        .map_err(|e| format!("CBOR decode message result payload: {e}"))?
                        .to_vec(),
                );
            }
            6 => {
                digest = Some(
                    decoder
                        .bytes()
                        .map_err(|e| format!("CBOR decode message result digest: {e}"))?
                        .to_vec(),
                );
            }
            _ => decoder
                .skip()
                .map_err(|e| format!("CBOR skip unknown message result field: {e}"))?,
        }
    }

    let status = status.ok_or_else(|| "Missing message result status".to_string())?;
    if status != ZCASH_SIGN_STATUS_SIGNED {
        return Err(format!("Unsupported message result status {status}"));
    }
    let kind = kind.ok_or_else(|| "Missing message result kind".to_string())?;
    if kind != ZCASH_SIGN_MESSAGE_KIND_PCZT_V1 {
        return Err(format!("Unsupported message result kind {kind}"));
    }
    let signed_pczt_bytes = payload.ok_or_else(|| "Missing signed PCZT payload".to_string())?;
    let digest = digest.ok_or_else(|| "Missing signed payload digest".to_string())?;
    if digest != sha256(&signed_pczt_bytes) {
        return Err("Signed payload digest mismatch".to_string());
    }

    Ok(ZcashBatchSignedMessage {
        id: id.ok_or_else(|| "Missing message result id".to_string())?,
        status,
        kind,
        signed_pczt_bytes,
        payload_digest_hex: hex::encode(digest),
    })
}

fn required_len(
    result: Result<Option<u64>, minicbor::decode::Error>,
    label: &str,
) -> Result<u64, String> {
    result
        .map_err(|e| format!("CBOR decode {label}: {e}"))?
        .ok_or_else(|| format!("Indefinite {label} is unsupported"))
}

fn decode_bytes_string(decoder: &mut minicbor::Decoder<'_>, label: &str) -> Result<String, String> {
    let bytes = decoder
        .bytes()
        .map_err(|e| format!("CBOR decode {label}: {e}"))?;
    Ok(String::from_utf8(bytes.to_vec()).unwrap_or_else(|_| hex::encode(bytes)))
}

fn sha256(bytes: &[u8]) -> [u8; 32] {
    use sha2::Digest;

    sha2::Sha256::digest(bytes).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_zcash_sign_batch_ur() {
        let parts = encode_zcash_sign_batch_ur_parts(
            "request-1",
            &[
                ZcashBatchMessageInput {
                    id: "tx-1".to_string(),
                    pczt_bytes: b"pczt-one".to_vec(),
                },
                ZcashBatchMessageInput {
                    id: "tx-2".to_string(),
                    pczt_bytes: b"pczt-two".to_vec(),
                },
            ],
            10_000,
        )
        .expect("batch UR should encode");

        assert_eq!(parts.len(), 1);
        assert!(parts[0].starts_with("UR:ZCASH-SIGN-BATCH/"));

        let part_lower = parts[0].to_lowercase();
        let (kind, cbor) = ur::decode(&part_lower).expect("batch UR should decode");
        let cbor = match kind {
            ur::ur::Kind::SinglePart => cbor,
            ur::ur::Kind::MultiPart => {
                let mut decoder = ur::Decoder::default();
                decoder.receive(&part_lower).expect("receive batch UR part");
                assert!(decoder.complete());
                decoder
                    .message()
                    .expect("batch UR message")
                    .expect("complete batch UR message")
            }
        };

        let mut decoder = minicbor::Decoder::new(&cbor);
        let len = required_len(decoder.map(), "test batch map").expect("map length");
        assert_eq!(len, 4);

        let mut version = None;
        let mut request_id = None;
        let mut network = None;
        let mut message_count = None;
        let expected_messages: [(&str, &[u8]); 2] = [("tx-1", b"pczt-one"), ("tx-2", b"pczt-two")];

        for _ in 0..len {
            match decoder.u8().expect("field key") {
                1 => version = Some(decoder.u32().expect("version")),
                2 => {
                    request_id = Some(
                        String::from_utf8(decoder.bytes().expect("request id").to_vec()).unwrap(),
                    );
                }
                3 => network = Some(decoder.u32().expect("network")),
                4 => {
                    let messages = required_len(decoder.array(), "test messages").expect("array");
                    message_count = Some(messages);
                    for expected in expected_messages.iter().take(messages as usize) {
                        let message_len =
                            required_len(decoder.map(), "test message map").expect("message map");
                        assert_eq!(message_len, 3);

                        let mut id = None;
                        let mut kind = None;
                        let mut payload = None;
                        for _ in 0..message_len {
                            match decoder.u8().expect("message field key") {
                                1 => {
                                    id = Some(
                                        String::from_utf8(
                                            decoder.bytes().expect("message id").to_vec(),
                                        )
                                        .unwrap(),
                                    );
                                }
                                2 => kind = Some(decoder.u32().expect("message kind")),
                                3 => {
                                    payload =
                                        Some(decoder.bytes().expect("message payload").to_vec())
                                }
                                6 => panic!("inbound payload digest should be omitted"),
                                _ => decoder.skip().expect("unknown message field"),
                            }
                        }

                        assert_eq!(id.as_deref(), Some(expected.0));
                        assert_eq!(kind, Some(ZCASH_SIGN_MESSAGE_KIND_PCZT_V1));
                        assert_eq!(payload.as_deref(), Some(expected.1));
                    }
                }
                11 => panic!("batch atomic field should be omitted"),
                _ => decoder.skip().expect("unknown field"),
            }
        }

        assert_eq!(version, Some(ZCASH_SIGN_BATCH_VERSION));
        assert_eq!(request_id.as_deref(), Some("request-1"));
        assert_eq!(network, Some(ZCASH_SIGN_BATCH_NETWORK_MAINNET));
        assert_eq!(message_count, Some(2));
    }

    #[test]
    fn ur_part_count_adds_small_redundancy_tail() {
        assert_eq!(ur_part_count(0), 0);
        assert_eq!(ur_part_count(1), 1);
        assert_eq!(ur_part_count(20), 22);
        assert_eq!(ur_part_count(36), 40);
        assert_eq!(ur_part_count(57), 63);
    }

    #[test]
    fn rejects_duplicate_batch_message_ids() {
        let err = encode_zcash_sign_batch_ur_parts(
            "request-1",
            &[
                ZcashBatchMessageInput {
                    id: "tx-1".to_string(),
                    pczt_bytes: b"pczt-one".to_vec(),
                },
                ZcashBatchMessageInput {
                    id: "tx-1".to_string(),
                    pczt_bytes: b"pczt-two".to_vec(),
                },
            ],
            10_000,
        )
        .expect_err("duplicate ids should fail");

        assert!(err.contains("Duplicate Zcash batch message id"));
    }

    #[test]
    fn decodes_zcash_sign_result_cbor() {
        let signed_one = b"signed-pczt-one".to_vec();
        let signed_two = b"signed-pczt-two".to_vec();
        let cbor = encode_test_sign_result(
            "request-1",
            &[
                ("tx-1", signed_one.clone(), sha256(&signed_one)),
                ("tx-2", signed_two.clone(), sha256(&signed_two)),
            ],
        );

        let decoded = decode_zcash_sign_result_cbor(&cbor).expect("result should decode");

        assert_eq!(decoded.version, ZCASH_SIGN_BATCH_VERSION);
        assert_eq!(decoded.request_id, "request-1");
        assert_eq!(decoded.results.len(), 2);
        assert_eq!(decoded.results[0].id, "tx-1");
        assert_eq!(decoded.results[0].signed_pczt_bytes, signed_one);
        assert_eq!(decoded.results[1].id, "tx-2");
        assert_eq!(decoded.results[1].signed_pczt_bytes, signed_two);
    }

    #[test]
    fn rejects_zcash_sign_result_digest_mismatch() {
        let signed = b"signed-pczt".to_vec();
        let mut wrong_digest = sha256(&signed);
        wrong_digest[0] ^= 0xff;
        let cbor = encode_test_sign_result("request-1", &[("tx-1", signed, wrong_digest)]);

        let err = decode_zcash_sign_result_cbor(&cbor).expect_err("digest mismatch should fail");

        assert_eq!(err, "Signed payload digest mismatch");
    }

    fn encode_test_sign_result(
        request_id: &str,
        messages: &[(&str, Vec<u8>, [u8; 32])],
    ) -> Vec<u8> {
        let mut cbor = Vec::new();
        let mut encoder = minicbor::Encoder::new(&mut cbor);

        encoder
            .map(3)
            .expect("result map")
            .u8(1)
            .expect("version key")
            .u32(ZCASH_SIGN_BATCH_VERSION)
            .expect("version")
            .u8(2)
            .expect("request key")
            .bytes(request_id.as_bytes())
            .expect("request")
            .u8(3)
            .expect("results key")
            .array(messages.len() as u64)
            .expect("results array");

        for (id, payload, digest) in messages {
            encoder
                .map(5)
                .expect("message map")
                .u8(1)
                .expect("id key")
                .bytes(id.as_bytes())
                .expect("id")
                .u8(2)
                .expect("status key")
                .u32(ZCASH_SIGN_STATUS_SIGNED)
                .expect("status")
                .u8(3)
                .expect("kind key")
                .u32(ZCASH_SIGN_MESSAGE_KIND_PCZT_V1)
                .expect("kind")
                .u8(4)
                .expect("payload key")
                .bytes(payload)
                .expect("payload")
                .u8(6)
                .expect("digest key")
                .bytes(digest)
                .expect("digest");
        }

        cbor
    }

    /// Encode a `zcash-batch-sig-result` CBOR payload for tests, mirroring the
    /// registry wire shape: `{1: version, 2: request_id, 3: results:
    /// [{1: message_id, 2: sigs: [{1: pool, 2: action_index, 3: sig}]}]}`.
    fn encode_test_sig_result(
        version: u32,
        request_id: &[u8],
        messages: &[(&[u8], Vec<(u32, u32, Vec<u8>)>)],
    ) -> Vec<u8> {
        let mut cbor = Vec::new();
        let mut encoder = minicbor::Encoder::new(&mut cbor);

        encoder
            .map(3)
            .expect("sig result map")
            .u8(1)
            .expect("version key")
            .u32(version)
            .expect("version")
            .u8(2)
            .expect("request id key")
            .bytes(request_id)
            .expect("request id")
            .u8(3)
            .expect("results key")
            .array(messages.len() as u64)
            .expect("results array");

        for (message_id, sigs) in messages {
            encoder
                .map(2)
                .expect("msg sig map")
                .u8(1)
                .expect("message id key")
                .bytes(message_id)
                .expect("message id")
                .u8(2)
                .expect("sigs key")
                .array(sigs.len() as u64)
                .expect("sigs array");
            for (pool, action_index, sig) in sigs {
                encoder
                    .map(3)
                    .expect("action sig map")
                    .u8(1)
                    .expect("pool key")
                    .u32(*pool)
                    .expect("pool")
                    .u8(2)
                    .expect("action index key")
                    .u32(*action_index)
                    .expect("action index")
                    .u8(3)
                    .expect("sig key")
                    .bytes(sig)
                    .expect("sig");
            }
        }

        cbor
    }

    #[test]
    fn decodes_zcash_sig_result_cbor() {
        let sig_a = [0x11u8; 64];
        let sig_b = [0x22u8; 64];
        let sig_c = [0x33u8; 64];
        let cbor = encode_test_sig_result(
            ZCASH_SIG_RESULT_VERSION,
            &[0xaa, 0xbb],
            &[
                (
                    b"migration-1",
                    vec![
                        (ZCASH_SIG_POOL_ORCHARD, 0, sig_a.to_vec()),
                        (ZCASH_SIG_POOL_IRONWOOD, 3, sig_b.to_vec()),
                    ],
                ),
                (
                    b"migration-2",
                    vec![(ZCASH_SIG_POOL_ORCHARD, 7, sig_c.to_vec())],
                ),
            ],
        );

        let decoded = decode_zcash_sig_result_cbor(&cbor).expect("sig result should decode");

        assert_eq!(decoded.version, ZCASH_SIG_RESULT_VERSION);
        assert_eq!(decoded.request_id, vec![0xaa, 0xbb]);
        assert_eq!(decoded.results.len(), 2);

        assert_eq!(decoded.results[0].message_id, b"migration-1".to_vec());
        assert_eq!(decoded.results[0].sigs.len(), 2);
        assert_eq!(decoded.results[0].sigs[0].pool, DECODED_SIG_POOL_ORCHARD);
        assert_eq!(decoded.results[0].sigs[0].action_index, 0);
        assert_eq!(decoded.results[0].sigs[0].sig, sig_a);
        assert_eq!(decoded.results[0].sigs[1].pool, DECODED_SIG_POOL_IRONWOOD);
        assert_eq!(decoded.results[0].sigs[1].action_index, 3);
        assert_eq!(decoded.results[0].sigs[1].sig, sig_b);

        assert_eq!(decoded.results[1].message_id, b"migration-2".to_vec());
        assert_eq!(decoded.results[1].sigs.len(), 1);
        assert_eq!(decoded.results[1].sigs[0].pool, DECODED_SIG_POOL_ORCHARD);
        assert_eq!(decoded.results[1].sigs[0].action_index, 7);
        assert_eq!(decoded.results[1].sigs[0].sig, sig_c);
    }

    #[test]
    fn rejects_zcash_sig_result_unsupported_version() {
        let cbor = encode_test_sig_result(ZCASH_SIG_RESULT_VERSION + 1, &[0x01], &[]);

        let err = decode_zcash_sig_result_cbor(&cbor).expect_err("bad version should fail");

        assert!(err.contains("Unsupported zcash-batch-sig-result version"));
    }

    #[test]
    fn rejects_zcash_sig_result_unknown_pool() {
        let cbor = encode_test_sig_result(
            ZCASH_SIG_RESULT_VERSION,
            &[0x01],
            &[(b"m", vec![(99, 0, vec![0x00; 64])])],
        );

        let err = decode_zcash_sig_result_cbor(&cbor).expect_err("unknown pool should fail");

        assert!(err.contains("Unsupported zcash-batch-sig-result pool"));
    }

    #[test]
    fn rejects_zcash_sig_result_bad_signature_length() {
        // 63 bytes instead of 64.
        let cbor = encode_test_sig_result(
            ZCASH_SIG_RESULT_VERSION,
            &[0x01],
            &[(b"m", vec![(ZCASH_SIG_POOL_ORCHARD, 0, vec![0x00; 63])])],
        );

        let err = decode_zcash_sig_result_cbor(&cbor).expect_err("short sig should fail");

        assert!(err.contains("signature must be"));
    }

    #[test]
    fn rejects_zcash_sig_result_duplicate_action_signature() {
        let cbor = encode_test_sig_result(
            ZCASH_SIG_RESULT_VERSION,
            &[0x01],
            &[(
                b"migration-1",
                vec![
                    (ZCASH_SIG_POOL_ORCHARD, 0, vec![0x11; 64]),
                    (ZCASH_SIG_POOL_ORCHARD, 0, vec![0x22; 64]),
                ],
            )],
        );

        let err = decode_zcash_sig_result_cbor(&cbor).expect_err("duplicate action should fail");

        assert!(err.contains("Duplicate zcash-batch-sig-result signature"));
    }

    #[test]
    fn rejects_zcash_sig_result_duplicate_map_key() {
        // map(2) { 1: 1, 1: 1 } — the version key appears twice.
        let cbor = vec![0xa2, 0x01, 0x01, 0x01, 0x01];

        let err = decode_zcash_sig_result_cbor(&cbor).expect_err("duplicate key should fail");

        assert!(err.contains("Duplicate key 1 in zcash-batch-sig-result map"));
    }

    #[test]
    fn rejects_zcash_sig_result_missing_required_field() {
        // map(2) { 1: version, 2: request id } — missing the results array.
        let cbor = vec![0xa2, 0x01, 0x01, 0x02, 0x41, 0x01];

        let err = decode_zcash_sig_result_cbor(&cbor).expect_err("missing results should fail");

        assert!(err.contains("Missing zcash-batch-sig-result results"));
    }

    #[test]
    fn rejects_zcash_sig_result_trailing_data() {
        let mut cbor = encode_test_sig_result(ZCASH_SIG_RESULT_VERSION, &[0x01], &[]);
        cbor.push(0x00);

        let err = decode_zcash_sig_result_cbor(&cbor).expect_err("trailing data should fail");

        assert!(err.contains("Trailing data after zcash-batch-sig-result"));
    }

    #[test]
    fn compact_action_sigs_round_trip() {
        let sigs = vec![
            DecodedActionSig {
                pool: DECODED_SIG_POOL_ORCHARD,
                action_index: 0,
                sig: [0x11; 64],
            },
            DecodedActionSig {
                pool: DECODED_SIG_POOL_IRONWOOD,
                action_index: 12,
                sig: [0x22; 64],
            },
        ];
        let blob = encode_compact_action_sigs(&sigs);
        // 4-byte count header + 2 records of 69 bytes each.
        assert_eq!(blob.len(), 4 + 2 * COMPACT_ACTION_SIG_LEN);
        assert_eq!(decode_compact_action_sigs(&blob).unwrap(), sigs);
    }

    #[test]
    fn compact_action_sigs_empty_round_trips() {
        let blob = encode_compact_action_sigs(&[]);
        assert_eq!(blob, vec![0, 0, 0, 0]);
        assert!(decode_compact_action_sigs(&blob).unwrap().is_empty());
    }

    #[test]
    fn decode_compact_action_sigs_rejects_truncated_body() {
        let mut blob = encode_compact_action_sigs(&[DecodedActionSig {
            pool: DECODED_SIG_POOL_ORCHARD,
            action_index: 3,
            sig: [0x33; 64],
        }]);
        blob.pop(); // drop one signature byte
        let err = decode_compact_action_sigs(&blob).expect_err("truncated blob should fail");
        assert!(err.contains("body bytes"));
    }

    #[test]
    fn decode_compact_action_sigs_rejects_short_header() {
        let err = decode_compact_action_sigs(&[0, 0]).expect_err("short header should fail");
        assert!(err.contains("count header"));
    }
}
