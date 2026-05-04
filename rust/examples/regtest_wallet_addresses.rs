use rust_lib_zcash_wallet::api::wallet;
use serde_json::json;

fn main() {
    let mnemonic = std::env::args()
        .nth(1)
        .expect("usage: cargo run --example regtest_wallet_addresses -- <mnemonic>");

    let tempdir = tempfile::tempdir().expect("tempdir");
    let db_path = tempdir.path().join("zcash_wallet.db");
    let db_path = db_path.to_str().expect("utf-8 db path").to_string();

    let result = wallet::import_wallet(
        mnemonic,
        Some(1),
        "regtest".to_string(),
        db_path.clone(),
        Some("E2E Account".to_string()),
    )
    .expect("import regtest wallet");

    let transparent_address = wallet::get_transparent_address(
        db_path,
        "regtest".to_string(),
        Some(result.account_uuid.clone()),
    )
    .expect("transparent address");

    println!(
        "{}",
        json!({
            "accountUuid": result.account_uuid,
            "unifiedAddress": result.unified_address,
            "transparentAddress": transparent_address,
        })
    );
}
