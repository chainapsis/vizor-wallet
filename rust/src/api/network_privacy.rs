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
use zcash_client_backend::tor::http::{HttpError, TimeoutPhase};

pub use crate::network_privacy::NetworkPrivacyStatus;

const TOR_API_RESPONSE_BODY_TIMEOUT: Duration = Duration::from_secs(30);
const TOR_HTTP_REQUEST_TIMEOUT_ERROR: &str = "Tor HTTP request timed out";
const TOR_HTTP_REQUEST_CANCELLED_ERROR: &str = "Tor HTTP request cancelled";
const MAINNET_SAPLING_ACTIVATION_HEIGHT: u64 = 419_200;
const MAINNET_SAPLING_ACTIVATION_TIME: u32 = 1_540_779_337;
const BIRTHDAY_ESTIMATE_TOLERANCE_SECONDS: i64 = 6 * 60 * 60;
const MAX_BIRTHDAY_CORRECTION_PROBES: usize = 2;
static TOR_HTTP_CANCELLATIONS: LazyLock<Mutex<HashMap<u64, tokio::sync::watch::Sender<bool>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_TOR_HTTP_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct BirthdayAnchor {
    height: u64,
    time: u32,
}

// Deep mainnet blocks are immutable enough to serve as interpolation anchors.
// Blossom is included explicitly because its activation halved the target block
// interval. Later anchors keep accumulated mining-rate drift well below the
// existing 15-day wallet-birthday safety margin.
const MAINNET_BIRTHDAY_ANCHORS: [BirthdayAnchor; 7] = [
    BirthdayAnchor {
        height: MAINNET_SAPLING_ACTIVATION_HEIGHT,
        time: MAINNET_SAPLING_ACTIVATION_TIME,
    },
    BirthdayAnchor {
        height: 653_600,
        time: 1_576_101_005,
    },
    BirthdayAnchor {
        height: 1_000_000,
        time: 1_602_206_541,
    },
    BirthdayAnchor {
        height: 1_500_000,
        time: 1_639_913_234,
    },
    BirthdayAnchor {
        height: 2_000_000,
        time: 1_677_602_242,
    },
    BirthdayAnchor {
        height: 2_500_000,
        time: 1_715_296_781,
    },
    BirthdayAnchor {
        height: 3_000_000,
        time: 1_752_983_473,
    },
];

