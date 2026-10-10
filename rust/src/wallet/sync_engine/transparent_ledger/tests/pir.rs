//! The transparent PIR source: origin, companions, passes and settlement.
//!
//! The service is the transport's request observer, which answers in place of
//! the network; no test reaches the live service.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicU64;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use bytes::Bytes;
use http_body_util::Full;
use sha2::{Digest, Sha256};
use zakura_pir_transparent::{ApplyStats, Outcome, ReferenceRecovery, SCHEMA};
use zcash_client_backend::data_api::transparent_ledger::ChainPoint;

use super::super::pir::{self, test_transport, TransparentPirSource, PASS_DEADLINE};
use super::*;
use crate::wallet::sync_engine::enhancement::{ObservedRequest, RequestObserver, RoutePolicy};

const MAIN: WalletNetwork = WalletNetwork::Main;
/// Every mainnet wallet's birthday, below the live service's publications so
/// that no fixture height is mistaken for a real one.
pub(super) const BIRTHDAY: u32 = 3_000_000;
/// The highest scanned block in every mainnet wallet.
pub(super) const TOP: u32 = BIRTHDAY + 9;
pub(super) const MAP: &str = "/v1/filters/shards";
pub(super) const INIT: &str = "/v1/shards/init";

pub(super) struct MainWallet {
    _dir: tempfile::TempDir,
    pub(super) path: String,
    /// Each account's UUID text and id, in creation order.
    pub(super) accounts: Vec<(String, AccountUuid)>,
}

/// A mainnet wallet with `accounts` software accounts, scanned from
/// [`BIRTHDAY`] through [`TOP`].
pub(super) fn main_wallet(accounts: usize) -> MainWallet {
    // The app installs the TLS provider at startup; transports need it.
    let _ = rustls::crypto::ring::default_provider().install_default();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let mut created = Vec::new();
    for index in 0..accounts {
        let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
        let birthday = Some(u64::from(BIRTHDAY));
        let (uuid, _) = if index == 0 {
            keys::init_db_and_create_account(&path, MAIN, &seed, birthday, "tpir")
        } else {
            keys::add_account(&path, MAIN, "tpir", &seed, birthday)
        }
        .unwrap();
        let account = keys::parse_account_uuid(&uuid).unwrap();
        created.push((uuid, account));
    }
    scan(&path, BIRTHDAY, BIRTHDAY, TOP, 0);
    MainWallet {
        _dir: dir,
        path,
        accounts: created,
    }
}

/// A watch set for `account` at the wallet's tip with nothing to watch: a
/// pass needs no retrieval, and is `Ready` once the wallet accepts the tip.
fn bare(account: AccountUuid) -> TransparentWatchSet<AccountUuid> {
    TransparentWatchSet {
        account,
        lifecycle: AccountLifecycle::Candidate,
        policy_generation: 0,
        target: Some(ChainPoint {
            height: TOP.into(),
            hash: main_hash(TOP),
        }),
        addresses: vec![],
        pending_pages: vec![],
    }
}

/// `account`'s watch set as the wallet reports it.
fn watched_by(wallet: &MainWallet, account: AccountUuid) -> TransparentWatchSet<AccountUuid> {
    let db = open_wallet_db_with_timeout(&wallet.path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let watch = db.transparent_watch_set(account).unwrap();
    assert!(!watch.addresses.is_empty());
    assert_eq!(watch.target.map(|target| target.height), Some(TOP.into()));
    watch
}

/// A one-shard mainnet publication from `start` through [`TOP`], ending on
/// the wallet's block there.
pub(super) fn shard_map(start: u32) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({
        "genesis_hash": "00040fe8ec8471911baa1db1266ea15dd06b4a8a5c453883c000b031973dce08",
        "network": "main",
        "profile": "zcash-transparent-range-v1",
        "range_envelope_version": 1,
        "start_height": start,
        "seal": {
            "archive-wide": {"max_scripts": 1629038, "max_page_rows": 63488, "max_txids": 0}
        },
        "shards": [{
            "shard_id": 0,
            "geometry": "archive-wide",
            "start_height": start,
            "end_height": TOP,
            "parent_block_hash": "00".repeat(32),
            "terminal_block_hash": main_hash(TOP).to_string(),
            "filter_hash": "11".repeat(32),
            "scripts": 1,
            "page_rows": 1,
            "txids": 1,
            "directory_segments": 1,
            "page_segments": 1,
            "manifest_digest": "22".repeat(32),
            "revision": 0,
            "sealed": false,
        }],
    }))
    .unwrap()
}

fn reply(status: u16, body: Vec<u8>) -> http::Response<Full<Bytes>> {
    http::Response::builder()
        .status(status)
        .body(Full::new(Bytes::from(body)))
        .unwrap()
}

/// A service that publishes `map` and the adapter's schema, and answers every
/// other request with a bare 503: a failure, not a capacity refusal.
pub(super) fn service(map: Arc<Mutex<Vec<u8>>>) -> RequestObserver {
    RequestObserver::answering(move |request| match request.path.as_str() {
        MAP => reply(200, map.lock().unwrap().clone()),
        INIT => reply(
            200,
            serde_json::to_vec(&serde_json::json!({"schema": SCHEMA, "geometries": []})).unwrap(),
        ),
        _ => reply(503, vec![]),
    })
}

/// A service that refuses everything.
pub(super) fn refusing() -> RequestObserver {
    RequestObserver::answering(|_| reply(503, vec![]))
}

/// The history service's six routes, as `METHOD path`: the library's
/// end-to-end check, verbatim.
pub(super) const HISTORY_ROUTES: &str = r"^(GET /v1/(filters/shards(/[0-9]+/filter)?|shards/init|shards/[0-9]+/revisions/[0-9a-f]{64}/(manifest|setup/(directory|pages)/[0-9]+))|POST /v1/shards/[0-9]+/revisions/[0-9a-f]{64}/query/(directory|pages))$";

