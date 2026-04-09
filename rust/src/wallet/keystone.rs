//! Keystone hardware wallet integration.
//!
//! Communicates with Keystone 3 via USB (EAPDU protocol) or provides
//! UR encoding/decoding for QR-based communication. Uses PCZT (ZIP-332)
//! for transaction signing.

use nusb::transfer::{Bulk, In, Out};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use ur_registry::traits::{RegistryItem, To, UR};
use ur_registry::zcash::zcash_accounts::ZcashAccounts;
use ur_registry::zcash::zcash_pczt::ZcashPczt;
use ur_parse_lib::keystone_ur_decoder::probe_decode;
use ur_parse_lib::keystone_ur_encoder::KeystoneUREncoder;

// ==================== USB Constants ====================

const KEYSTONE_VID: u16 = 0x1209;
const KEYSTONE_PID: u16 = 0x3001;
const USB_INTERFACE: u8 = 0;
const USB_ENDPOINT_OUT: u8 = 0x03;
const USB_ENDPOINT_IN: u8 = 0x83;
const EAPDU_HEADER_SIZE: usize = 9;
const USB_PACKET_SIZE: usize = 64;
const MAX_DATA_PER_PACKET: usize = USB_PACKET_SIZE - EAPDU_HEADER_SIZE;

const CMD_RESOLVE_UR: u16 = 0x0002;

// ==================== Data Types ====================

#[derive(Debug, Clone)]
pub struct KeystoneAccountInfo {
    pub name: String,
    pub ufvk: String,
    pub index: u32,
    pub seed_fingerprint: Vec<u8>,
}

// ==================== UR Encoding/Decoding ====================

/// Encode PCZT bytes as a UR string for QR display or USB transmission.
pub fn encode_pczt_to_ur(pczt_bytes: &[u8]) -> Result<String, String> {
    let zcash_pczt = ZcashPczt::new(pczt_bytes.to_vec());
    let cbor_bytes: Vec<u8> = zcash_pczt.try_into()
        .map_err(|e: ur_registry::error::URError| format!("CBOR encode failed: {e:?}"))?;
    let encoder = ur::Encoder::new(
        &cbor_bytes,
        cbor_bytes.len(), // single part
        ZcashPczt::get_registry_type().get_type(),
    ).map_err(|e| format!("UR encode failed: {e}"))?;
    let mut ks_encoder = KeystoneUREncoder::new(encoder);
    let ur_string = ks_encoder.next_part()
        .map_err(|e| format!("UR next_part failed: {e:?}"))?;
    Ok(ur_string.to_uppercase())
}

/// Decode a UR string (from QR scan or USB response) to PCZT bytes.
pub fn decode_ur_to_pczt(ur_string: &str) -> Result<Vec<u8>, String> {
    let result = probe_decode::<ZcashPczt>(ur_string.to_string())
        .map_err(|e| format!("UR decode failed: {e:?}"))?;
    match result.data {
        Some(pczt) => Ok(pczt.get_data()),
        None => Err("UR decode returned no data".into()),
    }
}

/// Decode a UR string containing ZcashAccounts.
pub fn decode_accounts_ur(ur_string: &str) -> Result<(Vec<u8>, Vec<KeystoneAccountInfo>), String> {
    let result = probe_decode::<ZcashAccounts>(ur_string.to_string())
        .map_err(|e| format!("UR decode failed: {e:?}"))?;
    let accounts = result.data.ok_or("UR decode returned no data")?;

    let seed_fp = accounts.get_seed_fingerprint();
    let infos: Vec<KeystoneAccountInfo> = accounts
        .get_accounts()
        .iter()
        .map(|a| KeystoneAccountInfo {
            name: a.get_name().unwrap_or_else(|| format!("Keystone {}", a.get_index())),
            ufvk: a.get_ufvk(),
            index: a.get_index(),
            seed_fingerprint: seed_fp.clone(),
        })
        .collect();

    Ok((seed_fp, infos))
}

// ==================== USB EAPDU Protocol ====================

/// Encode data into EAPDU packets for USB transmission.
fn encode_eapdu_packets(command: u16, request_id: u16, data: &[u8]) -> Vec<Vec<u8>> {
    let total_packets = if data.is_empty() {
        1
    } else {
        (data.len() + MAX_DATA_PER_PACKET - 1) / MAX_DATA_PER_PACKET
    };
    let mut packets = Vec::with_capacity(total_packets);

    for i in 0..total_packets {
        let chunk_start = i * MAX_DATA_PER_PACKET;
        let chunk_end = std::cmp::min(chunk_start + MAX_DATA_PER_PACKET, data.len());
        let chunk = if data.is_empty() {
            &[] as &[u8]
        } else {
            &data[chunk_start..chunk_end]
        };

        let mut pkt = vec![0u8; EAPDU_HEADER_SIZE + chunk.len()];
        pkt[0] = 0x00; // CLA
        pkt[1..3].copy_from_slice(&command.to_be_bytes());
        pkt[3..5].copy_from_slice(&(total_packets as u16).to_be_bytes());
        pkt[5..7].copy_from_slice(&(i as u16).to_be_bytes());
        pkt[7..9].copy_from_slice(&request_id.to_be_bytes());
        pkt[EAPDU_HEADER_SIZE..].copy_from_slice(chunk);
        packets.push(pkt);
    }

    packets
}

