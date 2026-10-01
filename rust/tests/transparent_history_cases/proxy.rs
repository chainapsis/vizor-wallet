//! Request-capturing, fault-injecting lightwalletd proxy (the F builder).
//!
//! A raw HTTP/2 forwarder in the style of
//! `integration_test/support/regtest_lightwalletd_proxy.dart`: every gRPC call
//! is recorded with its method and the transparent subjects it reveals
//! (addresses, txids), then forwarded to the real lightwalletd unless a fault
//! is armed for that method.

use std::{
    collections::HashSet,
    convert::Infallible,
    sync::{Arc, Mutex},
    time::Duration,
};

use bytes::{Buf, Bytes, BytesMut};
use http_body_util::{combinators::BoxBody, BodyExt, Full, StreamBody};
use hyper::body::Frame;
use prost::Message;
use serde::Serialize;
use tokio::sync::{mpsc, watch};
use zcash_client_backend::proto::service::{
    GetAddressUtxosArg, RawTransaction, SendResponse, TransparentAddressBlockFilter, TxFilter,
};

pub const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer/";

type ProxyBody = BoxBody<Bytes, Infallible>;

#[derive(Clone, Debug, Serialize)]
pub struct RequestRecord {
    pub method: String,
    /// Transparent addresses or txids (both byte orders for txids) the call revealed.
    pub subjects: Vec<String>,
    /// The fault applied to this call, if any.
    pub fault: Option<String>,
}

#[derive(Default)]
struct Faults {
    /// Cut every `GetTaddressTxids` response after this many messages.
    cut_taddress_txids_after: Option<usize>,
    /// Fail every `GetAddressUtxos` / `GetAddressUtxosStream` call.
    fail_address_utxos: bool,
    /// Accept, but never forward, the next N `SendTransaction` calls; their
    /// txids keep being swallowed on resubmission.
    swallow_next_sends: usize,
    swallowed_txids: HashSet<String>,
}

struct State {
    requests: Vec<RequestRecord>,
    faults: Faults,
    swallowed: Vec<(String, Vec<u8>)>,
    held_now: usize,
}

pub struct Proxy {
    pub url: String,
    state: Arc<Mutex<State>>,
    hold_tx: watch::Sender<bool>,
    _runtime: Arc<tokio::runtime::Runtime>,
}

impl Proxy {
    pub fn start(upstream: &str) -> Self {
        let runtime = Arc::new(
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .expect("proxy runtime"),
        );
        let state = Arc::new(Mutex::new(State {
            requests: Vec::new(),
            faults: Faults::default(),
            swallowed: Vec::new(),
            held_now: 0,
        }));
        let (hold_tx, hold_rx) = watch::channel(false);
        let listener = runtime
            .block_on(tokio::net::TcpListener::bind("127.0.0.1:0"))
            .expect("proxy bind");
        let url = format!("http://{}", listener.local_addr().unwrap());
        let client =
            hyper_util::client::legacy::Client::builder(hyper_util::rt::TokioExecutor::new())
                .http2_only(true)
                .build_http::<Full<Bytes>>();
        let upstream = upstream.trim_end_matches('/').to_string();
        let accept_state = state.clone();
        runtime.spawn(async move {
            loop {
                let Ok((stream, _)) = listener.accept().await else {
                    continue;
                };
                let state = accept_state.clone();
                let client = client.clone();
                let upstream = upstream.clone();
                let hold_rx = hold_rx.clone();
                tokio::spawn(async move {
                    let service = hyper::service::service_fn(move |request| {
                        handle(
                            request,
                            state.clone(),
                            client.clone(),
                            upstream.clone(),
                            hold_rx.clone(),
                        )
                    });
                    let _ = hyper::server::conn::http2::Builder::new(
                        hyper_util::rt::TokioExecutor::new(),
                    )
                    .serve_connection(hyper_util::rt::TokioIo::new(stream), service)
                    .await;
                });
            }
        });
        Proxy {
            url,
            state,
            hold_tx,
            _runtime: runtime,
        }
    }

    pub fn take_requests(&self) -> Vec<RequestRecord> {
        std::mem::take(&mut self.state.lock().unwrap().requests)
    }

    pub fn cut_taddress_txids_after(&self, messages: Option<usize>) {
        self.state.lock().unwrap().faults.cut_taddress_txids_after = messages;
    }

    pub fn fail_address_utxos(&self, fail: bool) {
        self.state.lock().unwrap().faults.fail_address_utxos = fail;
    }

    /// Holds every `GetTransaction` call until [`Self::release_get_transaction`].
    pub fn hold_get_transaction(&self) {
        let _ = self.hold_tx.send(true);
    }

    pub fn release_get_transaction(&self) {
        let _ = self.hold_tx.send(false);
    }

