//! Proxy delegation calls for Dart. Nothing reaches them while the
//! `VIZOR_PROXY_DELEGATION_ENABLED` build flag is off.

use crate::wallet::voting::{delegate_picture, participation};

/// The `vote` store keys, lowercase hex, that prove delegate entries
/// `delegate_indices`, in order. A check names 1 to 8 distinct indices,
/// none of them 0.
pub fn proxy_registry_entry_keys(delegate_indices: Vec<u32>) -> Result<Vec<String>, String> {
    Ok(participation::registry_entry_keys(&delegate_indices)?
        .iter()
        .map(hex::encode)
        .collect())
}

/// One delegate's registry entry as the chain proves it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiProvenRegistryEntry {
    /// Registry index `d`.
    pub delegate_index: u32,
    /// The `ProxyDelegateEntry` bytes zcash_voting decodes, or `None` when
    /// the chain proves the entry absent.
    pub entry: Option<Vec<u8>>,
}

/// Verifies `evidence` for the registry entries of `delegate_indices` under
/// `network`'s bundled trust anchor at `now_seconds`. The evidence is a
/// signed header, its validators and one proven `abci_query` answer per
/// entry key, in order, as Dart's registry proof client gathers them for
/// [`proxy_registry_entry_keys`].
pub fn verify_proxy_registry_entries(
    network: String,
    delegate_indices: Vec<u32>,
    evidence: String,
    now_seconds: i64,
) -> Result<Vec<ApiProvenRegistryEntry>, String> {
    let entries = participation::verify_registry_entries(
        &delegate_indices,
        &network,
        &evidence,
        now_seconds,
    )?;
    Ok(delegate_indices
        .into_iter()
        .zip(entries)
        .map(|(delegate_index, entry)| ApiProvenRegistryEntry {
            delegate_index,
            entry,
        })
        .collect())
}

/// A decoded delegate picture: `width` by `height` pixels, rows top to
/// bottom, RGBA with premultiplied alpha.
pub struct ApiDelegatePicture {
    /// Width in pixels.
    pub width: u32,
    /// Height in pixels.
    pub height: u32,
    /// `width * height * 4` bytes.
    pub rgba: Vec<u8>,
}

/// Decodes a wallet list row's `webp` picture in Rust within the caps in
/// `delegate_picture`. The signed list already bounds its size and shape;
/// any error means Vizor draws the identicon instead.
pub fn decode_delegate_picture(webp: Vec<u8>) -> Result<ApiDelegatePicture, String> {
    let picture = delegate_picture::decode(&webp).map_err(|error| format!("{error:?}"))?;
    Ok(ApiDelegatePicture {
        width: picture.width,
        height: picture.height,
        rgba: picture.rgba,
    })
}
