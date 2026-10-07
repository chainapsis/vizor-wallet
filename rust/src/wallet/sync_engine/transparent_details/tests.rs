//! Loop 4 behavior: source choice, privacy, bounds, failures and the view.
//!
//! The private service is the transport's request observer, answering in
//! place of the network; lightwalletd is a capturing local server. Stage
//! behavior that needs a found record uses a scripted source, since no fake
//! can answer a native PIR query. Nothing here reaches the live service; see
//! `live.rs` for that.

use std::cell::Cell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use bytes::Bytes;
use http_body_util::Full;
use sha2::{Digest, Sha256};
use transparent::{address::TransparentAddress, bundle::OutPoint};
use transparent_native::TableProfile;
use transparent_shard::display::{
    DisplayBucket, DisplayLayout, DisplayManifest, DisplayMap, DisplayMapEntry, DisplaySealParams,
};
use transparent_shard::manifest::TableGeometry;
use zcash_client_backend::data_api::{
    transparent_ledger::{
        TransactionMetadata, TransparentDetailOutcome, TransparentDisplayFacts,
        TransparentDisplayOutput, TransparentDisplayProvenance, TransparentDisplayView,
        TransparentLedgerMode, TransparentLedgerWrite, WholeTransactionFee,
    },
    WalletRead,
};
use zcash_client_sqlite::AccountUuid;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::{consensus::BlockHeight, value::Zatoshis};

use super::source::{test_seam, DetailAnswer, DetailFailure, DetailSource};
use super::*;
use crate::wallet::db::{
    open_wallet_db_readonly_with_timeout, open_wallet_db_with_timeout, READ_DB_BUSY_TIMEOUT,
    SYNC_DB_BUSY_TIMEOUT,
};
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

