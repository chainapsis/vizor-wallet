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
        TransparentDisplayOutput, TransparentDisplayProvenance, TransparentDisplaySource,
        TransparentDisplayView, TransparentLedgerMode, TransparentLedgerWrite, WholeTransactionFee,
    },
    WalletRead,
};
use zcash_client_sqlite::AccountUuid;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::{
    consensus::{BlockHeight, BranchId},
    value::Zatoshis,
};

use super::source::{test_seam, DetailAnswer, DetailFailure, DetailSource};
use super::*;
use crate::wallet::db::{
    open_wallet_db_readonly_with_timeout, open_wallet_db_with_timeout, READ_DB_BUSY_TIMEOUT,
    SYNC_DB_BUSY_TIMEOUT,
};
use crate::wallet::keys;
use crate::wallet::sync::{get_wallet_balance, WalletBalance};
use crate::wallet::sync_engine::enhancement::{
    test_log::log_lines, test_mode, ObservedRequest, RequestObserver,
};
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
    _serial: Option<Shared>,
    _dir: tempfile::TempDir,
    pub(crate) path: String,
    pub(crate) uuid: String,
    pub(crate) account: AccountUuid,
    pub(crate) address: TransparentAddress,
}

/// A mainnet wallet with one software account, scanned from [`BIRTHDAY`]
/// through [`TOP`].
pub(crate) fn wallet() -> Fixture {
    wallet_with_seed().0
}

/// [`wallet`], for a test that holds [`paused_writer`].
fn paused_wallet() -> Fixture {
    let mut fixture = unguarded_wallet().0;
    fixture._serial = None;
    fixture
}

/// [`wallet`], with the account's seed.
fn wallet_with_seed() -> (Fixture, Vec<u8>) {
    let serial = Shared::take();
    let (mut fixture, seed) = unguarded_wallet();
    fixture._serial = Some(serial);
    (fixture, seed)
}

fn unguarded_wallet() -> (Fixture, Vec<u8>) {
    use secrecy::ExposeSecret as _;
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
    let seed = seed.expose_secret().to_vec();
    (
        Fixture {
            _serial: None,
            _dir: dir,
            path,
            uuid,
            account,
            address,
        },
        seed,
    )
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
    view_for(&fixture.path, fixture.account, txid)
}

/// The detail view of `txid` for `account`, as the detail API reads it.
fn view_for(path: &str, account: AccountUuid, txid: &TxId) -> Option<TransparentDisplayView> {
    let db = open_wallet_db_readonly_with_timeout(path, MAIN, READ_DB_BUSY_TIMEOUT).unwrap();
    let conn = rusqlite::Connection::open(path).unwrap();
    detail_view(&db, &conn, account, txid.as_ref()).unwrap()
}

fn count(path: &str, sql: &str) -> i64 {
    rusqlite::Connection::open(path)
        .unwrap()
        .query_row(sql, [], |row| row.get(0))
        .unwrap()
}

/// Runs of these tests wait for the process-wide wallet write lock. On a
/// paused clock a moment's real contention spends a whole budget, so a test
/// on a paused clock runs alone among them ([`paused_writer`], with fixtures
/// from [`paused_wallet`]), and every other fixture holds a shared guard.
static SERIAL: std::sync::RwLock<()> = std::sync::RwLock::new(());

fn paused_writer() -> std::sync::RwLockWriteGuard<'static, ()> {
    SERIAL
        .write()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

thread_local! {
    /// Fixtures alive on this thread: only the first takes the shared guard,
    /// since a second read could wait behind a queued writer.
    static FIXTURES: Cell<usize> = const { Cell::new(0) };
}

