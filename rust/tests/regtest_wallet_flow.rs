mod common;

use common::{
    add_account_with_birthday, create_wallet, current_tip_height, ensure_regtest_up,
    exclusive_regtest, fund_wallet, get_balance, get_transaction_history,
    import_wallet_with_birthday, list_accounts, mine_blocks, sapling_params, sync_wallet,
    LIGHTWALLETD_URL, REGTEST_NETWORK,
};
use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn create_wallet_receives_funds_and_syncs_balance() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (tempdir, wallet) = create_wallet("Regtest Account");
    let db_path = tempdir.path().join("zcash_wallet.db");
    println!("wallet ua={}", wallet.unified_address);

    let txid = fund_wallet(&wallet.unified_address, "1.0");
    assert!(!txid.is_empty(), "funding should return a txid");
    println!("funding txid={txid}");

    sync_wallet(&db_path);

    let balance = get_balance(&db_path, &wallet.account_uuid);
    println!(
        "post-sync balance spendable={} total={} orchard={} sapling={} transparent={}",
        balance.spendable, balance.total, balance.orchard, balance.sapling, balance.transparent
    );
    assert!(
        balance.spendable >= 100_000_000,
        "expected at least 1 ZEC after funding, got spendable={} total={}",
        balance.spendable,
        balance.total
    );

    let history = get_transaction_history(&db_path, &wallet.account_uuid);
    assert!(
        history.iter().any(|tx| tx.account_balance_delta > 0),
        "expected a positive receive in transaction history"
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

    let proposal = sync_api::propose_send(
        sender_db.to_str().unwrap().into(),
        REGTEST_NETWORK.into(),
        sender_wallet.account_uuid.clone(),
        receiver_wallet.unified_address.clone(),
        50_000_000,
        None,
    )
    .expect("propose_send");

    let sapling_params = if proposal.needs_sapling_params {
        Some(
            sapling_params().expect(
                "proposal needs Sapling params, but REGTEST_SAPLING_PARAMS_DIR is missing or incomplete",
            ),
        )
    } else {
        None
    };

    let seed = wallet_api::derive_seed(sender_wallet.mnemonic.clone()).expect("derive_seed");
    let txid = sync_api::execute_proposal(
        sender_db.to_str().unwrap().into(),
        LIGHTWALLETD_URL.into(),
        proposal.proposal_id,
        seed,
        sapling_params.as_ref().map(|p| p.spend_path.clone()),
        sapling_params.as_ref().map(|p| p.output_path.clone()),
    )
    .expect("execute_proposal");
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
        receiver_history.iter().any(|tx| tx.account_balance_delta > 0),
        "receiver should record an inbound transaction"
    );
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn import_wallet_with_historical_birthday_recovers_existing_funds() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let historical_birthday = current_tip_height();
    let (_source_dir, source_wallet) = create_wallet("Import Source");

    fund_wallet(&source_wallet.unified_address, "1.4");
    mine_blocks(15);

    let (imported_dir, imported_wallet) = import_wallet_with_birthday(
        &source_wallet.mnemonic,
        "Imported Account",
        Some(historical_birthday),
    );
    let imported_db = imported_dir.path().join("zcash_wallet.db");

    sync_wallet(&imported_db);

    let balance = get_balance(&imported_db, &imported_wallet.account_uuid);
    assert!(
        balance.spendable >= 140_000_000,
        "imported wallet should recover historical funds, got {}",
        balance.spendable
    );

    let accounts = list_accounts(&imported_db);
    assert_eq!(accounts.len(), 1, "imported wallet should expose one account");
    assert_eq!(accounts[0].uuid, imported_wallet.account_uuid);

    let history = get_transaction_history(&imported_db, &imported_wallet.account_uuid);
    assert!(
        history.iter().any(|tx| tx.account_balance_delta > 0),
        "imported wallet should show an inbound historical transaction"
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
