use super::tests::{fake_raw, fake_txid, fresh_db, insert_row};
use super::*;
use tempfile::NamedTempFile;

fn populate_recovery_wallet(path: &str, txid: &[u8], raw: &[u8]) {
    // Exercise a real migrated view with an outgoing transaction spending a
    // funding note and returning change. These are synthetic SQL note contents;
    // this test verifies persisted recovery state, not note cryptography.
    crate::wallet::keys::init_db_and_create_account(
        path,
        WalletNetwork::Test,
        &secrecy::SecretVec::new(vec![7; 32]),
        Some(800_000),
        "Recovery test",
    )
    .unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    let account: i64 = conn
        .query_row("SELECT id FROM accounts", [], |r| r.get(0))
        .unwrap();
    let funding = fake_txid(0x80);
    conn.execute(
        "INSERT INTO transactions (id_tx, txid, mined_height, min_observed_height, expiry_height)
        VALUES (10, ?1, 800000, 800000, 1000000)",
        [funding],
    )
    .unwrap();
    conn.execute("INSERT INTO transactions (id_tx, txid, raw, mined_height, min_observed_height, expiry_height)
        VALUES (11, ?1, ?2, NULL, 800001, 1000000)", rusqlite::params![txid, raw]).unwrap();
    for (id, value) in [(10, 1000), (11, 100)] {
        conn.execute(
            "INSERT INTO orchard_received_notes
            (id, transaction_id, action_index, account_id, diversifier, value, rho, rseed,
             is_change, commitment_tree_position, recipient_key_scope, note_version)
            VALUES (?1, ?1, 0, ?2, zeroblob(11), ?3, zeroblob(32), zeroblob(32), 1, ?1, 1, 2)",
            rusqlite::params![id, account, value],
        )
        .unwrap();
    }
    conn.execute(
        "INSERT INTO orchard_received_note_spends (orchard_received_note_id, transaction_id)
        VALUES (10, 11)",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 0), (?1, 1)",
        [txid],
    )
    .unwrap();
}

fn add_recovery_evidence(
    conn: &rusqlite::Connection,
    txid: &[u8],
    pool: &str,
    position: Option<i64>,
) {
    conn.execute(
        &format!(
            "INSERT INTO {pool}_received_notes
        SELECT id_tx, ?2 FROM transactions WHERE txid = ?1"
        ),
        rusqlite::params![txid, position],
    )
    .unwrap();
}

fn queue_status(conn: &rusqlite::Connection, txid: &[u8], kind: i64) {
    conn.execute(
        "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, ?2)",
        rusqlite::params![txid, kind],
    )
    .unwrap();
}

fn assert_resubmit_count(db: &NamedTempFile, count: usize) {
    let path = db.path().to_str().unwrap();
    assert_eq!(get_resubmittable_txs(path, 900_000).unwrap().len(), count);
    // Exercise the separate metadata/raw path, without excluding our fixture.
    assert_eq!(
        get_resubmittable_txs_excluding(path, 900_000, &HashSet::from([fake_txid(0xff).to_vec()]))
            .unwrap()
            .len(),
        count
    );
}

#[test]
fn resubmit_status_guard_matrix() {
    for pool in ["sapling", "orchard", "ironwood"] {
        for position in [None, Some(0), Some(42)] {
            for status in [false, true] {
                for payload in [false, true] {
                    let db = fresh_db();
                    let txid = fake_txid(0x81);
                    insert_row(&db, &txid, Some(&fake_raw()), None, Some(1_000_000), -1);
                    let conn = rusqlite::Connection::open(db.path()).unwrap();
                    add_recovery_evidence(&conn, &txid, pool, position);
                    if status {
                        queue_status(&conn, &txid, 0);
                    }
                    if payload {
                        queue_status(&conn, &txid, 1);
                    }
                    assert_resubmit_count(&db, usize::from(!(status && position.is_some())));
                }
            }
        }
    }
}

#[test]
fn resubmit_no_change_mined_history_survives_backend_rewind() {
    let file = NamedTempFile::new().unwrap();
    let path = file.path().to_str().unwrap();
    let txid = fake_txid(0x91);
    populate_recovery_wallet(path, &txid, &fake_raw());
    let mut wallet = open_wallet_db(path, WalletNetwork::Test).unwrap();
    let mut conn = rusqlite::Connection::open(path).unwrap();
    conn.execute(
        "DELETE FROM orchard_received_notes WHERE transaction_id = 11",
        [],
    )
    .unwrap();
    wallet
        .update_chain_tip(BlockHeight::from_u32(900_000))
        .unwrap();
    // The funding note and spend link are present even before this send mines.
    assert_resubmit_count(&file, 1);
    let pending = [BlockHeight::from_u32(800_000)..BlockHeight::from_u32(900_001)];
    assert!(get_unmined_txids_with_mined_output_evidence(path, &pending)
        .unwrap()
        .is_empty());
    wallet
        .set_transaction_status(
            zcash_primitives::transaction::TxId::from_bytes(txid),
            zcash_client_backend::data_api::TransactionStatus::Mined(BlockHeight::from_u32(
                800_001,
            )),
        )
        .unwrap();
    // Real backend truncation clears the mined height but preserves our evidence.
    conn.execute(
        "INSERT INTO blocks (height, hash, time, sapling_tree)
         VALUES (800000, zeroblob(32), 0, X'000000')",
        [],
    )
    .unwrap();
    wallet
        .truncate_to_height(BlockHeight::from_u32(800_000))
        .unwrap();
    assert_eq!(
        conn.query_row(
            "SELECT mined_height FROM transactions WHERE id_tx = 11",
            [],
            |r| r.get::<_, Option<u32>>(0)
        )
        .unwrap(),
        None
    );
    conn.execute(
        "INSERT OR IGNORE INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 0), (?1, 1)",
        [txid],
    )
    .unwrap();
    assert_resubmit_count(&file, 0);
    assert_eq!(
        get_unmined_txids_with_mined_output_evidence(path, &pending).unwrap(),
        HashSet::from([txid.to_vec()])
    );
    // Reopening does not lose the guard. A conclusive result releases status only.
    drop(wallet);
    let mut wallet = open_wallet_db(path, WalletNetwork::Test).unwrap();
    wallet
        .update_chain_tip(BlockHeight::from_u32(900_000))
        .unwrap();
    assert_resubmit_count(&file, 0);
    assert!(resolve_recovered_nonmined_status(&mut conn, &txid).unwrap());
    assert_resubmit_count(&file, 1);
    assert_eq!(
        conn.query_row(
            "SELECT query_type FROM tx_retrieval_queue WHERE txid = ?1",
            [txid],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        1
    );
    assert!(get_unmined_txids_with_mined_output_evidence(path, &[])
        .unwrap()
        .is_empty());
}

#[test]
fn resubmit_evidence_is_transaction_scoped_and_deduplicated() {
    let db = fresh_db();
    let txid = fake_txid(0x81);
    let other = fake_txid(0x82);
    insert_row(&db, &txid, Some(&fake_raw()), None, Some(1_000_000), -1);
    insert_row(&db, &txid, Some(&fake_raw()), None, Some(1_000_000), -1);
    insert_row(
        &db,
        &other,
        Some(&fake_raw()),
        Some(800_000),
        Some(1_000_000),
        -1,
    );
    let conn = rusqlite::Connection::open(db.path()).unwrap();
    queue_status(&conn, &txid, 0);
    add_recovery_evidence(&conn, &other, "orchard", Some(0));
    assert_resubmit_count(&db, 1);
    add_recovery_evidence(&conn, &txid, "sapling", Some(0));
    assert_resubmit_count(&db, 0);
}

#[test]
fn resubmit_status_resolution_preserves_payload_and_releases_guard() {
    for pool in ["sapling", "orchard", "ironwood"] {
        let db = fresh_db();
        let txid = fake_txid(0x81);
        insert_row(&db, &txid, Some(&fake_raw()), None, Some(1_000_000), -1);
        let mut conn = rusqlite::Connection::open(db.path()).unwrap();
        queue_status(&conn, &txid, 0);
        queue_status(&conn, &txid, 1);
        add_recovery_evidence(&conn, &txid, pool, Some(0));
        // Repeated passes (including after reopening the DB) retain suppression.
        assert_resubmit_count(&db, 0);
        assert_resubmit_count(&db, 0);
        assert!(resolve_recovered_nonmined_status(&mut conn, &txid).unwrap());
        assert_resubmit_count(&db, 1);
        assert_eq!(
            conn.query_row("SELECT query_type FROM tx_retrieval_queue", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            1
        );
        assert_eq!(
            conn.query_row(
                "SELECT confirmed_unmined_at_height FROM transactions",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
            900_000
        );
        assert!(!resolve_recovered_nonmined_status(&mut conn, &txid).unwrap());
    }
}

#[test]
fn resubmit_resolution_errors_roll_back_and_retain_guard() {
    for failure in [
        "CREATE TRIGGER reject_status_delete BEFORE DELETE ON tx_retrieval_queue
                    BEGIN SELECT RAISE(ABORT, 'injected failure'); END;",
        "DELETE FROM scan_queue;",
    ] {
        let db = fresh_db();
        let txid = fake_txid(0x81);
        insert_row(&db, &txid, Some(&fake_raw()), None, Some(1_000_000), -1);
        let mut conn = rusqlite::Connection::open(db.path()).unwrap();
        queue_status(&conn, &txid, 0);
        add_recovery_evidence(&conn, &txid, "ironwood", Some(0));
        conn.execute_batch(failure).unwrap();
        assert!(resolve_recovered_nonmined_status(&mut conn, &txid).is_err());
        assert_resubmit_count(&db, 0);
        assert_eq!(
            conn.query_row(
                "SELECT confirmed_unmined_at_height FROM transactions",
                [],
                |r| r.get::<_, Option<i64>>(0)
            )
            .unwrap(),
            None
        );
    }
}

#[test]
fn resubmit_guard_schema_errors_fail_closed() {
    for table in [
        "vizor_mined_transactions",
        "tx_retrieval_queue",
        "sapling_received_notes",
        "orchard_received_notes",
        "ironwood_received_notes",
    ] {
        let db = fresh_db();
        insert_row(
            &db,
            &fake_txid(0x81),
            Some(&fake_raw()),
            None,
            Some(1_000_000),
            -1,
        );
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(&format!("DROP TABLE {table}"), []).unwrap();
        let path = db.path().to_str().unwrap();
        assert!(get_resubmittable_txs(path, 900_000).is_err());
        assert!(get_resubmittable_txs_excluding(
            path,
            900_000,
            &HashSet::from([fake_txid(0xff).to_vec()])
        )
        .is_err());
    }
}

#[derive(Clone)]
struct CountingLightwalletd(
    std::sync::Arc<std::sync::Mutex<Vec<Vec<u8>>>>,
    std::sync::Arc<
        std::sync::Mutex<Result<zcash_client_backend::proto::service::BlockId, tonic::Status>>,
    >,
    std::sync::Arc<std::sync::Mutex<Vec<&'static str>>>,
);

impl Default for CountingLightwalletd {
    fn default() -> Self {
        Self(
            Default::default(),
            std::sync::Arc::new(std::sync::Mutex::new(Ok(
                zcash_client_backend::proto::service::BlockId {
                    height: 900_000,
                    hash: vec![0x11; 32],
                },
            ))),
            Default::default(),
        )
    }
}

impl tonic::server::NamedService for CountingLightwalletd {
    const NAME: &'static str = "cash.z.wallet.sdk.rpc.CompactTxStreamer";
}

impl tower_service::Service<http::Request<tonic::body::Body>> for CountingLightwalletd {
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
        let requests = self.0.clone();
        let tip = self.1.clone();
        let calls = self.2.clone();
        Box::pin(async move {
            let message = if req.uri().path().ends_with("/GetLatestBlock") {
                calls.lock().unwrap().push("tip");
                match tip.lock().unwrap().clone() {
                    Ok(tip) => tip.encode_to_vec(),
                    Err(error) => {
                        return Ok(http::Response::builder()
                            .header("content-type", "application/grpc")
                            .header("grpc-status", (error.code() as u32).to_string())
                            .body(tonic::body::Body::empty())
                            .unwrap())
                    }
                }
            } else {
                assert!(req.uri().path().ends_with("/SendTransaction"));
                calls.lock().unwrap().push("send");
                let body = req.into_body().collect().await.unwrap().to_bytes();
                let raw = zcash_client_backend::proto::service::RawTransaction::decode(&body[5..])
                    .unwrap();
                requests.lock().unwrap().push(raw.data);
                // Empty protobuf: SendResponse { error_code: 0, error_message: "" }.
                Vec::new()
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

#[tokio::test]
async fn resubmit_rpc_guard_and_fail_closed() {
    use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
    use zcash_primitives::transaction::{Authorized, TransactionData, TxVersion};
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let service = CountingLightwalletd::default();
    let requests = service.0.clone();
    let incoming = futures::stream::unfold(listener, |listener| async {
        Some((listener.accept().await.map(|(socket, _)| socket), listener))
    });
    let server = tokio::spawn(
        tonic::transport::Server::builder()
            .add_service(service)
            .serve_with_incoming(incoming),
    );
    let channel = tonic::transport::Endpoint::from_shared(url.clone())
        .unwrap()
        .connect()
        .await
        .unwrap();
    let mut client = CompactTxStreamerClient::new(channel);
    let db = fresh_db();
    let path = db.path().to_str().unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    let mut txids = Vec::new();
    let mut raws = Vec::new();
    for lock_time in [0, 1] {
        let tx = TransactionData::<Authorized>::from_parts(
            TxVersion::V5,
            BranchId::Nu5,
            lock_time,
            BlockHeight::from_u32(1_000_000),
            None,
            None,
            None,
            None,
        )
        .freeze()
        .unwrap();
        let mut raw = Vec::new();
        tx.write(&mut raw).unwrap();
        let txid = tx.txid().as_ref().to_vec();
        insert_row(&db, &txid, Some(&raw), None, Some(1_000_000), -1);
        queue_status(&conn, &txid, 0);
        if lock_time == 0 {
            // No received change note: only the durable mined-history record
            // can suppress this transaction's SendTransaction RPC.
            conn.execute(
                "UPDATE transactions SET mined_height = 800001 WHERE txid = ?1",
                [&txid],
            )
            .unwrap();
            conn.execute(
                "UPDATE transactions SET mined_height = NULL WHERE txid = ?1",
                [&txid],
            )
            .unwrap();
        } else {
            add_recovery_evidence(&conn, &txid, "ironwood", Some(0));
        }
        txids.push(txid);
        raws.push(raw);
    }
    for exclusions in [HashSet::new(), HashSet::from([fake_txid(0xff).to_vec()])] {
        let stats = crate::wallet::sync::resubmit_pending_transactions(
            path,
            &url,
            &mut client,
            900_000,
            &exclusions,
            || false,
        )
        .await;
        assert_eq!(stats.attempted, 0);
        assert!(requests.lock().unwrap().is_empty());
    }
    // The ordinary post-batch pass uses the same verified handoff. A status
    // observation alone cannot release either guarded transaction on a new or
    // unverified chain. Unrelated pending status work must never be completed.
    use crate::wallet::sync_engine::{complete_verified_recovery_statuses, RefreshedTipRelation};
    let ready = HashSet::from([txids[0].clone()]);
    for relation in [
        RefreshedTipRelation::UnchangedUnverified,
        RefreshedTipRelation::Advanced,
        RefreshedTipRelation::Reorg,
        RefreshedTipRelation::ServerBehind,
    ] {
        complete_verified_recovery_statuses(path, &ready, relation).unwrap();
        let stats = crate::wallet::sync::resubmit_pending_transactions(
            path,
            &url,
            &mut client,
            900_000,
            &HashSet::new(),
            || false,
        )
        .await;
        assert_eq!(stats.attempted, 0);
        assert!(requests.lock().unwrap().is_empty());
    }
    complete_verified_recovery_statuses(path, &HashSet::new(), RefreshedTipRelation::Unchanged)
        .unwrap();
    assert!(has_recovered_status_work(&conn, &txids[0]).unwrap());
    complete_verified_recovery_statuses(path, &ready, RefreshedTipRelation::Unchanged).unwrap();
    let stats = crate::wallet::sync::resubmit_pending_transactions(
        path,
        &url,
        &mut client,
        900_000,
        &HashSet::new(),
        || false,
    )
    .await;
    assert_eq!(stats.succeeded, 1);
    assert_eq!(*requests.lock().unwrap(), vec![raws[0].clone()]);
    conn.execute("DROP TABLE orchard_received_notes", [])
        .unwrap();
    let stats = crate::wallet::sync::resubmit_pending_transactions(
        path,
        &url,
        &mut client,
        900_000,
        &HashSet::new(),
        || false,
    )
    .await;
    assert_eq!(stats.attempted, 0);
    assert_eq!(requests.lock().unwrap().len(), 1);
    server.abort();
}

/// A status observation resolved on the queue-drain path (no pending scan
/// ranges, so no post-batch pass follows) must still put the released
/// transaction on the wire in the same sync.
#[tokio::test]
async fn released_status_resubmission_refreshes_tip_before_expiry_filter() {
    use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
    use zcash_primitives::transaction::{Authorized, TransactionData, TxVersion};
    let _policy = crate::network_privacy::test_route_policy::lock_route_policy();
    crate::network_privacy::disable_tor();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let service = CountingLightwalletd::default();
    let requests = service.0.clone();
    let tip_response = service.1.clone();
    let calls = service.2.clone();
    let incoming = futures::stream::unfold(listener, |listener| async {
        Some((listener.accept().await.map(|(socket, _)| socket), listener))
    });
    let server = tokio::spawn(
        tonic::transport::Server::builder()
            .add_service(service)
            .serve_with_incoming(incoming),
    );
    let channel = tonic::transport::Endpoint::from_shared(url.clone())
        .unwrap()
        .connect()
        .await
        .unwrap();
    let mut client = CompactTxStreamerClient::new(channel);
    let tx = TransactionData::<Authorized>::from_parts(
        TxVersion::V5,
        BranchId::Nu5,
        0,
        BlockHeight::from_u32(1_000_000),
        None,
        None,
        None,
        None,
    )
    .freeze()
    .unwrap();
    let mut raw = Vec::new();
    tx.write(&mut raw).unwrap();
    let txid = tx.txid().as_ref().to_vec();
    let db = NamedTempFile::new().unwrap();
    let path = db.path().to_str().unwrap();
    populate_recovery_wallet(path, &txid, &raw);
    let conn = rusqlite::Connection::open(path).unwrap();
    let mut wallet = open_wallet_db(path, WalletNetwork::Test).unwrap();
    wallet
        .update_chain_tip(BlockHeight::from_u32(999_999))
        .unwrap();
    conn.execute(
        "INSERT INTO blocks (height, hash, time, sapling_tree)
        VALUES (999999, ?1, 0, X'000000')",
        [vec![0x11; 32]],
    )
    .unwrap();
    // Model a fully scanned wallet at the old tip before enhancement drains.
    conn.execute_batch(
        "DELETE FROM scan_queue;
        INSERT INTO scan_queue (block_range_start, block_range_end, priority)
        VALUES (800000, 1000000, 10);",
    )
    .unwrap();
    use crate::wallet::sync_engine::ReleasedResubmission;
    let mut validated_tip = 999_999;

    macro_rules! resubmit {
        ($released:expr, $allow:expr, $exit:expr) => {
            crate::wallet::sync_engine::resubmit_released_transactions(
                &if $released {
                    HashSet::from([txid.clone()])
                } else {
                    HashSet::new()
                },
                $allow,
                &[],
                path,
                &url,
                &mut client,
                &mut wallet,
                validated_tip,
                $exit,
            )
        };
    }
    // Still guarded: nothing released, nothing broadcast.
    assert!(matches!(
        resubmit!(false, true, || false).await.unwrap(),
        ReleasedResubmission::Skipped
    ));
    assert!(requests.lock().unwrap().is_empty());

    // Enhancement observes a conclusive status but retains the durable guard.
    assert!(has_recovered_status_work(&conn, &txid).unwrap());
    assert!(
        matches!(
            resubmit!(true, false, || false).await.unwrap(),
            ReleasedResubmission::Skipped
        ),
        "a sync that disallows resubmission never broadcasts"
    );
    assert!(requests.lock().unwrap().is_empty());

    assert!(
        calls.lock().unwrap().is_empty(),
        "disabled passes do not fetch a tip"
    );

    use zcash_client_backend::proto::service::BlockId;
    // Equal heights cannot rule out a same-height reorg when the wallet has
    // no stored tip hash. The released, unexpired candidate must stay private.
    conn.execute("DELETE FROM blocks WHERE height = 999999", [])
        .unwrap();
    assert!(get_resubmittable_txs(path, 999_999).unwrap().is_empty());
    *tip_response.lock().unwrap() = Ok(BlockId {
        height: 999_999,
        hash: vec![0x22; 32],
    });
    assert!(matches!(
        resubmit!(true, true, || false).await.unwrap(),
        ReleasedResubmission::Skipped
    ));
    assert_eq!(*calls.lock().unwrap(), vec!["tip"]);
    assert!(requests.lock().unwrap().is_empty());
    // The next startup pass must still suppress this transaction even though
    // status resolution preceded the unverified tip and no scan ranges remain.
    let stats = crate::wallet::sync::resubmit_pending_transactions(
        path,
        &url,
        &mut client,
        999_999,
        &HashSet::new(),
        || false,
    )
    .await;
    assert_eq!(stats.attempted, 0);
    assert!(requests.lock().unwrap().is_empty());
    assert_eq!(
        conn.query_row(
            "SELECT COUNT(*) FROM tx_retrieval_queue WHERE txid = ?1 AND query_type = 0",
            [&txid],
            |row| row.get::<_, i64>(0),
        )
        .unwrap(),
        1
    );
    conn.execute(
        "INSERT INTO blocks (height, hash, time, sapling_tree)
        VALUES (999999, ?1, 0, X'000000')",
        [vec![0x11; 32]],
    )
    .unwrap();

    // A failed completion leaves suppression durable despite a verified tip.
    *tip_response.lock().unwrap() = Ok(BlockId {
        height: 999_999,
        hash: vec![0x11; 32],
    });
    conn.execute_batch(
        "CREATE TRIGGER reject_status_completion BEFORE DELETE ON tx_retrieval_queue
        BEGIN SELECT RAISE(ABORT, 'injected completion failure'); END;",
    )
    .unwrap();
    assert!(resubmit!(true, true, || false).await.is_err());
    assert!(requests.lock().unwrap().is_empty());
    assert!(has_recovered_status_work(&conn, &txid).unwrap());
    conn.execute("DROP TRIGGER reject_status_completion", [])
        .unwrap();

    // Enhancement started at the last valid height, 999999. A block mined
    // during the drain must make expiry == refreshed tip ineligible immediately.
    for (height, expected_sends) in [(1_000_000, 0), (1_000_001, 0), (999_999, 1)] {
        conn.execute_batch(
            "DELETE FROM scan_queue;
            INSERT INTO scan_queue (block_range_start, block_range_end, priority)
            VALUES (800000, 1000000, 10);",
        )
        .unwrap();
        *tip_response.lock().unwrap() = Ok(BlockId {
            height,
            hash: vec![0x11; 32],
        });
        calls.lock().unwrap().clear();
        requests.lock().unwrap().clear();
        let outcome = resubmit!(true, true, || false).await.unwrap();
        match outcome {
            ReleasedResubmission::TipAdvanced(actual) if height > 999_999 => {
                assert_eq!(actual, height);
                assert_eq!(
                    wallet.chain_height().unwrap(),
                    Some(BlockHeight::from_u32(height as u32))
                );
            }
            ReleasedResubmission::Resubmitted if height == 999_999 => {}
            unexpected => panic!("unexpected outcome at height {height}: {unexpected:?}"),
        }
        assert_eq!(requests.lock().unwrap().len(), expected_sends as usize);
        if expected_sends == 0 {
            assert_eq!(*calls.lock().unwrap(), vec!["tip"]);
        } else {
            assert_eq!(*requests.lock().unwrap(), vec![raw.clone()]);
            assert_eq!(*calls.lock().unwrap(), vec!["tip", "send"]);
        }
    }

    queue_status(&conn, &txid, 0);
    // No stale-tip fallback for unavailable, lagging, divergent or malformed tips.
    for response in [
        Err(tonic::Status::unavailable("tip lookup failed")),
        Ok(BlockId {
            height: 999_998,
            hash: vec![0x11; 32],
        }),
        Ok(BlockId {
            height: 999_999,
            hash: vec![0x22; 32],
        }),
        Ok(BlockId {
            height: 999_999,
            hash: vec![0x11; 31],
        }),
        Ok(BlockId {
            height: u32::MAX as u64 + 1,
            hash: vec![0x11; 32],
        }),
    ] {
        *tip_response.lock().unwrap() = response;
        calls.lock().unwrap().clear();
        requests.lock().unwrap().clear();
        assert!(resubmit!(true, true, || false).await.is_err());
        assert!(requests.lock().unwrap().is_empty());
        assert_eq!(*calls.lock().unwrap(), vec!["tip"]);
        let stats = crate::wallet::sync::resubmit_pending_transactions(
            path,
            &url,
            &mut client,
            999_999,
            &HashSet::new(),
            || false,
        )
        .await;
        assert_eq!(
            stats.attempted, 0,
            "a retry must retain suppression after tip failure"
        );
        assert!(requests.lock().unwrap().is_empty());
    }

    *tip_response.lock().unwrap() = Ok(BlockId {
        height: 999_999,
        hash: vec![0x11; 32],
    });
    calls.lock().unwrap().clear();
    assert!(matches!(
        resubmit!(true, true, || true).await.unwrap(),
        ReleasedResubmission::Skipped
    ));
    assert!(calls.lock().unwrap().is_empty());
    // Cancellation or mode-change during the refresh prevents the following send.
    assert!(matches!(
        resubmit!(true, true, || !calls.lock().unwrap().is_empty())
            .await
            .unwrap(),
        ReleasedResubmission::Skipped
    ));
    assert_eq!(*calls.lock().unwrap(), vec!["tip"]);
    assert!(requests.lock().unwrap().is_empty());
    let stats = crate::wallet::sync::resubmit_pending_transactions(
        path,
        &url,
        &mut client,
        999_999,
        &HashSet::new(),
        || false,
    )
    .await;
    assert_eq!(
        stats.attempted, 0,
        "the next sync must retain suppression after cancellation"
    );
    assert!(requests.lock().unwrap().is_empty());
    // Unlike the expiry boundary above, this transaction is still valid at
    // the new tip. A block arriving during enhancement could have mined it:
    // promotion must queue scanning without revealing it via SendTransaction.
    validated_tip = 999_998;
    conn.execute_batch(
        "UPDATE blocks SET height = 999998;
        DELETE FROM scan_queue;
        INSERT INTO scan_queue (block_range_start, block_range_end, priority)
        VALUES (800000, 999999, 10);",
    )
    .unwrap();
    assert!(wallet.suggest_scan_ranges().unwrap().is_empty());
    conn.execute(
        "DELETE FROM tx_retrieval_queue WHERE txid = ?1 AND query_type = 0",
        [&txid],
    )
    .unwrap();
    assert_eq!(
        get_resubmittable_txs(path, 999_999).unwrap().len(),
        1,
        "expiry alone must not suppress this candidate"
    );
    queue_status(&conn, &txid, 0);
    *tip_response.lock().unwrap() = Ok(BlockId {
        height: 999_999,
        hash: vec![0x11; 32],
    });
    calls.lock().unwrap().clear();

    // A failed promotion must not broadcast or leave partially updated scan work.
    conn.execute_batch(
        "CREATE TRIGGER reject_tip_promotion BEFORE INSERT ON scan_queue
        BEGIN SELECT RAISE(ABORT, 'injected promotion failure'); END;",
    )
    .unwrap();
    assert!(resubmit!(true, true, || false).await.is_err());
    assert_eq!(
        wallet.chain_height().unwrap(),
        Some(BlockHeight::from_u32(999_998))
    );
    assert!(wallet.suggest_scan_ranges().unwrap().is_empty());
    assert!(requests.lock().unwrap().is_empty());
    conn.execute("DROP TRIGGER reject_tip_promotion", [])
        .unwrap();
    calls.lock().unwrap().clear();

    assert!(matches!(
        resubmit!(true, true, || false).await.unwrap(),
        ReleasedResubmission::TipAdvanced(999_999)
    ));
    assert_eq!(
        wallet.chain_height().unwrap(),
        Some(BlockHeight::from_u32(999_999))
    );
    let pending = wallet.suggest_scan_ranges().unwrap();
    assert!(
        pending.iter().any(|range| range
            .block_range()
            .contains(&BlockHeight::from_u32(999_999))),
        "the newly observed block must be scheduled for scanning"
    );
    assert_eq!(*calls.lock().unwrap(), vec!["tip"]);
    assert!(requests.lock().unwrap().is_empty());

    // Model scan persistence discovering the transaction in that new block.
    // A following resubmit pass must see its restored mined state and send nothing.
    wallet
        .set_transaction_status(
            tx.txid(),
            zcash_client_backend::data_api::TransactionStatus::Mined(BlockHeight::from_u32(
                999_999,
            )),
        )
        .unwrap();
    conn.execute_batch(
        "UPDATE blocks SET height = 999999;
        DELETE FROM scan_queue;
        INSERT INTO scan_queue (block_range_start, block_range_end, priority)
        VALUES (800000, 1000000, 10);",
    )
    .unwrap();
    validated_tip = 999_999;
    calls.lock().unwrap().clear();
    match resubmit!(true, true, || false).await.unwrap() {
        ReleasedResubmission::Resubmitted => {}
        unexpected => panic!("unexpected post-scan outcome: {unexpected:?}"),
    }
    assert_eq!(*calls.lock().unwrap(), vec!["tip"]);
    assert!(requests.lock().unwrap().is_empty());
    server.abort();
}

#[test]
fn resubmit_guard_matches_pinned_backend_schema() {
    let file = NamedTempFile::new().unwrap();
    let path = file.path().to_str().unwrap();
    crate::wallet::keys::ensure_db_initialized(path, WalletNetwork::Test).unwrap();
    let mut conn = rusqlite::Connection::open(path).unwrap();
    // Prepare and execute the full predicate even though preflight would skip an empty DB.
    let mut stmt = conn
        .prepare(&resubmission_candidate_sql(
            "v.txid, v.raw, v.expiry_height",
        ))
        .unwrap();
    assert!(stmt.query([900_000]).unwrap().next().unwrap().is_none());
    drop(stmt);
    assert!(!resolve_recovered_nonmined_status(&mut conn, &fake_txid(0x81)).unwrap());

    let txid = fake_txid(0x81);
    populate_recovery_wallet(path, &txid, &[1]);
    let mut wallet = open_wallet_db(path, WalletNetwork::Test).unwrap();
    wallet
        .update_chain_tip(BlockHeight::from_u32(900_000))
        .unwrap();
    assert_resubmit_count(&file, 0);
    wallet
        .set_transaction_status(
            zcash_primitives::transaction::TxId::from_bytes(txid),
            zcash_client_backend::data_api::TransactionStatus::Mined(BlockHeight::from_u32(
                800_001,
            )),
        )
        .unwrap();
    assert_eq!(
        conn.query_row(
            "SELECT mined_height FROM transactions WHERE id_tx = 11",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        800_001
    );
    assert_resubmit_count(&file, 0);
    // Model the local state after rewind; durable positions and status intent survive.
    conn.execute(
        "UPDATE transactions SET mined_height = NULL WHERE id_tx = 11",
        [],
    )
    .unwrap();
    assert_resubmit_count(&file, 0);
    conn.execute(
        "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
        [txid],
    )
    .unwrap();
    assert!(resolve_recovered_nonmined_status(&mut conn, &txid).unwrap());
    assert_resubmit_count(&file, 1);
    assert_eq!(
        conn.query_row(
            "SELECT query_type FROM tx_retrieval_queue WHERE txid = ?1",
            [txid],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        1
    );
}
