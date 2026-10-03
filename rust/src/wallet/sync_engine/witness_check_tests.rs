use super::*;
use incrementalmerkletree::{Address, Hashable, Level, Retention};
use std::sync::mpsc;
use std::time::Duration;
use zcash_client_sqlite::wallet::commitment_tree;

const TIP: u32 = 110;
const NETWORK: WalletNetwork = WalletNetwork::Regtest;
type TreeError = ShardTreeError<commitment_tree::Error>;

struct Wallet {
    _dir: tempfile::TempDir,
    path: String,
    db: WalletDatabase,
}

fn test_wallet() -> Wallet {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    keys::init_db_and_create_account(&path, NETWORK, &seed, Some(100), "witnesses").unwrap();
    let mut db = open_wallet_db_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.update_chain_tip(BlockHeight::from_u32(TIP)).unwrap();
    let conn = rusqlite::Connection::open(&path).unwrap();
    conn.execute_batch(
        "UPDATE scan_queue SET priority = 10;
         INSERT INTO blocks (height, hash, time, sapling_tree,
             sapling_commitment_tree_size, orchard_commitment_tree_size,
             ironwood_commitment_tree_size)
         VALUES (110, zeroblob(32), 0, X'000000', 1, 1, 1);
         INSERT INTO transactions
             (id_tx, txid, mined_height, block, min_observed_height)
         VALUES (1, zeroblob(32), 110, 110, 110);
         INSERT INTO sapling_received_notes
             (transaction_id, output_index, account_id, diversifier, value,
              rcm, nf, is_change, commitment_tree_position, recipient_key_scope)
         SELECT 1, 0, id, zeroblob(11), 10000, zeroblob(32), zeroblob(32), 0, 0, 0
         FROM accounts;
         INSERT INTO orchard_received_notes
             (transaction_id, action_index, account_id, diversifier, value,
              rho, rseed, nf, is_change, commitment_tree_position,
              recipient_key_scope, note_version)
         SELECT 1, 0, id, zeroblob(11), 10000, zeroblob(32), zeroblob(32),
             zeroblob(32), 0, 0, 0, 2 FROM accounts;
         INSERT INTO ironwood_received_notes
             (transaction_id, action_index, account_id, diversifier, value,
              rho, rseed, nf, is_change, commitment_tree_position,
              recipient_key_scope, note_version)
         SELECT 1, 0, id, zeroblob(11), 10000, zeroblob(32), zeroblob(32),
             zeroblob(32), 0, 0, 0, 3 FROM accounts;",
    )
    .unwrap();
    let result: Result<(), TreeError> = db.with_sapling_tree_mut(|tree| {
        tree.append(sapling_crypto::Node::empty_leaf(), Retention::Marked)?;
        tree.checkpoint(BlockHeight::from_u32(TIP))?;
        Ok(())
    });
    result.unwrap();
    let result: Result<(), TreeError> = db.with_orchard_tree_mut(|tree| {
        tree.append(
            orchard::tree::MerkleHashOrchard::empty_leaf(),
            Retention::Marked,
        )?;
        tree.checkpoint(BlockHeight::from_u32(TIP))?;
        Ok(())
    });
    result.unwrap();
    let result: Result<Option<()>, TreeError> = db.with_ironwood_tree_mut(|tree| {
        tree.append(
            orchard::tree::MerkleHashOrchard::empty_leaf(),
            Retention::Marked,
        )?;
        tree.checkpoint(BlockHeight::from_u32(TIP))?;
        Ok(())
    });
    result.unwrap().expect("Ironwood is enabled on regtest");
    Wallet {
        _dir: dir,
        path,
        db,
    }
}

fn apply(
    wallet: &mut Wallet,
    inspection: WitnessInspection,
    passes: &mut u32,
) -> Result<WitnessRepairOutcome, SyncError> {
    apply_witness_inspection(
        &wallet.path,
        &mut wallet.db,
        u64::from(TIP),
        passes,
        inspection,
        &|| false,
    )
}

fn not_contained() -> SqliteClientError {
    SqliteClientError::CommitmentTree(ShardTreeError::Query(QueryError::NotContained(
        Address::from_parts(Level::new(0), 100),
    )))
}

fn mutate_without_changing_tip(wallet: &Wallet) {
    with_wallet_db_write_lock("test.witness_mutation", || {
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        conn.execute("UPDATE accounts SET name = 'changed'", [])
            .unwrap();
    });
}

