//! Loop 4 behavior: source choice, privacy, bounds, failures and the view.
//!
//! The private service is the transport's request observer, answering in
//! place of the network; lightwalletd is a capturing local server. Stage
//! behavior that needs a found record uses a scripted source, since no fake
//! can answer a native PIR query. Nothing here reaches the live service; see
//! `live.rs` for that.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use bytes::Bytes;
use http_body_util::Full;
use sha2::{Digest, Sha256};
use transparent::{address::TransparentAddress, bundle::OutPoint};
use transparent_events::{FeeState, TransactionMetadata, Txid};
use transparent_native::TableProfile;
use transparent_shard::txid::{DisplayOutput, TransparentDisplayRecord};
use zcash_client_backend::data_api::{
    transparent_ledger::{TransparentLedgerMode, TransparentLedgerWrite},
    WalletRead,
};
use zcash_client_sqlite::AccountUuid;
use zcash_primitives::transaction::Transaction;

use super::client::{Provenance, DISPLAY_SCHEMA};
use super::source::{test_seam, DetailAnswer, DetailFailure, DetailSource};
use super::store::{self, DisplayView, ViewOutput};
use super::*;
use crate::wallet::db::{open_wallet_db_with_timeout, SYNC_DB_BUSY_TIMEOUT};
use crate::wallet::keys;
use crate::wallet::sync::{get_wallet_balance, WalletBalance};
use crate::wallet::sync_engine::enhancement::{test_log::log_lines, test_mode, RequestObserver};
use crate::wallet::sync_engine::test_lwd::{transition_on_first_dispatch, CapturingLwd};
use crate::wallet::sync_engine::transparent_recovery_tests::{downloaded, legacy_transaction};
use crate::wallet::sync_engine::{store_transparent_outputs, watch_for_exit};

mod live;

pub(crate) const MAIN: WalletNetwork = WalletNetwork::Main;
/// Below the live service's publications, so no fixture height is real.
pub(crate) const BIRTHDAY: u32 = 3_000_000;
pub(crate) const TOP: u32 = BIRTHDAY + 9;
const VALUE: u64 = 2_000_000;
/// A script paying someone else.
const PAYEE: [u8; 25] = {
    let mut script = [0x11; 25];
    script[0] = 0x76;
    script[1] = 0xa9;
    script[2] = 0x14;
    script[23] = 0x88;
    script[24] = 0xac;
    script
};

pub(crate) struct Fixture {
    _dir: tempfile::TempDir,
    pub(crate) path: String,
    pub(crate) uuid: String,
    pub(crate) account: AccountUuid,
    pub(crate) address: TransparentAddress,
}

/// A mainnet wallet with one software account, scanned from [`BIRTHDAY`]
/// through [`TOP`].
pub(crate) fn wallet() -> Fixture {
    let _ = rustls::crypto::ring::default_provider().install_default();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(&path, MAIN, &seed, Some(u64::from(BIRTHDAY)), "details")
            .unwrap();
    let account = keys::parse_account_uuid(&uuid).unwrap();
    let conn = rusqlite::Connection::open(&path).unwrap();
    for height in BIRTHDAY..=TOP {
        let mut hash = [0u8; 32];
        hash[..4].copy_from_slice(&height.to_le_bytes());
        hash[31] = 1;
        conn.execute(
            "INSERT OR REPLACE INTO blocks (height, hash, time, sapling_tree,
                 sapling_commitment_tree_size, orchard_commitment_tree_size,
                 ironwood_commitment_tree_size)
             VALUES (?1, ?2, 0, x'00', 0, 0, 0)",
            rusqlite::params![height, hash.to_vec()],
        )
        .unwrap();
    }
    conn.execute_batch(&format!(
        "DELETE FROM scan_queue;
         INSERT INTO scan_queue (block_range_start, block_range_end, priority)
         VALUES ({BIRTHDAY}, {}, 10);",
        TOP + 1
    ))
    .unwrap();
    let db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let address = *db
        .get_transparent_receivers(account, false, false)
        .unwrap()
        .keys()
        .next()
        .expect("the account has a transparent receiver");
    Fixture {
        _dir: dir,
        path,
        uuid,
        account,
        address,
    }
}

