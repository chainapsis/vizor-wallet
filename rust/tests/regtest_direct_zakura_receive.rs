//! Unix-only because the private funder handoff requires exact 0700/0600 modes.
#![cfg(unix)]

mod common;
#[path = "support/direct_zakura.rs"]
mod direct_zakura;

use direct_zakura::{
    assert_funding_response, fund_wallet, history_txid_from_rpc, path_string, required_environment,
    AMOUNT_ZATOSHI, NETWORK,
};
use rust_lib_zcash_wallet::api::{simple as simple_api, sync as sync_api, wallet as wallet_api};

#[test]
#[ignore = "requires Unix, direct Zakura/lightwalletd, and an independent external funder"]
fn empty_wallet_receives_exact_ironwood_funding_from_direct_zakura() {
    let environment = required_environment();
    simple_api::configure_regtest_ironwood_activation_height(1)
        .expect("configure wallet NU6.3 activation height");
    let initial_chain =
        wallet_api::get_chain_upgrade_status(environment.lightwalletd_url.clone(), NETWORK.into())
            .expect("query initial direct Zakura chain status");
    assert_eq!(initial_chain.tip_height, environment.initial_tip_height);
    assert_eq!(initial_chain.nu6_3_activation_height, Some(1));
    assert!(initial_chain.ironwood_active_at_tip);

    let tempdir = common::wallet_tempdir();
    let db = path_string(&tempdir.path().join("zcash_wallet.db"));
    let wallet = wallet_api::create_wallet(
        NETWORK.into(),
        db.clone(),
        Some(2),
        Some("Direct Zakura Receive Smoke".into()),
    )
    .expect("create empty regtest wallet");
    let account_uuid = wallet.account_uuid.clone();
    let response = fund_wallet(&environment, &wallet.unified_address);
    drop(wallet);

    let history_txid = assert_funding_response(&response, environment.initial_tip_height);
    let funded_chain =
        wallet_api::get_chain_upgrade_status(environment.lightwalletd_url.clone(), NETWORK.into())
            .expect("query funded direct Zakura chain status");
    assert_eq!(funded_chain.tip_height, response.final_tip_height);

    sync_api::run_full_sync_blocking(db.clone(), environment.lightwalletd_url, NETWORK.into(), 1)
        .expect("sync funded wallet against direct Zakura");
    let status =
        sync_api::get_sync_status(db.clone(), NETWORK.into()).expect("read funded sync status");
    assert!(status.is_complete);
    assert!(!status.is_syncing);
    assert_eq!(status.chain_tip_height, response.final_tip_height);
    assert_eq!(status.scanned_height, response.final_tip_height);

    let balance = sync_api::get_balance(db.clone(), NETWORK.into(), account_uuid.clone())
        .expect("read funded wallet balance");
    assert!(matches!(
        balance.availability,
        sync_api::WalletBalanceAvailability::Available
    ));
    assert_eq!(balance.ironwood, AMOUNT_ZATOSHI);
    assert_eq!(balance.spendable, AMOUNT_ZATOSHI);
    assert_eq!(balance.total, AMOUNT_ZATOSHI);
    assert_eq!(
        [
            balance.transparent,
            balance.sapling,
            balance.orchard,
            balance.transparent_locked,
            balance.sapling_locked,
            balance.orchard_locked,
            balance.ironwood_locked,
            balance.transparent_pending,
            balance.sapling_pending,
            balance.orchard_pending,
            balance.ironwood_pending,
            balance.change_pending_confirmation,
            balance.value_pending_spendability,
            balance.uneconomic_value,
            balance.locked,
        ],
        [0; 15]
    );

    let history = sync_api::get_transaction_history(db, NETWORK.into(), Some(20), account_uuid)
        .expect("read funded wallet transaction history");
    assert_eq!(
        history
            .iter()
            .filter(|transaction| transaction.txid_hex == history_txid)
            .count(),
        1
    );
    let positive = history
        .iter()
        .filter(|transaction| transaction.account_balance_delta > 0)
        .collect::<Vec<_>>();
    assert_eq!(positive.len(), 1);
    let received = positive[0];
    assert_eq!(received.txid_hex, history_txid);
    assert_eq!(received.mined_height, response.mined_height);
    assert_eq!(received.account_balance_delta, AMOUNT_ZATOSHI as i64);
    assert_eq!(received.display_amount, AMOUNT_ZATOSHI);
    assert_eq!(received.tx_kind, "received");
    assert_eq!(received.display_pool, "ironwood");
    assert!(!received.expired_unmined);
}

#[test]
fn rpc_txid_matches_history_protocol_order() {
    let bytes = std::array::from_fn(|index| index as u8);
    let txid = zcash_protocol::TxId::from_bytes(bytes);
    let history_hex = history_txid_from_rpc(&txid.to_string());
    assert_eq!(history_hex, hex::encode(bytes));
    assert_ne!(history_hex, txid.to_string());
}
