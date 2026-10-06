//! Recovery uses durable wallet evidence, including after a fresh process starts.
use super::*;
use crate::wallet::sync::{store_and_broadcast_signed_pczts, StoreAndBroadcastPcztsResult};
use std::sync::{Arc, Mutex};
use transparent::bundle::OutPoint;
use zcash_primitives::transaction::Transaction;

struct Signed {
    proof: Vec<u8>,
    signature: Vec<u8>,
    tx: Transaction,
    raw: Vec<u8>,
}

impl Signed {
    fn new(prevout: OutPoint, value: u64) -> Self {
        let (proof, signature, _) = super::tests::signed_pczt_with_input(
            200,
            secp256k1::SecretKey::from_slice(&[7; 32]).unwrap(),
            prevout,
            value,
        );
        let finalized = pczt::roles::spend_finalizer::SpendFinalizer::new(
            pczt::Pczt::parse(&signature).unwrap(),
        )
        .finalize_spends()
        .unwrap();
        let tx = pczt::roles::tx_extractor::TransactionExtractor::new(finalized)
            .extract()
            .unwrap();
        let mut raw = Vec::new();
        tx.write(&mut raw).unwrap();
        Self {
            proof,
            signature,
            tx,
            raw,
        }
    }
}

struct Wallet {
    _directory: tempfile::TempDir,
    path: String,
    signed: Vec<Signed>,
}

impl Wallet {
    fn new(batch: bool) -> Self {
        let directory = tempfile::tempdir().unwrap();
        let path = directory
            .path()
            .join("wallet.db")
            .to_str()
            .unwrap()
            .to_owned();
        crate::wallet::keys::ensure_db_initialized(&path, WalletNetwork::Regtest).unwrap();
        let first = Signed::new(OutPoint::new([1; 32], 0), 1_000_000);
        let mut signed = vec![first];
        if batch {
            signed.push(Signed::new(
                OutPoint::new(*signed[0].tx.txid().as_ref(), 0),
                990_000,
            ));
        }
        Self {
            _directory: directory,
            path,
            signed,
        }
    }

    fn store(&self, index: usize, raw: Option<&[u8]>, mined: Option<u32>) {
        let conn = open_wallet_raw_conn_with_timeout(&self.path, WALLET_DB_BUSY_TIMEOUT).unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, raw, mined_height) VALUES (?1, ?2, ?3)",
            params![self.signed[index].tx.txid().as_ref(), raw, mined],
        )
        .unwrap();
    }

    async fn recover(&self, url: &str) -> Result<StoreAndBroadcastPcztsResult, String> {
        store_and_broadcast_signed_pczts(
            &self.path,
            url,
            WalletNetwork::Regtest,
            &self
                .signed
                .iter()
                .map(|s| s.proof.clone())
                .collect::<Vec<_>>(),
            &self
                .signed
                .iter()
                .map(|s| s.signature.clone())
                .collect::<Vec<_>>(),
            None,
            None,
        )
        .await
    }
}

/// Counts every RPC and provides accepted, rejected, or ambiguous submissions.
#[derive(Clone)]
struct Lightwalletd {
    tip: u64,
    response: i32,
    calls: Arc<Mutex<Vec<&'static str>>>,
    submitted: Arc<Mutex<Vec<Vec<u8>>>>,
}

impl tonic::server::NamedService for Lightwalletd {
    const NAME: &'static str = "cash.z.wallet.sdk.rpc.CompactTxStreamer";
}