/// A receipt the UTXO refresh recorded at `height` without its payload: a
/// transparent transaction of the account with no raw bytes.
pub(crate) fn utxo_receipt(fixture: &Fixture, tag: u8, height: u32) -> Transaction {
    let tx = legacy_transaction(OutPoint::new([tag; 32], 0), fixture.address, VALUE);
    let mut db = open_wallet_db_with_timeout(&fixture.path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    store_transparent_outputs(&mut db, &[downloaded(&fixture.uuid, &tx, height)]).unwrap();
    tx
}

fn txid_of(tx: &Transaction) -> [u8; 32] {
    *tx.txid().as_ref()
}

/// Selects and durably applies `PrivateRequired` for the wallet at `path`.
pub(crate) fn require_private(path: &str) -> test_mode::ModeOverride {
    let mode = test_mode::set(path, TransparentLedgerMode::PrivateRequired);
    let mut db = open_wallet_db_with_timeout(path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.set_transparent_ledger_mode(TransparentLedgerMode::PrivateRequired);
    db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
        .unwrap();
    mode
}

pub(crate) fn required() -> EnhancementPolicy {
    EnhancementPolicy::for_preference(MAIN, false)
        .with_transparent_mode(TransparentLedgerMode::PrivateRequired)
}

fn public() -> EnhancementPolicy {
    EnhancementPolicy::for_preference(MAIN, false)
}

fn open(path: &str) -> WalletDatabase {
    open_wallet_db_with_timeout(path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap()
}

fn balance(fixture: &Fixture) -> WalletBalance {
    get_wallet_balance(&fixture.path, MAIN, &fixture.uuid).unwrap()
}

fn view(fixture: &Fixture, txid: &[u8; 32]) -> Option<DisplayView> {
    let conn = rusqlite::Connection::open(&fixture.path).unwrap();
    detail_view(
        &conn,
        &fixture.path,
        MAIN,
        fixture.account.expose_uuid().as_bytes(),
        txid,
    )
    .unwrap()
}

fn count(path: &str, sql: &str) -> i64 {
    rusqlite::Connection::open(path)
        .unwrap()
        .query_row(sql, [], |row| row.get(0))
        .unwrap()
}

/// The clock every stage in these tests measures with: tokio's, so a test
/// that pauses time advances it.
fn tokio_now() -> Instant {
    tokio::time::Instant::now().into_std()
}

/// Fixed wall-clock seconds: retries come due only through a view's
/// interest.
fn unix() -> i64 {
    1_800_000_000
}

fn clock() -> StageClock {
    StageClock {
        instant: tokio_now,
        unix,
    }
}

fn record(txid: [u8; 32], outputs: Vec<(u64, Vec<u8>)>) -> TransparentDisplayRecord {
    TransparentDisplayRecord {
        txid: Txid(txid),
        coinbase: false,
        metadata: TransactionMetadata {
            fee: FeeState::Exact(1_000),
            transparent_input_count: 1,
            has_shielded_components: false,
        },
        outputs: outputs
            .into_iter()
            .map(|(value, script)| DisplayOutput { value, script })
            .collect(),
    }
}

fn provenance() -> Provenance {
    Provenance {
        map_sha256: "aa".repeat(32),
        shard_id: 3,
        manifest_digest: "bb".repeat(32),
        sealed: true,
    }
}

/// The facts of `tx`: its own output, then a payment to [`PAYEE`].
fn facts_of(fixture: &Fixture, txid: [u8; 32]) -> DetailAnswer {
    let own: transparent::address::Script = fixture.address.script().into();
    DetailAnswer::Facts {
        record: record(txid, vec![(VALUE, own.0 .0.to_vec()), (5_000, PAYEE.to_vec())]),
        provenance: provenance(),
    }
}

type Answer = Box<dyn FnMut([u8; 32]) -> Result<DetailAnswer, DetailFailure> + Send>;

/// A private source that answers from a script, after `delay`.
struct Scripted {
    answer: Answer,
    delay: Duration,
    lookups: Arc<Mutex<Vec<[u8; 32]>>>,
}

impl Scripted {
    fn new(
        answer: impl FnMut([u8; 32]) -> Result<DetailAnswer, DetailFailure> + Send + 'static,
    ) -> Self {
        Self {
            answer: Box::new(answer),
            delay: Duration::ZERO,
            lookups: Default::default(),
        }
    }

    fn slow(mut self, delay: Duration) -> Self {
        self.delay = delay;
        self
    }

    fn looked_up(&self) -> Vec<[u8; 32]> {
        self.lookups.lock().unwrap().clone()
    }
}

impl DetailSource for Scripted {
    async fn lookup(
        &mut self,
        txid: [u8; 32],
        _mined_height: u64,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Result<DetailAnswer, DetailFailure> {
        self.lookups.lock().unwrap().push(txid);
        if !self.delay.is_zero() {
            tokio::select! {
                biased;
                _ = watch_for_exit(&should_exit) => return Err(DetailFailure::Cancelled),
                _ = tokio::time::sleep(self.delay) => {}
            }
        }
        (self.answer)(txid)
    }

    fn gate(&self) -> Option<&TransparentLookupGate> {
        None
    }
}

/// Runs `source` over the wallet as the followup does: guarded, with the
/// generation the wallet holds now.
async fn run_scripted(fixture: &Fixture, source: &mut Scripted) -> Option<RunOutcome> {
    let mut db = open(&fixture.path);
    let generation = db.applied_transparent_policy().unwrap().generation;
    guarded(async {
        Some(
            run(
                &mut db,
                &fixture.path,
                MAIN,
                source,
                generation,
                clock(),
                &|| false,
            )
            .await,
        )
    })
    .await
}

/// Runs the followup's source choice against `lwd`.
async fn followup_with(
    fixture: &Fixture,
    policy: EnhancementPolicy,
    lwd: &CapturingLwd,
) -> Option<RunOutcome> {
    let mut db = open(&fixture.path);
    guarded(followup(
        &mut db,
        &fixture.path,
        MAIN,
        policy,
        &lwd.client,
        clock(),
        &|| false,
    ))
    .await
}

fn reply(status: u16, headers: &[(&str, &str)], body: Vec<u8>) -> http::Response<Full<Bytes>> {
    let mut response = http::Response::builder().status(status);
    for (name, value) in headers {
        response = response.header(*name, *value);
    }
    response.body(Full::new(Bytes::from(body))).unwrap()
}

/// A txid display service that refuses everything with `status`.
fn refusing(status: u16) -> RequestObserver {
    RequestObserver::answering(move |_| reply(status, &[], Vec::new()))
}

/// A txid display service publishing one recent `txid-2k` shard over
/// `start..=end` that holds no record: every route of a lookup is answered
/// well-formed, so a lookup sends the whole transcript and finds nothing.
pub(crate) fn empty_publication(start: u32, end: u32) -> RequestObserver {
    let directory = TableProfile::new(
        transparent_shard::SCHEMA,
        "txid-2k",
        "txdirectory",
        2048,
        4096,
    )
    .unwrap();
    let pages = TableProfile::new(transparent_shard::SCHEMA, "txid-2k", "txpages", 2048, 4096)
        .unwrap();
    let seed = |kind: &str| {
        let digest = Sha256::new()
            .chain_update(transparent_shard::SCHEMA.as_bytes())
            .chain_update(b"/setup-seed\0txid-2k\0")
            .chain_update(kind.as_bytes())
            .finalize();
        u64::from_le_bytes(digest[..8].try_into().unwrap())
    };
    let init = serde_json::to_vec(&serde_json::json!({
        "schema": DISPLAY_SCHEMA,
        "codec": transparent_shard::txid::CODEC,
        "bucket_domain": "transparent-txid-display/bucket/v1",
        "native_schema": transparent_shard::SCHEMA,
        "geometries": [{
            "name": "txid-2k",
            "txdirectory": {"rows": 2048, "row_bytes": 4096, "scheme": directory.scheme, "setup_seed": seed("txdirectory")},
            "txpages": {"rows": 2048, "row_bytes": 4096, "scheme": pages.scheme, "setup_seed": seed("txpages")},
        }],
    }))
    .unwrap();
    let table = serde_json::json!({"rows": 2048, "row_bytes": 4096, "sha256": "cc".repeat(32)});
    let terminal = "dd".repeat(32);
    let manifest = serde_json::to_vec(&serde_json::json!({
        "schema": DISPLAY_SCHEMA,
        "network": "main",
        "genesis_hash": "ee".repeat(32),
        "shard_id": 0,
        "start_height": start,
        "end_height": end,
        "parent_block_hash": "ff".repeat(32),
        "terminal_block_hash": terminal,
        "parent_manifest_digest": "",
        "sealed": false,
        "revision": 1,
        "supersedes": "",
        "geometry": "txid-2k",
        "n_buckets": 1,
        "archive_target": 1,
        "layout": {
            "codec": transparent_shard::txid::CODEC,
            "inline_bytes": 128,
            "row_bytes": 4096,
            "fragment_bytes": 4050,
            "directory_choices": 2,
            "bucket_domain": "transparent-txid-display/bucket/v1",
        },
        "blocks": end - start + 1,
        "records": 0,
        "payload_bytes": 0,
        "page_rows_used": 0,
        "buckets": [{"bucket": 0, "records": 0, "inline_records": 0,
                     "directory_segments": [table], "page_histogram": {}}],
        "page_segments": [table],
    }))
    .unwrap();
    let digest = hex::encode(Sha256::digest(&manifest));
    let map = serde_json::to_vec(&serde_json::json!({
        "schema": DISPLAY_SCHEMA,
        "network": "main",
        "genesis_hash": "ee".repeat(32),
        "seal": {"n_archive": 1, "n_recent": 1, "archive_target": 1, "recent_floor": 1, "reorg_margin": 1},
        "start_height": start,
        "first_shard_id": 0,
        "shards": [{
            "shard_id": 0, "start_height": start, "end_height": end,
            "parent_block_hash": "ff".repeat(32), "terminal_block_hash": terminal,
            "geometry": "txid-2k", "n_buckets": 1, "directory_segments": [1], "page_segments": 1,
            "records": 0, "min_bucket_records": 0, "manifest_digest": digest,
            "revision": 1, "sealed": false,
        }],
    }))
    .unwrap();
    let map_sha256 = hex::encode(Sha256::digest(&map));
    let public_bytes = directory.scheme.public_bytes;
    let response_bytes = directory.scheme.response_bytes;
    let shard = format!("/v1/txid/recent/shards/0/revisions/{digest}");
    RequestObserver::answering(move |request| {
        let path = request.path.as_str();
        if path == "/v1/txid/init" {
            reply(200, &[], init.clone())
        } else if path == "/v1/txid/shards" {
            reply(200, &[("x-txid-map-sha256", &map_sha256)], map.clone())
        } else if path == format!("/v1/txid/shards/0/revisions/{digest}/manifest") {
            reply(200, &[], manifest.clone())
        } else if let Some(rest) = path.strip_prefix(&format!("{shard}/setup/")) {
            let (label, segment) = rest.split_once('/').unwrap();
            let params = vec![0u8; public_bytes];
            let setup = serde_json::json!({
                "manifest_digest": digest, "shard_id": 0, "table": label,
                "bucket": if label == "pages" { serde_json::Value::Null } else { serde_json::json!(0) },
                "segment": segment.parse::<u32>().unwrap(), "segments": 1, "geometry": "txid-2k",
                "public_params": B64.encode(&params),
                "public_params_sha256": hex::encode(Sha256::digest(&params)),
                "public_params_epoch": "0000000000000000",
            });
            reply(200, &[], serde_json::to_vec(&setup).unwrap())
        } else if path.starts_with(&format!("{shard}/query/")) {
            // Echo the binding; an all-zero row holds no entry.
            let mut body = request.body[..8].to_vec();
            body.extend([0u8; 8]);
            body.extend(vec![0u8; response_bytes]);
            reply(200, &[], body)
        } else {
            reply(404, &[], Vec::new())
        }
    })
}

fn paths(observer: &RequestObserver) -> Vec<String> {
    observer
        .requests()
        .into_iter()
        .map(|request| request.path)
        .collect()
}

/// Under `PrivateRequired` with the service down, loop 4 asks only the
/// private service and sends lightwalletd no `GetTransaction`; a `Public`
/// capture over the private wallet sends nothing anywhere.
#[tokio::test(flavor = "multi_thread")]
async fn private_required_zero_get_transaction_even_when_pir_down() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xa1, TOP - 1);
    let _mode = require_private(&fixture.path);
    let service = refusing(503);
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
    let before = balance(&fixture);

    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Unavailable(stats)) if stats.lookups == 1),
        "{outcome:?}"
    );
    assert_eq!(paths(&service), ["/v1/txid/init"]);
    assert_eq!(view(&fixture, &txid_of(&tx)), Some(DisplayView::Unavailable));

    // A build that captured `Public` withholds over the private wallet.
    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert_eq!(outcome, None);
    assert_eq!(lwd.count("/GetTransaction"), 0);
    assert_eq!(paths(&service).len(), 1);
    assert_eq!(balance(&fixture), before);
}

