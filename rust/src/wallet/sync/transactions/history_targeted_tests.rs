//! Targeted Gift Card/receipt reads through the production API. Read probes are
//! thread-local and compiled only in tests; fixtures use the library's real DB.
use super::*;
use std::cell::RefCell;

#[derive(Debug, Default)]
struct Reads {
    summaries: usize,
    details: Vec<Vec<Vec<u8>>>,
    outputs: Vec<Vec<Vec<u8>>>,
}

thread_local! {
    static READS: RefCell<Option<Reads>> = const { RefCell::new(None) };
    static BEFORE_DETAILS: RefCell<Option<Box<dyn FnOnce()>>> = const { RefCell::new(None) };
}

pub(in super::super) fn record_summary() {
    READS.with_borrow_mut(|reads| {
        if let Some(reads) = reads {
            reads.summaries += 1;
        }
    });
}

pub(in super::super) fn record_details(txids: &[TxId]) {
    READS.with_borrow_mut(|reads| {
        if let Some(reads) = reads {
            reads
                .details
                .push(txids.iter().map(|id| id.as_ref().to_vec()).collect());
        }
    });
    let action = BEFORE_DETAILS.with_borrow_mut(Option::take);
    if let Some(action) = action {
        action();
    }
}

pub(in super::super) fn record_outputs(txids: &[Value]) {
    READS.with_borrow_mut(|reads| {
        if let Some(reads) = reads {
            reads.outputs.push(
                txids
                    .iter()
                    .map(|value| match value {
                        Value::Blob(bytes) => bytes.clone(),
                        _ => panic!("output query must use transaction ID bytes"),
                    })
                    .collect(),
            );
        }
    });
}

fn observe<T>(action: impl FnOnce() -> T) -> (T, Reads) {
    struct Reset;
    impl Drop for Reset {
        fn drop(&mut self) {
            READS.with_borrow_mut(|reads| *reads = None);
            BEFORE_DETAILS.with_borrow_mut(|action| *action = None);
        }
    }
    let _reset = Reset;
    READS.with_borrow_mut(|reads| *reads = Some(Reads::default()));
    let result = action();
    (result, READS.with_borrow_mut(|reads| reads.take().unwrap()))
}

fn targeted(wallet: &Wallet, account: AccountUuid, txids: &[Vec<u8>]) -> Vec<TransactionInfo> {
    get_transaction_rows_for_txids(
        &wallet.path,
        NETWORK,
        &account.expose_uuid().to_string(),
        &txids.iter().map(hex::encode).collect::<Vec<_>>(),
    )
    .unwrap()
}

/// All rows have local construction evidence. Group 0 contains >20 peers;
/// other creation times and expiry heights must not expand its dependencies.
fn add_created_history(wallet: &Wallet, count: usize) -> Vec<Vec<u8>> {
    let mut conn = Connection::open(&wallet.path).unwrap();
    let tx = conn.transaction().unwrap();
    let account = account_id(&tx, wallet.sender);
    let mut ids = Vec::new();
    for n in 0..count {
        let mut id = [0x77; 32];
        id[..8].copy_from_slice(&(n as u64).to_le_bytes());
        let group = n / 25;
        // Adjacent groups share a creation time but have different expiries.
        let created = format!("fixture-created-{}", group / 2);
        let expiry = 220 + group % 2;
        tx.execute(
            "INSERT INTO transactions (txid, mined_height, min_observed_height,
                 tx_index, created, expiry_height)
             VALUES (?1, 102, 102, ?2, ?3, ?4)",
            params![id.as_slice(), n + 10, created, expiry],
        )
        .unwrap();
        let transaction = tx.last_insert_rowid();
        tx.execute(
            "INSERT INTO orchard_received_notes (transaction_id, action_index,
                 account_id, diversifier, value, rho, rseed, is_change, memo, note_version)
             SELECT id_tx, ?1, ?2, zeroblob(11), 110000, zeroblob(32), zeroblob(32), 0, X'F6', 2
             FROM transactions WHERE txid = ?3",
            params![n + 2, account, FUNDING],
        )
        .unwrap();
        let note = tx.last_insert_rowid();
        tx.execute(
            "INSERT INTO orchard_received_note_spends (orchard_received_note_id, transaction_id)
             VALUES (?1, ?2)",
            params![note, transaction],
        )
        .unwrap();
        tx.execute(
            "INSERT INTO sent_notes (transaction_id, output_pool, output_index,
                 from_account_id, to_address, value, memo)
             VALUES (?1, 3, 0, ?2, 'fixture-external', 100000, X'F6')",
            params![transaction, account],
        )
        .unwrap();
        ids.push(id.to_vec());
    }
    tx.commit().unwrap();
    ids
}