/// A transparent receipt the wallet recorded at `height` without its raw
/// bytes, with detail work queued for it as private recovery queues it, and
/// no payload work: a transaction loop 4 owns.
pub(crate) fn utxo_receipt(fixture: &Fixture, tag: u8, height: u32) -> Transaction {
    let tx = legacy_transaction(OutPoint::new([tag; 32], 0), fixture.address, VALUE);
    let mut db = open_wallet_db_with_timeout(&fixture.path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    store_transparent_outputs(&mut db, &[downloaded(&fixture.uuid, &tx, height)]).unwrap();
    let conn = rusqlite::Connection::open(&fixture.path).unwrap();
    conn.execute(
        "DELETE FROM tx_retrieval_queue WHERE txid = ?1",
        [tx.txid().as_ref().as_slice()],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO transparent_detail_work (transaction_id, reasons)
         SELECT id_tx, 1 FROM transactions WHERE txid = ?1",
        [tx.txid().as_ref().as_slice()],
    )
    .unwrap();
    tx
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

/// The detail view of `txid` for the fixture's account, as the detail API
/// reads it.
pub(crate) fn view(fixture: &Fixture, txid: &TxId) -> Option<TransparentDisplayView> {
    let db =
        open_wallet_db_readonly_with_timeout(&fixture.path, MAIN, READ_DB_BUSY_TIMEOUT).unwrap();
    let conn = rusqlite::Connection::open(&fixture.path).unwrap();
    detail_view(&db, &conn, fixture.account, txid.as_ref()).unwrap()
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

thread_local! {
    /// Wall-clock seconds the work is dated by, per test thread.
    static WALL: Cell<u64> = const { Cell::new(1_800_000_000) };
}

fn wall() -> SystemTime {
    UNIX_EPOCH + Duration::from_secs(WALL.with(Cell::get))
}

fn advance_wall(by: Duration) {
    WALL.with(|wall| wall.set(wall.get() + by.as_secs()));
}

fn clock() -> StageClock {
    StageClock {
        instant: tokio_now,
        system: wall,
    }
}

/// The facts of `txid` as the account's receipt: its own output, then a
/// payment to [`PAYEE`].
fn facts_of(fixture: &Fixture, txid: TxId) -> DetailAnswer {
    let own: transparent::address::Script = fixture.address.script().into();
    DetailAnswer::Facts(Box::new(TransparentDisplayFacts {
        txid,
        coinbase: false,
        metadata: TransactionMetadata {
            fee: WholeTransactionFee::Exact(Zatoshis::const_from_u64(1_000)),
            transparent_input_count: 1,
            has_shielded_components: false,
        },
        outputs: vec![
            TransparentDisplayOutput {
                value: Zatoshis::const_from_u64(VALUE),
                script: own.0 .0.to_vec(),
            },
            TransparentDisplayOutput {
                value: Zatoshis::const_from_u64(5_000),
                script: PAYEE.to_vec(),
            },
        ],
        provenance: TransparentDisplayProvenance {
            shard_id: 3,
            revision: 0,
            map_sha256: [0xaa; 32],
            looked_up_height: BlockHeight::from_u32(TOP - 1),
        },
    }))
}

fn deferred(outcome: TransparentDetailOutcome) -> Result<DetailAnswer, DetailFailure> {
    Err(DetailFailure::Deferred {
        outcome,
        map_sha256: Some([0xaa; 32]),
    })
}

fn unavailable(retry_after: Option<Duration>) -> Result<DetailAnswer, DetailFailure> {
    deferred(TransparentDetailOutcome::Unavailable { retry_after })
}

type Answer = Box<dyn FnMut(TxId) -> Result<DetailAnswer, DetailFailure> + Send>;

/// A private source that answers from a script, after `delay`.
struct Scripted {
    answer: Answer,
    delay: Duration,
    lookups: Arc<Mutex<Vec<TxId>>>,
    /// The map hash a refresh reports.
    refreshed: Option<[u8; 32]>,
}

impl Scripted {
    fn new(
        answer: impl FnMut(TxId) -> Result<DetailAnswer, DetailFailure> + Send + 'static,
    ) -> Self {
        Self {
            answer: Box::new(answer),
            delay: Duration::ZERO,
            lookups: Default::default(),
            refreshed: None,
        }
    }

    fn slow(mut self, delay: Duration) -> Self {
        self.delay = delay;
        self
    }

    fn looked_up(&self) -> Vec<TxId> {
        self.lookups.lock().unwrap().clone()
    }
}

impl DetailSource for Scripted {
    async fn lookup(
        &mut self,
        txid: TxId,
        _mined_height: BlockHeight,
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

    fn map_sha256(&self) -> Option<[u8; 32]> {
        Some([0xaa; 32])
    }

    async fn refresh_map(&mut self, _should_exit: &(dyn Fn() -> bool + Sync)) -> Option<[u8; 32]> {
        self.refreshed
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

/// The seed a table's public query setup derives from, as the service
/// publishes it.
fn setup_seed(kind: &str) -> u64 {
    let digest = Sha256::new()
        .chain_update(transparent_shard::SCHEMA.as_bytes())
        .chain_update(b"/setup-seed\0txid-2k\0")
        .chain_update(kind.as_bytes())
        .finalize();
    u64::from_le_bytes(digest[..8].try_into().unwrap())
}

/// A txid display service publishing one recent `txid-2k` shard over
/// `start..=end` that holds no record: every route of a lookup is answered
/// well-formed, so a lookup sends the whole transcript and finds nothing.
pub(crate) fn empty_publication(start: u32, end: u32) -> RequestObserver {
    let (start, end) = (u64::from(start), u64::from(end));
    let directory = TableProfile::new(
        transparent_shard::SCHEMA,
        "txid-2k",
        "txdirectory",
        2048,
        4096,
    )
    .unwrap();
    let pages =
        TableProfile::new(transparent_shard::SCHEMA, "txid-2k", "txpages", 2048, 4096).unwrap();
    let init = serde_json::to_vec(&serde_json::json!({
        "schema": transparent_shard::display::DISPLAY_SCHEMA,
        "codec": transparent_shard::txid::CODEC,
        "bucket_domain": "transparent-txid-display/bucket/v1",
        "native_schema": transparent_shard::SCHEMA,
        "geometries": [{
            "name": "txid-2k",
            "txdirectory": {"rows": 2048, "row_bytes": 4096, "scheme": directory.scheme, "setup_seed": setup_seed("txdirectory")},
            "txpages": {"rows": 2048, "row_bytes": 4096, "scheme": pages.scheme, "setup_seed": setup_seed("txpages")},
        }],
    }))
    .unwrap();
    let table = TableGeometry {
        rows: 2048,
        row_bytes: 4096,
        sha256: "cc".repeat(32),
    };
    let manifest = DisplayManifest {
        schema: transparent_shard::display::DISPLAY_SCHEMA.to_owned(),
        network: "main".to_owned(),
        genesis_hash: "ee".repeat(32),
        shard_id: 0,
        start_height: start,
        end_height: end,
        parent_block_hash: "ff".repeat(32),
        terminal_block_hash: "dd".repeat(32),
        parent_manifest_digest: String::new(),
        sealed: false,
        revision: 1,
        supersedes: String::new(),
        geometry: "txid-2k".to_owned(),
        n_buckets: 1,
        archive_target: 1,
        layout: DisplayLayout::current(),
        blocks: end - start + 1,
        records: 0,
        payload_bytes: 0,
        page_rows_used: 0,
        buckets: vec![DisplayBucket {
            bucket: 0,
            records: 0,
            inline_records: 0,
            directory_segments: vec![table.clone()],
            page_histogram: Default::default(),
        }],
        page_segments: vec![table],
    };
    manifest.validate().unwrap();
    let digest = manifest.digest();
    let manifest_bytes = manifest.canonical_bytes();
    let map = DisplayMap {
        schema: transparent_shard::display::DISPLAY_SCHEMA.to_owned(),
        network: "main".to_owned(),
        genesis_hash: "ee".repeat(32),
        seal: DisplaySealParams {
            n_archive: 1,
            n_recent: 1,
            archive_target: 1,
            recent_floor: 1,
            reorg_margin: 1,
        },
        start_height: start,
        first_shard_id: 0,
        shards: vec![DisplayMapEntry::from_manifest(&manifest, &digest)],
    };
    map.check_shape().unwrap();
    let map_bytes = map.to_bytes();
    let map_sha256 = hex::encode(Sha256::digest(&map_bytes));
    let public_bytes = directory.scheme.public_bytes;
    let response_bytes = directory.scheme.response_bytes;
    let shard = format!("/v1/txid/recent/shards/0/revisions/{digest}");
    RequestObserver::answering(move |request| {
        let path = request.path.as_str();
        if path == "/v1/txid/init" {
            reply(200, &[], init.clone())
        } else if path == "/v1/txid/shards" {
            reply(
                200,
                &[("x-txid-map-sha256", &map_sha256)],
                map_bytes.clone(),
            )
        } else if path == format!("/v1/txid/shards/0/revisions/{digest}/manifest") {
            reply(200, &[], manifest_bytes.clone())
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
    assert_eq!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Unavailable)
    );

    // A build that captured `Public` withholds over the private wallet.
    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert_eq!(outcome, None);
    assert_eq!(lwd.count("/GetTransaction"), 0);
    assert_eq!(paths(&service).len(), 1);
    assert_eq!(balance(&fixture), before);
}

/// Without `PrivateRequired`, the residual transaction is fetched through the
/// gate, once per authorized dispatch, and the private service sees nothing.
#[tokio::test]
async fn public_residual_only_via_gate() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xa2, TOP - 1);
    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    let service = refusing(503);
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_serving(
        vec![(*tx.txid().as_ref(), bytes, u64::from(TOP - 1))],
        0,
        |_| {},
    )
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
    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &tx.txid()) else {
        panic!("the stored payload shows its outputs");
    };
    assert_eq!(details.outputs.len(), 1);
    assert!(details.outputs[0].owned);
    assert_eq!(details.outputs[0].value.into_u64(), VALUE);

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
            (*tx.txid().as_ref(), bytes, u64::from(TOP - 1))
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
        assert_eq!(
            view(&fixture, &tx.txid()),
            Some(TransparentDisplayView::Pending)
        );
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn stage_failure_503_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb1, TOP - 1);
    let _mode = require_private(&fixture.path);
    let service =
        RequestObserver::answering(|_| reply(503, &[("retry-after", "30")], Vec::new()));
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
    assert!(
        events.lock().unwrap().is_empty(),
        "nothing stored, nothing reported"
    );
    assert_eq!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Unavailable)
    );
    assert_eq!(balance(&fixture), before);
}

#[tokio::test(start_paused = true)]
async fn stage_failure_timeout_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb2, TOP - 1);
    let before = balance(&fixture);
    let mut source = Scripted::new(|_| unavailable(None)).slow(Duration::from_secs(600));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.deferred == 1),
        "{outcome:?}"
    );
    assert_eq!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Unavailable)
    );
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
    assert_eq!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Unavailable)
    );
    assert_eq!(lwd.count("/GetTransaction"), 0);
    assert_eq!(balance(&fixture), before);
}