/// Without `PrivateRequired`, the residual transaction is fetched through the
/// gate, once per authorized dispatch, and the private service sees nothing.
#[tokio::test(flavor = "multi_thread")]
async fn public_residual_only_via_gate() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xa2, TOP - 1);
    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    let service = refusing(503);
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd =
        CapturingLwd::start_serving(vec![(txid_of(&tx), bytes, u64::from(TOP - 1))], 0, |_| {})
            .await;
    let dispatched = Arc::new(AtomicUsize::new(0));
    let _hook = crate::wallet::sync_engine::lwd::transparent_lookup::test_hooks::on_dispatch({
        let dispatched = dispatched.clone();
        move || {
            dispatched.fetch_add(1, Ordering::SeqCst);
        }
    });

    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 1),
        "{outcome:?}"
    );
    assert_eq!(lwd.count("/GetTransaction"), 1);
    assert_eq!(dispatched.load(Ordering::SeqCst), 1);
    assert!(service.requests().is_empty(), "no private request");
    let Some(DisplayView::Available { outputs }) = view(&fixture, &txid_of(&tx)) else {
        panic!("the stored payload shows its outputs");
    };
    assert_eq!(outputs.len(), 1);
    assert!(outputs[0].own);
    assert_eq!(outputs[0].value, VALUE);

    // Nothing is left to fetch.
    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert_eq!(outcome, Some(RunOutcome::Finished(RunStats::default())));
    assert_eq!(lwd.count("/GetTransaction"), 1);
}

