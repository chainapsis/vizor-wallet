//! Recovery through the coordinator, against the fixture source.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use secrecy::SecretVec;
use transparent::{address::TransparentAddress, bundle::OutPoint, keys::TransparentKeyScope};
use zcash_client_backend::data_api::{
    transparent_ledger::{
        AppliedTransparentPolicy, CandidateBlocker, ReceiveEvent, SpendEvent, WatchOrigin,
        WatchedAddress,
    },
    WalletWrite,
};
use zcash_keys::encoding::AddressCodec as _;
use zcash_primitives::{block::BlockHash, transaction::TxId};
use zcash_protocol::{consensus::BlockHeight, value::Zatoshis};

use zakura_pir_client::transparent::Outcome;

use super::fixture::{FixtureSource, Observed, FIXTURE_SOURCE};
use super::*;
use crate::wallet::sync::{get_wallet_balance, TransparentBalanceAuthority};
use crate::wallet::sync_engine::enhancement::test_mode;
use crate::wallet::sync_engine::lwd::transparent_lookup::apply_transparent_policy_fenced;
use crate::wallet::sync_engine::{SyncEventKind, SyncProgressEvent};
use crate::wallet::{
    db::{open_wallet_db_with_timeout, SYNC_DB_BUSY_TIMEOUT},
    keys::{self, HardwareSignerKind},
    network::WalletNetwork,
};
use zcash_client_backend::data_api::Account as _;

const NETWORK: WalletNetwork = WalletNetwork::Regtest;
/// The highest scanned block in every fixture wallet.
const TIP: u32 = 200;
const VALUE: u64 = 2_000_000;

/// The clock every run in these tests measures with: tokio's, so a test that
/// pauses time advances it.
fn now() -> Instant {
    tokio::time::Instant::now().into_std()
}

/// Direct harness runs represent a new block. Same-block service retries
/// are exercised through the production followup gate below.
#[allow(clippy::too_many_arguments)]
async fn run<S: RecoverySource>(
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    source: &S,
    first: Option<AccountUuid>,
    clock: fn() -> Instant,
    should_exit: &(dyn Fn() -> bool + Sync),
) -> Result<RunOutcome, SyncError> {
    super::run(
        db,
        db_path,
        network,
        policy,
        source,
        first,
        RecoverySchedule::Block,
        clock,
        should_exit,
    )
    .await
}

fn chain_hash(height: u32, fork: u8) -> BlockHash {
    let mut hash = [0; 32];
    hash[..4].copy_from_slice(&height.to_le_bytes());
    hash[4] = fork;
    hash[31] = 1;
    BlockHash(hash)
}

fn main_hash(height: u32) -> BlockHash {
    chain_hash(height, 0)
}

struct Wallet {
    _dir: tempfile::TempDir,
    path: String,
    seed: SecretVec<u8>,
    uuid: String,
    account: AccountUuid,
    db: WalletDatabase,
    birthday: u32,
}

/// A software wallet contiguously scanned from its birthday through [`TIP`].
fn wallet() -> Wallet {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) =
        keys::init_db_and_create_account(&path, NETWORK, &seed, Some(100), "tpir").unwrap();
    let account = keys::parse_account_uuid(&uuid).unwrap();
    let birthday: u32 = rusqlite::Connection::open(&path)
        .unwrap()
        .query_row("SELECT MIN(birthday_height) FROM accounts", [], |row| {
            row.get(0)
        })
        .unwrap();
    scan(&path, birthday, birthday, TIP, 0);
    let db = open_wallet_db_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    Wallet {
        _dir: dir,
        path,
        seed,
        uuid,
        account,
        db,
        birthday,
    }
}

/// Records blocks `from..=through` on `fork` and marks the wallet scanned
/// contiguously from `birthday` through `through`.
fn scan(path: &str, birthday: u32, from: u32, through: u32, fork: u8) {
    let conn = rusqlite::Connection::open(path).unwrap();
    for height in from..=through {
        conn.execute(
            "INSERT OR REPLACE INTO blocks (height, hash, time, sapling_tree,
                 sapling_commitment_tree_size, orchard_commitment_tree_size,
                 ironwood_commitment_tree_size)
             VALUES (?1, ?2, 0, x'00', 0, 0, 0)",
            rusqlite::params![height, chain_hash(height, fork).0.to_vec()],
        )
        .unwrap();
    }
    conn.execute_batch(&format!(
        "DELETE FROM scan_queue;
         INSERT INTO scan_queue (block_range_start, block_range_end, priority)
         VALUES ({birthday}, {}, 10);",
        through + 1
    ))
    .unwrap();
}

fn policy(mode: TransparentLedgerMode) -> EnhancementPolicy {
    EnhancementPolicy::for_preference(NETWORK, false).with_transparent_mode(mode)
}

fn apply_policy(path: &str, mode: TransparentLedgerMode) {
    let mut db = open_wallet_db_with_timeout(path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    with_wallet_db_write_lock("test.transparent_ledger.policy", || {
        db.apply_transparent_policy(mode)
    })
    .unwrap();
}

/// The wallet's durable policy, read through a production handle.
fn applied(path: &str, network: WalletNetwork) -> AppliedTransparentPolicy {
    open_wallet_db_with_timeout(path, network, SYNC_DB_BUSY_TIMEOUT)
        .unwrap()
        .applied_transparent_policy()
        .unwrap()
}

/// An unscanned mainnet wallet, for selections only mainnet makes. Returns
/// its directory guard, path, and an open handle.
fn main_wallet() -> (tempfile::TempDir, String, WalletDatabase) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    keys::init_db_and_create_account(&path, WalletNetwork::Main, &seed, None, "tpir").unwrap();
    let db = open_wallet_db_with_timeout(&path, WalletNetwork::Main, SYNC_DB_BUSY_TIMEOUT).unwrap();
    (dir, path, db)
}

/// A wallet under a durable `PrivateRequired` policy, which permits private
/// recovery.
fn private_wallet() -> Wallet {
    let wallet = wallet();
    apply_policy(&wallet.path, TransparentLedgerMode::PrivateRequired);
    wallet
}

/// Adds a software account to `wallet`, scanned like the first. Returns its
/// UUID text and id.
fn add_account(wallet: &Wallet) -> (String, AccountUuid) {
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let (uuid, _) = keys::add_account(&wallet.path, NETWORK, "other", &seed, Some(100)).unwrap();
    // Adding an account queues its range for scanning; mark it scanned again.
    scan(&wallet.path, wallet.birthday, wallet.birthday, TIP, 0);
    let account = keys::parse_account_uuid(&uuid).unwrap();
    (uuid, account)
}

/// A source that is not configured: every call is unavailable.
fn unavailable() -> FixtureSource {
    let source = FixtureSource::new(main_hash);
    source.fail(Some(SourceError::Unavailable));
    source
}

/// Runs recovery under `PrivateRequired` with `source` untrusted: its commits
/// are observed, and qualify nothing, even from a trusted source. Runs as many
/// syncs as recovery needs; see [`until_settled`].
async fn recover(wallet: &mut Wallet, source: &FixtureSource) -> RunOutcome {
    until_settled(wallet, source, true).await
}

/// One sync's recovery run under `PrivateRequired`, with `source` untrusted.
async fn recover_once(wallet: &mut Wallet, source: &FixtureSource) -> RunOutcome {
    run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &Observed(source),
        None,
        now,
        &|| false,
    )
    .await
    .unwrap()
}

/// Syncs a recovery needs at most in these fixtures.
const SETTLE_RUNS: usize = 8;

/// Every account's recovery state: its watch set and its candidate recovery.
fn recovery_state(wallet: &Wallet) -> String {
    let accounts = wallet.db.get_account_ids().unwrap();
    let state: Vec<_> = accounts
        .into_iter()
        .map(|account| {
            (
                wallet.db.transparent_watch_set(account).ok(),
                wallet.db.transparent_candidate_recovery(account).ok(),
            )
        })
        .collect();
    format!("{state:?}")
}

/// Repeats one sync's run, as successive syncs do, until a run leaves every
/// account's recovery state unchanged or [`SETTLE_RUNS`] ran: each run makes
/// one counted pass per account, so a window that grows, or a page that
/// continues, waits for the next run. Event counts (commits, qualified, stale
/// retries, promotions) are summed over the runs; visit counts (accounts,
/// skips) are the first run's. Any outcome other than `Finished` ends the
/// repetition and is returned. `observed` runs with `source` untrusted, as
/// [`recover`] does.
async fn until_settled(wallet: &mut Wallet, source: &FixtureSource, observed: bool) -> RunOutcome {
    let mut total: Option<RunStats> = None;
    for _ in 0..SETTLE_RUNS {
        let before = recovery_state(wallet);
        let outcome = if observed {
            recover_once(wallet, source).await
        } else {
            run_required_once(wallet, source).await
        };
        let stats = match outcome {
            RunOutcome::Finished(stats) => stats,
            other => return other,
        };
        total = Some(match total {
            None => stats,
            Some(mut sum) => {
                sum.commits += stats.commits;
                sum.qualified += stats.qualified;
                sum.stale_retries += stats.stale_retries;
                sum.promoted += stats.promoted;
                sum
            }
        });
        if recovery_state(wallet) == before {
            break;
        }
    }
    RunOutcome::Finished(total.expect("at least one run"))
}

fn required() -> EnhancementPolicy {
    policy(TransparentLedgerMode::PrivateRequired)
}

/// Moves a wallet to `PrivateRequired` the only way this build applies a
/// transparent policy, and configures every handle opened on it for that
/// mode until the guard drops.
async fn activate(wallet: &mut Wallet) -> test_mode::ModeOverride {
    let mut db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    // Wait for the wallet's lookups as long as production does.
    apply_transparent_policy_fenced(
        &mut db,
        &wallet.path,
        TransparentLedgerMode::PrivateRequired,
        super::policy::POLICY_DRAIN,
    )
    .await
    .unwrap();
    let guard = test_mode::set(&wallet.path, TransparentLedgerMode::PrivateRequired);
    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    guard
}

