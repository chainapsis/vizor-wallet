use super::serializer::pack_derivation_path;

pub(crate) const ZCASH_CLA: u8 = 0xe0;
pub(crate) const GET_VK: u8 = 0x50;
pub(crate) const GET_VK_FIRST: u8 = 0x00;
pub(crate) const GET_VK_CONTINUE: u8 = 0x80;
pub(crate) const GET_VK_UFVK: u8 = 0x00;
const RESPONSE_OK: u16 = 0x9000;
const UFVK_RESPONSE_LIMIT: usize = 8 * 1024;

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

pub(crate) fn decode_raw_ufvk_responses(responses: &[Vec<u8>]) -> Result<String, String> {
    if responses.is_empty() {
        return Err("Ledger UFVK response is missing".into());
    }
    let chunks = responses
        .iter()
        .map(|response| decode_raw_response(response))
        .collect::<Result<Vec<_>, _>>()?;
    decode_ufvk_chunks(&chunks)
}

pub(crate) fn decode_ufvk_chunks(chunks: &[Vec<u8>]) -> Result<String, String> {
    let mut response = chunks.first().cloned().unwrap_or_default();
    if response.len() < 2 {
        return Err("Ledger UFVK response is missing its length prefix".into());
    }

    let key_len = u16::from_be_bytes([response[0], response[1]]) as usize;
    let expected_len = 2 + key_len;
    if expected_len > UFVK_RESPONSE_LIMIT {
        return Err(format!(
            "Ledger UFVK response declares an unreasonable length: {key_len} bytes"
        ));
    }

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

pub(crate) fn decode_raw_response(response: &[u8]) -> Result<Vec<u8>, String> {
    if response.len() < 2 {
        return Err("Ledger APDU response was too short to contain a status word".into());
    }
    let status = u16::from_be_bytes([response[response.len() - 2], response[response.len() - 1]]);
    if status != RESPONSE_OK {
        return Err(map_status_word(status));
    }
    Ok(response[..response.len() - 2].to_vec())
}

pub(crate) fn map_status_word(status: u16) -> String {
    match status {
        0x5515 | 0x6982 | 0x5303 => {
            "Ledger device is locked; unlock it and reopen the Zcash app".into()
        }
        0x5501 => "Ledger request was rejected on the device".into(),
        0x6985 => "Ledger request was rejected or the PCZT was not finalized".into(),
        0x5502 => "Ledger device PIN is not set".into(),
        0x5223 => "Ledger device returned an internal error".into(),
        0x6601 => "Ledger device is busy switching apps; retry shortly".into(),
        0x670a => "Ledger app-open request did not include an app name".into(),
        0x6807 => "The Zcash app is not installed on this Ledger".into(),
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
    }

    #[test]
    fn raw_ufvk_responses_are_status_checked_and_reassembled() {
        let responses = vec![
            vec![0, 5, b'u', b'v', 0x90, 0],
            vec![b'i', b'e', b'w', 0x90, 0],
        ];
        assert_eq!(decode_raw_ufvk_responses(&responses).unwrap(), "uview");
        assert!(decode_raw_ufvk_responses(&[vec![0x69, 0x85]])
            .unwrap_err()
            .contains("rejected"));
        assert!(decode_raw_ufvk_responses(&[vec![0, 5, b'u', 0x90, 0]])
            .unwrap_err()
            .contains("before the declared length"));
        assert!(
            decode_raw_ufvk_responses(&[vec![0, 5, b'u', 0x90, 0], vec![0x90, 0],])
                .unwrap_err()
                .contains("before the declared length")
        );
    }
}
