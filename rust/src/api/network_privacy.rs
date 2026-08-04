use std::path::Path;

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use tonic::Request;
use zcash_client_backend::proto::{
    compact_formats::CompactBlock,
    service::{compact_tx_streamer_client::CompactTxStreamerClient, BlockId, ChainSpec, Empty},
};
use zcash_client_backend::tor::http::HttpError;

pub use crate::network_privacy::NetworkPrivacyStatus;

/// Configures the process-wide network route used by wallet gRPC and HTTP
/// clients. Enabling is fail-closed: the desired route changes before Tor
/// bootstrapping starts, so a bootstrap failure cannot fall back to clearnet.
pub async fn configure_network_privacy(
    enabled: bool,
    tor_directory: String,
) -> Result<NetworkPrivacyStatus, String> {
    if enabled {
        crate::network_privacy::enable_tor(Path::new(&tor_directory)).await
    } else {
        crate::network_privacy::disable_tor();
        Ok(NetworkPrivacyStatus::Direct)
    }
}

/// Returns the current runtime state. `Bootstrapping` and `Failed` both mean
/// that app network requests are blocked while Tor remains the desired route.
#[flutter_rust_bridge::frb(sync)]
pub fn get_network_privacy_status() -> NetworkPrivacyStatus {
    crate::network_privacy::status()
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_tor_enabled() -> bool {
    crate::network_privacy::is_tor_desired()
}

pub struct ImportBirthdayMetadata {
    pub sapling_activation_height: u64,
    pub sapling_activation_time: u32,
    pub tip_height: u64,
    pub tip_time: u32,
}

pub struct NetworkHttpHeader {
    pub name: String,
    pub value: String,
}

pub struct NetworkHttpResponse {
    pub status_code: u16,
    pub headers: Vec<NetworkHttpHeader>,
    pub body: Vec<u8>,
}

/// Makes a GET request on a fresh Tor circuit. Dart calls this only after its
/// process-wide route check has selected Tor; direct requests stay in Dart so
/// existing test injection and platform behaviour remain unchanged.
pub async fn tor_http_get(
    url: String,
    headers: Vec<NetworkHttpHeader>,
) -> Result<NetworkHttpResponse, String> {
    let client = crate::network_privacy::tor_client_for_route(true)?
        .ok_or_else(|| "Tor is not enabled".to_string())?;
    let uri = url
        .parse()
        .map_err(|error| format!("Invalid HTTP URL: {error}"))?;
    let response = client
        .http_get(
            uri,
            |builder| apply_headers(builder, &headers),
            collect_body,
            0,
            |_| None,
        )
        .await
        .map_err(|error| error.to_string())?;
    network_http_response(response)
}

/// Makes a POST request on a fresh Tor circuit. Every app-owned HTTP call is
/// isolated from wallet gRPC and from other HTTP destinations.
pub async fn tor_http_post(
    url: String,
    headers: Vec<NetworkHttpHeader>,
    body: Vec<u8>,
) -> Result<NetworkHttpResponse, String> {
    let client = crate::network_privacy::tor_client_for_route(true)?
        .ok_or_else(|| "Tor is not enabled".to_string())?;
    let uri = url
        .parse()
        .map_err(|error| format!("Invalid HTTP URL: {error}"))?;
    let response = client
        .http_post(
            uri,
            |builder| apply_headers(builder, &headers),
            Full::new(Bytes::from(body)),
            collect_body,
            0,
            |_| None,
        )
        .await
        .map_err(|error| error.to_string())?;
    network_http_response(response)
}

fn apply_headers(
    mut builder: http::request::Builder,
    headers: &[NetworkHttpHeader],
) -> http::request::Builder {
    for header in headers {
        builder = builder.header(&header.name, &header.value);
    }
    builder
}

async fn collect_body(
    body: hyper::body::Incoming,
) -> Result<Vec<u8>, zcash_client_backend::tor::Error> {
    Ok(body
        .collect()
        .await
        .map_err(HttpError::from)?
        .to_bytes()
        .to_vec())
}

fn network_http_response(response: http::Response<Vec<u8>>) -> Result<NetworkHttpResponse, String> {
    let status_code = response.status().as_u16();
    let headers = response
        .headers()
        .iter()
        .map(|(name, value)| {
            Ok(NetworkHttpHeader {
                name: name.as_str().to_string(),
                value: value
                    .to_str()
                    .map_err(|error| format!("Invalid response header {name}: {error}"))?
                    .to_string(),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(NetworkHttpResponse {
        status_code,
        headers,
        body: response.into_body(),
    })
}

pub async fn get_import_birthday_metadata(
    lightwalletd_url: String,
) -> Result<ImportBirthdayMetadata, String> {
    let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
        .await
        .map_err(|error| error.to_string())?;
    let info = client
        .get_lightd_info(Request::new(Empty {}))
        .await
        .map_err(|error| format!("GetLightdInfo: {error}"))?
        .into_inner();
    let tip = client
        .get_latest_block(Request::new(ChainSpec {}))
        .await
        .map_err(|error| format!("GetLatestBlock: {error}"))?
        .into_inner();
    let sapling_activation_height = info.sapling_activation_height;
    let sapling_activation_time = block_at_height(&mut client, sapling_activation_height)
        .await?
        .time;
    let tip_time = block_at_height(&mut client, tip.height).await?.time;

    Ok(ImportBirthdayMetadata {
        sapling_activation_height,
        sapling_activation_time,
        tip_height: tip.height,
        tip_time,
    })
}

pub async fn estimate_import_birthday_height(
    lightwalletd_url: String,
    target_epoch_seconds: i64,
) -> Result<u64, String> {
    let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
        .await
        .map_err(|error| error.to_string())?;
    let info = client
        .get_lightd_info(Request::new(Empty {}))
        .await
        .map_err(|error| format!("GetLightdInfo: {error}"))?
        .into_inner();
    let tip = client
        .get_latest_block(Request::new(ChainSpec {}))
        .await
        .map_err(|error| format!("GetLatestBlock: {error}"))?
        .into_inner();

    let mut low = info.sapling_activation_height;
    let mut high = tip.height;
    let sapling_time = i64::from(block_at_height(&mut client, low).await?.time);
    if target_epoch_seconds <= sapling_time {
        return Ok(low);
    }
    let tip_time = i64::from(block_at_height(&mut client, high).await?.time);
    if target_epoch_seconds >= tip_time {
        return Ok(high);
    }

    while low < high {
        let mid = low + (high - low) / 2;
        let mid_time = i64::from(block_at_height(&mut client, mid).await?.time);
        if mid_time < target_epoch_seconds {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    Ok(low)
}

async fn block_at_height(
    client: &mut CompactTxStreamerClient<tonic::transport::Channel>,
    height: u64,
) -> Result<CompactBlock, String> {
    client
        .get_block(Request::new(BlockId {
            height,
            hash: Vec::new(),
        }))
        .await
        .map_err(|error| format!("GetBlock({height}): {error}"))
        .map(|response| response.into_inner())
}
