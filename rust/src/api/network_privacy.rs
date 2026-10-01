use std::{
    collections::{hash_map::Entry, HashMap},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        LazyLock, Mutex,
    },
    time::Duration,
};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use tokio::io::AsyncWriteExt;
use tonic::Request;
use zcash_client_backend::proto::{
    compact_formats::CompactBlock,
    service::{compact_tx_streamer_client::CompactTxStreamerClient, BlockId, ChainSpec, Empty},
};
use zcash_client_backend::tor::{
    http::{HttpError, TimeoutPhase},
    Error as TorError,
};

pub use crate::network_privacy::NetworkPrivacyStatus;
use crate::wallet::birthday::{self, BirthdayAnchor, SAPLING_ACTIVATION};
use crate::wallet::network::WalletNetwork;

const TOR_API_RESPONSE_BODY_TIMEOUT: Duration = Duration::from_secs(30);
const TOR_HTTP_REQUEST_TIMEOUT_ERROR: &str = "Tor HTTP request timed out";
const TOR_HTTP_REQUEST_CANCELLED_ERROR: &str = "Tor HTTP request cancelled";
static TOR_HTTP_CANCELLATIONS: LazyLock<Mutex<HashMap<u64, tokio::sync::watch::Sender<bool>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_TOR_HTTP_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

/// Blocks new policy-aware direct requests immediately. Tor bootstrap is
/// intentionally separate so the caller can first quiesce channels that were
/// opened while direct mode was active.
#[flutter_rust_bridge::frb(sync)]
pub fn begin_network_privacy_enable() {
    crate::network_privacy::begin_tor_enable();
}

/// Publishes a failed enable when Dart gives up between
/// [begin_network_privacy_enable] and [configure_network_privacy] (for example
/// the direct drain did not finish). The route stays Tor-desired and
/// fail-closed; this only turns "still connecting" into a definite failure so
/// requests stop waiting for a bootstrap that is not running.
#[flutter_rust_bridge::frb(sync)]
pub fn fail_network_privacy_enable() {
    crate::network_privacy::fail_tor_enable();
}

/// Waits until direct tonic connections cancelled by
/// [begin_network_privacy_enable] have released their sockets.
pub async fn quiesce_network_privacy_direct_requests() -> Result<(), String> {
    crate::network_privacy::wait_for_direct_connections_to_close(Duration::from_secs(5)).await
}

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

/// Suspends or resumes Tor's circuit maintenance alongside the app lifecycle.
///
/// A bootstrapped client otherwise keeps guard connections and directory tasks
/// running while the app is in the background, which costs battery on mobile
/// and does work iOS will kill the app for. A no-op until Tor is connected.
#[flutter_rust_bridge::frb(sync)]
pub fn set_network_privacy_dormant(dormant: bool) {
    crate::network_privacy::set_tor_dormant(dormant);
}

/// Starts a token-protected loopback server that streams HTTPS update assets
/// from the embedded Tor client directly to a native desktop updater.
pub async fn start_tor_update_relay() -> Result<String, String> {
    crate::tor_update_relay::start().await
}

