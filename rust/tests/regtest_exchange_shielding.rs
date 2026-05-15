mod common;

use common::{
    create_wallet_with_birthday, current_tip_height, ensure_regtest_up, exclusive_regtest,
    fund_wallet_with_confirmations, get_balance, get_transaction_history, mine_blocks, path_str,
    sync_wallet, LIGHTWALLETD_URL, REGTEST_NETWORK,
};
use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn exchange_transparent_address_can_be_shielded_and_confirmed() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let birthday = current_tip_height().saturating_sub(1);
    let (tempdir, wallet) = create_wallet_with_birthday("Exchange Shield", Some(birthday));
    let db_path = tempdir.path().join("zcash_wallet.db");
    let db_path_str = path_str(&db_path);
    sync_wallet(&db_path);
    let exposure_tip = current_tip_height();

    let first = wallet_api::reserve_exchange_transparent_address(
        db_path_str.clone(),
        REGTEST_NETWORK.into(),
        wallet.account_uuid.clone(),
    )
    .expect("reserve first exchange address");
    let second = wallet_api::reserve_exchange_transparent_address(
        db_path_str.clone(),
        REGTEST_NETWORK.into(),
        wallet.account_uuid.clone(),
    )
    .expect("reserve second exchange address");
    assert_ne!(
        first.address, second.address,
        "exchange reservations should rotate"
    );
    assert!(
        first.exposed_at_height > 0 && first.exposed_at_height <= exposure_tip,
        "reserved address should be exposed at a known chain height"
    );

    let funding_txid = fund_wallet_with_confirmations(&first.address, "0.75", 10);
    assert!(!funding_txid.is_empty(), "funding should return a txid");

    sync_wallet(&db_path);

    let first_status = sync_api::get_shield_transparent_address_status(
        db_path_str.clone(),
        REGTEST_NETWORK.into(),
        wallet.account_uuid.clone(),
        first.address.clone(),
    )
    .expect("first address shield status");
    assert!(
        first_status.can_shield,
        "funded exchange address should be shieldable: {}",
        first_status.reason
    );
    assert!(
        first_status.shielded_zatoshi > 0,
        "shielded amount should be positive"
    );
    let expected_shielded = first_status.shielded_zatoshi;

    let second_status = sync_api::get_shield_transparent_address_status(
        db_path_str.clone(),
        REGTEST_NETWORK.into(),
        wallet.account_uuid.clone(),
        second.address.clone(),
    )
    .expect("second address shield status");
    assert!(
        !second_status.can_shield,
        "unfunded exchange address must not be selected for shielding"
    );

    let seed = wallet_api::derive_seed(wallet.mnemonic.clone()).expect("derive seed");
    let shield = sync_api::shield_transparent_address(
        db_path_str.clone(),
        LIGHTWALLETD_URL.into(),
        REGTEST_NETWORK.into(),
        wallet.account_uuid.clone(),
        first.address.clone(),
        seed,
    )
    .expect("shield first exchange address");
    let shield_txid = shield
        .txids
        .split(',')
        .find(|part| !part.trim().is_empty())
        .expect("shield should return a txid")
        .trim()
        .to_string();
    assert_eq!(
        shield.shielded_zatoshi, expected_shielded,
        "broadcast result should match dry-run shield amount"
    );

    let pending_history = get_transaction_history(&db_path, &wallet.account_uuid);
    assert!(
        pending_history.iter().any(|tx| {
            txid_matches_history(&tx.txid_hex, &shield_txid)
                && tx.tx_kind == "shielded"
                && tx.display_amount == expected_shielded
                && tx.mined_height == 0
                && !tx.expired_unmined
        }),
        "shield tx should be recorded as pending history; txid={shield_txid:?} history={}",
        history_summary(&pending_history)
    );

    mine_blocks(10);
    sync_wallet(&db_path);

    let mined_history = get_transaction_history(&db_path, &wallet.account_uuid);
    assert!(
        mined_history.iter().any(|tx| {
            txid_matches_history(&tx.txid_hex, &shield_txid)
                && tx.tx_kind == "shielded"
                && tx.display_amount == expected_shielded
                && tx.mined_height > 0
                && !tx.expired_unmined
        }),
        "shield tx should be recorded as mined history; txid={shield_txid:?} history={}",
        history_summary(&mined_history)
    );

    let balance = get_balance(&db_path, &wallet.account_uuid);
    assert_eq!(
        balance.transparent, 0,
        "specific exchange shielding should clear transparent balance"
    );
    assert!(
        balance.spendable >= expected_shielded,
        "shielded spendable balance should include the shielded amount"
    );
}

fn txid_matches_history(history_txid: &str, broadcast_txid: &str) -> bool {
    history_txid == broadcast_txid || history_txid == reverse_txid_bytes(broadcast_txid)
}

fn reverse_txid_bytes(txid: &str) -> String {
    if txid.len() != 64 || !txid.bytes().all(|b| b.is_ascii_hexdigit()) {
        return txid.to_string();
    }
    (0..txid.len())
        .step_by(2)
        .map(|i| &txid[i..i + 2])
        .rev()
        .collect::<Vec<_>>()
        .join("")
}

fn history_summary(history: &[sync_api::TransactionInfo]) -> String {
    history
        .iter()
        .map(|tx| {
            format!(
                "{}:{}:{}:mined={}:expired={}",
                tx.txid_hex, tx.tx_kind, tx.display_amount, tx.mined_height, tx.expired_unmined
            )
        })
        .collect::<Vec<_>>()
        .join(", ")
}