/// Blocks new policy-aware direct requests immediately. Tor bootstrap is
/// intentionally separate so the caller can first quiesce channels that were
/// opened while direct mode was active.
#[flutter_rust_bridge::frb(sync)]
pub fn begin_network_privacy_enable() {
    crate::network_privacy::begin_tor_enable();
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
pub async fn tor_http_get(
    url: String,
    headers: Vec<NetworkHttpHeader>,
    timeout_milliseconds: Option<u64>,
    request_id: Option<u64>,
) -> Result<NetworkHttpResponse, String> {
    let response = with_tor_http_request_cancellation(request_id, async {
        let client = crate::network_privacy::tor_client_for_route(true)?
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
pub async fn tor_http_post(
    url: String,
    headers: Vec<NetworkHttpHeader>,
    body: Vec<u8>,
    timeout_milliseconds: Option<u64>,
    request_id: Option<u64>,
) -> Result<NetworkHttpResponse, String> {
    let response = with_tor_http_request_cancellation(request_id, async {
        let client = crate::network_privacy::tor_client_for_route(true)?
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
    let cancellations = TOR_HTTP_CANCELLATIONS
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if let Some(sender) = cancellations.get(&request_id) {
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
    let client = crate::network_privacy::tor_client_for_route(true)?
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

async fn with_tor_http_request_timeout<T, E>(
    timeout_milliseconds: Option<u64>,
    future: impl std::future::Future<Output = Result<T, E>>,
) -> Result<T, String>
where
    E: std::fmt::Display,
{
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
    result.map_err(|error| error.to_string())
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

    if use_mainnet_fast_path {
        match client
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
                if tip.height < MAINNET_SAPLING_ACTIVATION_HEIGHT
                    || tip.time < MAINNET_SAPLING_ACTIVATION_TIME
                {
                    return Err("Mainnet tip predates Sapling activation".to_string());
                }
                return Ok(ImportBirthdayMetadata {
                    sapling_activation_height: MAINNET_SAPLING_ACTIVATION_HEIGHT,
                    sapling_activation_time: MAINNET_SAPLING_ACTIVATION_TIME,
                    tip_height: tip.height,
                    tip_time: tip.time,
                });
            }
            Err(error) if error.code() == tonic::Code::Unimplemented => {
                // Older custom lightwalletd servers may not expose the combined
                // tip state. Continue with the legacy four-request metadata path.
            }
            Err(error) => return Err(format!("GetLatestTreeState: {error}")),
        }
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
    let mut client = crate::wallet::sync_engine::open_lwd_channel(&lightwalletd_url)
        .await
        .map_err(|error| error.to_string())?;

    if use_mainnet_fast_path {
        if let (Some(tip_height), Some(tip_time)) = (tip_height, tip_time) {
            if let Some(height) = estimate_mainnet_birthday_height(
                &mut client,
                target_epoch_seconds,
                BirthdayAnchor {
                    height: tip_height,
                    time: tip_time,
                },
            )
            .await?
            {
                return Ok(height);
            }

            return binary_search_birthday_height(
                &mut client,
                MAINNET_SAPLING_ACTIVATION_HEIGHT,
                tip_height,
                target_epoch_seconds,
            )
            .await;
        }
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

    binary_search_birthday_height(
        &mut client,
        info.sapling_activation_height,
        tip.height,
        target_epoch_seconds,
    )
    .await
}

async fn estimate_mainnet_birthday_height(
    client: &mut CompactTxStreamerClient<tonic::transport::Channel>,
    target_epoch_seconds: i64,
    tip: BirthdayAnchor,
) -> Result<Option<u64>, String> {
    if target_epoch_seconds <= i64::from(MAINNET_SAPLING_ACTIVATION_TIME) {
        return Ok(Some(MAINNET_SAPLING_ACTIVATION_HEIGHT));
    }
    if target_epoch_seconds >= i64::from(tip.time) {
        return Ok(Some(tip.height));
    }

    let Some((lower, upper)) = mainnet_anchor_segment(target_epoch_seconds, tip) else {
        return Ok(None);
    };
    let Some(mut candidate) = interpolate_height(lower, upper, target_epoch_seconds) else {
        return Ok(None);
    };

    for probe_index in 0..=MAX_BIRTHDAY_CORRECTION_PROBES {
        let candidate_time = i64::from(block_at_height(client, candidate).await?.time);
        let error = target_epoch_seconds - candidate_time;
        if error.abs() <= BIRTHDAY_ESTIMATE_TOLERANCE_SECONDS {
            return Ok(Some(candidate));
        }
        if probe_index == MAX_BIRTHDAY_CORRECTION_PROBES {
            break;
        }

        let Some(corrected) = correct_estimated_height(lower, upper, candidate, error) else {
            return Ok(None);
        };
        if corrected == candidate {
            return Ok(None);
        }
        candidate = corrected;
    }

    Ok(None)
}

fn mainnet_anchor_segment(
    target_epoch_seconds: i64,
    tip: BirthdayAnchor,
) -> Option<(BirthdayAnchor, BirthdayAnchor)> {
    let mut anchors = MAINNET_BIRTHDAY_ANCHORS
        .iter()
        .copied()
        .take_while(|anchor| anchor.height < tip.height)
        .collect::<Vec<_>>();
    let previous = anchors.last().copied()?;
    if tip.height <= previous.height || tip.time <= previous.time {
        return None;
    }
    anchors.push(tip);

    anchors.windows(2).find_map(|pair| {
        let lower = pair[0];
        let upper = pair[1];
        (target_epoch_seconds <= i64::from(upper.time)).then_some((lower, upper))
    })
}

fn interpolate_height(
    lower: BirthdayAnchor,
    upper: BirthdayAnchor,
    target_epoch_seconds: i64,
) -> Option<u64> {
    let time_span = i128::from(upper.time.checked_sub(lower.time)?);
    let height_span = i128::from(upper.height.checked_sub(lower.height)?);
    let target_delta = i128::from(target_epoch_seconds - i64::from(lower.time));
    let height_delta = divide_round_nearest(target_delta * height_span, time_span)?;
    u64::try_from(
        (i128::from(lower.height) + height_delta)
            .clamp(i128::from(lower.height), i128::from(upper.height)),
    )
    .ok()
}

fn correct_estimated_height(
    lower: BirthdayAnchor,
    upper: BirthdayAnchor,
    current_height: u64,
    time_error_seconds: i64,
) -> Option<u64> {
    let time_span = i128::from(upper.time.checked_sub(lower.time)?);
    let height_span = i128::from(upper.height.checked_sub(lower.height)?);
    let correction = divide_round_nearest(i128::from(time_error_seconds) * height_span, time_span)?;
    u64::try_from(
        (i128::from(current_height) + correction)
            .clamp(i128::from(lower.height), i128::from(upper.height)),
    )
    .ok()
}

fn divide_round_nearest(numerator: i128, denominator: i128) -> Option<i128> {
    if denominator <= 0 {
        return None;
    }
    let adjustment = denominator / 2;
    Some(if numerator >= 0 {
        (numerator + adjustment) / denominator
    } else {
        (numerator - adjustment) / denominator
    })
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
        correct_estimated_height, interpolate_height, mainnet_anchor_segment,
        tor_http_begin_request, tor_http_cancel_request, with_api_response_body_timeout,
        with_tor_http_request_cancellation, with_tor_http_request_timeout, BirthdayAnchor,
        MAINNET_BIRTHDAY_ANCHORS,
    };

    #[test]
    fn mainnet_anchor_interpolation_preserves_anchor_heights() {
        let lower = MAINNET_BIRTHDAY_ANCHORS[1];
        let upper = MAINNET_BIRTHDAY_ANCHORS[2];

        assert_eq!(
            interpolate_height(lower, upper, i64::from(lower.time)),
            Some(lower.height)
        );
        assert_eq!(
            interpolate_height(lower, upper, i64::from(upper.time)),
            Some(upper.height)
        );
    }

    #[test]
    fn mainnet_anchor_interpolation_uses_blossom_as_interval_boundary() {
        let tip = BirthdayAnchor {
            height: 3_439_381,
            time: 1_786_094_043,
        };
        let blossom = MAINNET_BIRTHDAY_ANCHORS[1];

        assert_eq!(
            mainnet_anchor_segment(i64::from(blossom.time), tip),
            Some((MAINNET_BIRTHDAY_ANCHORS[0], blossom))
        );
        assert_eq!(
            mainnet_anchor_segment(i64::from(blossom.time) + 1, tip),
            Some((blossom, MAINNET_BIRTHDAY_ANCHORS[2]))
        );
    }

    #[test]
    fn mainnet_height_correction_moves_in_the_time_error_direction() {
        let lower = MAINNET_BIRTHDAY_ANCHORS[3];
        let upper = MAINNET_BIRTHDAY_ANCHORS[4];
        let current = 1_750_000;

        let later = correct_estimated_height(lower, upper, current, 3_600).unwrap();
        let earlier = correct_estimated_height(lower, upper, current, -3_600).unwrap();

        assert!(later > current);
        assert!(earlier < current);
    }

    #[test]
    fn inconsistent_mainnet_tip_disables_fast_estimation() {
        let last = *MAINNET_BIRTHDAY_ANCHORS.last().unwrap();
        let stale_tip = BirthdayAnchor {
            height: last.height + 1,
            time: last.time,
        };

        assert_eq!(
            mainnet_anchor_segment(i64::from(last.time), stale_tip),
            None
        );
    }

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
            std::future::pending::<Result<(), &'static str>>().await
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