/// A fixture's share of [`SERIAL`].
struct Shared(#[allow(dead_code)] Option<std::sync::RwLockReadGuard<'static, ()>>);

impl Shared {
    fn take() -> Self {
        let first = FIXTURES.with(|count| {
            count.set(count.get() + 1);
            count.get() == 1
        });
        Shared(first.then(|| {
            SERIAL
                .read()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
        }))
    }
}

impl Drop for Shared {
    fn drop(&mut self) {
        FIXTURES.with(|count| count.set(count.get() - 1));
    }
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
    let answer = publication(start, end).answer;
    RequestObserver::answering(move |request| answer(request))
}

type Responder =
    Arc<dyn Fn(&ObservedRequest) -> http::Response<Full<Bytes>> + Send + Sync + 'static>;

/// One publication's answers and the digest of its map.
struct Publication {
    answer: Responder,
    map_sha256: [u8; 32],
}

/// A service publishing `before` until `advanced` is set, then `after`.
fn advancing(
    before: Publication,
    after: Publication,
    advanced: Arc<AtomicBool>,
) -> RequestObserver {
    RequestObserver::answering(move |request| {
        if advanced.load(Ordering::SeqCst) {
            (after.answer)(request)
        } else {
            (before.answer)(request)
        }
    })
}

/// The answers of [`empty_publication`].
fn publication(start: u32, end: u32) -> Publication {
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
    let map_digest: [u8; 32] = Sha256::digest(&map_bytes).into();
    let map_sha256 = hex::encode(map_digest);
    let public_bytes = directory.scheme.public_bytes;
    let response_bytes = directory.scheme.response_bytes;
    let shard = format!("/v1/txid/recent/shards/0/revisions/{digest}");
    let answer: Responder = Arc::new(move |request: &ObservedRequest| {
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
    });
    Publication {
        answer,
        map_sha256: map_digest,
    }
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
// The serial guard is held for the whole test on purpose; see `SERIAL`.
#[allow(clippy::await_holding_lock)]
async fn stage_failure_timeout_sync_ok_balances_unchanged() {
    let _serial = paused_writer();
    let fixture = paused_wallet();
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
// The serial guard is held for the whole test on purpose; see `SERIAL`.
#[allow(clippy::await_holding_lock)]
async fn stage_honors_should_exit_and_budget() {
    let _serial = paused_writer();
    let fixture = paused_wallet();
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
    let fixture = paused_wallet();
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
    let fixture = paused_wallet();
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
    // Parking for a map is private: under public authority the work would
    // be due at its ordinary retry.
    let _mode = require_private(&fixture.path);
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

// ---- mixed transactions: the account's own part is shielded ---------------

/// The wallet's id of `account`.
fn account_id(path: &str, account: AccountUuid) -> i64 {
    rusqlite::Connection::open(path)
        .unwrap()
        .query_row(
            "SELECT id FROM accounts WHERE uuid = ?1",
            [account.expose_uuid().as_bytes().as_slice()],
            |row| row.get(0),
        )
        .unwrap()
}

/// How a fixture transaction's transparent side is recorded.
#[derive(Clone, Copy, PartialEq, Eq)]
enum TransparentSide {
    /// Nothing: a fully shielded transaction.
    None,
    /// The sticky route-2 marker and mixed detail work, as Enhance PIR
    /// records a mixed transaction under `PrivateRequired`.
    RouteTwo,
}

/// Records `txid` mined at `height` without raw bytes, in which `account`
/// received an Orchard note and has no transparent output or spend.
fn shielded_part(path: &str, account: AccountUuid, txid: TxId, height: u32, side: TransparentSide) {
    let conn = rusqlite::Connection::open(path).unwrap();
    conn.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index)
         VALUES (?1, ?2, ?2, 1)",
        rusqlite::params![txid.as_ref().as_slice(), height],
    )
    .unwrap();
    let tx = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO orchard_received_notes (transaction_id, action_index,
             account_id, diversifier, value, rho, rseed, is_change, memo, note_version)
         VALUES (?1, 0, ?2, zeroblob(11), 50000, zeroblob(32), zeroblob(32), 0, X'F6', 2)",
        rusqlite::params![tx, account_id(path, account)],
    )
    .unwrap();
    if side == TransparentSide::RouteTwo {
        conn.execute(
            "INSERT INTO ironwood_enhance_routing (transaction_id, route) VALUES (?1, 2)",
            [tx],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO transparent_detail_work (transaction_id, reasons) VALUES (?1, 4)",
            [tx],
        )
        .unwrap();
    }
}

/// The facts of a mixed transaction: one transparent input, a payment of
/// 5,000 to [`PAYEE`], and a shielded part.
fn mixed_facts(txid: TxId) -> DetailAnswer {
    DetailAnswer::Facts(Box::new(TransparentDisplayFacts {
        txid,
        coinbase: false,
        metadata: TransactionMetadata {
            fee: WholeTransactionFee::Exact(Zatoshis::const_from_u64(1_000)),
            transparent_input_count: 1,
            has_shielded_components: true,
        },
        outputs: vec![TransparentDisplayOutput {
            value: Zatoshis::const_from_u64(5_000),
            script: PAYEE.to_vec(),
        }],
        provenance: TransparentDisplayProvenance {
            shard_id: 3,
            revision: 0,
            map_sha256: [0xaa; 32],
            looked_up_height: BlockHeight::from_u32(TOP - 1),
        },
    }))
}

/// A pre-Overwinter transaction spending `prevout` and paying 5,000 to
/// [`PAYEE`]: the raw bytes lightwalletd serves for a mixed transaction.
fn payee_transaction(prevout: OutPoint) -> Transaction {
    let mut bytes = 1u32.to_le_bytes().to_vec();
    bytes.push(1);
    bytes.extend_from_slice(prevout.hash());
    bytes.extend_from_slice(&prevout.n().to_le_bytes());
    bytes.push(0);
    bytes.extend_from_slice(&u32::MAX.to_le_bytes());
    bytes.push(1);
    bytes.extend_from_slice(&5_000u64.to_le_bytes());
    bytes.push(PAYEE.len() as u8);
    bytes.extend_from_slice(&PAYEE);
    bytes.extend_from_slice(&0u32.to_le_bytes());
    Transaction::read(&bytes[..], BranchId::Sprout).unwrap()
}

/// A pre-Overwinter transaction with no transparent input or output.
fn no_transparent_transaction() -> Transaction {
    let mut bytes = 1u32.to_le_bytes().to_vec();
    bytes.extend([0, 0]);
    bytes.extend_from_slice(&0u32.to_le_bytes());
    Transaction::read(&bytes[..], BranchId::Sprout).unwrap()
}

/// `(index, value, owned)` of every output a view shows.
fn rows(
    details: &zcash_client_backend::data_api::transparent_ledger::TransparentDisplayDetails,
) -> Vec<(u32, u64, bool)> {
    details
        .outputs
        .iter()
        .map(|output| (output.index, output.value.into_u64(), output.owned))
        .collect()
}

/// Storing the private details of a mixed transaction, whose only part for
/// the account is shielded, deletes its work; the view stays, from the
/// stored facts, and the detail API carries it.
#[tokio::test]
async fn mixed_private_details_stay_visible_after_storing() {
    let fixture = wallet();
    let _mode = require_private(&fixture.path);
    let txid = TxId::from_bytes([0x71; 32]);
    shielded_part(
        &fixture.path,
        fixture.account,
        txid,
        TOP - 1,
        TransparentSide::RouteTwo,
    );
    assert_eq!(view(&fixture, &txid), Some(TransparentDisplayView::Pending));

    let mut source = Scripted::new(|txid| Ok(mixed_facts(txid)));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 1),
        "{outcome:?}"
    );
    assert_eq!(
        count(
            &fixture.path,
            "SELECT COUNT(*) FROM transparent_detail_work"
        ),
        0
    );

    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &txid) else {
        panic!("the stored details stay visible");
    };
    assert!(matches!(
        details.source,
        TransparentDisplaySource::Display(_)
    ));
    assert!(details.shielded);
    assert_eq!(rows(&details), [(0, 5_000, false)]);

    let detail = crate::wallet::sync::get_transaction_detail(
        &fixture.path,
        MAIN,
        &fixture.uuid,
        &hex::encode(txid.as_ref()),
        "received",
    )
    .unwrap();
    let Some(crate::wallet::sync::TransparentDetailsView::Available(rows)) =
        detail.transparent_details
    else {
        panic!("the detail carries the stored outputs");
    };
    assert_eq!(rows.len(), 1);
    assert!(!rows[0].is_own);
    assert_eq!(rows[0].amount_zatoshi, 5_000);
}

/// Storage shape only: raw bytes that replace the work of a transaction in
/// which the account's recorded part is a shielded note keep its view.
///
/// The note is a fixture row and the raw bytes a transparent-only stand-in,
/// written as the wallet's raw store writes them (the bytes in, the work
/// and any display facts out). [`genuine_mixed_raw_details_stay_visible`]
/// stores a real mixed transaction the wallet decrypts.
#[tokio::test]
async fn mixed_raw_storage_shape_keeps_the_view() {
    let fixture = wallet();
    let tx = payee_transaction(OutPoint::new([0x72; 32], 0));
    shielded_part(
        &fixture.path,
        fixture.account,
        tx.txid(),
        TOP - 1,
        TransparentSide::RouteTwo,
    );
    assert_eq!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Pending)
    );
    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    let conn = rusqlite::Connection::open(&fixture.path).unwrap();
    conn.execute(
        "UPDATE transactions SET raw = ?1 WHERE txid = ?2",
        rusqlite::params![bytes, tx.txid().as_ref().as_slice()],
    )
    .unwrap();
    conn.execute_batch("DELETE FROM transparent_detail_work; DELETE FROM transparent_tx_display;")
        .unwrap();

    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &tx.txid()) else {
        panic!("the raw transaction stays visible");
    };
    assert_eq!(details.source, TransparentDisplaySource::RawTransaction);
    assert_eq!(rows(&details), [(0, 5_000, false)]);
    assert_eq!(details.input_count, 1);
}

