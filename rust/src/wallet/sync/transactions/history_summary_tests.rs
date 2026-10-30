//! Consumer wiring under the library's real migrated schema. These fixtures
//! record local accounting facts; they do not need a node or real wallet data.

use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc, Arc,
};
use std::time::Duration;

use rusqlite::{
    hooks::{AuthAction, AuthContext, Authorization},
    params, Connection,
};
use secrecy::SecretVec;

use super::*;
use crate::wallet::keys;

#[path = "history_targeted_tests.rs"]
pub(super) mod targeted;

const NETWORK: WalletNetwork = WalletNetwork::Regtest;
// Nonuniform identifiers catch an accidental switch from database byte order
// to TxId's reversed display encoding at the typed-API boundary.
const FUNDING: [u8; 32] = {
    let mut bytes = [0x31; 32];
    bytes[0] = 0x11;
    bytes
};
const PAYMENT: [u8; 32] = {
    let mut bytes = [0x32; 32];
    bytes[0] = 0x12;
    bytes
};

struct Wallet {
    _dir: tempfile::TempDir,
    path: String,
    sender: AccountUuid,
    recipient: AccountUuid,
}

fn wallet() -> Wallet {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let (sender, _) = keys::init_db_and_create_account(
        &path,
        NETWORK,
        &SecretVec::new(vec![1; 32]),
        Some(100),
        "sender",
    )
    .unwrap();
    let (recipient, _) = keys::add_account(
        &path,
        NETWORK,
        "recipient",
        &SecretVec::new(vec![2; 32]),
        Some(100),
    )
    .unwrap();
    Wallet {
        _dir: dir,
        path,
        sender: parse_account_uuid(&sender).unwrap(),
        recipient: parse_account_uuid(&recipient).unwrap(),
    }
}

fn account_id(conn: &Connection, account: AccountUuid) -> i64 {
    conn.query_row(
        "SELECT id FROM accounts WHERE uuid = ?1",
        [account.expose_uuid().as_bytes()],
        |row| row.get(0),
    )
    .unwrap()
}

/// Two equal-value owned inputs fund change, an internal payment to a second
/// account, and an external payment. Equal values must not collapse, and the
/// sender's accounting must not leak into the recipient's history.
fn populate(wallet: &Wallet) {
    let mut conn = Connection::open(&wallet.path).unwrap();
    conn.pragma_update(None, "foreign_keys", true).unwrap();
    let tx = conn.transaction().unwrap();
    let sender = account_id(&tx, wallet.sender);
    let recipient = account_id(&tx, wallet.recipient);
    let birthday: u32 = tx
        .query_row("SELECT MIN(birthday_height) FROM accounts", [], |row| {
            row.get(0)
        })
        .unwrap();
    for height in birthday..=200 {
        let mut hash = [0; 32];
        hash[..4].copy_from_slice(&height.to_le_bytes());
        tx.execute(
            "INSERT INTO blocks (height, hash, time, sapling_tree,
                 sapling_commitment_tree_size, orchard_commitment_tree_size,
                 ironwood_commitment_tree_size)
             VALUES (?1, ?2, ?3, x'00', 0, 0, 0)",
            params![height, hash.as_slice(), 600_000 + height],
        )
        .unwrap();
    }
    tx.execute("DELETE FROM scan_queue", []).unwrap();
    tx.execute(
        "INSERT INTO scan_queue (block_range_start, block_range_end, priority)
         VALUES (?1, 201, 10)",
        [birthday],
    )
    .unwrap();
    tx.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index)
         VALUES (?1, 100, 100, 1)",
        [FUNDING],
    )
    .unwrap();
    let funding_id = tx.last_insert_rowid();
    let mut notes = vec![];
    for index in 0..2 {
        tx.execute(
            "INSERT INTO orchard_received_notes (transaction_id, action_index,
                 account_id, diversifier, value, rho, rseed, is_change, memo, note_version)
             VALUES (?1, ?2, ?3, zeroblob(11), 100000, zeroblob(32),
                 zeroblob(32), 0, X'F6', 2)",
            params![funding_id, index, sender],
        )
        .unwrap();
        notes.push(tx.last_insert_rowid());
    }
    tx.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height,
             tx_index, expiry_height, fee, created)
         VALUES (?1, 101, 101, 2, 220, 10000, '2026-01-02 03:04:05')",
        [PAYMENT],
    )
    .unwrap();
    let payment_id = tx.last_insert_rowid();
    for note in notes {
        tx.execute(
            "INSERT INTO orchard_received_note_spends (orchard_received_note_id, transaction_id)
             VALUES (?1, ?2)",
            params![note, payment_id],
        )
        .unwrap();
    }
    for (index, to, value, change) in [(0, sender, 50000, true), (1, recipient, 90000, false)] {
        tx.execute(
            "INSERT INTO orchard_received_notes (transaction_id, action_index,
                 account_id, diversifier, value, rho, rseed, is_change, memo, note_version)
             VALUES (?1, ?2, ?3, zeroblob(11), ?4, zeroblob(32),
                 zeroblob(32), ?5, X'F6', 2)",
            params![payment_id, index, to, value, change],
        )
        .unwrap();
        tx.execute(
            "INSERT INTO sent_notes (transaction_id, output_pool, output_index,
                 from_account_id, to_account_id, value, memo)
             VALUES (?1, 3, ?2, ?3, ?4, ?5, X'F6')",
            params![payment_id, index, sender, to, value],
        )
        .unwrap();
    }
    tx.execute(
        "INSERT INTO sent_notes (transaction_id, output_pool, output_index,
             from_account_id, to_address, value, memo)
         VALUES (?1, 3, 2, ?2, 'fixture-external-recipient', 50000, X'F6')",
        params![payment_id, sender],
    )
    .unwrap();
    tx.commit().unwrap();
}