/// Runs recovery under `PrivateRequired` from `source` as many syncs as it
/// needs; see [`until_settled`].
async fn run_required(wallet: &mut Wallet, source: &FixtureSource) -> RunOutcome {
    until_settled(wallet, source, false).await
}

/// One sync's recovery run under `PrivateRequired` from `source`.
async fn run_required_once(wallet: &mut Wallet, source: &FixtureSource) -> RunOutcome {
    run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        source,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap()
}

fn lifecycle(wallet: &Wallet, account: AccountUuid) -> AccountLifecycle {
    wallet.db.transparent_watch_set(account).unwrap().lifecycle
}

fn balance(wallet: &Wallet, uuid: &str) -> crate::wallet::sync::WalletBalance {
    get_wallet_balance(&wallet.path, NETWORK, uuid).unwrap()
}

/// A trusted fixture holding one mined receive at the account's first
/// external address.
fn funded_source(wallet: &Wallet) -> FixtureSource {
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, external(wallet, 0), VALUE, 150))
        .trust();
    source
}

fn watched(wallet: &Wallet) -> Vec<WatchedAddress> {
    wallet
        .db
        .transparent_watch_set(wallet.account)
        .unwrap()
        .addresses
}

fn derived(wallet: &Wallet, scope: TransparentKeyScope, index: u32) -> TransparentAddress {
    watched(wallet)
        .into_iter()
        .find_map(|watched| match watched.origin {
            WatchOrigin::Derived { scope: s, index: i }
            | WatchOrigin::CandidateWindow { scope: s, index: i }
                if s == scope && i.index() == index =>
            {
                Some(watched.address)
            }
            _ => None,
        })
        .expect("address is watched")
}

fn last_derived_external(wallet: &Wallet) -> u32 {
    watched(wallet)
        .iter()
        .filter_map(|watched| match watched.origin {
            WatchOrigin::Derived { scope, index } if scope == TransparentKeyScope::EXTERNAL => {
                Some(index.index())
            }
            _ => None,
        })
        .max()
        .unwrap()
}

/// The highest external index the account watches. While it is restoring,
/// that is the end of its fixed restore window, past its derived addresses.
fn last_watched_external(wallet: &Wallet) -> u32 {
    watched(wallet)
        .iter()
        .filter_map(|watched| match watched.origin {
            WatchOrigin::Derived { scope, index }
            | WatchOrigin::CandidateWindow { scope, index }
                if scope == TransparentKeyScope::EXTERNAL =>
            {
                Some(index.index())
            }
            _ => None,
        })
        .max()
        .unwrap()
}

/// The software account's external address at `index`, derived from the seed.
fn external(wallet: &Wallet, index: u32) -> TransparentAddress {
    let encoded = keys::software_account_transparent_addresses(NETWORK, &wallet.seed, 0, index + 1)
        .unwrap()
        .swap_remove(2 * index as usize);
    TransparentAddress::decode(&NETWORK, &encoded).unwrap()
}

fn receive(tag: u8, address: TransparentAddress, value: u64, height: u32) -> ReceiveEvent {
    ReceiveEvent {
        // Fixture sources, like legacy recovery sources, carry no metadata.
        metadata: None,
        outpoint: OutPoint::new([tag; 32], 0),
        address,
        value: Zatoshis::const_from_u64(value),
        coinbase: false,
        mined_height: BlockHeight::from_u32(height),
    }
}

fn spend(tag: u8, of: &ReceiveEvent, height: u32) -> SpendEvent {
    SpendEvent {
        metadata: None,
        spending_txid: TxId::from_bytes([tag; 32]),
        input_index: 0,
        prevout: of.outpoint.clone(),
        prevout_address: of.address,
        mined_height: BlockHeight::from_u32(height),
    }
}

fn count(path: &str, sql: &str) -> i64 {
    rusqlite::Connection::open(path)
        .unwrap()
        .query_row(sql, [], |row| row.get(0))
        .unwrap()
}

/// Every non-`tpir_*` table, rows rendered and sorted.
fn production_dump(path: &str) -> Vec<(String, Vec<String>)> {
    let conn = rusqlite::Connection::open(path).unwrap();
    let tables: Vec<String> = conn
        .prepare(
            "SELECT name FROM sqlite_master WHERE type = 'table'
             AND name NOT LIKE 'tpir\\_%' ESCAPE '\\' AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'
             ORDER BY name",
        )
        .unwrap()
        .query_map([], |row| row.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    tables
        .into_iter()
        .map(|table| {
            let mut statement = conn.prepare(&format!("SELECT * FROM \"{table}\"")).unwrap();
            let columns = statement.column_count();
            let mut rows: Vec<String> = statement
                .query_map([], |row| {
                    Ok((0..columns)
                        .map(|i| format!("{:?}", row.get_ref(i).unwrap()))
                        .collect::<Vec<_>>()
                        .join("|"))
                })
                .unwrap()
                .collect::<Result<_, _>>()
                .unwrap();
            rows.sort();
            (table, rows)
        })
        .collect()
}

fn assert_complete(wallet: &Wallet, source: &FixtureSource) {
    let recovery = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert_eq!(recovery.blockers, []);
    assert_eq!(recovery.covered_through, Some(BlockHeight::from_u32(TIP)));
    let (receives, spends) = source.expected(TIP);
    assert_eq!(recovery.receives, receives);
    assert_eq!(recovery.spends, spends);
}

#[tokio::test]
async fn public_policy_and_an_unavailable_source_send_nothing() {
    let mut wallet = wallet();
    let source = FixtureSource::new(main_hash);
    let exit = || false;

    // Production: the captured mode is Public, so nothing is read.
    let public = policy(TransparentLedgerMode::Public);
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        public,
        &source,
        None,
        now,
        &exit,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::NotEnabled);
    // A private handle on a durably Public wallet does not start either.
    assert_eq!(recover(&mut wallet, &source).await, RunOutcome::NotEnabled);
    assert_eq!(source.calls(), 0);

    apply_policy(&wallet.path, TransparentLedgerMode::PrivateRequired);
    let unavailable = unavailable();
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &unavailable,
        None,
        now,
        &exit,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::SourceUnavailable);
    assert_eq!(unavailable.calls(), 1, "the run stops at the first account");
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions"),
        0
    );
}

#[tokio::test]
async fn fixture_recovery_converges_to_the_exact_set() {
    let mut wallet = private_wallet();
    let first = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let change = derived(&wallet, TransparentKeyScope::INTERNAL, 0);
    let funding = receive(1, first, 50_000, 150);
    let kept = receive(2, change, 20_000, 160);
    let source = FixtureSource::new(main_hash);
    source
        .receive(funding.clone())
        .receive(kept.clone())
        .spend(spend(3, &funding, 170));

    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery did not finish");
    };
    assert_eq!((stats.accounts, stats.stale_retries), (1, 0));
    // Every pass's batch was applied and acknowledged, as applied: none
    // resolved retired revisions.
    assert_eq!(source.acknowledged(), source.calls());
    assert_eq!(source.reconciled(), 0);
    assert_complete(&wallet, &source);
    let recovery = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert_eq!(recovery.unspent, [kept.outpoint]);
    assert_eq!(recovery.recovered_unverified, Some(kept.value));
    // Every revision the coordinator committed came from the fixture.
    assert_eq!(
        count(
            &wallet.path,
            &format!(
                "SELECT COUNT(*) FROM tpir_revisions WHERE source != x'{}'",
                hex::encode(FIXTURE_SOURCE)
            )
        ),
        0
    );
}

/// Only a qualified revision withdraws older provisional evidence, so this
/// runs under `PrivateRequired` with a trusted source.
#[tokio::test]
async fn replacement_revisions_retract_withdrawn_events() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let funding = receive(1, address, 50_000, 150);
    let source = FixtureSource::new(main_hash);
    source
        .receive(funding.clone())
        .spend(spend(2, &funding, 170))
        .trust();
    run_required(&mut wallet, &source).await;
    assert_complete(&wallet, &source);

    // A complete replacement keeps the output but withdraws its spend.
    source.replace_events(vec![funding.clone()], vec![]);
    run_required(&mut wallet, &source).await;
    assert_complete(&wallet, &source);
    let replaced = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert_eq!(replaced.unspent, [funding.outpoint]);
    assert_eq!(replaced.recovered_unverified, Some(funding.value));

    // Replaying the replacement is idempotent.
    run_required(&mut wallet, &source).await;
    assert_eq!(
        wallet
            .db
            .transparent_candidate_recovery(wallet.account)
            .unwrap(),
        replaced
    );

    // A further complete replacement withdraws the receive as well.
    source.replace_events(vec![], vec![]);
    run_required(&mut wallet, &source).await;
    assert_complete(&wallet, &source);
    let empty = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert!(empty.unspent.is_empty());
    assert_eq!(empty.recovered_unverified, Some(Zatoshis::ZERO));
}

