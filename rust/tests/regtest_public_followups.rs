//! Public mode's post-sync follow-ups on a real chain. With private queries
//! off, a sync reports `Completed`, then keeps running follow-ups (transparent
//! details through public lookups, the inactive-account refresh, ephemeral
//! address checks) before its stream ends. Those follow-ups may make a
//! transaction's details richer, but must not change what the wallet already
//! showed when it reported completion: balances, and each history row's
//! direction, amount, account movement and height.

// The sync future nests deeply enough to exceed the default layout depth.
#![recursion_limit = "256"]

mod common;

use std::sync::{
    atomic::{AtomicBool, AtomicU8},
    Arc, Mutex,
};

use common::{
    create_wallet, ensure_regtest_up, exclusive_regtest, path_str, run_script, LIGHTWALLETD_URL,
    REGTEST_NETWORK,
};
use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};
use rust_lib_zcash_wallet::wallet::network::WalletNetwork;
use rust_lib_zcash_wallet::wallet::sync_engine::{run_sync_inner, SyncEventKind};

/// What the wallet shows that a follow-up must not change: the balances, and
/// per history row its direction, amount, movement and height.
#[derive(Debug, PartialEq, Eq)]
struct Shown {
    transparent: u64,
    total: u64,
    rows: Vec<(String, String, u64, i64, u64)>,
}

fn shown(db_path: &str, account_uuid: &str) -> Shown {
    let balance =
        sync_api::get_balance(db_path.into(), REGTEST_NETWORK.into(), account_uuid.into())
            .expect("get_balance");
    let mut rows: Vec<_> = sync_api::get_transaction_history(
        db_path.into(),
        REGTEST_NETWORK.into(),
        Some(50),
        account_uuid.into(),
    )
    .expect("get_transaction_history")
    .into_iter()
    .map(|row| {
        (
            row.txid_hex,
            row.tx_kind,
            row.display_amount,
            row.account_balance_delta,
            row.mined_height,
        )
    })
    .collect();
    rows.sort();
    Shown {
        transparent: balance.transparent,
        total: balance.total,
        rows,
    }
}

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn public_followups_change_no_balance_or_movement_shown_at_completion() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (tempdir, wallet) = create_wallet("Public follow-ups");
    let db = tempdir.path().join("zcash_wallet.db");
    let db_path = path_str(&db);
    let taddr = wallet_api::get_transparent_receive_address(
        db_path.clone(),
        REGTEST_NETWORK.into(),
        Some(wallet.account_uuid.clone()),
    )
    .expect("a transparent receive address");

    // Two transparent receives from the shielded faucet: public discovery
    // finds their outputs without the transactions' bytes, which the details
    // follow-up then looks up.
    for amount in ["0.5", "0.25"] {
        let txid = run_script("fund-wallet.sh", &[&taddr, amount, "3"]);
        println!("funded {taddr} with {amount}: {txid}");
    }

    let at_completion: Arc<Mutex<Option<Shown>>> = Arc::default();
    let completions = Arc::new(Mutex::new(0usize));
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let result = {
        let at_completion = at_completion.clone();
        let completions = completions.clone();
        let (db_path, uuid) = (db_path.clone(), wallet.account_uuid.clone());
        runtime.block_on(run_sync_inner(
            &db_path.clone(),
            LIGHTWALLETD_URL,
            WalletNetwork::Regtest,
            Arc::new(AtomicBool::new(false)),
            1,
            &AtomicU8::new(1),
            None,
            true,
            move |event| {
                if event.kind == SyncEventKind::Completed {
                    let mut count = completions.lock().unwrap();
                    *count += 1;
                    if *count == 1 {
                        *at_completion.lock().unwrap() = Some(shown(&db_path, &uuid));
                    }
                }
            },
        ))
    };
    result.expect("the sync and its follow-ups complete");

    let at_completion = at_completion
        .lock()
        .unwrap()
        .take()
        .expect("the sync reported completion before its stream ended");
    assert_eq!(
        at_completion.transparent, 75_000_000,
        "both transparent receives counted at completion: {at_completion:?}"
    );
    let at_end = shown(&db_path, &wallet.account_uuid);
    assert_eq!(
        at_end, at_completion,
        "a follow-up changed a balance or a movement shown at completion"
    );
}