/// A store that cannot take the wallet's write lock in time fails without
/// failing the run or the sync; nothing is stored.
#[tokio::test(flavor = "multi_thread")]
async fn stage_failure_db_busy_sync_ok_balances_unchanged() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xb4, TOP - 1);
    let before = balance(&fixture);
    let mut db = open(&fixture.path);
    let generation = db.applied_transparent_policy().unwrap().generation;
    let holder = rusqlite::Connection::open(&fixture.path).unwrap();
    holder.execute_batch("BEGIN IMMEDIATE").unwrap();
    let mut source = Scripted::new({
        let answer = Mutex::new(Some(facts_of(&fixture, tx.txid())));
        move |_| Ok(answer.lock().unwrap().take().unwrap())
    });
    let outcome = guarded(async {
        Some(
            run(
                &mut db,
                &fixture.path,
                MAIN,
                &mut source,
                generation,
                clock(),
                &|| false,
            )
            .await,
        )
    })
    .await;
    holder.execute_batch("ROLLBACK").unwrap();
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.stored == 0),
        "{outcome:?}"
    );
    assert!(matches!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Pending | TransparentDisplayView::Unavailable)
    ));
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
    assert_eq!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Pending)
    );
    assert_eq!(balance(&fixture), before);
}

#[tokio::test(start_paused = true)]
async fn stage_honors_should_exit_and_budget() {
    let fixture = wallet();
    for tag in 0..10u8 {
        utxo_receipt(&fixture, 0xc0 + tag, TOP - 1 - u32::from(tag % 8));
    }
    let absent = |_: TxId| deferred(TransparentDetailOutcome::Absent);

    // At most eight lookups per run.
    let mut source = Scripted::new(absent);
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == MAX_LOOKUPS),
        "{outcome:?}"
    );
    assert_eq!(source.looked_up().len(), MAX_LOOKUPS);

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
            deferred(TransparentDetailOutcome::Absent)
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
    let mut source = Scripted::new(absent).slow(Duration::from_secs(20));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 3 && stats.deferred == 3),
        "{outcome:?}"
    );
    let took = tokio_now() - started;
    assert!(
        took >= RUN_BUDGET && took < RUN_BUDGET + Duration::from_secs(2),
        "{took:?}"
    );
}