#[tokio::test]
async fn empty_ranges_complete_recovery() {
    let mut wallet = private_wallet();
    let source = FixtureSource::new(main_hash);
    assert!(matches!(
        recover(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    assert_complete(&wallet, &source);
}

#[tokio::test]
async fn partial_pages_resume_in_the_same_run_and_across_runs() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, address, 10_000, 120))
        .split_pages();
    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery did not finish");
    };
    // One pass opens the page and the next completes it; activity near the
    // window end adds a pass for the grown window.
    assert!(stats.commits >= 2);
    assert_complete(&wallet, &source);

    // The source fails after opening the page: it stays open for a later run.
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = Arc::new(FixtureSource::new(main_hash));
    source
        .receive(receive(1, address, 10_000, 120))
        .split_pages();
    let failing = source.clone();
    source.on_call(|| {}).on_call(move || {
        failing.fail(Some(SourceError::Failed));
    });
    assert!(matches!(
        recover(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    let recovery = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert!(recovery.blockers.contains(&CandidateBlocker::PendingPages));
    assert_eq!(recovery.pending_pages, 1);

    source.fail(None);
    assert!(matches!(
        recover(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    assert_complete(&wallet, &source);
}

#[tokio::test]
async fn cancellation_keeps_committed_passes() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, address, 10_000, 120))
        .split_pages();
    let exit = Arc::new(AtomicBool::new(false));
    let flag = exit.clone();
    source
        .on_call(|| {})
        .on_call(move || flag.store(true, Ordering::SeqCst));
    let should_exit = || exit.load(Ordering::SeqCst);
    // The first sync's pass leaves its first page open; the next sync is
    // cancelled during its pass.
    assert!(matches!(
        recover_once(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &Observed(&source),
        None,
        now,
        &should_exit,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::Exited);
    assert_eq!(source.calls(), 2);
    // The first pass's open page is durable; the cancelled answer is not.
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_pending_pages"),
        1
    );
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events"),
        0
    );

    assert!(matches!(
        recover(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    assert_complete(&wallet, &source);
}

#[tokio::test]
async fn window_growth_repeats_at_the_same_target() {
    let mut wallet = private_wallet();
    let before = production_dump(&wallet.path);
    let last = last_derived_external(&wallet);
    let source = FixtureSource::new(main_hash);
    // Activity at the window end extends it; activity in the extension
    // extends it again.
    source
        .receive(receive(1, external(&wallet, last), 10_000, 150))
        .receive(receive(2, external(&wallet, last + 1), 20_000, 160));

    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery did not finish");
    };
    assert!(stats.commits >= 2, "growth must trigger another pass");
    assert_complete(&wallet, &source);
    assert!(watched(&wallet)
        .iter()
        .any(|watched| matches!(watched.origin, WatchOrigin::CandidateWindow { .. })));
    // Window addresses are derived on read, never allocated.
    assert_eq!(production_dump(&wallet.path), before);
}

#[tokio::test]
async fn restart_converges_to_the_same_state() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 1);
    let source = FixtureSource::new(main_hash);
    let funding = receive(1, address, 10_000, 120);
    source
        .receive(funding.clone())
        .spend(spend(2, &funding, 130));
    recover(&mut wallet, &source).await;
    let first = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();

    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    assert!(matches!(
        recover(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    let second = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert_eq!(first, second);
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions"),
        1
    );
}

#[tokio::test]
async fn reorg_during_a_source_call_is_retried_at_the_new_target() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source.receive(receive(1, address, 10_000, 120));
    let path = wallet.path.clone();
    let birthday = wallet.birthday;
    source.on_call(move || {
        let mut db = open_wallet_db_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
        with_wallet_db_write_lock("test.transparent_ledger.reorg", || {
            db.truncate_to_height(BlockHeight::from_u32(TIP - 5))
        })
        .unwrap();
        scan(&path, birthday, TIP - 4, TIP, 1);
    });

    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery did not finish");
    };
    assert_eq!(stats.stale_retries, 1);
    assert_complete(&wallet, &source);
    let target = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap()
        .target
        .unwrap();
    assert_eq!(target.hash, chain_hash(TIP, 1));
}

#[tokio::test]
async fn account_deleted_during_a_source_call_is_skipped() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source.receive(receive(1, address, 10_000, 120));
    let path = wallet.path.clone();
    let uuid = wallet.uuid.clone();
    source.on_call(move || keys::delete_account(&path, NETWORK, &uuid).unwrap());

    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery did not finish");
    };
    assert_eq!((stats.commits, stats.stale_retries), (0, 1));
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events"),
        0
    );
}

#[tokio::test]
async fn policy_transition_during_a_source_call_stops_the_run() {
    let mut wallet = private_wallet();
    let source = FixtureSource::new(main_hash);
    let path = wallet.path.clone();
    source.on_call(move || apply_policy(&path, TransparentLedgerMode::Public));
    assert_eq!(recover(&mut wallet, &source).await, RunOutcome::NotEnabled);
    assert_eq!(count(&wallet.path, "SELECT COUNT(*) FROM tpir_coverage"), 0);
}

#[tokio::test]
async fn contradicting_the_stored_evidence_quarantines_and_skips_the_account() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let honest = FixtureSource::new(main_hash);
    honest.receive(receive(1, address, 10_000, 120));
    recover(&mut wallet, &honest).await;

    let contradicting = FixtureSource::new(main_hash);
    contradicting.receive(receive(1, address, 99_000, 120));
    let RunOutcome::Finished(stats) = recover(&mut wallet, &contradicting).await else {
        panic!("the run continues past the account");
    };
    assert_eq!((stats.accounts, stats.commits), (1, 0));
    assert_eq!(contradicting.acknowledged(), 0);
    assert_complete(&wallet, &honest);
    assert_eq!(
        count(
            &wallet.path,
            "SELECT COUNT(*) FROM tpir_quarantined_accounts"
        ),
        1
    );
}

/// Runs [`SETTLE_RUNS`] syncs' recovery from an untrusted `source` whose
/// service asks the wallet to wait each pass, letting each wait pass before
/// the next sync. Time must be paused.
async fn recover_through_waits(wallet: &mut Wallet, source: &FixtureSource) {
    for _ in 0..SETTLE_RUNS {
        recover_once(wallet, source).await;
        tokio::time::advance(Duration::from_secs(31)).await;
    }
}

/// The lagging source asks to be retried after a wait each pass; paused time
/// lets each wait pass before the next sync.
#[tokio::test(start_paused = true)]
async fn a_lagging_source_anchors_below_the_target() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, address, 10_000, 120))
        .receive(receive(2, address, 20_000, TIP - 2))
        .published_through(Some(TIP - 10));
    recover_through_waits(&mut wallet, &source).await;
    let recovery = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert_eq!(
        recovery.covered_through,
        Some(BlockHeight::from_u32(TIP - 10))
    );
    assert_eq!(recovery.blockers, [CandidateBlocker::IncompleteCoverage]);
    assert_eq!(recovery.receives.len(), 1);

    // Catching up supersedes the lagging provisional revision.
    source.published_through(None);
    recover_through_waits(&mut wallet, &source).await;
    assert_complete(&wallet, &source);
}

#[tokio::test]
async fn unsupported_ranges_block_completeness() {
    let mut wallet = private_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source.unsupported(address);
    recover(&mut wallet, &source).await;
    let recovery = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert!(recovery
        .blockers
        .contains(&CandidateBlocker::UnsupportedRanges));
}

