const UFVK_RESPONSE_LIMIT: usize = 8 * 1024;
const MAX_APDU_DATA: usize = 255;

pub(crate) const ZCASH_CLA: u8 = 0xe0;
pub(crate) const GET_VK: u8 = 0x50;
pub(crate) const GET_VK_FIRST: u8 = 0x00;
pub(crate) const GET_VK_CONTINUE: u8 = 0x80;
pub(crate) const GET_VK_UFVK: u8 = 0x00;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ApduCommand {
    pub cla: u8,
    pub ins: u8,
    pub p1: u8,
    pub p2: u8,
    pub data: Vec<u8>,
}

pub(crate) fn ufvk_commands(account_index: u32) -> Result<(ApduCommand, ApduCommand), String> {
    if account_index >= 0x8000_0000 {
        return Err("Ledger account index must be below 2^31".into());
    }

    let account = 0x8000_0000 | account_index;
    let mut request = pack_derivation_path(&[0x8000_0020, 0x8000_0085, account])?;
    request.extend_from_slice(&pack_derivation_path(&[0x8000_002c, 0x8000_0085, account])?);
    if request.len() > MAX_APDU_DATA {
        return Err("Ledger UFVK request exceeds one APDU packet".into());
    }

    Ok((
        ApduCommand {
            cla: ZCASH_CLA,
            ins: GET_VK,
            p1: GET_VK_FIRST,
            p2: GET_VK_UFVK,
            data: request,
        },
        ApduCommand {
            cla: ZCASH_CLA,
            ins: GET_VK,
            p1: GET_VK_CONTINUE,
            p2: GET_VK_UFVK,
            data: Vec::new(),
        },
    ))
}

fn pack_derivation_path(path: &[u32]) -> Result<Vec<u8>, String> {
    let path_len = u8::try_from(path.len()).map_err(|_| "Ledger derivation path is too long")?;
    let mut bytes = Vec::with_capacity(1 + path.len() * 4);
    bytes.push(path_len);
    for component in path {
        bytes.extend_from_slice(&component.to_be_bytes());
    }
    if bytes.len() > MAX_APDU_DATA {
        return Err("Ledger derivation path exceeds one APDU packet".into());
    }
    Ok(bytes)
}

pub(crate) fn decode_ufvk_chunks(chunks: &[Vec<u8>]) -> Result<String, String> {
    let mut response = chunks.first().cloned().unwrap_or_default();
    let expected_len = ufvk_expected_len(&response)?;

    for chunk in chunks.iter().skip(1) {
        if response.len() >= expected_len {
            return Err("Ledger UFVK response contains trailing chunks".into());
        }
        if chunk.is_empty() {
            return Err("Ledger UFVK response ended before the declared length".into());
        }
        response.extend_from_slice(chunk);
    }
    if response.len() < expected_len {
        return Err("Ledger UFVK response ended before the declared length".into());
    }
    if response.len() != expected_len {
        return Err("Ledger UFVK response contains trailing bytes".into());
    }

    String::from_utf8(response[2..].to_vec())
        .map_err(|_| "Ledger UFVK response is not valid UTF-8".into())
}

pub(crate) fn ufvk_expected_len(first_chunk: &[u8]) -> Result<usize, String> {
    if first_chunk.len() < 2 {
        return Err("Ledger UFVK response is missing its length prefix".into());
    }
    let key_len = u16::from_be_bytes([first_chunk[0], first_chunk[1]]) as usize;
    let expected_len = 2 + key_len;
    if expected_len > UFVK_RESPONSE_LIMIT {
        return Err(format!(
            "Ledger UFVK response declares an unreasonable length: {key_len} bytes"
        ));
    }
    Ok(expected_len)
}

pub(crate) fn map_status_word(status: u16) -> String {
    match status {
        0x5515 | 0x6982 | 0x5303 => {
            "Ledger device is locked; unlock it and reopen the Zcash app".into()
        }
        0x5501 => "Ledger request was rejected on the device".into(),
        0x6985 => "Ledger request was rejected on the device (0x6985)".into(),
        0x6986 => {
            "Ledger signing preconditions were not met (0x6986): account path or PCZT finalization"
                .into()
        }
        0x6f01 => "Ledger app version could not be parsed (0x6f01)".into(),
        0x6f03 => "Ledger app random number generation failed (0x6f03)".into(),
        0x5502 => "Ledger device PIN is not set".into(),
        0x5223 => "Ledger device returned an internal error".into(),
        0x6601 => "Ledger device is busy switching apps; retry shortly".into(),
        0x670a => "Ledger app-open request did not include an app name".into(),
        0x6807 => "The Zcash app is not installed on this Ledger".into(),
        0x6901 => "Ledger display is busy starting a review; retry shortly".into(),
        0x6a80 => "Ledger rejected the PCZT data or key path".into(),
        0x6e00 => "Ledger device does not support this command class".into(),
        0x6d00 => "The running Ledger app does not support this command".into(),
        0xb007 => "Ledger Zcash app is in the wrong state; close and reopen the app".into(),
        _ => format!("Ledger Zcash app returned status 0x{status:04x}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ufvk_plan_matches_the_zcash_app_protocol() {
        let (first, continuation) = ufvk_commands(7).unwrap();
        assert_eq!(
            (first.cla, first.ins, first.p1, first.p2),
            (0xe0, 0x50, 0, 0)
        );
        assert_eq!(
            first.data,
            hex::decode("03800000208000008580000007038000002c8000008580000007").unwrap()
        );
        assert_eq!(
            (
                continuation.cla,
                continuation.ins,
                continuation.p1,
                continuation.p2
            ),
            (0xe0, 0x50, 0x80, 0)
        );
        assert!(continuation.data.is_empty());
        assert!(ufvk_commands(0x8000_0000)
            .unwrap_err()
            .contains("below 2^31"));
    }

    #[test]
    fn ufvk_chunks_are_reassembled_and_truncation_is_rejected() {
        let chunks = vec![vec![0, 5, b'u', b'v'], vec![b'i', b'e', b'w']];
        assert_eq!(decode_ufvk_chunks(&chunks).unwrap(), "uview");
        assert!(decode_ufvk_chunks(&[vec![0, 5, b'u']])
            .unwrap_err()
            .contains("before the declared length"));
    }

    #[test]
    fn ufvk_response_rejects_missing_trailing_and_unreasonable_data() {
        assert!(decode_ufvk_chunks(&[])
            .unwrap_err()
            .contains("length prefix"));
        assert!(decode_ufvk_chunks(&[vec![0, 1, b'a'], vec![b'b']])
            .unwrap_err()
            .contains("trailing chunks"));
        assert!(decode_ufvk_chunks(&[vec![0, 1, b'a', b'b']])
            .unwrap_err()
            .contains("trailing bytes"));
        assert!(decode_ufvk_chunks(&[vec![0x20, 0x00]])
            .unwrap_err()
            .contains("unreasonable length"));
    }

    #[test]
    fn status_words_distinguish_denial_preconditions_and_internal_failures() {
        assert!(map_status_word(0x6985).contains("rejected"));
        for code in [0x6986, 0x6f01, 0x6f03] {
            let message = map_status_word(code);
            assert!(message.contains(&format!("0x{code:04x}")));
            assert!(!message.contains("returned status"));
        }
    }
}
