//! Keystone hardware wallet FRB API.

use crate::wallet::keystone;

pub struct KeystoneAccountInfo {
    pub name: String,
    pub ufvk: String,
    pub index: u32,
    pub seed_fingerprint: Vec<u8>,
}

/// Check if a Keystone device is connected via USB.
pub async fn is_keystone_connected() -> bool {
    keystone::is_keystone_connected().await
}

/// Sign PCZT bytes via Keystone USB. Returns signed PCZT bytes.
/// The device will display the transaction for user confirmation.
pub async fn keystone_usb_sign_pczt(pczt_bytes: Vec<u8>) -> Result<Vec<u8>, String> {
    keystone::usb_sign_pczt(&pczt_bytes).await
}

/// Encode PCZT bytes to a UR string for QR code display.
pub fn encode_pczt_to_ur(pczt_bytes: Vec<u8>) -> Result<String, String> {
    keystone::encode_pczt_to_ur(&pczt_bytes)
}

/// Decode a UR string (from QR scan) to PCZT bytes.
pub fn decode_ur_to_pczt(ur_string: String) -> Result<Vec<u8>, String> {
    keystone::decode_ur_to_pczt(&ur_string)
}

/// Decode a ZcashAccounts UR string to account info list.
pub fn decode_accounts_ur(ur_string: String) -> Result<Vec<KeystoneAccountInfo>, String> {
    let (_seed_fp, infos) = keystone::decode_accounts_ur(&ur_string)?;
    Ok(infos
        .into_iter()
        .map(|i| KeystoneAccountInfo {
            name: i.name,
            ufvk: i.ufvk,
            index: i.index,
            seed_fingerprint: i.seed_fingerprint,
        })
        .collect())
}