#[tokio::test]
async fn candidate_recovery_leaves_production_state_untouched() {
    let mut wallet = private_wallet();
    let first = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let last = last_derived_external(&wallet);
    let source = FixtureSource::new(main_hash);
    let funding = receive(1, first, 50_000, 150);
    source
        .receive(funding.clone())
        .receive(receive(2, external(&wallet, last), 30_000, 160))
        .spend(spend(3, &funding, 170));

    let balance = |wallet: &Wallet| {
        let balances = crate::wallet::sync::get_wallet_balances(
            &wallet.path,
            NETWORK,
            &[wallet.uuid.as_str()],
        )
        .unwrap();
        balances
            .iter()
            .map(|b| (b.transparent, b.transparent_locked, b.transparent_pending))
            .collect::<Vec<_>>()
    };
    let history = |wallet: &Wallet| {
        crate::wallet::sync::get_transaction_history(&wallet.path, NETWORK, None, &wallet.uuid)
            .unwrap()
            .into_iter()
            .map(|tx| tx.txid_hex)
            .collect::<Vec<_>>()
    };
    let before = (
        production_dump(&wallet.path),
        balance(&wallet),
        history(&wallet),
    );

    assert!(matches!(
        recover(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    assert_complete(&wallet, &source);
    assert_eq!(
        (
            production_dump(&wallet.path),
            balance(&wallet),
            history(&wallet)
        ),
        before
    );
}

/// A source that never answers, not even to cancellation.
struct Silent;

impl RecoverySource for Silent {
    fn trusted(&self) -> bool {
        false
    }

    fn recover(
        &self,
        _request: SourceRequest<'_>,
    ) -> impl Future<Output = Result<PassReport, SourceError>> + Send {
        std::future::pending()
    }

    fn apply(
        &self,
        _account: AccountUuid,
        _db: &mut WalletDatabase,
        _trust: Trust,
        _should_exit: &(dyn Fn() -> bool + Sync),
    ) -> impl Future<Output = Result<Option<Applied>, ApplyFailure>> + Send {
        std::future::ready(Ok(None))
    }
}

#[tokio::test(start_paused = true)]
async fn a_source_past_its_time_bound_commits_nothing() {
    let mut wallet = private_wallet();
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &Silent,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(
        outcome,
        RunOutcome::Finished(RunStats {
            accounts: 1,
            ..RunStats::default()
        })
    );
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions"),
        0
    );
}

#[tokio::test]
async fn raise_needs_a_confirmed_preference() {
    use crate::wallet::sync_engine::lwd::transparent_lookup::TransparentLookupGate;

    let mut wallet = wallet();
    let before = applied(&wallet.path, NETWORK);
    let required = policy(TransparentLedgerMode::PrivateRequired);
    // A public lookup in flight, which a raise waiting at the fence would
    // wait for.
    let lookups = policy(TransparentLedgerMode::Public)
        .public_transparent_lookups(&wallet.db)
        .unwrap();
    let gate = TransparentLookupGate::for_wallet(lookups, &wallet.path, NETWORK).unwrap();
    let (release, released) = tokio::sync::oneshot::channel::<()>();
    let in_flight =
        tokio::spawn(async move { gate.dispatch(async { released.await.unwrap() }).await });
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    // A preference that could not be read opens private handles for the
    // launch, but writes nothing, and never takes the fence: it does not
    // wait for the lookup.
    let unconfirmed =
        test_mode::set_with(&wallet.path, TransparentLedgerMode::PrivateRequired, false);
    let source = unavailable();
    let outcome = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        run(
            &mut wallet.db,
            &wallet.path,
            NETWORK,
            required,
            &source,
            None,
            now,
            &|| false,
        ),
    )
    .await
    .expect("a raise that cannot apply does not wait at the fence")
    .unwrap();
    assert_eq!(outcome, RunOutcome::NotEnabled);
    assert_eq!(applied(&wallet.path, NETWORK), before);
    drop(unconfirmed);
    release.send(()).unwrap();
    assert_eq!(in_flight.await.unwrap().unwrap(), Some(()));

    let _confirmed = test_mode::set(&wallet.path, TransparentLedgerMode::PrivateRequired);
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required,
        &source,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap();
    // Raised, then stopped by the unavailable source before any request.
    assert_eq!(outcome, RunOutcome::SourceUnavailable);
    assert_eq!(
        applied(&wallet.path, NETWORK),
        AppliedTransparentPolicy {
            mode: TransparentLedgerMode::PrivateRequired,
            generation: before.generation + 1,
        }
    );
}

#[tokio::test]
async fn raise_does_not_override_a_concurrent_toggle_off() {
    use crate::wallet::sync_engine::lwd::transparent_lookup::TransparentLookupGate;

    let mut wallet = wallet();
    let before = applied(&wallet.path, NETWORK);
    // A public lookup in flight keeps the raise waiting at the fence.
    let lookups = policy(TransparentLedgerMode::Public)
        .public_transparent_lookups(&wallet.db)
        .unwrap();
    let gate = TransparentLookupGate::for_wallet(lookups, &wallet.path, NETWORK).unwrap();
    let (release, released) = tokio::sync::oneshot::channel::<()>();
    let in_flight = tokio::spawn({
        let gate = gate.clone();
        async move { gate.dispatch(async { released.await.unwrap() }).await }
    });
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    let selected = test_mode::set(&wallet.path, TransparentLedgerMode::PrivateRequired);
    let path = wallet.path.clone();
    let toggle_off = async move {
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        // Turning the setting off clears the live selection first, then
        // reconciles the wallet.
        drop(selected);
        let off = test_mode::set(&path, TransparentLedgerMode::Public);
        release.send(()).unwrap();
        let lowered = set_transparent_policy(&path, NETWORK, false).await.unwrap();
        (lowered, off)
    };
    let source = unavailable();
    let (outcome, (lowered, _off)) = tokio::join!(
        run(
            &mut wallet.db,
            &wallet.path,
            NETWORK,
            policy(TransparentLedgerMode::PrivateRequired),
            &source,
            None,
            now,
            &|| false,
        ),
        toggle_off,
    );

    assert_eq!(in_flight.await.unwrap().unwrap(), Some(()));
    assert_eq!(outcome.unwrap(), RunOutcome::NotEnabled);
    assert_eq!(lowered, None, "nothing was raised");
    assert_eq!(applied(&wallet.path, NETWORK), before);
}

/// A toggle-off that arrives after a raise decided to apply, while the raise
/// still holds the fence, waits for it and lowers what it applied instead of
/// reading the policy from before the raise and leaving it private.
#[tokio::test]
async fn a_toggle_off_behind_a_raise_lowers_what_it_applied() {
    let wallet = wallet();
    let path = wallet.path.clone();
    let before = applied(&path, NETWORK);
    let (decided, raise_decided) = tokio::sync::oneshot::channel::<()>();
    let (commit, may_commit) = std::sync::mpsc::channel::<()>();
    // The raise runs on its own thread, so its check under the fence can hold
    // it there while this runtime starts the toggle-off.
    let raise = std::thread::spawn({
        let path = path.clone();
        move || {
            let mut db = open_wallet_db_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
            db.set_transparent_ledger_mode(TransparentLedgerMode::PrivateRequired);
            let checks = std::sync::atomic::AtomicUsize::new(0);
            let decided = std::sync::Mutex::new(Some(decided));
            // The first check runs before the fence, the second under it.
            let may_raise = || {
                if checks.fetch_add(1, Ordering::SeqCst) == 1 {
                    decided.lock().unwrap().take().unwrap().send(()).unwrap();
                    may_commit.recv().unwrap();
                }
                true
            };
            tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap()
                .block_on(raise_to_required(&mut db, &path, may_raise))
                .unwrap()
        }
    });
    raise_decided.await.unwrap();

    let toggle_off = tokio::spawn({
        let path = path.clone();
        async move { set_transparent_policy(&path, NETWORK, false).await }
    });
    // Long enough for the toggle-off to open the wallet and reach the fence.
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    assert!(!toggle_off.is_finished(), "waiting behind the raise");
    commit.send(()).unwrap();
    let raised = tokio::task::spawn_blocking(move || raise.join().unwrap())
        .await
        .unwrap();
    assert!(raised);

    let lowered = toggle_off.await.unwrap().unwrap();
    let expected = AppliedTransparentPolicy {
        mode: TransparentLedgerMode::Public,
        generation: before.generation + 2,
    };
    assert_eq!(lowered, Some(expected));
    assert_eq!(applied(&path, NETWORK), expected);
}

#[tokio::test]
async fn private_queries_off_pauses_a_private_wallet_without_weakening_it() {
    let network = WalletNetwork::Main;
    let (_dir, path, mut db) = main_wallet();
    with_wallet_db_write_lock("test.transparent_ledger.policy", || {
        db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
    })
    .unwrap();
    let before = applied(&path, network);
    // Private queries off while a prior private policy remains applied.
    let private_queries_off = EnhancementPolicy::for_preference(network, false);
    assert_eq!(
        private_queries_off.transparent_mode(),
        TransparentLedgerMode::Public
    );
    let source = FixtureSource::new(main_hash);

    let outcome = run(
        &mut db,
        &path,
        network,
        private_queries_off,
        &source,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::NotEnabled);
    assert_eq!(source.calls(), 0);
    // Startup only reconciles upward and preserves this prior policy.
    assert_eq!(
        set_transparent_policy(&path, network, true).await.unwrap(),
        None
    );
    assert_eq!(applied(&path, network), before);

    // Handles keep the wallet's policy, so public lookups stay withheld.
    let mut reopened = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    private_queries_off.configure_db(&mut reopened);
    assert_eq!(
        reopened.transparent_ledger_mode().unwrap(),
        TransparentLedgerMode::PrivateRequired
    );
    assert_eq!(
        private_queries_off
            .public_transparent_lookups(&reopened)
            .unwrap(),
        crate::wallet::sync_engine::enhancement::PublicTransparentLookups::Withheld
    );
}

/// Quarantines `account` as an integrity failure involving its evidence
/// would.
fn quarantine(path: &str, account: AccountUuid) {
    rusqlite::Connection::open(path)
        .unwrap()
        .execute(
            "INSERT INTO tpir_quarantined_accounts (account_id)
             SELECT id FROM accounts WHERE uuid = ?1",
            [account.expose_uuid().as_bytes().as_slice()],
        )
        .unwrap();
}

/// Imports a Ledger account into `wallet`, scanned like the first.
fn import_ledger(wallet: &Wallet) -> AccountUuid {
    use secrecy::ExposeSecret;
    let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
    let ufvk = zcash_keys::keys::UnifiedSpendingKey::from_seed(
        &NETWORK,
        seed.expose_secret(),
        zip32::AccountId::ZERO,
    )
    .unwrap()
    .to_unified_full_viewing_key();
    let fingerprint = zip32::fingerprint::SeedFingerprint::from_seed(seed.expose_secret())
        .unwrap()
        .to_bytes();
    let (uuid, _) = keys::import_hardware_account(
        &wallet.path,
        NETWORK,
        "Ledger",
        &ufvk.encode(&NETWORK),
        &fingerprint,
        0,
        Some(100),
        HardwareSignerKind::Ledger,
    )
    .unwrap();
    scan(&wallet.path, wallet.birthday, wallet.birthday, TIP, 0);
    keys::parse_account_uuid(&uuid).unwrap()
}

#[tokio::test]
async fn a_trusted_source_qualifies_each_revision_before_applying_it() {
    let qualified = |path: &str| count(path, "SELECT COUNT(*) FROM tpir_qualified_revisions");

    // An untrusted source's commits apply, qualify nothing, and leave the
    // account a candidate.
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let untrusted = FixtureSource::new(main_hash);
    untrusted.receive(receive(1, external(&wallet, 0), VALUE, 150));
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &untrusted).await else {
        panic!("recovery finishes");
    };
    assert!(stats.commits > 0);
    assert_eq!((stats.qualified, stats.promoted), (0, 0));
    assert_eq!(qualified(&wallet.path), 0);

    // The same facts from a trusted source qualify their revision in the
    // transaction that applies them, so the account is promoted.
    let trusted = funded_source(&wallet);
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &trusted).await else {
        panic!("recovery finishes");
    };
    assert!(stats.commits > 0);
    assert_eq!((stats.qualified, stats.promoted), (stats.commits, 1));
    // Every pass answered from the one publication, so one revision.
    assert_eq!(qualified(&wallet.path), 1);
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );

    // Each later revision is qualified as it is applied, so an active
    // account keeps taking commits.
    trusted.replace_events(vec![receive(1, external(&wallet, 0), VALUE, 150)], vec![]);
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &trusted).await else {
        panic!("recovery finishes");
    };
    assert!(stats.commits > 0);
    assert_eq!(stats.qualified, stats.commits);
    assert_eq!(qualified(&wallet.path), 2);
    assert_eq!(
        count(
            &wallet.path,
            "SELECT COUNT(*) FROM tpir_coverage c WHERE NOT EXISTS (
                 SELECT 1 FROM tpir_qualified_revisions q WHERE q.revision_id = c.revision_id
             )"
        ),
        0,
        "no unqualified evidence remains"
    );
}

#[tokio::test]
async fn a_pending_batch_applies_and_acknowledges_nothing() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    source.pending(Some(Outcome::Complete));

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.accounts, stats.commits, stats.promoted), (1, 0, 0));
    assert_eq!((source.calls(), source.acknowledged()), (1, 0));
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_revisions"),
        0
    );
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );

    // Once the publication catches up, the next run recovers and promotes,
    // acknowledging each of its batches.
    source.pending(None);
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 1);
    assert_eq!(source.acknowledged(), source.calls() - 1);
}