/// A policy transition that lands after the first lookup was authorized lets
/// that request finish but stores nothing from it, and withholds the rest.
#[tokio::test]
async fn fenced_transition_midrun_withholds() {
    let fixture = wallet();
    let first = utxo_receipt(&fixture, 0xa3, TOP - 1);
    let second = utxo_receipt(&fixture, 0xa4, TOP - 2);
    let served = [&first, &second]
        .into_iter()
        .map(|tx| {
            let mut bytes = Vec::new();
            tx.write(&mut bytes).unwrap();
            (txid_of(tx), bytes, u64::from(TOP - 1))
        })
        .collect();
    let lwd = CapturingLwd::start_serving(served, 0, |_| {}).await;
    let raw = "SELECT COUNT(*) FROM transactions WHERE raw IS NOT NULL";
    let raw_before = count(&fixture.path, raw);
    let _transition =
        transition_on_first_dispatch(&fixture.path, MAIN, TransparentLedgerMode::PrivateShadow);

    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Withheld(stats)) if stats.lookups == 1 && stats.stored == 0),
        "{outcome:?}"
    );
    assert_eq!(lwd.count("/GetTransaction"), 1);
    assert_eq!(count(&fixture.path, raw), raw_before);
    for tx in [&first, &second] {
        assert_eq!(view(&fixture, &txid_of(tx)), Some(DisplayView::Pending));
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn stage_failure_503_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb1, TOP - 1);
    let _mode = require_private(&fixture.path);
    let service = RequestObserver::answering(|_| reply(503, &[("retry-after", "30")], Vec::new()));
    let _seam = test_seam::set(&fixture.path, service);
    let lwd = CapturingLwd::start_with(Vec::new(), 0, |_| {}).await;
    let before = balance(&fixture);
    let events = Mutex::new(Vec::new());
    let mut db = open(&fixture.path);
    transparent_details_followup(
        &mut db,
        &fixture.path,
        MAIN,
        required(),
        &lwd.client,
        &|| false,
        &|event: SyncProgressEvent| events.lock().unwrap().push(event),
        (u64::from(TOP), u64::from(TOP)),
    )
    .await;
    assert!(events.lock().unwrap().is_empty(), "nothing stored, nothing reported");
    assert_eq!(view(&fixture, &txid_of(&tx)), Some(DisplayView::Unavailable));
    assert_eq!(balance(&fixture), before);
}