/// Storage shape only: a payment the account made from its shielded funds
/// to an external transparent recipient, with no transparent input or
/// change of its own, keeps its view once raw bytes replace its work. The
/// sent note is a fixture row, as the wallet records a payment to a
/// transparent recipient (`output_pool` 0); another account has no view.
#[tokio::test]
async fn shielded_payment_to_a_transparent_recipient_keeps_the_view() {
    let fixture = wallet();
    let other_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (other_uuid, _) = keys::add_account(
        &fixture.path,
        MAIN,
        "other",
        &other_seed,
        Some(u64::from(BIRTHDAY)),
    )
    .unwrap();
    let other = keys::parse_account_uuid(&other_uuid).unwrap();
    let tx = payee_transaction(OutPoint::new([0x76; 32], 0));
    let conn = rusqlite::Connection::open(&fixture.path).unwrap();
    conn.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index)
         VALUES (?1, ?2, ?2, 1)",
        rusqlite::params![tx.txid().as_ref().as_slice(), TOP - 1],
    )
    .unwrap();
    let id = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO sent_notes (transaction_id, output_pool, output_index,
             from_account_id, to_address, value)
         VALUES (?1, 0, 0, ?2, 'fixture-transparent-recipient', 5000)",
        rusqlite::params![id, account_id(&fixture.path, fixture.account)],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO transparent_detail_work (transaction_id, reasons) VALUES (?1, 4)",
        [id],
    )
    .unwrap();
    assert_eq!(
        view(&fixture, &tx.txid()),
        Some(TransparentDisplayView::Pending)
    );
    assert_eq!(view_for(&fixture.path, other, &tx.txid()), None);

    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    conn.execute(
        "UPDATE transactions SET raw = ?1 WHERE id_tx = ?2",
        rusqlite::params![bytes, id],
    )
    .unwrap();
    conn.execute("DELETE FROM transparent_detail_work", [])
        .unwrap();
    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &tx.txid()) else {
        panic!("the payment stays visible");
    };
    assert_eq!(rows(&details), [(0, 5_000, false)]);
    assert_eq!(view_for(&fixture.path, other, &tx.txid()), None);
}

/// A real mixed transaction: an external transparent input pays the
/// account an Orchard note and an external transparent recipient.
fn genuine_mixed(fixture: &Fixture, height: u32) -> Transaction {
    use sapling_crypto::prover::mock::{MockOutputProver, MockSpendProver};
    use zcash_client_backend::data_api::Account as _;
    use zcash_primitives::transaction::{
        builder::{BuildConfig, Builder, BundlePadding},
        fees::zip317,
    };
    let recipient = open(&fixture.path)
        .get_account(fixture.account)
        .unwrap()
        .unwrap()
        .ufvk()
        .unwrap()
        .orchard()
        .unwrap()
        .address_at(0u32, orchard::keys::Scope::External);
    let mut keys = transparent::builder::TransparentSigningSet::new();
    let pubkey = keys.add_key(secp256k1::SecretKey::from_slice(&[0x5a; 32]).unwrap());
    let coin = transparent::bundle::TxOut::new(
        Zatoshis::const_from_u64(1_000_000),
        TransparentAddress::from_pubkey(&pubkey).script().into(),
    );
    let mut builder = Builder::new(
        MAIN,
        BlockHeight::from_u32(height),
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: Some(orchard::Anchor::empty_tree()),
            ironwood_anchor: None,
            orchard_padding: BundlePadding::DEFAULT,
            ironwood_padding: BundlePadding::DEFAULT,
        },
    );
    builder
        .add_transparent_p2pkh_input(pubkey, OutPoint::new([0x5b; 32], 0), coin)
        .unwrap();
    // `PAYEE`'s script.
    builder
        .add_transparent_output(
            &TransparentAddress::PublicKeyHash([0x11; 20]),
            Zatoshis::const_from_u64(5_000),
        )
        .unwrap();
    builder
        .add_orchard_output::<zip317::FeeError>(
            None,
            recipient,
            Zatoshis::const_from_u64(1_000_000 - 5_000 - 15_000),
            zcash_protocol::memo::MemoBytes::empty(),
        )
        .unwrap();
    builder
        .build(
            &keys,
            &[],
            &[],
            voting_crypto_deps::rand::rngs::OsRng,
            &MockSpendProver,
            &MockOutputProver,
            &zip317::FeeRule::standard(),
        )
        .unwrap()
        .transaction()
        .clone()
}

/// A real mixed transaction whose only part for the account is an Orchard
/// note keeps its view once public raw recovery stores it: loop 4 fetches
/// the raw bytes, the wallet decrypts the account's note and clears the
/// work, and the view shows the external recipient as not the account's.
/// Another account has no view.
#[tokio::test]
async fn genuine_mixed_raw_details_stay_visible() {
    let fixture = wallet();
    let other_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (other_uuid, _) = keys::add_account(
        &fixture.path,
        MAIN,
        "other",
        &other_seed,
        Some(u64::from(BIRTHDAY)),
    )
    .unwrap();
    let other = keys::parse_account_uuid(&other_uuid).unwrap();
    let tx = genuine_mixed(&fixture, TOP - 1);
    assert!(tx.orchard_bundle().is_some() && tx.transparent_bundle().is_some());
    // The wallet knows the transaction without its raw bytes, as mixed.
    let conn = rusqlite::Connection::open(&fixture.path).unwrap();
    conn.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height)
         VALUES (?1, ?2, ?2)",
        rusqlite::params![tx.txid().as_ref().as_slice(), TOP - 1],
    )
    .unwrap();
    let id = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO ironwood_enhance_routing (transaction_id, route) VALUES (?1, 2)",
        [id],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO transparent_detail_work (transaction_id, reasons) VALUES (?1, 4)",
        [id],
    )
    .unwrap();
    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    let lwd = CapturingLwd::start_serving(
        vec![(*tx.txid().as_ref(), bytes, u64::from(TOP - 1))],
        0,
        |_| {},
    )
    .await;

    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 1),
        "{outcome:?}"
    );
    assert_eq!(lwd.count("/GetTransaction"), 1);
    assert_eq!(
        count(
            &fixture.path,
            "SELECT COUNT(*) FROM transparent_detail_work"
        ),
        0
    );
    let account = account_id(&fixture.path, fixture.account);
    assert_eq!(
        count(
            &fixture.path,
            &format!(
                "SELECT COUNT(*) FROM orchard_received_notes n
                 JOIN transactions t ON t.id_tx = n.transaction_id
                 WHERE t.id_tx = {id} AND n.account_id = {account}"
            )
        ),
        1,
        "the wallet decrypted the account's note"
    );
    assert_eq!(
        count(
            &fixture.path,
            &format!(
                "SELECT COUNT(*) FROM transparent_received_outputs WHERE transaction_id = {id}"
            )
        ),
        0,
        "the account owns no transparent output"
    );

    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &tx.txid()) else {
        panic!("the stored mixed transaction stays visible");
    };
    assert_eq!(details.source, TransparentDisplaySource::RawTransaction);
    assert_eq!(rows(&details), [(0, 5_000, false)]);
    assert_eq!(details.input_count, 1);
    assert!(details.shielded);
    assert_eq!(view_for(&fixture.path, other, &tx.txid()), None);
}

