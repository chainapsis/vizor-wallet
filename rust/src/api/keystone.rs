//! Keystone hardware wallet FRB API.

use crate::wallet::keystone;

pub use crate::wallet::keystone::{
    KeystoneAccountInfo, UrDecodeResult, ZcashBatchMessageInput, ZcashBatchSignResult,
    ZcashBatchSignedMessage,
};

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

/// Encode redacted PCZT bytes into a `zcash-sign-batch` animated UR.
pub fn encode_zcash_sign_batch_ur_parts(
    request_id: String,
    messages: Vec<ZcashBatchMessageInput>,
    max_fragment_len: usize,
) -> Result<Vec<String>, String> {
    keystone::encode_zcash_sign_batch_ur_parts(&request_id, &messages, max_fragment_len)
}

/// Decode the CBOR payload returned from a `zcash-sign-result` UR.
pub fn decode_zcash_sign_result_cbor(cbor: Vec<u8>) -> Result<ZcashBatchSignResult, String> {
    keystone::decode_zcash_sign_result_cbor(&cbor)
}

/// One spend-authorization signature from a compact `zcash-batch-sig-result`,
/// located by `pool` (0 = Orchard, 1 = Ironwood) and the spend action's index
/// within that pool's bundle. `sig` is the raw 64-byte spend-authorization
/// signature; FRB does not bridge `[u8; 64]` arrays cleanly, so it crosses as a
/// `Vec<u8>` (always length 64) the way other fixed byte arrays do at this
/// boundary.
pub struct KeystoneActionSig {
    pub pool: u8,
    pub action_index: u32,
    pub sig: Vec<u8>,
}

/// The signatures produced for a single requested message, correlated back to
/// the wallet's held proofs-PCZT by `message_id` (the id the wallet assigned
/// when it built the batch).
pub struct KeystoneMsgSig {
    pub message_id: Vec<u8>,
    pub sigs: Vec<KeystoneActionSig>,
}

/// FRB-friendly decoding of a compact `zcash-batch-sig-result` UR (tag 49207): the
/// "signatures-only" response. Unlike [`ZcashBatchSignResult`], which echoes the
/// whole redacted PCZTs back, this carries only the produced signatures so the
/// wallet can re-apply them to the proofs-PCZTs it already holds (see
/// `sync::pczt::apply_sigs_and_extract`).
pub struct KeystoneSigResult {
    pub version: u32,
    pub request_id: Vec<u8>,
    pub results: Vec<KeystoneMsgSig>,
}

/// Reshape a PCZT [`OrchardSpendAuthSignature`] into the FRB-boundary form.
///
/// [`OrchardSpendAuthSignature`]: pczt::roles::signer::OrchardSpendAuthSignature
fn action_sig_to_api(
    action: &pczt::roles::signer::OrchardSpendAuthSignature,
) -> Result<KeystoneActionSig, String> {
    let pool = match action.value_pool() {
        orchard::ValuePool::Orchard => 0,
        orchard::ValuePool::Ironwood => 1,
    };
    let action_index = u32::try_from(action.action_index())
        .map_err(|_| "PCZT signature action index exceeds u32".to_string())?;
    Ok(KeystoneActionSig {
        pool,
        action_index,
        sig: action.signature().to_vec(),
    })
}

/// Reshape an upstream PCZT batch signing response into the flat FRB structs
/// Dart consumes.
fn sig_result_to_api(
    decoded: pczt::roles::signer::batch::BatchSignResponse,
) -> Result<KeystoneSigResult, String> {
    Ok(KeystoneSigResult {
        version: pczt::roles::signer::batch::VERSION,
        request_id: decoded.request_id().to_vec(),
        results: decoded
            .results()
            .iter()
            .map(|msg| {
                Ok(KeystoneMsgSig {
                    message_id: msg.message_id().to_vec(),
                    sigs: msg
                        .signatures()
                        .iter()
                        .map(action_sig_to_api)
                        .collect::<Result<Vec<_>, String>>()?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?,
    })
}

/// Decode the Postcard payload returned from a compact
/// `zcash-batch-sig-result` UR into flat FRB structs. The wallet-layer decode
/// applies correlation policy on top of the upstream PCZT wire types; this
/// wrapper only reshapes fixed-size signatures into the `Vec<u8>` form FRB
/// carries.
pub fn decode_zcash_batch_sign_response(postcard: Vec<u8>) -> Result<KeystoneSigResult, String> {
    let decoded = keystone::decode_zcash_batch_sign_response(&postcard)?;
    sig_result_to_api(decoded)
}

/// Decode a legacy `zcash-sign-result` response and normalize it to the compact
/// signature shape used by migration completion. Current ForgeBox firmware may
/// still echo signed redacted PCZTs; the wallet only needs their
/// spend-authorization signatures because it already holds the proofs-PCZTs.
pub fn decode_zcash_sign_result_cbor_as_sig_result(
    cbor: Vec<u8>,
) -> Result<KeystoneSigResult, String> {
    let decoded = keystone::decode_zcash_sign_result_cbor(&cbor)?;
    let results = decoded
        .results
        .into_iter()
        .map(|message| {
            Ok(pczt::roles::signer::batch::BatchSignResponseMessage::new(
                message.id.into_bytes(),
                crate::wallet::sync::extract_compact_sigs_from_signed_pczt(
                    &message.signed_pczt_bytes,
                )?,
            ))
        })
        .collect::<Result<Vec<_>, String>>()?;

    sig_result_to_api(pczt::roles::signer::batch::BatchSignResponse::new(
        decoded.request_id.into_bytes(),
        results,
    ))
}

/// Return the Sapling and Orchard nullifiers spent by a PCZT.
pub fn pczt_spend_nullifiers(pczt_bytes: Vec<u8>) -> Result<Vec<String>, String> {
    keystone::pczt_spend_nullifiers(&pczt_bytes)
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