/// Stops the loopback update relay and cancels any active package transfer.
pub async fn stop_tor_update_relay() {
    crate::tor_update_relay::stop().await;
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
///
/// `timeout_milliseconds` bounds the HTTP exchange only. A request made while
/// Tor is still bootstrapping waits for the route first, under the bootstrap's
/// own deadline, and the caller's cancellation covers that wait.
pub async fn tor_http_get(
    url: String,
    headers: Vec<NetworkHttpHeader>,
    timeout_milliseconds: Option<u64>,
    request_id: Option<u64>,
) -> Result<NetworkHttpResponse, String> {
    let response = with_tor_http_request_cancellation(request_id, async {
        // The cancellation wrapper selects over this whole future, wait included.
        let client = crate::network_privacy::tor_client_for_route(true, || false)
            .await?
            .ok_or_else(|| "Tor is not enabled".to_string())?;
        let uri = url
            .parse()
            .map_err(|error| format!("Invalid HTTP URL: {error}"))?;
        with_tor_http_request_timeout(
            timeout_milliseconds,
            client.http_get(
                uri,
                |builder| apply_headers(builder, &headers),
                collect_body,
                0,
                |_| None,
            ),
        )
        .await
    })
    .await?;
    network_http_response(response)
}

/// Makes a POST request on a fresh Tor circuit. Every app-owned HTTP call is
/// isolated from wallet gRPC and from other HTTP destinations.
///
/// `timeout_milliseconds` bounds the HTTP exchange only. A request made while
/// Tor is still bootstrapping waits for the route first, under the bootstrap's
/// own deadline, and the caller's cancellation covers that wait.
pub async fn tor_http_post(
    url: String,
    headers: Vec<NetworkHttpHeader>,
    body: Vec<u8>,
    timeout_milliseconds: Option<u64>,
    request_id: Option<u64>,
) -> Result<NetworkHttpResponse, String> {
    let response = with_tor_http_request_cancellation(request_id, async {
        // The cancellation wrapper selects over this whole future, wait included.
        let client = crate::network_privacy::tor_client_for_route(true, || false)
            .await?
            .ok_or_else(|| "Tor is not enabled".to_string())?;
        let uri = url
            .parse()
            .map_err(|error| format!("Invalid HTTP URL: {error}"))?;
        with_tor_http_request_timeout(
            timeout_milliseconds,
            client.http_post(
                uri,
                |builder| apply_headers(builder, &headers),
                Full::new(Bytes::from(body)),
                collect_body,
                0,
                |_| None,
            ),
        )
        .await
    })
    .await?;
    network_http_response(response)
}

/// Reserves a process-unique cancellation token for one Tor HTTP request.
#[flutter_rust_bridge::frb(sync)]
pub fn tor_http_begin_request() -> u64 {
    loop {
        let request_id = NEXT_TOR_HTTP_REQUEST_ID.fetch_add(1, Ordering::Relaxed);
        if request_id == 0 {
            continue;
        }
        let mut cancellations = TOR_HTTP_CANCELLATIONS
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Entry::Vacant(entry) = cancellations.entry(request_id) {
            let (sender, _) = tokio::sync::watch::channel(false);
            entry.insert(sender);
            return request_id;
        }
    }
}

/// Cancels one in-flight Tor HTTP request without affecting other circuits.
#[flutter_rust_bridge::frb(sync)]
pub fn tor_http_cancel_request(request_id: u64) {
    let sender = TOR_HTTP_CANCELLATIONS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&request_id);
    if let Some(sender) = sender {
        sender.send_replace(true);
    }
}

async fn with_tor_http_request_cancellation<T>(
    request_id: Option<u64>,
    request: impl std::future::Future<Output = Result<T, String>>,
) -> Result<T, String> {
    let Some(request_id) = request_id else {
        return request.await;
    };
    let mut cancellation = {
        let cancellations = TOR_HTTP_CANCELLATIONS
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        cancellations
            .get(&request_id)
            .ok_or_else(|| "Tor HTTP request cancellation token is not registered".to_string())?
            .subscribe()
    };
    let result = if *cancellation.borrow() {
        Err(TOR_HTTP_REQUEST_CANCELLED_ERROR.to_string())
    } else {
        tokio::select! {
            result = request => result,
            _ = cancellation.changed() => Err(TOR_HTTP_REQUEST_CANCELLED_ERROR.to_string()),
        }
    };
    TOR_HTTP_CANCELLATIONS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&request_id);
    result
}

/// Streams an HTTP GET response over an isolated Tor route directly to disk.
/// This avoids moving large proving-parameter files through Rust and Dart
/// whole-body buffers.
pub async fn tor_http_download(
    url: String,
    headers: Vec<NetworkHttpHeader>,
    destination_path: String,
) -> Result<NetworkHttpResponse, String> {
    let client = crate::network_privacy::tor_client_for_route(true, || false)
        .await?
        .ok_or_else(|| "Tor is not enabled".to_string())?;
    let uri = url
        .parse()
        .map_err(|error| format!("Invalid HTTP URL: {error}"))?;
    let destination = PathBuf::from(destination_path);
    let response = client
        .http_get(
            uri,
            |builder| apply_headers(builder, &headers),
            move |body| write_body_to_file(body, destination),
            0,
            |_| None,
        )
        .await
        .map_err(|error| error.to_string())?;
    network_http_response(response.map(|_| Vec::new()))
}

async fn with_tor_http_request_timeout<T>(
    timeout_milliseconds: Option<u64>,
    future: impl std::future::Future<Output = Result<T, TorError>>,
) -> Result<T, String> {
    let result = match timeout_milliseconds {
        Some(0) => return Err("Tor HTTP request timeout must be positive".to_string()),
        Some(timeout_milliseconds) => {
            tokio::time::timeout(Duration::from_millis(timeout_milliseconds), future)
                .await
                .map_err(|_| {
                    format!("{TOR_HTTP_REQUEST_TIMEOUT_ERROR} after {timeout_milliseconds} ms")
                })?
        }
        None => future.await,
    };
    result.map_err(normalize_tor_http_error)
}