#[tokio::test(start_paused = true)]
async fn stage_failure_timeout_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb2, TOP - 1);
    let before = balance(&fixture);
    let mut source =
        Scripted::new(|_| Err(DetailFailure::Failed("never"))).slow(Duration::from_secs(600));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.deferred == 1),
        "{outcome:?}"
    );
    assert_eq!(view(&fixture, &txid_of(&tx)), Some(DisplayView::Unavailable));
    assert_eq!(balance(&fixture), before);
}

#[tokio::test(flavor = "multi_thread")]
async fn stage_failure_protocol_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb3, TOP - 1);
    let _mode = require_private(&fixture.path);
    let service = RequestObserver::answering(|_| reply(200, &[], b"not json".to_vec()));
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), 0, |_| {}).await;
    let before = balance(&fixture);
    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.deferred == 1),
        "{outcome:?}"
    );
    assert_eq!(paths(&service), ["/v1/txid/init"]);
    assert_eq!(view(&fixture, &txid_of(&tx)), Some(DisplayView::Unavailable));
    assert_eq!(lwd.count("/GetTransaction"), 0);
    assert_eq!(balance(&fixture), before);
}

/// A write that cannot take the wallet's write lock defers the transaction.
#[tokio::test(flavor = "multi_thread")]
async fn stage_failure_db_busy_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb4, TOP - 1);
    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    let lwd =
        CapturingLwd::start_serving(vec![(txid_of(&tx), bytes, u64::from(TOP - 1))], 0, |_| {})
            .await;
    let before = balance(&fixture);
    let mut db = open(&fixture.path);
    let holder = rusqlite::Connection::open(&fixture.path).unwrap();
    holder.execute_batch("BEGIN IMMEDIATE").unwrap();
    let outcome = guarded(followup(
        &mut db,
        &fixture.path,
        MAIN,
        public(),
        &lwd.client,
        clock(),
        &|| false,
    ))
    .await;
    holder.execute_batch("ROLLBACK").unwrap();
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 0 && stats.deferred == 1),
        "{outcome:?}"
    );
    assert_eq!(view(&fixture, &txid_of(&tx)), Some(DisplayView::Unavailable));
    assert_eq!(balance(&fixture), before);
}

