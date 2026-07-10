//! Standalone sync performance benchmark harness.
//!
//! Drives the real sync engine (`run_sync_inner`) against mainnet lightwalletd,
//! with a dev mnemonic and a fixed birthday, so we can measure cold-start sync
//! wall-clock time and iterate on performance WITHOUT running the Flutter app.
//!
//! Usage:
//!   cargo run --release --example sync_bench                 # single account
//!   SCENARIO=multi cargo run --release --example sync_bench  # 2 accounts
//!
//! Env overrides:
//!   SCENARIO   = single | multi           (default: single)
//!   BIRTHDAY   = <height>                  (default: 3346523)
//!   LWD_URL    = <url>                     (default: mainnet stardust)
//!   NETWORK    = main | test | regtest     (default: main)
//!   LABEL      = free-form tag for the JSON summary (default: SCENARIO)
//!
//! Emits a single-line JSON summary to stdout prefixed with `BENCH_RESULT `.
//! All engine logs go to stderr.

use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::Arc;
use std::time::Instant;

use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};
use rust_lib_zcash_wallet::wallet::keys;
use rust_lib_zcash_wallet::wallet::sync_engine;

// Canonical 24-word BIP39 test vector (public knowledge, zero secrecy),
// used only for the optional 2nd account in the `multi` scenario.
const SECONDARY_MNEMONIC: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";

/// The benchmark wallet's mnemonic comes from the environment — NEVER
/// hardcode a mnemonic in this file, even a throwaway dev one. The file is
/// committed; an accidentally pushed mnemonic is unrecoverable.
fn primary_mnemonic() -> String {
    std::env::var("BENCH_MNEMONIC").unwrap_or_else(|_| {
        eprintln!(
            "BENCH_MNEMONIC is not set.\n\
             Export the benchmark wallet's 24-word mnemonic first, e.g.:\n\
             BENCH_MNEMONIC=\"word1 word2 ...\" cargo run --release --example sync_bench\n\
             Use a throwaway dev wallet whose on-chain history matches the\n\
             BIRTHDAY you pass; results are only comparable on the same wallet."
        );
        std::process::exit(2);
    })
}

const DEFAULT_BIRTHDAY: u64 = 3346523;
const DEFAULT_LWD_URL: &str = "https://us.zec.stardust.rest:443";
const DEFAULT_NETWORK: &str = "main";

/// Minimal stderr logger so we see the engine's per-batch timing logs.
struct StderrLogger;
impl log::Log for StderrLogger {
    fn enabled(&self, m: &log::Metadata) -> bool {
        m.level() <= log::Level::Info
    }
    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            eprintln!("[{}] {}", record.level(), record.args());
        }
    }
    fn flush(&self) {}
}
static LOGGER: StderrLogger = StderrLogger;

fn env_or<'a>(key: &str, default: &'a str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn main() {
    let _ = log::set_logger(&LOGGER);
    log::set_max_level(log::LevelFilter::Info);
    // rustls 0.23 needs an explicit crypto provider before the first TLS handshake.
    let _ = rustls::crypto::ring::default_provider().install_default();

    let scenario = env_or("SCENARIO", "single");
    let label = env_or("LABEL", &scenario);
    let birthday: u64 = env_or("BIRTHDAY", &DEFAULT_BIRTHDAY.to_string())
        .parse()
        .expect("BIRTHDAY must be a u64");
    let lwd_url = env_or("LWD_URL", DEFAULT_LWD_URL);
    let network = env_or("NETWORK", DEFAULT_NETWORK);

    // Fresh temp DB per run — always a cold sync from `birthday`.
    let tempdir = tempfile::tempdir().expect("tempdir");
    let db_path = tempdir.path().join("zcash_wallet.db");
    let db_path_str = db_path.to_str().unwrap().to_string();

    eprintln!("=== sync_bench: scenario={scenario} birthday={birthday} network={network} url={lwd_url} ===");

    // --- Account setup -------------------------------------------------------
    let import = wallet_api::import_wallet(
        primary_mnemonic(),
        Some(birthday),
        network.clone(),
        db_path_str.clone(),
        Some("Account 1".into()),
    )
    .expect("import_wallet (account 1)");
    eprintln!("account 1 uuid={}", import.account_uuid);

    if scenario == "multi" {
        let add = wallet_api::add_account(
            db_path_str.clone(),
            network.clone(),
            "Account 2".into(),
            SECONDARY_MNEMONIC.into(),
            Some(birthday),
        )
        .expect("add_account (account 2)");
        eprintln!("account 2 uuid={}", add.account_uuid);
    }

    let accounts =
        wallet_api::list_accounts(db_path_str.clone(), network.clone()).expect("list_accounts");
    eprintln!("accounts: {}", accounts.len());

    // --- Run the real sync engine, timed -------------------------------------
    let wallet_network = keys::parse_network(&network).expect("parse_network");
    let cancel = Arc::new(AtomicBool::new(false));
    let desired_mode = AtomicU8::new(1); // foreground
    let running_mode = 1u8;

    // Phase accounting from progress events.
    let events = Arc::new(AtomicU64::new(0));
    let last_scanned = Arc::new(AtomicU64::new(0));
    let last_tip = Arc::new(AtomicU64::new(0));
    let events_cb = events.clone();
    let last_scanned_cb = last_scanned.clone();
    let last_tip_cb = last_tip.clone();

    let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
    let start = Instant::now();
    let result = rt.block_on(async {
        sync_engine::run_sync_inner(
            &db_path_str,
            &lwd_url,
            wallet_network,
            cancel,
            running_mode,
            &desired_mode,
            move |ev| {
                events_cb.fetch_add(1, Ordering::Relaxed);
                last_scanned_cb.store(ev.scanned_height, Ordering::Relaxed);
                last_tip_cb.store(ev.chain_tip_height, Ordering::Relaxed);
            },
        )
        .await
    });
    let elapsed = start.elapsed();

    if let Err(e) = &result {
        eprintln!("SYNC FAILED: {e}");
    }

    let scanned = last_scanned.load(Ordering::Relaxed);
    let tip = last_tip.load(Ordering::Relaxed);
    let blocks = tip.saturating_sub(birthday);

    // --- Balances ------------------------------------------------------------
    let mut balances = Vec::new();
    for acct in &accounts {
        if let Ok(bal) =
            sync_api::get_balance(db_path_str.clone(), network.clone(), acct.uuid.clone())
        {
            balances.push(format!(
                "{{\"uuid\":\"{}\",\"total\":{},\"spendable\":{}}}",
                acct.uuid, bal.total, bal.spendable
            ));
        }
    }

    let secs = elapsed.as_secs_f64();
    let bps = if secs > 0.0 {
        blocks as f64 / secs
    } else {
        0.0
    };

    // Machine-readable summary line.
    println!(
        "BENCH_RESULT {{\"label\":\"{label}\",\"scenario\":\"{scenario}\",\"ok\":{},\
\"birthday\":{birthday},\"tip\":{tip},\"scanned\":{scanned},\"blocks\":{blocks},\
\"accounts\":{},\"events\":{},\"elapsed_s\":{:.2},\"blocks_per_s\":{:.1},\"balances\":[{}]}}",
        result.is_ok(),
        accounts.len(),
        events.load(Ordering::Relaxed),
        secs,
        bps,
        balances.join(","),
    );

    eprintln!(
        "=== DONE: {:.2}s, {} blocks, {:.1} blocks/s, ok={} ===",
        secs,
        blocks,
        bps,
        result.is_ok()
    );
}
