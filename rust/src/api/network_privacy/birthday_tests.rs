//! Request-recording tests for the real birthday API, without external services.

use super::*;
use prost::Message;
use std::sync::Arc;
use zcash_client_backend::proto::service::{BlockId, TreeState};

#[cfg(not(ironwood_masquerade))]
struct FakeLwd {
    url: String,
    calls: Arc<Mutex<Vec<(String, Option<u64>)>>>,
    task: tokio::task::JoinHandle<()>,
}

#[cfg(not(ironwood_masquerade))]
impl Drop for FakeLwd {
    fn drop(&mut self) {
        self.task.abort();
    }
}

#[cfg(not(ironwood_masquerade))]
impl FakeLwd {
    async fn start(latest_status: u8, network: &str, tip: BirthdayAnchor) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let calls = Arc::new(Mutex::new(Vec::new()));
        let server_calls = calls.clone();
        let network = network.to_owned();
        let task = tokio::spawn(async move {
            loop {
                let (stream, _) = listener.accept().await.unwrap();
                let calls = server_calls.clone();
                let network = network.clone();
                tokio::spawn(async move {
                    let service = hyper::service::service_fn(
                        move |request: hyper::Request<hyper::body::Incoming>| {
                            let calls = calls.clone();
                            let network = network.clone();
                            async move {
                                let method =
                                    request.uri().path().rsplit('/').next().unwrap().to_owned();
                                let body = request.into_body().collect().await.unwrap().to_bytes();
                                let height = if method == "GetBlock" {
                                    Some(BlockId::decode(&body[5..]).unwrap().height)
                                } else {
                                    None
                                };
                                calls.lock().unwrap().push((method.clone(), height));
                                let (status, message) = match method.as_str() {
                                    "GetLatestTreeState" if latest_status == 0 => (
                                        0,
                                        TreeState {
                                            network,
                                            height: tip.height,
                                            time: tip.time,
                                            ..Default::default()
                                        }
                                        .encode_to_vec(),
                                    ),
                                    "GetLatestTreeState" => (latest_status, vec![]),
                                    "GetLatestBlock" => (
                                        0,
                                        BlockId {
                                            height: tip.height,
                                            hash: vec![],
                                        }
                                        .encode_to_vec(),
                                    ),
                                    "GetBlock" if height == Some(tip.height) => (
                                        0,
                                        CompactBlock {
                                            height: tip.height,
                                            time: tip.time,
                                            ..Default::default()
                                        }
                                        .encode_to_vec(),
                                    ),
                                    _ => (3, vec![]),
                                };
                                let mut frame = vec![];
                                if status == 0 {
                                    frame.push(0);
                                    frame.extend_from_slice(&(message.len() as u32).to_be_bytes());
                                    frame.extend_from_slice(&message);
                                }
                                Ok::<_, std::convert::Infallible>(
                                    hyper::Response::builder()
                                        .header("content-type", "application/grpc")
                                        .header("grpc-status", status.to_string())
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
        Self { url, calls, task }
    }
}

fn tip() -> BirthdayAnchor {
    BirthdayAnchor {
        height: 3_498_200,
        time: 1_790_527_223,
    }
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn mainnet_birthday_with_metadata_needs_no_connection() {
    let height = estimate_import_birthday_height(
        "not-a-lightwalletd-url".to_owned(),
        1_659_305_748,
        true,
        Some(tip().height),
        Some(tip().time),
    )
    .await
    .unwrap();
    assert_eq!(height, 1_757_270);
    let invalid = estimate_import_birthday_height(
        "not-a-lightwalletd-url".to_owned(),
        1_659_305_748,
        true,
        Some(tip().height),
        Some(0),
    )
    .await
    .unwrap_err();
    assert!(invalid.contains("predates Sapling"), "{invalid}");
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn mainnet_birthday_without_metadata_requests_only_public_tip() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    let server = FakeLwd::start(0, "main", tip()).await;
    let height =
        estimate_import_birthday_height(server.url.clone(), 1_659_305_748, true, None, None)
            .await
            .unwrap();
    assert_eq!(height, 1_757_270);
    assert_eq!(
        *server.calls.lock().unwrap(),
        vec![("GetLatestTreeState".to_owned(), None)]
    );
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn mainnet_birthday_legacy_server_fetches_block_only_at_tip() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    let server = FakeLwd::start(12, "main", tip()).await;
    let height =
        estimate_import_birthday_height(server.url.clone(), 1_659_305_748, true, None, None)
            .await
            .unwrap();
    assert_eq!(height, 1_757_270);
    assert_eq!(
        *server.calls.lock().unwrap(),
        vec![
            ("GetLatestTreeState".to_owned(), None),
            ("GetLatestBlock".to_owned(), None),
            ("GetBlock".to_owned(), Some(tip().height)),
        ]
    );
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn mainnet_birthday_metadata_is_reused_and_errors_do_not_search() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    let server = FakeLwd::start(0, "main", tip()).await;
    let metadata = get_import_birthday_metadata(server.url.clone(), true)
        .await
        .unwrap();
    assert_eq!(metadata.tip_height, tip().height);
    assert_eq!(metadata.tip_time, tip().time);
    estimate_import_birthday_height(
        server.url.clone(),
        1_659_305_748,
        true,
        Some(metadata.tip_height),
        Some(metadata.tip_time),
    )
    .await
    .unwrap();
    assert_eq!(server.calls.lock().unwrap().len(), 1);
    for (status, network, bad_tip) in [
        (14, "main", tip()),
        (0, "test", tip()),
        (0, "main", BirthdayAnchor { time: 0, ..tip() }),
    ] {
        let server = FakeLwd::start(status, network, bad_tip).await;
        assert!(get_import_birthday_metadata(server.url.clone(), true)
            .await
            .is_err());
        assert_eq!(
            *server.calls.lock().unwrap(),
            vec![("GetLatestTreeState".to_owned(), None)]
        );
    }
}

#[tokio::test]
async fn mainnet_birthday_disabled_fast_path_uses_the_endpoint() {
    assert!(estimate_import_birthday_height(
        "not-a-lightwalletd-url".to_owned(),
        1_659_305_748,
        false,
        Some(tip().height),
        Some(tip().time)
    )
    .await
    .is_err());
    #[cfg(ironwood_masquerade)]
    assert!(estimate_import_birthday_height(
        "not-a-lightwalletd-url".to_owned(),
        1_659_305_748,
        true,
        Some(tip().height),
        Some(tip().time)
    )
    .await
    .is_err());
}