fn assert_bounded(reads: &Reads, expected: &HashSet<Vec<u8>>) {
    for batches in [&reads.details, &reads.outputs] {
        assert!(batches.iter().all(|batch| batch.len() <= 20), "{reads:?}");
        let ids: Vec<_> = batches.iter().flatten().cloned().collect();
        assert_eq!(ids.len(), expected.len(), "each dependency is loaded once");
        assert_eq!(ids.into_iter().collect::<HashSet<_>>(), *expected);
    }
}

#[test]
fn targeted_details_ignore_unrelated_created_history_and_reuse_batches() {
    for count in [100, 1000] {
        let wallet = wallet();
        populate(&wallet);
        let ids = add_created_history(&wallet, count);
        let expected: Vec<_> = history(&wallet, wallet.sender, None)
            .into_iter()
            .filter(|row| row.txid_hex == hex::encode(&ids[0]))
            .collect();
        assert_eq!(expected.len(), 1);
        let mut verified = false;
        // Concurrent fixtures can evict the four-account LRU between calls.
        // Retry a cold pass; unconditional summary/detail rereads still fail.
        for _ in 0..100 {
            history_pages::evict_db(&wallet.path);
            let (rows, reads) = observe(|| targeted(&wallet, wallet.sender, &[ids[0].clone()]));
            assert_eq!(rows, expected);
            assert_eq!(reads.summaries, 1);
            assert_bounded(&reads, &ids[..25].iter().cloned().collect());
            let (rows, repeated) =
                observe(|| targeted(&wallet, wallet.sender, &[ids[1].clone(), ids[1].clone()]));
            if repeated.summaries != 0 {
                continue;
            }
            assert_eq!(rows.len(), 1);
            assert_bounded(&repeated, &HashSet::new());
            let (_, next) = observe(|| targeted(&wallet, wallet.sender, &[ids[25].clone()]));
            if next.summaries != 0 {
                continue;
            }
            assert_bounded(&next, &ids[25..50].iter().cloned().collect());
            verified = true;
            break;
        }
        assert!(verified, "unchanged batches did not reuse the snapshot");
        history_pages::evict_db(&wallet.path);
    }
}

#[test]
fn targeted_reads_keep_large_proposals_and_only_return_requested_transactions() {
    let wallet = wallet();
    populate(&wallet);
    let ids = add_created_history(&wallet, 200);
    let requested = ids[..150].to_vec();
    let all = history(&wallet, wallet.sender, None);
    let expected: Vec<_> = all
        .into_iter()
        .filter(|row| requested.iter().any(|id| hex::encode(id) == row.txid_hex))
        .collect();
    let (rows, reads) = observe(|| targeted(&wallet, wallet.sender, &requested));
    assert_eq!(rows, expected);
    assert_bounded(&reads, &requested.into_iter().collect());
    history_pages::evict_db(&wallet.path);
}

