mod common;
use common::*;
use rust_lib_zcash_wallet::api::gift_card_tracking as tracking;

/// Explicit opt-in: shares the Docker regtest chain and mines blocks.
#[test]
#[ignore = "requires explicitly requested Docker regtest execution"]
fn observer_scans_multiple_view_only_accounts_and_retires_only_used_card() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();
    let (card_dir, card) = create_wallet("Card");
    let (other_dir, other) = create_wallet("Other card");
    let (_receiver_dir, receiver) = create_wallet("Receiver");
    let observer = tempfile::tempdir().unwrap();
    let observer_path = path_str(&observer.path().join("observer.db"));
    let uuid = tracking::register_gift_card_observer(
        observer_path.clone(),
        "regtest".into(),
        card.mnemonic.as_bytes().to_vec(),
        card.unified_address.clone(),
        1,
    )
    .unwrap();
    fund_wallet(&card.unified_address, "0.5001");
    fund_wallet(&other.unified_address, "0.5001");
    let scan = || {
        tracking::sync_gift_card_observers(
            observer_path.clone(),
            "regtest".into(),
            LIGHTWALLETD_URL.into(),
        )
        .unwrap()
    };
    scan();
    // Add an older birthday after the observer has already scanned the funding.
    let other_uuid = tracking::register_gift_card_observer(
        observer_path.clone(),
        "regtest".into(),
        other.mnemonic.as_bytes().to_vec(),
        other.unified_address.clone(),
        1,
    )
    .unwrap();
    scan();
    let card_db = card_dir.path().join("zcash_wallet.db");
    let other_db = other_dir.path().join("zcash_wallet.db");
    sync_wallet(&card_db);
    sync_wallet(&other_db);
    let funding = get_transaction_history(&card_db, &card.account_uuid)
        .into_iter()
        .find(|tx| tx.account_balance_delta == 50_010_000)
        .unwrap()
        .txid_hex;
    let other_funding = get_transaction_history(&other_db, &other.account_uuid)
        .into_iter()
        .find(|tx| tx.account_balance_delta == 50_010_000)
        .unwrap()
        .txid_hex;
    let inspect = |account: &String, funding: &String| {
        tracking::inspect_gift_card_usage(
            observer_path.clone(),
            account.clone(),
            funding.clone(),
            50_010_000,
        )
        .unwrap()
    };
    assert_eq!(inspect(&uuid, &funding).status, "unused");
    assert_eq!(inspect(&other_uuid, &other_funding).status, "unused");
    execute_send(
        &card_db,
        &card.account_uuid,
        &card.mnemonic,
        &receiver.unified_address,
        50_000_000,
    );
    mine_blocks(1);
    scan();
    assert_eq!(inspect(&uuid, &funding).status, "spendDetected");
    mine_blocks(5);
    scan();
    let evidence = inspect(&uuid, &funding);
    assert_eq!(evidence.status, "used");
    assert!(evidence.can_delete);
    assert_eq!(inspect(&other_uuid, &other_funding).status, "unused");
    tracking::remove_gift_card_observer(observer_path.clone(), "regtest".into(), uuid).unwrap();
    assert_eq!(
        tracking::list_gift_card_observers(observer_path).unwrap(),
        [other_uuid]
    );
}
