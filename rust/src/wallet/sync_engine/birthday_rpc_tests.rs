//! Verify birthday privacy on the real scan-batch RPC path.

use super::*;
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use prost::Message;
use std::sync::{Arc, Mutex};
use zcash_client_backend::proto::{
    compact_formats::{ChainMetadata, CompactBlock},
    service::{BlockId, BlockRange, TreeState},
};

struct FakeLwd {
    url: String,
    calls: Arc<Mutex<Vec<(String, BlockId)>>>,
    task: tokio::task::JoinHandle<()>,
}

impl Drop for FakeLwd {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl FakeLwd {
    async fn start(state: &chain::ChainState) -> Self {
        let height = u64::from(u32::from(state.block_height()));
        let block = CompactBlock {
            height: height + 1,
            hash: vec![99; 32],
            prev_hash: state.block_hash().0.to_vec(),
            chain_metadata: Some(ChainMetadata {
                sapling_commitment_tree_size: state.final_sapling_tree().tree_size() as u32,
                orchard_commitment_tree_size: state.final_orchard_tree().tree_size() as u32,
                ironwood_commitment_tree_size: state.final_ironwood_tree().tree_size() as u32,
            }),
            ..Default::default()
        };
        // Network/fork fixtures use empty trees. The matching-checkpoint test
        // must never request this deliberately empty server tree state.
        let mut display_hash = state.block_hash().0;
        display_hash.reverse();
        let tree_state = TreeState {
            network: "main".into(),
            height,
            hash: hex::encode(display_hash),
            ..Default::default()
        };
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let calls = Arc::new(Mutex::new(Vec::new()));
        let server_calls = calls.clone();
        let task = tokio::spawn(async move {
            loop {
                let (stream, _) = listener.accept().await.unwrap();
                let calls = server_calls.clone();
                let block = block.clone();
                let tree_state = tree_state.clone();
                tokio::spawn(async move {
                    let service = hyper::service::service_fn(
                        move |request: hyper::Request<hyper::body::Incoming>| {
                            let calls = calls.clone();
                            let block = block.clone();
                            let tree_state = tree_state.clone();
                            async move {
                                let method =
                                    request.uri().path().rsplit('/').next().unwrap().to_owned();
                                let body = request.into_body().collect().await.unwrap().to_bytes();
                                let (id, message) = match method.as_str() {
                                    "GetBlockRange" => {
                                        let range = BlockRange::decode(&body[5..]).unwrap();
                                        assert_eq!(range.end.unwrap().height, block.height);
                                        (range.start.unwrap(), block.encode_to_vec())
                                    }
                                    "GetTreeState" => (
                                        BlockId::decode(&body[5..]).unwrap(),
                                        tree_state.encode_to_vec(),
                                    ),
                                    _ => panic!("unexpected birthday RPC: {method}"),
                                };
                                calls.lock().unwrap().push((method, id));
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
        Self { url, calls, task }
    }
}

async fn scan_one_block(server: &FakeLwd, network: WalletNetwork, start: u64) {
    let start = BlockHeight::from_u32(u32::try_from(start).unwrap());
    let mut client = CompactTxStreamerClient::connect(server.url.clone())
        .await
        .unwrap();
    let (source, state) = download_scan_batch(&mut client, start, start, network)
        .await
        .unwrap();
    validate_scan_batch(&source, &state, start, start + 1).unwrap();
}

fn height_request(method: &str, height: u64) -> (String, BlockId) {
    (
        method.into(),
        BlockId {
            height,
            hash: vec![],
        },
    )
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn compiled_birthday_batch_sends_only_the_bucket_block_range() {
    let birthday = tree_states::restore_birthday(WalletNetwork::Main, 2_345_678);
    let state = tree_states::mainnet_chain_state(WalletNetwork::Main, birthday - 1).unwrap();
    let server = FakeLwd::start(&state).await;
    scan_one_block(&server, WalletNetwork::Main, birthday).await;
    assert_eq!(
        *server.calls.lock().unwrap(),
        vec![height_request("GetBlockRange", 2_340_001)]
    );
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn restore_past_the_table_queries_the_grid_instead_of_the_exact_birthday() {
    let birthday = tree_states::restore_birthday(WalletNetwork::Main, 9_000_123);
    assert_eq!(birthday, 9_000_001);
    let state = chain::ChainState::empty(BlockHeight::from_u32(9_000_000), BlockHash([7; 32]));
    let server = FakeLwd::start(&state).await;
    scan_one_block(&server, WalletNetwork::Main, birthday).await;
    let calls = server.calls.lock().unwrap();
    assert_eq!(calls.len(), 2);
    assert!(calls.contains(&height_request("GetBlockRange", 9_000_001)));
    assert!(calls.contains(&height_request("GetTreeState", 9_000_000)));
}

#[cfg(not(ironwood_masquerade))]
#[tokio::test]
async fn mismatched_compiled_checkpoint_falls_back_by_predecessor_hash_only() {
    let birthday = tree_states::restore_birthday(WalletNetwork::Main, 2_345_678);
    let protocol_hash = std::array::from_fn(|index| index as u8 + 1);
    let state =
        chain::ChainState::empty(BlockHeight::from_u32(2_340_000), BlockHash(protocol_hash));
    let server = FakeLwd::start(&state).await;
    scan_one_block(&server, WalletNetwork::Main, birthday).await;
    let mut display_hash = protocol_hash;
    display_hash.reverse();
    assert_eq!(
        *server.calls.lock().unwrap(),
        vec![
            height_request("GetBlockRange", 2_340_001),
            (
                "GetTreeState".into(),
                BlockId {
                    height: 0,
                    hash: display_hash.to_vec()
                }
            ),
        ]
    );
}

#[tokio::test]
async fn non_mainnet_batches_keep_the_network_tree_state_lookup() {
    let mut networks = vec![WalletNetwork::Test, WalletNetwork::Regtest];
    if cfg!(ironwood_masquerade) {
        networks.push(WalletNetwork::Main);
    }
    for network in networks {
        let state = chain::ChainState::empty(BlockHeight::from_u32(2_340_000), BlockHash([8; 32]));
        let server = FakeLwd::start(&state).await;
        scan_one_block(&server, network, 2_340_001).await;
        let calls = server.calls.lock().unwrap();
        assert_eq!(calls.len(), 2);
        assert!(calls.contains(&height_request("GetBlockRange", 2_340_001)));
        assert!(calls.contains(&height_request("GetTreeState", 2_340_000)));
    }
}
