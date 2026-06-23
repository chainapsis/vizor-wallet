mod common;

use common::{
    add_account_with_birthday, create_wallet, ensure_regtest_up, exclusive_regtest, execute_send,
    fund_wallet, get_balance, get_transaction_history, mine_blocks, path_str, sync_wallet,
    REGTEST_NETWORK,
};
use rust_lib_zcash_wallet::api::sync as sync_api;

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

/// VZR-42 integration guard: a real `propose_transfer` shortfall must be classified by
/// sync state, not surfaced as an always-final error. This exercises end to end what the
/// unit tests can only fake (they feed hand-written error strings):
///   1. not synced to tip -> a shortfall is coded retryable (`sync_in_progress|` /
///      `scan_required|`) and NEVER `insufficient_funds|` (the exact VZR-42 symptom:
///      a false "insufficient" must not block Review while the wallet is still catching up)
///   2. synced + genuine overspend -> FINAL `insufficient_funds|` (the fix must NOT
///      over-suppress once the wallet is idle at tip)
///   3. synced + affordable amount -> the proposal builds (recovery path works)
///
/// The middle/last cases reach `propose_send` through the public API on a fully-synced
/// wallet, so `is_sync_running()` is false and `wallet_is_synced_to_tip(db)` is true —
/// the only state in which a shortfall is allowed to be final.
#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn propose_send_codes_shortfall_by_sync_state() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (sender_dir, sender_wallet) = create_wallet("Sender");
    let sender_db = sender_dir.path().join("zcash_wallet.db");
    let (_receiver_dir, receiver_wallet) = create_wallet("Receiver");
    let db_str = path_str(&sender_db);
    let send_flow_id = "regtest-vzr42-flow";
    // 10,000 ZEC — far beyond any test balance, so propose_transfer must report a shortfall.
    let overspend: u64 = 1_000_000_000_000;

    // 1. Before any sync the wallet is not synced to tip, so a shortfall must be coded as
    //    retryable, never as a final insufficient_funds (the VZR-42 false-block symptom).
    let unsynced_err = sync_api::propose_send(
        db_str.clone(),
        REGTEST_NETWORK.into(),
        sender_wallet.account_uuid.clone(),
        send_flow_id.into(),
        receiver_wallet.unified_address.clone(),
        50_000_000,
        None,
    )
    .err()
    .expect("propose on an unsynced wallet must fail to build a proposal");
    assert!(
        !unsynced_err.contains("insufficient_funds|"),
        "an unsynced wallet must NOT report a final insufficient shortfall (VZR-42), got: {unsynced_err}"
    );
    assert!(
        unsynced_err.contains("sync_in_progress|") || unsynced_err.contains("scan_required|"),
        "an unsynced shortfall should be coded as waiting-for-sync, got: {unsynced_err}"
    );

    // Fund + sync to tip.
    fund_wallet(&sender_wallet.unified_address, "1.0");
    sync_wallet(&sender_db);
    let before = get_balance(&sender_db, &sender_wallet.account_uuid);
    assert!(
        before.spendable >= 90_000_000,
        "expected ~1 ZEC spendable after sync, got {}",
        before.spendable
    );

    // 2. Synced + genuine overspend: now the shortfall is FINAL insufficient_funds.
    let final_err = sync_api::propose_send(
        db_str.clone(),
        REGTEST_NETWORK.into(),
        sender_wallet.account_uuid.clone(),
        send_flow_id.into(),
        receiver_wallet.unified_address.clone(),
        overspend,
        None,
    )
    .err()
    .expect("overspend on a synced wallet must fail to build a proposal");
    assert!(
        final_err.contains("insufficient_funds|"),
        "synced overspend should be coded final insufficient, got: {final_err}"
    );
    assert!(
        !final_err.contains("sync_in_progress|") && !final_err.contains("scan_required|"),
        "synced overspend must not be masked as still-syncing, got: {final_err}"
    );

    // 3. Synced + affordable amount: the normal path still builds a proposal.
    let ok = sync_api::propose_send(
        db_str.clone(),
        REGTEST_NETWORK.into(),
        sender_wallet.account_uuid.clone(),
        send_flow_id.into(),
        receiver_wallet.unified_address.clone(),
        50_000_000,
        None,
    );
    assert!(
        ok.is_ok(),
        "an affordable amount on a synced wallet should propose cleanly, got: {:?}",
        ok.err()
    );
}