/// An outage defers the transaction; a run before its next attempt asks
/// nothing, and the first run after it stores the details.
#[tokio::test]
async fn outage_then_recovery_reconciles_next_sync() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xf1, TOP - 1);
    let txid = tx.txid();
    let down = Arc::new(AtomicBool::new(true));
    let mut source = Scripted::new({
        let (down, answer) = (down.clone(), facts_of(&fixture, txid));
        let answer = Mutex::new(Some(answer));
        move |_| {
            if down.load(Ordering::SeqCst) {
                unavailable(Some(Duration::from_secs(30)))
            } else {
                Ok(answer.lock().unwrap().take().unwrap())
            }
        }
    });
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Unavailable(_))),
        "{outcome:?}"
    );
    assert_eq!(
        view(&fixture, &txid),
        Some(TransparentDisplayView::Unavailable)
    );

    // Before the next attempt: nothing is due, even when a view asks.
    down.store(false, Ordering::SeqCst);
    prioritize(&fixture.path, *txid.as_ref());
    let outcome = run_scripted(&fixture, &mut source).await;
    assert_eq!(outcome, Some(RunOutcome::Finished(RunStats::default())));

    // The next sync after the backoff reconciles.
    advance_wall(Duration::from_secs(2 * 60 * 60));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 1),
        "{outcome:?}"
    );
    assert_eq!(source.looked_up(), [txid, txid]);
    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &txid) else {
        panic!("recovered details");
    };
    assert_eq!(details.outputs.len(), 2);
}

