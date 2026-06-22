mod common;

use common::{
    add_account_with_birthday, create_wallet, create_wallet_with_birthday, current_tip_height,
    ensure_regtest_up, exclusive_regtest, fund_wallet, get_balance, get_transaction_history,
    has_pending_scan_below, history_txids, inject_orphaned_historic_below,
    inject_orphaned_scanned_below, list_accounts, min_account_birthday, mine_blocks,
    positive_history_count, sync_wallet, unique_account_uuids,
};

/// VZR-89 rescue path: a wallet already stuck by a PRE-FIX account deletion
/// (an orphaned pending Historic range left below the surviving birthday) must
/// be healed automatically by the sync-start rescue hook in `run_sync_inner` —
/// the user only has to update and re-sync, no reinstall.
///
/// Regtest fully scans its short chain, so the orphan cannot be produced by a
/// real import+delete here (it would all become `Scanned`); we inject the
/// orphan directly to mimic the mainnet-scale stuck state, then drive the real
/// sync entry point and assert it is pruned. The on-delete prevention path is
/// covered by the in-crate unit tests.
#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn sync_start_rescues_wallet_stuck_by_orphaned_historical_scan_range() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    // A normal, recent-birthday wallet, funded and synced to the tip.
    let birthday = current_tip_height();
    let (main_dir, wallet) = create_wallet_with_birthday("Primary", Some(birthday));
    let main_db = main_dir.path().join("zcash_wallet.db");
    fund_wallet(&wallet.unified_address, "1.0");
    mine_blocks(10);
    sync_wallet(&main_db);

    let balance_before = get_balance(&main_db, &wallet.account_uuid);
    assert!(
        balance_before.spendable >= 100_000_000,
        "primary should hold its funds before the rescue, got {}",
        balance_before.spendable
    );

    let h = min_account_birthday(&main_db);
    assert!(
        h > 1,
        "test needs a birthday above genesis to have a sub-birthday range, got {h}"
    );

    // Simulate the pre-fix stuck state: an orphaned pending Historic range below
    // the surviving birthday that no account needs.
    let flipped = inject_orphaned_historic_below(&main_db, h);
    assert!(
        flipped >= 1,
        "expected to inject at least one orphaned historic range below birthday {h}"
    );
    assert!(
        has_pending_scan_below(&main_db, h),
        "sanity: the injected orphan must be present before the rescue sync"
    );

    // The sync-start rescue hook must demote the orphan on the next sync.
    sync_wallet(&main_db);

    assert!(
        !has_pending_scan_below(&main_db, h),
        "sync start must prune the orphaned historical scan range below the birthday"
    );
    let balance_after = get_balance(&main_db, &wallet.account_uuid);
    assert_eq!(
        balance_after.spendable, balance_before.spendable,
        "the rescue prune must not disturb the wallet balance"
    );
}

