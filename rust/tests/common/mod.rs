use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU8};
use std::sync::{LazyLock, Mutex, MutexGuard};

use rust_lib_zcash_wallet::{
    api::{sync as sync_api, wallet as wallet_api},
    wallet::{keys, sync_engine},
};
use tempfile::TempDir;

pub const REGTEST_NETWORK: &str = "regtest";
pub const LIGHTWALLETD_URL: &str = "http://127.0.0.1:9067";
static REGTEST_LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

pub struct SaplingParams {
    pub spend_path: String,
    pub output_path: String,
}

pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("rust crate should live under repo root")
        .to_path_buf()
}

pub fn exclusive_regtest() -> MutexGuard<'static, ()> {
    REGTEST_LOCK.lock().expect("regtest mutex poisoned")
}

pub fn regtest_script(name: &str) -> PathBuf {
    repo_root().join("scripts").join("regtest").join(name)
}

pub fn run_script(name: &str, args: &[&str]) -> String {
    let output = Command::new(regtest_script(name))
        .args(args)
        .current_dir(repo_root())
        .output()
        .unwrap_or_else(|e| panic!("failed to run {name}: {e}"));
    if !output.status.success() {
        panic!(
            "{name} failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr),
        );
    }
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

pub fn ensure_regtest_up() {
    if wallet_api::get_latest_block_height(LIGHTWALLETD_URL.into())
        .map(|height| height > 0)
        .unwrap_or(false)
    {
        return;
    }

    run_script("up.sh", &[]);
}

pub fn mine_blocks(blocks: u32) {
    run_script("mine.sh", &[&blocks.to_string()]);
}

pub fn fund_wallet(unified_address: &str, amount_zec: &str) -> String {
    run_script("fund-wallet.sh", &[unified_address, amount_zec, "10"])
}

pub fn current_tip_height() -> u64 {
    wallet_api::get_latest_block_height(LIGHTWALLETD_URL.into())
        .expect("failed to fetch regtest chain tip")
}

pub fn create_wallet(account_name: &str) -> (TempDir, wallet_api::WalletCreationResult) {
    create_wallet_with_birthday(account_name, Some(1))
}

pub fn create_wallet_with_birthday(
    account_name: &str,
    birthday_height: Option<u64>,
) -> (TempDir, wallet_api::WalletCreationResult) {
    let tempdir = tempfile::tempdir().expect("tempdir");
    let db_path = tempdir.path().join("zcash_wallet.db");
    let result = wallet_api::create_wallet(
        REGTEST_NETWORK.into(),
        path_str(&db_path),
        birthday_height,
        Some(account_name.into()),
    )
    .expect("create_wallet");
    (tempdir, result)
}

pub fn import_wallet_with_birthday(
    mnemonic: &str,
    account_name: &str,
    birthday_height: Option<u64>,
) -> (TempDir, wallet_api::WalletImportResult) {
    let tempdir = tempfile::tempdir().expect("tempdir");
    let db_path = tempdir.path().join("zcash_wallet.db");
    let result = wallet_api::import_wallet(
        mnemonic.into(),
        birthday_height,
        REGTEST_NETWORK.into(),
        path_str(&db_path),
        Some(account_name.into()),
    )
    .expect("import_wallet");
    (tempdir, result)
}

pub fn add_account_with_birthday(
    db_path: &Path,
    account_name: &str,
    mnemonic: &str,
    birthday_height: Option<u64>,
) -> wallet_api::AccountCreationResult {
    wallet_api::add_account(
        path_str(db_path),
        REGTEST_NETWORK.into(),
        account_name.into(),
        mnemonic.into(),
        birthday_height,
    )
    .expect("add_account")
}

pub fn list_accounts(db_path: &Path) -> Vec<wallet_api::AccountInfo> {
    wallet_api::list_accounts(path_str(db_path), REGTEST_NETWORK.into()).expect("list_accounts")
}

pub fn sync_wallet(db_path: &Path) {
    let network = keys::parse_network(REGTEST_NETWORK).expect("parse_network(regtest)");
    let cancel = Arc::new(AtomicBool::new(false));
    let desired_mode = AtomicU8::new(1);
    let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
    rt.block_on(async {
        sync_engine::run_sync_inner(
            &path_str(db_path),
            LIGHTWALLETD_URL,
            network,
            cancel,
            1,
            &desired_mode,
            |_| {},
        )
        .await
        .expect("run_sync_inner");
    });
}

pub fn get_balance(db_path: &Path, account_uuid: &str) -> sync_api::WalletBalance {
    sync_api::get_balance(
        path_str(db_path),
        REGTEST_NETWORK.into(),
        account_uuid.into(),
    )
    .expect("get_balance")
}

pub fn get_transaction_history(
    db_path: &Path,
    account_uuid: &str,
) -> Vec<sync_api::TransactionInfo> {
    sync_api::get_transaction_history(
        path_str(db_path),
        REGTEST_NETWORK.into(),
        Some(20),
        account_uuid.into(),
    )
    .expect("get_transaction_history")
}

pub fn path_str(path: &Path) -> String {
    path.to_str().expect("utf-8 path").to_string()
}

pub fn sapling_params() -> Option<SaplingParams> {
    let dir = std::env::var("REGTEST_SAPLING_PARAMS_DIR").ok()?;
    let dir = PathBuf::from(dir);
    let spend_path = dir.join("sapling-spend.params");
    let output_path = dir.join("sapling-output.params");
    if spend_path.is_file() && output_path.is_file() {
        Some(SaplingParams {
            spend_path: path_str(&spend_path),
            output_path: path_str(&output_path),
        })
    } else {
        None
    }
}