/// A lookup parked on the display map it saw (after its day's wait) becomes
/// due once the source's refreshed map differs, within the same run.
#[tokio::test]
async fn parked_work_relists_after_map_refresh() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x70, TOP - 1).txid();
    let mut source = Scripted::new(|_| deferred(TransparentDetailOutcome::NotCovered));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.not_covered == 1),
        "{outcome:?}"
    );
    // A day later, on the same map: parked, nothing asked.
    advance_wall(Duration::from_secs(31 * 60 * 60));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert_eq!(outcome, Some(RunOutcome::Finished(RunStats::default())));
    // A refreshed map releases it.
    source.refreshed = Some([0xbb; 32]);
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1),
        "{outcome:?}"
    );
    assert_eq!(source.looked_up(), [txid, txid]);
}

#[tokio::test]
async fn prioritized_transactions_are_served_first() {
    let fixture = wallet();
    let txids: Vec<TxId> = (0..12u8)
        .map(|tag| utxo_receipt(&fixture, 0x60 + tag, TOP - 1).txid())
        .collect();
    let wanted = txids[11];
    prioritize(&fixture.path, *wanted.as_ref());
    let mut source = Scripted::new(|_| deferred(TransparentDetailOutcome::Absent));
    run_scripted(&fixture, &mut source).await;
    assert_eq!(source.looked_up()[0], wanted);
}

#[tokio::test]
async fn store_emits_has_new_tx() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0xf2, TOP - 1);
    let other = utxo_receipt(&fixture, 0xf3, TOP - 2);
    let answers = Mutex::new(HashMap::from([
        (tx.txid(), Ok(facts_of(&fixture, tx.txid()))),
        (other.txid(), deferred(TransparentDetailOutcome::NotCovered)),
    ]));
    let mut source = Scripted::new(move |txid| answers.lock().unwrap().remove(&txid).unwrap());
    let outcome = run_scripted(&fixture, &mut source).await;
    let events = Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    report(outcome, &|| false, &progress, (7, 8));
    {
        let events = events.lock().unwrap();
        assert_eq!(events.len(), 1);
        assert!(events[0].is_complete && events[0].has_new_tx);
        assert_eq!(
            (events[0].scanned_height, events[0].chain_tip_height),
            (7, 8)
        );
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
                    prioritize(&private.path, *tx.txid().as_ref());
                }
                advance_wall(Duration::from_secs(2 * 60 * 60));
                followup_with(&private, required(), &lwd).await;
            }
            // Popped from the end: a protocol failure, then not covered.
            let mut answers = vec![
                deferred(TransparentDetailOutcome::NotCovered),
                deferred(TransparentDetailOutcome::Protocol),
            ];
            let mut facts = Some(facts_of(&scripted, txs[4].txid()));
            let mut source = Scripted::new(move |txid| {
                if let Some(DetailAnswer::Facts(mut facts)) = facts.take() {
                    facts.txid = txid;
                    return Ok(DetailAnswer::Facts(facts));
                }
                answers.pop().unwrap_or_else(|| unavailable(None))
            });
            run_scripted(&scripted, &mut source).await;
            assert_eq!(source.looked_up().len(), 3);
        });
    });
    assert!(!lines.is_empty(), "the runs logged");
    for tx in &txs {
        let mut reversed = *tx.txid().as_ref();
        reversed.reverse();
        for needle in [hex::encode(tx.txid().as_ref()), hex::encode(reversed)] {
            for (_, line) in &lines {
                assert!(!line.contains(&needle), "{line:?} names a txid");
            }
        }
    }
}