fn history(wallet: &Wallet, account: AccountUuid, limit: Option<u32>) -> Vec<TransactionInfo> {
    get_transaction_history(
        &wallet.path,
        NETWORK,
        limit,
        &account.expose_uuid().to_string(),
    )
    .unwrap()
}

#[test]
fn history_summaries_keep_empty_and_unknown_accounts_distinct() {
    let wallet = wallet();
    assert!(history(&wallet, wallet.sender, None).is_empty());
    assert!(
        get_transaction_history(&wallet.path, NETWORK, None, &uuid::Uuid::nil().to_string(),)
            .err()
            .unwrap()
            .contains("Failed to read history summaries")
    );
}

#[test]
fn history_summaries_match_view_and_preserve_account_display_and_limit() {
    let wallet = wallet();
    populate(&wallet);
    let conn = open_readonly_conn(&wallet.path).unwrap();
    let read_tx = conn.unchecked_transaction().unwrap();
    for (account, expected_rows) in [(wallet.sender, 2), (wallet.recipient, 1)] {
        let bases = read_history_bases(&read_tx, &wallet.path, NETWORK, account).unwrap();
        assert_eq!(bases.len(), expected_rows);
        for base in bases {
            let view =
                read_history_base_by_txid(&read_tx, account.expose_uuid().as_bytes(), &base.txid)
                    .unwrap()
                    .unwrap();
            assert_eq!(base, view);
            // The projection itself does not authorize complete history.
            assert!(!base.history.details_complete);
            assert!(base.history.provisional);
            if base.txid == PAYMENT {
                assert_eq!(base.expiry_height, Some(220));
                assert_eq!(base.tx_index, 2);
                assert_eq!(base.mined_height, Some(101));
                assert_eq!(base.block_time, 600101);
                assert_eq!(base.created_time, 1767323045);
                assert!(base.spent_orchard_note);
                assert!(!base.is_shielding);
                if account == wallet.sender {
                    assert_eq!(base.total_spent, 200000);
                    assert_eq!(base.total_received, 50000);
                    assert_eq!(base.account_balance_delta, -150000);
                    assert_eq!(base.fee, Some(10000));
                } else {
                    assert_eq!(base.total_spent, 0);
                    assert_eq!(base.total_received, 90000);
                    assert_eq!(base.account_balance_delta, 90000);
                }
            }
        }
    }
    let sender = history(&wallet, wallet.sender, None);
    assert_eq!(sender.len(), 2);
    assert_eq!(sender[0].txid_hex, hex::encode(PAYMENT));
    assert_eq!(sender[0].tx_kind, "sent");
    assert_eq!(sender[0].display_amount, 140000);
    assert_eq!(sender[0].fee, 10000);
    assert_eq!(sender[0].fee_state, TransactionFeeState::Known);
    assert!(sender[0].details_complete);
    assert!(!sender[0].provisional);
    assert_eq!(sender[1].tx_kind, "received");
    assert_eq!(sender[1].display_amount, 200000);
    let limited = history(&wallet, wallet.sender, Some(1));
    assert_eq!(limited.len(), 1);
    assert_eq!(limited[0].txid_hex, sender[0].txid_hex);
    let recipient = history(&wallet, wallet.recipient, None);
    assert_eq!(recipient.len(), 1);
    assert_eq!(recipient[0].tx_kind, "received");
    assert_eq!(recipient[0].display_amount, 90000);
    assert_eq!(recipient[0].fee_state, TransactionFeeState::NotApplicable);
}