/// Gives Arti's phase-specific HTTP timeouts the stable marker consumed by
/// Dart, without relying on Arti's human-readable error wording across FFI.
fn normalize_tor_http_error(error: TorError) -> String {
    match &error {
        TorError::Http(HttpError::Timeout(phase)) => {
            format!("{TOR_HTTP_REQUEST_TIMEOUT_ERROR} while {phase}")
        }
        _ => error.to_string(),
    }
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
    with_api_response_body_timeout(TOR_API_RESPONSE_BODY_TIMEOUT, async move {
        Ok(body
            .collect()
            .await
            .map_err(HttpError::from)?
            .to_bytes()
            .to_vec())
    })
    .await
}

async fn with_api_response_body_timeout<T>(
    timeout: Duration,
    future: impl std::future::Future<Output = Result<T, zcash_client_backend::tor::Error>>,
) -> Result<T, zcash_client_backend::tor::Error> {
    tokio::time::timeout(timeout, future)
        .await
        .unwrap_or_else(|_| Err(HttpError::Timeout(TimeoutPhase::ResponseBody).into()))
}

async fn write_body_to_file(
    mut body: hyper::body::Incoming,
    destination: PathBuf,
) -> Result<(), zcash_client_backend::tor::Error> {
    let mut file = tokio::fs::File::create(destination).await?;
    while let Some(frame) = body.frame().await {
        let frame = frame.map_err(HttpError::from)?;
        if let Ok(data) = frame.into_data() {
            file.write_all(&data).await?;
        }
    }
    file.flush().await?;
    Ok(())
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
    use_mainnet_fast_path: bool,
) -> Result<ImportBirthdayMetadata, String> {
    let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
        .await
        .map_err(|error| error.to_string())?;

    if use_mainnet_fast_path && birthday::uses_mainnet_anchors(WalletNetwork::Main) {
        let tip = mainnet_tip(&mut client).await?;
        return Ok(ImportBirthdayMetadata {
            sapling_activation_height: SAPLING_ACTIVATION.height,
            sapling_activation_time: SAPLING_ACTIVATION.time,
            tip_height: tip.height,
            tip_time: tip.time,
        });
    }

    let info = client
        .get_lightd_info(timed_birthday_request(Empty {}))
        .await
        .map_err(|error| format!("GetLightdInfo: {error}"))?
        .into_inner();
    let tip = client
        .get_latest_block(timed_birthday_request(ChainSpec {}))
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
    use_mainnet_fast_path: bool,
    tip_height: Option<u64>,
    tip_time: Option<u32>,
) -> Result<u64, String> {
    if use_mainnet_fast_path && birthday::uses_mainnet_anchors(WalletNetwork::Main) {
        // Reuse metadata fetched by the birthday screen without even opening a
        // channel. Otherwise request only the public chain tip, never a height
        // inferred from the user's birthday.
        let tip = match (tip_height, tip_time) {
            (Some(height), Some(time)) => BirthdayAnchor { height, time },
            _ => {
                let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
                    .await
                    .map_err(|error| error.to_string())?;
                mainnet_tip(&mut client).await?
            }
        };
        return birthday::mainnet_height_for_time(target_epoch_seconds, tip);
    }

    let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
        .await
        .map_err(|error| error.to_string())?;

    let info = client
        .get_lightd_info(timed_birthday_request(Empty {}))
        .await
        .map_err(|error| format!("GetLightdInfo: {error}"))?
        .into_inner();
    let tip = client
        .get_latest_block(timed_birthday_request(ChainSpec {}))
        .await
        .map_err(|error| format!("GetLatestBlock: {error}"))?
        .into_inner();

    binary_search_birthday_height(
        &mut client,
        info.sapling_activation_height,
        tip.height,
        target_epoch_seconds,
    )
    .await
}

/// Public tip metadata; all request heights are independent of the wallet.
async fn mainnet_tip(
    client: &mut CompactTxStreamerClient<tonic::transport::Channel>,
) -> Result<BirthdayAnchor, String> {
    let tip = match client
        .get_latest_tree_state(timed_birthday_request(Empty {}))
        .await
    {
        Ok(response) => {
            let tip = response.into_inner();
            if !is_mainnet(&tip.network) {
                return Err(format!(
                    "Expected mainnet birthday metadata, endpoint reported {}",
                    tip.network
                ));
            }
            BirthdayAnchor {
                height: tip.height,
                time: tip.time,
            }
        }
        Err(error) if error.code() == tonic::Code::Unimplemented => {
            let tip = client
                .get_latest_block(timed_birthday_request(ChainSpec {}))
                .await
                .map_err(|error| format!("GetLatestBlock: {error}"))?
                .into_inner();
            let block = block_at_height(client, tip.height).await?;
            if block.height != tip.height {
                return Err("Latest block response has an unexpected height".to_string());
            }
            BirthdayAnchor {
                height: tip.height,
                time: block.time,
            }
        }
        Err(error) => return Err(format!("GetLatestTreeState: {error}")),
    };
    birthday::validate_mainnet_tip(tip)
}