#[tokio::test]
async fn detail_view_states() {
    let fixture = wallet();
    let pending = utxo_receipt(&fixture, 0x81, TOP - 1).txid();
    let unavailable_tx = utxo_receipt(&fixture, 0x82, TOP - 2).txid();
    let not_covered = utxo_receipt(&fixture, 0x83, TOP - 3).txid();
    let available = utxo_receipt(&fixture, 0x84, TOP - 4).txid();
    let answers = Mutex::new(HashMap::from([
        (unavailable_tx, unavailable(None)),
        (not_covered, deferred(TransparentDetailOutcome::NotCovered)),
        (available, Ok(facts_of(&fixture, available))),
    ]));
    // One transaction per run, so `pending` is never asked.
    for txid in [available, not_covered, unavailable_tx] {
        prioritize(&fixture.path, *txid.as_ref());
        let answer = Mutex::new(answers.lock().unwrap().remove(&txid));
        let mut source = Scripted::new(move |_| answer.lock().unwrap().take().unwrap());
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
    assert_eq!(
        view(&fixture, &pending),
        Some(TransparentDisplayView::Pending)
    );
    assert_eq!(
        view(&fixture, &unavailable_tx),
        Some(TransparentDisplayView::Unavailable)
    );
    assert_eq!(
        view(&fixture, &not_covered),
        Some(TransparentDisplayView::NotCovered)
    );
    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &available) else {
        panic!("stored facts are available");
    };
    let rows: Vec<_> = details
        .outputs
        .iter()
        .map(|output| (output.index, output.value.into_u64(), output.owned))
        .collect();
    assert_eq!(rows, [(0, VALUE, true), (1, 5_000, false)]);
    assert_eq!(details.outputs[0].address, Some(fixture.address));
    // A transaction the account has no transparent part in has no view.
    assert_eq!(view(&fixture, &TxId::from_bytes([0x55; 32])), None);

    // The detail API carries the view.
    let detail = crate::wallet::sync::get_transaction_detail(
        &fixture.path,
        MAIN,
        &fixture.uuid,
        &hex::encode(available.as_ref()),
        "received",
    )
    .unwrap();
    let Some(crate::wallet::sync::TransparentDetailsView::Available(rows)) =
        detail.transparent_details
    else {
        panic!("the detail carries the available outputs");
    };
    assert_eq!(rows.len(), 2);
    assert!(rows[0].is_own && !rows[1].is_own);
    assert_eq!(rows[1].amount_zatoshi, 5_000);
}

/// Looks up only the run's first transaction and ends the run after it.
struct FirstOnly<'s>(&'s mut Scripted, bool);

impl DetailSource for FirstOnly<'_> {
    async fn lookup(
        &mut self,
        txid: TxId,
        mined_height: BlockHeight,
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

    fn map_sha256(&self) -> Option<[u8; 32]> {
        self.0.map_sha256()
    }

    async fn refresh_map(&mut self, should_exit: &(dyn Fn() -> bool + Sync)) -> Option<[u8; 32]> {
        self.0.refresh_map(should_exit).await
    }
}
