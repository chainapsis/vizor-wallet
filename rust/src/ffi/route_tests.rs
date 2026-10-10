//! Route tests for the iOS migration outbox C ABI, against a local recording
//! lightwalletd. Every assertion about traffic counts accepted TCP connections
//! and received RPCs at the server, not a flag inside the client.

use super::*;
use crate::network_privacy::{
    begin_tor_enable, disable_tor, fail_tor_enable, test_route_policy::lock_route_policy,
};
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use prost::Message;
use std::ffi::CString;
use std::sync::{atomic::AtomicUsize, Arc, Mutex};
use zcash_client_backend::proto::service::{BlockId, RawTransaction, SendResponse};

const TIP_HEIGHT: u64 = 3_456_789;

/// Plaintext HTTP/2 lightwalletd on loopback that records what reaches it.
struct RecordingLwd {
    url: CString,
    connections: Arc<AtomicUsize>,
    rpcs: Arc<Mutex<Vec<(String, Vec<u8>)>>>,
    /// Signalled when a SendTransaction request has fully arrived.
    send_received: Arc<tokio::sync::Notify>,
    /// While set, SendTransaction responses wait for `release_send`.
    hold_send: bool,
    release_send: Arc<tokio::sync::Notify>,
    runtime: Option<tokio::runtime::Runtime>,
}

impl Drop for RecordingLwd {
    fn drop(&mut self) {
        if let Some(runtime) = self.runtime.take() {
            runtime.shutdown_background();
        }
    }
}

impl RecordingLwd {
    fn start() -> Self {
        Self::start_with(false)
    }

    fn start_holding_send() -> Self {
        Self::start_with(true)
    }

    fn start_with(hold_send: bool) -> Self {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .unwrap();
        // Bound synchronously: async tests construct this inside their own
        // runtime, where `block_on` is not allowed.
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let url = CString::new(format!("http://{}", listener.local_addr().unwrap())).unwrap();
        let connections = Arc::new(AtomicUsize::new(0));
        let rpcs = Arc::new(Mutex::new(Vec::new()));
        let send_received = Arc::new(tokio::sync::Notify::new());
        let release_send = Arc::new(tokio::sync::Notify::new());
        {
            let connections = connections.clone();
            let rpcs = rpcs.clone();
            let send_received = send_received.clone();
            let release_send = release_send.clone();
            runtime.spawn(async move {
                let listener = tokio::net::TcpListener::from_std(listener).unwrap();
                loop {
                    let Ok((stream, _)) = listener.accept().await else {
                        return;
                    };
                    connections.fetch_add(1, Ordering::SeqCst);
                    let rpcs = rpcs.clone();
                    let send_received = send_received.clone();
                    let release_send = release_send.clone();
                    tokio::spawn(async move {
                        let service = hyper::service::service_fn(
                            move |request: hyper::Request<hyper::body::Incoming>| {
                                let rpcs = rpcs.clone();
                                let send_received = send_received.clone();
                                let release_send = release_send.clone();
                                async move {
                                    let method =
                                        request.uri().path().rsplit('/').next().unwrap().to_owned();
                                    let body =
                                        request.into_body().collect().await.unwrap().to_bytes();
                                    let payload = body[5..].to_vec();
                                    rpcs.lock().unwrap().push((method.clone(), payload.clone()));
                                    let message = match method.as_str() {
                                        "GetLatestBlock" => BlockId {
                                            height: TIP_HEIGHT,
                                            hash: vec![],
                                        }
                                        .encode_to_vec(),
                                        "SendTransaction" => {
                                            send_received.notify_one();
                                            if hold_send {
                                                release_send.notified().await;
                                            }
                                            let raw = RawTransaction::decode(&payload[..]).unwrap();
                                            SendResponse {
                                                error_code: 0,
                                                error_message: format!("{} bytes", raw.data.len()),
                                            }
                                            .encode_to_vec()
                                        }
                                        _ => panic!("unexpected migration RPC: {method}"),
                                    };
                                    let mut frame = vec![0];
                                    frame.extend_from_slice(&(message.len() as u32).to_be_bytes());
                                    frame.extend_from_slice(&message);
                                    Ok::<_, std::convert::Infallible>(
                                        hyper::Response::builder()
                                            .header("content-type", "application/grpc")
                                            .header("grpc-status", "0")
                                            .body(Full::new(Bytes::from(frame)))
                                            .unwrap(),
                                    )
                                }
                            },
                        );
                        let _ = hyper::server::conn::http2::Builder::new(
                            hyper_util::rt::TokioExecutor::new(),
                        )
                        .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
                        .await;
                    });
                }
            });
        }
        Self {
            url,
            connections,
            rpcs,
            send_received,
            hold_send,
            release_send,
            runtime: Some(runtime),
        }
    }

