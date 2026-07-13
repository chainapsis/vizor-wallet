mod common;

use common::{
    create_wallet, ensure_regtest_up, exclusive_regtest, fund_wallet, get_balance, run_script,
    sync_wallet,
};

use std::path::Path;

fn wallet_scanned_tip(db_path: &Path) -> (u64, Vec<u8>) {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.query_row(
        "SELECT height, hash FROM blocks ORDER BY height DESC LIMIT 1",
        [],
        |row| Ok((row.get::<_, u64>(0)?, row.get::<_, Vec<u8>>(1)?)),
    )
    .expect("wallet must have a scanned tip")
}

/// A same-height reorg leaves a height-only scan queue empty. Completion must
/// compare the canonical hash, rewind, and replace the wallet's orphaned tip.
#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn same_height_reorg_replaces_wallet_tip_hash() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (wallet_dir, wallet) = create_wallet("SameHeightReorg");
    let wallet_db = wallet_dir.path().join("zcash_wallet.db");

    fund_wallet(&wallet.unified_address, "1.0");
    sync_wallet(&wallet_db);

    let balance_before = get_balance(&wallet_db, &wallet.account_uuid);
    let (height_before, hash_before) = wallet_scanned_tip(&wallet_db);

    run_script("reorg-same-height.sh", &["5"]);
    sync_wallet(&wallet_db);

    let (height_after, hash_after) = wallet_scanned_tip(&wallet_db);
    assert_eq!(
        height_after, height_before,
        "replacement branch must finish at the original height"
    );
    assert_ne!(
        hash_after, hash_before,
        "wallet must replace its stored tip hash after a same-height reorg"
    );

    let balance_after = get_balance(&wallet_db, &wallet.account_uuid);
    assert_eq!(
        balance_after.spendable, balance_before.spendable,
        "a note below the branch point must remain spendable"
    );
}