#[tokio::test]
async fn a_withdrawn_batch_holds_only_that_account() {
    let mut wallet = wallet();
    let (_, other) = add_account(&wallet);
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    source.withdraw(wallet.account, Some(WithdrawnCause::Regression));

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.accounts, stats.promoted, stats.held), (2, 1, 0));
    assert_eq!(
        recovery_hold(&wallet.path, wallet.account),
        Some(HoldCause::Withdrawn(WithdrawnCause::Regression))
    );
    assert_eq!(recovery_hold(&wallet.path, other), None);
    assert_eq!(lifecycle(&wallet, other), AccountLifecycle::Active);
    assert_eq!(
        count(&wallet.path, "SELECT COUNT(*) FROM tpir_receive_events"),
        0,
        "nothing of the withdrawn account's batch applied"
    );

    // The next run skips the held account without asking the source.
    let other_calls = source.calls_for(other);
    let RunOutcome::Finished(stats) = run_required_once(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.accounts, stats.held), (1, 1));
    assert_eq!(source.calls_for(wallet.account), 1);
    assert_eq!(source.calls_for(other), other_calls + 1);

    // Once the hold ends, the account is retried, and later syncs promote it.
    fn after_the_hold() -> Instant {
        now() + HOLD + Duration::from_secs(1)
    }
    source.withdraw(wallet.account, None);
    let asked = source.calls_for(wallet.account);
    let (mut held, mut promoted) = (0, 0);
    for _ in 0..SETTLE_RUNS {
        let outcome = run(
            &mut wallet.db,
            &wallet.path,
            NETWORK,
            required(),
            &Observed(&source),
            None,
            after_the_hold,
            &|| false,
        )
        .await
        .unwrap();
        let RunOutcome::Finished(stats) = outcome else {
            panic!("recovery finishes");
        };
        held += stats.held;
        promoted += stats.promoted;
    }
    assert_eq!((held, promoted), (0, 1));
    assert!(source.calls_for(wallet.account) > asked);
}

#[tokio::test]
async fn a_batch_is_acknowledged_only_after_every_commit_applies() {
    let mut wallet = private_wallet();
    let path = wallet.path.clone();
    let addresses = watched(&wallet).len() as i64;
    assert!(addresses >= 2, "the batch splits its addresses");
    // No activity, so no window growth: one pass, one batch of two commits.
    let source = FixtureSource::new(main_hash);
    source.split_commits();
    // At each acknowledgment, the addresses the wallet holds coverage for.
    let seen = Arc::new(std::sync::Mutex::new(Vec::new()));
    source.on_acknowledge({
        let (seen, path) = (seen.clone(), path.clone());
        move || {
            let covered = count(&path, "SELECT COUNT(DISTINCT script) FROM tpir_coverage");
            seen.lock().unwrap().push(covered);
        }
    });

    let RunOutcome::Finished(stats) = recover_once(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.commits, 2);
    assert_eq!(source.acknowledged(), 1);
    assert_eq!(
        *seen.lock().unwrap(),
        [addresses],
        "both commits applied first"
    );

    // A batch whose last commit is refused is not acknowledged; the commits
    // before it stay applied.
    source.replace_events(vec![], vec![]).then_invalid(true);
    let RunOutcome::Finished(stats) = recover_once(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.commits, 2);
    assert_eq!(source.acknowledged(), 1);
    assert_eq!(seen.lock().unwrap().len(), 1);
    // A commit registers its revision only when it applies.
    assert_eq!(
        count(
            &path,
            "SELECT COUNT(*) FROM tpir_revisions WHERE lineage = 2"
        ),
        1
    );
}

/// Coverage the fixture's first revision supports, which a replacement
/// retires.
const RETIRED_COVERAGE: &str = "SELECT COUNT(*) FROM tpir_coverage c
     JOIN tpir_revisions r ON r.id = c.revision_id WHERE r.lineage = 1";

/// A batch that resolves retired revisions is acknowledged as reconciled, once
/// every commit went through the trusted operation, which withdrew the retired
/// revision's provisional evidence. Batches without retirements are
/// acknowledged as applied.
#[tokio::test]
async fn retired_revisions_are_acknowledged_after_trusted_reconciliation() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let path = wallet.path.clone();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let funding = receive(1, address, 50_000, 150);
    let source = FixtureSource::new(main_hash);
    source
        .receive(funding.clone())
        .spend(spend(2, &funding, 170))
        .trust();
    run_required(&mut wallet, &source).await;
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
    assert_eq!(
        (source.acknowledged(), source.reconciled()),
        (source.calls(), 0)
    );

    // The publication replaces its revision, and its batches name the
    // retired one until a reconciled acknowledgment. At each acknowledgment:
    // the qualified revisions, and the retired revision's coverage.
    let seen = Arc::new(std::sync::Mutex::new(Vec::new()));
    source.on_acknowledge({
        let (seen, path) = (seen.clone(), path.clone());
        move || {
            seen.lock().unwrap().push((
                count(&path, "SELECT COUNT(*) FROM tpir_qualified_revisions"),
                count(&path, RETIRED_COVERAGE),
            ));
        }
    });
    source
        .replace_events(vec![funding.clone()], vec![])
        .retire();
    let (calls, acknowledged) = (source.calls(), source.acknowledged());
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.qualified, stats.commits);
    assert_eq!(source.reconciled(), 1);
    assert_eq!(
        source.acknowledged() - acknowledged,
        source.calls() - calls,
        "every batch was acknowledged"
    );
    assert_eq!(
        seen.lock().unwrap()[0],
        (2, 0),
        "the successor was qualified and the retired evidence withdrawn first"
    );
    assert_eq!(recovery_hold(&path, wallet.account), None);
    assert_complete(&wallet, &source);
}

/// Without the trusted operation, a batch that resolves retired revisions is
/// refused before any commit applies, never acknowledged, and its account is
/// held.
#[tokio::test]
async fn unreconciled_retirements_acknowledge_nothing_and_hold_the_account() {
    // The trusted origin, observed, which qualifies nothing.
    let mut observed = private_wallet();
    let source = funded_source(&observed);
    recover(&mut observed, &source).await;
    let acknowledged = source.acknowledged();
    assert_eq!(acknowledged, source.calls());
    source.replace_events(vec![], vec![]).retire();
    let before = production_dump(&observed.path);
    let RunOutcome::Finished(stats) = recover(&mut observed, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.commits, stats.qualified), (0, 0));
    assert_eq!(production_dump(&observed.path), before);
    assert_eq!(source.acknowledged(), acknowledged);
    // Only reconciliation withdraws the retired revision's evidence.
    assert!(count(&observed.path, RETIRED_COVERAGE) > 0);
    assert_eq!(
        recovery_hold(&observed.path, observed.account),
        Some(HoldCause::Unreconciled)
    );
    // The held account is skipped without asking the source.
    let calls = source.calls();
    let RunOutcome::Finished(stats) = recover(&mut observed, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.held, 1);
    assert_eq!(source.calls(), calls);

    // An untrusted source under `PrivateRequired` is held the same way, and
    // its account stays a candidate.
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let untrusted = FixtureSource::new(main_hash);
    untrusted
        .receive(receive(1, external(&wallet, 0), VALUE, 150))
        .retire();
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &untrusted).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.commits, stats.qualified, stats.promoted), (0, 0, 0));
    assert_eq!(untrusted.acknowledged(), 0);
    assert_eq!(
        recovery_hold(&wallet.path, wallet.account),
        Some(HoldCause::Unreconciled)
    );
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );
}

