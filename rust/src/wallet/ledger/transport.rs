use ledger_transport::{APDUAnswer, APDUCommand};
use ledger_transport_hid::hidapi::{HidApi, HidDevice};

use super::{
    apdu::{
        decode_ufvk_chunks, map_status_word, ufvk_commands, ufvk_expected_len,
        ApduCommand as ZcashApduCommand, ZCASH_CLA,
    },
    serializer::{packet_p1, packet_p2, CommandPackets},
    OperationContext,
};

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
const REVIEW_BUSY_STATUS: u16 = 0x6901;
const REVIEW_BUSY_MAX_ATTEMPTS: usize = 3;
const REVIEW_BUSY_RETRY_DELAY: std::time::Duration = std::time::Duration::from_millis(200);

fn is_ledger_interface(vendor_id: u16, usage_page: u16, interface: i32, is_linux: bool) -> bool {
    // Match Ledger's HID transport: Linux enumeration may omit the usage page.
    vendor_id == LEDGER_VID
        && if is_linux {
            interface == 0
        } else {
            usage_page == LEDGER_USAGE_PAGE
        }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct RunningDeviceApp {
    pub name: String,
    pub version: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct TransparentSignature {
    pub signature: Vec<u8>,
    pub sighash_type: u8,
}

pub(super) struct LedgerTransport {
    device: HidDevice,
    operation: OperationContext,
    model: Option<String>,
}

impl LedgerTransport {
    pub(super) fn connect(operation: OperationContext) -> Result<Self, String> {
        operation.check()?;
        let hid = HidApi::new().map_err(|error| classify_hid_error("Initialize", error))?;
        let device_info = hid
            .device_list()
            .find(|device| {
                is_ledger_interface(
                    device.vendor_id(),
                    device.usage_page(),
                    device.interface_number(),
                    cfg!(target_os = "linux"),
                )
            })
            .ok_or_else(|| "No Ledger device found. Connect and unlock the Ledger.".to_string())?;
        let model = device_info.product_string().map(str::to_owned);
        let device = device_info
            .open_device(&hid)
            .map_err(|error| classify_hid_error("Open", error))?;
        operation.check()?;
        Ok(Self {
            device,
            operation,
            model,
        })
    }

    pub(super) fn connect_signing(operation: OperationContext) -> Result<Self, String> {
        Self::connect(operation)
    }

    pub(super) fn connect_ufvk(operation: OperationContext) -> Result<Self, String> {
        Self::connect(operation)
    }

    pub(super) fn device_model(&self) -> Option<&str> {
        self.model.as_deref()
    }

    pub(super) fn current_app(&self) -> Result<RunningDeviceApp, String> {
        let data = self.exchange_with_cla(BOLOS_CLA, GET_APP_AND_VERSION, 0, 0, Vec::new())?;
        decode_app_and_version_response(&data)
    }

    pub(super) fn open_app(&self, name: &str) -> Result<(), String> {
        if !name.is_ascii() || name.is_empty() {
            return Err("Ledger app name must be non-empty ASCII".into());
        }
        self.exchange_allowing_disconnect(ZCASH_CLA, OPEN_APP, name.as_bytes().to_vec())
    }

    pub(super) fn close_app(&self) -> Result<(), String> {
        self.exchange_allowing_disconnect(BOLOS_CLA, CLOSE_APP, Vec::new())
    }

    pub(super) fn ufvk(&self, account_index: u32) -> Result<String, String> {
        collect_ufvk(
            account_index,
            |command| self.exchange(command.ins, command.p1, command.p2, command.data),
            || self.operation.check(),
        )
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
        let response = retry_review_busy(
            || self.exchange_hid(&command),
            |response| response.retcode(),
            || {
                self.operation.check()?;
                std::thread::sleep(REVIEW_BUSY_RETRY_DELAY);
                self.operation.check()
            },
        )?;
        if response.retcode() != RESPONSE_OK {
            return Err(map_status_word(response.retcode()));
        }
        Ok(response.data().to_vec())
    }

    /// App transitions can detach HID after the request is written but before
    /// its status word reaches the host. The caller reconnects and verifies
    /// the resulting app state before continuing.
    fn exchange_allowing_disconnect(&self, cla: u8, ins: u8, data: Vec<u8>) -> Result<(), String> {
        let command = build_command(cla, ins, 0, 0, data)?;
        self.operation.check()?;
        self.write_apdu(&command.serialize())?;
        let answer = match self.read_apdu() {
            Ok(answer) => answer,
            Err(_) => return Ok(()),
        };
        self.operation.check()?;
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
        self.operation.check()?;
        APDUAnswer::from_answer(answer)
            .map_err(|_| "Ledger response was too short to contain a status word".into())
    }

    fn write_apdu(&self, command: &[u8]) -> Result<(), String> {
        for packet in frame_hid_request(command)? {
            self.operation.check()?;
            let written = self
                .device
                .write(&packet)
                .map_err(|error| classify_hid_error("Write", error))?;
            if written != packet.len() {
                return Err(
                    "Ledger HID request was only partially written; reconnect and retry".into(),
                );
            }
        }
        Ok(())
    }

    fn read_apdu(&self) -> Result<Vec<u8>, String> {
        let mut response = HidResponse::new();
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
                .map_err(|error| classify_hid_error("Read", error))?;
            if read == 0 {
                continue;
            }
            if let Some(answer) = response.push(&packet[..read])? {
                return Ok(answer);
            }
        }
    }
}

fn classify_hid_error(action: &str, error: impl std::fmt::Display) -> String {
    format!("{action} Ledger HID device: {error}")
}

fn collect_ufvk(
    account_index: u32,
    mut exchange: impl FnMut(ZcashApduCommand) -> Result<Vec<u8>, String>,
    mut check: impl FnMut() -> Result<(), String>,
) -> Result<String, String> {
    let (first, continuation) = ufvk_commands(account_index)?;
    let first_chunk = exchange(first)?;
    check()?;
    let expected_len = ufvk_expected_len(&first_chunk)?;
    if first_chunk.len() > expected_len {
        return Err("Ledger UFVK response contains trailing bytes".into());
    }

    let mut received = first_chunk.len();
    let mut chunks = vec![first_chunk];
    while received < expected_len {
        let chunk = exchange(continuation.clone())?;
        check()?;
        if chunk.is_empty() {
            return Err("Ledger UFVK response ended before the declared length".into());
        }
        received = received
            .checked_add(chunk.len())
            .ok_or_else(|| "Ledger UFVK response length overflowed".to_string())?;
        if received > expected_len {
            return Err("Ledger UFVK response contains trailing bytes".into());
        }
        chunks.push(chunk);
    }
    decode_ufvk_chunks(&chunks)
}

fn frame_hid_request(command: &[u8]) -> Result<Vec<[u8; HID_WRITE_SIZE]>, String> {
    let command_len = u16::try_from(command.len())
        .map_err(|_| "Ledger APDU request exceeds the HID framing limit")?;
    let mut framed = Vec::with_capacity(command.len() + 2);
    framed.extend_from_slice(&command_len.to_be_bytes());
    framed.extend_from_slice(command);

    framed
        .chunks(HID_WRITE_SIZE - 6)
        .enumerate()
        .map(|(sequence, chunk)| {
            let sequence = u16::try_from(sequence)
                .map_err(|_| "Ledger HID request requires too many packets")?;
            let mut packet = [0u8; HID_WRITE_SIZE];
            packet[1..3].copy_from_slice(&LEDGER_CHANNEL.to_be_bytes());
            packet[3] = LEDGER_TAG;
            packet[4..6].copy_from_slice(&sequence.to_be_bytes());
            packet[6..6 + chunk.len()].copy_from_slice(chunk);
            Ok(packet)
        })
        .collect()
}

struct HidResponse {
    answer: Vec<u8>,
    expected_len: Option<usize>,
    expected_sequence: u16,
}

impl HidResponse {
    fn new() -> Self {
        Self {
            answer: Vec::new(),
            expected_len: None,
            expected_sequence: 0,
        }
    }

    fn push(&mut self, packet: &[u8]) -> Result<Option<Vec<u8>>, String> {
        if packet.len() < 5 || (self.expected_sequence == 0 && packet.len() < 7) {
            return Err("Ledger HID response had an incomplete header".into());
        }
        if u16::from_be_bytes([packet[0], packet[1]]) != LEDGER_CHANNEL {
            return Err("Ledger HID response used an unexpected channel".into());
        }
        if packet[2] != LEDGER_TAG {
            return Err("Ledger HID response used an unexpected tag".into());
        }
        if u16::from_be_bytes([packet[3], packet[4]]) != self.expected_sequence {
            return Err("Ledger HID response packets arrived out of sequence".into());
        }

        let payload_start = if self.expected_sequence == 0 {
            self.expected_len = Some(u16::from_be_bytes([packet[5], packet[6]]) as usize);
            7
        } else {
            5
        };
        let expected_len = self
            .expected_len
            .expect("first Ledger HID frame sets response length");
        let missing = expected_len.saturating_sub(self.answer.len());
        let take = missing.min(packet.len().saturating_sub(payload_start));
        self.answer
            .extend_from_slice(&packet[payload_start..payload_start + take]);
        if self.answer.len() == expected_len {
            return Ok(Some(std::mem::take(&mut self.answer)));
        }
        if take == 0 {
            return Err("Ledger HID response packet contained no payload".into());
        }
        self.expected_sequence = self
            .expected_sequence
            .checked_add(1)
            .ok_or_else(|| "Ledger HID response requires too many packets".to_string())?;
        Ok(None)
    }
}

fn retry_review_busy<T>(
    mut exchange: impl FnMut() -> Result<T, String>,
    status: impl Fn(&T) -> u16,
    mut wait: impl FnMut() -> Result<(), String>,
) -> Result<T, String> {
    for attempt in 0..REVIEW_BUSY_MAX_ATTEMPTS {
        let response = exchange()?;
        if status(&response) != REVIEW_BUSY_STATUS || attempt + 1 == REVIEW_BUSY_MAX_ATTEMPTS {
            return Ok(response);
        }
        wait()?;
    }
    unreachable!("the bounded Ledger review retry loop always returns")
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
    fn device_filter_handles_linux_without_a_usage_page() {
        assert!(is_ledger_interface(LEDGER_VID, 0, 0, true));
        assert!(is_ledger_interface(LEDGER_VID, LEDGER_USAGE_PAGE, 0, true));
        for interface in [-1, 1, 2] {
            assert!(!is_ledger_interface(LEDGER_VID, 0, interface, true));
            assert!(!is_ledger_interface(
                LEDGER_VID,
                LEDGER_USAGE_PAGE,
                interface,
                true
            ));
        }
        assert!(!is_ledger_interface(0x1234, 0, 0, true));

        // macOS and Windows still require the Ledger usage page.
        assert!(!is_ledger_interface(LEDGER_VID, 0, 0, false));
        assert!(is_ledger_interface(
            LEDGER_VID,
            LEDGER_USAGE_PAGE,
            -1,
            false
        ));
        assert!(!is_ledger_interface(0x1234, LEDGER_USAGE_PAGE, 0, false));
    }

    #[test]
    fn ufvk_exchange_is_bounded_before_and_during_continuation() {
        let mut reads = 0;
        let error = collect_ufvk(
            0,
            |_| {
                reads += 1;
                Ok(vec![0x20, 0])
            },
            || Ok(()),
        )
        .unwrap_err();
        assert!(error.contains("unreasonable length"));
        assert_eq!(reads, 1);

        let mut responses = vec![vec![0, 3, b'a'], Vec::new()].into_iter();
        let error = collect_ufvk(0, |_| Ok(responses.next().unwrap()), || Ok(())).unwrap_err();
        assert!(error.contains("before the declared length"));
    }

    #[test]
    fn ufvk_exchange_reassembles_valid_fragments_without_extra_reads() {
        let mut responses = vec![vec![0, 5, b'u'], vec![b'v', b'i'], vec![b'e', b'w']].into_iter();
        let mut reads = 0;
        let ufvk = collect_ufvk(
            3,
            |_| {
                reads += 1;
                Ok(responses.next().unwrap())
            },
            || Ok(()),
        )
        .unwrap();
        assert_eq!(ufvk, "uview");
        assert_eq!(reads, 3);
    }

    #[test]
    fn ufvk_exchange_discards_a_response_that_completes_after_cancellation() {
        let cancelled = std::cell::Cell::new(false);
        let mut reads = 0;
        let error = collect_ufvk(
            0,
            |_| {
                reads += 1;
                cancelled.set(true);
                Ok(vec![0, 1, b'a'])
            },
            || {
                if cancelled.get() {
                    Err("Ledger operation was cancelled. Retry when ready.".into())
                } else {
                    Ok(())
                }
            },
        )
        .unwrap_err();
        assert!(error.contains("cancelled"));
        assert_eq!(reads, 1);
    }

    #[test]
    fn hid_request_framing_and_response_headers_are_checked() {
        let command = vec![0x55; 80];
        let packets = frame_hid_request(&command).unwrap();
        assert_eq!(packets.len(), 2);
        assert_eq!(&packets[0][1..6], &[0x01, 0x01, 0x05, 0x00, 0x00]);
        assert_eq!(&packets[0][6..8], &[0, 80]);
        assert_eq!(&packets[1][1..6], &[0x01, 0x01, 0x05, 0x00, 0x01]);

        let mut response = HidResponse::new();
        assert!(response
            .push(&[0x01, 0x01, 0x05, 0, 0, 0, 3, 1])
            .unwrap()
            .is_none());
        assert_eq!(
            response.push(&[0x01, 0x01, 0x05, 0, 1, 2, 3]).unwrap(),
            Some(vec![1, 2, 3])
        );
        assert!(HidResponse::new()
            .push(&[0, 0, 5, 0, 0, 0, 1])
            .unwrap_err()
            .contains("channel"));
        assert!(HidResponse::new()
            .push(&[1, 1, 5, 0, 1, 0, 1])
            .unwrap_err()
            .contains("sequence"));
    }

    #[test]
    fn app_info_decodes_and_rejects_malformed_fields() {
        let app = hex::decode("01055a6361736805332e392e320102").unwrap();
        assert_eq!(
            decode_app_and_version_response(&app).unwrap(),
            RunningDeviceApp {
                name: "Zcash".into(),
                version: "3.9.2".into(),
            }
        );
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
    fn review_busy_retry_is_bounded() {
        let mut exchanges = 0;
        let response = retry_review_busy(
            || {
                exchanges += 1;
                Ok(REVIEW_BUSY_STATUS)
            },
            |status| *status,
            || Ok(()),
        )
        .unwrap();
        assert_eq!(response, REVIEW_BUSY_STATUS);
        assert_eq!(exchanges, REVIEW_BUSY_MAX_ATTEMPTS);
    }

    #[test]
    fn transparent_signature_response_preserves_parity_and_sighash() {
        let mut response = vec![0x31, 0x06, 0x02, 0x01, 1, 0x02, 0x01, 1];
        response.push(1);
        let decoded = decode_transparent_signature_response(response).unwrap();
        assert_eq!(decoded.signature[0], 0x31);
        assert_eq!(decoded.sighash_type, 1);
    }

    #[test]
    fn transparent_signature_response_rejects_malformed_der() {
        assert!(decode_transparent_signature_response(vec![0x30, 1])
            .unwrap_err()
            .contains("expected DER"));
        let malformed = vec![0x30, 0x07, 0x02, 0x01, 1, 0x02, 0x01, 1, 1];
        assert!(decode_transparent_signature_response(malformed)
            .unwrap_err()
            .contains("DER length"));
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
            [0xe0, 0xd8, 0, 0, 5, b'Z', b'c', b'a', b's', b'h']
        );
    }
}
