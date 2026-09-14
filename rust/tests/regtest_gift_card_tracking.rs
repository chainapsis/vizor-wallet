mod common;
use common::*;
use rust_lib_zcash_wallet::api::gift_card_tracking as tracking;

/// Explicit opt-in: shares the Docker regtest chain and mines blocks.
#[test]
#[ignore = "requires explicitly requested Docker regtest execution"]
fn observer_scans_multiple_view_only_accounts_and_retires_only_used_card() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();
    let birthday = current_tip_height();
    assert!(birthday > 1);
    let (card_dir, card) = create_wallet_with_birthday("Card", Some(birthday));
    let (other_dir, other) = create_wallet_with_birthday("Other card", Some(birthday - 1));
    let (_receiver_dir, receiver) = create_wallet("Receiver");
    let observer = tempfile::tempdir().unwrap();
    let observer_path = path_str(&observer.path().join("observer.db"));
    let uuid = tracking::register_gift_card_observer(
        observer_path.clone(),
        "regtest".into(),
        card.mnemonic.as_bytes().to_vec(),
        card.unified_address.clone(),
        birthday,
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
        birthday - 1,
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

/// Exercises real notes and tree frontiers across an empty observer interval.
#[test]
#[ignore = "requires explicitly requested Docker regtest execution"]
fn observer_reuses_empty_db_without_scanning_idle_gap() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();
    let observer = tempfile::tempdir().unwrap();
    let path = observer.path().join("observer.db");
    let register = |card: &rust_lib_zcash_wallet::api::wallet::WalletCreationResult, birthday| {
        tracking::register_gift_card_observer(
            path_str(&path),
            "regtest".into(),
            card.mnemonic.as_bytes().to_vec(),
            card.unified_address.clone(),
            birthday,
        )
        .unwrap()
    };
    let scan = || {
        tracking::sync_gift_card_observers(
            path_str(&path),
            "regtest".into(),
            LIGHTWALLETD_URL.into(),
        )
        .unwrap()
    };
    let inspect = |uuid: &str, funding: &str| {
        tracking::inspect_gift_card_usage(path_str(&path), uuid.into(), funding.into(), 10_010_000)
            .unwrap()
    };
    let (_receiver_dir, receiver) = create_wallet("Receiver");
    let first_birthday = current_tip_height();
    let (first_dir, first) = create_wallet_with_birthday("First", Some(first_birthday));
    let first_uuid = register(&first, first_birthday);
    let funding = fund_wallet(&first.unified_address, "0.1001");
    scan();
    assert_eq!(inspect(&first_uuid, &funding).status, "unused");
    let first_db = first_dir.path().join("zcash_wallet.db");
    sync_wallet(&first_db);
    execute_send(
        &first_db,
        &first.account_uuid,
        &first.mnemonic,
        &receiver.unified_address,
        10_000_000,
    );
    mine_blocks(1);
    scan();
    assert_eq!(inspect(&first_uuid, &funding).status, "spendDetected");
    assert!(!inspect(&first_uuid, &funding).can_delete);
    mine_blocks(5);
    scan();
    assert_eq!(inspect(&first_uuid, &funding).status, "used");
    assert!(inspect(&first_uuid, &funding).can_delete);
    let old_tip = current_tip_height();
    tracking::remove_gift_card_observer(path_str(&path), "regtest".into(), first_uuid).unwrap();
    assert!(path.exists());
    assert!(tracking::list_gift_card_observers(path_str(&path))
        .unwrap()
        .is_empty());
    let conn = rusqlite::Connection::open(&path).unwrap();
    let retained: u64 = conn
        .query_row("SELECT MAX(height) FROM blocks", [], |r| r.get(0))
        .unwrap();
    assert_eq!(retained, old_tip);
    drop(conn);

    // A real shielded deposit changes the trees while no observer is registered.
    mine_blocks(20);
    let older_birthday = current_tip_height();
    let (_older_dir, older) = create_wallet_with_birthday("Recovered older", Some(older_birthday));
    let older_funding = fund_wallet(&older.unified_address, "0.1001");
    mine_blocks(200);
    let birthday = current_tip_height();
    assert!(birthday > old_tip + 200);
    let (second_dir, second) = create_wallet_with_birthday("Second", Some(birthday));
    let second_uuid = register(&second, birthday);
    let second_funding = fund_wallet(&second.unified_address, "0.1001");
    scan();
    assert_eq!(inspect(&second_uuid, &second_funding).status, "unused");
    let conn = rusqlite::Connection::open(&path).unwrap();
    let gap_blocks: u64 = conn
        .query_row(
            "SELECT COUNT(*) FROM blocks WHERE height > ?1 AND height < ?2",
            rusqlite::params![old_tip, birthday],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(gap_blocks, 0, "observer scanned the idle gap");
    assert_eq!(
        conn.query_row(
            "SELECT COUNT(*) FROM blocks WHERE height=?1",
            [old_tip],
            |r| r.get::<_, u64>(0)
        )
        .unwrap(),
        1
    );
    drop(conn);
    assert!(!has_pending_scan_below(&path, birthday as i64));
    // Another tip update must not bring the idle gap back.
    mine_blocks(1);
    scan();
    let conn = rusqlite::Connection::open(&path).unwrap();
    assert_eq!(
        conn.query_row(
            "SELECT COUNT(*) FROM blocks WHERE height > ?1 AND height < ?2",
            rusqlite::params![old_tip, birthday],
            |r| r.get::<_, u64>(0)
        )
        .unwrap(),
        0
    );
    drop(conn);

    let older_uuid = register(&older, older_birthday);
    scan();
    assert_eq!(inspect(&older_uuid, &older_funding).status, "unused");
    assert_eq!(inspect(&second_uuid, &second_funding).status, "unused");
    assert!(!has_pending_scan_below(&path, older_birthday as i64));
    let second_db = second_dir.path().join("zcash_wallet.db");
    sync_wallet(&second_db);
    execute_send(
        &second_db,
        &second.account_uuid,
        &second.mnemonic,
        &receiver.unified_address,
        10_000_000,
    );
    mine_blocks(6);
    scan();
    let used = inspect(&second_uuid, &second_funding);
    assert_eq!(used.status, "used");
    assert!(used.can_delete);
    tracking::remove_gift_card_observer(path_str(&path), "regtest".into(), second_uuid).unwrap();
    assert_eq!(
        tracking::list_gift_card_observers(path_str(&path)).unwrap(),
        [older_uuid.clone()]
    );
    assert_eq!(inspect(&older_uuid, &older_funding).status, "unused");
}