#[test]
fn targeted_reads_refresh_summary_and_detail_only_changes() {
    let wallet = wallet();
    populate(&wallet);
    let conn = Connection::open(&wallet.path).unwrap();
    let before = targeted(&wallet, wallet.sender, &[PAYMENT.to_vec()]);
    conn.execute(
        "UPDATE transactions SET fee = 23456 WHERE txid = ?1",
        [PAYMENT],
    )
    .unwrap();
    let (after, reads) = observe(|| targeted(&wallet, wallet.sender, &[PAYMENT.to_vec()]));
    let expected: Vec<_> = history(&wallet, wallet.sender, None)
        .into_iter()
        .filter(|row| row.txid_hex == hex::encode(PAYMENT))
        .collect();
    assert_eq!(after, expected);
    assert_ne!(after, before);
    assert_eq!(reads.summaries, 1);
    assert_bounded(&reads, &HashSet::from([PAYMENT.to_vec()]));
    // Enrich outputs without changing the accounting summary. Targeted reads
    // must discard previously cached details even in this case.
    const RECEIVED: [u8; 32] = [0x99; 32];
    conn.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index)
         VALUES (?1, 102, 102, 10)",
        [RECEIVED],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO orchard_received_notes (transaction_id, action_index,
             account_id, diversifier, value, rho, rseed, is_change, memo, note_version)
         SELECT id_tx, 0, ?1, zeroblob(11), 0, zeroblob(32), zeroblob(32), 0, X'F6', 2
         FROM transactions WHERE txid = ?2",
        params![account_id(&conn, wallet.recipient), RECEIVED],
    )
    .unwrap();
    let before = targeted(&wallet, wallet.recipient, &[RECEIVED.to_vec()]);
    assert!(before[0].details_complete);
    conn.execute("UPDATE orchard_received_notes SET memo = NULL WHERE transaction_id = (SELECT id_tx FROM transactions WHERE txid = ?1)", [RECEIVED]).unwrap();
    let after = targeted(&wallet, wallet.recipient, &[RECEIVED.to_vec()]);
    assert!(!after[0].details_complete);
    let expected: Vec<_> = history(&wallet, wallet.recipient, None)
        .into_iter()
        .filter(|row| row.txid_hex == hex::encode(RECEIVED))
        .collect();
    assert_eq!(after, expected);
    history_pages::evict_db(&wallet.path);
    drop(conn);
    std::fs::remove_file(&wallet.path).unwrap();
}

#[test]
fn targeted_summary_details_and_outputs_share_snapshot_during_sync_commit() {
    let wallet = wallet();
    populate(&wallet);
    let expected: Vec<_> = history(&wallet, wallet.sender, None)
        .into_iter()
        .filter(|row| row.txid_hex == hex::encode(PAYMENT))
        .collect();
    let (start_tx, start_rx) = mpsc::channel();
    let (done_tx, done_rx) = mpsc::channel();
    let path = wallet.path.clone();
    let writer = std::thread::spawn(move || {
        start_rx.recv_timeout(Duration::from_secs(10)).unwrap();
        let mut conn = Connection::open(path).unwrap();
        let tx = conn.transaction().unwrap();
        tx.execute(
            "UPDATE transactions SET fee = 20000 WHERE txid = ?1",
            [PAYMENT],
        )
        .unwrap();
        tx.execute(
            "UPDATE sent_notes SET value = 56000 WHERE output_index = 2
                 AND transaction_id = (SELECT id_tx FROM transactions WHERE txid = ?1)",
            [PAYMENT],
        )
        .unwrap();
        tx.commit().unwrap();
        done_tx.send(()).unwrap();
    });
    BEFORE_DETAILS.with_borrow_mut(|action| {
        *action = Some(Box::new(move || {
            start_tx.send(()).unwrap();
            done_rx.recv_timeout(Duration::from_secs(10)).unwrap();
        }));
    });
    let (during, _) = observe(|| targeted(&wallet, wallet.sender, &[PAYMENT.to_vec()]));
    writer.join().unwrap();
    assert_eq!(
        during, expected,
        "the writer must not mix new outputs with the old summary"
    );
    let fresh = targeted(&wallet, wallet.sender, &[PAYMENT.to_vec()]);
    let expected: Vec<_> = history(&wallet, wallet.sender, None)
        .into_iter()
        .filter(|row| row.txid_hex == hex::encode(PAYMENT))
        .collect();
    assert_eq!(fresh, expected);
    assert_ne!(fresh, during);
    history_pages::evict_db(&wallet.path);
}