#[test]
fn history_summaries_preserve_unknown_metadata_and_private_expiry_fallback() {
    let wallet = wallet();
    populate(&wallet);
    let conn = Connection::open(&wallet.path).unwrap();
    conn.execute(
        "UPDATE transactions SET mined_height = NULL, tx_index = NULL,
             expiry_height = NULL, fee = NULL, created = 'unparseable'
         WHERE txid = ?1",
        [PAYMENT],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO ironwood_enhance_routing (transaction_id, route, history_expiry_height)
         SELECT id_tx, 0, 150 FROM transactions WHERE txid = ?1",
        [PAYMENT],
    )
    .unwrap();
    let reader = open_readonly_conn(&wallet.path).unwrap();
    let tx = reader.unchecked_transaction().unwrap();
    let bases = read_history_bases(&tx, &wallet.path, NETWORK, wallet.sender).unwrap();
    let payment = bases.iter().find(|base| base.txid == PAYMENT).unwrap();
    assert_eq!(payment.mined_height, None);
    assert_eq!(payment.tx_index, -1);
    assert_eq!(payment.block_time, 0);
    assert_eq!(payment.created.as_deref(), Some("unparseable"));
    assert_eq!(payment.created_time, 0);
    assert_eq!(payment.fee, None);
    assert_eq!(payment.history.fee, Fee::Unknown);
    assert_eq!(payment.expiry_height, Some(150));
    // Private history's display expiry does not establish protocol expiration.
    assert!(!payment.expired_unmined);
    let rows = history(&wallet, wallet.sender, None);
    let payment = rows
        .iter()
        .find(|row| row.txid_hex == hex::encode(PAYMENT))
        .unwrap();
    assert_eq!(payment.fee_state, TransactionFeeState::Unknown);
    assert!(!payment.expired_unmined);
    assert!(payment.provisional);
}

#[test]
fn history_summaries_do_not_select_raw_payloads() {
    let wallet = wallet();
    populate(&wallet);
    let conn = open_readonly_conn(&wallet.path).unwrap();
    conn.authorizer(Some(|context: AuthContext<'_>| match context.action {
        AuthAction::Read {
            table_name: "transactions",
            column_name: "raw",
        } => Authorization::Deny,
        _ => Authorization::Allow,
    }));
    let read_tx = conn.unchecked_transaction().unwrap();
    assert_eq!(
        read_history_bases(&read_tx, &wallet.path, NETWORK, wallet.sender)
            .unwrap()
            .len(),
        2,
    );
}

#[test]
fn history_summaries_details_and_outputs_share_snapshot_during_sync_commit() {
    assert_history_snapshot(None);
    assert_history_snapshot(Some(1));
}

