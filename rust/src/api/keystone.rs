//! Keystone hardware wallet FRB API.

use crate::wallet::keystone;

const KEYSTONE_FW_VERSION_PROP: &str = "keystone:fw_version";

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
    /// Raw Keystone firmware version bytes reported by the signer. Current
    /// firmware encodes this as `[major, minor, build]`.
    pub firmware_version: Vec<u8>,
    pub request_id: Vec<u8>,
    pub results: Vec<KeystoneMsgSig>,
}

/// Reshape a PCZT [`SpendAuthSignature`] into the FRB-boundary form.
///
/// [`SpendAuthSignature`]: pczt::roles::signer::SpendAuthSignature
fn action_sig_to_api(
    action: &pczt::roles::signer::SpendAuthSignature,
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
    firmware_version: Vec<u8>,
    request_id: Vec<u8>,
    message_ids: Vec<Vec<u8>>,
) -> Result<KeystoneSigResult, String> {
    if firmware_version.len() != 3 {
        return Err("Keystone firmware version must be 3 bytes [major, minor, build]".to_string());
    }
    if request_id.is_empty() {
        return Err("Zcash batch request id must not be empty".to_string());
    }
    if decoded.signatures().len() != message_ids.len() {
        return Err(format!(
            "Keystone returned {} signature lists for {} requested messages",
            decoded.signatures().len(),
            message_ids.len()
        ));
    }

    let mut seen_ids = std::collections::HashSet::new();
    for message_id in &message_ids {
        if message_id.is_empty() {
            return Err("Zcash batch message id must not be empty".to_string());
        }
        if !seen_ids.insert(message_id) {
            return Err("Zcash batch message ids must be unique".to_string());
        }
    }

    Ok(KeystoneSigResult {
        firmware_version,
        request_id,
        results: decoded
            .signatures()
            .iter()
            .zip(message_ids)
            .map(|(signatures, message_id)| {
                Ok(KeystoneMsgSig {
                    message_id,
                    sigs: signatures
                        .iter()
                        .map(action_sig_to_api)
                        .collect::<Result<Vec<_>, String>>()?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?,
    })
}

/// Decode the CBOR payload returned from a compact `zcash-batch-sig-result` UR
/// into flat FRB structs. The echoed request id is checked before the ordered
/// signature lists are correlated with the application's ordered message ids.
pub fn decode_zcash_batch_sign_response(
    cbor: Vec<u8>,
    expected_request_id: String,
    message_ids: Vec<String>,
) -> Result<KeystoneSigResult, String> {
    if expected_request_id.is_empty() {
        return Err("Expected Zcash batch request id must not be empty".to_string());
    }
    let (firmware_version, request_id, decoded) =
        keystone::decode_zcash_batch_sign_response(&cbor)?;
    if request_id != expected_request_id.as_bytes() {
        return Err("Keystone batch result request id does not match the request".to_string());
    }
    sig_result_to_api(
        decoded,
        firmware_version,
        request_id,
        message_ids.into_iter().map(String::into_bytes).collect(),
    )
}

fn signed_pczt_firmware_version(pczt: &pczt::Pczt) -> Result<Vec<u8>, String> {
    let firmware_version = pczt
        .global()
        .proprietary()
        .get(KEYSTONE_FW_VERSION_PROP)
        .ok_or_else(|| {
            format!("Signed PCZT is missing {KEYSTONE_FW_VERSION_PROP} firmware metadata")
        })?;
    if firmware_version.len() != 3 {
        return Err(format!(
            "Signed PCZT {KEYSTONE_FW_VERSION_PROP} firmware metadata must be 3 bytes [major, minor, build]"
        ));
    }
    Ok(firmware_version.clone())
}

fn retain_consistent_firmware_version(
    expected: &mut Option<Vec<u8>>,
    firmware_version: Vec<u8>,
) -> Result<(), String> {
    match expected {
        Some(expected) if expected != &firmware_version => {
            Err("Keystone signed PCZTs report inconsistent firmware versions".to_string())
        }
        Some(_) => Ok(()),
        None => {
            *expected = Some(firmware_version);
            Ok(())
        }
    }
}

/// Decode a legacy `zcash-sign-result` response and normalize it to the compact
/// signature shape used by migration completion. Current ForgeBox firmware may
/// still echo signed redacted PCZTs. Every returned PCZT must carry the same
/// non-empty `keystone:fw_version` stamp. The wallet otherwise only needs their
/// spend-authorization signatures because it already holds the proofs-PCZTs.
pub fn decode_zcash_sign_result_cbor_as_sig_result(
    cbor: Vec<u8>,
) -> Result<KeystoneSigResult, String> {
    let decoded = keystone::decode_zcash_sign_result_cbor(&cbor)?;
    let request_id = decoded.request_id.into_bytes();
    let mut firmware_version = None;
    let mut parsed_messages = Vec::with_capacity(decoded.results.len());
    for message in decoded.results {
        let signed_pczt = pczt::Pczt::parse(&message.signed_pczt_bytes)
            .map_err(|e| format!("Parse signed PCZT: {e:?}"))?;
        retain_consistent_firmware_version(
            &mut firmware_version,
            signed_pczt_firmware_version(&signed_pczt)?,
        )?;
        parsed_messages.push((message.id.into_bytes(), signed_pczt));
    }
    let firmware_version = firmware_version
        .ok_or_else(|| "Keystone signing result contains no firmware version".to_string())?;
    let messages = parsed_messages
        .into_iter()
        .map(|(message_id, signed_pczt)| {
            let signatures = crate::wallet::sync::extract_compact_sigs_from_pczt(&signed_pczt)?;
            Ok((message_id, signatures))
        })
        .collect::<Result<Vec<_>, String>>()?;
    let (message_ids, signatures) = messages.into_iter().unzip();

    sig_result_to_api(
        pczt::roles::signer::batch::BatchSignResponse::new(signatures),
        firmware_version,
        request_id,
        message_ids,
    )
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

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_FIRMWARE_VERSION: [u8; 3] = [1, 2, 3];

    fn encoded_compact_response(request_id: &str) -> Vec<u8> {
        use pczt::roles::signer::batch::BatchSignResponse;

        let postcard = BatchSignResponse::new(vec![vec![]]).serialize().unwrap();
        ur_registry::zcash::zcash_batch_sig_result::ZcashBatchSigResult::new(
            request_id.as_bytes().to_vec(),
            postcard,
            TEST_FIRMWARE_VERSION,
        )
        .try_into()
        .unwrap()
    }

    #[test]
    fn compact_response_validates_echoed_request_id() {
        let decoded = decode_zcash_batch_sign_response(
            encoded_compact_response("request-1"),
            "request-1".to_string(),
            vec!["message-1".to_string()],
        )
        .unwrap();

        assert_eq!(decoded.firmware_version, TEST_FIRMWARE_VERSION);
        assert_eq!(decoded.request_id, b"request-1");
        assert_eq!(decoded.results[0].message_id, b"message-1");
    }

    #[test]
    fn compact_response_rejects_wrong_request_id_before_mapping() {
        let error = decode_zcash_batch_sign_response(
            encoded_compact_response("stale-request"),
            "request-1".to_string(),
            vec!["message-1".to_string()],
        )
        .err()
        .unwrap();

        assert_eq!(
            error,
            "Keystone batch result request id does not match the request"
        );
    }

    #[test]
    fn compact_response_uses_application_correlation_in_request_order() {
        let response = pczt::roles::signer::batch::BatchSignResponse::new(vec![
            vec![pczt::roles::signer::SpendAuthSignature::from_parts(
                orchard::ValuePool::Orchard,
                0,
                [0x11; 64],
            )],
            vec![pczt::roles::signer::SpendAuthSignature::from_parts(
                orchard::ValuePool::Ironwood,
                3,
                [0x22; 64],
            )],
        ]);

        let decoded = sig_result_to_api(
            response,
            TEST_FIRMWARE_VERSION.to_vec(),
            b"request-1".to_vec(),
            vec![b"message-1".to_vec(), b"message-2".to_vec()],
        )
        .unwrap();

        assert_eq!(decoded.firmware_version, TEST_FIRMWARE_VERSION);
        assert_eq!(decoded.request_id, b"request-1");
        assert_eq!(decoded.results[0].message_id, b"message-1");
        assert_eq!(decoded.results[0].sigs[0].pool, 0);
        assert_eq!(decoded.results[1].message_id, b"message-2");
        assert_eq!(decoded.results[1].sigs[0].pool, 1);
    }

    #[test]
    fn compact_response_rejects_correlation_count_mismatch() {
        let response = pczt::roles::signer::batch::BatchSignResponse::new(vec![vec![]]);

        let error = sig_result_to_api(
            response,
            TEST_FIRMWARE_VERSION.to_vec(),
            b"request-1".to_vec(),
            vec![],
        )
        .err()
        .unwrap();

        assert!(error.contains("1 signature lists for 0 requested messages"));
    }

    #[test]
    fn compact_response_rejects_invalid_firmware_version_length_before_mapping() {
        let response = pczt::roles::signer::batch::BatchSignResponse::new(vec![vec![]]);

        let error = sig_result_to_api(
            response,
            vec![1, 2],
            b"request-1".to_vec(),
            vec![b"message-1".to_vec()],
        )
        .err()
        .unwrap();

        assert_eq!(
            error,
            "Keystone firmware version must be 3 bytes [major, minor, build]"
        );
    }

    fn test_pczt_with_firmware_version(firmware_version: Option<&[u8]>) -> pczt::Pczt {
        use pczt::roles::{creator::Creator, updater::Updater};
        use zcash_protocol::consensus::BranchId;

        let pczt = Creator::new(BranchId::Nu6.into(), 10_000_000, 133, None, None)
            .unwrap()
            .build()
            .unwrap();
        if let Some(firmware_version) = firmware_version {
            Updater::new(pczt)
                .update_global_with(|mut global| {
                    global.set_proprietary(
                        KEYSTONE_FW_VERSION_PROP.to_string(),
                        firmware_version.to_vec(),
                    );
                })
                .finish()
        } else {
            pczt
        }
    }

    #[test]
    fn legacy_pczt_requires_firmware_version_stamp() {
        let error =
            signed_pczt_firmware_version(&test_pczt_with_firmware_version(None)).unwrap_err();

        assert!(error.contains("missing keystone:fw_version"));
    }

    #[test]
    fn legacy_pczt_rejects_invalid_firmware_version_length() {
        let error = signed_pczt_firmware_version(&test_pczt_with_firmware_version(Some(&[1, 2])))
            .unwrap_err();

        assert!(error.contains("must be 3 bytes"));
    }

    #[test]
    fn legacy_pczt_reads_firmware_version_stamp() {
        let version = signed_pczt_firmware_version(&test_pczt_with_firmware_version(Some(
            &TEST_FIRMWARE_VERSION,
        )))
        .unwrap();

        assert_eq!(version, TEST_FIRMWARE_VERSION);
    }

    #[test]
    fn legacy_pczt_versions_must_be_consistent() {
        let mut version = None;
        retain_consistent_firmware_version(&mut version, TEST_FIRMWARE_VERSION.to_vec()).unwrap();
        retain_consistent_firmware_version(&mut version, TEST_FIRMWARE_VERSION.to_vec()).unwrap();

        let error = retain_consistent_firmware_version(&mut version, vec![1, 2, 4]).unwrap_err();

        assert_eq!(
            error,
            "Keystone signed PCZTs report inconsistent firmware versions"
        );
    }
}