async fn binary_search_birthday_height(
    client: &mut CompactTxStreamerClient<tonic::transport::Channel>,
    mut low: u64,
    mut high: u64,
    target_epoch_seconds: i64,
) -> Result<u64, String> {
    let sapling_time = i64::from(block_at_height(client, low).await?.time);
    if target_epoch_seconds <= sapling_time {
        return Ok(low);
    }
    let tip_time = i64::from(block_at_height(client, high).await?.time);
    if target_epoch_seconds >= tip_time {
        return Ok(high);
    }

    while low < high {
        let mid = low + (high - low) / 2;
        let mid_time = i64::from(block_at_height(client, mid).await?.time);
        if mid_time < target_epoch_seconds {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    Ok(low)
}

fn is_mainnet(network: &str) -> bool {
    matches!(network.trim(), "main" | "mainnet")
}

async fn block_at_height(
    client: &mut CompactTxStreamerClient<tonic::transport::Channel>,
    height: u64,
) -> Result<CompactBlock, String> {
    client
        .get_block(timed_birthday_request(BlockId {
            height,
            hash: Vec::new(),
        }))
        .await
        .map_err(|error| format!("GetBlock({height}): {error}"))
        .map(|response| response.into_inner())
}

fn timed_birthday_request<T>(message: T) -> Request<T> {
    let mut request = Request::new(message);
    request.set_timeout(Duration::from_secs(10));
    request
}

#[cfg(test)]
mod tests {
    use std::{
        sync::{
            atomic::{AtomicBool, Ordering},
            Arc,
        },
        time::Duration,
    };

    use zcash_client_backend::tor::{
        http::{HttpError, TimeoutPhase},
        Error,
    };

    use super::{
        normalize_tor_http_error, tor_http_begin_request, tor_http_cancel_request,
        with_api_response_body_timeout, with_tor_http_request_cancellation,
        with_tor_http_request_timeout, TOR_HTTP_REQUEST_TIMEOUT_ERROR,
    };

    #[tokio::test]
    async fn ordinary_http_body_stall_is_cancelled_before_download_deadline() {
        let result = with_api_response_body_timeout(
            Duration::from_millis(1),
            std::future::pending::<Result<(), Error>>(),
        )
        .await;

        assert!(matches!(
            result,
            Err(Error::Http(HttpError::Timeout(TimeoutPhase::ResponseBody)))
        ));
    }

    #[test]
    fn arti_http_timeout_phases_receive_the_stable_timeout_marker() {
        for phase in [
            TimeoutPhase::Connect,
            TimeoutPhase::Request,
            TimeoutPhase::ResponseBody,
        ] {
            let error = normalize_tor_http_error(Error::Http(HttpError::Timeout(phase)));
            assert!(
                error.starts_with(TOR_HTTP_REQUEST_TIMEOUT_ERROR),
                "unrecognized timeout: {error}"
            );
        }

        assert_eq!(
            normalize_tor_http_error(Error::Http(HttpError::NonHttpUrl)),
            "HTTP-over-Tor error: Only HTTP or HTTPS URLs are supported"
        );
    }

    #[tokio::test]
    async fn whole_http_deadline_drops_the_in_flight_tor_request() {
        struct DropSignal(Arc<AtomicBool>);

        impl Drop for DropSignal {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }

        let dropped = Arc::new(AtomicBool::new(false));
        let request_drop = Arc::clone(&dropped);
        let result = with_tor_http_request_timeout(Some(1), async move {
            let _drop_signal = DropSignal(request_drop);
            std::future::pending::<Result<(), Error>>().await
        })
        .await;

        assert_eq!(
            result,
            Err("Tor HTTP request timed out after 1 ms".to_string())
        );
        assert!(dropped.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn explicit_cancellation_drops_only_the_selected_tor_request() {
        let cancelled_id = tor_http_begin_request();
        let retained_id = tor_http_begin_request();
        let cancelled = tokio::spawn(with_tor_http_request_cancellation(
            Some(cancelled_id),
            std::future::pending::<Result<(), String>>(),
        ));
        let retained = tokio::spawn(with_tor_http_request_cancellation(
            Some(retained_id),
            std::future::pending::<Result<(), String>>(),
        ));
        tokio::task::yield_now().await;

        tor_http_cancel_request(cancelled_id);

        assert_eq!(
            cancelled.await.unwrap(),
            Err("Tor HTTP request cancelled".to_string())
        );
        assert!(!retained.is_finished());
        tor_http_cancel_request(retained_id);
        assert_eq!(
            retained.await.unwrap(),
            Err("Tor HTTP request cancelled".to_string())
        );
    }
}

#[cfg(test)]
#[path = "network_privacy/birthday_tests.rs"]
mod birthday_tests;