fn assert_history_snapshot(limit: Option<u32>) {
    let wallet = wallet();
    populate(&wallet);
    let conn = open_readonly_conn(&wallet.path).unwrap();
    let fired = Arc::new(AtomicBool::new(false));
    let intercepted = fired.clone();
    let (start_tx, start_rx) = mpsc::channel();
    let (done_tx, done_rx) = mpsc::channel();
    let path = wallet.path.clone();
    let writer = std::thread::spawn(move || {
        start_rx.recv_timeout(Duration::from_secs(10)).unwrap();
        let mut conn = Connection::open(path).unwrap();
        conn.busy_timeout(Duration::from_secs(2)).unwrap();
        let tx = conn.transaction().unwrap();
        // Remove construction evidence as well as mined evidence. A recorded
        // local construction legitimately keeps payment details complete even
        // while unmined; this recovery state must change the completeness read.
        tx.execute(
            "UPDATE transactions SET mined_height = NULL, tx_index = NULL,
                 fee = 20000, created = NULL
             WHERE txid = ?1",
            [PAYMENT],
        )
        .unwrap();
        tx.execute(
            "UPDATE orchard_received_notes SET value = 45000
             WHERE transaction_id = (SELECT id_tx FROM transactions WHERE txid = ?1)
               AND action_index = 0",
            [PAYMENT],
        )
        .unwrap();
        tx.execute(
            "UPDATE sent_notes SET value = CASE output_index WHEN 0 THEN 45000
                 WHEN 2 THEN 56000 ELSE value END
             WHERE transaction_id = (SELECT id_tx FROM transactions WHERE txid = ?1)",
            [PAYMENT],
        )
        .unwrap();
        tx.execute(
            "UPDATE tpir_meta SET policy_generation = policy_generation + 1",
            [],
        )
        .unwrap();
        tx.commit().unwrap();
        done_tx.send(()).unwrap();
    });
    // The first policy read belongs to the completeness API, after the summary
    // SELECT has finished. Commit a separate WAL writer before allowing the
    // production reader to fetch completeness and outputs. No timing sleeps.
    conn.authorizer(Some(move |context: AuthContext<'_>| {
        if matches!(
            context.action,
            AuthAction::Read {
                table_name: "tpir_meta",
                ..
            }
        ) && !intercepted.swap(true, Ordering::SeqCst)
            && (start_tx.send(()).is_err()
                || done_rx.recv_timeout(Duration::from_secs(10)).is_err())
        {
            return Authorization::Deny;
        }
        Authorization::Allow
    }));
    let rows = read_transaction_history(&conn, &wallet.path, NETWORK, limit, wallet.sender);
    writer.join().unwrap();
    assert!(
        fired.load(Ordering::SeqCst),
        "must commit between library reads"
    );
    let rows = rows.unwrap();
    assert_eq!(rows.len(), limit.unwrap_or(2) as usize);
    let payment = &rows[0];
    assert_eq!(payment.mined_height, 101);
    assert_eq!(payment.block_time, 600101);
    assert_eq!(payment.account_balance_delta, -150000);
    assert_eq!(
        payment.display_amount, 140000,
        "outputs must share the summary snapshot"
    );
    assert_eq!(payment.fee, 10000);
    assert!(
        payment.details_complete,
        "completeness must share the summary snapshot"
    );
    assert!(!payment.provisional);

    // Releasing the read transaction lets the next UI request observe sync's
    // entire commit, rather than holding a stale snapshot across requests.
    let fresh = history(&wallet, wallet.sender, None);
    let payment = &fresh[0];
    assert_eq!(payment.mined_height, 0);
    assert_eq!(payment.block_time, 0);
    assert_eq!(payment.account_balance_delta, -155000);
    assert_eq!(payment.display_amount, 146000);
    assert_eq!(payment.fee, 20000);
    assert_eq!(payment.created_time, 0);
    assert!(!payment.details_complete);
    assert!(payment.provisional);
}

