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
        Self::with_key(
            prevout,
            value,
            secp256k1::SecretKey::from_slice(&[7; 32]).unwrap(),
        )
    }

    fn with_key(prevout: OutPoint, value: u64, key: secp256k1::SecretKey) -> Self {
        let (proof, signature, _) = super::tests::signed_pczt_with_input(200, key, prevout, value);
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

/// Signing has consumed the proposal, but completion still owns its input lock.
struct SignedProposal {
    id: u64,
    flow: String,
}

impl SignedProposal {
    fn new(wallet: &Wallet) -> Self {
        use crate::wallet::sync::{proposal_locks, StoredProposalLock, PROPOSAL_STORE};
        use std::collections::BTreeMap;
        use transparent::{address::TransparentAddress, bundle::TxOut};
        use zcash_client_backend::{
            data_api::wallet::ConfirmationsPolicy,
            fees::TransactionBalance,
            proposal::Proposal,
            wallet::{LockOwner, OutputRef, WalletTransparentOutput},
            zip321::{Payment, TransactionRequest},
        };
        use zcash_keys::address::Address;
        use zcash_protocol::{consensus::BlockHeight, value::Zatoshis, PoolType};

        let address = TransparentAddress::PublicKeyHash([7; 20]);
        let input = WalletTransparentOutput::from_parts(
            OutPoint::new([1; 32], 0),
            TxOut::new(Zatoshis::const_from_u64(1_000_000), address.script().into()),
            Some(BlockHeight::from_u32(150)),
            None,
            None,
            None,
        )
        .unwrap();
        let payment = Payment::new(
            Address::Transparent(address).to_zcash_address(&WalletNetwork::Regtest),
            Some(Zatoshis::const_from_u64(990_000)),
            None,
            None,
            None,
            vec![],
        )
        .unwrap();
        let proposal = Proposal::single_step(
            TransactionRequest::new(vec![payment]).unwrap(),
            BTreeMap::from([(0, PoolType::TRANSPARENT)]),
            vec![input],
            None,
            BlockHeight::from_u32(200),
            TransactionBalance::new(vec![], Zatoshis::const_from_u64(10_000)).unwrap(),
            crate::wallet::sync::ConservativeZip317FeeRule,
            wallet.signed[0].tx.expiry_height().into(),
            ConfirmationsPolicy::default(),
            false,
            false,
        )
        .unwrap();
        let id = {
            let mut store = PROPOSAL_STORE.lock().unwrap();
            let id = store.next_id;
            store.next_id += 1;
            id
        };
        let flow = format!("mined-recovery-{id}");
        let mut owner_bytes = [0; 32];
        owner_bytes[..8].copy_from_slice(&id.to_le_bytes());
        let owner = LockOwner::new(owner_bytes);
        proposal_locks::persist(
            &wallet.path,
            owner,
            &[OutputRef::new(
                zcash_primitives::transaction::TxId::from_bytes([1; 32]),
                PoolType::TRANSPARENT,
                0,
            )],
            wallet.signed[0].tx.expiry_height(),
        )
        .unwrap();
        PROPOSAL_STORE.lock().unwrap().locks.insert(
            id,
            StoredProposalLock {
                proposal,
                network: WalletNetwork::Regtest,
                db_path: wallet.path.clone(),
                owner,
                send_flow_id: flow.clone(),
            },
        );
        Self { id, flow }
    }

    async fn recover(
        &self,
        wallet: &Wallet,
        signature: Vec<u8>,
    ) -> Result<StoreAndBroadcastPcztsResult, String> {
        crate::wallet::sync::store_and_broadcast_signed_pczts_for_proposal(
            &wallet.path,
            "http://127.0.0.1:1",
            WalletNetwork::Regtest,
            self.id,
            &self.flow,
            &[wallet.signed[0].proof.clone()],
            &[signature],
            None,
            None,
        )
        .await
    }

    fn assert_retained(&self, wallet: &Wallet, retained: bool) {
        let has_lock = crate::wallet::sync::PROPOSAL_STORE
            .lock()
            .unwrap()
            .locks
            .contains_key(&self.id);
        assert_eq!(has_lock, retained, "proposal retry capability");
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        let count: u32 = conn
            .query_row("SELECT COUNT(*) FROM vizor_send_proposal_locks", [], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(count, u32::from(retained), "durable input reservation");
    }
}

impl Drop for SignedProposal {
    fn drop(&mut self) {
        if let Ok(mut store) = crate::wallet::sync::PROPOSAL_STORE.lock() {
            store.locks.remove(&self.id);
        }
    }
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
        // Pending-transaction storage requires the wallet's observed chain tip.
        use zcash_client_backend::data_api::WalletWrite;
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            &path,
            WalletNetwork::Regtest,
            WALLET_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        db.update_chain_tip(zcash_protocol::consensus::BlockHeight::from_u32(205))
            .unwrap();
        drop(db);
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
            "INSERT INTO transactions (txid, raw, mined_height, min_observed_height) VALUES (?1, ?2, ?3, 200)",
            params![self.signed[index].tx.txid().as_ref(), raw, mined],
        )
        .unwrap();
    }

    fn checkpoint(&self, operation_id: &str, kind: &str) {
        checkpoint_batch(
            &self.path,
            WalletNetwork::Regtest,
            operation_id,
            "account-1",
            kind,
            Some("deposit-1"),
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
    responses: Arc<Mutex<Vec<i32>>>,
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
                let mut submitted = this.submitted.lock().unwrap();
                let responses = this.responses.lock().unwrap();
                let response = *responses
                    .get(submitted.len())
                    .unwrap_or_else(|| responses.last().unwrap());
                submitted.push(raw.data);
                drop(submitted);
                drop(responses);
                if response == -1 {
                    return Ok(http::Response::builder()
                        .header("content-type", "application/grpc")
                        .header("grpc-status", "14")
                        .body(tonic::body::Body::empty())
                        .unwrap());
                }
                zcash_client_backend::proto::service::SendResponse {
                    error_code: response,
                    error_message: if response == 0 {
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
        responses: Arc::new(Mutex::new(vec![response])),
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
async fn missing_or_mismatching_mined_bytes_defer_without_rpc() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for evidence in [
        "missing",
        "malformed",
        "different-effects",
        "trailing-bytes",
    ] {
        let wallet = Wallet::new(false);
        let raw = match evidence {
            "missing" => None,
            "malformed" => Some(vec![0x42]),
            "different-effects" => Some(Signed::new(OutPoint::new([2; 32], 0), 1_000_000).raw),
            "trailing-bytes" => {
                let mut raw = wallet.signed[0].raw.clone();
                raw.push(0x42);
                Some(raw)
            }
            _ => unreachable!(),
        };
        wallet.store(0, raw.as_deref(), Some(201));
        wallet.checkpoint("uncertain-op", "swap_deposit");
        let (url, service, handle) = server(1_000, 0).await;
        let error = wallet
            .recover(&url)
            .await
            .err()
            .expect("mined bytes must defer");
        assert!(error.contains("stored mined transaction"), "{error}");
        broadcast(
            &wallet.path,
            &url,
            WalletNetwork::Regtest,
            "uncertain-op",
            None,
            None,
        )
        .await
        .unwrap_err();
        let rows = list(&wallet.path, WalletNetwork::Regtest, None).unwrap();
        assert_eq!(rows[0].state, STATE_SIGNED_PENDING_BROADCAST);
        assert_eq!(rows[0].external_ref.as_deref(), Some("deposit-1"));
        assert!(service.calls.lock().unwrap().is_empty());
        // Enhancement can supply exact bytes on a later attempt.
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        conn.execute("UPDATE transactions SET raw = ?1", [&wallet.signed[0].raw])
            .unwrap();
        let result = broadcast(
            &wallet.path,
            "http://127.0.0.1:1",
            WalletNetwork::Regtest,
            "uncertain-op",
            None,
            None,
        )
        .await
        .unwrap();
        assert_eq!(result.status, "broadcasted");
        assert!(result.requires_ack);
        handle.abort();
    }
}

#[tokio::test]
async fn rewound_mining_defers_only_while_recovery_evidence_is_pending() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for (start, end, priority, deferred) in [
        (200, 206, 20, true),
        (200, 206, 10, false),     // Already scanned.
        (1, 100, 20, false),       // Before the transaction was observed.
        (1_000, 1_001, 20, false), // After its expiry.
    ] {
        let wallet = Wallet::new(false);
        wallet.store(0, Some(&wallet.signed[0].raw), Some(201));
        wallet.checkpoint("rewound-op", "swap_deposit");
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        conn.execute(
            "UPDATE transactions SET mined_height = NULL, expiry_height = ?1",
            [u32::from(wallet.signed[0].tx.expiry_height())],
        )
        .unwrap();
        conn.execute("DELETE FROM scan_queue", []).unwrap();
        conn.execute("INSERT INTO scan_queue (block_range_start, block_range_end, priority) VALUES (?1, ?2, ?3)",
            params![start, end, priority]).unwrap();
        let (url, service, handle) = server(1_000, 0).await;
        let result = broadcast(
            &wallet.path,
            &url,
            WalletNetwork::Regtest,
            "rewound-op",
            None,
            None,
        )
        .await;
        if deferred {
            let error = result.unwrap_err();
            assert!(error.contains("awaiting mined-state recovery"), "{error}");
            assert!(service.calls.lock().unwrap().is_empty());
            let rows = list(&wallet.path, WalletNetwork::Regtest, None).unwrap();
            assert_eq!(rows[0].state, STATE_SIGNED_PENDING_BROADCAST);
            assert_eq!(rows[0].external_ref.as_deref(), Some("deposit-1"));
            // A restored mined height completes recovery offline.
            conn.execute("UPDATE transactions SET mined_height = 201", [])
                .unwrap();
            assert_eq!(
                broadcast(
                    &wallet.path,
                    "http://127.0.0.1:1",
                    WalletNetwork::Regtest,
                    "rewound-op",
                    None,
                    None
                )
                .await
                .unwrap()
                .status,
                "broadcasted"
            );
        } else {
            assert_eq!(result.unwrap().status, "expired");
            assert_eq!(*service.calls.lock().unwrap(), ["tip"]);
        }
        handle.abort();
    }
}

#[tokio::test]
async fn an_unobserved_transaction_still_expires_normally() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    let wallet = Wallet::new(false);
    let (url, service, handle) = server(1_000, 0).await;
    let result = wallet.recover(&url).await.unwrap();
    assert_eq!(
        (result.status.as_str(), result.broadcasted_count),
        ("expired", 0)
    );
    assert_eq!(*service.calls.lock().unwrap(), ["tip"]);
    handle.abort();
}

#[tokio::test]
async fn partially_mined_batch_preserves_count_and_mined_row() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for (mined_index, tip, response, status, count) in [
        (0, 1_000, 0, "partial_broadcast", 1),
        (1, 1_000, 0, "partial_broadcast", 1),
        (0, 205, 0, "broadcasted", 2),
        (0, 205, 1, "partial_broadcast", 1),
        (0, 205, -1, "partial_broadcast", 1),
        (1, 205, 1, "partial_broadcast", 1),
        (1, 205, -1, "partial_broadcast", 1),
        (1, 205, 0, "broadcasted", 2),
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
            if tip == 1_000 {
                vec![]
            } else {
                vec![wallet.signed[1 - mined_index].raw.clone()]
            }
        );
        handle.abort();
    }
}

