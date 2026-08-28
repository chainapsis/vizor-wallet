use ledger_transport::{APDUAnswer, APDUCommand};
use ledger_transport_hid::hidapi::{HidApi, HidDevice};

#[cfg(debug_assertions)]
use std::{
    env,
    io::{Read, Write},
    net::{IpAddr, SocketAddr, TcpStream},
};

#[cfg(debug_assertions)]
use serde_json::{json, Value};
#[cfg(debug_assertions)]
use url::{Host, Url};

use super::{
    apdu::{
        decode_ufvk_chunks, decode_wallet_public_key, map_status_word, ufvk_commands,
        wallet_identity_commands, WalletPublicKey,
    },
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

#[cfg(debug_assertions)]
const SPECULOS_UFVK_API_URL: &str = "VIZOR_LEDGER_SPECULOS_UFVK_API_URL";
#[cfg(debug_assertions)]
const SPECULOS_SIGNING_API_URL: &str = "VIZOR_LEDGER_SPECULOS_SIGNING_API_URL";
#[cfg(debug_assertions)]
const SPECULOS_IO_POLL_MILLIS: u64 = 100;
#[cfg(debug_assertions)]
const SPECULOS_MAX_RESPONSE_BYTES: usize = 1024 * 1024;

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

enum Backend {
    Hid(HidDevice),
    #[cfg(debug_assertions)]
    Speculos(SpeculosClient),
}

#[derive(Clone, Copy)]
enum TransportPurpose {
    Device,
    Ufvk,
    Signing,
}

pub(super) struct LedgerTransport {
    backend: Backend,
    operation: OperationContext,
}

impl LedgerTransport {
    pub(super) fn connect(operation: OperationContext) -> Result<Self, String> {
        Self::connect_for(operation, TransportPurpose::Device)
    }

    pub(super) fn connect_ufvk(operation: OperationContext) -> Result<Self, String> {
        Self::connect_for(operation, TransportPurpose::Ufvk)
    }

    pub(super) fn connect_signing(operation: OperationContext) -> Result<Self, String> {
        Self::connect_for(operation, TransportPurpose::Signing)
    }

    fn connect_for(operation: OperationContext, purpose: TransportPurpose) -> Result<Self, String> {
        operation.check()?;
        #[cfg(debug_assertions)]
        if let Some(client) = SpeculosClient::from_environment(purpose)? {
            operation.check()?;
            return Ok(Self {
                backend: Backend::Speculos(client),
                operation,
            });
        }
        #[cfg(not(debug_assertions))]
        let _ = purpose;

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
        Ok(Self {
            backend: Backend::Hid(device),
            operation,
        })
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

    pub(super) fn wallet_identity(&self) -> Result<WalletPublicKey, String> {
        let mut commands = wallet_identity_commands()?.into_iter();
        let identity_command = commands
            .next()
            .ok_or("Ledger wallet identity plan is empty")?;
        let identity = decode_wallet_public_key(&self.exchange(
            identity_command.ins,
            identity_command.p1,
            identity_command.p2,
            identity_command.data,
        )?)?;
        Ok(identity)
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
        let response = match &self.backend {
            Backend::Hid(_) => {
                self.operation.check()?;
                self.write_apdu(&command.serialize())?;
                let answer = match self.read_apdu() {
                    Ok(answer) => answer,
                    Err(_) => return Ok(()),
                };
                APDUAnswer::from_answer(answer)
                    .map_err(|_| "Ledger HID response was too short to contain a status word")?
            }
            #[cfg(debug_assertions)]
            Backend::Speculos(_) => self.exchange_hid(&command)?,
        };
        if response.retcode() != RESPONSE_OK {
            return Err(map_status_word(response.retcode()));
        }
        Ok(())
    }

    fn exchange_hid(&self, command: &APDUCommand<Vec<u8>>) -> Result<APDUAnswer<Vec<u8>>, String> {
        self.operation.check()?;
        let answer = match &self.backend {
            Backend::Hid(_) => {
                self.write_apdu(&command.serialize())?;
                self.read_apdu()?
            }
            #[cfg(debug_assertions)]
            Backend::Speculos(client) => {
                client.exchange_apdu(&command.serialize(), self.operation)?
            }
        };
        APDUAnswer::from_answer(answer)
            .map_err(|_| "Ledger response was too short to contain a status word".into())
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

            let device = match &self.backend {
                Backend::Hid(device) => device,
                #[cfg(debug_assertions)]
                Backend::Speculos(_) => {
                    return Err("Internal error: attempted HID write through Speculos".into())
                }
            };
            let written = device
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
            let device = match &self.backend {
                Backend::Hid(device) => device,
                #[cfg(debug_assertions)]
                Backend::Speculos(_) => {
                    return Err("Internal error: attempted HID read through Speculos".into())
                }
            };
            let read = device
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

#[cfg(debug_assertions)]
#[derive(Debug)]
struct SpeculosClient {
    address: SocketAddr,
    host_header: String,
}

#[cfg(debug_assertions)]
impl SpeculosClient {
    fn from_environment(purpose: TransportPurpose) -> Result<Option<Self>, String> {
        let ufvk_url = env::var_os(SPECULOS_UFVK_API_URL)
            .map(|value| {
                value
                    .into_string()
                    .map_err(|_| format!("{SPECULOS_UFVK_API_URL} must be valid Unicode"))
            })
            .transpose()?;
        let signing_url = env::var_os(SPECULOS_SIGNING_API_URL)
            .map(|value| {
                value
                    .into_string()
                    .map_err(|_| format!("{SPECULOS_SIGNING_API_URL} must be valid Unicode"))
            })
            .transpose()?;
        Self::from_config(purpose, ufvk_url.as_deref(), signing_url.as_deref())
    }

    fn from_config(
        purpose: TransportPurpose,
        ufvk_url: Option<&str>,
        signing_url: Option<&str>,
    ) -> Result<Option<Self>, String> {
        if ufvk_url.is_none() && signing_url.is_none() {
            return Ok(None);
        }
        let missing_config = || {
            format!(
                "Speculos E2E transport requires both {SPECULOS_UFVK_API_URL} and {SPECULOS_SIGNING_API_URL}"
            )
        };
        let ufvk = Self::new(ufvk_url.ok_or_else(missing_config)?, SPECULOS_UFVK_API_URL)?;
        let signing = Self::new(
            signing_url.ok_or_else(missing_config)?,
            SPECULOS_SIGNING_API_URL,
        )?;
        if ufvk.address == signing.address {
            return Err(format!(
                "Speculos UFVK and signing endpoints must be different fresh instances; configure distinct ports in {SPECULOS_UFVK_API_URL} and {SPECULOS_SIGNING_API_URL}"
            ));
        }

        Ok(Some(match purpose {
            TransportPurpose::Device | TransportPurpose::Ufvk => ufvk,
            TransportPurpose::Signing => signing,
        }))
    }

    fn new(api_url: &str, variable: &str) -> Result<Self, String> {
        let url = Url::parse(api_url)
            .map_err(|error| format!("Invalid {variable} Speculos API URL: {error}"))?;
        if url.scheme() != "http" {
            return Err(format!("{variable} must use plain http for local Speculos"));
        }
        if !url.username().is_empty() || url.password().is_some() {
            return Err(format!("{variable} must not contain credentials"));
        }
        if url.path() != "/" || url.query().is_some() || url.fragment().is_some() {
            return Err(format!(
                "{variable} must contain only an origin, for example http://127.0.0.1:5000"
            ));
        }
        let ip = match url.host() {
            Some(Host::Ipv4(ip)) => IpAddr::V4(ip),
            Some(Host::Ipv6(ip)) => IpAddr::V6(ip),
            Some(Host::Domain(_)) => {
                return Err(format!(
                    "{variable} must use an explicit loopback IP address, not a hostname"
                ))
            }
            None => return Err(format!("{variable} is missing a host")),
        };
        if !ip.is_loopback() {
            return Err(format!("{variable} must use a loopback IP address"));
        }
        let port = url
            .port()
            .ok_or_else(|| format!("{variable} must include an explicit port"))?;
        Ok(Self {
            address: SocketAddr::new(ip, port),
            host_header: match ip {
                IpAddr::V4(_) => format!("{ip}:{port}"),
                IpAddr::V6(_) => format!("[{ip}]:{port}"),
            },
        })
    }

    fn exchange_apdu(
        &self,
        command: &[u8],
        operation: OperationContext,
    ) -> Result<Vec<u8>, String> {
        operation.check()?;
        let timeout = operation
            .remaining()
            .min(std::time::Duration::from_millis(SPECULOS_IO_POLL_MILLIS));
        if timeout.is_zero() {
            operation.check()?;
            return Err("Ledger operation timed out".into());
        }
        let mut stream = TcpStream::connect_timeout(&self.address, timeout)
            .map_err(|error| format!("Connect to Speculos API: {error}"))?;
        stream
            .set_read_timeout(Some(timeout))
            .map_err(|error| format!("Set Speculos read timeout: {error}"))?;
        stream
            .set_write_timeout(Some(timeout))
            .map_err(|error| format!("Set Speculos write timeout: {error}"))?;

        let body = json!({ "data": hex::encode(command) }).to_string();
        let request = format!(
            "POST /apdu HTTP/1.1\r\nHost: {}\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
            self.host_header,
            body.len(),
            body
        );
        stream
            .write_all(request.as_bytes())
            .map_err(|error| format!("Write Speculos APDU request: {error}"))?;

        let mut response = Vec::new();
        let mut buffer = [0u8; 4096];
        loop {
            operation.check()?;
            match stream.read(&mut buffer) {
                Ok(0) => break,
                Ok(read) => {
                    if response.len().saturating_add(read) > SPECULOS_MAX_RESPONSE_BYTES {
                        return Err("Speculos API response exceeded 1 MiB".into());
                    }
                    response.extend_from_slice(&buffer[..read]);
                }
                Err(error)
                    if matches!(
                        error.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) =>
                {
                    continue;
                }
                Err(error) => return Err(format!("Read Speculos APDU response: {error}")),
            }
        }
        operation.check()?;

        let body = decode_http_response(&response)?;
        let json: Value = serde_json::from_slice(&body)
            .map_err(|error| format!("Decode Speculos APDU JSON response: {error}"))?;
        let data = json
            .get("data")
            .and_then(Value::as_str)
            .ok_or("Speculos /apdu response is missing string field 'data'")?;
        hex::decode(data).map_err(|error| format!("Decode Speculos APDU response: {error}"))
    }
}

#[cfg(debug_assertions)]
fn decode_http_response(response: &[u8]) -> Result<Vec<u8>, String> {
    if response.len() > SPECULOS_MAX_RESPONSE_BYTES {
        return Err("Speculos API response exceeded 1 MiB".into());
    }
    let header_end = response
        .windows(4)
        .position(|window| window == b"\r\n\r\n")
        .ok_or("Speculos HTTP response is missing a header terminator")?;
    let headers = std::str::from_utf8(&response[..header_end])
        .map_err(|_| "Speculos HTTP response headers are not UTF-8")?;
    let status = headers
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|status| status.parse::<u16>().ok())
        .ok_or("Speculos HTTP response has an invalid status line")?;
    let body = &response[header_end + 4..];
    if !(200..300).contains(&status) {
        return Err(format!(
            "Speculos API returned HTTP {status}: {}",
            String::from_utf8_lossy(body)
        ));
    }
    let transfer_encoding = headers.lines().skip(1).find_map(|line| {
        line.split_once(':').and_then(|(name, value)| {
            name.eq_ignore_ascii_case("transfer-encoding")
                .then(|| value.trim())
        })
    });
    let content_length = headers.lines().skip(1).find_map(|line| {
        line.split_once(':').and_then(|(name, value)| {
            name.eq_ignore_ascii_case("content-length")
                .then(|| value.trim().parse::<usize>())
        })
    });
    if transfer_encoding.is_some() && content_length.is_some() {
        return Err(
            "Speculos HTTP response must not combine Transfer-Encoding and Content-Length".into(),
        );
    }
    if let Some(encoding) = transfer_encoding {
        let encodings = encoding.split(',').map(str::trim).collect::<Vec<_>>();
        if encodings.len() != 1 || !encodings[0].eq_ignore_ascii_case("chunked") {
            return Err("Speculos API returned an unsupported transfer encoding".into());
        }
        return decode_chunked_body(body);
    }
    if let Some(length) = content_length {
        let length = length.map_err(|_| "Speculos HTTP Content-Length is invalid")?;
        if body.len() != length {
            return Err(format!(
                "Speculos HTTP body length {} does not match Content-Length {length}",
                body.len()
            ));
        }
    }
    Ok(body.to_vec())
}

#[cfg(debug_assertions)]
fn decode_chunked_body(body: &[u8]) -> Result<Vec<u8>, String> {
    let mut cursor = 0usize;
    let mut decoded = Vec::new();
    loop {
        let line_end = find_crlf(body, cursor)
            .ok_or("Speculos chunked response is missing a chunk-size terminator")?;
        let size_line = std::str::from_utf8(&body[cursor..line_end])
            .map_err(|_| "Speculos chunk size is not UTF-8")?;
        let size_text = size_line
            .split_once(';')
            .map_or(size_line, |(size, _)| size)
            .trim();
        if size_text.is_empty() {
            return Err("Speculos chunked response has an empty chunk size".into());
        }
        let size = usize::from_str_radix(size_text, 16)
            .map_err(|_| "Speculos chunk size is not hexadecimal")?;
        cursor = line_end + 2;

        if size == 0 {
            loop {
                let trailer_end = find_crlf(body, cursor)
                    .ok_or("Speculos chunked response has incomplete trailers")?;
                if trailer_end == cursor {
                    cursor += 2;
                    if cursor != body.len() {
                        return Err("Speculos chunked response has bytes after its trailers".into());
                    }
                    return Ok(decoded);
                }
                cursor = trailer_end + 2;
            }
        }

        let chunk_end = cursor
            .checked_add(size)
            .ok_or("Speculos chunk size overflowed")?;
        let terminator_end = chunk_end
            .checked_add(2)
            .ok_or("Speculos chunk terminator overflowed")?;
        let chunk = body
            .get(cursor..chunk_end)
            .ok_or("Speculos chunked response ended mid-chunk")?;
        if body.get(chunk_end..terminator_end) != Some(b"\r\n") {
            return Err("Speculos chunked response has an invalid chunk terminator".into());
        }
        if decoded.len().saturating_add(chunk.len()) > SPECULOS_MAX_RESPONSE_BYTES {
            return Err("Decoded Speculos API response exceeded 1 MiB".into());
        }
        decoded.extend_from_slice(chunk);
        cursor = terminator_end;
    }
}

#[cfg(debug_assertions)]
fn find_crlf(bytes: &[u8], start: usize) -> Option<usize> {
    bytes
        .get(start..)?
        .windows(2)
        .position(|window| window == b"\r\n")
        .map(|offset| start + offset)
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

    #[cfg(debug_assertions)]
    #[test]
    fn speculos_url_accepts_only_explicit_loopback_http_origins() {
        let ipv4 = SpeculosClient::new("http://127.0.0.1:5004", "TEST_URL").unwrap();
        assert_eq!(ipv4.address, "127.0.0.1:5004".parse().unwrap());
        assert_eq!(ipv4.host_header, "127.0.0.1:5004");

        let ipv6 = SpeculosClient::new("http://[::1]:5005", "TEST_URL").unwrap();
        assert_eq!(ipv6.address, "[::1]:5005".parse().unwrap());
        assert_eq!(ipv6.host_header, "[::1]:5005");

        for url in [
            "https://127.0.0.1:5004",
            "http://localhost:5004",
            "http://192.0.2.1:5004",
            "http://127.0.0.1",
            "http://127.0.0.1:5004/apdu",
            "http://127.0.0.1:5004?mode=test",
            "http://user@127.0.0.1:5004",
        ] {
            assert!(
                SpeculosClient::new(url, "TEST_URL").is_err(),
                "unexpectedly accepted {url}"
            );
        }
    }

    #[cfg(debug_assertions)]
    #[test]
    fn speculos_config_routes_readiness_and_ufvk_separately_from_signing() {
        let ufvk_url = "http://127.0.0.1:5004";
        let signing_url = "http://127.0.0.1:5005";
        let device = SpeculosClient::from_config(
            TransportPurpose::Device,
            Some(ufvk_url),
            Some(signing_url),
        )
        .unwrap()
        .unwrap();
        let ufvk =
            SpeculosClient::from_config(TransportPurpose::Ufvk, Some(ufvk_url), Some(signing_url))
                .unwrap()
                .unwrap();
        let signing = SpeculosClient::from_config(
            TransportPurpose::Signing,
            Some(ufvk_url),
            Some(signing_url),
        )
        .unwrap()
        .unwrap();

        assert_eq!(device.address.port(), 5004);
        assert_eq!(ufvk.address.port(), 5004);
        assert_eq!(signing.address.port(), 5005);
        assert!(
            SpeculosClient::from_config(TransportPurpose::Ufvk, None, None)
                .unwrap()
                .is_none()
        );
        assert!(
            SpeculosClient::from_config(TransportPurpose::Signing, Some(ufvk_url), None,)
                .unwrap_err()
                .contains("requires both")
        );
        assert!(SpeculosClient::from_config(
            TransportPurpose::Signing,
            Some(ufvk_url),
            Some(ufvk_url),
        )
        .unwrap_err()
        .contains("must be different"));
    }

    #[cfg(debug_assertions)]
    #[test]
    fn speculos_http_response_requires_success_and_consistent_framing() {
        let response = b"HTTP/1.1 200 OK\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{\"data\":\"9000\"}";
        assert_eq!(
            decode_http_response(response).unwrap(),
            b"{\"data\":\"9000\"}"
        );

        let failed = b"HTTP/1.1 500 Error\r\nContent-Length: 4\r\n\r\nboom";
        assert!(decode_http_response(failed)
            .unwrap_err()
            .contains("HTTP 500"));

        let truncated = b"HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\n{}";
        assert!(decode_http_response(truncated)
            .unwrap_err()
            .contains("does not match"));

        let chunked = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n7;source=speculos\r\n{\"data\"\r\n8\r\n:\"9000\"}\r\n0\r\nX-Test: ok\r\n\r\n";
        assert_eq!(
            decode_http_response(chunked).unwrap(),
            b"{\"data\":\"9000\"}"
        );

        let conflicting = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 2\r\n\r\n2\r\n{}\r\n0\r\n\r\n";
        assert!(decode_http_response(conflicting)
            .unwrap_err()
            .contains("must not combine"));
    }

    #[cfg(debug_assertions)]
    #[test]
    fn speculos_chunked_response_rejects_incomplete_and_malformed_bodies() {
        for (body, expected) in [
            (b"2".as_slice(), "chunk-size terminator"),
            (b"x\r\n".as_slice(), "not hexadecimal"),
            (b"4\r\n{}".as_slice(), "ended mid-chunk"),
            (b"2\r\n{}xx".as_slice(), "invalid chunk terminator"),
            (b"0\r\n".as_slice(), "incomplete trailers"),
            (b"0\r\n\r\nextra".as_slice(), "bytes after"),
        ] {
            assert!(
                decode_chunked_body(body).unwrap_err().contains(expected),
                "unexpected error for {body:?}"
            );
        }
    }

    #[cfg(debug_assertions)]
    #[test]
    fn speculos_http_response_enforces_raw_and_decoded_limits() {
        let raw = vec![b'x'; SPECULOS_MAX_RESPONSE_BYTES + 1];
        assert!(decode_http_response(&raw)
            .unwrap_err()
            .contains("exceeded 1 MiB"));

        let payload = vec![b'x'; SPECULOS_MAX_RESPONSE_BYTES + 1];
        let mut chunked = format!("{:x}\r\n", payload.len()).into_bytes();
        chunked.extend_from_slice(&payload);
        chunked.extend_from_slice(b"\r\n0\r\n\r\n");
        assert!(decode_chunked_body(&chunked)
            .unwrap_err()
            .contains("Decoded Speculos API response exceeded 1 MiB"));
    }
}
