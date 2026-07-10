mod common;

use common::{
    create_wallet, ensure_regtest_up, exclusive_regtest, execute_send, fund_wallet, get_balance,
    mine_blocks, run_script, sync_wallet,
};

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
