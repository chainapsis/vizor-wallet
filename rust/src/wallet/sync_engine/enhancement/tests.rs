//! Transaction enhancement pass for the sync engine.
//!
//! `scan_cached_blocks` walks compact blocks and discovers transactions
//! that are relevant to the wallet, but a compact block only carries
//! the subset of transaction data needed for shielded-note discovery.
//! Things the wallet still has to learn afterwards:
//!
//!   - The full transaction bytes (for memo decryption, transparent
//!     input/output tracking, etc.).
//!   - Mined status for a transaction the wallet knows about but
//!     hasn't confirmed on-chain yet.
//!   - Transparent-address history in a given block range (used when
//!     the wallet imports or derives a new t-address and has to
//!     backfill its activity).
//!
//! Librustzcash exposes payload retrieval through `transaction_enhancement_work()`,
//! status through `transaction_status_work()`, and transparent-address history
//! through `transaction_data_requests()`. The parent session services these snapshots in
//! a fixed order and keeps their completion independent.

use zcash_client_backend::data_api::status::{TransactionStatusMode, TransactionStatusRead};
use zcash_client_backend::{
    data_api::{WalletRead, WalletWrite},
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};

use crate::wallet::network::WalletNetwork;

use super::super::{SyncError, WalletDatabase};

use super::EnhancementSession;

#[cfg(test)]
use {
    super::super::block_source::MemoryBlockSource,
    super::{
        auxiliary::fees::*,
        payload::{public::*, queue::*},
        status::persist_status_observation as store_transaction_observation,
    },
    crate::wallet::db::SYNC_DB_BUSY_TIMEOUT,
    std::collections::BTreeMap,
    tonic::{Code, Status},
    transparent::bundle::OutPoint,
    zcash_client_backend::proto::service::RawTransaction,
    zcash_primitives::transaction::{Transaction, TxId},
    zcash_protocol::{
        consensus::{BlockHeight, BranchId},
        value::Zatoshis,
    },
};