/// A lagging publication ends the run with the service's delay: the account
/// is skipped without a source call until the delay passes, and the next run
/// after it asks again; once the service caught up, later runs restore
/// authority. Nothing waits inside a run.
#[tokio::test]
async fn a_lagging_source_is_asked_again_only_after_its_delay() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    // Paused time lets the test move the clock. Activation's drain must not
    // see it.
    tokio::time::pause();
    let source = funded_source(&wallet);
    source.published_through(Some(TIP - 10));

    let RunOutcome::Finished(stats) = run_required_once(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(
        source.calls(),
        1,
        "one pass, and no second one after waiting"
    );
    assert_eq!((stats.waiting, stats.promoted), (0, 0));

    // The service catches up, but its delay has not passed: no request.
    source.published_through(None);
    tokio::time::advance(Duration::from_secs(5)).await;
    let RunOutcome::Finished(stats) = run_required_once(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(source.calls(), 1);
    assert_eq!((stats.accounts, stats.waiting), (0, 1));

    // After the delay the account is asked again, and later syncs finish
    // recovery.
    tokio::time::advance(Duration::from_secs(10)).await;
    let RunOutcome::Finished(stats) = run_required_once(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(source.calls(), 2);
    assert_eq!(stats.waiting, 0);
    run_required(&mut wallet, &source).await;
    let current = balance(&wallet, &wallet.uuid);
    assert_eq!(
        current.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(current.transparent, VALUE);
}

/// A failed selected entry cannot remove a public service wait, even when
/// another block or a reorg makes recovery eligible before it expires.
#[tokio::test]
async fn content_failure_preserves_service_wait_across_new_blocks_and_reorgs() {
    for outcome in [Outcome::Behind, Outcome::Overloaded] {
        for failed in [0, 1] {
            let mut wallet = wallet();
            let _mode = activate(&mut wallet).await;
            let source = funded_source(&wallet);
            source.next(Some(outcome));
            source.failed_entries(zakura_pir_client::transparent::FailedEntries {
                entries: failed,
                held: 0,
            });
            followup(&mut wallet, &source, &|_| {}, (200, 200)).await;
            assert_eq!(source.calls(), 1);
            followup(&mut wallet, &source, &|_| {}, (200, 201)).await;
            assert_eq!(source.calls(), 1, "the next block preserves the wait");
            clear_recovery_tip(&wallet.path);
            followup(&mut wallet, &source, &|_| {}, (200, 200)).await;
            assert_eq!(source.calls(), 1, "a rewind preserves the wait");
        }
    }
}

/// Exercise the outer followup gate, rather than calling the account runner
/// directly: an expired public wait must permit recovery at the same tip.
#[tokio::test]
async fn expired_service_wait_runs_followup_at_the_same_tip() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    source.published_through(Some(TIP - 1));
    followup(&mut wallet, &source, &|_| {}, (200, 200)).await;
    assert_eq!(source.calls(), 1);
    source.published_through(None);
    assert!(!service_retry_due(&wallet.path));
    // Expire the service deadline without a wall-clock sleep.
    set_not_before(&wallet.path, wallet.account, Instant::now(), Duration::ZERO);
    let status =
        crate::wallet::sync_engine::recovery_status_for(&wallet.db, &wallet.path, String::new())
            .unwrap();
    assert!(
        status.transparent_retry_due,
        "the app poll sees the expired wait"
    );
    followup(&mut wallet, &source, &|_| {}, (200, 200)).await;
    assert_eq!(source.calls(), 2, "catch up before another block arrives");
    assert!(
        !service_retry_due(&wallet.path),
        "the deadline was consumed"
    );
    followup(&mut wallet, &source, &|_| {}, (200, 200)).await;
    assert_eq!(source.calls(), 2, "the expired deadline is consumed once");
}

#[tokio::test]
async fn a_stale_commit_does_not_bypass_the_service_wait() {
    let mut wallet = private_wallet();
    let source = FixtureSource::new(main_hash);
    source.next(Some(Outcome::Behind));
    let path = wallet.path.clone();
    let birthday = wallet.birthday;
    source.on_call(move || {
        let mut db = open_wallet_db_with_timeout(&path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
        with_wallet_db_write_lock("test.transparent_ledger.reorg", || {
            db.truncate_to_height(BlockHeight::from_u32(TIP - 5))
        })
        .unwrap();
        scan(&path, birthday, TIP - 4, TIP, 1);
    });
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        Some(wallet.account),
        now,
        &|| false,
    )
    .await
    .unwrap();
    let RunOutcome::Finished(stats) = outcome else {
        panic!("recovery finishes")
    };
    assert_eq!(stats.stale_retries, 1);
    assert_eq!(
        source.calls(),
        1,
        "the stale commit waits instead of asking again"
    );
    assert!(waiting_at(&wallet.path, wallet.account, now()));
}

/// Cancellation during settlement must preserve a new service delay, while
/// an interrupted retry with no new delay stays eligible for the next sync.
#[tokio::test(start_paused = true)]
async fn cancelling_a_service_retry_preserves_its_new_wait() {
    struct InterruptSettlement<'a> {
        source: &'a FixtureSource,
        exit: &'a AtomicBool,
        outcome: Outcome,
    }
    impl RecoverySource for InterruptSettlement<'_> {
        fn trusted(&self) -> bool {
            self.source.trusted()
        }
        fn recover(
            &self,
            request: SourceRequest<'_>,
        ) -> impl Future<Output = Result<PassReport, SourceError>> + Send {
            self.source.recover(request)
        }
        fn apply(
            &self,
            _account: AccountUuid,
            _db: &mut WalletDatabase,
            _trust: Trust,
            _should_exit: &(dyn Fn() -> bool + Sync),
        ) -> impl Future<Output = Result<Option<Applied>, ApplyFailure>> + Send {
            self.exit.store(true, Ordering::SeqCst);
            std::future::ready(Err(ApplyFailure {
                error: zakura_pir_client::transparent::ApplyError::Interrupted,
                stats: zakura_pir_client::transparent::ApplyStats::default(),
                progress: zakura_pir_client::transparent::Progress {
                    covered_through: 0,
                    outcome: self.outcome,
                },
            }))
        }
    }
    for (outcome, delay) in [
        (Outcome::Behind, Some(Retry::BEHIND)),
        (Outcome::Overloaded, Some(Retry::OVERLOADED)),
        (Outcome::Complete, None),
    ] {
        let mut wallet = private_wallet();
        let source = FixtureSource::new(main_hash);
        source.next(Some(outcome));
        let exit = AtomicBool::new(false);
        let interrupted = InterruptSettlement {
            source: &source,
            exit: &exit,
            outcome,
        };
        recovery_ran(&wallet.path, u64::from(TIP));
        set_not_before(&wallet.path, wallet.account, now(), Duration::ZERO);
        let result = super::run(
            &mut wallet.db,
            &wallet.path,
            NETWORK,
            required(),
            &interrupted,
            Some(wallet.account),
            RecoverySchedule::ServiceWait,
            now,
            &|| exit.load(Ordering::SeqCst),
        )
        .await
        .unwrap();
        assert_eq!(result, RunOutcome::Exited);
        assert_eq!(source.calls(), 1);
        assert_eq!(
            waiting_at(&wallet.path, wallet.account, now()),
            delay.is_some(),
            "cancellation cannot erase a fresh service delay"
        );
        if let Some(delay) = delay {
            tokio::time::advance(delay - Duration::from_secs(1)).await;
            assert!(waiting_at(&wallet.path, wallet.account, now()));
            recover_once(&mut wallet, &source).await;
            assert_eq!(source.calls(), 1, "resume respects the remaining wait");
            tokio::time::advance(Duration::from_secs(1)).await;
            assert!(!waiting_at(&wallet.path, wallet.account, now()));
        }
        // At expiry (or with no new delay), the next sync may ask again.
        source.next(Some(Outcome::Complete));
        recover_once(&mut wallet, &source).await;
        assert_eq!(source.calls(), 2);
    }
}

/// A public wait for one account cannot unlock another account's pass at
/// the same block, even if that account still has unfinished recovery.
#[tokio::test]
async fn expired_service_wait_retries_only_its_account() {
    let mut wallet = private_wallet();
    let (_, other) = add_account(&wallet);
    let source = FixtureSource::new(main_hash);
    followup(&mut wallet, &source, &|_| {}, (200, 200)).await;
    assert_eq!(source.calls_for(wallet.account), 1);
    assert_eq!(source.calls_for(other), 1);
    set_not_before(&wallet.path, wallet.account, Instant::now(), Duration::ZERO);
    followup(&mut wallet, &source, &|_| {}, (200, 200)).await;
    assert_eq!(source.calls_for(wallet.account), 2);
    assert_eq!(
        source.calls_for(other),
        1,
        "unrelated work waits for a block"
    );
}

/// An active account can catch up to each new block after the publication
/// briefly trails it, recovering spend authority before the next block.
#[tokio::test]
async fn service_wait_catch_up_restores_current_authority() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    run_required(&mut wallet, &source).await;
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );
    for tip in TIP + 1..=TIP + 3 {
        scan(&wallet.path, wallet.birthday, tip, tip, 0);
        wallet
            .db
            .update_chain_tip(BlockHeight::from_u32(tip))
            .unwrap();
        source.published_through(Some(tip - 1));
        followup(&mut wallet, &source, &|_| {}, (tip.into(), tip.into())).await;
        assert_ne!(
            balance(&wallet, &wallet.uuid).transparent_authority,
            TransparentBalanceAuthority::Current
        );
        source.published_through(None);
        set_not_before(&wallet.path, wallet.account, Instant::now(), Duration::ZERO);
        followup(&mut wallet, &source, &|_| {}, (tip.into(), tip.into())).await;
        assert_eq!(
            balance(&wallet, &wallet.uuid).transparent_authority,
            TransparentBalanceAuthority::Current
        );
    }
}

/// A capacity refusal ends each account's pass with the service's delay; the
/// other accounts still get theirs, and no account is asked again before the
/// delay passes.
#[tokio::test(start_paused = true)]
async fn a_capacity_refusal_defers_each_account_to_a_run_after_its_delay() {
    let mut wallet = private_wallet();
    let (_, other) = add_account(&wallet);
    let source = FixtureSource::new(main_hash);
    // A capacity refusal asks for thirty seconds.
    source.next(Some(Outcome::Overloaded));

    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &Observed(&source),
        Some(wallet.account),
        now,
        &|| false,
    )
    .await
    .unwrap();
    let RunOutcome::Finished(stats) = outcome else {
        panic!("recovery finishes");
    };
    assert_eq!(source.calls_for(wallet.account), 1);
    assert_eq!(source.calls_for(other), 1);
    assert_eq!((stats.accounts, stats.waiting), (2, 0));

    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.accounts, stats.waiting), (0, 2));
    assert_eq!(source.calls(), 2);

    tokio::time::advance(Duration::from_secs(31)).await;
    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.accounts, stats.waiting), (2, 0));
    assert_eq!(source.calls(), 4);
}

#[tokio::test]
async fn the_active_account_runs_first_and_others_rotate() {
    let mut wallet = private_wallet();
    let (_, b) = add_account(&wallet);
    let (_, c) = add_account(&wallet);
    let source = FixtureSource::new(main_hash);
    for _ in 0..3 {
        let outcome = run(
            &mut wallet.db,
            &wallet.path,
            NETWORK,
            required(),
            &source,
            Some(c),
            now,
            &|| false,
        )
        .await
        .unwrap();
        assert!(matches!(outcome, RunOutcome::Finished(_)));
    }
    let order = source.order();
    assert_eq!(order.len(), 9, "one pass per account per run");
    let runs: Vec<_> = order.chunks(3).collect();
    for run in &runs {
        assert_eq!(run[0], c, "the active account goes first");
    }
    let rest: Vec<_> = runs.iter().map(|run| run[1..].to_vec()).collect();
    assert_eq!(
        rest[0]
            .iter()
            .copied()
            .collect::<std::collections::BTreeSet<_>>(),
        [wallet.account, b].into()
    );
    assert_eq!(rest[1], [rest[0][1], rest[0][0]], "the others rotate");
    assert_eq!(rest[2], rest[0]);

    // Without an active account, every account takes its turn first.
    let source = FixtureSource::new(main_hash);
    for _ in 0..3 {
        recover(&mut wallet, &source).await;
    }
    let firsts: std::collections::BTreeSet<_> =
        source.order().chunks(3).map(|run| run[0]).collect();
    assert_eq!(firsts, [wallet.account, b, c].into());
}