/// The view is the account's own: another account's mixed transaction, a
/// fully shielded transaction with or without raw bytes, and an unknown
/// transaction have none.
#[tokio::test]
async fn views_need_a_transparent_part_the_account_takes_part_in() {
    let fixture = wallet();
    let other_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (other_uuid, _) = keys::add_account(
        &fixture.path,
        MAIN,
        "other",
        &other_seed,
        Some(u64::from(BIRTHDAY)),
    )
    .unwrap();
    let other = keys::parse_account_uuid(&other_uuid).unwrap();

    // Another account's mixed transaction, while pending and once stored.
    let theirs = TxId::from_bytes([0x73; 32]);
    shielded_part(
        &fixture.path,
        other,
        theirs,
        TOP - 1,
        TransparentSide::RouteTwo,
    );
    assert_eq!(
        view_for(&fixture.path, other, &theirs),
        Some(TransparentDisplayView::Pending)
    );
    assert_eq!(view(&fixture, &theirs), None);
    let mut source = Scripted::new(|txid| Ok(mixed_facts(txid)));
    let outcome = run_scripted(&fixture, &mut source).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 1),
        "{outcome:?}"
    );
    assert!(matches!(
        view_for(&fixture.path, other, &theirs),
        Some(TransparentDisplayView::Available(_))
    ));
    assert_eq!(view(&fixture, &theirs), None);

    // Fully shielded, without raw bytes.
    let shielded = TxId::from_bytes([0x74; 32]);
    shielded_part(
        &fixture.path,
        fixture.account,
        shielded,
        TOP - 2,
        TransparentSide::None,
    );
    assert_eq!(view(&fixture, &shielded), None);

    // Fully shielded, with raw bytes.
    let raw = no_transparent_transaction();
    shielded_part(
        &fixture.path,
        fixture.account,
        raw.txid(),
        TOP - 3,
        TransparentSide::None,
    );
    let mut bytes = Vec::new();
    raw.write(&mut bytes).unwrap();
    rusqlite::Connection::open(&fixture.path)
        .unwrap()
        .execute(
            "UPDATE transactions SET raw = ?1 WHERE txid = ?2",
            rusqlite::params![bytes, raw.txid().as_ref().as_slice()],
        )
        .unwrap();
    assert_eq!(view(&fixture, &raw.txid()), None);

    assert_eq!(view(&fixture, &TxId::from_bytes([0x75; 32])), None);
}

// ---- held work and the display map ----------------------------------------

/// `last_outcome` codes of the wallet's detail work.
const ABSENT_CODE: i64 = 1;
const NOT_COVERED_CODE: i64 = 2;

/// The work row of `txid`: its last outcome and the map it was recorded for.
fn work_row(path: &str, txid: &TxId) -> Option<(Option<i64>, Option<[u8; 32]>)> {
    use rusqlite::OptionalExtension as _;
    rusqlite::Connection::open(path)
        .unwrap()
        .query_row(
            "SELECT w.last_outcome, w.last_map_sha256 FROM transparent_detail_work w
             JOIN transactions t ON t.id_tx = w.transaction_id WHERE t.txid = ?1",
            [txid.as_ref().as_slice()],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get::<_, Option<Vec<u8>>>(1)?
                        .map(|map| map.try_into().unwrap()),
                ))
            },
        )
        .optional()
        .unwrap()
}

/// Longer than any backoff a held outcome gets.
const PAST_BACKOFF: Duration = Duration::from_secs(2 * 24 * 60 * 60);
const MAP_RECHECK: Duration = Duration::from_secs(6 * 60 * 60);

/// A lookup failure belongs to the placement it requested. A remine or
/// rewind while it is in flight must not postpone the replacement work.
#[tokio::test]
async fn stale_lookup_failures_preserve_remined_or_unmined_work() {
    for new_height in [Some(TOP), None] {
        let fixture = wallet();
        let txid = utxo_receipt(&fixture, 0x4c, TOP - 1).txid();
        let path = fixture.path.clone();
        let mut source = Scripted::new(move |looked_up_txid| {
            rusqlite::Connection::open(&path)
                .unwrap()
                .execute(
                    "UPDATE transactions SET mined_height = ?1 WHERE txid = ?2",
                    rusqlite::params![new_height, looked_up_txid.as_ref().as_slice()],
                )
                .unwrap();
            deferred(TransparentDetailOutcome::NotCovered)
        });
        run_scripted(&fixture, &mut source).await.unwrap();
        assert_eq!(work_row(&fixture.path, &txid), Some((None, None)));
        let (attempts, next): (u32, i64) = rusqlite::Connection::open(&fixture.path)
            .unwrap()
            .query_row(
                "SELECT attempts, next_attempt_at FROM transparent_detail_work w
                        JOIN transactions t ON t.id_tx = w.transaction_id WHERE t.txid = ?1",
                [txid.as_ref().as_slice()],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!((attempts, next), (0, 0));
        let db = open(&fixture.path);
        let work = db
            .transparent_detail_work(wall(), WORK_WINDOW, source.map_sha256())
            .unwrap();
        if let Some(height) = new_height {
            assert_eq!(work.requests.len(), 1);
            assert_eq!(work.requests[0].mined_height, BlockHeight::from_u32(height));
        } else {
            assert!(work.requests.is_empty());
        }
    }
}

/// Requests `observer` saw after the first `sent`.
fn paths_since(observer: &RequestObserver, sent: usize) -> Vec<String> {
    paths(observer)[sent..].to_vec()
}

fn finished_with(outcome: Option<RunOutcome>, lookups: usize) -> bool {
    matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == lookups)
}

/// A publication that starts above every fixture receipt: a lookup finds the
/// receipt below it, not covered, and the wallet holds it for this map.
fn not_covering() -> Publication {
    publication(TOP, TOP + 5)
}

/// Holds the receipt `txid` as not covered under `service`'s first map, and
/// passes its backoff.
async fn hold(fixture: &Fixture, lwd: &CapturingLwd, txid: &TxId, map: [u8; 32]) {
    let outcome = followup_with(fixture, required(), lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.not_covered == 1),
        "{outcome:?}"
    );
    assert_eq!(
        work_row(&fixture.path, txid),
        Some((Some(NOT_COVERED_CODE), Some(map)))
    );
    advance_wall(PAST_BACKOFF);
}

/// Work held as not covered under one map learns of a newer map through the
/// client the runs share, though no other work is due to send a lookup.
#[tokio::test(flavor = "multi_thread")]
async fn held_work_learns_of_new_coverage_through_the_cached_client() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x41, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let (old, new) = (not_covering(), publication(BIRTHDAY, TOP));
    let (old_map, new_map) = (old.map_sha256, new.map_sha256);
    let advanced = Arc::new(AtomicBool::new(false));
    let service = advancing(old, new, advanced.clone());
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
    hold(&fixture, &lwd, &txid, old_map).await;

    advanced.store(true, Ordering::SeqCst);
    let sent = service.requests().len();
    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.deferred == 1),
        "{outcome:?}"
    );
    let sent = paths_since(&service, sent);
    assert_eq!(sent[0], "/v1/txid/shards", "{sent:?}");
    assert!(sent.iter().any(|path| path.contains("/query/")), "{sent:?}");
    assert_eq!(
        work_row(&fixture.path, &txid),
        Some((Some(ABSENT_CODE), Some(new_map)))
    );
    assert_eq!(lwd.count("/GetTransaction"), 0);
}