impl tower_service::Service<http::Request<tonic::body::Body>> for Lightwalletd {
    type Response = http::Response<tonic::body::Body>;
    type Error = std::convert::Infallible;
    type Future = futures::future::BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(
        &mut self,
        _: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn call(&mut self, req: http::Request<tonic::body::Body>) -> Self::Future {
        use http_body_util::BodyExt;
        use prost::Message;
        let this = self.clone();
        Box::pin(async move {
            let message = if req.uri().path().ends_with("/GetLatestBlock") {
                this.calls.lock().unwrap().push("tip");
                zcash_client_backend::proto::service::BlockId {
                    height: this.tip,
                    hash: vec![1; 32],
                }
                .encode_to_vec()
            } else {
                assert!(req.uri().path().ends_with("/SendTransaction"));
                this.calls.lock().unwrap().push("send");
                let body = req.into_body().collect().await.unwrap().to_bytes();
                let raw = zcash_client_backend::proto::service::RawTransaction::decode(&body[5..])
                    .unwrap();
                this.submitted.lock().unwrap().push(raw.data);
                if this.response == -1 {
                    return Ok(http::Response::builder()
                        .header("content-type", "application/grpc")
                        .header("grpc-status", "14")
                        .body(tonic::body::Body::empty())
                        .unwrap());
                }
                zcash_client_backend::proto::service::SendResponse {
                    error_code: this.response,
                    error_message: if this.response == 0 {
                        String::new()
                    } else {
                        "rejected".into()
                    },
                }
                .encode_to_vec()
            };
            let mut framed = vec![0];
            framed.extend_from_slice(&(message.len() as u32).to_be_bytes());
            framed.extend_from_slice(&message);
            let mut trailers = http::HeaderMap::new();
            trailers.insert("grpc-status", http::HeaderValue::from_static("0"));
            let frames = futures::stream::iter([
                Ok::<_, std::convert::Infallible>(hyper::body::Frame::data(bytes::Bytes::from(
                    framed,
                ))),
                Ok(hyper::body::Frame::trailers(trailers)),
            ]);
            Ok(http::Response::builder()
                .header("content-type", "application/grpc")
                .body(tonic::body::Body::new(http_body_util::StreamBody::new(
                    frames,
                )))
                .unwrap())
        })
    }
}

async fn server(
    tip: u64,
    response: i32,
) -> (
    String,
    Lightwalletd,
    tokio::task::JoinHandle<Result<(), tonic::transport::Error>>,
) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let service = Lightwalletd {
        tip,
        response,
        calls: Default::default(),
        submitted: Default::default(),
    };
    let incoming = futures::stream::unfold(listener, |listener| async {
        Some((listener.accept().await.map(|(socket, _)| socket), listener))
    });
    let handle = tokio::spawn(
        tonic::transport::Server::builder()
            .add_service(service.clone())
            .serve_with_incoming(incoming),
    );
    (url, service, handle)
}

#[tokio::test]
async fn exact_mined_batch_recovers_without_any_rpc_after_expiry() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    let wallet = Wallet::new(true);
    for (i, signed) in wallet.signed.iter().enumerate() {
        wallet.store(i, Some(&signed.raw), Some(201));
    }
    let (url, service, handle) = server(1_000, 0).await;
    let result = wallet.recover(&url).await.unwrap();
    assert_eq!(
        (
            result.status.as_str(),
            result.broadcasted_count,
            result.total_count
        ),
        ("broadcasted", 2, 2)
    );
    assert_eq!(
        result.txids,
        wallet
            .signed
            .iter()
            .map(|s| s.tx.txid().to_string())
            .collect::<Vec<_>>()
            .join(",")
    );
    assert!(service.calls.lock().unwrap().is_empty());
    handle.abort();
}

#[tokio::test]
async fn byte_mismatch_missing_raw_and_rewound_mining_do_not_bypass_expiry() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for evidence in ["mismatch", "missing_raw", "rewound", "missing_row"] {
        let wallet = Wallet::new(false);
        match evidence {
            "mismatch" => wallet.store(0, Some(&[0x42]), Some(201)),
            "missing_raw" => wallet.store(0, None, Some(201)),
            "rewound" => {
                wallet.store(0, Some(&wallet.signed[0].raw), Some(201));
                let conn = open_wallet_raw_conn_with_timeout(&wallet.path, WALLET_DB_BUSY_TIMEOUT)
                    .unwrap();
                conn.execute("UPDATE transactions SET mined_height = NULL", [])
                    .unwrap();
                assert_eq!(
                    conn.query_row("SELECT COUNT(*) FROM vizor_mined_transactions", [], |r| r
                        .get::<_, u32>(
                        0
                    ))
                    .unwrap(),
                    1
                );
            }
            _ => {}
        }
        let (url, service, handle) = server(1_000, 0).await;
        let result = wallet.recover(&url).await.unwrap();
        assert_eq!(
            (result.status.as_str(), result.broadcasted_count),
            ("expired", 0),
            "{evidence}"
        );
        assert_eq!(*service.calls.lock().unwrap(), ["tip"], "{evidence}");
        handle.abort();
    }
}