    fn url_str(&self) -> &str {
        self.url.to_str().unwrap()
    }

    fn connections(&self) -> usize {
        self.connections.load(Ordering::SeqCst)
    }

    fn methods(&self) -> Vec<String> {
        self.rpcs
            .lock()
            .unwrap()
            .iter()
            .map(|(method, _)| method.clone())
            .collect()
    }

    fn assert_untouched(&self, context: &str) {
        assert_eq!(self.connections(), 0, "{context}: a connection reached lightwalletd");
        assert!(self.methods().is_empty(), "{context}: {:?}", self.methods());
    }
}

/// Calls the tip entry point Swift links, the way Swift calls it.
fn latest_block_height(server: &RecordingLwd) -> (i32, u64) {
    let mut height = 0;
    let code = zcash_lightwalletd_routed_latest_block_height(
        server.url.as_ptr(),
        &mut height,
        std::ptr::null(),
    );
    (code, height)
}

/// Calls the broadcast entry point Swift links, the way Swift calls it.
fn send_transaction(server: &RecordingLwd, raw: &[u8]) -> (i32, i32, String) {
    let mut error_code = -1;
    let mut message = vec![0 as c_char; 4096];
    let code = zcash_lightwalletd_routed_send_transaction(
        server.url.as_ptr(),
        raw.as_ptr(),
        raw.len(),
        &mut error_code,
        message.as_mut_ptr(),
        message.len(),
        std::ptr::null(),
    );
    let message = unsafe { CStr::from_ptr(message.as_ptr()) }
        .to_string_lossy()
        .into_owned();
    (code, error_code, message)
}

fn observe_transaction(server: &RecordingLwd) -> i32 {
    let mut output = CLightwalletdTransactionObservation::not_found();
    zcash_lightwalletd_observe_transaction(
        server.url.as_ptr(),
        [7u8; 32].as_ptr(),
        32,
        &mut output,
        std::ptr::null(),
    )
}

#[test]
fn direct_route_reaches_lightwalletd_for_tip_and_broadcast() {
    // Positive control: with Tor off the outbox still submits, directly.
    let _policy = lock_route_policy();
    disable_tor();
    let server = RecordingLwd::start();

    assert_eq!(latest_block_height(&server), (0, TIP_HEIGHT));
    let (code, error_code, message) = send_transaction(&server, &[1, 2, 3]);

    assert_eq!((code, error_code), (0, 0));
    assert_eq!(message, "3 bytes");
    assert_eq!(server.methods(), ["GetLatestBlock", "SendTransaction"]);
}

#[test]
fn starting_or_failed_tor_sends_nothing_and_reports_route_blocked() {
    let _policy = lock_route_policy();
    let server = RecordingLwd::start();

    begin_tor_enable();
    assert_eq!(latest_block_height(&server).0, LIGHTWALLETD_RESULT_ROUTE_BLOCKED);
    assert_eq!(
        send_transaction(&server, &[1, 2, 3]).0,
        LIGHTWALLETD_RESULT_ROUTE_BLOCKED
    );
    assert_ne!(observe_transaction(&server), 0);
    server.assert_untouched("Tor starting");

    fail_tor_enable();
    assert_eq!(latest_block_height(&server).0, LIGHTWALLETD_RESULT_ROUTE_BLOCKED);
    assert_eq!(
        send_transaction(&server, &[1, 2, 3]).0,
        LIGHTWALLETD_RESULT_ROUTE_BLOCKED
    );
    assert_ne!(observe_transaction(&server), 0);
    server.assert_untouched("Tor failed");
}

