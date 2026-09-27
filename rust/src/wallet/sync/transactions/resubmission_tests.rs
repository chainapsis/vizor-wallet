use super::tests::{fake_raw, fake_txid, fresh_db, insert_row};
use super::*;
use tempfile::NamedTempFile;

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
        "INSERT INTO tx_retrieval_queue VALUES (?1, ?2)",
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

#[derive(Clone, Default)]
struct CountingLightwalletd(std::sync::Arc<std::sync::Mutex<Vec<Vec<u8>>>>);

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
        Box::pin(async move {
            assert!(req.uri().path().ends_with("/SendTransaction"));
            let body = req.into_body().collect().await.unwrap().to_bytes();
            let raw =
                zcash_client_backend::proto::service::RawTransaction::decode(&body[5..]).unwrap();
            requests.lock().unwrap().push(raw.data);
            // An empty protobuf is SendResponse { error_code: 0, error_message: "" }.
            let mut trailers = http::HeaderMap::new();
            trailers.insert("grpc-status", http::HeaderValue::from_static("0"));
            let frames = futures::stream::iter([
                Ok::<_, std::convert::Infallible>(hyper::body::Frame::data(
                    bytes::Bytes::from_static(&[0, 0, 0, 0, 0]),
                )),
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
    let mut conn = rusqlite::Connection::open(path).unwrap();
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
        add_recovery_evidence(&conn, &txid, "ironwood", Some(0));
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
    // One resolved transaction and one still protected: only the former goes on wire.
    assert!(resolve_recovered_nonmined_status(&mut conn, &txids[0]).unwrap());
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
async fn released_status_guard_is_resubmitted_without_a_post_batch_pass() {
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
    let mut conn = rusqlite::Connection::open(path).unwrap();
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
    insert_row(&db, &txid, Some(&raw), None, Some(1_000_000), -1);
    queue_status(&conn, &txid, 0);
    add_recovery_evidence(&conn, &txid, "orchard", Some(0));

    macro_rules! resubmit {
        ($released:expr, $allow:expr) => {
            crate::wallet::sync_engine::resubmit_released_transactions(
                $released,
                $allow,
                &[],
                path,
                &url,
                &mut client,
                900_000,
                || false,
            )
        };
    }
    // Still guarded: nothing released, nothing broadcast.
    assert!(resubmit!(false, true).await.unwrap().is_none());
    assert!(requests.lock().unwrap().is_empty());

    // Enhancement resolves the final status observation, releasing the guard.
    assert!(resolve_recovered_nonmined_status(&mut conn, &txid).unwrap());
    assert!(
        resubmit!(true, false).await.unwrap().is_none(),
        "a sync that disallows resubmission never broadcasts"
    );
    assert!(requests.lock().unwrap().is_empty());

    let stats = resubmit!(true, true).await.unwrap().expect("a pass ran");
    assert_eq!(stats.succeeded, 1);
    assert_eq!(*requests.lock().unwrap(), vec![raw]);
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
    let account: i64 = conn
        .query_row("SELECT id FROM accounts", [], |r| r.get(0))
        .unwrap();
    let funding = fake_txid(0x80);
    let txid = fake_txid(0x81);
    conn.execute(
        "INSERT INTO transactions (id_tx, txid, mined_height, min_observed_height, expiry_height)
        VALUES (10, ?1, 800000, 800000, 1000000)",
        [funding],
    )
    .unwrap();
    conn.execute("INSERT INTO transactions (id_tx, txid, raw, mined_height, min_observed_height, expiry_height)
        VALUES (11, ?1, X'01', NULL, 800001, 1000000)", [txid]).unwrap();
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