/// An unchanged map keeps held work held. Consecutive runs share a six-hour
/// check interval; restarting the client forgets its attempted check time.
#[tokio::test(flavor = "multi_thread")]
async fn held_work_stays_held_while_the_map_is_unchanged() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x42, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let held = not_covering();
    let map = held.map_sha256;
    let service = RequestObserver::answering(move |request| (held.answer)(request));
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
    {
        let _seam = test_seam::set(&fixture.path, service.clone());
        hold(&fixture, &lwd, &txid, map).await;
        let sent = service.requests().len();
        let outcome = followup_with(&fixture, required(), &lwd).await;
        assert!(finished_with(outcome, 0), "{outcome:?}");
        assert_eq!(paths_since(&service, sent), ["/v1/txid/shards"]);

        // New sources in consecutive sync runs retain the attempted check.
        let sent = service.requests().len();
        let outcome = followup_with(&fixture, required(), &lwd).await;
        assert!(finished_with(outcome, 0), "{outcome:?}");
        assert!(paths_since(&service, sent).is_empty());
        advance_wall(MAP_RECHECK - Duration::from_secs(1));
        let outcome = followup_with(&fixture, required(), &lwd).await;
        assert!(finished_with(outcome, 0), "{outcome:?}");
        assert!(paths_since(&service, sent).is_empty());
        advance_wall(Duration::from_secs(1));
        let outcome = followup_with(&fixture, required(), &lwd).await;
        assert!(finished_with(outcome, 0), "{outcome:?}");
        assert_eq!(paths_since(&service, sent), ["/v1/txid/shards"]);
    }
    // A restart: a new client, without a map.
    let _seam = test_seam::set(&fixture.path, service.clone());
    let sent = service.requests().len();
    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert!(finished_with(outcome, 0), "{outcome:?}");
    assert_eq!(paths_since(&service, sent), ["/v1/txid/shards"]);

    assert_eq!(
        work_row(&fixture.path, &txid),
        Some((Some(NOT_COVERED_CODE), Some(map)))
    );
    assert_eq!(
        view(&fixture, &txid),
        Some(TransparentDisplayView::NotCovered)
    );
    assert_eq!(lwd.count("/GetTransaction"), 0);
}

/// A restart forgets the map; the first run after it fetches the map before
/// any lookup, so held work learns of new coverage.
#[tokio::test(flavor = "multi_thread")]
async fn held_work_learns_of_new_coverage_after_a_restart() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x43, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let (old, new) = (not_covering(), publication(BIRTHDAY, TOP));
    let (old_map, new_map) = (old.map_sha256, new.map_sha256);
    let advanced = Arc::new(AtomicBool::new(false));
    let service = advancing(old, new, advanced.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
    {
        let _seam = test_seam::set(&fixture.path, service.clone());
        hold(&fixture, &lwd, &txid, old_map).await;
    }

    advanced.store(true, Ordering::SeqCst);
    let _seam = test_seam::set(&fixture.path, service.clone());
    let sent = service.requests().len();
    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert!(finished_with(outcome, 1), "{outcome:?}");
    assert_eq!(paths_since(&service, sent)[0], "/v1/txid/shards");
    assert_eq!(
        work_row(&fixture.path, &txid),
        Some((Some(ABSENT_CODE), Some(new_map)))
    );
    assert_eq!(lwd.count("/GetTransaction"), 0);
}

/// A map request that fails leaves held work held under the map it was held
/// for, through a kept client and after a restart: no lookup, no public
/// request, and no log line names the transaction.
#[test]
fn held_work_stays_held_when_the_map_cannot_be_fetched() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x44, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let held = not_covering();
    let map = held.map_sha256;
    let covering = publication(BIRTHDAY, TOP).answer;
    // 0 publishes the held map; any other value fails the map request in
    // its own way, and the rest of the service covers the receipt.
    let failure = Arc::new(AtomicUsize::new(0));
    const FAILURES: usize = 4;
    let service = RequestObserver::answering({
        let failure = failure.clone();
        move |request| {
            let kind = failure.load(Ordering::SeqCst);
            if kind == 0 {
                return (held.answer)(request);
            }
            if request.path != "/v1/txid/shards" {
                return covering(request);
            }
            match kind {
                1 => reply(503, &[("retry-after", "30")], Vec::new()),
                2 => reply(404, &[], Vec::new()),
                3 => {
                    // A map without its digest header.
                    let mut response = covering(request);
                    response.headers_mut().remove("x-txid-map-sha256");
                    response
                }
                _ => {
                    let body = b"not a map".to_vec();
                    let digest = hex::encode(Sha256::digest(&body));
                    reply(200, &[("x-txid-map-sha256", &digest)], body)
                }
            }
        }
    });
    let lines = log_lines(|| {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(async {
            let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
            let check = |sent: usize| {
                assert_eq!(paths_since(&service, sent), ["/v1/txid/shards"]);
                assert_eq!(
                    work_row(&fixture.path, &txid),
                    Some((Some(NOT_COVERED_CODE), Some(map)))
                );
            };
            {
                let _seam = test_seam::set(&fixture.path, service.clone());
                hold(&fixture, &lwd, &txid, map).await;
                for kind in 1..=FAILURES {
                    failure.store(kind, Ordering::SeqCst);
                    let sent = service.requests().len();
                    let outcome = followup_with(&fixture, required(), &lwd).await;
                    assert!(finished_with(outcome, 0), "{kind}: {outcome:?}");
                    check(sent);
                    let sent = service.requests().len();
                    let outcome = followup_with(&fixture, required(), &lwd).await;
                    assert!(finished_with(outcome, 0), "{kind}: {outcome:?}");
                    assert!(
                        paths_since(&service, sent).is_empty(),
                        "failed checks are bounded too"
                    );
                    advance_wall(MAP_RECHECK);
                }
            }
            for kind in 1..=FAILURES {
                failure.store(kind, Ordering::SeqCst);
                let _seam = test_seam::set(&fixture.path, service.clone());
                let sent = service.requests().len();
                let outcome = followup_with(&fixture, required(), &lwd).await;
                assert!(finished_with(outcome, 0), "{kind}: {outcome:?}");
                check(sent);
            }
            assert_eq!(lwd.count("/GetTransaction"), 0);
        });
    });
    assert_eq!(
        view(&fixture, &txid),
        Some(TransparentDisplayView::NotCovered)
    );
    assert!(!lines.is_empty(), "the runs logged");
    let mut reversed = *txid.as_ref();
    reversed.reverse();
    for needle in [hex::encode(txid.as_ref()), hex::encode(reversed)] {
        for (_, line) in &lines {
            assert!(!line.contains(&needle), "{line:?} names a txid");
        }
    }
}