#[test]
fn route_blocked_is_distinct_from_every_other_result() {
    for other in [
        0,
        1,
        2,
        LIGHTWALLETD_RESULT_CANCELLED,
        STATUS_RESULT_INCONCLUSIVE,
        STATUS_RESULT_UNSUPPORTED,
    ] {
        assert_ne!(LIGHTWALLETD_RESULT_ROUTE_BLOCKED, other);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_switch_to_tor_before_dispatch_refuses_the_broadcast() {
    let _policy = lock_route_policy();
    disable_tor();
    let server = RecordingLwd::start();

    // Tor is selected after the direct connection opened and before the
    // transaction is handed to it.
    let result = routed_send_transaction(server.url_str(), &[1, 2, 3], begin_tor_enable).await;

    assert!(
        matches!(result, Err(RoutedRequestError::RouteBlocked(_))),
        "{result:?}"
    );
    assert!(
        !server.methods().contains(&"SendTransaction".to_string()),
        "a broadcast went out directly after Tor was selected: {:?}",
        server.methods()
    );

    // Nothing new reaches the server afterwards either.
    let connections = server.connections();
    let blocked = routed_send_transaction(server.url_str(), &[1, 2, 3], || {}).await;
    assert!(matches!(blocked, Err(RoutedRequestError::RouteBlocked(_))));
    let tip = routed_latest_block_height(server.url_str()).await;
    assert!(matches!(tip, Err(RoutedRequestError::RouteBlocked(_))));
    assert_eq!(server.connections(), connections);
    assert!(server.methods().is_empty(), "{:?}", server.methods());
}

#[tokio::test(flavor = "multi_thread")]
async fn a_broadcast_already_dispatched_completes_across_a_switch_to_tor() {
    let _policy = lock_route_policy();
    disable_tor();
    let server = RecordingLwd::start_holding_send();
    assert!(server.hold_send);

    let url = server.url_str().to_owned();
    let broadcast =
        tokio::spawn(async move { routed_send_transaction(&url, &[1, 2, 3, 4], || {}).await });
    tokio::time::timeout(Duration::from_secs(10), server.send_received.notified())
        .await
        .expect("the broadcast reached lightwalletd");

    // The user turns Tor on while the response is outstanding. Cancelling now
    // could not unsend the transaction; it would only lose its outcome.
    begin_tor_enable();
    let drain = tokio::spawn(crate::network_privacy::wait_for_direct_connections_to_close(
        Duration::from_secs(10),
    ));
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(
        !drain.is_finished(),
        "the Tor switch must wait for the dispatched broadcast"
    );
    server.release_send.notify_one();

    let response = tokio::time::timeout(Duration::from_secs(10), broadcast)
        .await
        .expect("the broadcast finished")
        .expect("the broadcast task")
        .expect("the dispatched broadcast keeps its response");
    assert_eq!(response.error_code, 0);
    assert_eq!(response.error_message, "4 bytes");
    drain
        .await
        .expect("the drain task")
        .expect("the committed connection closes once its response is read");
    assert_eq!(server.methods(), ["SendTransaction"]);

    // The next pass is refused without touching the network.
    let connections = server.connections();
    let blocked = routed_send_transaction(server.url_str(), &[1, 2, 3, 4], || {}).await;
    assert!(matches!(blocked, Err(RoutedRequestError::RouteBlocked(_))));
    assert_eq!(server.connections(), connections);
    assert_eq!(server.methods(), ["SendTransaction"]);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_switch_to_tor_mid_tip_request_is_not_completed_directly() {
    // The tip request holds no commitment, so the lease cancels it like any
    // other direct request and the caller learns the route refused it.
    let _policy = lock_route_policy();
    disable_tor();
    let server = RecordingLwd::start();
    let mut channel = crate::wallet::sync_engine::open_native_migration_lwd_channel(
        server.url_str(),
        false,
        None,
    )
    .await
    .expect("direct channel");
    assert!(channel.direct);

    begin_tor_enable();
    let result = crate::wallet::sync_engine::get_latest_block(&mut channel.client).await;

    assert!(result.is_err(), "a direct tip request completed after Tor was selected");
    assert!(server.methods().is_empty(), "{:?}", server.methods());
}

/// Swift can only link what the bridging header declares, so this pins the
/// outbox to the routed entry points: an always-direct tip or broadcast cannot
/// be reintroduced for the foreground without changing this list.
#[test]
fn ios_header_declares_only_routed_outbox_requests() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let header = std::fs::read_to_string(root.join("ios/Runner/zcash_sync.h")).unwrap();
    let client =
        std::fs::read_to_string(root.join("ios/Runner/NativeLightwalletdClient.swift")).unwrap();
    for routed in [
        "zcash_lightwalletd_routed_latest_block_height(",
        "zcash_lightwalletd_routed_send_transaction(",
    ] {
        assert!(header.contains(routed), "header lacks {routed}");
        assert!(client.contains(routed), "Swift client does not call {routed}");
    }
    for direct in [
        "zcash_lightwalletd_latest_block_height(",
        "zcash_lightwalletd_send_transaction(",
    ] {
        assert!(!header.contains(direct), "header still declares {direct}");
    }
}
