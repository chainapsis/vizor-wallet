use super::serializer::pack_derivation_path;

pub(crate) const ZCASH_CLA: u8 = 0xe0;
pub(crate) const GET_PUBLIC_KEY: u8 = 0x40;
pub(crate) const GET_PUBLIC_KEY_NO_DISPLAY: u8 = 0x00;
pub(crate) const GET_VK: u8 = 0x50;
pub(crate) const GET_VK_FIRST: u8 = 0x00;
pub(crate) const GET_VK_CONTINUE: u8 = 0x80;
pub(crate) const GET_VK_UFVK: u8 = 0x00;
const RESPONSE_OK: u16 = 0x9000;
const UFVK_RESPONSE_LIMIT: usize = 8 * 1024;
const CHAIN_CODE_LEN: usize = 32;

const BIP44_PURPOSE: u32 = 0x8000_002c;
const ZCASH_COIN_TYPE: u32 = 0x8000_0085;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct WalletPublicKey {
    pub public_key: [u8; 33],
    pub address: String,
    pub chain_code: [u8; CHAIN_CODE_LEN],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ApduCommand {
    pub cla: u8,
    pub ins: u8,
    pub p1: u8,
    pub p2: u8,
    pub data: Vec<u8>,
}

pub(crate) fn wallet_identity_commands(
    verification_account_index: Option<u32>,
) -> Result<Vec<ApduCommand>, String> {
    let mut commands = vec![public_key_command(&[
        BIP44_PURPOSE,
        ZCASH_COIN_TYPE,
        0x8000_0000,
    ])?];
    if let Some(account_index) = verification_account_index {
        if account_index >= 0x8000_0000 {
            return Err("Ledger account index must be below 2^31".into());
        }
        commands.push(public_key_command(&[
            BIP44_PURPOSE,
            ZCASH_COIN_TYPE,
            0x8000_0000 | account_index,
            0,
            0,
        ])?);
    }
    Ok(commands)
}

fn public_key_command(path: &[u32]) -> Result<ApduCommand, String> {
    Ok(ApduCommand {
        cla: ZCASH_CLA,
        ins: GET_PUBLIC_KEY,
        p1: GET_PUBLIC_KEY_NO_DISPLAY,
        p2: 0,
        data: pack_derivation_path(path)?,
    })
}

pub(crate) fn decode_raw_wallet_public_key(response: &[u8]) -> Result<WalletPublicKey, String> {
    decode_wallet_public_key(&decode_raw_response(response)?)
}

pub(crate) fn decode_wallet_public_key(response: &[u8]) -> Result<WalletPublicKey, String> {
    let public_key_len = response
        .first()
        .copied()
        .ok_or("Ledger public-key response is missing its key length")?
        as usize;
    let public_key_end = 1usize
        .checked_add(public_key_len)
        .ok_or("Ledger public-key response length overflow")?;
    let address_len = response
        .get(public_key_end)
        .copied()
        .ok_or("Ledger public-key response is missing its address length")?
        as usize;
    let address_start = public_key_end + 1;
    let address_end = address_start
        .checked_add(address_len)
        .ok_or("Ledger public-key response length overflow")?;
    let expected_len = address_end
        .checked_add(CHAIN_CODE_LEN)
        .ok_or("Ledger public-key response length overflow")?;
    if response.len() != expected_len {
        return Err(format!(
            "Ledger public-key response has {} bytes; expected {expected_len}",
            response.len()
        ));
    }

    let public_key = secp256k1::PublicKey::from_slice(&response[1..public_key_end])
        .map_err(|_| "Ledger returned an invalid secp256k1 public key")?
        .serialize();
    let address = String::from_utf8(response[address_start..address_end].to_vec())
        .map_err(|_| "Ledger public-key address is not valid UTF-8")?;
    if address.is_empty() {
        return Err("Ledger public-key response returned an empty address".into());
    }
    let chain_code = response[address_end..]
        .try_into()
        .map_err(|_| "Ledger public-key response has an invalid chain code")?;
    Ok(WalletPublicKey {
        public_key,
        address,
        chain_code,
    })
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
    fn wallet_identity_plan_uses_no_display_and_standard_paths() {
        let commands = wallet_identity_commands(Some(7)).unwrap();
        assert_eq!(commands.len(), 2);
        assert_eq!(
            (
                commands[0].cla,
                commands[0].ins,
                commands[0].p1,
                commands[0].p2
            ),
            (0xe0, 0x40, 0, 0)
        );
        assert_eq!(
            commands[0].data,
            hex::decode("038000002c8000008580000000").unwrap()
        );
        assert_eq!(
            commands[1].data,
            hex::decode("058000002c80000085800000070000000000000000").unwrap()
        );
    }

    #[test]
    fn wallet_public_key_response_is_strict_and_canonicalized() {
        let secret = secp256k1::SecretKey::from_slice(&[7; 32]).unwrap();
        let key = secp256k1::PublicKey::from_secret_key(&secp256k1::Secp256k1::new(), &secret);
        let mut response = vec![65];
        response.extend_from_slice(&key.serialize_uncompressed());
        response.push(4);
        response.extend_from_slice(b"t1ok");
        response.extend_from_slice(&[9; 32]);

        let parsed = decode_wallet_public_key(&response).unwrap();
        assert_eq!(parsed.public_key, key.serialize());
        assert_eq!(parsed.address, "t1ok");
        assert_eq!(parsed.chain_code, [9; 32]);

        let mut trailing = response.clone();
        trailing.push(0);
        assert!(decode_wallet_public_key(&trailing)
            .unwrap_err()
            .contains("expected"));
        response[1..66].fill(0);
        assert!(decode_wallet_public_key(&response)
            .unwrap_err()
            .contains("invalid secp256k1"));
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