// ==================== USB Device Communication ====================

/// Check if a Keystone device is connected via USB.
pub async fn is_keystone_connected() -> bool {
    match nusb::list_devices().await {
        Ok(devices) => devices
            .into_iter()
            .any(|d| d.vendor_id() == KEYSTONE_VID && d.product_id() == KEYSTONE_PID),
        Err(_) => false,
    }
}

/// Sign PCZT bytes via Keystone USB. Returns signed PCZT bytes.
pub async fn usb_sign_pczt(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    let ur_string = encode_pczt_to_ur(pczt_bytes)?;

    // Find and open device
    let device_info = nusb::list_devices()
        .await
        .map_err(|e| format!("USB enumerate failed: {e}"))?
        .into_iter()
        .find(|d| d.vendor_id() == KEYSTONE_VID && d.product_id() == KEYSTONE_PID)
        .ok_or("Keystone device not found")?;

    let device = device_info
        .open()
        .await
        .map_err(|e| format!("USB open failed: {e}"))?;
    let interface = device
        .claim_interface(USB_INTERFACE)
        .await
        .map_err(|e| format!("USB claim interface failed: {e}"))?;

    let mut writer = interface
        .endpoint::<Bulk, Out>(USB_ENDPOINT_OUT)
        .map_err(|e| format!("USB endpoint OUT failed: {e}"))?
        .writer(USB_PACKET_SIZE)
        .with_num_transfers(4);

    let mut reader = interface
        .endpoint::<Bulk, In>(USB_ENDPOINT_IN)
        .map_err(|e| format!("USB endpoint IN failed: {e}"))?
        .reader(USB_PACKET_SIZE)
        .with_num_transfers(4);

    // Send EAPDU packets
    let request_id: u16 = rand::random();
    let packets = encode_eapdu_packets(CMD_RESOLVE_UR, request_id, ur_string.as_bytes());
    log::info!(
        "keystone: sending {} EAPDU packets ({} bytes)",
        packets.len(),
        ur_string.len()
    );

    for pkt in &packets {
        writer
            .write_all(pkt)
            .await
            .map_err(|e| format!("USB write failed: {e}"))?;
    }
    writer
        .flush()
        .await
        .map_err(|e| format!("USB flush failed: {e}"))?;

    log::info!("keystone: waiting for user confirmation on device...");

    // Read response — accumulate until we have all packets
    let mut response_data = Vec::new();
    let mut buf = [0u8; USB_PACKET_SIZE];

    // Read first packet to get total count
    let n = reader
        .read(&mut buf)
        .await
        .map_err(|e| format!("USB read failed: {e}"))?;
    if n < EAPDU_HEADER_SIZE + 2 {
        return Err(format!("Response too short: {n} bytes"));
    }

    let resp_total = u16::from_be_bytes([buf[3], buf[4]]);
    let status = u16::from_be_bytes([buf[n - 2], buf[n - 1]]);
    if n > EAPDU_HEADER_SIZE + 2 {
        response_data.extend_from_slice(&buf[EAPDU_HEADER_SIZE..n - 2]);
    }

    // Read remaining packets
    for _ in 1..resp_total {
        let n = reader
            .read(&mut buf)
            .await
            .map_err(|e| format!("USB read failed: {e}"))?;
        if n > EAPDU_HEADER_SIZE + 2 {
            response_data.extend_from_slice(&buf[EAPDU_HEADER_SIZE..n - 2]);
        }
    }

    if status != 0x0000 {
        return Err(format!("Keystone returned error: 0x{:04X}", status));
    }

    // Parse JSON response: {"payload": "UR:ZCASH-PCZT/..."}
    let response_str =
        String::from_utf8(response_data).map_err(|e| format!("Response not UTF-8: {e}"))?;
    let json: serde_json::Value =
        serde_json::from_str(&response_str).map_err(|e| format!("Response not JSON: {e}"))?;
    let signed_ur = json
        .get("payload")
        .and_then(|v| v.as_str())
        .ok_or("Missing 'payload' in response")?;

    log::info!(
        "keystone: received signed response ({} bytes)",
        signed_ur.len()
    );

    decode_ur_to_pczt(signed_ur)
}
