mod common;

use common::{
    add_account_with_birthday, create_wallet, ensure_regtest_up, exclusive_regtest, execute_send,
    execute_send_with_source, fund_wallet, get_balance, get_transaction_history, mine_blocks,
    sync_wallet, transparent_receive_address,
};

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

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn transparent_source_can_send_to_shielded_recipient() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (sender_dir, sender_wallet) = create_wallet("Transparent Sender");
    let sender_db = sender_dir.path().join("zcash_wallet.db");
    let (receiver_dir, receiver_wallet) = create_wallet("Shielded Receiver");
    let receiver_db = receiver_dir.path().join("zcash_wallet.db");

    let sender_taddr = transparent_receive_address(&sender_db, &sender_wallet.account_uuid);
    fund_wallet(&sender_taddr, "1.1");
    sync_wallet(&sender_db);

    let sender_before = get_balance(&sender_db, &sender_wallet.account_uuid);
    assert!(
        sender_before.transparent >= 110_000_000,
        "expected sender to have at least 1.1 transparent ZEC before send, got {}",
        sender_before.transparent
    );

    let txid = execute_send_with_source(
        &sender_db,
        &sender_wallet.account_uuid,
        &sender_wallet.mnemonic,
        &receiver_wallet.unified_address,
        40_000_000,
        Some("transparent"),
    );
    assert!(
        !txid.is_empty(),
        "transparent-source send should return a txid"
    );

    mine_blocks(10);
    sync_wallet(&sender_db);
    sync_wallet(&receiver_db);

    let sender_after = get_balance(&sender_db, &sender_wallet.account_uuid);
    let receiver_after = get_balance(&receiver_db, &receiver_wallet.account_uuid);

    assert!(
        sender_after.transparent < sender_before.transparent,
        "sender transparent balance should decrease after transparent-source send"
    );
    assert!(
        receiver_after.spendable >= 40_000_000,
        "receiver should see at least 0.4 ZEC after transparent-source send, got {}",
        receiver_after.spendable
    );

    let receiver_history = get_transaction_history(&receiver_db, &receiver_wallet.account_uuid);
    assert!(
        receiver_history
            .iter()
            .any(|tx| tx.account_balance_delta > 0),
        "receiver should record an inbound transparent-source transaction"
    );
}
