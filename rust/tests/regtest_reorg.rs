mod common;

use common::{
    create_wallet, ensure_regtest_up, exclusive_regtest, execute_send, fund_wallet, get_balance,
    get_transaction_history, mine_blocks, run_script, sync_wallet,
};

use std::path::Path;

fn wallet_scanned_tip(db_path: &Path) -> (u64, Vec<u8>) {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.query_row(
        "SELECT height, hash FROM blocks ORDER BY height DESC LIMIT 1",
        [],
        |row| Ok((row.get::<_, u64>(0)?, row.get::<_, Vec<u8>>(1)?)),
    )
    .expect("wallet must have a scanned tip")
}

/// A reorg recovery is only complete when the wallet can spend again.
/// A successful post-reorg send proves that the reconstructed note tree,
/// witness, and anchor are accepted by the consensus node.
#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn wallet_survives_reorg_and_can_still_spend() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (sender_dir, sender) = create_wallet("ReorgSender");
    let sender_db = sender_dir.path().join("zcash_wallet.db");
    let (receiver_dir, receiver) = create_wallet("ReorgReceiver");
    let receiver_db = receiver_dir.path().join("zcash_wallet.db");

    // Keep the funded note below the branch point so it must remain spendable
    // after the wallet rewinds and scans the replacement branch.
    fund_wallet(&sender.unified_address, "2.0");
    mine_blocks(15);
    sync_wallet(&sender_db);

    let before = get_balance(&sender_db, &sender.account_uuid);
    assert!(
        before.spendable >= 200_000_000,
        "expected at least 2 ZEC before the reorg, got {}",
        before.spendable
    );

    run_script("reorg.sh", &["5", "25"]);
    sync_wallet(&sender_db);

    let after_reorg = get_balance(&sender_db, &sender.account_uuid);
    assert_eq!(
        after_reorg.spendable, before.spendable,
        "funding below the branch point must survive the reorg"
    );

    let txid = execute_send(
        &sender_db,
        &sender.account_uuid,
        &sender.mnemonic,
        &receiver.unified_address,
        50_000_000,
    );
    assert!(!txid.is_empty(), "post-reorg send must produce a txid");

    mine_blocks(10);
    sync_wallet(&sender_db);
    sync_wallet(&receiver_db);

    let received = get_balance(&receiver_db, &receiver.account_uuid);
    assert!(
        received.spendable >= 50_000_000,
        "receiver should see the post-reorg send, got {}",
        received.spendable
    );
}

/// A reorg can replace the canonical tip without changing its height. This is
/// the case a height-only completion check misses, so assert the wallet's
/// stored block hash actually changes after the second sync.
#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn same_height_reorg_replaces_wallet_tip_hash() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (wallet_dir, wallet) = create_wallet("SameHeightReorg");
    let wallet_db = wallet_dir.path().join("zcash_wallet.db");

    // Keep the received note below the replaced range. Its unchanged balance
    // distinguishes a correct rewind/rescan from destructive recovery.
    fund_wallet(&wallet.unified_address, "1.0");
    sync_wallet(&wallet_db);

    let balance_before = get_balance(&wallet_db, &wallet.account_uuid);
    let (height_before, hash_before) = wallet_scanned_tip(&wallet_db);

    run_script("reorg.sh", &["5", "6", "same-height"]);
    sync_wallet(&wallet_db);

    let (height_after, hash_after) = wallet_scanned_tip(&wallet_db);
    assert_eq!(
        height_after, height_before,
        "same-height replacement must leave the scanned height unchanged"
    );
    assert_ne!(
        hash_after, hash_before,
        "wallet must replace its stored tip hash after a same-height reorg"
    );

    let balance_after = get_balance(&wallet_db, &wallet.account_uuid);
    assert_eq!(
        balance_after.spendable, balance_before.spendable,
        "a note below the branch point must remain spendable"
    );
}

