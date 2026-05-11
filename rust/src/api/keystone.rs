//! Keystone hardware wallet FRB API.

use crate::wallet::keystone;

pub use crate::wallet::keystone::{KeystoneAccountInfo, UrDecodeResult};

/// Encode PCZT bytes to a UR string for QR code display.
pub fn encode_pczt_to_ur(pczt_bytes: Vec<u8>) -> Result<String, String> {
    keystone::encode_pczt_to_ur(&pczt_bytes)
}

/// Decode a UR string (from QR scan) to PCZT bytes.
pub fn decode_ur_to_pczt(ur_string: String) -> Result<Vec<u8>, String> {
    keystone::decode_ur_to_pczt(&ur_string)
}

/// Decode a single UR part (from animated QR scan). Stateful — accumulates parts
/// until the full UR is decoded. `expected_ur_type` pins the scan to one UR
/// registry type (e.g. `"zcash-pczt"`); parts of any other type are rejected.
/// The session auto-resets on completion or when the expected type changes.
pub fn decode_ur_part(part: String, expected_ur_type: String) -> Result<UrDecodeResult, String> {
    keystone::decode_ur_part(&part, &expected_ur_type)
}

/// Encode PCZT bytes into multiple UR parts for animated QR display.
pub fn encode_pczt_ur_parts(
    pczt_bytes: Vec<u8>,
    max_fragment_len: usize,
) -> Result<Vec<String>, String> {
    keystone::encode_pczt_ur_parts(&pczt_bytes, max_fragment_len)
}

/// Discard any in-flight multi-part UR decode state. The scan screen calls
/// this on entry to guarantee a fresh session regardless of how the previous
/// scan ended (cancel, back button, mid-stream error).
///
/// Marked `#[frb(sync)]` so the Dart caller does not race with the camera:
/// QR scan screen entry needs the Rust `UR_SESSION` to be clean **before** the
/// first `onDetect` callback fires, and a fire-and-forget `Future` provides no
/// such ordering guarantee. The Rust body is a single mutex lock + `None`
/// assignment, so it's trivially non-blocking.
#[flutter_rust_bridge::frb(sync)]
pub fn reset_ur_session() {
    keystone::reset_ur_session();
}

/// Decode ZcashAccounts from raw CBOR bytes (from animated QR scan result).
pub fn decode_accounts_from_cbor(cbor: Vec<u8>) -> Result<Vec<KeystoneAccountInfo>, String> {
    let accounts: ur_registry::zcash::zcash_accounts::ZcashAccounts = cbor
        .try_into()
        .map_err(|e: ur_registry::error::URError| format!("CBOR decode: {e:?}"))?;
    let seed_fp = accounts.get_seed_fingerprint();
    Ok(accounts
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
        .collect())
}

/// Decode raw PCZT bytes from a ZcashPczt CBOR envelope (from animated QR scan result).
pub fn decode_pczt_from_cbor(cbor: Vec<u8>) -> Result<Vec<u8>, String> {
    let pczt: ur_registry::zcash::zcash_pczt::ZcashPczt = cbor
        .try_into()
        .map_err(|e: ur_registry::error::URError| format!("CBOR decode: {e:?}"))?;
    Ok(pczt.get_data())
}

/// Decode a ZcashAccounts UR string to account info list.
pub fn decode_accounts_ur(ur_string: String) -> Result<Vec<KeystoneAccountInfo>, String> {
    let (_seed_fp, infos) = keystone::decode_accounts_ur(&ur_string)?;
    Ok(infos)
}
