mod common;

use common::{
    add_account_with_birthday, create_wallet, ensure_regtest_up, exclusive_regtest, execute_send,
    fund_wallet, get_balance, get_sync_status, get_transaction_history, mine_blocks, sync_wallet,
};

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn no_range_sync_refreshes_pending_status_and_completes() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (sender_dir, sender_wallet) = create_wallet("Pending Sender");
    let sender_db = sender_dir.path().join("zcash_wallet.db");
    let (_receiver_dir, receiver_wallet) = create_wallet("Pending Receiver");

    fund_wallet(&sender_wallet.unified_address, "2.0");
    sync_wallet(&sender_db);

    let txid = execute_send(
        &sender_db,
        &sender_wallet.account_uuid,
        &sender_wallet.mnemonic,
        &receiver_wallet.unified_address,
        50_000_000,
    );
    assert!(!txid.is_empty(), "execute_proposal should return a txid");

    let conn = rusqlite::Connection::open(&sender_db).expect("open wallet db");
    let pending_scan_ranges: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM scan_queue WHERE priority > 10",
            [],
            |row| row.get(0),
        )
        .expect("query pending scan ranges");
    assert_eq!(
        pending_scan_ranges, 0,
        "the status refresh must exercise the no-range completion path"
    );
    let confirmed_before: Option<i64> = conn
        .query_row(
            "SELECT confirmed_unmined_at_height
             FROM transactions
             WHERE mined_height IS NULL
             ORDER BY id_tx DESC
             LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("query pending transaction before sync");
    assert_eq!(confirmed_before, None);
    drop(conn);

    // Do not mine a block. The second sync has no scan work, but its final
    // bounded enhancement pass must still poll the pending transaction.
    sync_wallet(&sender_db);

    let status = get_sync_status(&sender_db);
    assert!(
        status.is_complete,
        "pending GetStatus must not block completion"
    );
    assert_eq!(status.scanned_height, status.chain_tip_height);

    let conn = rusqlite::Connection::open(&sender_db).expect("open wallet db");
    let (mined_height, confirmed_after): (Option<i64>, Option<i64>) = conn
        .query_row(
            "SELECT mined_height, confirmed_unmined_at_height
             FROM transactions
             WHERE mined_height IS NULL
             ORDER BY id_tx DESC
             LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("query pending transaction after sync");
    assert_eq!(mined_height, None);
    assert!(
        confirmed_after.is_some(),
        "the no-range enhancement pass should update pending status"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn funded_wallet_can_send_to_second_wallet() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (sender_dir, sender_wallet) = create_wallet("Sender");
    let sender_db = sender_dir.path().join("zcash_wallet.db");
    let (receiver_dir, receiver_wallet) = create_wallet("Receiver");
    let receiver_db = receiver_dir.path().join("zcash_wallet.db");

    fund_wallet(&sender_wallet.unified_address, "2.0");
    sync_wallet(&sender_db);

    let sender_before = get_balance(&sender_db, &sender_wallet.account_uuid);
    assert!(
        sender_before.spendable >= 200_000_000,
        "expected sender to have at least 2 ZEC before send, got {}",
        sender_before.spendable
    );

    let txid = execute_send(
        &sender_db,
        &sender_wallet.account_uuid,
        &sender_wallet.mnemonic,
        &receiver_wallet.unified_address,
        50_000_000,
    );
    assert!(!txid.is_empty(), "execute_proposal should return a txid");

    mine_blocks(10);
    sync_wallet(&sender_db);
    sync_wallet(&receiver_db);

    let sender_after = get_balance(&sender_db, &sender_wallet.account_uuid);
    let receiver_after = get_balance(&receiver_db, &receiver_wallet.account_uuid);

    assert!(
        sender_after.spendable < sender_before.spendable,
        "sender spendable balance should decrease after sending"
    );
    assert!(
        receiver_after.spendable >= 50_000_000,
        "receiver should see at least 0.5 ZEC after send, got {}",
        receiver_after.spendable
    );

    let receiver_history = get_transaction_history(&receiver_db, &receiver_wallet.account_uuid);
    assert!(
        receiver_history
            .iter()
            .any(|tx| tx.account_balance_delta > 0),
        "receiver should record an inbound transaction"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn imported_second_account_can_send_using_its_own_seed() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, primary_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");
    let (_secondary_source_dir, secondary_source_wallet) = create_wallet("Secondary Source");
    let (receiver_dir, receiver_wallet) = create_wallet("Receiver");
    let receiver_db = receiver_dir.path().join("zcash_wallet.db");

    let second_account = add_account_with_birthday(
        &main_db,
        "Secondary",
        &secondary_source_wallet.mnemonic,
        Some(1),
    );

    fund_wallet(&second_account.unified_address, "1.6");
    sync_wallet(&main_db);

    let primary_before = get_balance(&main_db, &primary_wallet.account_uuid);
    let second_before = get_balance(&main_db, &second_account.account_uuid);
    assert_eq!(
        primary_before.spendable, 0,
        "primary account should remain unfunded in this scenario"
    );
    assert!(
        second_before.spendable >= 160_000_000,
        "second account should have spendable funds before send, got {}",
        second_before.spendable
    );

    let txid = execute_send(
        &main_db,
        &second_account.account_uuid,
        &secondary_source_wallet.mnemonic,
        &receiver_wallet.unified_address,
        60_000_000,
    );
    assert!(!txid.is_empty(), "second account send should return a txid");

    mine_blocks(10);
    sync_wallet(&main_db);
    sync_wallet(&receiver_db);

    let primary_after = get_balance(&main_db, &primary_wallet.account_uuid);
    let second_after = get_balance(&main_db, &second_account.account_uuid);
    let receiver_after = get_balance(&receiver_db, &receiver_wallet.account_uuid);

    assert_eq!(
        primary_after.spendable, 0,
        "sending from second account must not credit or debit the primary account"
    );
    assert!(
        second_after.spendable < second_before.spendable,
        "second account spendable balance should decrease after sending"
    );
    assert!(
        receiver_after.spendable >= 60_000_000,
        "receiver should see at least 0.6 ZEC after imported-account send, got {}",
        receiver_after.spendable
    );
}