#[tokio::test]
async fn partial_expiry_preserves_the_ledger_deposit_result_for_acknowledgement() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for kind in ["swap_deposit", "pay_deposit"] {
        let mut wallet = Wallet::new(true);
        use zcash_client_backend::wallet::{LockOwner, OutputRef};
        let owner = LockOwner::new([42; 32]);
        proposal_locks::persist(
            &wallet.path,
            owner,
            &[OutputRef::new(
                wallet.signed[0].tx.txid(),
                zcash_protocol::PoolType::TRANSPARENT,
                0,
            )],
            wallet.signed[0].tx.expiry_height(),
        )
        .unwrap();
        wallet.signed[0].proof =
            proposal_locks::bind_pczt(pczt::Pczt::parse(&wallet.signed[0].proof).unwrap(), owner)
                .serialize()
                .unwrap();
        wallet.store(0, Some(&wallet.signed[0].raw), Some(201));
        wallet.checkpoint("partial-op", kind);
        let (url, service, handle) = server(1_000, 0).await;
        let result = broadcast(
            &wallet.path,
            &url,
            WalletNetwork::Regtest,
            "partial-op",
            None,
            None,
        )
        .await
        .unwrap();
        assert_eq!(result.status, "partial_broadcast");
        assert!(result.requires_ack);
        let rows = list(&wallet.path, WalletNetwork::Regtest, None).unwrap();
        assert_eq!(rows[0].state, STATE_RESULT_PENDING_ACK);
        assert_eq!(rows[0].status.as_deref(), Some("partial_broadcast"));
        assert_eq!(rows[0].external_ref.as_deref(), Some("deposit-1"));
        assert!(rows[0]
            .txid
            .as_deref()
            .unwrap()
            .contains(&wallet.signed[0].tx.txid().to_string()));
        assert_eq!(*service.calls.lock().unwrap(), ["tip"]);
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        let durable = || {
            conn.query_row("SELECT phase = 'signed' AND retain_until_expiry FROM vizor_send_proposal_locks WHERE owner = ?1", [owner.as_bytes().as_slice()], |r| r.get::<_, bool>(0)).unwrap()
        };
        assert!(durable());
        assert!(acknowledge(&wallet.path, WalletNetwork::Regtest, "missing-op").is_err());
        conn.execute_batch("CREATE TRIGGER refuse_release BEFORE UPDATE ON vizor_send_proposal_locks BEGIN SELECT RAISE(ABORT, 'release failed'); END;").unwrap();
        assert!(acknowledge(&wallet.path, WalletNetwork::Regtest, "partial-op").is_err());
        assert_eq!(
            list(&wallet.path, WalletNetwork::Regtest, None)
                .unwrap()
                .len(),
            1
        );
        assert!(durable());
        conn.execute_batch("DROP TRIGGER refuse_release;").unwrap();
        acknowledge(&wallet.path, WalletNetwork::Regtest, "partial-op").unwrap();
        assert!(list(&wallet.path, WalletNetwork::Regtest, None)
            .unwrap()
            .is_empty());
        let reservations: u32 = conn
            .query_row("SELECT COUNT(*) FROM vizor_send_proposal_locks", [], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(reservations, 0, "same-process reservation cleanup");
        handle.abort();
    }
}

