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
//!   GIT_SHA    = optional source revision override (default: `git rev-parse HEAD`)
//!
//! Emits a single-line JSON summary to stdout prefixed with `BENCH_RESULT `.
//! All engine logs go to stderr.

use std::collections::BTreeMap;
use std::process::Command;
use std::sync::atomic::{AtomicBool, AtomicU8};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};
use rust_lib_zcash_wallet::wallet::keys;
use rust_lib_zcash_wallet::wallet::sync_engine;
use serde::Serialize;
use serde_json::{json, Value};
use tonic::transport::{ClientTlsConfig, Endpoint};
use zcash_client_backend::proto::service::{
    compact_tx_streamer_client::CompactTxStreamerClient, ChainSpec,
};

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

#[derive(Debug, Serialize)]
struct TipAnchor {
    height: u64,
    /// The lightwalletd `BlockId.hash` bytes, encoded without changing byte order.
    hash_hex: String,
}

#[derive(Debug, Default)]
struct ProgressStats {
    events: u64,
    phase_counts: BTreeMap<String, u64>,
    first_scanned: Option<u64>,
    last_scanned: u64,
    last_tip: u64,
    last_is_complete: bool,
    complete_events: u64,
    pending_download_start: Option<u64>,
    /// Sum of each observed scan batch's end-minus-start delta. Unlike the
    /// chain span, this includes work repeated after verification or rewind.
    scan_blocks_processed: u64,
}

impl ProgressStats {
    fn observe(&mut self, event: &sync_engine::SyncProgressEvent) {
        self.events += 1;
        let phase = if event.phase.is_empty() {
            if event.is_complete {
                "complete"
            } else {
                "unspecified"
            }
        } else {
            event.phase.as_str()
        };
        *self.phase_counts.entry(phase.to_string()).or_default() += 1;

        self.first_scanned.get_or_insert(event.scanned_height);
        self.last_scanned = event.scanned_height;
        self.last_tip = event.chain_tip_height;
        self.last_is_complete = event.is_complete;
        if event.is_complete {
            self.complete_events += 1;
        }

        match event.phase.as_str() {
            "download" => self.pending_download_start = Some(event.scanned_height),
            "scan" => {
                if let Some(start) = self.pending_download_start.take() {
                    self.scan_blocks_processed = self
                        .scan_blocks_processed
                        .saturating_add(event.scanned_height.saturating_sub(start));
                }
            }
            _ => {}
        }
    }

    fn net_scanned_delta(&self) -> u64 {
        self.first_scanned
            .map(|first| self.last_scanned.saturating_sub(first))
            .unwrap_or(0)
    }
}

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

fn source_revision() -> Option<String> {
    std::env::var("GIT_SHA")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            let output = Command::new("git")
                .args(["rev-parse", "HEAD"])
                .output()
                .ok()?;
            output
                .status
                .success()
                .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
                .filter(|value| !value.is_empty())
        })
}

fn source_is_dirty() -> Option<bool> {
    Command::new("git")
        .args(["status", "--porcelain", "--untracked-files=normal"])
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| !output.stdout.is_empty())
}

fn tuning_environment() -> BTreeMap<String, String> {
    std::env::vars()
        .filter(|(key, _)| key.starts_with("ZCASH_SYNC_") || key.starts_with("ZCASH_E2E_SYNC_"))
        .collect()
}

async fn fetch_tip_anchor(lightwalletd_url: &str) -> Result<TipAnchor, String> {
    let endpoint = Endpoint::from_shared(lightwalletd_url.to_string())
        .map_err(|e| format!("invalid URL: {e}"))?
        .connect_timeout(Duration::from_secs(10));
    let channel = if lightwalletd_url.starts_with("https://") {
        endpoint
            .tls_config(ClientTlsConfig::new().with_webpki_roots())
            .map_err(|e| format!("TLS config: {e}"))?
            .connect()
            .await
            .map_err(|e| format!("connect: {e}"))?
    } else {
        endpoint
            .connect()
            .await
            .map_err(|e| format!("connect: {e}"))?
    };
    let mut client = CompactTxStreamerClient::new(channel);
    let mut request = tonic::Request::new(ChainSpec::default());
    request.set_timeout(Duration::from_secs(20));
    let block = client
        .get_latest_block(request)
        .await
        .map_err(|e| format!("get_latest_block: {e}"))?
        .into_inner();
    Ok(TipAnchor {
        height: block.height,
        hash_hex: hex::encode(block.hash),
    })
}