/// The txid display service's six routes, as `METHOD path`: the public init,
/// recent map and archive index chunks, then a shard revision's manifest,
/// setup and queries, named by tier, shard, revision, table and segment only.
pub(crate) const TXID_ROUTES: &str = r"^(GET /v1/txid/(init|map|map/[0-9]+/[0-9a-f]{64}|shards/[0-9]+/revisions/[0-9a-f]{64}/manifest|(archive|recent)/shards/[0-9]+/revisions/[0-9a-f]{64}/setup/directory-[0-9]+/[0-9]+)|POST /v1/txid/(archive|recent)/shards/[0-9]+/revisions/[0-9a-f]{64}/query/directory-[0-9]+)$";

/// Every route either service serves.
pub(crate) const ROUTES: &str = concat!(
    r"^(",
    r"GET /v1/(filters/shards(/[0-9]+/filter)?|shards/init|shards/[0-9]+/revisions/[0-9a-f]{64}/(manifest|setup/(directory|pages)/[0-9]+))",
    r"|POST /v1/shards/[0-9]+/revisions/[0-9a-f]{64}/query/(directory|pages)",
    r"|GET /v1/txid/(init|map|map/[0-9]+/[0-9a-f]{64}|shards/[0-9]+/revisions/[0-9a-f]{64}/manifest|(archive|recent)/shards/[0-9]+/revisions/[0-9a-f]{64}/setup/directory-[0-9]+/[0-9]+)",
    r"|POST /v1/txid/(archive|recent)/shards/[0-9]+/revisions/[0-9a-f]{64}/query/directory-[0-9]+",
    r")$"
);

/// Asserts that every request used one of the services' routes with that
/// route's method, with no query string, and that no path or body carries
/// any of `secrets`, in bytes or in hex. A failure names the request by its
/// index, never by its path, which holds shard ids and digests.
pub(crate) fn assert_private(requests: &[ObservedRequest], secrets: &[Vec<u8>]) {
    let routes = regex::Regex::new(ROUTES).unwrap();
    let needles: Vec<Vec<u8>> = secrets
        .iter()
        .flat_map(|secret| {
            [
                secret.clone(),
                hex::encode(secret).into_bytes(),
                hex::encode_upper(secret).into_bytes(),
            ]
        })
        .collect();
    let carries = |bytes: &[u8]| {
        needles
            .iter()
            .any(|needle| bytes.windows(needle.len()).any(|window| window == needle))
    };
    // Positive control: a script holding a secret, in bytes or in hex, would
    // be caught.
    let probe = secrets.first().expect("a secret to look for");
    assert!(carries(
        &[&[0x76, 0xa9, 20][..], probe, &[0x88, 0xac]].concat()
    ));
    assert!(carries(format!("/{}", hex::encode_upper(probe)).as_bytes()));
    for (index, request) in requests.iter().enumerate() {
        let line = format!("{} {}", request.method, request.path);
        assert!(
            routes.is_match(&line),
            "request {index} ({}) is not a service route",
            request.method
        );
        assert!(
            !carries(request.path.as_bytes()),
            "request {index} carries a secret in its path"
        );
        assert!(
            !carries(&request.body),
            "request {index} carries a secret in its body"
        );
    }
}

fn paths(requests: &[ObservedRequest]) -> Vec<&str> {
    requests
        .iter()
        .map(|request| request.path.as_str())
        .collect()
}

/// `uuid`'s companion file for the default origin.
fn companion(path: &str, uuid: &str) -> PathBuf {
    pir::companion_dir(path).companion_path(uuid, pir::DEFAULT_MAINNET_ORIGIN)
}

fn with_suffix(base: &Path, suffix: &str) -> PathBuf {
    let mut path = base.as_os_str().to_owned();
    path.push(suffix);
    path.into()
}

fn touch(path: &Path) {
    std::fs::write(path, b"companion").unwrap();
}

/// A request for one pass over `account` from `watch`.
fn request<'a>(
    account: AccountUuid,
    watch: &'a TransparentWatchSet<AccountUuid>,
    should_exit: &'a (dyn Fn() -> bool + Sync),
) -> SourceRequest<'a> {
    SourceRequest {
        account,
        watch,
        should_exit,
    }
}

/// The `Ready` answer of a pass that needed no retrieval.
const COMPLETE: SourceBatch = SourceBatch {
    state: BatchState::Ready,
    progress: Progress {
        covered_through: TOP as u64,
        outcome: Outcome::Complete,
    },
};

/// How a settlement ended, comparably.
#[derive(Debug, PartialEq, Eq)]
enum Settled {
    /// No `Ready` batch was parked.
    Nothing,
    Acknowledged(ApplyStats),
    /// Not acknowledged, after `applied` commits.
    Refused {
        applied: usize,
        action: ApplyAction,
    },
}

fn settled(settlement: Option<Result<Applied, ApplyFailure>>) -> Settled {
    match settlement {
        None => Settled::Nothing,
        Some(Ok(applied)) => Settled::Acknowledged(applied.stats),
        Some(Err(failure)) => Settled::Refused {
            applied: failure.stats.applied,
            action: failure.action(),
        },
    }
}