#[tokio::test]
async fn partial_storage_failure_retains_real_inputs_after_acknowledgement() {
    use secrecy::ExposeSecret;
    use transparent::{
        address::TransparentAddress,
        bundle::TxOut,
        keys::{AccountPrivKey, NonHardenedChildIndex, TransparentKeyScope},
    };
    use zcash_client_backend::{
        data_api::{OutputLockStore, WalletWrite},
        wallet::{LockOwner, OutputRef, WalletTransparentOutput},
    };
    use zcash_protocol::{consensus::BlockHeight, value::Zatoshis, PoolType};
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for kind in ["swap_deposit", "pay_deposit"] {
        for storage_fails in [true, false] {
            let mut wallet = Wallet::new(true);
            let seed = secrecy::SecretVec::new(vec![1; 32]);
            let (uuid, _) = crate::wallet::keys::init_db_and_create_account(
                &wallet.path,
                WalletNetwork::Regtest,
                &seed,
                Some(1),
                "Ledger",
            )
            .unwrap();
            let account = crate::wallet::keys::parse_account_uuid(&uuid).unwrap();
            let key = AccountPrivKey::from_seed(
                &WalletNetwork::Regtest,
                seed.expose_secret(),
                zip32::AccountId::ZERO,
            )
            .unwrap()
            .derive_external_secret_key(NonHardenedChildIndex::from_index(0).unwrap())
            .unwrap();
            let address =
                TransparentAddress::from_pubkey(&key.public_key(&secp256k1::Secp256k1::new()));
            wallet.signed[0] = Signed::with_key(OutPoint::new([1; 32], 0), 1_000_000, key);
            wallet.signed[1] = Signed::with_key(
                OutPoint::new(*wallet.signed[0].tx.txid().as_ref(), 0),
                990_000,
                key,
            );
            let owner = LockOwner::new([43; 32]);
            let output = OutputRef::new(
                zcash_primitives::transaction::TxId::from_bytes([1; 32]),
                PoolType::TRANSPARENT,
                0,
            );
            let expiry = wallet.signed[0].tx.expiry_height();
            let mut db = crate::wallet::db::open_wallet_db_with_timeout(
                &wallet.path,
                WalletNetwork::Regtest,
                WALLET_DB_BUSY_TIMEOUT,
            )
            .unwrap();
            db.update_chain_tip(BlockHeight::from_u32(200)).unwrap();
            db.put_received_transparent_utxo(
                &WalletTransparentOutput::from_parts(
                    OutPoint::new([1; 32], 0),
                    TxOut::new(Zatoshis::const_from_u64(1_000_000), address.script().into()),
                    Some(BlockHeight::from_u32(150)),
                    Some(account),
                    Some(TransparentKeyScope::EXTERNAL),
                    None,
                )
                .unwrap(),
            )
            .unwrap();
            db.lock_outputs(std::slice::from_ref(&output), owner, expiry)
                .unwrap();
            drop(db);
            proposal_locks::persist(&wallet.path, owner, &[output], expiry).unwrap();
            wallet.signed[0].proof = proposal_locks::bind_pczt(
                pczt::Pczt::parse(&wallet.signed[0].proof).unwrap(),
                owner,
            )
            .serialize()
            .unwrap();
            wallet.checkpoint("storage-op", kind);
            let conn = rusqlite::Connection::open(&wallet.path).unwrap();
            if storage_fails {
                conn.execute_batch("CREATE TRIGGER refuse_storage BEFORE INSERT ON transactions BEGIN SELECT RAISE(ABORT, 'forced wallet storage failure'); END;").unwrap();
            }
            let (url, service, handle) = server(200, 0).await;
            *service.responses.lock().unwrap() = vec![0, 1];
            let result = broadcast(
                &wallet.path,
                &url,
                WalletNetwork::Regtest,
                "storage-op",
                None,
                None,
            )
            .await
            .unwrap();
            assert_eq!(result.status, "partial_broadcast");
            assert!(result.requires_ack);
            assert_eq!(*service.calls.lock().unwrap(), ["tip", "send", "send"]);
            let storage_failure = result
                .message
                .as_deref()
                .unwrap()
                .contains("local storage failed");
            assert_eq!(storage_failure, storage_fails, "{result:?}");
            if storage_fails {
                let message = result.message.as_deref().unwrap();
                assert!(message.contains("Primary PCZT storage failed"), "{message}");
                assert!(message.contains("Fallback storage failed"), "{message}");
                assert!(
                    message.contains("forced wallet storage failure"),
                    "{message}"
                );
            }
            let parent_stored: bool = conn
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM transactions WHERE txid = ?1 AND raw IS NOT NULL)",
                    [wallet.signed[0].tx.txid().as_ref()],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(parent_stored, !storage_fails);
            acknowledge(&wallet.path, WalletNetwork::Regtest, "storage-op").unwrap();
            assert!(list(&wallet.path, WalletNetwork::Regtest, None)
                .unwrap()
                .is_empty());
            let reservations: u32 = conn.query_row("SELECT COUNT(*) FROM vizor_send_proposal_locks WHERE retain_until_expiry = 1 AND phase = 'signed'", [], |r| r.get(0)).unwrap();
            let locked: bool = conn.query_row("SELECT EXISTS(SELECT 1 FROM transparent_received_outputs WHERE lock_owner = ?1)", [owner.as_bytes().as_slice()], |r| r.get(0)).unwrap();
            assert_eq!(reservations, u32::from(storage_fails));
            assert_eq!(
                locked, storage_fails,
                "unrecorded network spend must keep its real input locked"
            );
            handle.abort();
        }
    }
}