    pub fn held_now(&self) -> usize {
        self.state.lock().unwrap().held_now
    }

    pub fn swallow_next_sends(&self, count: usize) {
        self.state.lock().unwrap().faults.swallow_next_sends = count;
    }

    /// Raw bytes of every swallowed transaction, keyed by display txid.
    pub fn swallowed(&self) -> Vec<(String, Vec<u8>)> {
        self.state.lock().unwrap().swallowed.clone()
    }
}

fn grpc_frame(message: &impl Message) -> Bytes {
    let payload = message.encode_to_vec();
    let mut frame = BytesMut::with_capacity(payload.len() + 5);
    frame.extend_from_slice(&[0]);
    frame.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    frame.extend_from_slice(&payload);
    frame.freeze()
}

fn messages(mut body: Bytes) -> Vec<Bytes> {
    let mut out = Vec::new();
    while body.len() >= 5 {
        let len = u32::from_be_bytes([body[1], body[2], body[3], body[4]]) as usize;
        if body.len() < 5 + len {
            break;
        }
        body.advance(5);
        out.push(body.split_to(len));
    }
    out
}

fn txid_subjects(hash: &[u8]) -> Vec<String> {
    let mut reversed = hash.to_vec();
    reversed.reverse();
    vec![hex::encode(hash), hex::encode(reversed)]
}

/// Display-order txid of a serialized transaction.
pub fn txid_of(raw: &[u8]) -> Option<String> {
    use zcash_primitives::transaction::Transaction;
    use zcash_protocol::consensus::BranchId;
    Transaction::read(raw, BranchId::Nu6)
        .ok()
        .map(|tx| tx.txid().to_string())
}

fn subjects(method: &str, body: &Bytes) -> Vec<String> {
    let mut out = Vec::new();
    for message in messages(body.clone()) {
        match method {
            "GetAddressUtxos" | "GetAddressUtxosStream" => {
                if let Ok(arg) = GetAddressUtxosArg::decode(message) {
                    out.extend(arg.addresses);
                }
            }
            "GetTaddressTxids" | "GetTaddressTransactions" => {
                if let Ok(filter) = TransparentAddressBlockFilter::decode(message) {
                    out.push(filter.address);
                }
            }
            "GetTransaction" => {
                if let Ok(filter) = TxFilter::decode(message) {
                    out.extend(txid_subjects(&filter.hash));
                }
            }
            "SendTransaction" => {
                if let Ok(raw) = RawTransaction::decode(message) {
                    out.extend(txid_of(&raw.data));
                }
            }
            "GetTaddressBalance" | "GetTaddressBalanceStream" => {
                // AddressList / Address: field 1 holds address strings.
                if let Ok(list) =
                    zcash_client_backend::proto::service::AddressList::decode(message.clone())
                {
                    out.extend(list.addresses);
                }
            }
            _ => {}
        }
    }
    out
}

fn status_only(code: u32, message: &str) -> hyper::Response<ProxyBody> {
    hyper::Response::builder()
        .header("content-type", "application/grpc")
        .header("grpc-status", code.to_string())
        .header("grpc-message", message)
        .body(Full::new(Bytes::new()).boxed())
        .unwrap()
}

fn unary_ok(message: &impl Message) -> hyper::Response<ProxyBody> {
    let (tx, rx) = mpsc::unbounded_channel::<Frame<Bytes>>();
    let _ = tx.send(Frame::data(grpc_frame(message)));
    let mut trailers = http::HeaderMap::new();
    trailers.insert("grpc-status", "0".parse().unwrap());
    let _ = tx.send(Frame::trailers(trailers));
    drop(tx);
    hyper::Response::builder()
        .header("content-type", "application/grpc")
        .body(channel_body(rx))
        .unwrap()
}

fn channel_body(mut rx: mpsc::UnboundedReceiver<Frame<Bytes>>) -> ProxyBody {
    let stream = futures::stream::poll_fn(move |cx| rx.poll_recv(cx).map(|f| f.map(Ok)));
    StreamBody::new(stream).boxed()
}