#[tokio::test]
async fn stage_failure_panic_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb5, TOP - 1);
    let before = balance(&fixture);
    let mut source = Scripted::new(|_| panic!("a source bug"));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert_eq!(outcome, None, "the panic is caught");
    let events = Mutex::new(Vec::new());
    report(
        outcome,
        &|| false,
        &|event: SyncProgressEvent| events.lock().unwrap().push(event),
        (0, 0),
    );
    assert!(events.lock().unwrap().is_empty());
    assert_eq!(view(&fixture, &txid_of(&tx)), Some(DisplayView::Pending));
    assert_eq!(balance(&fixture), before);
}

#[tokio::test(start_paused = true)]
async fn stage_honors_should_exit_and_budget() {
    let fixture = wallet();
    let txids: Vec<_> = (0..10u8)
        .map(|tag| txid_of(&utxo_receipt(&fixture, 0xc0 + tag, TOP - 1 - u32::from(tag % 8))))
        .collect();
    let not_covered = |_: [u8; 32]| Ok(DetailAnswer::NotCovered { map_sha256: None });

    // At most eight lookups per run, newest first.
    let mut source = Scripted::new(not_covered);
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == MAX_LOOKUPS),
        "{outcome:?}"
    );
    assert_eq!(source.looked_up().len(), MAX_LOOKUPS);
    let left: Vec<_> = txids
        .iter()
        .filter(|txid| !source.looked_up().contains(txid))
        .copied()
        .collect();
    assert_eq!(left.len(), 2);

    // Cancellation stops the run at once, mid-work.
    let fixture = wallet();
    for tag in 0..5u8 {
        utxo_receipt(&fixture, 0xd0 + tag, TOP - 1);
    }
    let exit = Arc::new(AtomicBool::new(false));
    let calls = Arc::new(AtomicUsize::new(0));
    let mut source = Scripted::new({
        let (exit, calls) = (exit.clone(), calls.clone());
        move |_| {
            if calls.fetch_add(1, Ordering::SeqCst) == 1 {
                exit.store(true, Ordering::SeqCst);
            }
            Ok(DetailAnswer::NotCovered { map_sha256: None })
        }
    });
    let mut db = open(&fixture.path);
    let generation = db.applied_transparent_policy().unwrap().generation;
    let should_exit = || exit.load(Ordering::SeqCst);
    let outcome = run(
        &mut db,
        &fixture.path,
        MAIN,
        &mut source,
        generation,
        clock(),
        &should_exit,
    )
    .await;
    assert!(
        matches!(outcome, RunOutcome::Exited(stats) if stats.lookups == 2),
        "{outcome:?}"
    );

    // The budget: twenty-second lookups fit twice in forty-five seconds; the
    // third is stopped at the budget and deferred.
    let fixture = wallet();
    for tag in 0..5u8 {
        utxo_receipt(&fixture, 0xe0 + tag, TOP - 1);
    }
    let started = tokio_now();
    let mut source = Scripted::new(not_covered).slow(Duration::from_secs(20));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats))
            if stats.lookups == 3 && stats.not_covered == 2 && stats.deferred == 1),
        "{outcome:?}"
    );
    let took = tokio_now() - started;
    assert!(took >= RUN_BUDGET && took < RUN_BUDGET + Duration::from_secs(2), "{took:?}");
}