#[tokio::test]
async fn invalid_signed_effects_are_rejected_even_when_base_is_mined() {
    let wallet = Wallet::new(false);
    wallet.store(0, Some(&wallet.signed[0].raw), Some(201));
    let different = Signed::new(OutPoint::new([2; 32], 0), 1_000_000);
    let error = store_and_broadcast_signed_pczts(
        &wallet.path,
        "http://127.0.0.1:1",
        WalletNetwork::Regtest,
        &[wallet.signed[0].proof.clone()],
        &[different.signature],
        None,
        None,
    )
    .await
    .err()
    .expect("mismatched effects must fail");
    assert!(
        error.contains("transaction effects do not match"),
        "{error}"
    );
}

#[tokio::test]
async fn proposal_recovery_preserves_retry_capability_until_mined_evidence_returns() {
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    for evidence in ["missing", "conflicting", "rescan"] {
        let wallet = Wallet::new(false);
        let raw = match evidence {
            "missing" => None,
            "conflicting" => Some(&b"conflicting"[..]),
            _ => Some(wallet.signed[0].raw.as_slice()),
        };
        wallet.store(0, raw, Some(201));
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        if evidence == "rescan" {
            conn.execute(
                "UPDATE transactions SET mined_height = NULL, expiry_height = ?1",
                [u32::from(wallet.signed[0].tx.expiry_height())],
            )
            .unwrap();
            conn.execute_batch("DELETE FROM scan_queue; INSERT INTO scan_queue (block_range_start, block_range_end, priority) VALUES (200, 206, 20)").unwrap();
        }
        let proposal = SignedProposal::new(&wallet);
        let error = proposal
            .recover(&wallet, wallet.signed[0].signature.clone())
            .await
            .err()
            .expect("incomplete mined evidence must remain retryable");
        assert!(error.contains("retry after sync"), "{evidence}: {error}");
        proposal.assert_retained(&wallet, true);
        conn.execute(
            "UPDATE transactions SET raw = ?1, mined_height = 201",
            [&wallet.signed[0].raw],
        )
        .unwrap();
        let result = proposal
            .recover(&wallet, wallet.signed[0].signature.clone())
            .await
            .unwrap();
        assert_eq!(result.status, "broadcasted");
        assert_eq!((result.broadcasted_count, result.total_count), (1, 1));
        assert_eq!(result.txids, wallet.signed[0].tx.txid().to_string());
        proposal.assert_retained(&wallet, false);
    }
}

