//! A request-recording lightwalletd for privacy-boundary tests.

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};

use bytes::Bytes;
use http_body_util::Full;
use hyper::service::service_fn;
use prost::Message;
use tonic::transport::Channel;
use zcash_client_backend::data_api::transparent_ledger::{
    TransparentLedgerMode, TransparentLedgerWrite,
};
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, BlockId, RawTransaction, SendResponse,
};

use crate::wallet::{db::open_wallet_db_with_timeout, network::WalletNetwork};

use super::SYNC_DB_BUSY_TIMEOUT;

type OnRequest = Arc<dyn Fn(&str) + Send + Sync>;

/// Records every request path. Address history returns `history_tx`, or ends
/// with no transaction when `history_tx` is empty;
/// transaction lookups answer "not found", `GetLatestBlock` reports
/// `tip_height`, and UTXO streams are empty.
pub(crate) struct CapturingLwd {
    pub(crate) client: CompactTxStreamerClient<Channel>,
    pub(crate) url: String,
    requests: Arc<Mutex<Vec<String>>>,
    server: tokio::task::JoinHandle<()>,
}

impl CapturingLwd {
    pub(crate) async fn start(history_tx: Vec<u8>) -> Self {
        Self::start_with(history_tx, 0, |_| {}).await
    }

    /// Like [`Self::start`], but runs `on_request` with each request path after
    /// recording it and before answering, so a test can act at the moment a
    /// request is dispatched.
    pub(crate) async fn start_with(
        history_tx: Vec<u8>,
        tip_height: u64,
        on_request: impl Fn(&str) + Send + Sync + 'static,
    ) -> Self {
        Self::start_inner(history_tx, tip_height, on_request, false).await
    }

    /// A real successful broadcast response for durable operation recovery tests.
    pub(crate) async fn start_for_broadcast(tip_height: u64) -> Self {
        Self::start_inner(Vec::new(), tip_height, |_| {}, true).await
    }

    async fn start_inner(
        history_tx: Vec<u8>,
        tip_height: u64,
        on_request: impl Fn(&str) + Send + Sync + 'static,
        accept_broadcast: bool,
    ) -> Self {
        let requests = Arc::new(Mutex::new(Vec::new()));
        let recorded = requests.clone();
        let on_request: OnRequest = Arc::new(on_request);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = listener.accept().await.unwrap();
                let recorded = recorded.clone();
                let on_request = on_request.clone();
                let history_tx = history_tx.clone();
                tokio::spawn(async move {
                    let service =
                        service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
                            let path = request.uri().path().to_owned();
                            recorded.lock().unwrap().push(path.clone());
                            on_request(&path);
                            let history_tx = history_tx.clone();
                            async move {
                                let grpc = hyper::Response::builder()
                                    .header("content-type", "application/grpc");
                                let response = if path.ends_with("/GetTaddressTxids")
                                    && !history_tx.is_empty()
                                {
                                    let message = RawTransaction {
                                        data: history_tx,
                                        height: 150,
                                    };
                                    grpc.header("grpc-status", "0")
                                        .body(Full::new(grpc_frame(&message)))
                                } else if path.ends_with("/GetLatestBlock") {
                                    let message = BlockId {
                                        height: tip_height,
                                        hash: vec![0; 32],
                                    };
                                    grpc.header("grpc-status", "0")
                                        .body(Full::new(grpc_frame(&message)))
                                } else if path.ends_with("/SendTransaction") && accept_broadcast {
                                    grpc.header("grpc-status", "0").body(Full::new(grpc_frame(
                                        &SendResponse {
                                            error_code: 0,
                                            error_message: String::new(),
                                        },
                                    )))
                                } else if path.ends_with("/GetTransaction") {
                                    grpc.header("grpc-status", "5")
                                        .header("grpc-message", "not found")
                                        .body(Full::new(Bytes::new()))
                                } else {
                                    grpc.header("grpc-status", "0")
                                        .body(Full::new(Bytes::new()))
                                };
                                Ok::<_, std::convert::Infallible>(response.unwrap())
                            }
                        });
                    let _ = hyper::server::conn::http2::Builder::new(
                        hyper_util::rt::TokioExecutor::new(),
                    )
                    .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
                    .await;
                });
            }
        });
        let url = format!("http://{endpoint}");
        let channel = tonic::transport::Endpoint::from_shared(url.clone())
            .unwrap()
            .connect()
            .await
            .unwrap();
        let _ = rustls::crypto::ring::default_provider().install_default();
        Self {
            client: CompactTxStreamerClient::new(channel),
            url,
            requests,
            server,
        }
    }

    pub(crate) fn requests(&self) -> Vec<String> {
        self.requests.lock().unwrap().clone()
    }

    /// How many recorded requests called `rpc`, such as `"/GetTransaction"`.
    pub(crate) fn count(&self, rpc: &str) -> usize {
        self.requests()
            .iter()
            .filter(|path| path.ends_with(rpc))
            .count()
    }
}

