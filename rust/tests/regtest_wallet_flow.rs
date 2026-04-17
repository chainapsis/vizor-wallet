mod common;

use common::{
    create_wallet, ensure_regtest_up, fund_wallet, get_balance, get_transaction_history,
    mine_blocks, sapling_params, sync_wallet, LIGHTWALLETD_URL, REGTEST_NETWORK,
};
use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn create_wallet_receives_funds_and_syncs_balance() {
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
