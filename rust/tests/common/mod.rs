use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{LazyLock, Mutex, MutexGuard};

use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};
use tempfile::TempDir;
use uuid::Uuid;

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
    match REGTEST_LOCK.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
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
    fund_wallet_with_confirmations(unified_address, amount_zec, 10)
}

pub fn fund_wallet_with_confirmations(
    unified_address: &str,
    amount_zec: &str,
    confirming_blocks: u32,
) -> String {
    run_script(
        "fund-wallet.sh",
        &[unified_address, amount_zec, &confirming_blocks.to_string()],
    )
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
    sync_api::run_full_sync_blocking(
        path_str(db_path),
        LIGHTWALLETD_URL.into(),
        REGTEST_NETWORK.into(),
        1,
    )
    .expect("run_full_sync_blocking");
}

pub fn get_balance(db_path: &Path, account_uuid: &str) -> sync_api::WalletBalance {
    sync_api::get_balance(
        path_str(db_path),
        REGTEST_NETWORK.into(),
        account_uuid.into(),
    )
    .expect("get_balance")
}

pub fn transparent_receive_address(db_path: &Path, account_uuid: &str) -> String {
    wallet_api::get_transparent_receive_address(
        path_str(db_path),
        REGTEST_NETWORK.into(),
        Some(account_uuid.into()),
    )
    .expect("get_transparent_receive_address")
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

// --- VZR-89 scan_queue helpers (orphaned-range rescue tests) --------------

/// Lowest birthday across surviving accounts — the threshold below which any
/// pending scan range is orphaned.
pub fn min_account_birthday(db_path: &Path) -> i64 {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.query_row("SELECT MIN(birthday_height) FROM accounts", [], |r| {
        r.get(0)
    })
    .expect("min birthday")
}

/// True if any pending (priority > Scanned) scan range starts below `height`.
pub fn has_pending_scan_below(db_path: &Path, height: i64) -> bool {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM scan_queue WHERE block_range_start < ?1 AND priority > 10)",
        [height],
        |r| r.get(0),
    )
    .expect("query scan_queue")
}

/// Simulate a wallet already stuck by a PRE-FIX account deletion: demote the
/// (normally Ignored) sub-birthday range to Historic so it looks like the
/// orphan librustzcash leaves behind after deleting an old-birthday account.
/// Returns the number of rows flipped to Historic.
pub fn inject_orphaned_historic_below(db_path: &Path, height: i64) -> usize {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.execute(
        "UPDATE scan_queue SET priority = 20 WHERE block_range_end <= ?1 AND priority = 0",
        [height],
    )
    .expect("inject orphaned historic range")
}

/// Simulate the harder pre-fix stuck state: a deleted old-birthday account that
/// was only PARTIALLY synced leaves a `Scanned` (priority 10) range below the
/// surviving birthday, followed by an `Ignored` gap up to the birthday. This is
/// the configuration that pins librustzcash's `block_fully_scanned` and blocks
/// sync completion until the rescue prune demotes the leftover Scanned range.
pub fn inject_orphaned_scanned_below(db_path: &Path, birthday: i64) {
    assert!(
        birthday > 2,
        "birthday must leave room for a sub-birthday range"
    );
    let mid = birthday / 2 + 1;
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.execute(
        "DELETE FROM scan_queue WHERE block_range_end <= ?1",
        [birthday],
    )
    .expect("clear sub-birthday ranges");
    conn.execute(
        "INSERT INTO scan_queue (block_range_start, block_range_end, priority) VALUES (1, ?1, 10)",
        [mid],
    )
    .expect("inject leftover scanned range");
    conn.execute(
        "INSERT INTO scan_queue (block_range_start, block_range_end, priority) VALUES (?1, ?2, 0)",
        [mid, birthday],
    )
    .expect("inject ignored gap");
}

pub fn execute_send(
    db_path: &Path,
    sender_account_uuid: &str,
    sender_mnemonic: &str,
    to_address: &str,
    amount_zatoshi: u64,
) -> String {
    execute_send_with_source(
        db_path,
        sender_account_uuid,
        sender_mnemonic,
        to_address,
        amount_zatoshi,
        None,
    )
}

pub fn execute_send_with_source(
    db_path: &Path,
    sender_account_uuid: &str,
    sender_mnemonic: &str,
    to_address: &str,
    amount_zatoshi: u64,
    send_source: Option<&str>,
) -> String {
    let send_flow_id = "regtest-send-flow";
    let proposal = propose_send_with_source(
        db_path,
        sender_account_uuid,
        send_flow_id,
        to_address,
        amount_zatoshi,
        send_source,
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

    sync_api::execute_proposal(
        path_str(db_path),
        LIGHTWALLETD_URL.into(),
        proposal.proposal_id,
        send_flow_id.into(),
        sender_mnemonic.as_bytes().to_vec(),
        sapling_params.as_ref().map(|p| p.spend_path.clone()),
        sapling_params.as_ref().map(|p| p.output_path.clone()),
    )
    .expect("execute_proposal")
    .txids
}

pub fn propose_send_with_source(
    db_path: &Path,
    sender_account_uuid: &str,
    send_flow_id: &str,
    to_address: &str,
    amount_zatoshi: u64,
    send_source: Option<&str>,
) -> Result<sync_api::ProposalResult, String> {
    sync_api::propose_send(
        path_str(db_path),
        REGTEST_NETWORK.into(),
        sender_account_uuid.into(),
        send_flow_id.into(),
        to_address.into(),
        amount_zatoshi,
        None,
        send_source.map(str::to_string),
    )
}

pub fn positive_history_count(history: &[sync_api::TransactionInfo]) -> usize {
    history
        .iter()
        .filter(|tx| tx.account_balance_delta > 0)
        .count()
}

pub fn history_txids(history: &[sync_api::TransactionInfo]) -> Vec<String> {
    history.iter().map(|tx| tx.txid_hex.clone()).collect()
}

pub fn unique_account_uuids(accounts: &[wallet_api::AccountInfo]) -> usize {
    let ids: std::collections::HashSet<Uuid> = accounts
        .iter()
        .map(|a| Uuid::parse_str(&a.uuid).expect("valid account uuid"))
        .collect();
    ids.len()
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
