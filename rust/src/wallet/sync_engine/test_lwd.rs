//! A request-recording lightwalletd for privacy-boundary tests.

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};

use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper::service::service_fn;
use prost::Message;
use tonic::transport::Channel;
use zcash_client_backend::data_api::transparent_ledger::{
    TransparentLedgerMode, TransparentLedgerWrite,
};
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, BlockId, RawTransaction, SendResponse,
    TxFilter,
};

use crate::wallet::{db::open_wallet_db_with_timeout, network::WalletNetwork};

use super::SYNC_DB_BUSY_TIMEOUT;

type OnRequest = Arc<dyn Fn(&str) + Send + Sync>;

/// A failure [`CapturingLwd::start_faulty`] answers a request with.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Fault {
    /// The call fails with gRPC status `UNAVAILABLE`.
    Status,
    /// The call succeeds, but reading its response stream fails.
    BrokenStream,
}

type FaultHook = Arc<dyn Fn(&str) -> Option<Fault> + Send + Sync>;

/// Transactions `GetTransaction` answers, by txid: raw bytes and height.
type Served = Arc<std::collections::HashMap<[u8; 32], (Vec<u8>, u64)>>;

/// Records every request path. Address history returns `history_tx`, or ends
/// with no transaction when `history_tx` is empty;
/// transaction lookups answer "not found" unless the transaction is served,
/// `GetLatestBlock` reports
/// `tip_height`, and UTXO streams are empty.
pub(crate) struct CapturingLwd {
    pub(crate) client: CompactTxStreamerClient<Channel>,
    /// The transport `client` uses, for calls that layer services over it.
    pub(crate) channel: Channel,
    pub(crate) url: String,
    requests: Arc<Mutex<Vec<String>>>,
    response_gates: Arc<Mutex<std::collections::HashMap<&'static str, Arc<tokio::sync::Notify>>>>,
    server: tokio::task::JoinHandle<()>,
}