impl Drop for CapturingLwd {
    fn drop(&mut self) {
        self.server.abort();
    }
}

fn grpc_frame(message: &impl Message) -> Bytes {
    let message = message.encode_to_vec();
    let mut frame = vec![0];
    frame.extend_from_slice(&(message.len() as u32).to_be_bytes());
    frame.extend_from_slice(&message);
    Bytes::from(frame)
}

/// An `on_request` hook that durably applies `mode` through another connection
/// when the first `rpc` request arrives, as a settings transition racing an
/// in-flight lane would.
pub(crate) fn transition_on_first(
    rpc: &'static str,
    db_path: &str,
    network: WalletNetwork,
    mode: TransparentLedgerMode,
) -> impl Fn(&str) + Send + Sync + 'static {
    let db_path = db_path.to_owned();
    let fired = AtomicBool::new(false);
    move |path| {
        if path.ends_with(rpc) && !fired.swap(true, Ordering::SeqCst) {
            open_wallet_db_with_timeout(&db_path, network, SYNC_DB_BUSY_TIMEOUT)
                .unwrap()
                .apply_transparent_policy(mode)
                .unwrap();
        }
    }
}

/// Durably applies `mode` through another connection right after the first
/// authorized transparent lookup dispatch on this thread, before that RPC or
/// any other request of its batch is polled. The transition lands between two
/// requests of one concurrent batch, which a per-batch check cannot see.
pub(crate) fn transition_on_first_dispatch(
    db_path: &str,
    network: WalletNetwork,
    mode: TransparentLedgerMode,
) -> super::lwd::transparent_lookup::test_hooks::DispatchHook {
    let db_path = db_path.to_owned();
    let mut fired = false;
    super::lwd::transparent_lookup::test_hooks::on_dispatch(move || {
        if !std::mem::replace(&mut fired, true) {
            open_wallet_db_with_timeout(&db_path, network, SYNC_DB_BUSY_TIMEOUT)
                .unwrap()
                .apply_transparent_policy(mode)
                .unwrap();
        }
    })
}

/// Like [`transition_on_first_dispatch`], but on every authorized dispatch,
/// alternating `PrivateShadow` and `Public` so each one bumps the generation
/// while keeping public authority.
pub(crate) fn transition_on_every_dispatch(
    db_path: &str,
    network: WalletNetwork,
) -> super::lwd::transparent_lookup::test_hooks::DispatchHook {
    use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerRead;
    let db_path = db_path.to_owned();
    super::lwd::transparent_lookup::test_hooks::on_dispatch(move || {
        let mut db = open_wallet_db_with_timeout(&db_path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
        let next = match db.applied_transparent_policy().unwrap().mode {
            TransparentLedgerMode::PrivateShadow => TransparentLedgerMode::Public,
            _ => TransparentLedgerMode::PrivateShadow,
        };
        db.apply_transparent_policy(next).unwrap();
    })
}
