use ledger_transport::{APDUAnswer, APDUCommand};
use ledger_transport_hid::hidapi::{HidApi, HidDevice};

use super::{
    apdu::{decode_ufvk_chunks, map_status_word, ufvk_commands},
    serializer::{packet_p1, packet_p2, CommandPackets},
    OperationContext,
};

const ZCASH_CLA: u8 = 0xe0;
const BOLOS_CLA: u8 = 0xb0;
const GET_APP_AND_VERSION: u8 = 0x01;
const OPEN_APP: u8 = 0xd8;
const CLOSE_APP: u8 = 0xa7;
const RESPONSE_OK: u16 = 0x9000;
const LEDGER_VID: u16 = 0x2c97;
const LEDGER_USAGE_PAGE: u16 = 0xffa0;
const LEDGER_CHANNEL: u16 = 0x0101;
const LEDGER_TAG: u8 = 0x05;
const HID_WRITE_SIZE: usize = 65;
const HID_READ_SIZE: usize = 64;
const HID_POLL_MILLIS: u64 = 100;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct RunningDeviceApp {
    pub name: String,
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct TransparentSignature {
    /// DER-encoded ECDSA signature. Ledger uses the low bit of the DER sequence
    /// tag to return the public-key parity, so callers must clear that bit before
    /// parsing the DER value.
    pub signature: Vec<u8>,
    pub sighash_type: u8,
}

pub(super) struct LedgerTransport {
    device: HidDevice,
    operation: OperationContext,
}

impl LedgerTransport {
    pub(super) fn connect(operation: OperationContext) -> Result<Self, String> {
        operation.check()?;
        let hid = HidApi::new().map_err(|e| format!("Initialize Ledger HID: {e}"))?;
        let device_info = hid
            .device_list()
            .find(|device| {
                device.vendor_id() == LEDGER_VID && device.usage_page() == LEDGER_USAGE_PAGE
            })
            .ok_or_else(|| "No Ledger device found. Connect and unlock the Nano S+.".to_string())?;
        let device = device_info
            .open_device(&hid)
            .map_err(|e| format!("Open Ledger HID device: {e}"))?;
        operation.check()?;
        Ok(Self { device, operation })
    }

    pub(super) fn current_app(&self) -> Result<RunningDeviceApp, String> {
        let data = self.exchange_with_cla(BOLOS_CLA, GET_APP_AND_VERSION, 0, 0, Vec::new())?;
        decode_app_and_version_response(&data)
    }

    pub(super) fn open_app(&self, name: &str) -> Result<(), String> {
        if !name.is_ascii() || name.is_empty() {
            return Err("Ledger app name must be non-empty ASCII".into());
        }
        self.exchange_allowing_disconnect(ZCASH_CLA, OPEN_APP, name.as_bytes().to_vec())?;
        Ok(())
    }

    pub(super) fn close_app(&self) -> Result<(), String> {
        self.exchange_allowing_disconnect(BOLOS_CLA, CLOSE_APP, Vec::new())?;
        Ok(())
    }

    pub(super) fn ufvk(&self, account_index: u32) -> Result<String, String> {
        let (first, continuation) = ufvk_commands(account_index)?;
        let mut chunks = vec![self.exchange(first.ins, first.p1, first.p2, first.data)?];
        let expected_len = chunks[0]
            .get(..2)
            .map(|prefix| 2 + u16::from_be_bytes([prefix[0], prefix[1]]) as usize)
            .ok_or_else(|| "Ledger UFVK response is missing its length prefix".to_string())?;
        while chunks.iter().map(Vec::len).sum::<usize>() < expected_len {
            chunks.push(self.exchange(
                continuation.ins,
                continuation.p1,
                continuation.p2,
                continuation.data.clone(),
            )?);
        }
        decode_ufvk_chunks(&chunks)
    }

    pub(super) fn send_pczt(&self, commands: &[CommandPackets]) -> Result<(), String> {
        for command in commands {
            let total = command.packets.len();
            if total == 0 {
                return Err("Ledger PCZT command has no packets".into());
            }
            for (index, packet) in command.packets.iter().enumerate() {
                self.exchange(
                    command.instruction,
                    packet_p1(index, total),
                    packet_p2(index, total, command.finishes_pczt),
                    packet.clone(),
                )
                .map_err(|error| {
                    format!(
                        "Ledger PCZT APDU {:#04x} packet {}/{} failed: {error}",
                        command.instruction,
                        index + 1,
                        total
                    )
                })?;
            }
        }
        Ok(())
    }

    pub(super) fn sign_action(
        &self,
        instruction: u8,
        action_index: usize,
    ) -> Result<[u8; 64], String> {
        let action_index =
            u8::try_from(action_index).map_err(|_| "Ledger action index exceeds the APDU range")?;
        let response = self.exchange(instruction, 0, action_index, Vec::new())?;
        let signature: [u8; 64] = response.try_into().map_err(|response: Vec<u8>| {
            format!(
                "Ledger returned a {}-byte spend authorization signature; expected 64",
                response.len()
            )
        })?;
        if signature.iter().all(|byte| *byte == 0) {
            return Err("Ledger returned an all-zero spend authorization signature".into());
        }
        Ok(signature)
    }

    pub(super) fn sign_transparent_input(
        &self,
        input_index: usize,
    ) -> Result<TransparentSignature, String> {
        let input_index =
            u8::try_from(input_index).map_err(|_| "Ledger input index exceeds the APDU range")?;
        let response = self.exchange(0x55, 0, input_index, Vec::new())?;
        decode_transparent_signature_response(response)
    }

    fn exchange(&self, ins: u8, p1: u8, p2: u8, data: Vec<u8>) -> Result<Vec<u8>, String> {
        self.exchange_with_cla(ZCASH_CLA, ins, p1, p2, data)
    }

    fn exchange_with_cla(
        &self,
        cla: u8,
        ins: u8,
        p1: u8,
        p2: u8,
        data: Vec<u8>,
    ) -> Result<Vec<u8>, String> {
        let command = build_command(cla, ins, p1, p2, data)?;
        let response = self.exchange_hid(&command)?;
        if response.retcode() != RESPONSE_OK {
            return Err(map_status_word(response.retcode()));
        }
        Ok(response.data().to_vec())
    }

    /// App transitions may detach HID before the status word reaches the host.
    /// Once the request is fully written, a missing read is treated as an
    /// indeterminate transition and the caller must reconnect and verify the
    /// running app before continuing.
    fn exchange_allowing_disconnect(&self, cla: u8, ins: u8, data: Vec<u8>) -> Result<(), String> {
        let command = build_command(cla, ins, 0, 0, data)?;
        self.operation.check()?;
        self.write_apdu(&command.serialize())?;
        let answer = match self.read_apdu() {
            Ok(answer) => answer,
            Err(_) => return Ok(()),
        };
        let response = APDUAnswer::from_answer(answer)
            .map_err(|_| "Ledger HID response was too short to contain a status word")?;
        if response.retcode() != RESPONSE_OK {
            return Err(map_status_word(response.retcode()));
        }
        Ok(())
    }

    fn exchange_hid(&self, command: &APDUCommand<Vec<u8>>) -> Result<APDUAnswer<Vec<u8>>, String> {
        self.operation.check()?;
        self.write_apdu(&command.serialize())?;
        let answer = self.read_apdu()?;
        APDUAnswer::from_answer(answer)
            .map_err(|_| "Ledger HID response was too short to contain a status word".into())
    }

    fn write_apdu(&self, command: &[u8]) -> Result<(), String> {
        let mut framed = Vec::with_capacity(command.len() + 2);
        framed.extend_from_slice(&(command.len() as u16).to_be_bytes());
        framed.extend_from_slice(command);

        for (sequence, chunk) in framed.chunks(HID_WRITE_SIZE - 6).enumerate() {
            self.operation.check()?;
            let sequence = u16::try_from(sequence)
                .map_err(|_| "Ledger HID request requires too many packets")?;
            let mut packet = [0u8; HID_WRITE_SIZE];
            packet[1..3].copy_from_slice(&LEDGER_CHANNEL.to_be_bytes());
            packet[3] = LEDGER_TAG;
            packet[4..6].copy_from_slice(&sequence.to_be_bytes());
            packet[6..6 + chunk.len()].copy_from_slice(chunk);

            let written = self
                .device
                .write(&packet)
                .map_err(|e| format!("Write Ledger HID packet: {e}"))?;
            if written != packet.len() {
                return Err(
                    "Ledger HID request was only partially written; reconnect and retry".into(),
                );
            }
        }
        Ok(())
    }

    fn read_apdu(&self) -> Result<Vec<u8>, String> {
        let mut answer = Vec::new();
        let mut expected_len = None;
        let mut expected_sequence = 0u16;

        loop {
            self.operation.check()?;
            let poll_millis = self
                .operation
                .remaining()
                .min(std::time::Duration::from_millis(HID_POLL_MILLIS))
                .as_millis()
                .max(1) as i32;
            let mut packet = [0u8; HID_READ_SIZE];
            let read = self
                .device
                .read_timeout(&mut packet, poll_millis)
                .map_err(|e| format!("Read Ledger HID packet: {e}"))?;
            if read == 0 {
                continue;
            }
            if read < 5 || (expected_sequence == 0 && read < 7) {
                return Err("Ledger HID response had an incomplete header".into());
            }
            if u16::from_be_bytes([packet[0], packet[1]]) != LEDGER_CHANNEL {
                return Err("Ledger HID response used an unexpected channel".into());
            }
            if packet[2] != LEDGER_TAG {
                return Err("Ledger HID response used an unexpected tag".into());
            }
            if u16::from_be_bytes([packet[3], packet[4]]) != expected_sequence {
                return Err("Ledger HID response packets arrived out of sequence".into());
            }

            let payload_start = if expected_sequence == 0 {
                let length = u16::from_be_bytes([packet[5], packet[6]]) as usize;
                expected_len = Some(length);
                7
            } else {
                5
            };
            let expected_len = expected_len.expect("first Ledger HID frame sets response length");
            let missing = expected_len.saturating_sub(answer.len());
            let available = read.saturating_sub(payload_start);
            let take = missing.min(available);
            answer.extend_from_slice(&packet[payload_start..payload_start + take]);

            if answer.len() == expected_len {
                return Ok(answer);
            }
            if take == 0 {
                return Err("Ledger HID response packet contained no payload".into());
            }
            expected_sequence = expected_sequence
                .checked_add(1)
                .ok_or_else(|| "Ledger HID response requires too many packets".to_string())?;
        }
    }
}

fn build_command(
    cla: u8,
    ins: u8,
    p1: u8,
    p2: u8,
    data: Vec<u8>,
) -> Result<APDUCommand<Vec<u8>>, String> {
    if data.len() > 255 {
        return Err(format!(
            "Ledger APDU payload exceeds 255 bytes: {}",
            data.len()
        ));
    }
    Ok(APDUCommand {
        cla,
        ins,
        p1,
        p2,
        data,
    })
}

fn decode_transparent_signature_response(
    response: Vec<u8>,
) -> Result<TransparentSignature, String> {
    // A secp256k1 DER signature is at most 72 bytes; Ledger appends one
    // sighash-type byte. The lower bound rejects empty/truncated DER values.
    if !(9..=73).contains(&response.len()) {
        return Err(format!(
            "Ledger returned a {}-byte transparent signature; expected DER plus sighash type",
            response.len()
        ));
    }

    let (signature, sighash_type) = response.split_at(response.len() - 1);
    if signature[0] & 0xfe != 0x30 {
        return Err("Ledger transparent signature has an invalid DER sequence tag".into());
    }
    if signature[1] as usize + 2 != signature.len() {
        return Err("Ledger transparent signature has an invalid DER length".into());
    }

    Ok(TransparentSignature {
        signature: signature.to_vec(),
        sighash_type: sighash_type[0],
    })
}

fn decode_app_and_version_response(response: &[u8]) -> Result<RunningDeviceApp, String> {
    let mut cursor = 0usize;
    let format = take_byte(response, &mut cursor, "format")?;
    if format != 1 {
        return Err(format!(
            "Ledger returned unsupported app-info format {format}"
        ));
    }

    let name = take_length_prefixed_string(response, &mut cursor, "app name")?;
    let version = take_length_prefixed_string(response, &mut cursor, "app version")?;

    if cursor < response.len() {
        let flags_len = take_byte(response, &mut cursor, "flags length")? as usize;
        let flags_end = cursor
            .checked_add(flags_len)
            .ok_or_else(|| "Ledger app-info flags length overflowed".to_string())?;
        if flags_end != response.len() {
            return Err("Ledger app-info response has malformed flags".into());
        }
    }

    Ok(RunningDeviceApp { name, version })
}

fn take_byte(response: &[u8], cursor: &mut usize, field: &str) -> Result<u8, String> {
    let value = response
        .get(*cursor)
        .copied()
        .ok_or_else(|| format!("Ledger app-info response is missing {field}"))?;
    *cursor += 1;
    Ok(value)
}

fn take_length_prefixed_string(
    response: &[u8],
    cursor: &mut usize,
    field: &str,
) -> Result<String, String> {
    let length = take_byte(response, cursor, &format!("{field} length"))? as usize;
    let end = cursor
        .checked_add(length)
        .ok_or_else(|| format!("Ledger {field} length overflowed"))?;
    let bytes = response
        .get(*cursor..end)
        .ok_or_else(|| format!("Ledger app-info response truncated {field}"))?;
    *cursor = end;
    std::str::from_utf8(bytes)
        .map(str::to_owned)
        .map_err(|_| format!("Ledger {field} is not valid UTF-8"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_words_are_actionable() {
        assert!(map_status_word(0x6985).contains("rejected"));
        assert!(map_status_word(0x5501).contains("rejected"));
        assert!(map_status_word(0x5515).contains("locked"));
        assert!(map_status_word(0x6982).contains("locked"));
        assert!(map_status_word(0x6601).contains("switching"));
        assert!(map_status_word(0x6807).contains("not installed"));
        assert!(map_status_word(0xb007).contains("reopen"));
        assert!(map_status_word(0x6d00).contains("running Ledger app"));
    }

    #[test]
    fn app_info_decodes_dashboard_and_running_app() {
        let dashboard = hex::decode("0105424f4c4f5309312e342e302d726332").unwrap();
        assert_eq!(
            decode_app_and_version_response(&dashboard).unwrap(),
            RunningDeviceApp {
                name: "BOLOS".into(),
                version: "1.4.0-rc2".into(),
            }
        );

        let app = hex::decode("01055a6361736805332e392e320102").unwrap();
        assert_eq!(
            decode_app_and_version_response(&app).unwrap(),
            RunningDeviceApp {
                name: "Zcash".into(),
                version: "3.9.2".into(),
            }
        );
    }

    #[test]
    fn device_management_apdus_match_ledger_protocol() {
        assert_eq!(
            build_command(BOLOS_CLA, GET_APP_AND_VERSION, 0, 0, vec![])
                .unwrap()
                .serialize(),
            [0xb0, 0x01, 0x00, 0x00, 0x00]
        );
        assert_eq!(
            build_command(ZCASH_CLA, OPEN_APP, 0, 0, b"Zcash".to_vec())
                .unwrap()
                .serialize(),
            [0xe0, 0xd8, 0x00, 0x00, 0x05, b'Z', b'c', b'a', b's', b'h']
        );
        assert_eq!(
            build_command(BOLOS_CLA, CLOSE_APP, 0, 0, vec![])
                .unwrap()
                .serialize(),
            [0xb0, 0xa7, 0x00, 0x00, 0x00]
        );
    }

    #[test]
    fn app_info_rejects_truncated_or_malformed_fields() {
        assert!(decode_app_and_version_response(&[2])
            .unwrap_err()
            .contains("unsupported"));
        assert!(decode_app_and_version_response(&[1, 5, b'Z'])
            .unwrap_err()
            .contains("truncated app name"));
        assert!(
            decode_app_and_version_response(&[1, 1, b'Z', 1, b'1', 2, 0])
                .unwrap_err()
                .contains("malformed flags")
        );
    }

    #[test]
    fn transparent_signature_response_preserves_der_and_sighash() {
        let mut response = hex::decode(
            "314402202b22627d88f9ecebf2ab586ffa970232cddad6eabb3289fa1359b2bc9f5554bc02207cfba5db7c01b89c5d540dcb1ada67d485ab1638c2151eaa78b4d368059c007801",
        )
        .unwrap();
        let expected = response[..response.len() - 1].to_vec();

        let decoded = decode_transparent_signature_response(std::mem::take(&mut response)).unwrap();
        assert_eq!(decoded.signature, expected);
        assert_eq!(decoded.sighash_type, 1);
    }

    #[test]
    fn transparent_signature_response_rejects_truncated_der() {
        assert!(decode_transparent_signature_response(vec![0x30, 1])
            .unwrap_err()
            .contains("expected DER"));

        let malformed = vec![0x30, 7, 2, 1, 1, 2, 1, 1, 1];
        assert!(decode_transparent_signature_response(malformed)
            .unwrap_err()
            .contains("DER length"));
    }
}