/// Settles `account`'s parked batch on the wallet at `path`, observed.
async fn settle(source: &TransparentPirSource, path: &str, account: AccountUuid) -> Settled {
    let mut db = open_wallet_db_with_timeout(path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    settled(
        source
            .apply(account, &mut db, Trust::Observed, &|| false)
            .await,
    )
}

#[tokio::test(flavor = "multi_thread")]
async fn new_selects_the_origin_gates_mainnet_and_uses_the_wallet_route() {
    let custom = "https://transparent-pir.example".to_owned();
    assert_eq!(
        pir::origin_for(MAIN, None).as_deref(),
        Some(pir::DEFAULT_MAINNET_ORIGIN)
    );
    assert_eq!(
        pir::origin_for(MAIN, Some(custom.clone())),
        Some(custom.clone())
    );
    for network in [WalletNetwork::Test, WalletNetwork::Regtest] {
        assert_eq!(pir::origin_for(network, None), None);
        assert_eq!(pir::origin_for(network, Some(custom.clone())), None);
    }
    // Only a debug build reads the override.
    let read = pir::origin_override(|name| {
        assert_eq!(name, "VIZOR_TRANSPARENT_PIR_URL");
        Some(custom.clone())
    });
    assert_eq!(read, cfg!(debug_assertions).then(|| custom.clone()));

    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let watch = watched_by(&wallet, account);
    let seam = test_transport::set(&wallet.path, refusing());

    // Off mainnet a pass sends nothing and creates nothing.
    let testnet = TransparentPirSource::new(&wallet.path, WalletNetwork::Test);
    assert_eq!(
        testnet.recover(request(account, &watch, &|| false)).await,
        Err(SourceError::Unavailable)
    );
    assert!(seam.seam.observer.requests().is_empty());
    assert!(!pir::companion_dir(&wallet.path).path().exists());

    // On mainnet the pass's transport takes the wallet's route. Its first
    // request fails: a service refusing its shard map is down, so the pass is
    // unavailable.
    let source = TransparentPirSource::new(&wallet.path, MAIN);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Err(SourceError::Unavailable)
    );
    assert_eq!(paths(&seam.seam.observer.requests()), [MAP]);
    assert_eq!(seam.seam.routes(), [RoutePolicy::WalletPreference]);
}

#[tokio::test(flavor = "multi_thread")]
async fn companions_are_per_account_and_bound_to_origin_and_schema() {
    let wallet = main_wallet(2);
    let (a_uuid, a) = wallet.accounts[0].clone();
    let (b_uuid, b) = wallet.accounts[1].clone();
    let seam = test_transport::set(&wallet.path, refusing());
    let dir = pir::companion_dir(&wallet.path);
    assert_eq!(dir.path(), Path::new(&format!("{}.tpir", wallet.path)));

    let source = TransparentPirSource::new(&wallet.path, MAIN);
    assert!(
        !dir.path().exists(),
        "companions are created by a pass, not the source"
    );
    for account in [a, b] {
        assert_eq!(
            source
                .recover(request(account, &bare(account), &|| false))
                .await,
            Ok(COMPLETE)
        );
    }
    assert!(seam.seam.observer.requests().is_empty());
    drop(source);
    let companions: BTreeSet<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "sqlite")
        })
        .collect();
    let (a_path, b_path) = (
        companion(&wallet.path, &a_uuid),
        companion(&wallet.path, &b_uuid),
    );
    assert_eq!(companions, BTreeSet::from([a_path.clone(), b_path]));

    // The adapter binds the source, the account's UUID, the origin and its
    // schema into the companion, and refuses it under any other.
    let config = pir::recovery_config(a, pir::DEFAULT_MAINNET_ORIGIN);
    assert_eq!(config.source, b"vizor/transparent-pir/v1");
    assert_eq!(config.account_binding, a.expose_uuid().as_bytes());
    assert_eq!(config.origin, pir::DEFAULT_MAINNET_ORIGIN);
    assert!(ReferenceRecovery::open(
        &a_path,
        pir::recovery_config(b, pir::DEFAULT_MAINNET_ORIGIN)
    )
    .is_err());
    let other = "https://transparent-pir.example";
    assert!(ReferenceRecovery::open(&a_path, pir::recovery_config(a, other)).is_err());
    ReferenceRecovery::open(&a_path, config).unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn deleting_an_account_removes_its_companion_and_sidecars() {
    let wallet = main_wallet(2);
    let (a_uuid, a) = wallet.accounts[0].clone();
    let (b_uuid, b) = wallet.accounts[1].clone();
    let _seam = test_transport::set(&wallet.path, refusing());
    let source = TransparentPirSource::new(&wallet.path, MAIN);
    for account in [a, b] {
        assert_eq!(
            source
                .recover(request(account, &bare(account), &|| false))
                .await,
            Ok(COMPLETE)
        );
    }
    drop(source);
    let a_path = companion(&wallet.path, &a_uuid);
    let a_files = [
        a_path.clone(),
        with_suffix(&a_path, "-wal"),
        with_suffix(&a_path, "-shm"),
        with_suffix(&a_path, "-journal"),
    ];
    for sidecar in &a_files[1..] {
        touch(sidecar);
    }

    keys::delete_account(&wallet.path, MAIN, &a_uuid).unwrap();

    for path in &a_files {
        assert!(!path.exists(), "{path:?} survived");
    }
    assert!(companion(&wallet.path, &b_uuid).exists());
    // Deleting an account with no companion is not an error.
    pir::remove_companions(&wallet.path, &a_uuid).unwrap();
}