/// Cancellation during the map request ends the run: nothing is looked up
/// or recorded.
#[tokio::test(flavor = "multi_thread")]
async fn map_refresh_honors_cancellation() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x45, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let held = not_covering();
    let map = held.map_sha256;
    let covering = publication(BIRTHDAY, TOP).answer;
    let exit = Arc::new(AtomicBool::new(false));
    let refreshing = Arc::new(AtomicBool::new(false));
    let service = RequestObserver::answering({
        let (exit, refreshing) = (exit.clone(), refreshing.clone());
        move |request| {
            if !refreshing.load(Ordering::SeqCst) {
                return (held.answer)(request);
            }
            if request.path == "/v1/txid/shards" {
                exit.store(true, Ordering::SeqCst);
            }
            covering(request)
        }
    });
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
    hold(&fixture, &lwd, &txid, map).await;

    refreshing.store(true, Ordering::SeqCst);
    let sent = service.requests().len();
    let mut db = open(&fixture.path);
    let should_exit = || exit.load(Ordering::SeqCst);
    let outcome = followup(
        &mut db,
        &fixture.path,
        MAIN,
        required(),
        &lwd.client,
        clock(),
        &should_exit,
    )
    .await;
    assert_eq!(outcome, Some(RunOutcome::Exited(RunStats::default())));
    assert_eq!(paths_since(&service, sent), ["/v1/txid/shards"]);
    assert_eq!(
        work_row(&fixture.path, &txid),
        Some((Some(NOT_COVERED_CODE), Some(map)))
    );
    assert_eq!(lwd.count("/GetTransaction"), 0);
}

/// A wallet without detail work asks the private service nothing.
#[tokio::test(flavor = "multi_thread")]
async fn no_detail_work_no_private_request() {
    let fixture = wallet();
    let _mode = require_private(&fixture.path);
    let service = empty_publication(BIRTHDAY, TOP);
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert_eq!(outcome, Some(RunOutcome::Finished(RunStats::default())));
    assert!(service.requests().is_empty());
}

/// A service that once published a display this client does not support,
/// and comes to support it, is found again: the client does not keep the
/// unsupported init document for good.
#[tokio::test(flavor = "multi_thread")]
async fn a_service_that_comes_to_support_the_client_is_found_again() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x46, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let supported = Arc::new(AtomicBool::new(false));
    let covering = publication(BIRTHDAY, TOP);
    let new_map = covering.map_sha256;
    let service = RequestObserver::answering({
        let supported = supported.clone();
        let covering = covering.answer;
        move |request| {
            if request.path == "/v1/txid/init" && !supported.load(Ordering::SeqCst) {
                let init = serde_json::json!({
                    "schema": transparent_shard::display::DISPLAY_SCHEMA,
                    "codec": "transparent-txid-display-v9",
                    "bucket_domain": "transparent-txid-display/bucket/v1",
                    "native_schema": transparent_shard::SCHEMA,
                    "geometries": [],
                });
                return reply(200, &[], serde_json::to_vec(&init).unwrap());
            }
            covering(request)
        }
    });
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;

    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.not_covered == 1),
        "{outcome:?}"
    );
    assert_eq!(work_row(&fixture.path, &txid).unwrap().0, Some(3));

    // The service now supports the client; once the wallet retries, the
    // receipt is looked up in the publication.
    supported.store(true, Ordering::SeqCst);
    advance_wall(PAST_BACKOFF);
    let sent = service.requests().len();
    let outcome = followup_with(&fixture, required(), &lwd).await;
    assert!(finished_with(outcome, 1), "{outcome:?}");
    let sent = paths_since(&service, sent);
    assert!(sent.contains(&"/v1/txid/init".to_owned()), "{sent:?}");
    assert!(sent.iter().any(|path| path.contains("/query/")), "{sent:?}");
    assert_eq!(
        work_row(&fixture.path, &txid),
        Some((Some(ABSENT_CODE), Some(new_map)))
    );
}

/// Work held for the private source's map is due at its ordinary retry once
/// the wallet returns to public lookups, and the public source fetches it.
#[tokio::test(flavor = "multi_thread")]
async fn held_work_is_fetched_publicly_after_a_return_to_public() {
    let fixture = wallet();
    let tx = utxo_receipt(&fixture, 0x47, TOP - 1);
    let txid = tx.txid();
    let mode = require_private(&fixture.path);
    let held = not_covering();
    let map = held.map_sha256;
    let service = RequestObserver::answering(move |request| (held.answer)(request));
    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    let lwd =
        CapturingLwd::start_serving(vec![(*txid.as_ref(), bytes, u64::from(TOP - 1))], 0, |_| {})
            .await;
    {
        let _seam = test_seam::set(&fixture.path, service.clone());
        hold(&fixture, &lwd, &txid, map).await;
    }
    drop(mode);
    let _mode = test_mode::set(&fixture.path, TransparentLedgerMode::Public);
    {
        let mut db = open(&fixture.path);
        db.set_transparent_ledger_mode(TransparentLedgerMode::Public);
        db.apply_transparent_policy(TransparentLedgerMode::Public)
            .unwrap();
    }

    let sent = service.requests().len();
    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.stored == 1),
        "{outcome:?}"
    );
    assert_eq!(lwd.count("/GetTransaction"), 1);
    assert!(paths_since(&service, sent).is_empty(), "no private request");
    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &txid) else {
        panic!("the public raw transaction shows its outputs");
    };
    assert_eq!(details.source, TransparentDisplaySource::RawTransaction);
}

/// A request that holds the shared client (a debug lookup, or one abandoned
/// at its backstop) delays no run past its exit: neither the digest the run
/// lists its work with, nor the lookup that waits for the client.
#[tokio::test(flavor = "multi_thread")]
async fn a_held_client_delays_no_run_past_its_exit() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x48, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let service = empty_publication(BIRTHDAY, TOP);
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
    let client = test_seam::client(&fixture.path);
    let (release, released) = std::sync::mpsc::channel::<()>();
    let (held, holding) = std::sync::mpsc::channel();
    let holder = std::thread::spawn(move || {
        let _client = client.lock().unwrap();
        held.send(()).unwrap();
        let _ = released.recv_timeout(Duration::from_secs(30));
    });
    holding.recv().unwrap();

    let exit = Arc::new(AtomicBool::new(false));
    std::thread::spawn({
        let exit = exit.clone();
        move || {
            std::thread::sleep(Duration::from_millis(300));
            exit.store(true, Ordering::SeqCst);
        }
    });
    let started = Instant::now();
    let mut db = open(&fixture.path);
    let should_exit = || exit.load(Ordering::SeqCst);
    let outcome = followup(
        &mut db,
        &fixture.path,
        MAIN,
        required(),
        &lwd.client,
        clock(),
        &should_exit,
    )
    .await;
    let took = started.elapsed();
    drop(release);
    holder.join().unwrap();
    assert!(took < Duration::from_secs(5), "{took:?}");
    assert!(
        matches!(outcome, Some(RunOutcome::Exited(stats)) if stats.lookups == 1),
        "{outcome:?}"
    );
    assert!(service.requests().is_empty(), "nothing was sent");
    assert_eq!(work_row(&fixture.path, &txid), Some((None, None)));
}