impl CapturingLwd {
    /// Holds each response to `rpc` asynchronously until its gate is released.
    pub(crate) fn hold_responses(&self, rpc: &'static str) -> Arc<tokio::sync::Notify> {
        let gate = Arc::new(tokio::sync::Notify::new());
        self.response_gates
            .lock()
            .unwrap()
            .insert(rpc, gate.clone());
        gate
    }

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
        Self::start_inner(
            history_tx,
            tip_height,
            on_request,
            false,
            None,
            Served::default(),
        )
        .await
    }

    /// Like [`Self::start_with`], but answers a request with the fault
    /// `fault` returns for its path, if any, instead of the normal response.
    pub(crate) async fn start_faulty(
        history_tx: Vec<u8>,
        tip_height: u64,
        fault: impl Fn(&str) -> Option<Fault> + Send + Sync + 'static,
    ) -> Self {
        Self::start_inner_with_faults(
            history_tx,
            tip_height,
            |_| {},
            false,
            None,
            Served::default(),
            Arc::new(fault),
        )
        .await
    }

    /// Like [`Self::start_with`], but `GetTransaction` answers each of
    /// `served` (txid, raw bytes, height) with the transaction.
    pub(crate) async fn start_serving(
        served: Vec<([u8; 32], Vec<u8>, u64)>,
        tip_height: u64,
        on_request: impl Fn(&str) + Send + Sync + 'static,
    ) -> Self {
        let served = served
            .into_iter()
            .map(|(txid, bytes, height)| (txid, (bytes, height)))
            .collect();
        Self::start_inner(
            Vec::new(),
            tip_height,
            on_request,
            false,
            None,
            Arc::new(served),
        )
        .await
    }

    /// A real successful broadcast response for durable operation recovery tests.
    pub(crate) async fn start_for_broadcast(tip_height: u64) -> Self {
        Self::start_inner(
            Vec::new(),
            tip_height,
            |_| {},
            true,
            None,
            Served::default(),
        )
        .await
    }

    /// Like [`Self::start_for_broadcast`], but every `SendTransaction`
    /// response waits for a permit on the returned gate after the request
    /// has been received in full.
    pub(crate) async fn start_for_held_broadcast(
        tip_height: u64,
    ) -> (Self, Arc<tokio::sync::Notify>) {
        let gate = Arc::new(tokio::sync::Notify::new());
        let lwd = Self::start_inner(
            Vec::new(),
            tip_height,
            |_| {},
            true,
            Some(gate.clone()),
            Served::default(),
        )
        .await;
        (lwd, gate)
    }

    async fn start_inner(
        history_tx: Vec<u8>,
        tip_height: u64,
        on_request: impl Fn(&str) + Send + Sync + 'static,
        accept_broadcast: bool,
        send_gate: Option<Arc<tokio::sync::Notify>>,
        served: Served,
    ) -> Self {
        Self::start_inner_with_faults(
            history_tx,
            tip_height,
            on_request,
            accept_broadcast,
            send_gate,
            served,
            Arc::new(|_| None),
        )
        .await
    }

    async fn start_inner_with_faults(
        history_tx: Vec<u8>,
        tip_height: u64,
        on_request: impl Fn(&str) + Send + Sync + 'static,
        accept_broadcast: bool,
        send_gate: Option<Arc<tokio::sync::Notify>>,
        served: Served,
        fault: FaultHook,
    ) -> Self {
        let requests = Arc::new(Mutex::new(Vec::new()));
        let response_gates = Arc::new(Mutex::new(std::collections::HashMap::<
            &'static str,
            Arc<tokio::sync::Notify>,
        >::new()));
        let server_gates = response_gates.clone();
        let recorded = requests.clone();
        let on_request: OnRequest = Arc::new(on_request);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            loop {
                let (stream, _) = listener.accept().await.unwrap();
                let recorded = recorded.clone();
                let response_gates = server_gates.clone();
                let on_request = on_request.clone();
                let history_tx = history_tx.clone();
                let send_gate = send_gate.clone();
                let served = served.clone();
                let fault = fault.clone();
                tokio::spawn(async move {
                    let service =
                        service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
                            let path = request.uri().path().to_owned();
                            recorded.lock().unwrap().push(path.clone());
                            on_request(&path);
                            let response_gate = response_gates
                                .lock()
                                .unwrap()
                                .iter()
                                .find(|(rpc, _)| path.ends_with(**rpc))
                                .map(|(_, gate)| gate.clone());
                            let fault = fault(&path);
                            let history_tx = history_tx.clone();
                            let send_gate = send_gate.clone();
                            let served = served.clone();
                            async move {
                                if let Some(gate) = response_gate {
                                    gate.notified().await;
                                }
                                if let Some(fault) = fault {
                                    let grpc = hyper::Response::builder()
                                        .header("content-type", "application/grpc");
                                    let response = match fault {
                                        Fault::Status => grpc
                                            .header("grpc-status", "14")
                                            .header("grpc-message", "unavailable")
                                            .body(Full::new(Bytes::new())),
                                        // A frame flagged compressed without
                                        // a grpc-encoding: an undecodable
                                        // message. No grpc-status in the
                                        // headers, which would make this a
                                        // trailers-only reply whose body is
                                        // never read.
                                        Fault::BrokenStream => grpc
                                            .body(Full::new(Bytes::from_static(&[1, 0, 0, 0, 0]))),
                                    };
                                    return Ok::<_, std::convert::Infallible>(response.unwrap());
                                }
                                if path.ends_with("/GetTransaction") && !served.is_empty() {
                                    let body = request.into_body().collect().await;
                                    let filter = body.ok().and_then(|body| {
                                        let bytes = body.to_bytes();
                                        TxFilter::decode(bytes.get(5..)?).ok()
                                    });
                                    let found = filter.and_then(|filter| {
                                        served.get(filter.hash.as_slice()).cloned()
                                    });
                                    let grpc = hyper::Response::builder()
                                        .header("content-type", "application/grpc");
                                    let response = match found {
                                        Some((data, height)) => {
                                            grpc.header("grpc-status", "0").body(Full::new(
                                                grpc_frame(&RawTransaction { data, height }),
                                            ))
                                        }
                                        None => grpc
                                            .header("grpc-status", "5")
                                            .header("grpc-message", "not found")
                                            .body(Full::new(Bytes::new())),
                                    };
                                    return Ok::<_, std::convert::Infallible>(response.unwrap());
                                }
                                if path.ends_with("/SendTransaction") {
                                    if let Some(gate) = send_gate {
                                        // Hold the response only after the
                                        // whole request has arrived.
                                        let _ = request.into_body().collect().await;
                                        gate.notified().await;
                                    }
                                }
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
            client: CompactTxStreamerClient::new(channel.clone()),
            channel,
            url,
            requests,
            response_gates,
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