/// VZR-89 regression (real-device #272 retest): import an old-birthday account
/// on a build WITHOUT the fix, partially sync, delete it, then open a build WITH
/// the fix. The deleted account leaves a `Scanned` range below the surviving
/// birthday; librustzcash's `block_fully_scanned` keys off that leftover Scanned
/// range and, with the Ignored gap above it, pins the fully-scanned height there
/// — `ensure_complete_scan_state` then blocks completion forever
/// ("fully scanned height N below wallet DB chain tip"). The rescue prune must
/// demote the leftover Scanned range so sync completes.
///
/// Regtest fully scans its short chain (so a real partial scan can't be left
/// behind), so we inject the leftover Scanned-below-birthday state directly and
/// then drive the real sync entry point: without the fix `sync_wallet` errors
/// at completion and panics; with the fix it completes.
#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn sync_completes_when_deleted_account_left_scanned_range_below_birthday() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let birthday = current_tip_height();
    let (main_dir, wallet) = create_wallet_with_birthday("Primary", Some(birthday));
    let main_db = main_dir.path().join("zcash_wallet.db");
    fund_wallet(&wallet.unified_address, "1.0");
    mine_blocks(10);
    sync_wallet(&main_db);

    let balance_before = get_balance(&main_db, &wallet.account_uuid);
    assert!(
        balance_before.spendable >= 100_000_000,
        "primary should hold its funds before the retest, got {}",
        balance_before.spendable
    );

    let h = min_account_birthday(&main_db);
    assert!(h > 2, "need room for a sub-birthday range, got {h}");

    // Plant a leftover Scanned range below the birthday + an Ignored gap, exactly
    // the shape a partially-synced-then-deleted old-birthday account leaves.
    inject_orphaned_scanned_below(&main_db, h);

    // Drive the real sync entry point. Without the fix this returns a
    // "fully scanned height ... below wallet DB chain tip" error and the
    // `.expect` inside `sync_wallet` panics, failing the test.
    sync_wallet(&main_db);

    // Sync completed cleanly, no Scanned range left below the birthday, balance
    // intact.
    assert!(
        !has_pending_scan_below(&main_db, h),
        "no pending coverage should remain below the birthday after the rescue",
    );
    let balance_after = get_balance(&main_db, &wallet.account_uuid);
    assert_eq!(
        balance_after.spendable, balance_before.spendable,
        "the rescue prune must not disturb the wallet balance",
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn adding_second_account_after_tip_sync_recovers_historical_and_future_funds() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, first_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");

    fund_wallet(&first_wallet.unified_address, "1.1");
    sync_wallet(&main_db);
    let first_before = get_balance(&main_db, &first_wallet.account_uuid);
    assert!(
        first_before.spendable >= 110_000_000,
        "primary account should have its initial funds, got {}",
        first_before.spendable
    );

    let historical_birthday = current_tip_height();
    let (_external_dir, external_wallet) = create_wallet("Secondary Source");
    fund_wallet(&external_wallet.unified_address, "0.7");
    mine_blocks(20);

    sync_wallet(&main_db);
    let first_after_catchup = get_balance(&main_db, &first_wallet.account_uuid);
    assert_eq!(
        first_after_catchup.spendable, first_before.spendable,
        "syncing past the second account's receive height should not affect the first account"
    );

    let second_account = add_account_with_birthday(
        &main_db,
        "Secondary",
        &external_wallet.mnemonic,
        Some(historical_birthday),
    );
    let accounts = list_accounts(&main_db);
    assert_eq!(accounts.len(), 2, "wallet should now contain two accounts");

    sync_wallet(&main_db);

    let second_after_historical = get_balance(&main_db, &second_account.account_uuid);
    assert!(
        second_after_historical.spendable >= 70_000_000,
        "second account should recover historical funds after being added, got {}",
        second_after_historical.spendable
    );

    let first_after_add = get_balance(&main_db, &first_wallet.account_uuid);
    assert_eq!(
        first_after_add.spendable, first_before.spendable,
        "adding a second account must not disturb the first account balance"
    );

    fund_wallet(&first_wallet.unified_address, "0.4");
    fund_wallet(&second_account.unified_address, "0.6");

    sync_wallet(&main_db);

    let first_final = get_balance(&main_db, &first_wallet.account_uuid);
    let second_final = get_balance(&main_db, &second_account.account_uuid);

    assert!(
        first_final.spendable >= first_before.spendable + 40_000_000,
        "first account should pick up new funds after multi-account sync, got {}",
        first_final.spendable
    );
    assert!(
        second_final.spendable >= second_after_historical.spendable + 60_000_000,
        "second account should pick up both historical and new funds, got {}",
        second_final.spendable
    );

    let second_history = get_transaction_history(&main_db, &second_account.account_uuid);
    let inbound_count = second_history
        .iter()
        .filter(|tx| tx.account_balance_delta > 0)
        .count();
    assert!(
        inbound_count >= 2,
        "second account should show both historical and new inbound transactions, got {}",
        inbound_count
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn late_added_account_with_tip_birthday_still_recovers_historical_funds() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, first_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");
    sync_wallet(&main_db);

    let (_external_dir, external_wallet) = create_wallet("Future Birthday Source");
    fund_wallet(&external_wallet.unified_address, "0.9");
    mine_blocks(12);
    let too_new_birthday = current_tip_height();

    let second_account = add_account_with_birthday(
        &main_db,
        "Tip Birthday",
        &external_wallet.mnemonic,
        Some(too_new_birthday),
    );

    sync_wallet(&main_db);
    let before_balance = get_balance(&main_db, &second_account.account_uuid);
    assert!(
        before_balance.spendable >= 90_000_000,
        "account added at tip birthday should still recover historical funds in the current add_account flow"
    );

    fund_wallet(&second_account.unified_address, "0.5");
    sync_wallet(&main_db);

    let after_balance = get_balance(&main_db, &second_account.account_uuid);
    assert!(
        after_balance.spendable >= before_balance.spendable + 50_000_000,
        "account should recover both historical and post-add receives"
    );
    let first_balance = get_balance(&main_db, &first_wallet.account_uuid);
    assert_eq!(
        first_balance.spendable, 0,
        "late-added second account activity must not leak into first account balance"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn two_new_accounts_added_before_single_sync_are_both_recovered() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, _primary_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");
    sync_wallet(&main_db);

    let birthday = current_tip_height();
    let (_second_source_dir, second_source_wallet) = create_wallet("Second Source");
    let (_third_source_dir, third_source_wallet) = create_wallet("Third Source");

    fund_wallet(&second_source_wallet.unified_address, "0.8");
    fund_wallet(&third_source_wallet.unified_address, "0.6");
    mine_blocks(15);

    let second_account = add_account_with_birthday(
        &main_db,
        "Second",
        &second_source_wallet.mnemonic,
        Some(birthday),
    );
    let third_account = add_account_with_birthday(
        &main_db,
        "Third",
        &third_source_wallet.mnemonic,
        Some(birthday),
    );

    sync_wallet(&main_db);

    let accounts = list_accounts(&main_db);
    assert_eq!(accounts.len(), 3, "wallet should contain three accounts");
    assert_eq!(
        unique_account_uuids(&accounts),
        3,
        "all listed account UUIDs should stay unique after adding two accounts"
    );

    let second_balance = get_balance(&main_db, &second_account.account_uuid);
    let third_balance = get_balance(&main_db, &third_account.account_uuid);
    assert!(
        second_balance.spendable >= 80_000_000,
        "single sync should recover second account funds"
    );
    assert!(
        third_balance.spendable >= 60_000_000,
        "single sync should recover third account funds"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn existing_account_history_is_unchanged_when_new_account_is_added() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, first_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");
    fund_wallet(&first_wallet.unified_address, "0.5");
    fund_wallet(&first_wallet.unified_address, "0.4");
    sync_wallet(&main_db);

    let first_history_before = get_transaction_history(&main_db, &first_wallet.account_uuid);
    let first_txids_before = history_txids(&first_history_before);
    let first_positive_before = positive_history_count(&first_history_before);

    let birthday = current_tip_height();
    let (_external_dir, external_wallet) = create_wallet("Secondary Source");
    fund_wallet(&external_wallet.unified_address, "0.7");
    mine_blocks(12);

    let second_account = add_account_with_birthday(
        &main_db,
        "Secondary",
        &external_wallet.mnemonic,
        Some(birthday),
    );
    sync_wallet(&main_db);

    let first_history_after = get_transaction_history(&main_db, &first_wallet.account_uuid);
    let first_txids_after = history_txids(&first_history_after);
    let first_positive_after = positive_history_count(&first_history_after);
    let second_balance = get_balance(&main_db, &second_account.account_uuid);

    assert_eq!(
        first_txids_before, first_txids_after,
        "adding a new account must not rewrite the first account history ordering"
    );
    assert_eq!(
        first_positive_before, first_positive_after,
        "adding a new account must not change the first account inbound history count"
    );
    assert!(
        second_balance.spendable >= 70_000_000,
        "new account should still recover its own historical funds"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn multi_account_sync_keeps_balances_isolated_per_account() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, first_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");
    let birthday = current_tip_height();
    let (_second_source_dir, second_source_wallet) = create_wallet("Secondary Source");

    let second_account = add_account_with_birthday(
        &main_db,
        "Secondary",
        &second_source_wallet.mnemonic,
        Some(birthday),
    );

    fund_wallet(&first_wallet.unified_address, "0.55");
    fund_wallet(&second_account.unified_address, "0.85");
    sync_wallet(&main_db);

    let first_balance = get_balance(&main_db, &first_wallet.account_uuid);
    let second_balance = get_balance(&main_db, &second_account.account_uuid);
    assert!(
        first_balance.spendable >= 55_000_000 && first_balance.spendable < 85_000_000,
        "first account balance should reflect only first-account funding, got {}",
        first_balance.spendable
    );
    assert!(
        second_balance.spendable >= 85_000_000,
        "second account balance should reflect only second-account funding, got {}",
        second_balance.spendable
    );

    let first_history = get_transaction_history(&main_db, &first_wallet.account_uuid);
    let second_history = get_transaction_history(&main_db, &second_account.account_uuid);
    assert_eq!(
        positive_history_count(&first_history),
        1,
        "first account should record exactly one inbound transaction"
    );
    assert_eq!(
        positive_history_count(&second_history),
        1,
        "second account should record exactly one inbound transaction"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn repeated_sync_is_idempotent_for_multi_account_wallet() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, first_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");
    let birthday = current_tip_height();
    let (_second_source_dir, second_source_wallet) = create_wallet("Secondary Source");
    let second_account = add_account_with_birthday(
        &main_db,
        "Secondary",
        &second_source_wallet.mnemonic,
        Some(birthday),
    );

    fund_wallet(&first_wallet.unified_address, "0.45");
    fund_wallet(&second_account.unified_address, "0.65");
    sync_wallet(&main_db);

    let first_balance_before = get_balance(&main_db, &first_wallet.account_uuid);
    let second_balance_before = get_balance(&main_db, &second_account.account_uuid);
    let first_history_before = get_transaction_history(&main_db, &first_wallet.account_uuid);
    let second_history_before = get_transaction_history(&main_db, &second_account.account_uuid);

    sync_wallet(&main_db);
    sync_wallet(&main_db);

    let first_balance_after = get_balance(&main_db, &first_wallet.account_uuid);
    let second_balance_after = get_balance(&main_db, &second_account.account_uuid);
    let first_history_after = get_transaction_history(&main_db, &first_wallet.account_uuid);
    let second_history_after = get_transaction_history(&main_db, &second_account.account_uuid);

    assert_eq!(
        first_balance_before.spendable, first_balance_after.spendable,
        "repeated sync without new blocks must not change first account balance"
    );
    assert_eq!(
        second_balance_before.spendable, second_balance_after.spendable,
        "repeated sync without new blocks must not change second account balance"
    );
    assert_eq!(
        history_txids(&first_history_before),
        history_txids(&first_history_after),
        "repeated sync without new blocks must not duplicate first account history"
    );
    assert_eq!(
        history_txids(&second_history_before),
        history_txids(&second_history_after),
        "repeated sync without new blocks must not duplicate second account history"
    );
}