/// An outage defers the transaction; the next run once the delay has passed
/// stores its details, and a detail view's interest skips the delay.
#[tokio::test]
async fn outage_then_recovery_reconciles_next_sync() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xf1, TOP - 1);
    let txid = txid_of(&tx);
    let down = Arc::new(AtomicBool::new(true));
    let mut source = Scripted::new({
        let (down, answer) = (down.clone(), facts_of(&fixture, txid));
        let answer = Mutex::new(Some(answer));
        move |_| {
            if down.load(Ordering::SeqCst) {
                Err(DetailFailure::Unavailable {
                    retry_after: Some(Duration::from_secs(30)),
                })
            } else {
                Ok(answer.lock().unwrap().take().unwrap())
            }
        }
    });
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(matches!(outcome, Some(RunOutcome::Unavailable(_))), "{outcome:?}");
    assert_eq!(view(&fixture, &txid), Some(DisplayView::Unavailable));

    // Before the delay: nothing is due.
    down.store(false, Ordering::SeqCst);
    let outcome = run_scripted(&fixture, &mut source).await;
    assert_eq!(outcome, Some(RunOutcome::Finished(RunStats::default())));

    // The detail view asks for it: served at once.
    prioritize(&fixture.path, txid);
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 1),
        "{outcome:?}"
    );
    assert_eq!(source.looked_up(), [txid, txid]);
    let Some(DisplayView::Available { outputs }) = view(&fixture, &txid) else {
        panic!("recovered details");
    };
    assert_eq!(outputs.len(), 2);
}

#[tokio::test]
async fn store_emits_has_new_tx() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xf2, TOP - 1);
    let other = utxo_receipt(&fixture, 0xf3, TOP - 2);
    let answers: HashMap<[u8; 32], DetailAnswer> = [
        (txid_of(&tx), facts_of(&fixture, txid_of(&tx))),
        (
            txid_of(&other),
            DetailAnswer::NotCovered { map_sha256: None },
        ),
    ]
    .into_iter()
    .collect();
    let answers = Mutex::new(answers);
    let mut source = Scripted::new(move |txid| Ok(answers.lock().unwrap().remove(&txid).unwrap()));
    let outcome = run_scripted(&fixture, &mut source).await;
    let events = Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    report(outcome, &|| false, &progress, (7, 8));
    {
        let events = events.lock().unwrap();
        assert_eq!(events.len(), 1);
        assert!(events[0].is_complete && events[0].has_new_tx);
        assert_eq!((events[0].scanned_height, events[0].chain_tip_height), (7, 8));
    }

    // A run that stores nothing reports nothing.
    let mut idle = Scripted::new(|_| unreachable!("nothing is due"));
    report(
        run_scripted(&fixture, &mut idle).await,
        &|| false,
        &progress,
        (7, 8),
    );
    assert_eq!(events.lock().unwrap().len(), 1);
}

/// No log line of a private run names a txid, in either byte order.
#[test]
fn logs_txid_free_private() {
    let private = wallet();
    let scripted = wallet();
    let mut txs: Vec<_> = (0..4u8)
        .map(|tag| utxo_receipt(&private, 0x90 + tag, TOP - 1))
        .collect();
    txs.extend((0..3u8).map(|tag| utxo_receipt(&scripted, 0x98 + tag, TOP - 1)));
    let _mode = require_private(&private.path);
    let lines = log_lines(|| {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async {
            let lwd = CapturingLwd::start_with(Vec::new(), 0, |_| {}).await;
            for service in [
                refusing(503),
                RequestObserver::answering(|_| reply(200, &[], b"{}".to_vec())),
                empty_publication(BIRTHDAY, TOP),
            ] {
                let _seam = test_seam::set(&private.path, service);
                for tx in &txs[..4] {
                    prioritize(&private.path, txid_of(tx));
                }
                followup_with(&private, required(), &lwd).await;
            }
            let mut answers = vec![
                Ok(DetailAnswer::NotCovered { map_sha256: None }),
                Err(DetailFailure::Failed("transport")),
                Ok(facts_of(&scripted, [0; 32])),
            ];
            let mut source = Scripted::new(move |txid| match answers.pop() {
                Some(Ok(DetailAnswer::Facts {
                    mut record,
                    provenance,
                })) => {
                    record.txid = Txid(txid);
                    Ok(DetailAnswer::Facts { record, provenance })
                }
                Some(answer) => answer,
                None => Err(DetailFailure::Unavailable { retry_after: None }),
            });
            run_scripted(&scripted, &mut source).await;
            assert_eq!(source.looked_up().len(), 3);
        });
    });
    assert!(!lines.is_empty(), "the runs logged");
    for tx in &txs {
        let mut reversed = txid_of(tx);
        reversed.reverse();
        for needle in [hex::encode(txid_of(tx)), hex::encode(reversed)] {
            for (_, line) in &lines {
                assert!(!line.contains(&needle), "{line:?} names a txid");
            }
        }
    }
}