/// Starts a sync that is cancelled before it reaches the network, which runs
/// only the start-of-sync housekeeping.
async fn start_cancelled_sync(path: &str) {
    // A cancelled sync to an unreachable server stops after its first attempt.
    let _ = crate::wallet::sync_engine::run_sync_inner(
        path,
        "http://127.0.0.1:1",
        MAIN,
        Arc::new(AtomicBool::new(true)),
        1,
        &std::sync::atomic::AtomicU8::new(0),
        None,
        false,
        |_| {},
    )
    .await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_sync_start_deletes_a_companion_its_account_deletion_left_behind() {
    let wallet = main_wallet(2);
    // Private, so the start of sync keeps live companions; a public wallet
    // forgets them all with its ledger facts.
    open_wallet_db_with_timeout(&wallet.path, MAIN, SYNC_DB_BUSY_TIMEOUT)
        .unwrap()
        .apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
        .unwrap();
    let (a_uuid, _) = wallet.accounts[0].clone();
    let (b_uuid, _) = wallet.accounts[1].clone();
    keys::delete_account(&wallet.path, MAIN, &a_uuid).unwrap();
    // The removal after the deletion failed: its files are still there.
    std::fs::create_dir_all(pir::companion_dir(&wallet.path).path()).unwrap();
    let left = companion(&wallet.path, &a_uuid);
    let left_files = [left.clone(), with_suffix(&left, "-wal")];
    for path in &left_files {
        touch(path);
    }
    let live = companion(&wallet.path, &b_uuid);
    touch(&live);

    start_cancelled_sync(&wallet.path).await;

    for path in &left_files {
        assert!(!path.exists(), "{path:?} survived");
    }
    assert!(live.exists(), "a live account's companion was deleted");
}

/// A public wallet keeps no private ledger facts, so the start of every sync
/// forgets any left behind, deleting every companion first.
#[tokio::test(flavor = "multi_thread")]
async fn a_public_sync_start_forgets_private_ledger_state() {
    let wallet = main_wallet(1);
    let (uuid, _) = wallet.accounts[0].clone();
    std::fs::create_dir_all(pir::companion_dir(&wallet.path).path()).unwrap();
    let live = companion(&wallet.path, &uuid);
    touch(&live);

    start_cancelled_sync(&wallet.path).await;

    assert!(!live.exists(), "a public wallet kept a companion");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_publication_change_retries_once_keeping_the_companion() {
    let wallet = main_wallet(1);
    let (uuid, account) = wallet.accounts[0].clone();
    let watch = watched_by(&wallet, account);
    let map = Arc::new(Mutex::new(shard_map(BIRTHDAY - 100)));
    let seam = test_transport::set(&wallet.path, service(map.clone()));
    let observer = &seam.seam.observer;

    // The first pass binds the companion to the publication's set identity,
    // then the service refuses the rest, its filters among them: an outage.
    let first = TransparentPirSource::new(&wallet.path, MAIN);
    assert_eq!(
        first.recover(request(account, &watch, &|| false)).await,
        Err(SourceError::Unavailable)
    );
    let bound = observer.requests().len();
    assert!(bound > 2, "the first pass got past the service's init");
    assert_eq!(paths(&observer.requests()[..2]), [MAP, INIT]);
    drop(first);
    let path = companion(&wallet.path, &uuid);
    rusqlite::Connection::open(&path)
        .unwrap()
        .execute_batch("CREATE TABLE vizor_test_marker (x)")
        .unwrap();

    // The publication restarts at another height: a new set identity. The
    // adapter resets the companion's store, keeping its catalog, and the pass
    // retries once on the same companion: from the reset store it binds the
    // new set and sends the first pass's requests again, and no more.
    *map.lock().unwrap() = shard_map(BIRTHDAY - 50);
    let second = TransparentPirSource::new(&wallet.path, MAIN);
    assert_eq!(
        second.recover(request(account, &watch, &|| false)).await,
        Err(SourceError::Unavailable)
    );
    let requests = observer.requests();
    let mut expected = vec![MAP, INIT];
    expected.extend(paths(&requests[..bound]));
    assert_eq!(paths(&requests[bound..]), expected);
    drop(second);
    let marker: i64 = rusqlite::Connection::open(&path)
        .unwrap()
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE name = 'vizor_test_marker'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(marker, 1, "the companion was recreated");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_failed_pass_reports_failed_and_sends_nothing_public() {
    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let watch = watched_by(&wallet, account);
    let before = production_dump(&wallet.path);
    let tpir_before = count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions");
    // The service publishes a map but refuses its init.
    let seam = test_transport::set(
        &wallet.path,
        RequestObserver::answering(|request| match request.path.as_str() {
            MAP => reply(200, shard_map(BIRTHDAY - 100)),
            _ => reply(503, vec![]),
        }),
    );

    let source = TransparentPirSource::new(&wallet.path, MAIN);
    // A service that is not serving its init is an outage, which ends the run
    // rather than failing only this account.
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Err(SourceError::Unavailable)
    );
    // Nothing is retried, and nothing reaches the wallet: the pass reads it
    // only to check the chain, and the source holds no other client.
    assert_eq!(paths(&seam.seam.observer.requests()), [MAP, INIT]);
    assert_eq!(production_dump(&wallet.path), before);
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions"),
        tpir_before
    );
    // A failed pass leaves nothing to acknowledge.
    assert_eq!(
        settle(&source, &wallet.path, account).await,
        Settled::Nothing
    );

    // A refusal of this request, not an outage of the service, fails only the
    // account's pass. The first source holds the companion; release it.
    drop(source);
    let _seam = test_transport::set(
        &wallet.path,
        RequestObserver::answering(|request| match request.path.as_str() {
            MAP => reply(200, shard_map(BIRTHDAY - 100)),
            _ => reply(404, vec![]),
        }),
    );
    let source = TransparentPirSource::new(&wallet.path, MAIN);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Err(SourceError::Failed)
    );
}

/// An outage of the service ends the whole run at its first account: no
/// other account is asked, and nothing is committed.
#[tokio::test(flavor = "multi_thread")]
async fn an_outage_stops_the_run_instead_of_failing_each_account() {
    let wallet = main_wallet(2);
    let path = wallet.path.clone();
    let _mode = test_mode::set(&path, TransparentLedgerMode::PrivateRequired);
    {
        let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
        db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
            .unwrap();
    }
    let before = production_dump(&path);
    let seam = test_transport::set(&path, refusing());
    let source = TransparentPirSource::new(&path, MAIN);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let policy = EnhancementPolicy::for_preference(MAIN, false)
        .with_transparent_mode(TransparentLedgerMode::PrivateRequired);
    let outcome = run(
        &mut db,
        &path,
        MAIN,
        policy,
        &source,
        Some(wallet.accounts[0].1),
        Instant::now,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::SourceUnavailable);
    // One account's shard map, then nothing.
    assert_eq!(paths(&seam.seam.observer.requests()), [MAP]);
    assert_eq!(production_dump(&path), before);
}