#[test]
fn witness_inspection_is_read_only_and_matches_all_pool_witnesses() {
    let mut wallet = test_wallet();
    let expected = wallet.db.check_witnesses().unwrap();
    assert!(expected.is_empty());
    let inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    assert_eq!(inspection.result.as_ref().unwrap(), &expected);
    assert_eq!(
        witness_data_version(&inspection.connection).unwrap(),
        inspection.data_version
    );
    let error = inspection
        .connection
        .execute("UPDATE accounts SET name = 'forbidden'", [])
        .unwrap_err();
    assert_eq!(
        error.sqlite_error_code(),
        Some(rusqlite::ErrorCode::ReadOnly)
    );
    assert_eq!(
        apply(&mut wallet, inspection, &mut 0).unwrap(),
        WitnessRepairOutcome::NoRepairs
    );
    assert_eq!(
        read_witness_check_meta(&wallet.path)
            .unwrap()
            .last_clean_height,
        Some(u64::from(TIP))
    );
}

#[test]
fn witness_inspection_finds_real_missing_paths_in_each_shielded_pool() {
    for pool in ["sapling", "orchard", "ironwood"] {
        let mut wallet = test_wallet();
        let conn = rusqlite::Connection::open(&wallet.path).unwrap();
        // Advance the checkpoint without supplying the second leaf. A note at
        // position zero now lacks its sibling, which must schedule a rescan.
        conn.execute_batch(&format!(
            "UPDATE {pool}_tree_checkpoints SET position = 1;
             UPDATE blocks SET {pool}_commitment_tree_size = 2;"
        ))
        .unwrap();
        let expected = wallet.db.check_witnesses().unwrap();
        assert!(!expected.is_empty(), "{pool} witness was not checked");
        let inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
        assert_eq!(inspection.result.as_ref().unwrap(), &expected, "{pool}");
        let mut passes = 0;
        assert_eq!(
            apply(&mut wallet, inspection, &mut passes).unwrap(),
            WitnessRepairOutcome::Queued(1),
            "{pool}"
        );
        assert_eq!(passes, 1);
        assert_eq!(
            read_witness_check_meta(&wallet.path)
                .unwrap()
                .last_clean_height,
            None
        );
    }
}

#[test]
fn witness_inspection_can_finish_while_a_wallet_writer_owns_the_mutex() {
    let wallet = test_wallet();
    let path = wallet.path.clone();
    let (send, receive) = mpsc::channel();
    let mut worker = None;
    let inspection = with_wallet_db_write_lock("test.witness_writer", || {
        // Keep an actual uncommitted SQLite write open as well. WAL readers
        // should still inspect the previous committed state without waiting.
        let mut conn = rusqlite::Connection::open(&wallet.path).unwrap();
        let tx = conn.transaction().unwrap();
        tx.execute("UPDATE accounts SET name = 'uncommitted'", [])
            .unwrap();
        worker = Some(std::thread::spawn(move || {
            send.send(inspect_witnesses(&path, NETWORK)).unwrap();
        }));
        let result = receive.recv_timeout(Duration::from_secs(5));
        tx.rollback().unwrap();
        result
            .expect("witness inspection waited for the writer mutex or SQL writer")
            .unwrap()
    });
    worker.unwrap().join().unwrap();
    assert!(inspection.result.unwrap().is_empty());
}

#[test]
fn witness_inspection_rejects_stale_clean_result_without_marking_clean() {
    let mut wallet = test_wallet();
    let inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    mutate_without_changing_tip(&wallet);
    let mut passes = 0;
    assert_eq!(
        apply(&mut wallet, inspection, &mut passes).unwrap(),
        WitnessRepairOutcome::Retry
    );
    assert_eq!(passes, 0);
    assert_eq!(
        read_witness_check_meta(&wallet.path)
            .unwrap()
            .last_clean_height,
        None
    );
    let fresh = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    assert_eq!(
        apply(&mut wallet, fresh, &mut passes).unwrap(),
        WitnessRepairOutcome::NoRepairs
    );
}

#[test]
fn witness_inspection_rejects_stale_repairs_without_consuming_budget() {
    let mut wallet = test_wallet();
    let mut inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    inspection.result = Ok(vec![
        BlockHeight::from_u32(TIP - 1)..BlockHeight::from_u32(TIP + 1),
    ]);
    mutate_without_changing_tip(&wallet);
    let mut passes = 0;
    assert_eq!(
        apply(&mut wallet, inspection, &mut passes).unwrap(),
        WitnessRepairOutcome::Retry
    );
    assert_eq!(passes, 0);
    assert_eq!(
        pending_scan_blocks(&wallet.db.suggest_scan_ranges().unwrap()),
        0
    );
}