#[tokio::test]
async fn detail_view_states() {
    let fixture = wallet();
    let pending = txid_of(&utxo_receipt(&fixture, 0x81, TOP - 1));
    let unavailable = txid_of(&utxo_receipt(&fixture, 0x82, TOP - 2));
    let not_covered = txid_of(&utxo_receipt(&fixture, 0x83, TOP - 3));
    let available = txid_of(&utxo_receipt(&fixture, 0x84, TOP - 4));
    let answers = Mutex::new(HashMap::from([
        (pending, Err(DetailFailure::Cancelled)),
        (
            unavailable,
            Err(DetailFailure::Unavailable { retry_after: None }),
        ),
        (
            not_covered,
            Ok(DetailAnswer::NotCovered { map_sha256: None }),
        ),
        (available, Ok(facts_of(&fixture, available))),
    ]));
    // Unavailable ends a run, so each transaction gets its own.
    for txid in [available, not_covered, unavailable] {
        prioritize(&fixture.path, txid);
        let mut source = Scripted::new({
            let answer = answers.lock().unwrap().remove(&txid).unwrap();
            let answer = Mutex::new(Some(answer));
            move |_| answer.lock().unwrap().take().unwrap()
        });
        let mut db = open(&fixture.path);
        let generation = db.applied_transparent_policy().unwrap().generation;
        let mut first_only = FirstOnly(&mut source, false);
        run(
            &mut db,
            &fixture.path,
            MAIN,
            &mut first_only,
            generation,
            clock(),
            &|| false,
        )
        .await;
    }
    assert_eq!(view(&fixture, &pending), Some(DisplayView::Pending));
    assert_eq!(view(&fixture, &unavailable), Some(DisplayView::Unavailable));
    assert_eq!(view(&fixture, &not_covered), Some(DisplayView::NotCovered));
    let script_address = |script: &[u8]| store::script_address(MAIN, script);
    let own: transparent::address::Script = fixture.address.script().into();
    assert_eq!(
        view(&fixture, &available),
        Some(DisplayView::Available {
            outputs: vec![
                ViewOutput {
                    index: 0,
                    value: VALUE,
                    address: script_address(&own.0 .0),
                    own: true,
                },
                ViewOutput {
                    index: 1,
                    value: 5_000,
                    address: script_address(&PAYEE),
                    own: false,
                },
            ],
        })
    );
    // A transaction the account has no transparent part in has no view.
    assert_eq!(view(&fixture, &[0x55; 32]), None);

    // The detail API carries the view.
    let detail = crate::wallet::sync::get_transaction_detail(
        &fixture.path,
        MAIN,
        &fixture.uuid,
        &hex::encode(available),
        "received",
    );
    if let Ok(detail) = detail {
        assert!(matches!(
            detail.transparent_details,
            Some(crate::wallet::sync::TransparentDetailsView::Available(ref rows)) if rows.len() == 2
        ));
    }
}

/// Looks up only the run's first transaction, answering the rest as
/// cancelled by the sync.
struct FirstOnly<'s>(&'s mut Scripted, bool);

impl DetailSource for FirstOnly<'_> {
    async fn lookup(
        &mut self,
        txid: [u8; 32],
        mined_height: u64,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Result<DetailAnswer, DetailFailure> {
        if std::mem::replace(&mut self.1, true) {
            return Err(DetailFailure::Withheld);
        }
        self.0.lookup(txid, mined_height, should_exit).await
    }

    fn gate(&self) -> Option<&TransparentLookupGate> {
        None
    }
}