#[tokio::test(flavor = "multi_thread")]
async fn cancelling_a_pass_waits_for_the_blocking_task() {
    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let watch = watched_by(&wallet, account);
    let exit = Arc::new(AtomicBool::new(false));
    let finished = Arc::new(AtomicBool::new(false));
    // The service is slow to answer the first request, and the sync is
    // cancelled while it waits.
    let seam = test_transport::set(&wallet.path, {
        let (exit, finished) = (exit.clone(), finished.clone());
        RequestObserver::answering(move |_| {
            exit.store(true, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(500));
            finished.store(true, Ordering::SeqCst);
            reply(200, shard_map(BIRTHDAY - 100))
        })
    });

    let source = TransparentPirSource::new(&wallet.path, MAIN);
    let should_exit = || exit.load(Ordering::SeqCst);
    assert_eq!(
        source.recover(request(account, &watch, &should_exit)).await,
        Err(SourceError::Cancelled)
    );
    // The pass returned only once its blocking work had, and it sent nothing
    // after the cancellation.
    assert!(finished.load(Ordering::SeqCst));
    assert_eq!(paths(&seam.seam.observer.requests()), [MAP]);
    // A cancelled pass leaves nothing to acknowledge, and its companion is
    // parked again for the next pass.
    assert_eq!(
        settle(&source, &wallet.path, account).await,
        Settled::Nothing
    );
    assert_eq!(
        source
            .recover(request(account, &bare(account), &|| false))
            .await,
        Ok(COMPLETE)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_dropped_pass_stops_at_its_next_request() {
    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let watch = watched_by(&wallet, account);
    let (started, finished) = (
        Arc::new(AtomicBool::new(false)),
        Arc::new(AtomicBool::new(false)),
    );
    // The service answers the first request after the call is dropped, as
    // when the coordinator's backstop abandons it.
    let seam = test_transport::set(&wallet.path, {
        let (started, finished) = (started.clone(), finished.clone());
        RequestObserver::answering(move |_| {
            started.store(true, Ordering::SeqCst);
            std::thread::sleep(Duration::from_millis(300));
            finished.store(true, Ordering::SeqCst);
            reply(200, shard_map(BIRTHDAY - 100))
        })
    });

    let source = TransparentPirSource::new(&wallet.path, MAIN);
    let stay = || false;
    let mut call = Box::pin(source.recover(request(account, &watch, &stay)));
    // Drop the call once its first request is in flight, however long the
    // pass takes to open the wallet and companion first.
    let in_flight = async {
        while !started.load(Ordering::SeqCst) {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    };
    tokio::select! {
        _ = &mut call => panic!("the pass answered before the service did"),
        _ = in_flight => {}
    }
    drop(call);
    while !finished.load(Ordering::SeqCst) {
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    tokio::time::sleep(Duration::from_millis(300)).await;
    // The detached pass sent nothing after the first answer.
    assert_eq!(paths(&seam.seam.observer.requests()), [MAP]);
}

/// A pass that ignores its cancellation, here a request that never returns,
/// is abandoned after [`pir::CANCEL_GRACE`] rather than holding the call, and
/// the runtime that ran the call shuts down without waiting for it: the pass
/// runs on a thread of its own, never on that runtime's blocking pool, whose
/// shutdown would wait forever. Once it returns, its companion is free again.
#[test]
fn a_stuck_pass_holds_neither_the_call_nor_its_runtime() {
    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let watch = watched_by(&wallet, account);
    let started = Arc::new(AtomicBool::new(false));
    let (release, released) = std::sync::mpsc::channel::<()>();
    let released = Mutex::new(released);
    let _seam = test_transport::set(&wallet.path, {
        let started = started.clone();
        RequestObserver::answering(move |_| {
            started.store(true, Ordering::SeqCst);
            // Deaf to the exit flag, as a stuck read would be.
            let _ = released
                .lock()
                .unwrap()
                .recv_timeout(Duration::from_secs(60));
            reply(200, shard_map(BIRTHDAY - 100))
        })
    });

    let exit = AtomicBool::new(false);
    let begun = Instant::now();
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let answer = runtime.block_on(async {
        let source = TransparentPirSource::new(&wallet.path, MAIN);
        let should_exit = || exit.load(Ordering::SeqCst);
        let call = source.recover(request(account, &watch, &should_exit));
        let stuck = async {
            while !started.load(Ordering::SeqCst) {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
            exit.store(true, Ordering::SeqCst);
        };
        let (answer, ()) = tokio::join!(call, stuck);
        answer
    });
    drop(runtime);
    let took = begun.elapsed();
    assert_eq!(answer, Err(SourceError::Cancelled));
    assert!(
        took < pir::CANCEL_GRACE + Duration::from_secs(10),
        "the call or its runtime waited for the stuck pass: {took:?}"
    );

    // Released, the abandoned pass returns its companion, and the next pass
    // runs on it.
    drop(release);
    let runtime = tokio::runtime::Runtime::new().unwrap();
    let next = runtime.block_on(async {
        TransparentPirSource::new(&wallet.path, MAIN)
            .recover(request(account, &bare(account), &|| false))
            .await
    });
    assert_eq!(next, Ok(COMPLETE));
}

#[tokio::test(flavor = "multi_thread")]
async fn a_pass_past_its_deadline_fails_without_committing() {
    static ORIGIN: OnceLock<Instant> = OnceLock::new();
    static SKEW: AtomicU64 = AtomicU64::new(0);
    fn clock() -> Instant {
        *ORIGIN.get_or_init(Instant::now) + Duration::from_secs(SKEW.load(Ordering::SeqCst))
    }

    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let watch = watched_by(&wallet, account);
    // The deadline passes while the service answers the shard map.
    let seam = test_transport::set(
        &wallet.path,
        RequestObserver::answering(|_| {
            SKEW.store(PASS_DEADLINE.as_secs(), Ordering::SeqCst);
            reply(200, shard_map(BIRTHDAY - 100))
        }),
    );

    let source = TransparentPirSource::new(&wallet.path, MAIN).with_clock(clock);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Err(SourceError::Failed)
    );
    // Nothing is requested after the deadline, and nothing can be applied.
    assert_eq!(paths(&seam.seam.observer.requests()), [MAP]);
    assert_eq!(
        settle(&source, &wallet.path, account).await,
        Settled::Nothing
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn passes_and_acknowledgments_on_one_companion_are_serialized() {
    let wallet = main_wallet(1);
    let (uuid, account) = wallet.accounts[0].clone();
    let _seam = test_transport::set(&wallet.path, refusing());

    // A source parks the companion of a ready pass with its lock.
    let first = TransparentPirSource::new(&wallet.path, MAIN);
    assert_eq!(
        first
            .recover(request(account, &bare(account), &|| false))
            .await,
        Ok(COMPLETE)
    );

    // Another source's pass on the same companion waits for it.
    let second = Arc::new(TransparentPirSource::new(&wallet.path, MAIN));
    let mut waiting = tokio::spawn({
        let second = second.clone();
        async move {
            second
                .recover(request(account, &bare(account), &|| false))
                .await
        }
    });
    assert!(
        tokio::time::timeout(Duration::from_millis(300), &mut waiting)
            .await
            .is_err(),
        "a second pass ran on a held companion"
    );
    // So does removal, which gives up after its wait and deletes nothing.
    assert!(
        pir::remove_account_companions(&wallet.path, &uuid, Duration::from_millis(50)).is_err()
    );
    assert!(companion(&wallet.path, &uuid).exists());

    // The holder settles under its own lock, once.
    assert_eq!(
        settle(&first, &wallet.path, account).await,
        Settled::Acknowledged(ApplyStats::default())
    );
    assert_eq!(
        settle(&first, &wallet.path, account).await,
        Settled::Nothing
    );

    // Dropping it releases the companion to the waiting pass.
    drop(first);
    assert_eq!(waiting.await.unwrap(), Ok(COMPLETE));
    // A batch without retired revisions may also be settled as trusted.
    let mut db = open_wallet_db_with_timeout(&wallet.path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    assert_eq!(
        settled(
            second
                .apply(account, &mut db, Trust::Trusted, &|| false)
                .await
        ),
        Settled::Acknowledged(ApplyStats::default())
    );
}

/// The route of the one shard's activity filter.
const FILTER: &str = "/v1/filters/shards/0/filter";

/// A range filter with no element: no script matches it.
const EMPTY_FILTER: [u8; 1] = [0];

/// [`shard_map`] at `revision`, its shard filtered by [`EMPTY_FILTER`]: a pass
/// covers every watched script through the shard without a private query.
fn empty_filter_map(start: u32, revision: u32) -> Vec<u8> {
    let mut map: serde_json::Value = serde_json::from_slice(&shard_map(start)).unwrap();
    // The double SHA-256 of the filter, in display order.
    let mut filter_hash: [u8; 32] = Sha256::digest(Sha256::digest(EMPTY_FILTER)).into();
    filter_hash.reverse();
    let shard = &mut map["shards"][0];
    shard["filter_hash"] = hex::encode(filter_hash).into();
    shard["revision"] = revision.into();
    shard["manifest_digest"] = format!("{:064x}", u64::from(revision) + 1).into();
    serde_json::to_vec(&map).unwrap()
}

/// A service that publishes `map`, the adapter's schema and the shard's empty
/// filter, and answers every other request, a private query among them, with
/// a bare 503.
fn empty_filter_service(map: Arc<Mutex<Vec<u8>>>) -> RequestObserver {
    RequestObserver::answering(move |request| match request.path.as_str() {
        MAP => reply(200, map.lock().unwrap().clone()),
        INIT => reply(
            200,
            serde_json::to_vec(&serde_json::json!({"schema": SCHEMA, "geometries": []})).unwrap(),
        ),
        FILTER => reply(200, EMPTY_FILTER.to_vec()),
        _ => reply(503, vec![]),
    })
}

/// Moves the wallet's policy generation on, as a transition by another
/// connection would, without changing its mode.
fn bump_policy_generation(path: &str) {
    rusqlite::Connection::open(path)
        .unwrap()
        .execute(
            "UPDATE tpir_meta SET policy_generation = policy_generation + 1",
            [],
        )
        .unwrap();
}

/// A real pass with commits, settled through [`TransparentPirSource::apply`]
/// and the adapter: a policy change since the pass is refused as stale before
/// anything applies; the replay settles trusted, so its coverage reaches the
/// wallet with its revision qualified, and is acknowledged. Settling again,
/// or replaying the acknowledged publication, changes nothing. A newer
/// revision of the shard retires the acknowledged one: only a trusted
/// settlement reconciles it, and once that is acknowledged, no later batch
/// lists it again.
/// A quarantine stays with the account whose evidence it covers. Every
/// source id hashes the account's companion binding, so an account added
/// after another account's sources were quarantined recovers from sources of
/// its own: its batch settles, and nothing reports it quarantined.
#[tokio::test(flavor = "multi_thread")]
async fn a_quarantine_never_reaches_an_account_added_later() {
    let wallet = main_wallet(1);
    let first = wallet.accounts[0].1;
    let path = wallet.path.clone();
    let _mode = test_mode::set(&path, TransparentLedgerMode::PrivateRequired);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
        .unwrap();
    let map = Arc::new(Mutex::new(empty_filter_map(BIRTHDAY - 100, 0)));
    let _seam = test_transport::set(&path, empty_filter_service(map.clone()));
    let source = TransparentPirSource::new(&path, MAIN);
    let settle_trusted = |account| {
        let watch = watched_by(&wallet, account);
        let source = &source;
        let path = path.clone();
        async move {
            assert_eq!(
                source.recover(request(account, &watch, &|| false)).await,
                Ok(COMPLETE)
            );
            let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
            settled(
                source
                    .apply(account, &mut db, Trust::Trusted, &|| false)
                    .await,
            )
        }
    };
    let quarantined = |db: &WalletDatabase, account| {
        db.transparent_ledger_snapshot(account, crate::wallet::confirmations_policy())
            .unwrap()
            .blockers
            .contains(&RecoveryBlocker::Quarantined)
    };
    assert!(matches!(
        settle_trusted(first).await,
        Settled::Acknowledged(_)
    ));

    // An integrity rejection quarantines every source the first account's
    // evidence came from, and the account.
    let conn = rusqlite::Connection::open(&path).unwrap();
    conn.execute_batch(&format!(
        "INSERT INTO tpir_quarantined_sources (source)
             SELECT DISTINCT source FROM tpir_revisions;
         INSERT INTO tpir_quarantined_accounts (account_id)
             SELECT id FROM accounts WHERE uuid = X'{}';",
        hex::encode(first.expose_uuid().as_bytes())
    ))
    .unwrap();
    assert!(quarantined(&db, first));

    // An account added afterwards.
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (later, _) =
        keys::add_account(&path, MAIN, "later", &seed, Some(u64::from(BIRTHDAY))).unwrap();
    scan(&path, BIRTHDAY, BIRTHDAY, TOP, 0);
    let later = keys::parse_account_uuid(&later).unwrap();
    db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
        .unwrap();

    let Settled::Acknowledged(stats) = settle_trusted(later).await else {
        panic!("the later account's batch settles");
    };
    assert!(stats.applied > 0);
    assert!(!quarantined(&db, later));
    // The first account stays refused.
    assert_eq!(
        settle_trusted(first).await,
        Settled::Refused {
            applied: 0,
            action: ApplyAction::Skip,
        }
    );
}

/// Cancellation stops a settlement between its wallet writes: what applied
/// stays, nothing is acknowledged, and the next pass replays the batch and
/// settles it.
#[tokio::test(flavor = "multi_thread")]
async fn cancellation_stops_a_settlement_between_wallet_writes() {
    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let path = wallet.path.clone();
    let _mode = test_mode::set(&path, TransparentLedgerMode::PrivateRequired);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
        .unwrap();
    let map = Arc::new(Mutex::new(empty_filter_map(BIRTHDAY - 100, 0)));
    let _seam = test_transport::set(&path, empty_filter_service(map.clone()));
    let source = TransparentPirSource::new(&path, MAIN);
    let qualified = || count(&path, "SELECT COUNT(*) FROM tpir_qualified_revisions");

    // Exit is requested once the first commit is durable.
    let exit_after_first = || qualified() >= 1;
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    assert_eq!(
        settled(
            source
                .apply(account, &mut db, Trust::Trusted, &exit_after_first)
                .await
        ),
        Settled::Refused {
            applied: 1,
            action: ApplyAction::Interrupted,
        }
    );
    assert_eq!(qualified(), 1);

    // The next pass replays the batch, and it is acknowledged.
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    assert!(matches!(
        settled(
            source
                .apply(account, &mut db, Trust::Trusted, &|| false)
                .await
        ),
        Settled::Acknowledged(_)
    ));
    assert_eq!(qualified(), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_covering_pass_settles_trusted_and_is_acknowledged() {
    let wallet = main_wallet(1);
    let account = wallet.accounts[0].1;
    let path = wallet.path.clone();
    let _mode = test_mode::set(&path, TransparentLedgerMode::PrivateRequired);
    let mut db = open_wallet_db_with_timeout(&path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
        .unwrap();
    let map = Arc::new(Mutex::new(empty_filter_map(BIRTHDAY - 100, 0)));
    let seam = test_transport::set(&path, empty_filter_service(map.clone()));
    let source = TransparentPirSource::new(&path, MAIN);
    let covered = |db: &WalletDatabase| {
        db.transparent_candidate_recovery(account)
            .unwrap()
            .covered_through
    };
    let qualified = || count(&path, "SELECT COUNT(*) FROM tpir_qualified_revisions");
    let refused = |settlement| match settled(settlement) {
        Settled::Refused { applied, action } => (applied, action),
        other => panic!("refused, not {other:?}"),
    };
    let acknowledged = |settlement| match settled(settlement) {
        Settled::Acknowledged(stats) => stats,
        other => panic!("acknowledged, not {other:?}"),
    };

    // The policy changes after the pass read its watch set: the first commit
    // is refused, and nothing reaches the wallet.
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    bump_policy_generation(&path);
    assert_eq!(
        refused(
            source
                .apply(account, &mut db, Trust::Trusted, &|| false)
                .await
        ),
        (0, ApplyAction::Refresh)
    );
    assert_eq!((covered(&db), qualified()), (None, 0));

    // The next pass, from a fresh watch set, replays the batch. Every commit
    // applies qualified, and the batch is acknowledged.
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    let stats = acknowledged(
        source
            .apply(account, &mut db, Trust::Trusted, &|| false)
            .await,
    );
    assert!(stats.applied > 0, "the pass committed coverage");
    assert_eq!(stats.qualified, stats.applied);
    assert_eq!(covered(&db), Some(BlockHeight::from_u32(TOP)));
    assert!(db
        .transparent_candidate_recovery(account)
        .unwrap()
        .receives
        .is_empty());
    assert_eq!(qualified(), 1);
    // The acknowledged batch is spent.
    assert_eq!(
        settled(
            source
                .apply(account, &mut db, Trust::Trusted, &|| false)
                .await
        ),
        Settled::Nothing
    );

    // Replaying the acknowledged publication settles nothing new.
    let settled = (
        db.transparent_candidate_recovery(account).unwrap(),
        count(&path, "SELECT COUNT(*) FROM tpir_coverage"),
        qualified(),
    );
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    assert!(
        !acknowledged(
            source
                .apply(account, &mut db, Trust::Trusted, &|| false)
                .await
        )
        .window_grew
    );
    assert_eq!(
        (
            db.transparent_candidate_recovery(account).unwrap(),
            count(&path, "SELECT COUNT(*) FROM tpir_coverage"),
            qualified(),
        ),
        settled
    );

    // A newer revision of the shard retires the acknowledged one, which only
    // trusted commits reconcile: an observed settlement applies nothing.
    *map.lock().unwrap() = empty_filter_map(BIRTHDAY - 100, 1);
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    assert_eq!(
        refused(
            source
                .apply(account, &mut db, Trust::Observed, &|| false)
                .await
        ),
        (0, ApplyAction::Reconcile)
    );
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    let stats = acknowledged(
        source
            .apply(account, &mut db, Trust::Trusted, &|| false)
            .await,
    );
    assert_eq!(stats.qualified, stats.applied);
    assert_eq!(covered(&db), Some(BlockHeight::from_u32(TOP)));
    assert_eq!(qualified(), 2);
    // The acknowledgment forgot the retirement: the next batch does not list
    // it again, so even an observed settlement goes through.
    let watch = watched_by(&wallet, account);
    assert_eq!(
        source.recover(request(account, &watch, &|| false)).await,
        Ok(COMPLETE)
    );
    acknowledged(
        source
            .apply(account, &mut db, Trust::Observed, &|| false)
            .await,
    );

    // Covering needed only the publication and each revision's filter.
    let requests = seam.seam.observer.requests();
    assert!(
        paths(&requests)
            .iter()
            .all(|path| [MAP, INIT, FILTER].contains(path)),
        "no private query was sent"
    );
    assert_eq!(
        paths(&requests)
            .iter()
            .filter(|path| **path == FILTER)
            .count(),
        2,
        "each revision's filter was downloaded once"
    );
}

#[test]
fn routes_are_the_union_of_both_services() {
    let all = regex::Regex::new(ROUTES).unwrap();
    let history = regex::Regex::new(HISTORY_ROUTES).unwrap();
    let txid = regex::Regex::new(TXID_ROUTES).unwrap();
    let digest = "ab".repeat(32);
    for line in [
        "GET /v1/filters/shards".to_owned(),
        "GET /v1/shards/init".to_owned(),
        format!("POST /v1/shards/3/revisions/{digest}/query/pages"),
        "GET /v1/txid/init".to_owned(),
        "GET /v1/txid/map".to_owned(),
        format!("GET /v1/txid/map/32/{digest}"),
        format!("GET /v1/txid/shards/3/revisions/{digest}/manifest"),
        format!("GET /v1/txid/archive/shards/3/revisions/{digest}/setup/directory-0/0"),
        format!("POST /v1/txid/recent/shards/3/revisions/{digest}/query/directory-1"),
    ] {
        assert!(all.is_match(&line), "{line}");
        assert!(history.is_match(&line) != txid.is_match(&line), "{line}");
    }
    for line in [
        format!("GET /v1/txid/recent/shards/3/revisions/{digest}/query/directory-0"),
        format!("POST /v1/txid/recent/shards/3/revisions/{digest}/query/pages"),
        format!("GET /v1/txid/recent/shards/3/revisions/{digest}/setup/pages/0"),
        format!("POST /v1/txid/archive/shards/3/revisions/{digest}/query/txdirectory"),
        format!("GET /v1/txid/{digest}"),
        "GET /v1/txid/shards".to_owned(),
        "GET /v1/txid/map?txid=1".to_owned(),
    ] {
        assert!(!all.is_match(&line), "{line}");
    }
}

/// Loop 4's private source sends a whole lookup transcript over the txid
/// display routes only, on the wallet's route, and no request names the
/// transaction or any watched script; lightwalletd sees nothing.
#[tokio::test(flavor = "multi_thread")]
async fn txid_routes_whitelisted_no_secret_leak() {
    use crate::wallet::sync_engine::test_lwd::CapturingLwd;
    use crate::wallet::sync_engine::transparent_details::{
        followup, guarded, source::test_seam, tests as details, RunOutcome, StageClock,
    };

    let fixture = details::wallet();
    let tx = details::utxo_receipt(&fixture, 0x7e, details::TOP - 1);
    let _mode = details::require_private(&fixture.path);
    let service = details::empty_publication(details::BIRTHDAY, details::TOP);
    let _seam = test_seam::set(&fixture.path, service.clone());
    let lwd = CapturingLwd::start_with(Vec::new(), 0, |_| {}).await;
    let mut db = open_wallet_db_with_timeout(&fixture.path, MAIN, SYNC_DB_BUSY_TIMEOUT).unwrap();
    let outcome = guarded(followup(
        &mut db,
        &fixture.path,
        MAIN,
        details::required(),
        &lwd.client,
        StageClock::system(),
        &|| false,
    ))
    .await;
    assert!(
        matches!(outcome, Some(RunOutcome::Finished(stats)) if stats.deferred == 1),
        "{outcome:?}"
    );

    let requests = service.requests();
    let digest = "[0-9a-f]{64}";
    let transcript = [
        "^/v1/txid/init$".to_owned(),
        "^/v1/txid/map$".to_owned(),
        format!("^/v1/txid/shards/0/revisions/{digest}/manifest$"),
        format!("^/v1/txid/recent/shards/0/revisions/{digest}/setup/directory-0/0$"),
        format!("^/v1/txid/recent/shards/0/revisions/{digest}/query/directory-0$"),
        format!("^/v1/txid/recent/shards/0/revisions/{digest}/query/directory-0$"),
    ];
    assert_eq!(requests.len(), transcript.len(), "{:?}", paths(&requests));
    for (request, expected) in requests.iter().zip(&transcript) {
        assert!(regex::Regex::new(expected).unwrap().is_match(&request.path));
    }
    let txid = regex::Regex::new(TXID_ROUTES).unwrap();
    assert!(requests
        .iter()
        .all(|request| txid.is_match(&format!("{} {}", request.method, request.path))));
    let mut secrets = vec![tx.txid().as_ref().to_vec()];
    let mut reversed = tx.txid().as_ref().to_vec();
    reversed.reverse();
    secrets.push(reversed);
    match fixture.address {
        TransparentAddress::PublicKeyHash(hash) | TransparentAddress::ScriptHash(hash) => {
            secrets.push(hash.to_vec())
        }
    }
    assert_private(&requests, &secrets);
    assert!(lwd.requests().is_empty(), "nothing reached lightwalletd");
}