/// Whether the wallet's routed payload snapshot holds a public request for `txid`.
#[cfg(test)]
fn has_public_payload_work(db: &WalletDatabase, txid: TxId) -> bool {
    use zcash_client_backend::data_api::{
        enhance_pir::{EnhancePirRead, TransactionEnhancementWork},
        PublicTransactionEnhancementRequest,
    };
    db.transaction_enhancement_work()
        .unwrap()
        .contains(&TransactionEnhancementWork::Public(
            PublicTransactionEnhancementRequest::new(txid),
        ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::proto::compact_formats::{CompactBlock, CompactTx};

    #[test]
    fn queue_stored_transactions_is_batch_scoped_idempotent_and_non_destructive() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        rusqlite::vtab::array::load_module(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (txid BLOB PRIMARY KEY, raw BLOB, mined_height INTEGER);
             CREATE TABLE tx_retrieval_queue (
                txid BLOB, query_type INTEGER, dependent_transaction_id INTEGER,
                PRIMARY KEY(txid, query_type));
             INSERT INTO transactions VALUES (X'01', X'AB', NULL), (X'02', NULL, 10),
                (X'03', X'CD', 11), (X'05', X'EF', 10), (X'06', X'EF', 9);
             INSERT INTO tx_retrieval_queue VALUES (X'01', 0, 7), (X'03', 1, 9);",
        )
        .unwrap();
        // 01: stored raw, missing details; 02: newly scanned, no raw yet;
        // 03/06: outside this batch; 04: unrelated chain transaction;
        // 05: transparent-only transaction omitted from compact data.
        let blocks = MemoryBlockSource::new(vec![CompactBlock {
            height: 10,
            vtx: [1, 2, 4]
                .into_iter()
                .map(|id| CompactTx {
                    txid: vec![id],
                    ..Default::default()
                })
                .collect(),
            ..Default::default()
        }]);
        queue_stored_transactions(file.path().to_str().unwrap(), &blocks).unwrap();
        queue_stored_transactions(file.path().to_str().unwrap(), &blocks).unwrap();
        drop(conn);
        // Reopen without running enhancement: a cancelled scan retains intent.
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        let rows: Vec<(Vec<u8>, i64, Option<i64>)> = conn.prepare(
            "SELECT txid, query_type, dependent_transaction_id FROM tx_retrieval_queue ORDER BY txid, query_type"
        ).unwrap().query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
            .unwrap().collect::<Result<_, _>>().unwrap();
        assert_eq!(
            rows,
            vec![
                (vec![1], 0, Some(7)),
                (vec![1], 1, None),
                (vec![3], 1, Some(9)),
                (vec![5], 1, None)
            ]
        );
    }

    fn scanned_transaction_missing_fee_test_db(
        mined_height: BlockHeight,
        wallet_funded: bool,
    ) -> (tempfile::NamedTempFile, WalletDatabase, Transaction) {
        let (tx, raw) = transparent_fee_test_tx_and_bytes();
        let txid = tx.txid();
        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            db_path,
            WalletNetwork::Regtest,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        zcash_client_sqlite::wallet::init::init_wallet_db(&mut db, None).unwrap();
        db.update_chain_tip(mined_height + 10).unwrap();
        drop(db);

        let conn = rusqlite::Connection::open(db_path).unwrap();
        conn.execute(
            "INSERT INTO transactions
                (txid, mined_height, raw, fee, min_observed_height)
             VALUES (?1, ?2, ?3, NULL, ?2)",
            rusqlite::params![txid.as_ref(), u32::from(mined_height), raw],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO accounts
                (uuid, account_kind, uivk, birthday_height, has_spend_key)
             VALUES (randomblob(16), 1, 'test-uivk', 1, 0)",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO sapling_received_notes
                (transaction_id, output_index, account_id, diversifier, value,
                 rcm, is_change, commitment_tree_position, recipient_key_scope)
             SELECT id_tx, 0, 1, X'00', 1, X'00', 1, 1, 1
             FROM transactions WHERE txid = ?1",
            rusqlite::params![txid.as_ref()],
        )
        .unwrap();
        if wallet_funded {
            // The transaction spends a note the wallet received earlier.
            conn.execute(
                "INSERT INTO transactions (txid, mined_height, min_observed_height)
                 VALUES (?1, ?2, ?2)",
                rusqlite::params![[3u8; 32].as_slice(), u32::from(mined_height) - 1],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO sapling_received_notes
                    (transaction_id, output_index, account_id, diversifier, value,
                     rcm, is_change, commitment_tree_position, recipient_key_scope)
                 SELECT id_tx, 0, 1, X'00', 2, X'00', 0, 0, 0
                 FROM transactions WHERE txid = ?1",
                rusqlite::params![[3u8; 32].as_slice()],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO sapling_received_note_spends (sapling_received_note_id, transaction_id)
                 SELECT n.id, t.id_tx
                 FROM sapling_received_notes n, transactions t
                 WHERE n.transaction_id = (SELECT id_tx FROM transactions WHERE txid = ?1)
                 AND t.txid = ?2",
                rusqlite::params![[3u8; 32].as_slice(), txid.as_ref()],
            )
            .unwrap();
        }
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type)
             VALUES (?1, 0)",
            rusqlite::params![txid.as_ref()],
        )
        .unwrap();
        drop(conn);

        let mut db = crate::wallet::db::open_wallet_db_with_timeout(
            db_path,
            WalletNetwork::Regtest,
            SYNC_DB_BUSY_TIMEOUT,
        )
        .unwrap();
        db.set_status_mode(TransactionStatusMode::Public);
        db.set_enhancement_mode(
            zcash_client_backend::data_api::enhance_pir::EnhancementMode::Standard,
        );
        (file, db, tx)
    }

    #[test]
    fn observation_does_not_hydrate_payload_or_fees() {
        use crate::wallet::transaction_data::TransactionObservation;
        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET raw = NULL, mined_height = NULL",
            [],
        )
        .unwrap();
        store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool).unwrap();
        let row: (Option<Vec<u8>>, Option<i64>, Option<i64>) = conn
            .query_row(
                "SELECT raw, fee, confirmed_unmined_at_height FROM transactions WHERE txid = ?1",
                rusqlite::params![tx.txid().as_ref()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(row, (None, None, Some(110)));
    }

    #[test]
    fn status_observation_preserves_pending_payload_work() {
        use crate::wallet::transaction_data::TransactionObservation;
        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET raw = NULL, mined_height = NULL",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();
        for observation in [
            TransactionObservation::NotFound,
            TransactionObservation::Mempool,
            TransactionObservation::Forked,
            TransactionObservation::Mined(BlockHeight::from_u32(100)),
        ] {
            store_transaction_observation(&mut db, tx.txid(), observation).unwrap();
            assert!(has_public_payload_work(&db, tx.txid()));
        }
        // Payload completion does not affect status persistence.
        conn.execute("DELETE FROM tx_retrieval_queue WHERE query_type = 1", [])
            .unwrap();
        store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool).unwrap();
    }

    #[test]
    fn payload_not_found_and_status_complete_independently() {
        use crate::wallet::transaction_data::TransactionObservation;
        for status_first in [false, true] {
            let (file, mut db, tx) =
                scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
            let conn = rusqlite::Connection::open(file.path()).unwrap();
            conn.execute(
                "UPDATE transactions SET raw = NULL, mined_height = NULL",
                [],
            )
            .unwrap();
            conn.execute(
                "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
                rusqlite::params![tx.txid().as_ref()],
            )
            .unwrap();
            if status_first {
                store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool)
                    .unwrap();
            }
            db.notify_transaction_enhancement_not_found(tx.txid())
                .unwrap();
            assert!(!has_public_payload_work(&db, tx.txid()));
            let requests = db.transaction_status_work().unwrap();
            if !status_first {
                assert!(requests.iter().any(|work| work.txid() == tx.txid()));
                store_transaction_observation(&mut db, tx.txid(), TransactionObservation::Mempool)
                    .unwrap();
            }
        }
    }

    #[tokio::test]
    async fn payload_only_recovery_configures_the_wallet_mode() {
        use zcash_client_backend::data_api::enhance_pir::EnhancePirRead;

        let file = tempfile::NamedTempFile::new().unwrap();
        let db_path = file.path().to_str().unwrap();
        let network = WalletNetwork::Regtest;
        let mut db =
            crate::wallet::db::open_wallet_db_with_timeout(db_path, network, SYNC_DB_BUSY_TIMEOUT)
                .unwrap();
        zcash_client_sqlite::wallet::init::init_wallet_db(&mut db, None).unwrap();
        let channel = tonic::transport::Endpoint::from_static("http://127.0.0.1:1").connect_lazy();
        let mut client = CompactTxStreamerClient::new(channel);
        let _ = rustls::crypto::ring::default_provider().install_default();
        let mut enhancement = EnhancementSession::new(network, db_path);

        assert!(!enhancement
            .run_payload_recovery(&mut db, &mut client, None, &|| false)
            .await
            .unwrap());
        assert!(db.transaction_enhancement_work().unwrap().is_empty());
    }

    #[tokio::test]
    async fn checkpoint_observes_status_before_retryable_payload_failure() {
        use bytes::Bytes;
        use http_body_util::Full;
        use hyper::service::service_fn;
        use prost::Message;
        use std::sync::atomic::{AtomicUsize, Ordering};

        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET raw = NULL, mined_height = NULL",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let calls = std::sync::Arc::new(AtomicUsize::new(0));
        let calls_for_server = calls.clone();
        let (_, raw_bytes) = transparent_fee_test_tx_and_bytes();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let io = hyper_util::rt::TokioIo::new(stream);
            let service = service_fn(move |request: hyper::Request<hyper::body::Incoming>| {
                let calls = calls_for_server.clone();
                let raw_bytes = raw_bytes.clone();
                async move {
                    assert!(request.uri().path().ends_with("/GetTransaction"));
                    let response = if calls.fetch_add(1, Ordering::SeqCst) == 0 {
                        let raw = RawTransaction {
                            data: raw_bytes,
                            height: 0,
                        };
                        let message = raw.encode_to_vec();
                        let mut frame = vec![0];
                        frame.extend_from_slice(&(message.len() as u32).to_be_bytes());
                        frame.extend_from_slice(&message);
                        hyper::Response::builder()
                            .header("content-type", "application/grpc")
                            .header("grpc-status", "0")
                            .body(Full::new(Bytes::from(frame)))
                            .unwrap()
                    } else {
                        hyper::Response::builder()
                            .header("content-type", "application/grpc")
                            .header("grpc-status", "14")
                            .header("grpc-message", "temporary failure")
                            .body(Full::new(Bytes::new()))
                            .unwrap()
                    };
                    Ok::<_, std::convert::Infallible>(response)
                }
            });
            hyper::server::conn::http2::Builder::new(hyper_util::rt::TokioExecutor::new())
                .serve_connection(io, service)
                .await
                .unwrap();
        });
        let channel = tonic::transport::Endpoint::from_shared(format!("http://{address}"))
            .unwrap()
            .connect()
            .await
            .unwrap();
        let mut client = CompactTxStreamerClient::new(channel);
        let db_path = file.path().to_str().unwrap();
        let should_exit = || false;
        let _ = rustls::crypto::ring::default_provider().install_default();
        let mut enhancement = EnhancementSession::new(WalletNetwork::Regtest, db_path);
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            enhancement.run_checkpoint(&mut db, &mut client, None, &should_exit),
        )
        .await
        .expect("enhancement checkpoint timed out");
        server.abort();

        assert!(
            matches!(result, Err(SyncError::Network(message)) if message.contains("temporary failure"))
        );
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert!(has_public_payload_work(&db, tx.txid()));
        let observed: Option<i64> = conn
            .query_row(
                "SELECT confirmed_unmined_at_height FROM transactions WHERE txid = ?1",
                rusqlite::params![tx.txid().as_ref()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(observed, Some(110));
    }

    fn transparent_fee_test_tx_and_bytes() -> (Transaction, Vec<u8>) {
        let tx_bytes = hex::decode(
            "0400008085202f8901aee37187e843da597683c26c01457f5fd3b1a038996ef74dc8d60d483aaf395a000000006b483045022100874c70db77ea9e93f75cc83a9e141e17c8eb97588e29fe4e307631fdde4f162a02203493df62d648cd86a1189eaf9bcafc652bc14c5df02519d9e45e25b32aaffb5b012102106a2dcaaac2ae3b24358a03f4264e05db420c5b090399bc23885fa02fef7716ffffffff02764e1900000000001976a914fb451987556f7a19b726966ee6cff917e0bb3bfb88ac560ca400000000001976a9141634f5ff0b8f6603a17570436d6c12a91f4b1fed88ac00000000000000000000000000000000000000",
        )
        .unwrap();
        let tx = Transaction::read(&tx_bytes[..], BranchId::Sapling).unwrap();
        (tx, tx_bytes)
    }

    fn transparent_fee_test_tx() -> Transaction {
        transparent_fee_test_tx_and_bytes().0
    }

    fn no_transparent_inputs_test_tx() -> Transaction {
        use zcash_primitives::transaction::{Authorized, TransactionData, TxVersion};

        TransactionData::<Authorized>::from_parts(
            TxVersion::V5,
            BranchId::Nu5,
            0,
            BlockHeight::from_u32(1),
            None,
            None,
            None,
            None,
        )
        .freeze()
        .unwrap()
    }

    fn transparent_fee_test_db(tx: &Transaction, total_spent: i64) -> tempfile::NamedTempFile {
        transparent_fee_test_db_with_optional_wallet_row(tx, Some(total_spent))
    }

    fn transparent_fee_test_db_with_optional_wallet_row(
        tx: &Transaction,
        total_spent: Option<i64>,
    ) -> tempfile::NamedTempFile {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY,
                 txid BLOB NOT NULL UNIQUE,
                 raw BLOB,
                 fee INTEGER
             );
             CREATE TABLE v_transactions (
                 txid BLOB NOT NULL,
                 total_spent INTEGER NOT NULL
             );
             CREATE TABLE transparent_received_outputs (
                 transaction_id INTEGER NOT NULL,
                 output_index INTEGER NOT NULL,
                 value_zat INTEGER NOT NULL
             );",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, fee) VALUES (?1, NULL)",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();
        if let Some(total_spent) = total_spent {
            conn.execute(
                "INSERT INTO v_transactions (txid, total_spent) VALUES (?1, ?2)",
                rusqlite::params![tx.txid().as_ref(), total_spent],
            )
            .unwrap();
        }
        file
    }

    #[test]
    fn get_transaction_not_found_completes_enhancement_only() {
        let status = Status::new(Code::NotFound, "txid not recognized");

        assert_eq!(
            classify_get_transaction_error(&status),
            GetTransactionErrorAction::CompleteEnhancementNotFound,
        );
    }

    #[test]
    fn get_transaction_transient_errors_retry_as_network() {
        for code in [
            Code::Unavailable,
            Code::DeadlineExceeded,
            Code::Cancelled,
            Code::Unknown,
            Code::Internal,
        ] {
            let status = Status::new(code, "temporary failure");
            assert_eq!(
                classify_get_transaction_error(&status),
                GetTransactionErrorAction::RetryAsNetwork,
            );
        }
    }

    #[test]
    fn scanned_transaction_missing_fee_is_selected_when_status_request_is_dormant() {
        let mined_height = BlockHeight::from_u32(500);
        let (file, db, tx) = scanned_transaction_missing_fee_test_db(mined_height, true);
        let txid = tx.txid();

        assert!(!db
            .transaction_status_work()
            .unwrap()
            .iter()
            .any(|work| work.txid() == txid));
        assert_eq!(
            stored_transaction_ids_missing_fee(file.path().to_str().unwrap()).unwrap(),
            vec![txid]
        );
        assert_eq!(db.get_transaction(txid).unwrap().unwrap().txid(), txid);
    }

    #[test]
    fn coinbase_transaction_is_not_selected_for_fee_backfill() {
        let mined_height = BlockHeight::from_u32(500);
        let (file, _db, tx) = scanned_transaction_missing_fee_test_db(mined_height, true);
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute(
            "UPDATE transactions SET tx_index = 0 WHERE txid = ?1",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();

        assert!(
            stored_transaction_ids_missing_fee(file.path().to_str().unwrap())
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn fee_without_transparent_inputs_is_persisted() {
        // Fully shielded transactions follow this path: no transparent
        // prevouts are required to compute their fee from public value
        // balances. This minimal transaction isolates that property.
        let tx = no_transparent_inputs_test_tx();
        let db = transparent_fee_test_db(&tx, 1);
        let fee = fee_from_prevout_values(&tx, &BTreeMap::new())
            .unwrap()
            .unwrap();

        assert!(should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
        persist_fee_if_missing(db.path().to_str().unwrap(), &tx, fee).unwrap();
        assert!(!should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());

        let conn = rusqlite::Connection::open(db.path()).unwrap();
        let stored_fee: i64 = conn
            .query_row(
                "SELECT fee FROM transactions WHERE txid = ?1",
                rusqlite::params![tx.txid().as_ref()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(stored_fee, 0);
    }

    #[test]
    fn transparent_fee_uses_exact_prevout_output_index() {
        let tx = transparent_fee_test_tx();
        let prevout = tx.transparent_bundle().unwrap().vin[0].prevout().clone();
        let input_value = Zatoshis::from_nonnegative_i64(12_449_548).unwrap();

        let mut wrong_prevout_values = BTreeMap::new();
        wrong_prevout_values.insert(OutPoint::new(*prevout.hash(), prevout.n() + 1), input_value);
        assert_eq!(
            fee_from_prevout_values(&tx, &wrong_prevout_values).unwrap(),
            None
        );

        let mut prevout_values = BTreeMap::new();
        prevout_values.insert(prevout, input_value);
        assert_eq!(
            fee_from_prevout_values(&tx, &prevout_values)
                .unwrap()
                .map(u64::from),
            Some(40_000),
        );
    }

    #[test]
    fn transparent_fee_backfill_requires_wallet_relevance() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db_with_optional_wallet_row(&tx, None);

        assert!(!should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn received_transaction_fee_is_not_wanted() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 0);

        assert!(!should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn wallet_funded_transaction_fee_is_wanted() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 12_449_548);

        assert!(should_fill_missing_fee(db.path().to_str().unwrap(), &tx).unwrap());
    }

    #[test]
    fn raw_height_out_of_u32_range_is_parse_error() {
        assert!(matches!(
            mined_height_from_raw_height(u32::MAX as u64 + 1),
            Err(SyncError::Parse(_)),
        ));
    }

    #[test]
    fn enhancement_payload_requires_matching_identity_and_valid_height() {
        let (tx, data) = transparent_fee_test_tx_and_bytes();
        let raw = RawTransaction { data, height: 100 };
        assert!(decode_enhancement_payload(&raw, tx.txid()).is_ok());
        assert!(matches!(
            decode_enhancement_payload(&raw, TxId::from_bytes([0; 32])),
            Err(SyncError::Parse(_))
        ));
        assert!(matches!(
            decode_enhancement_payload(
                &RawTransaction {
                    height: u32::MAX as u64 + 1,
                    ..raw
                },
                tx.txid()
            ),
            Err(SyncError::Parse(_))
        ));
    }
    struct FakeStatusSource {
        opens: std::sync::Arc<std::sync::atomic::AtomicUsize>,
        requests: std::sync::Arc<std::sync::Mutex<Vec<zakura_transaction_status::StatusRequest>>>,
        response: Result<
            zakura_transaction_status::StatusObservation,
            zakura_transaction_status::StatusError,
        >,
    }
    impl zakura_transaction_status::StatusSource for FakeStatusSource {
        type Session = Self;
        async fn open(self) -> Result<Self, zakura_transaction_status::StatusError> {
            self.opens.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Ok(self)
        }
    }
    impl zakura_transaction_status::StatusSession for FakeStatusSource {
        async fn observe(
            &mut self,
            request: zakura_transaction_status::StatusRequest,
        ) -> Result<
            zakura_transaction_status::StatusObservation,
            zakura_transaction_status::StatusError,
        > {
            self.requests.lock().unwrap().push(request);
            self.response
        }
    }
    fn status_source(
        response: Result<
            zakura_transaction_status::StatusObservation,
            zakura_transaction_status::StatusError,
        >,
    ) -> FakeStatusSource {
        FakeStatusSource {
            opens: Default::default(),
            requests: Default::default(),
            response,
        }
    }

    #[tokio::test]
    async fn routed_recovery_status_retains_guard_until_verified_tip() {
        use crate::wallet::sync_engine::{
            complete_verified_recovery_statuses, RefreshedTipRelation,
        };
        use zakura_transaction_status::StatusObservation;
        use zcash_client_backend::data_api::status::{
            PublicTransactionStatusRequest, TransactionStatusWork,
        };
        for private in [false, true] {
            for observation in [
                StatusObservation::NotFound,
                StatusObservation::Mempool,
                StatusObservation::Forked,
            ] {
                let file = tempfile::NamedTempFile::new().unwrap();
                let path = file.path().to_str().unwrap();
                let txid = TxId::from_bytes([0x61; 32]);
                crate::wallet::sync::populate_recovery_wallet(path, txid.as_ref(), &[1, 2, 3]);
                let mut db =
                    crate::wallet::sync::open_wallet_db(path, WalletNetwork::Test).unwrap();
                db.update_chain_tip(BlockHeight::from_u32(900_000)).unwrap();
                let conn = rusqlite::Connection::open(path).unwrap();
                conn.execute("INSERT INTO blocks (height, hash, time, sapling_tree) VALUES (900000, ?1, 0, X'000000')", [[7u8; 32].as_slice()]).unwrap();
                db.set_status_mode(if private {
                    TransactionStatusMode::Private
                } else {
                    TransactionStatusMode::Public
                });
                let work = if private {
                    db.transaction_status_work_for(txid).unwrap()
                } else {
                    TransactionStatusWork::Public(PublicTransactionStatusRequest::new(txid))
                };
                assert_eq!(matches!(work, TransactionStatusWork::Private(_)), private);
                let mut reader = super::super::status::RoutedStatusReader::new(
                    status_source(Ok(observation)),
                    status_source(Ok(observation)),
                );
                let mut ready = std::collections::HashSet::new();
                if private && matches!(observation, StatusObservation::NotFound) {
                    conn.execute("DELETE FROM blocks WHERE height = 900000", [])
                        .unwrap();
                    super::super::status::run_requests(
                        &mut reader,
                        &mut db,
                        &[work],
                        &mut Default::default(),
                        &mut false,
                        path,
                        &mut ready,
                        &|| false,
                    )
                    .await
                    .unwrap();
                    assert!(
                        ready.is_empty(),
                        "private absence without a decision hash is inconclusive"
                    );
                    assert!(
                        crate::wallet::sync::has_recovered_status_work(&conn, txid.as_ref())
                            .unwrap()
                    );
                    conn.execute("INSERT INTO blocks (height, hash, time, sapling_tree) VALUES (900000, ?1, 0, X'000000')", [[7u8; 32].as_slice()]).unwrap();
                }
                super::super::status::run_requests(
                    &mut reader,
                    &mut db,
                    &[work],
                    &mut Default::default(),
                    &mut false,
                    path,
                    &mut ready,
                    &|| false,
                )
                .await
                .unwrap();
                assert_eq!(
                    ready,
                    std::collections::HashSet::from([txid.as_ref().to_vec()])
                );
                assert!(
                    crate::wallet::sync::has_recovered_status_work(&conn, txid.as_ref()).unwrap()
                );
                complete_verified_recovery_statuses(
                    path,
                    &ready,
                    RefreshedTipRelation::UnchangedUnverified,
                )
                .unwrap();
                assert!(
                    crate::wallet::sync::has_recovered_status_work(&conn, txid.as_ref()).unwrap()
                );
                complete_verified_recovery_statuses(path, &ready, RefreshedTipRelation::Unchanged)
                    .unwrap();
                assert!(
                    !crate::wallet::sync::has_recovered_status_work(&conn, txid.as_ref()).unwrap()
                );
                let payload: bool = conn.query_row("SELECT EXISTS (SELECT 1 FROM tx_retrieval_queue WHERE txid = ?1 AND query_type = 1)", [txid.as_ref()], |row| row.get(0)).unwrap();
                assert!(payload);
            }
        }
    }

    #[tokio::test]
    async fn incomplete_private_status_trips_feedback_gate_without_public_fallback() {
        use zakura_transaction_status::{StatusError, StatusObservation};
        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
        rusqlite::Connection::open(file.path())
            .unwrap()
            .execute(
                "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
                rusqlite::params![tx.txid().as_ref()],
            )
            .unwrap();
        db.set_status_mode(TransactionStatusMode::Private);
        let work = vec![db.transaction_status_work_for(tx.txid()).unwrap()];
        let public = status_source(Ok(StatusObservation::NotFound));
        let public_opens = public.opens.clone();
        let private = status_source(Err(StatusError::CoverageIncomplete));
        let requests = private.requests.clone();
        let mut reader = super::super::status::RoutedStatusReader::new(public, private);
        let mut attempted = std::collections::HashSet::new();
        assert!(matches!(
            super::super::status::run_requests(
                &mut reader,
                &mut db,
                &work,
                &mut attempted,
                &mut false,
                file.path().to_str().unwrap(),
                &mut std::collections::HashSet::new(),
                &|| false
            )
            .await,
            Err(SyncError::PrivateStatusCoverageIncomplete)
        ));
        assert_eq!(public_opens.load(std::sync::atomic::Ordering::SeqCst), 0);
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].coverage.earliest_possible_inclusion, None);
        assert_eq!(requests[0].coverage.required_through, Some(110));
        assert!(has_public_payload_work(&db, tx.txid()));
        // An inconclusive lookup cannot replace a previously mined observation with absence.
        assert_eq!(
            db.get_tx_height(tx.txid()).unwrap(),
            Some(BlockHeight::from_u32(100))
        );
    }

    /// A durable private status obligation with no payload work must still
    /// count toward a recovery-only restart, or a deferred Status PIR failure
    /// is never retried until a new block or a manual action.
    #[test]
    fn recovery_status_counts_private_status_obligations() {
        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute("UPDATE transactions SET mined_height = NULL", [])
            .unwrap();
        conn.execute(
            "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 0)
             ON CONFLICT (txid, query_type) DO NOTHING",
            rusqlite::params![tx.txid().as_ref()],
        )
        .unwrap();

        db.set_status_mode(TransactionStatusMode::Private);
        let status = super::super::super::recovery_status_for(&db, String::new()).unwrap();
        assert_eq!(status.status, 1, "the private obligation is recovery work");

        // A public status failure fails the sync instead of being deferred, so
        // public status work never needs a recovery-only restart.
        db.set_status_mode(TransactionStatusMode::Public);
        let status = super::super::super::recovery_status_for(&db, String::new()).unwrap();
        assert_eq!(status.status, 0);
    }

    /// Migration creation evidence records an earliest-inclusion bound only.
    /// It queues no status or payload work, so retiring an unbroadcast run
    /// leaves nothing for a later sync to query.
    #[test]
    fn migration_creation_evidence_alone_queues_no_work() {
        use zcash_client_backend::data_api::enhance_pir::EnhancePirRead;
        use zcash_client_backend::data_api::status::TransactionStatusWrite;
        let (_file, mut db, _tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
        let txid = TxId::from_bytes([0x5a; 32]);
        db.record_transaction_created(txid, BlockHeight::from_u32(90))
            .unwrap();
        for mode in [
            TransactionStatusMode::Private,
            TransactionStatusMode::Public,
        ] {
            db.set_status_mode(mode);
            assert!(!db
                .transaction_status_work()
                .unwrap()
                .iter()
                .any(|work| work.txid() == txid));
            use zcash_client_backend::data_api::enhance_pir::{
                EnhancePirWork, TransactionEnhancementWork,
            };
            assert!(!db
                .transaction_enhancement_work()
                .unwrap()
                .iter()
                .any(|work| match work {
                    TransactionEnhancementWork::Public(request) => request.txid() == txid,
                    TransactionEnhancementWork::Private(EnhancePirWork::Query(request)) => {
                        request.request_id().txid() == txid
                    }
                    TransactionEnhancementWork::Private(_) => false,
                }));
            let status = super::super::super::recovery_status_for(&db, String::new()).unwrap();
            assert_eq!(
                (status.status, status.queries, status.rediscovery),
                (0, 0, 0)
            );
        }
    }

    fn private_status_work_db() -> (tempfile::NamedTempFile, WalletDatabase, TxId) {
        let (file, mut db, tx) =
            scanned_transaction_missing_fee_test_db(BlockHeight::from_u32(100), false);
        rusqlite::Connection::open(file.path())
            .unwrap()
            .execute(
                "INSERT INTO tx_retrieval_queue (txid, query_type) VALUES (?1, 1)",
                rusqlite::params![tx.txid().as_ref()],
            )
            .unwrap();
        db.set_status_mode(TransactionStatusMode::Private);
        (file, db, tx.txid())
    }

    #[tokio::test]
    async fn private_status_errors_are_deferred_for_the_session_without_failing_sync() {
        use zakura_transaction_status::{StatusError, StatusObservation};
        for error in [
            StatusError::Unsupported,
            StatusError::Unavailable,
            StatusError::Stale,
            StatusError::Timeout,
            StatusError::Malformed,
            StatusError::Transport { code: 14 },
        ] {
            let (_file, mut db, txid) = private_status_work_db();
            let work = vec![db.transaction_status_work_for(txid).unwrap()];
            let public = status_source(Ok(StatusObservation::NotFound));
            let public_opens = public.opens.clone();
            let private = status_source(Err(error));
            let requests = private.requests.clone();
            let mut reader = super::super::status::RoutedStatusReader::new(public, private);
            let mut private_failed = false;

            assert!(
                super::super::status::run_requests(
                    &mut reader,
                    &mut db,
                    &work,
                    &mut std::collections::HashSet::new(),
                    &mut private_failed,
                    _file.path().to_str().unwrap(),
                    &mut std::collections::HashSet::new(),
                    &|| false,
                )
                .await
                .unwrap(),
                "{error:?} must not fail the sync"
            );
            assert!(private_failed, "{error:?} must latch private status off");

            // A later checkpoint in the same session starts with a fresh attempted
            // set but must not query the failed private service again.
            assert!(!super::super::status::run_requests(
                &mut reader,
                &mut db,
                &work,
                &mut std::collections::HashSet::new(),
                &mut private_failed,
                _file.path().to_str().unwrap(),
                &mut std::collections::HashSet::new(),
                &|| false,
            )
            .await
            .unwrap());

            assert_eq!(requests.lock().unwrap().len(), 1, "{error:?}");
            assert_eq!(public_opens.load(std::sync::atomic::Ordering::SeqCst), 0);
            assert_eq!(
                db.transaction_status_work_for(txid).unwrap(),
                work[0],
                "{error:?} must leave the status obligation pending"
            );
            assert_eq!(
                db.get_tx_height(txid).unwrap(),
                Some(BlockHeight::from_u32(100))
            );
        }
    }

    #[tokio::test]
    async fn local_storage_status_errors_fail_sync_without_deferring() {
        use zakura_transaction_status::{StatusError, StatusObservation};
        let (_file, mut db, txid) = private_status_work_db();
        let work = vec![db.transaction_status_work_for(txid).unwrap()];
        let public = status_source(Ok(StatusObservation::NotFound));
        let public_opens = public.opens.clone();
        let mut reader = super::super::status::RoutedStatusReader::new(
            public,
            status_source(Err(StatusError::LocalStorage)),
        );
        let mut private_failed = false;

        let result = super::super::status::run_requests(
            &mut reader,
            &mut db,
            &work,
            &mut std::collections::HashSet::new(),
            &mut private_failed,
            _file.path().to_str().unwrap(),
            &mut std::collections::HashSet::new(),
            &|| false,
        )
        .await;

        assert!(
            matches!(result, Err(SyncError::Db(_))),
            "a local read failure must fail the sync, got {result:?}"
        );
        assert!(!private_failed, "a local failure is not a service outage");
        assert_eq!(public_opens.load(std::sync::atomic::Ordering::SeqCst), 0);
        assert_eq!(
            db.transaction_status_work_for(txid).unwrap(),
            work[0],
            "the status obligation stays pending"
        );
    }

    #[tokio::test]
    async fn public_status_errors_still_fail_sync() {
        use zakura_transaction_status::{StatusError, StatusObservation};
        use zcash_client_backend::data_api::status::{
            PublicTransactionStatusRequest, TransactionStatusWork,
        };
        let (_file, mut db, txid) = private_status_work_db();
        let work = vec![TransactionStatusWork::Public(
            PublicTransactionStatusRequest::new(txid),
        )];
        let mut reader = super::super::status::RoutedStatusReader::new(
            status_source(Err(StatusError::Unavailable)),
            status_source(Ok(StatusObservation::NotFound)),
        );
        let mut private_failed = false;
        assert!(matches!(
            super::super::status::run_requests(
                &mut reader,
                &mut db,
                &work,
                &mut std::collections::HashSet::new(),
                &mut private_failed,
                _file.path().to_str().unwrap(),
                &mut std::collections::HashSet::new(),
                &|| false,
            )
            .await,
            Err(SyncError::Network(_))
        ));
        assert!(!private_failed);
    }

    #[tokio::test]
    async fn status_work_variant_selects_source_and_preserves_coverage_context() {
        use zakura_transaction_status::StatusObservation;
        use zcash_client_backend::data_api::status::{
            PrivateTransactionStatusRequest, PublicTransactionStatusRequest, TransactionStatusWork,
        };
        let public = status_source(Ok(StatusObservation::Mempool));
        let private = status_source(Ok(StatusObservation::Mined(BlockHeight::from_u32(100))));
        let public_requests = public.requests.clone();
        let private_requests = private.requests.clone();
        let mut reader = super::super::status::RoutedStatusReader::new(public, private);
        let txid = TxId::from_bytes([42; 32]);
        let work = TransactionStatusWork::Private(PrivateTransactionStatusRequest::new(
            txid,
            Some(BlockHeight::from_u32(80)),
        ));
        assert_eq!(
            reader.observe(work, Some(110)).await,
            Ok(StatusObservation::Mined(BlockHeight::from_u32(100)))
        );
        assert!(public_requests.lock().unwrap().is_empty());
        let request = private_requests.lock().unwrap()[0];
        assert_eq!(request.coverage.earliest_possible_inclusion, Some(80));
        assert_eq!(request.coverage.required_through, Some(110));
        assert_eq!(
            reader
                .observe(
                    TransactionStatusWork::Public(PublicTransactionStatusRequest::new(txid)),
                    None
                )
                .await,
            Ok(StatusObservation::Mempool)
        );
        assert_eq!(public_requests.lock().unwrap().len(), 1);
        assert_eq!(private_requests.lock().unwrap().len(), 1);
    }

    #[test]
    fn received_transaction_is_not_selected_for_fee_backfill() {
        let mined_height = BlockHeight::from_u32(500);
        let (file, _db, _tx) = scanned_transaction_missing_fee_test_db(mined_height, false);

        assert!(
            stored_transaction_ids_missing_fee(file.path().to_str().unwrap())
                .unwrap()
                .is_empty()
        );
    }

    fn stored_fee(db: &tempfile::NamedTempFile, tx: &Transaction) -> Option<i64> {
        rusqlite::Connection::open(db.path())
            .unwrap()
            .query_row(
                "SELECT fee FROM transactions WHERE txid = ?1",
                rusqlite::params![tx.txid().as_ref()],
                |row| row.get(0),
            )
            .unwrap()
    }

    fn transparent_parent_raw(value: u64) -> Vec<u8> {
        // A v1 transaction whose only output is the requested prevout value.
        let mut parent = 1u32.to_le_bytes().to_vec();
        parent.push(1);
        parent.extend_from_slice(&[9; 32]);
        parent.extend_from_slice(&0u32.to_le_bytes());
        parent.push(0);
        parent.extend_from_slice(&u32::MAX.to_le_bytes());
        parent.push(1);
        parent.extend_from_slice(&value.to_le_bytes());
        parent.push(0);
        parent.extend_from_slice(&0u32.to_le_bytes());
        parent
    }

    #[test]
    fn transparent_fee_comes_from_wallet_output_already_known() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 12_449_548);
        let prevout = tx.transparent_bundle().unwrap().vin[0].prevout().clone();
        let conn = rusqlite::Connection::open(db.path()).unwrap();
        conn.execute(
            "INSERT INTO transactions (txid, raw, fee) VALUES (?1, NULL, NULL)",
            rusqlite::params![prevout.hash().as_slice()],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO transparent_received_outputs (transaction_id, output_index, value_zat)
             VALUES (?1, ?2, ?3)",
            rusqlite::params![conn.last_insert_rowid(), prevout.n(), 12_449_548u64],
        )
        .unwrap();
        drop(conn);

        fill_fee_from_local(db.path().to_str().unwrap(), &tx).unwrap();
        assert_eq!(stored_fee(&db, &tx), Some(40_000));
    }

    #[test]
    fn transparent_fee_comes_from_parent_raw_already_stored() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 12_449_548);
        let prevout = tx.transparent_bundle().unwrap().vin[0].prevout().clone();
        assert_eq!(prevout.n(), 0);
        rusqlite::Connection::open(db.path())
            .unwrap()
            .execute(
                "INSERT INTO transactions (txid, raw, fee) VALUES (?1, ?2, NULL)",
                rusqlite::params![
                    prevout.hash().as_slice(),
                    transparent_parent_raw(12_449_548)
                ],
            )
            .unwrap();

        fill_fee_from_local(db.path().to_str().unwrap(), &tx).unwrap();
        assert_eq!(stored_fee(&db, &tx), Some(40_000));
    }

    #[test]
    fn missing_parent_leaves_transparent_fee_unknown() {
        let tx = transparent_fee_test_tx();
        let db = transparent_fee_test_db(&tx, 12_449_548);

        fill_fee_from_local(db.path().to_str().unwrap(), &tx).unwrap();
        assert_eq!(stored_fee(&db, &tx), None);
    }
}