fn anchor_json(result: Result<TipAnchor, String>) -> (Value, Value) {
    match result {
        Ok(anchor) => (json!(anchor), Value::Null),
        Err(error) => (Value::Null, json!(error)),
    }
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

    // Phase and actual scan-work accounting from progress events.
    let progress = Arc::new(Mutex::new(ProgressStats::default()));
    let progress_cb = progress.clone();

    let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
    let remote_tip_before = rt.block_on(fetch_tip_anchor(&lwd_url));
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
                progress_cb
                    .lock()
                    .expect("progress mutex poisoned")
                    .observe(&ev);
            },
        )
        .await
    });
    let elapsed = start.elapsed();
    let remote_tip_after = rt.block_on(fetch_tip_anchor(&lwd_url));

    if let Err(e) = &result {
        eprintln!("SYNC FAILED: {e}");
    }

    let progress = progress.lock().expect("progress mutex poisoned");
    let scanned = progress.last_scanned;
    let tip = progress.last_tip;
    let chain_span_blocks = tip.saturating_sub(birthday);
    let blocks = progress.scan_blocks_processed;
    let complete = progress.last_is_complete && progress.complete_events > 0;
    let heights_match = scanned == tip;
    let ok = result.is_ok() && complete && heights_match;

    // --- Balances ------------------------------------------------------------
    let mut balances = Vec::new();
    for acct in &accounts {
        if let Ok(bal) =
            sync_api::get_balance(db_path_str.clone(), network.clone(), acct.uuid.clone())
        {
            balances.push(json!({
                "uuid": acct.uuid.to_string(),
                "total": bal.total,
                "spendable": bal.spendable,
            }));
        }
    }

    let secs = elapsed.as_secs_f64();
    let bps = if secs > 0.0 {
        blocks as f64 / secs
    } else {
        0.0
    };

    let mut failure_reasons = Vec::new();
    if let Err(error) = &result {
        failure_reasons.push(format!("sync error: {error}"));
    }
    if !complete {
        failure_reasons.push("no terminal complete progress event".to_string());
    }
    if !heights_match {
        failure_reasons.push(format!("terminal scanned height {scanned} != tip {tip}"));
    }

    let (remote_tip_before, remote_tip_before_error) = anchor_json(remote_tip_before);
    let (remote_tip_after, remote_tip_after_error) = anchor_json(remote_tip_after);
    let summary = json!({
        "label": label,
        "scenario": scenario,
        "ok": ok,
        "failure_reasons": failure_reasons,
        "birthday": birthday,
        "tip": tip,
        "scanned": scanned,
        // Kept for compatibility, but now represents observed scan work rather
        // than the misleading `tip - birthday` chain span.
        "blocks": blocks,
        "scan_blocks_processed": blocks,
        "net_scanned_delta": progress.net_scanned_delta(),
        "chain_span_blocks": chain_span_blocks,
        "complete": complete,
        "accounts": accounts.len(),
        "events": progress.events,
        "phase_counts": progress.phase_counts,
        "elapsed_s": secs,
        "blocks_per_s": bps,
        "balances": balances,
        "remote_tip_before": remote_tip_before,
        "remote_tip_before_error": remote_tip_before_error,
        "remote_tip_after": remote_tip_after,
        "remote_tip_after_error": remote_tip_after_error,
        "git_sha": source_revision(),
        "git_dirty": source_is_dirty(),
        "tuning_env": tuning_environment(),
    });

    // serde_json emits compact, escaped, single-line JSON suitable for JSONL
    // collection after stripping the stable `BENCH_RESULT ` prefix.
    println!("BENCH_RESULT {summary}");

    eprintln!(
        "=== DONE: {:.2}s, {} blocks, {:.1} blocks/s, ok={} ===",
        secs, blocks, bps, ok
    );

    if !ok {
        std::process::exit(1);
    }
}