#[tokio::test]
async fn a_quarantined_or_held_account_is_skipped_without_a_source_call() {
    let mut wallet = wallet();
    let (_, held) = add_account(&wallet);
    let (_, open) = add_account(&wallet);
    let _mode = activate(&mut wallet).await;
    quarantine(&wallet.path, wallet.account);
    set_hold(&wallet.path, held, HoldCause::FailedEntries, now());
    let source = FixtureSource::new(main_hash);
    source.trust();

    let RunOutcome::Finished(stats) = run_required_once(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.quarantined, stats.held, stats.accounts), (1, 1, 1));
    assert_eq!(source.order(), [open]);
}

/// A run that stalls, however often, never holds the account: it is asked
/// again at the next sync, so a reply that failed never changes when the
/// account is asked next.
#[tokio::test]
async fn stalled_runs_never_hold_the_account() {
    let mut wallet = private_wallet();
    let source = FixtureSource::new(main_hash);
    source.next(Some(Outcome::Stalled));
    for run in 1..=5 {
        let RunOutcome::Finished(stats) = recover_once(&mut wallet, &source).await else {
            panic!("recovery finishes");
        };
        assert_eq!(stats.held, 0);
        assert_eq!(recovery_hold(&wallet.path, wallet.account), None);
        assert_eq!(source.calls(), run);
    }
}

#[tokio::test]
async fn a_legacy_discrepancy_holds_the_account() {
    use transparent::bundle::TxOut;
    use zcash_client_backend::wallet::WalletTransparentOutput;

    let mut wallet = wallet();
    wallet
        .db
        .update_chain_tip(BlockHeight::from_u32(TIP))
        .unwrap();
    // Public discovery stored an output the private source does not report.
    let legacy = WalletTransparentOutput::from_parts(
        OutPoint::new([0x51; 32], 0),
        TxOut::new(
            Zatoshis::const_from_u64(VALUE),
            external(&wallet, 0).script().into(),
        ),
        Some(BlockHeight::from_u32(150)),
        Some(wallet.account),
        Some(TransparentKeyScope::EXTERNAL),
        None,
    )
    .unwrap();
    wallet.db.put_received_transparent_utxo(&legacy).unwrap();
    let _mode = activate(&mut wallet).await;
    let source = FixtureSource::new(main_hash);
    source.trust();

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 0);
    assert_eq!(
        recovery_hold(&wallet.path, wallet.account),
        Some(HoldCause::LegacyDiscrepancy)
    );
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.held, 1);
    assert_eq!(source.calls(), 1, "the held account costs no traffic");
}

/// A pass whose directory entry reached three content failures holds the
/// account once everything else it read has settled. The balance read
/// reports the stop reason a stalled recovery already shows, and the held
/// account costs no traffic.
#[tokio::test]
async fn a_directory_entry_failed_three_times_holds_the_account() {
    use crate::wallet::sync::TransparentStopReason;
    use zakura_pir_client::transparent::FailedEntries;

    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    source.failed_entries(FailedEntries {
        entries: 1,
        held: 1,
    });

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.commits, 1, "the rest of the pass settled");
    assert_eq!(
        recovery_hold(&wallet.path, wallet.account),
        Some(HoldCause::FailedEntries)
    );
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_stop,
        Some(TransparentStopReason::Stalled)
    );

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.held, 1);
    assert_eq!(source.calls(), 1, "the held account costs no traffic");
}

#[tokio::test]
async fn cancellation_during_a_pass_applies_nothing_from_it() {
    let mut wallet = private_wallet();
    let source = FixtureSource::new(main_hash);
    source.receive(receive(1, external(&wallet, 0), 10_000, 150));
    let exit = Arc::new(AtomicBool::new(false));
    let flag = exit.clone();
    // Cancellation arrives while the source answers.
    source.on_call(move || flag.store(true, Ordering::SeqCst));
    let should_exit = || exit.load(Ordering::SeqCst);

    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        None,
        now,
        &should_exit,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::Exited);
    assert_eq!((source.calls(), source.acknowledged()), (1, 0));
    for table in ["tpir_revisions", "tpir_coverage", "tpir_receive_events"] {
        assert_eq!(
            count(&wallet.path, &format!("SELECT COUNT(*) FROM {table}")),
            0,
            "{table}"
        );
    }
}

/// Selects the imported Ledger account as the subject of these recovery tests.
fn ledger_wallet() -> Wallet {
    let mut wallet = wallet();
    wallet.account = import_ledger(&wallet);
    wallet.uuid = wallet.account.expose_uuid().to_string();
    wallet
}

fn ledger_address(wallet: &Wallet, scope: TransparentKeyScope, index: u32) -> TransparentAddress {
    use transparent::keys::{IncomingViewingKey, NonHardenedChildIndex};
    let account = wallet.db.get_account(wallet.account).unwrap().unwrap();
    let transparent = account.ufvk().unwrap().transparent().unwrap();
    let index = NonHardenedChildIndex::from_index(index).unwrap();
    if scope == TransparentKeyScope::EXTERNAL {
        transparent
            .derive_external_ivk()
            .unwrap()
            .derive_address(index)
            .unwrap()
    } else {
        transparent
            .derive_internal_ivk()
            .unwrap()
            .derive_address(index)
            .unwrap()
    }
}

#[tokio::test]
async fn a_ledger_account_recovers_privately_and_can_shield() {
    use super::tests::activation::checkpoint_trees;
    use crate::wallet::sync::{get_shield_transparent_status, get_transaction_history};

    let mut wallet = ledger_wallet();
    let address = ledger_address(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source.receive(receive(1, address, VALUE, 150)).trust();
    let _mode = activate(&mut wallet).await;
    let pending = balance(&wallet, &wallet.uuid);
    assert_eq!(pending.transparent, 0);
    assert_eq!(
        pending.transparent_stop, None,
        "hardware recovery is pending, not stopped"
    );

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.promoted, 2, "both software and Ledger recover");
    assert!(source.calls_for(wallet.account) > 0);
    assert_eq!(
        source.requested_from(wallet.account),
        [BlockHeight::from_u32(wallet.birthday)].into()
    );
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
    let current = balance(&wallet, &wallet.uuid);
    assert_eq!(
        (current.transparent_authority, current.transparent),
        (TransparentBalanceAuthority::Current, VALUE)
    );
    assert_eq!(current.transparent_stop, None);
    let history = get_transaction_history(&wallet.path, NETWORK, None, &wallet.uuid).unwrap();
    assert_eq!(history.len(), 1);
    assert_eq!(history[0].txid_hex, hex::encode([1; 32]));
    checkpoint_trees(&mut wallet, TIP);
    let shielding = get_shield_transparent_status(&wallet.path, NETWORK, &wallet.uuid).unwrap();
    assert!(shielding.can_shield, "{}", shielding.reason);
}

#[tokio::test]
async fn ledger_spent_receiving_and_change_addresses_extend_private_discovery() {
    let mut wallet = ledger_wallet();
    let _mode = activate(&mut wallet).await;
    let source = FixtureSource::new(main_hash);
    source.trust();
    // Fully spent history fills the initial gaps; funded addresses beyond them
    // must be found by later passes, for both receiving and change scopes.
    for (scope, gap, tag_base) in [
        (TransparentKeyScope::EXTERNAL, 10, 10u8),
        (TransparentKeyScope::INTERNAL, 5, 50u8),
    ] {
        for index in 0..=gap {
            let tag = tag_base + index as u8;
            let funding = receive(tag, ledger_address(&wallet, scope, index), VALUE, 120);
            source.receive(funding.clone());
            if index < gap {
                source.spend(spend(tag + 100, &funding, 130));
            }
        }
    }
    run_required(&mut wallet, &source).await;
    assert!(
        source.calls_for(wallet.account) > 1,
        "used gaps require another pass"
    );
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, 2 * VALUE);
    assert_eq!(lifecycle(&wallet, wallet.account), AccountLifecycle::Active);
    let recovery = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert_eq!((recovery.receives.len(), recovery.spends.len()), (17, 15));
}

#[tokio::test]
async fn interrupted_ledger_recovery_resumes_after_reopening_under_private_policy() {
    let mut wallet = ledger_wallet();
    let address = ledger_address(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source.receive(receive(1, address, VALUE, 150)).trust();
    let mode = activate(&mut wallet).await;
    let exit = Arc::new(AtomicBool::new(false));
    let flag = exit.clone();
    source.on_call(move || flag.store(true, Ordering::SeqCst));
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        Some(wallet.account),
        now,
        &|| exit.load(Ordering::SeqCst),
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::Exited);
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, 0);
    drop(mode);
    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    assert_eq!(
        applied(&wallet.path, NETWORK).mode,
        TransparentLedgerMode::PrivateRequired
    );
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, 0);
    let _mode = test_mode::set(&wallet.path, TransparentLedgerMode::PrivateRequired);
    run_required(&mut wallet, &source).await;
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, VALUE);
}

#[tokio::test]
async fn ledger_private_recovery_honors_the_stored_birthday() {
    let mut wallet = ledger_wallet();
    let address = ledger_address(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, address, VALUE, wallet.birthday - 1))
        .receive(receive(2, address, VALUE, wallet.birthday))
        .trust();
    let _mode = activate(&mut wallet).await;
    run_required(&mut wallet, &source).await;
    assert_eq!(
        source.requested_from(wallet.account),
        [BlockHeight::from_u32(wallet.birthday)].into()
    );
    assert_eq!(balance(&wallet, &wallet.uuid).transparent, VALUE);
    let recovery = wallet
        .db
        .transparent_candidate_recovery(wallet.account)
        .unwrap();
    assert_eq!(recovery.receives.len(), 1);
    assert_eq!(recovery.receives[0].outpoint, OutPoint::new([2; 32], 0));
}

