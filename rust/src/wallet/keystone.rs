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

    // Subsequent parts — feed to existing decoder.
    let session = session_guard.as_mut().unwrap();
    session
        .decoder
        .receive(&part_lower)
        .map_err(|e| format!("UR receive: {e}"))?;

    if session.decoder.complete() {
        let cbor = session
            .decoder
            .message()
            .map_err(|e| format!("UR message: {e}"))?
            .ok_or("Decoder complete but no message")?;
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

    let progress = session.decoder.progress();
    Ok(UrDecodeResult {
        complete: false,
        progress: progress as u32,
        data: None,
        ur_type: Some(expected_ur_type.to_string()),
    })
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

    let count = encoder.fragment_count();
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