/// Exercise transaction state on the branch that disappears: the sender's
/// outgoing transaction and the receiver's note are first observed mined,
/// then the exact transaction is kept out of the same-height replacement.
#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn orphaned_send_is_unmined_and_receiver_loses_spendable_note() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (funder_dir, funder) = create_wallet("OrphanedSendFunder");
    let funder_db = funder_dir.path().join("zcash_wallet.db");
    let (sender_dir, sender) = create_wallet("OrphanedSendSender");
    let sender_db = sender_dir.path().join("zcash_wallet.db");
    let (receiver_dir, receiver) = create_wallet("OrphanedSendReceiver");
    let receiver_db = receiver_dir.path().join("zcash_wallet.db");

    // Keep the funder's note below the branch point. The parent and child
    // transactions below are both externally submitted SDK transactions, so
    // restarting zcashd removes them from the disconnected-branch mempool.
    fund_wallet(&funder.unified_address, "2.0");
    mine_blocks(15);
    sync_wallet(&funder_db);

    let parent_txids = execute_send(
        &funder_db,
        &funder.account_uuid,
        &funder.mnemonic,
        &sender.unified_address,
        80_000_000,
    );
    let parent_parts: Vec<_> = parent_txids.split(',').collect();
    assert_eq!(
        parent_parts.len(),
        1,
        "parent funding must use a single transaction"
    );
    let parent_txid = parent_parts[0];
    mine_blocks(10);
    sync_wallet(&sender_db);
    assert!(
        get_balance(&sender_db, &sender.account_uuid).spendable >= 80_000_000,
        "sender must first be able to spend the old-branch parent note"
    );

    let child_txids = execute_send(
        &sender_db,
        &sender.account_uuid,
        &sender.mnemonic,
        &receiver.unified_address,
        50_000_000,
    );
    let child_parts: Vec<_> = child_txids.split(',').collect();
    assert_eq!(
        child_parts.len(),
        1,
        "child spend must use a single transaction"
    );
    let child_txid = child_parts[0];

    // Parent and child are each mined in the first block of a ten-block run.
    // The parent therefore sits at old_tip - 19; replacing twenty blocks
    // removes both transactions and returns to the identical tip height.
    mine_blocks(10);
    sync_wallet(&sender_db);
    sync_wallet(&receiver_db);

    let receiver_mined = get_transaction_history(&receiver_db, &receiver.account_uuid);
    assert!(
        receiver_mined
            .iter()
            .any(|tx| tx.txid_hex == child_txid && tx.mined_height > 0),
        "receiver must first observe the child transaction mined on the old branch"
    );
    assert!(
        get_balance(&receiver_db, &receiver.account_uuid).spendable >= 50_000_000,
        "receiver must first be able to spend the confirmed old-branch note"
    );

    let (old_height, old_hash) = wallet_scanned_tip(&sender_db);
    let dropped_txids = format!("{parent_txid},{child_txid}");
    run_script(
        "reorg.sh",
        &["19", "20", "same-height", "drop-mempool", &dropped_txids],
    );
    sync_wallet(&sender_db);
    sync_wallet(&receiver_db);

    let (new_height, new_hash) = wallet_scanned_tip(&sender_db);
    assert_eq!(new_height, old_height, "replacement must be same-height");
    assert_ne!(new_hash, old_hash, "sender must adopt the replacement tip");

    let sender_history = get_transaction_history(&sender_db, &sender.account_uuid);
    let orphaned_parent = sender_history
        .iter()
        .find(|tx| tx.txid_hex == parent_txid)
        .expect("sender must retain the orphaned incoming parent transaction");
    assert_eq!(
        orphaned_parent.mined_height, 0,
        "orphaned incoming parent transaction must no longer be marked mined"
    );
    let orphaned_child = sender_history
        .iter()
        .find(|tx| tx.txid_hex == child_txid)
        .expect("sender must retain the locally-created orphan child transaction");
    assert_eq!(
        orphaned_child.mined_height, 0,
        "orphaned outgoing child transaction must no longer be marked mined"
    );

    let receiver_history = get_transaction_history(&receiver_db, &receiver.account_uuid);
    if let Some(receiver_orphan) = receiver_history.iter().find(|tx| tx.txid_hex == child_txid) {
        assert_eq!(
            receiver_orphan.mined_height, 0,
            "orphaned incoming transaction must no longer be marked mined"
        );
    }
    assert_eq!(
        get_balance(&receiver_db, &receiver.account_uuid).spendable,
        0,
        "receiver must lose spendability of the orphaned note"
    );

    // Once the local transaction expires on the replacement branch, the
    // invalid child must not become mined by automatic resubmission.
    mine_blocks(50);
    sync_wallet(&sender_db);
    let expired_history = get_transaction_history(&sender_db, &sender.account_uuid);
    let expired = expired_history
        .iter()
        .find(|tx| tx.txid_hex == child_txid)
        .expect("sender must retain expired transaction history");
    assert!(
        expired.expired_unmined,
        "orphaned send must eventually expire"
    );
    assert_eq!(expired.mined_height, 0, "invalid child must remain unmined");
}