#[test]
fn batch_transaction_rows_match_full_history_without_unrequested_rows() {
    let wallet = wallet();
    populate(&wallet);
    for account in [wallet.sender, wallet.recipient] {
        let uuid = account.expose_uuid().to_string();
        let all = get_transaction_history(&wallet.path, NETWORK, None, &uuid).unwrap();
        assert!(!all.is_empty());
        for requested in [
            vec![hex::encode(PAYMENT)],
            vec![
                hex::encode(FUNDING),
                hex::encode(PAYMENT),
                hex::encode(PAYMENT),
            ],
        ] {
            let scoped =
                get_transaction_rows_for_txids(&wallet.path, NETWORK, &uuid, &requested).unwrap();
            let expected: Vec<_> = all
                .iter()
                .filter(|row| requested.contains(&row.txid_hex))
                .collect();
            let signature = |row: &TransactionInfo| {
                (
                    row.txid_hex.clone(),
                    row.tx_kind.clone(),
                    row.mined_height,
                    row.expired_unmined,
                    row.account_balance_delta,
                    row.display_amount,
                    row.fee,
                    row.fee_state,
                    row.details_complete,
                    row.provisional,
                )
            };
            assert_eq!(
                scoped.iter().map(signature).collect::<Vec<_>>(),
                expected.into_iter().map(signature).collect::<Vec<_>>()
            );
        }
        assert!(get_transaction_rows_for_txids(
            &wallet.path,
            NETWORK,
            &uuid,
            &[hex::encode([0x99; 32])]
        )
        .unwrap()
        .is_empty());
        assert!(
            get_transaction_rows_for_txids(&wallet.path, NETWORK, &uuid, &[])
                .unwrap()
                .is_empty()
        );
    }
}

/// Local synthetic-wallet benchmark, without nodes, network, or proofs. Run
/// explicitly with `cargo test --lib benchmark_recent_history -- --ignored --nocapture`.
#[test]
#[ignore = "diagnostic performance measurement"]
fn benchmark_recent_history() {
    use std::time::Instant;

    for count in [100, 1_000] {
        let wallet = wallet();
        populate(&wallet);
        let mut conn = Connection::open(&wallet.path).unwrap();
        let tx = conn.transaction().unwrap();
        let account = account_id(&tx, wallet.sender);
        for i in 0..count {
            let mut id = [0x77; 32];
            id[..8].copy_from_slice(&(i as u64).to_le_bytes());
            tx.execute(
                "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index)
                 VALUES (?1, 102, 102, ?2)",
                params![id.as_slice(), i + 10],
            )
            .unwrap();
            let transaction = tx.last_insert_rowid();
            for output in 0..4 {
                tx.execute(
                    "INSERT INTO orchard_received_notes (transaction_id, action_index,
                         account_id, diversifier, value, rho, rseed, is_change, memo, note_version)
                     VALUES (?1, ?2, ?3, zeroblob(11), 100000, zeroblob(32), zeroblob(32), 0, X'F6', 2)",
                    params![transaction, output, account],
                ).unwrap();
            }
        }
        tx.commit().unwrap();
        drop(conn);
        let reader = open_readonly_conn(&wallet.path).unwrap();
        let mut expected = None;
        // Alternate order to reduce warm-cache ordering bias. Fixture creation
        // and Rust compilation are outside the timed region.
        for recent in [false, true, true, false] {
            let start = Instant::now();
            let mut rows = read_transaction_history(
                &reader,
                &wallet.path,
                NETWORK,
                recent.then_some(10),
                wallet.sender,
            )
            .unwrap();
            rows.truncate(10);
            let elapsed = start.elapsed();
            if let Some(expected) = &expected {
                assert_eq!(&rows, expected);
            } else {
                expected = Some(rows);
            }
            println!(
                "RECENT_HISTORY_BENCH transactions={} recent={recent} elapsed_us={}",
                count + 2,
                elapsed.as_micros()
            );
        }
    }
}