#[test]
fn witness_inspection_queues_valid_repairs_and_preserves_the_budget() {
    let mut wallet = test_wallet();
    let mut inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    inspection.result = Ok(vec![
        BlockHeight::from_u32(TIP - 1)..BlockHeight::from_u32(TIP + 1),
    ]);
    let mut passes = 0;
    assert_eq!(
        apply(&mut wallet, inspection, &mut passes).unwrap(),
        WitnessRepairOutcome::Queued(2)
    );
    assert_eq!(passes, 1);
    assert_eq!(
        read_witness_check_meta(&wallet.path)
            .unwrap()
            .last_clean_height,
        None
    );
    let mut inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    inspection.result = Ok(vec![
        BlockHeight::from_u32(TIP - 1)..BlockHeight::from_u32(TIP + 1),
    ]);
    passes = MAX_WITNESS_REPAIR_PASSES_PER_RUN;
    assert!(apply(&mut wallet, inspection, &mut passes)
        .unwrap_err()
        .to_string()
        .contains("budget exhausted"));
    assert_eq!(passes, MAX_WITNESS_REPAIR_PASSES_PER_RUN);
}

#[test]
fn witness_inspection_rechecks_unmined_position_cleanup_outside_the_lock() {
    let mut wallet = test_wallet();
    let conn = rusqlite::Connection::open(&wallet.path).unwrap();
    conn.execute(
        "UPDATE transactions SET mined_height = NULL, block = NULL",
        [],
    )
    .unwrap();
    conn.execute(
        "UPDATE sapling_received_notes SET commitment_tree_position = 100",
        [],
    )
    .unwrap();
    let inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    assert!(is_witness_position_beyond_tree(
        inspection.result.as_ref().unwrap_err()
    ));
    assert_eq!(
        apply(&mut wallet, inspection, &mut 0).unwrap(),
        WitnessRepairOutcome::Retry
    );
    assert_eq!(
        read_witness_check_meta(&wallet.path)
            .unwrap()
            .last_clean_height,
        None
    );
    let position: Option<u64> = conn
        .query_row(
            "SELECT commitment_tree_position FROM sapling_received_notes",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(position, None);
    let fresh = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    assert_eq!(
        apply(&mut wallet, fresh, &mut 0).unwrap(),
        WitnessRepairOutcome::NoRepairs
    );
}

#[test]
fn witness_inspection_does_not_apply_stale_errors_or_cancelled_results() {
    let mut wallet = test_wallet();
    let mut inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    inspection.result = Err(not_contained());
    mutate_without_changing_tip(&wallet);
    assert_eq!(
        apply(&mut wallet, inspection, &mut 0).unwrap(),
        WitnessRepairOutcome::Retry
    );
    let inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    let outcome = apply_witness_inspection(
        &wallet.path,
        &mut wallet.db,
        u64::from(TIP),
        &mut 0,
        inspection,
        &|| true,
    )
    .unwrap();
    assert_eq!(outcome, WitnessRepairOutcome::Cancelled);
    assert_eq!(
        read_witness_check_meta(&wallet.path)
            .unwrap()
            .last_clean_height,
        None
    );
    // A stable error on a mined note must still fail rather than clear it.
    let mut inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    inspection.result = Err(not_contained());
    assert!(matches!(
        apply(&mut wallet, inspection, &mut 0),
        Err(SyncError::Db(_))
    ));
}

#[test]
fn witness_inspection_is_not_invalidated_by_an_unrelated_wallet_write() {
    let mut wallet = test_wallet();
    let other = test_wallet();
    let inspection = inspect_witnesses(&wallet.path, NETWORK).unwrap();
    mutate_without_changing_tip(&other);
    assert_eq!(
        apply(&mut wallet, inspection, &mut 0).unwrap(),
        WitnessRepairOutcome::NoRepairs
    );
}

#[tokio::test(flavor = "current_thread")]
async fn witness_inspection_worker_completes_and_obeys_cancellation() {
    let mut wallet = test_wallet();
    let mut passes = 0;
    assert_eq!(
        queue_witness_repairs_if_needed(
            &wallet.path,
            &mut wallet.db,
            u64::from(TIP),
            &mut passes,
            true,
            &|| false
        )
        .await
        .unwrap(),
        WitnessRepairOutcome::NoRepairs
    );
    assert_eq!(
        queue_witness_repairs_if_needed(
            &wallet.path,
            &mut wallet.db,
            u64::from(TIP),
            &mut passes,
            true,
            &|| true
        )
        .await
        .unwrap(),
        WitnessRepairOutcome::Cancelled
    );
    assert_eq!(passes, 0);
}