/// A run whose store waits on the wallet's write lock, held by another
/// operation of this process, gives up at its budget or exit instead of
/// waiting it out; nothing is stored and the transaction stays due.
#[tokio::test(start_paused = true)]
// The serial guard is held for the whole test on purpose; see `SERIAL`.
#[allow(clippy::await_holding_lock)]
async fn a_held_write_lock_delays_no_run_past_its_budget() {
    let _serial = paused_writer();
    let fixture = paused_wallet();
    let txid = utxo_receipt(&fixture, 0x49, TOP - 1).txid();
    let answer = facts_of(&fixture, txid);
    let answer = Mutex::new(Some(answer));
    let mut source = Scripted::new(move |_| Ok(answer.lock().unwrap().take().unwrap()));
    let release = crate::wallet::db::hold_wallet_db_write_lock(Duration::from_secs(20));
    let started = tokio_now();
    let outcome = run_scripted(&fixture, &mut source).await;
    let took = tokio_now() - started;
    drop(release);
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.lookups == 1 && stats.stored == 0),
        "{outcome:?}"
    );
    assert!(took < RUN_BUDGET + Duration::from_secs(3), "{took:?}");
    assert_eq!(view(&fixture, &txid), Some(TransparentDisplayView::Pending));

    // Exit while waiting ends the run at once.
    let other = utxo_receipt(&fixture, 0x4a, TOP - 2).txid();
    let answer = Mutex::new(Some(facts_of(&fixture, other)));
    let mut source = Scripted::new(move |txid| {
        let mut facts = answer.lock().unwrap().take().unwrap();
        if let DetailAnswer::Facts(facts) = &mut facts {
            facts.txid = txid;
        }
        Ok(facts)
    });
    let release = crate::wallet::db::hold_wallet_db_write_lock(Duration::from_secs(20));
    let exit = Arc::new(AtomicBool::new(false));
    let mut db = open(&fixture.path);
    let generation = db.applied_transparent_policy().unwrap().generation;
    let should_exit = {
        let exit = exit.clone();
        move || exit.load(Ordering::SeqCst)
    };
    let run = run(
        &mut db,
        &fixture.path,
        MAIN,
        &mut source,
        generation,
        clock(),
        &should_exit,
    );
    let stop = async {
        tokio::time::sleep(Duration::from_secs(1)).await;
        exit.store(true, Ordering::SeqCst);
        std::future::pending::<()>().await
    };
    let started = tokio_now();
    let outcome = tokio::select! {
        outcome = run => outcome,
        _ = stop => unreachable!(),
    };
    let took = tokio_now() - started;
    drop(release);
    assert!(
        matches!(outcome, RunOutcome::Exited(stats) if stats.lookups == 1 && stats.stored == 0),
        "{outcome:?}"
    );
    // The exit came a second in; the run returned with it.
    assert!(took < Duration::from_secs(2), "{took:?}");
    // With the lock released, nothing late is written: the work stays due.
    tokio::time::sleep(Duration::from_secs(5)).await;
    assert_eq!(work_row(&fixture.path, &other), Some((None, None)));
    assert_eq!(
        view(&fixture, &other),
        Some(TransparentDisplayView::Pending)
    );
}

/// A lookup whose transport ignores its cancellation is abandoned within the
/// cancel grace. The run returns, and so does the runtime the sync owns and
/// drops on return, though the lookup still runs; a later run waits for the
/// client it still holds only while it is wanted. Once the stuck request
/// returns, the abandoned lookup sends nothing more and nothing is stored.
#[test]
fn an_abandoned_lookup_holds_neither_the_run_nor_its_runtime() {
    let fixture = wallet();
    let txid = utxo_receipt(&fixture, 0x4b, TOP - 1).txid();
    let _mode = require_private(&fixture.path);
    let (release, released) = std::sync::mpsc::channel::<()>();
    let released = Arc::new(Mutex::new(released));
    let (unblock, blocked) = std::sync::mpsc::channel::<()>();
    let blocked = Arc::new(Mutex::new(blocked));
    let (descendant, descended) = std::sync::mpsc::channel::<()>();
    let (descendant_started, started) = std::sync::mpsc::channel::<()>();
    let started = Arc::new(Mutex::new(started));
    let stuck = Arc::new(AtomicBool::new(false));
    let covering = publication(BIRTHDAY, TOP).answer;
    let service = RequestObserver::answering({
        let (released, blocked, stuck) = (released.clone(), blocked.clone(), stuck.clone());
        move |request| {
            if request.path.contains("/query/") && !stuck.swap(true, Ordering::SeqCst) {
                // Blocking work the request's I/O left on its runtime, as a
                // stuck DNS lookup leaves it, never awaited.
                let descendant = descendant.clone();
                let descendant_started = descendant_started.clone();
                let blocked = blocked.clone();
                tokio::task::spawn_blocking(move || {
                    descendant_started.send(()).unwrap();
                    let _ = blocked
                        .lock()
                        .unwrap()
                        .recv_timeout(Duration::from_secs(30));
                    let _ = descendant.send(());
                });
                started
                    .lock()
                    .unwrap()
                    .recv_timeout(Duration::from_secs(10))
                    .unwrap();
                // Blocks until released, whatever the cancellation says.
                let _ = released
                    .lock()
                    .unwrap()
                    .recv_timeout(Duration::from_secs(30));
            }
            covering(request)
        }
    });
    let _seam = test_seam::set(&fixture.path, service.clone());
    // As the full sync runs: on a runtime of its own, dropped on return.
    let sync = |exit_after: Duration| {
        let path = fixture.path.clone();
        std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(1)
                .enable_all()
                .build()
                .unwrap();
            let started = Instant::now();
            let outcome = runtime.block_on(async {
                let lwd = CapturingLwd::start_with(Vec::new(), u64::from(TOP), |_| {}).await;
                let mut db = open(&path);
                let should_exit = || started.elapsed() >= exit_after;
                followup(
                    &mut db,
                    &path,
                    MAIN,
                    required(),
                    &lwd.client,
                    clock(),
                    &should_exit,
                )
                .await
            });
            drop(runtime);
            (outcome, started.elapsed())
        })
        .join()
        .unwrap()
    };

    let (outcome, took) = sync(Duration::from_millis(500));
    assert!(
        stuck.load(Ordering::SeqCst),
        "the lookup reached the stuck request"
    );
    assert!(
        matches!(outcome, Some(RunOutcome::Exited(stats)) if stats.lookups == 1),
        "{outcome:?}"
    );
    assert!(
        took < Duration::from_millis(500) + source::CANCEL_GRACE + Duration::from_secs(2),
        "{took:?}"
    );

    // The abandoned lookup still holds the client.
    let (outcome, took) = sync(Duration::from_millis(300));
    assert!(
        matches!(outcome, Some(RunOutcome::Exited(stats)) if stats.lookups == 1),
        "{outcome:?}"
    );
    assert!(took < Duration::from_secs(3), "{took:?}");

    let sent = service.requests().len();
    release.send(()).unwrap();
    unblock.send(()).unwrap();
    // The abandoned lookup sends only while it holds the client: once the
    // client is free, it has returned, and its descendant work has ended.
    drop(test_seam::client(&fixture.path).lock().unwrap());
    descended.recv_timeout(Duration::from_secs(10)).unwrap();
    // The stuck request is recorded once answered; nothing follows it.
    let late = paths_since(&service, sent);
    assert_eq!(late.len(), 1, "{late:?}");
    assert!(late[0].contains("/query/"), "{late:?}");
    assert_eq!(work_row(&fixture.path, &txid), Some((None, None)));
    assert_eq!(view(&fixture, &txid), Some(TransparentDisplayView::Pending));
}