#[tokio::test]
async fn ledger_public_records_before_the_birthday_still_block_private_activation() {
    use crate::wallet::sync::TransparentStopReason;
    use transparent::bundle::TxOut;
    use zcash_client_backend::wallet::WalletTransparentOutput;

    let mut wallet = ledger_wallet();
    let address = ledger_address(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let legacy = WalletTransparentOutput::from_parts(
        OutPoint::new([1; 32], 0),
        TxOut::new(Zatoshis::const_from_u64(VALUE), address.script().into()),
        Some(BlockHeight::from_u32(wallet.birthday - 1)),
        Some(wallet.account),
        Some(TransparentKeyScope::EXTERNAL),
        None,
    )
    .unwrap();
    wallet.db.put_received_transparent_utxo(&legacy).unwrap();
    let _mode = activate(&mut wallet).await;
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, address, VALUE, wallet.birthday - 1))
        .trust();
    run_required(&mut wallet, &source).await;
    assert!(source.calls_for(wallet.account) > 0);
    assert_eq!(
        lifecycle(&wallet, wallet.account),
        AccountLifecycle::Candidate
    );
    let stopped = balance(&wallet, &wallet.uuid);
    assert_eq!(stopped.transparent, 0);
    assert_eq!(
        stopped.transparent_stop,
        Some(TransparentStopReason::LegacyDiscrepancy)
    );
}

/// Runs the foreground recovery followup of [`SETTLE_RUNS`] syncs, one after
/// each of the blocks that follow `completed`'s chain tip, under
/// `PrivateRequired` from `source`.
async fn followups(
    wallet: &mut Wallet,
    source: &impl RecoverySource,
    progress: &(impl Fn(SyncProgressEvent) + Send + Sync),
    completed: (u64, u64),
) {
    for block in 1..=SETTLE_RUNS as u64 {
        followup(wallet, source, progress, (completed.0, completed.1 + block)).await;
    }
}

/// Runs the foreground recovery followup of one sync that completed at
/// `completed`, under `PrivateRequired` from `source`.
async fn followup(
    wallet: &mut Wallet,
    source: &impl RecoverySource,
    progress: &(impl Fn(SyncProgressEvent) + Send + Sync),
    completed: (u64, u64),
) {
    crate::wallet::sync_engine::transparent_followup(
        1,
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        source,
        Some(wallet.account),
        &|| false,
        progress,
        completed,
    )
    .await;
}

/// Recovery runs on block cadence: once after the first sync that follows a
/// new block. A service that forges a receive at the last watched address,
/// which grows the wallet's window, sees the wallet ask exactly when an
/// honest one does: one pass per block, and none for a second sync at the
/// same block (a resume, or a retry of other private work).
///
/// A restoring account watches a fixed window of addresses whatever the
/// replies show, so a receive inside it grows nothing. The forged receive
/// sits at the window's last address, the only place a reply can grow it.
#[tokio::test]
async fn a_forged_receive_does_not_change_when_recovery_runs() {
    async fn calls_per_sync(forge: bool) -> (Vec<usize>, usize) {
        let mut wallet = private_wallet();
        let window = watched(&wallet).len();
        let source = FixtureSource::new(main_hash);
        if forge {
            let last = last_watched_external(&wallet);
            source.receive(receive(1, external(&wallet, last), 10_000, 150));
        }
        let progress = |_: SyncProgressEvent| {};
        let mut calls = vec![];
        for tip in TIP + 1..=TIP + 4 {
            for _ in 0..2 {
                let completed = (u64::from(TIP), u64::from(tip));
                followup(&mut wallet, &Observed(&source), &progress, completed).await;
                calls.push(source.calls());
            }
        }
        (calls, watched(&wallet).len() - window)
    }
    let (honest, honest_growth) = calls_per_sync(false).await;
    let (forged, forged_growth) = calls_per_sync(true).await;
    assert_eq!(honest, [1, 1, 2, 2, 3, 3, 4, 4]);
    assert_eq!(forged, honest, "the same requests at the same blocks");
    assert_eq!(honest_growth, 0);
    assert!(forged_growth > 0, "the forged receive grew the window");
}

/// A restore whose funds lie beyond the first window completes over the
/// blocks that follow, with no user action.
#[tokio::test]
async fn a_restore_beyond_the_first_window_completes_over_blocks() {
    let mut wallet = private_wallet();
    let last = last_derived_external(&wallet);
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, external(&wallet, last), 10_000, 150))
        .receive(receive(2, external(&wallet, last + 1), 20_000, 160));
    let progress = |_: SyncProgressEvent| {};
    followups(
        &mut wallet,
        &Observed(&source),
        &progress,
        (u64::from(TIP), u64::from(TIP)),
    )
    .await;
    assert_complete(&wallet, &source);
}

/// An app restart forgets the block the wallet last recovered at, so the
/// first sync after it recovers at the current block, from what the library
/// stored.
#[tokio::test]
async fn a_restart_recovers_once_at_the_current_block() {
    let mut wallet = private_wallet();
    let source = FixtureSource::new(main_hash);
    let progress = |_: SyncProgressEvent| {};
    let completed = (u64::from(TIP), u64::from(TIP) + 1);
    followup(&mut wallet, &Observed(&source), &progress, completed).await;
    followup(&mut wallet, &Observed(&source), &progress, completed).await;
    assert_eq!(source.calls(), 1);

    // The restart: the schedule lived in memory, and the wallet is reopened.
    clear_recovery_tip(&wallet.path);
    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    followup(&mut wallet, &Observed(&source), &progress, completed).await;
    followup(&mut wallet, &Observed(&source), &progress, completed).await;
    assert_eq!(source.calls(), 2);
}

#[tokio::test]
async fn the_followup_reports_an_update_after_recovery() {
    use crate::wallet::sync_engine::transparent_followup;

    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    let events = std::sync::Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    let completed = (u64::from(TIP), u64::from(TIP) + 1);

    transparent_followup(
        1,
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        Some(wallet.account),
        &|| false,
        &progress,
        completed,
    )
    .await;
    {
        let events = events.lock().unwrap();
        assert_eq!(events.len(), 1);
        let event = &events[0];
        assert_eq!(event.kind, SyncEventKind::FollowupUpdated);
        assert!(!event.is_syncing);
        assert_eq!((event.scanned_height, event.chain_tip_height), completed);
    }
    // Each later sync's followup reports again; the balance the UI re-reads
    // shows the restored authority.
    followups(&mut wallet, &source, &progress, completed).await;
    assert_eq!(events.lock().unwrap().len(), 1 + SETTLE_RUNS);
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );

    // Nothing is re-reported when recovery is not enabled, or exited, even
    // at a new block.
    let completed = (completed.0, completed.1 + 100);
    let reported = events.lock().unwrap().len();
    let calls = source.calls();
    for (policy, exit) in [
        (policy(TransparentLedgerMode::Public), false),
        (required(), true),
    ] {
        transparent_followup(
            1,
            &mut wallet.db,
            &wallet.path,
            NETWORK,
            policy,
            &source,
            Some(wallet.account),
            &|| exit,
            &progress,
            completed,
        )
        .await;
    }
    assert_eq!(events.lock().unwrap().len(), reported);
    assert_eq!(source.calls(), calls);
}

#[tokio::test]
async fn the_followup_retires_a_cached_receive_address_recovery_funded() {
    use crate::wallet::sync_engine::transparent_followup;
    use crate::wallet::transparent_receive_cache;

    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let funded = external(&wallet, 0).encode(&NETWORK);
    let cached = |wallet: &Wallet| {
        transparent_receive_cache::get_clean_address(&wallet.path, NETWORK, &wallet.uuid).unwrap()
    };
    let progress = |_: SyncProgressEvent| {};
    let completed = (u64::from(TIP), u64::from(TIP) + 1);
    // The sync refreshes the cache when it completes, before recovery runs.
    transparent_receive_cache::refresh_all_from_wallet_db(&wallet.path, NETWORK, Some(completed.0))
        .unwrap();
    assert_eq!(cached(&wallet).as_deref(), Some(funded.as_str()));
    let empty = FixtureSource::new(main_hash);
    empty.trust();

    // With private queries off nothing runs, and the cache stays clean.
    transparent_followup(
        1,
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        policy(TransparentLedgerMode::Public),
        &empty,
        Some(wallet.account),
        &|| false,
        &progress,
        completed,
    )
    .await;
    assert_eq!(cached(&wallet).as_deref(), Some(funded.as_str()));

    // A run that exits may have committed for an earlier account, so it
    // leaves the cache dirty and reads fall back to the wallet DB.
    transparent_followup(
        1,
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &empty,
        Some(wallet.account),
        &|| true,
        &progress,
        completed,
    )
    .await;
    assert_eq!(cached(&wallet), None);

    // Recovery that finds nothing leaves the address on offer.
    transparent_followup(
        1,
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &empty,
        Some(wallet.account),
        &|| false,
        &progress,
        completed,
    )
    .await;
    assert_eq!(cached(&wallet).as_deref(), Some(funded.as_str()));

    // Recovery that finds funds there retires it.
    let funded_source = funded_source(&wallet);
    followups(&mut wallet, &funded_source, &progress, completed).await;
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );
    let next = cached(&wallet).expect("the cache offers the next unused address");
    assert_ne!(next, funded);
    assert_eq!(next, external(&wallet, 1).encode(&NETWORK));
}

#[tokio::test]
async fn a_background_sync_skips_the_recovery_followup() {
    use crate::wallet::sync_engine::{runs_transparent_followup, transparent_followup};

    assert!(runs_transparent_followup(1));
    assert!(!runs_transparent_followup(2));

    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    let events = std::sync::Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    let completed = (u64::from(TIP), u64::from(TIP) + 1);
    let before = balance(&wallet, &wallet.uuid).transparent_authority;

    // Background preparation (mode 2): no source call, no re-report, and the
    // ledger is left for the next foreground sync.
    transparent_followup(
        2,
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        Some(wallet.account),
        &|| false,
        &progress,
        completed,
    )
    .await;
    assert_eq!(source.calls(), 0);
    assert!(events.lock().unwrap().is_empty());
    assert_eq!(balance(&wallet, &wallet.uuid).transparent_authority, before);

    // The same wallet recovers in the foreground.
    followups(&mut wallet, &source, &progress, completed).await;
    assert!(source.calls() > 0);
    assert_eq!(events.lock().unwrap().len(), SETTLE_RUNS);
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );
}

mod activation;
mod live;
pub(crate) mod pir;
mod policy;
mod qualification;
mod real_sync;
mod shard_service;
mod status;