#[tokio::test]
async fn proposal_recovery_still_releases_invalid_signed_effects() {
    let wallet = Wallet::new(false);
    wallet.store(0, Some(&wallet.signed[0].raw), Some(201));
    let proposal = SignedProposal::new(&wallet);
    let different = Signed::new(OutPoint::new([2; 32], 0), 1_000_000);
    let error = proposal
        .recover(&wallet, different.signature)
        .await
        .err()
        .expect("mismatched effects must fail");
    assert!(
        error.contains("transaction effects do not match"),
        "{error}"
    );
    proposal.assert_retained(&wallet, false);
}

#[tokio::test]
async fn interrupted_outcome_write_recovers_in_a_fresh_offline_process() {
    use crate::wallet::db::open_wallet_db_with_timeout;
    use secrecy::ExposeSecret;
    use transparent::{
        address::TransparentAddress,
        bundle::TxOut,
        keys::{AccountPrivKey, NonHardenedChildIndex, TransparentKeyScope},
    };
    use zcash_client_backend::{
        data_api::{wallet::decrypt_and_store_transaction, WalletWrite},
        wallet::WalletTransparentOutput,
    };
    use zcash_protocol::{consensus::BlockHeight, value::Zatoshis};
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    let mut wallet = Wallet::new(false);
    let seed = secrecy::SecretVec::new(vec![1; 32]);
    let (uuid, _) = crate::wallet::keys::init_db_and_create_account(
        &wallet.path,
        WalletNetwork::Regtest,
        &seed,
        Some(1),
        "Ledger",
    )
    .unwrap();
    let account = crate::wallet::keys::parse_account_uuid(&uuid).unwrap();
    let key = AccountPrivKey::from_seed(
        &WalletNetwork::Regtest,
        seed.expose_secret(),
        zip32::AccountId::ZERO,
    )
    .unwrap()
    .derive_external_secret_key(NonHardenedChildIndex::from_index(0).unwrap())
    .unwrap();
    let address = TransparentAddress::from_pubkey(&key.public_key(&secp256k1::Secp256k1::new()));
    wallet.signed[0] = Signed::with_key(OutPoint::new([1; 32], 0), 1_000_000, key);
    let signed = &wallet.signed[0];
    let mut db =
        open_wallet_db_with_timeout(&wallet.path, WalletNetwork::Regtest, WALLET_DB_BUSY_TIMEOUT)
            .unwrap();
    db.update_chain_tip(BlockHeight::from_u32(200)).unwrap();
    db.put_received_transparent_utxo(
        &WalletTransparentOutput::from_parts(
            OutPoint::new([1; 32], 0),
            TxOut::new(Zatoshis::const_from_u64(1_000_000), address.script().into()),
            Some(BlockHeight::from_u32(150)),
            Some(account),
            Some(TransparentKeyScope::EXTERNAL),
            None,
        )
        .unwrap(),
    )
    .unwrap();
    drop(db);
    checkpoint(
        &wallet.path,
        WalletNetwork::Regtest,
        "restart-op",
        &uuid,
        "swap_deposit",
        Some("deposit-1"),
        &signed.proof,
        &signed.signature,
    )
    .unwrap();
    let conn = open_wallet_raw_conn_with_timeout(&wallet.path, WALLET_DB_BUSY_TIMEOUT).unwrap();
    conn.execute_batch("CREATE TRIGGER interrupt_outcome BEFORE UPDATE ON vizor_ledger_signed_operations WHEN NEW.state = 'result_pending_ack' BEGIN SELECT RAISE(ABORT, 'interrupted outcome write'); END").unwrap();
    let (url, service, handle) = server(200, 0).await;
    let error = broadcast(
        &wallet.path,
        &url,
        WalletNetwork::Regtest,
        "restart-op",
        None,
        None,
    )
    .await
    .unwrap_err();
    assert!(error.contains("interrupted outcome write"), "{error}");
    assert_eq!(*service.submitted.lock().unwrap(), [signed.raw.clone()]);
    assert_eq!(
        list(&wallet.path, WalletNetwork::Regtest, None).unwrap()[0].state,
        STATE_SIGNED_PENDING_BROADCAST
    );
    let raw: Vec<u8> = conn
        .query_row(
            "SELECT raw FROM transactions WHERE txid=?1",
            [signed.tx.txid().as_ref()],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(raw, signed.raw);
    assert_eq!(
        conn.query_row(
            "SELECT COUNT(*) FROM transparent_received_output_spends",
            [],
            |r| r.get::<_, u32>(0)
        )
        .unwrap(),
        1
    );
    conn.execute_batch("DROP TRIGGER interrupt_outcome")
        .unwrap();
    drop(conn);
    // Sync observes mining before startup can reconcile the pending outbox row.
    let mut db =
        open_wallet_db_with_timeout(&wallet.path, WalletNetwork::Regtest, WALLET_DB_BUSY_TIMEOUT)
            .unwrap();
    decrypt_and_store_transaction(
        &WalletNetwork::Regtest,
        &mut db,
        &signed.tx,
        Some(BlockHeight::from_u32(201)),
    )
    .unwrap();
    db.update_chain_tip(BlockHeight::from_u32(1_000)).unwrap();
    drop(db);
    for _ in 0..2 {
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
    }
    assert_eq!(*service.submitted.lock().unwrap(), [signed.raw.clone()]);
    acknowledge(&wallet.path, WalletNetwork::Regtest, "restart-op").unwrap();
    assert!(list(&wallet.path, WalletNetwork::Regtest, None)
        .unwrap()
        .is_empty());
    handle.abort();
}

#[tokio::test]
async fn offline_restart_child() {
    let Ok(path) = std::env::var("VIZOR_MINED_RECOVERY_TEST_DB") else {
        return;
    };
    crate::network_privacy::disable_tor();
    let rows = list(&path, WalletNetwork::Regtest, None).unwrap();
    if rows[0].state == STATE_RESULT_PENDING_ACK {
        assert_eq!(rows[0].status.as_deref(), Some("broadcasted"));
        assert_eq!(rows[0].external_ref.as_deref(), Some("deposit-1"));
        return;
    }
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