/// A real payment the account made from an Orchard note to an external
/// transparent recipient, with no transparent input or change: one Orchard
/// spend of the account's note, one transparent output to [`PAYEE`], and
/// returns the payment and the spent note's nullifier.
fn genuine_payment(seed: &[u8], height: u32) -> (Transaction, [u8; 32], u64) {
    use incrementalmerkletree::{Hashable, Level};
    use orchard::{
        keys::{FullViewingKey, Scope, SpendAuthorizingKey},
        note::{ExtractedNoteCommitment, RandomSeed, Rho},
        tree::{MerkleHashOrchard, MerklePath},
        value::NoteValue,
        Note, NoteVersion,
    };
    use sapling_crypto::prover::mock::{MockOutputProver, MockSpendProver};
    use zcash_primitives::transaction::{
        builder::{BuildConfig, Builder, BundlePadding},
        fees::zip317,
    };
    let usk = zcash_keys::keys::UnifiedSpendingKey::from_seed(&MAIN, seed, zip32::AccountId::ZERO)
        .unwrap();
    let sk = usk.orchard();
    let fvk = FullViewingKey::from(sk);
    // Exactly the payment and its fee: no change.
    let value = 5_000 + 15_000;
    let rho = Rho::from_bytes(&[0; 32]).unwrap();
    let note = Note::from_parts(
        fvk.address_at(0u32, Scope::External),
        NoteValue::from_raw(value),
        rho,
        RandomSeed::from_bytes([7; 32], &rho).unwrap(),
        NoteVersion::V2,
    )
    .unwrap();
    let path = MerklePath::from_parts(
        0,
        core::array::from_fn(|level| MerkleHashOrchard::empty_root(Level::from(level as u8))),
    );
    let anchor = path.root(ExtractedNoteCommitment::from(note.commitment()));
    let mut builder = Builder::new(
        MAIN,
        BlockHeight::from_u32(height),
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: Some(anchor),
            ironwood_anchor: None,
            orchard_padding: BundlePadding::DEFAULT,
            ironwood_padding: BundlePadding::DEFAULT,
        },
    );
    builder
        .add_orchard_spend::<zip317::FeeError>(fvk.clone(), note, path)
        .unwrap();
    builder
        .add_transparent_output(
            &TransparentAddress::PublicKeyHash([0x11; 20]),
            Zatoshis::const_from_u64(5_000),
        )
        .unwrap();
    let tx = builder
        .build(
            &transparent::builder::TransparentSigningSet::new(),
            &[],
            &[SpendAuthorizingKey::from(sk)],
            voting_crypto_deps::rand::rngs::OsRng,
            &MockSpendProver,
            &MockOutputProver,
            &zip317::FeeRule::standard(),
        )
        .unwrap()
        .transaction()
        .clone();
    (tx, note.nullifier(&fvk).to_bytes(), value)
}

/// A real payment the account made from its Orchard funds to an external
/// transparent recipient keeps its view once public raw recovery stores it.
/// The wallet knows only that the account's note was spent; loop 4 fetches
/// the raw bytes, the wallet finds the account's spend by its nullifier,
/// records the payment to the transparent recipient (`output_pool` 0) and
/// clears the work. The view shows the recipient as not the account's, no
/// transparent input, and a shielded part; another account has none.
#[tokio::test]
async fn genuine_shielded_payment_to_a_transparent_recipient_stays_visible() {
    let (fixture, seed) = wallet_with_seed();
    let other_seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (other_uuid, _) = keys::add_account(
        &fixture.path,
        MAIN,
        "other",
        &other_seed,
        Some(u64::from(BIRTHDAY)),
    )
    .unwrap();
    let other = keys::parse_account_uuid(&other_uuid).unwrap();
    let (tx, nullifier, value) = genuine_payment(&seed, TOP - 1);
    assert!(tx.orchard_bundle().is_some());
    assert!(tx
        .transparent_bundle()
        .is_some_and(|bundle| bundle.vin.is_empty() && bundle.vout.len() == 1));

    // The account's note, received earlier, and the payment the compact scan
    // saw spend it, without raw bytes, as mixed.
    let account = account_id(&fixture.path, fixture.account);
    let conn = rusqlite::Connection::open(&fixture.path).unwrap();
    conn.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height, tx_index)
         VALUES (?1, ?2, ?2, 1)",
        rusqlite::params![[0x77u8; 32].as_slice(), TOP - 2],
    )
    .unwrap();
    let funding = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO orchard_received_notes (transaction_id, action_index, account_id,
             diversifier, value, rho, rseed, nf, is_change, note_version)
         VALUES (?1, 0, ?2, zeroblob(11), ?3, zeroblob(32), zeroblob(32), ?4, 0, 2)",
        rusqlite::params![funding, account, value, nullifier.as_slice()],
    )
    .unwrap();
    let note = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO transactions (txid, mined_height, min_observed_height)
         VALUES (?1, ?2, ?2)",
        rusqlite::params![tx.txid().as_ref().as_slice(), TOP - 1],
    )
    .unwrap();
    let id = conn.last_insert_rowid();
    conn.execute(
        "INSERT INTO orchard_received_note_spends (orchard_received_note_id, transaction_id)
         VALUES (?1, ?2)",
        [note, id],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO ironwood_enhance_routing (transaction_id, route) VALUES (?1, 2)",
        [id],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO transparent_detail_work (transaction_id, reasons) VALUES (?1, 4)",
        [id],
    )
    .unwrap();
    let mut bytes = Vec::new();
    tx.write(&mut bytes).unwrap();
    let lwd = CapturingLwd::start_serving(
        vec![(*tx.txid().as_ref(), bytes, u64::from(TOP - 1))],
        0,
        |_| {},
    )
    .await;

    let outcome = followup_with(&fixture, public(), &lwd).await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.stored == 1),
        "{outcome:?}"
    );
    assert_eq!(lwd.count("/GetTransaction"), 1);
    assert_eq!(
        count(
            &fixture.path,
            "SELECT COUNT(*) FROM transparent_detail_work"
        ),
        0
    );
    assert_eq!(
        count(
            &fixture.path,
            &format!(
                "SELECT COUNT(*) FROM sent_notes
                 WHERE transaction_id = {id} AND output_pool = 0 AND from_account_id = {account}
                   AND value = 5000"
            )
        ),
        1,
        "the store recorded the payment to the transparent recipient"
    );
    assert_eq!(
        count(
            &fixture.path,
            &format!(
                "SELECT COUNT(*) FROM transparent_received_outputs WHERE transaction_id = {id}"
            )
        ),
        0
    );

    let Some(TransparentDisplayView::Available(details)) = view(&fixture, &tx.txid()) else {
        panic!("the stored payment stays visible");
    };
    assert_eq!(details.source, TransparentDisplaySource::RawTransaction);
    assert_eq!(rows(&details), [(0, 5_000, false)]);
    assert_eq!(details.input_count, 0);
    assert!(details.shielded);
    assert_eq!(view_for(&fixture.path, other, &tx.txid()), None);
}