#[tokio::test]
async fn partially_mined_batch_preserves_count_and_mined_row() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for (mined_index, tip, response, status, count) in [
        (0, 1_000, 0, "expired", 1),
        (0, 200, 0, "broadcasted", 2),
        (0, 200, 1, "partial_broadcast", 1),
        (0, 200, -1, "partial_broadcast", 1),
        (1, 200, 1, "partial_broadcast", 1),
        (1, 200, -1, "partial_broadcast", 1),
        (1, 200, 0, "broadcasted", 2),
    ] {
        let wallet = Wallet::new(true);
        wallet.store(
            mined_index,
            Some(&wallet.signed[mined_index].raw),
            Some(201),
        );
        let (url, service, handle) = server(tip, response).await;
        let result = wallet.recover(&url).await.unwrap();
        assert_eq!(
            (
                result.status.as_str(),
                result.broadcasted_count,
                result.total_count
            ),
            (status, count, 2),
            "mined={mined_index}, response={response}"
        );
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        let stored: (Vec<u8>, u32) = conn
            .query_row(
                "SELECT raw, mined_height FROM transactions WHERE txid=?1",
                [wallet.signed[mined_index].tx.txid().as_ref()],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap();
        assert_eq!(stored, (wallet.signed[mined_index].raw.clone(), 201));
        assert_eq!(
            *service.submitted.lock().unwrap(),
            if status == "expired" {
                vec![]
            } else {
                vec![wallet.signed[1 - mined_index].raw.clone()]
            }
        );
        handle.abort();
    }
}

#[tokio::test]
async fn invalid_signed_effects_are_rejected_even_when_base_is_mined() {
    let wallet = Wallet::new(false);
    wallet.store(0, Some(&wallet.signed[0].raw), Some(201));
    let different = Signed::new(OutPoint::new([2; 32], 0), 1_000_000);
    assert!(store_and_broadcast_signed_pczts(
        &wallet.path,
        "http://127.0.0.1:1",
        WalletNetwork::Regtest,
        &[wallet.signed[0].proof.clone()],
        &[different.signature],
        None,
        None
    )
    .await
    .is_err());
}

#[tokio::test]
async fn interrupted_outcome_write_recovers_in_a_fresh_offline_process() {
    let wallet = Wallet::new(false);
    let signed = &wallet.signed[0];
    checkpoint(
        &wallet.path,
        WalletNetwork::Regtest,
        "restart-op",
        "account-1",
        "swap_deposit",
        Some("deposit-1"),
        &signed.proof,
        &signed.signature,
    )
    .unwrap();
    // The wallet has observed the accepted transaction, while the outbox update failed.
    wallet.store(0, Some(&signed.raw), Some(201));
    let conn = open_wallet_raw_conn_with_timeout(&wallet.path, WALLET_DB_BUSY_TIMEOUT).unwrap();
    conn.execute_batch("CREATE TRIGGER interrupt_outcome BEFORE UPDATE ON vizor_ledger_signed_operations BEGIN SELECT RAISE(ABORT, 'interrupted outcome write'); END").unwrap();
    let error = broadcast(
        &wallet.path,
        "http://127.0.0.1:1",
        WalletNetwork::Regtest,
        "restart-op",
        None,
        None,
    )
    .await
    .unwrap_err();
    assert!(error.contains("interrupted outcome write"), "{error}");
    assert_eq!(
        list(&wallet.path, WalletNetwork::Regtest, None).unwrap()[0].state,
        STATE_SIGNED_PENDING_BROADCAST
    );
    conn.execute_batch("DROP TRIGGER interrupt_outcome")
        .unwrap();
    drop(conn);
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "wallet::ledger::operations::mined_recovery_tests::offline_restart_child",
            "--nocapture",
        ])
        .env("VIZOR_MINED_RECOVERY_TEST_DB", &wallet.path)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let rows = list(&wallet.path, WalletNetwork::Regtest, None).unwrap();
    assert_eq!(rows[0].state, STATE_RESULT_PENDING_ACK);
    assert_eq!(rows[0].status.as_deref(), Some("broadcasted"));
    assert_eq!(
        rows[0].txid.as_deref(),
        Some(signed.tx.txid().to_string().as_str())
    );
    assert_eq!(rows[0].external_ref.as_deref(), Some("deposit-1"));
    acknowledge(&wallet.path, WalletNetwork::Regtest, "restart-op").unwrap();
    assert!(list(&wallet.path, WalletNetwork::Regtest, None)
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn offline_restart_child() {
    let Ok(path) = std::env::var("VIZOR_MINED_RECOVERY_TEST_DB") else {
        return;
    };
    crate::network_privacy::disable_tor();
    let result = broadcast(
        &path,
        "http://127.0.0.1:1",
        WalletNetwork::Regtest,
        "restart-op",
        None,
        None,
    )
    .await
    .unwrap();
    assert_eq!(result.status, "broadcasted");
    assert!(result.requires_ack);
}