async fn handle(
    request: hyper::Request<hyper::body::Incoming>,
    state: Arc<Mutex<State>>,
    client: hyper_util::client::legacy::Client<
        hyper_util::client::legacy::connect::HttpConnector,
        Full<Bytes>,
    >,
    upstream: String,
    mut hold_rx: watch::Receiver<bool>,
) -> Result<hyper::Response<ProxyBody>, Infallible> {
    let path = request.uri().path().to_string();
    let method = path.strip_prefix(SERVICE).unwrap_or(&path).to_string();
    let (parts, body) = request.into_parts();
    let body = match body.collect().await {
        Ok(collected) => collected.to_bytes(),
        Err(_) => return Ok(status_only(13, "proxy: request body")),
    };
    let subjects = subjects(&method, &body);

    // Decide the fault under one lock, recording the request with it.
    let mut fault: Option<String> = None;
    let mut cut_after = None;
    let mut swallow_raw: Option<(String, Vec<u8>)> = None;
    {
        let mut state = state.lock().unwrap();
        match method.as_str() {
            "GetAddressUtxos" | "GetAddressUtxosStream" if state.faults.fail_address_utxos => {
                fault = Some("fail_unavailable".into());
            }
            "GetTaddressTxids" => {
                if let Some(n) = state.faults.cut_taddress_txids_after {
                    fault = Some(format!("cut_after_{n}"));
                    cut_after = Some(n);
                }
            }
            "SendTransaction" => {
                if let Some(txid) = subjects.first().cloned() {
                    let swallow = if state.faults.swallowed_txids.contains(&txid) {
                        true
                    } else if state.faults.swallow_next_sends > 0 {
                        state.faults.swallow_next_sends -= 1;
                        state.faults.swallowed_txids.insert(txid.clone());
                        true
                    } else {
                        false
                    };
                    if swallow {
                        fault = Some("swallowed".into());
                        let raw = messages(body.clone())
                            .first()
                            .and_then(|m| RawTransaction::decode(m.clone()).ok())
                            .map(|r| r.data)
                            .unwrap_or_default();
                        swallow_raw = Some((txid, raw));
                    }
                }
            }
            "GetTransaction" if *hold_rx.borrow() => {
                fault = Some("held".into());
            }
            _ => {}
        }
        state.requests.push(RequestRecord {
            method: method.clone(),
            subjects: subjects.clone(),
            fault: fault.clone(),
        });
        if let Some((txid, raw)) = &swallow_raw {
            if !state.swallowed.iter().any(|(t, _)| t == txid) {
                state.swallowed.push((txid.clone(), raw.clone()));
            }
        }
    }

    match fault.as_deref() {
        Some("fail_unavailable") => return Ok(status_only(14, "proxy: injected failure")),
        Some("swallowed") => {
            return Ok(unary_ok(&SendResponse {
                error_code: 0,
                error_message: String::new(),
            }))
        }
        Some("held") => {
            state.lock().unwrap().held_now += 1;
            while *hold_rx.borrow() {
                if hold_rx.changed().await.is_err() {
                    break;
                }
            }
            state.lock().unwrap().held_now -= 1;
        }
        _ => {}
    }

    let mut builder = hyper::Request::builder()
        .method(parts.method)
        .uri(format!("{upstream}{path}"));
    for (name, value) in parts.headers.iter() {
        if name != "host" {
            builder = builder.header(name, value);
        }
    }
    let upstream_request = builder.body(Full::new(body)).unwrap();
    let response = match tokio::time::timeout(
        Duration::from_secs(120),
        client.request(upstream_request),
    )
    .await
    {
        Ok(Ok(response)) => response,
        Ok(Err(e)) => return Ok(status_only(14, &format!("proxy: upstream {e}"))),
        Err(_) => return Ok(status_only(4, "proxy: upstream timeout")),
    };
    let (parts, mut upstream_body) = response.into_parts();
    let (tx, rx) = mpsc::unbounded_channel::<Frame<Bytes>>();
    tokio::spawn(async move {
        let mut buffer = BytesMut::new();
        let mut forwarded = 0usize;
        while let Some(frame) = upstream_body.frame().await {
            let Ok(frame) = frame else { break };
            match frame.into_data() {
                Ok(data) => {
                    let Some(limit) = cut_after else {
                        let _ = tx.send(Frame::data(data));
                        continue;
                    };
                    buffer.extend_from_slice(&data);
                    while buffer.len() >= 5 {
                        let len = u32::from_be_bytes([buffer[1], buffer[2], buffer[3], buffer[4]])
                            as usize;
                        if buffer.len() < 5 + len {
                            break;
                        }
                        let message = buffer.split_to(5 + len).freeze();
                        if forwarded == limit {
                            let mut trailers = http::HeaderMap::new();
                            trailers.insert("grpc-status", "14".parse().unwrap());
                            trailers.insert("grpc-message", "proxy: stream cut".parse().unwrap());
                            let _ = tx.send(Frame::trailers(trailers));
                            return;
                        }
                        forwarded += 1;
                        let _ = tx.send(Frame::data(message));
                    }
                }
                Err(frame) => {
                    if let Ok(trailers) = frame.into_trailers() {
                        let _ = tx.send(Frame::trailers(trailers));
                    }
                }
            }
        }
    });
    Ok(hyper::Response::from_parts(parts, channel_body(rx)))
}
