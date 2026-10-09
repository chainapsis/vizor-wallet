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

use super::fixture::{FixtureSource, FIXTURE_SOURCE};
use super::*;
use crate::wallet::sync::{get_wallet_balance, TransparentBalanceAuthority};
use crate::wallet::sync_engine::enhancement::test_mode;
use crate::wallet::sync_engine::lwd::transparent_lookup::apply_transparent_policy_fenced;
use crate::wallet::sync_engine::SyncProgressEvent;
use crate::wallet::{
    db::{open_wallet_db_with_timeout, SYNC_DB_BUSY_TIMEOUT},
    keys,
    network::WalletNetwork,
};

const NETWORK: WalletNetwork = WalletNetwork::Regtest;
/// The highest scanned block in every fixture wallet.
const TIP: u32 = 200;
const VALUE: u64 = 2_000_000;

/// The clock every run in these tests measures with: tokio's, so a test that
/// pauses time advances it.
fn now() -> Instant {
    tokio::time::Instant::now().into_std()
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

fn shadow() -> EnhancementPolicy {
    policy(TransparentLedgerMode::PrivateShadow)
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

/// A wallet whose durable policy permits private recovery.
fn shadow_wallet() -> Wallet {
    let wallet = wallet();
    apply_policy(&wallet.path, TransparentLedgerMode::PrivateShadow);
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

async fn recover(wallet: &mut Wallet, source: &FixtureSource) -> RunOutcome {
    run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        shadow(),
        source,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap()
}

fn required() -> EnhancementPolicy {
    policy(TransparentLedgerMode::PrivateRequired)
}

/// Moves a wallet to `PrivateRequired` the only way this build applies a
/// transparent policy, and configures every handle opened on it for that
/// mode until the guard drops.
async fn activate(wallet: &mut Wallet) -> test_mode::ModeOverride {
    let mut db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    // The policy fence is process-wide, so parallel tests' transitions and
    // lookups queue on it: wait as long as production does.
    apply_transparent_policy_fenced(
        &mut db,
        TransparentLedgerMode::PrivateRequired,
        super::policy::POLICY_DRAIN,
    )
    .await
    .unwrap();
    let guard = test_mode::set(&wallet.path, TransparentLedgerMode::PrivateRequired);
    wallet.db = open_wallet_db_with_timeout(&wallet.path, NETWORK, SYNC_DB_BUSY_TIMEOUT).unwrap();
    guard
}

async fn run_required(wallet: &mut Wallet, source: &FixtureSource) -> RunOutcome {
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

    apply_policy(&wallet.path, TransparentLedgerMode::PrivateShadow);
    let unavailable = unavailable();
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        shadow(),
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
    let mut wallet = shadow_wallet();
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
    let mut wallet = shadow_wallet();
    let source = FixtureSource::new(main_hash);
    assert!(matches!(
        recover(&mut wallet, &source).await,
        RunOutcome::Finished(_)
    ));
    assert_complete(&wallet, &source);
}

#[tokio::test]
async fn partial_pages_resume_in_the_same_run_and_across_runs() {
    let mut wallet = shadow_wallet();
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
    let mut wallet = shadow_wallet();
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
    let mut wallet = shadow_wallet();
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
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        shadow(),
        &source,
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
    let mut wallet = shadow_wallet();
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
    let mut wallet = shadow_wallet();
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
    let mut wallet = shadow_wallet();
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
    let mut wallet = shadow_wallet();
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
    let mut wallet = shadow_wallet();
    let source = FixtureSource::new(main_hash);
    let path = wallet.path.clone();
    source.on_call(move || apply_policy(&path, TransparentLedgerMode::Public));
    assert_eq!(recover(&mut wallet, &source).await, RunOutcome::NotEnabled);
    assert_eq!(count(&wallet.path, "SELECT COUNT(*) FROM tpir_coverage"), 0);
}

#[tokio::test]
async fn contradicting_the_stored_evidence_quarantines_and_skips_the_account() {
    let mut wallet = shadow_wallet();
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

/// The lagging source asks to be retried after a wait each pass; paused time
/// lets the run spend its waits at once.
#[tokio::test(start_paused = true)]
async fn a_lagging_source_anchors_below_the_target() {
    let mut wallet = shadow_wallet();
    let address = derived(&wallet, TransparentKeyScope::EXTERNAL, 0);
    let source = FixtureSource::new(main_hash);
    source
        .receive(receive(1, address, 10_000, 120))
        .receive(receive(2, address, 20_000, TIP - 2))
        .published_through(Some(TIP - 10));
    recover(&mut wallet, &source).await;
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
    recover(&mut wallet, &source).await;
    assert_complete(&wallet, &source);
}

#[tokio::test]
async fn unsupported_ranges_block_completeness() {
    let mut wallet = shadow_wallet();
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
async fn shadow_recovery_leaves_production_state_untouched() {
    let mut wallet = shadow_wallet();
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
    ) -> impl Future<Output = Result<SourceBatch, SourceError>> + Send {
        std::future::pending()
    }

    fn apply(
        &self,
        _account: AccountUuid,
        _db: &mut WalletDatabase,
        _trust: Trust,
    ) -> impl Future<Output = Settlement> + Send {
        std::future::ready(Settlement::Refused {
            stats: ApplyStats::default(),
            refusal: Refusal::Skip,
        })
    }
}

#[tokio::test(start_paused = true)]
async fn a_source_past_its_time_bound_commits_nothing() {
    let mut wallet = shadow_wallet();
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        shadow(),
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

    // A preference that could not be read selects private handles for the
    // launch, but writes nothing, and never takes the fence: it does not
    // wait for the lookup.
    let unconfirmed =
        test_mode::select(&wallet.path, TransparentLedgerMode::PrivateRequired, false);
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
        let lowered = set_transparent_policy(&path, NETWORK, false, true)
            .await
            .unwrap();
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
                .block_on(raise_to_required(&mut db, may_raise))
                .unwrap()
        }
    });
    raise_decided.await.unwrap();

    let toggle_off = tokio::spawn({
        let path = path.clone();
        async move { set_transparent_policy(&path, NETWORK, false, true).await }
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
async fn a_flag_off_build_pauses_a_private_wallet_without_weakening_it() {
    let network = WalletNetwork::Main;
    let (_dir, path, mut db) = main_wallet();
    with_wallet_db_write_lock("test.transparent_ledger.policy", || {
        db.apply_transparent_policy(TransparentLedgerMode::PrivateRequired)
    })
    .unwrap();
    let before = applied(&path, network);
    // Private queries on in a build without the development flag.
    let flag_off = EnhancementPolicy::for_inputs(network, true, false);
    assert_eq!(flag_off.transparent_mode(), TransparentLedgerMode::Public);
    let source = FixtureSource::new(main_hash);

    let outcome = run(
        &mut db,
        &path,
        network,
        flag_off,
        &source,
        None,
        now,
        &|| false,
    )
    .await
    .unwrap();
    assert_eq!(outcome, RunOutcome::NotEnabled);
    assert_eq!(source.calls(), 0);
    // Startup in this build reconciles only upward, and selects nothing.
    assert_eq!(
        set_transparent_policy(&path, network, true, false)
            .await
            .unwrap(),
        None
    );
    assert_eq!(applied(&path, network), before);

    // Handles keep the wallet's policy, so public lookups stay withheld.
    let mut reopened = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
    flag_off.configure_db(&mut reopened);
    assert_eq!(
        reopened.transparent_ledger_mode().unwrap(),
        TransparentLedgerMode::PrivateRequired
    );
    assert_eq!(
        flag_off.public_transparent_lookups(&reopened).unwrap(),
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

    // Under `PrivateShadow` nothing is qualified, even from a trusted source.
    let mut shadowed = shadow_wallet();
    let source = funded_source(&shadowed);
    let RunOutcome::Finished(stats) = recover(&mut shadowed, &source).await else {
        panic!("recovery finishes");
    };
    assert!(stats.commits > 0);
    assert_eq!(stats.qualified, 0);
    assert_eq!(qualified(&shadowed.path), 0);

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
    source.pending(Some(Continuation::Complete));

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
    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.accounts, stats.held), (1, 1));
    assert_eq!(source.calls_for(wallet.account), 1);
    assert_eq!(source.calls_for(other), 2);

    // Once the hold ends, the account is retried.
    fn after_the_hold() -> Instant {
        now() + HOLD + Duration::from_secs(1)
    }
    source.withdraw(wallet.account, None);
    let asked = source.calls_for(wallet.account);
    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        required(),
        &source,
        None,
        after_the_hold,
        &|| false,
    )
    .await
    .unwrap();
    let RunOutcome::Finished(stats) = outcome else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.held, stats.promoted), (0, 1));
    assert!(source.calls_for(wallet.account) > asked);
}

#[tokio::test]
async fn a_batch_is_acknowledged_only_after_every_commit_applies() {
    let mut wallet = shadow_wallet();
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

    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
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
    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
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
    // The trusted origin under `PrivateShadow`, which qualifies nothing.
    let mut shadowed = shadow_wallet();
    let source = funded_source(&shadowed);
    recover(&mut shadowed, &source).await;
    let acknowledged = source.acknowledged();
    assert_eq!(acknowledged, source.calls());
    source.replace_events(vec![], vec![]).retire();
    let before = production_dump(&shadowed.path);
    let RunOutcome::Finished(stats) = recover(&mut shadowed, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.commits, stats.qualified), (0, 0));
    assert_eq!(production_dump(&shadowed.path), before);
    assert_eq!(source.acknowledged(), acknowledged);
    // Only reconciliation withdraws the retired revision's evidence.
    assert!(count(&shadowed.path, RETIRED_COVERAGE) > 0);
    assert_eq!(
        recovery_hold(&shadowed.path, shadowed.account),
        Some(HoldCause::Unreconciled)
    );
    // The held account is skipped without asking the source.
    let calls = source.calls();
    let RunOutcome::Finished(stats) = recover(&mut shadowed, &source).await else {
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

#[tokio::test]
async fn a_lagging_source_that_catches_up_within_the_cap_restores_authority() {
    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    // Paused time lets the run spend its wait at once. Activation's drain
    // must not see it.
    tokio::time::pause();
    let source = Arc::new(funded_source(&wallet));
    source.published_through(Some(TIP - 10));
    let catching_up = source.clone();
    source.on_call(|| {}).on_call(move || {
        catching_up.published_through(None);
    });

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(source.calls(), 2);
    assert_eq!(stats.publication_wait, Duration::from_secs(10));
    assert_eq!((stats.qualified, stats.promoted), (2, 1));
    let current = balance(&wallet, &wallet.uuid);
    assert_eq!(
        current.transparent_authority,
        TransparentBalanceAuthority::Current
    );
    assert_eq!(current.transparent, VALUE);
}

#[tokio::test(start_paused = true)]
async fn publication_waits_stop_at_the_cap() {
    let mut wallet = shadow_wallet();
    let (_, other) = add_account(&wallet);
    let source = FixtureSource::new(main_hash);
    source.next(Some(Continuation::RetryAfter(Duration::from_secs(30))));

    let outcome = run(
        &mut wallet.db,
        &wallet.path,
        NETWORK,
        shadow(),
        &source,
        Some(wallet.account),
        now,
        &|| false,
    )
    .await
    .unwrap();
    let RunOutcome::Finished(stats) = outcome else {
        panic!("recovery finishes");
    };
    // Three waits reach the cap; the first account's fourth pass and the
    // other account's only pass have none left.
    assert_eq!(stats.publication_wait, PUBLICATION_WAIT_CAP);
    assert_eq!(source.calls_for(wallet.account), 4);
    assert_eq!(source.calls_for(other), 1);
    assert_eq!(stats.accounts, 2);

    // The cap is per run.
    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.publication_wait, PUBLICATION_WAIT_CAP);
}

#[tokio::test]
async fn the_active_account_runs_first_and_others_rotate() {
    let mut wallet = shadow_wallet();
    let (_, b) = add_account(&wallet);
    let (_, c) = add_account(&wallet);
    let source = FixtureSource::new(main_hash);
    for _ in 0..3 {
        let outcome = run(
            &mut wallet.db,
            &wallet.path,
            NETWORK,
            shadow(),
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
    set_hold(&wallet.path, held, HoldCause::Stalled, now());
    let source = FixtureSource::new(main_hash);
    source.trust();

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!((stats.quarantined, stats.held, stats.accounts), (1, 1, 1));
    assert_eq!(source.order(), [open]);
}

#[tokio::test]
async fn three_stalled_runs_hold_the_account() {
    let mut wallet = shadow_wallet();
    let source = FixtureSource::new(main_hash);
    source.next(Some(Continuation::Stalled));
    for _ in 0..STALL_RUNS_BEFORE_HOLD {
        assert_eq!(recovery_hold(&wallet.path, wallet.account), None);
        recover(&mut wallet, &source).await;
    }
    assert_eq!(
        recovery_hold(&wallet.path, wallet.account),
        Some(HoldCause::Stalled)
    );
    assert_eq!(source.calls(), STALL_RUNS_BEFORE_HOLD);
    let RunOutcome::Finished(stats) = recover(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(stats.held, 1);
    assert_eq!(source.calls(), STALL_RUNS_BEFORE_HOLD);

    // A completed run restarts the count.
    let mut other = shadow_wallet();
    let source = FixtureSource::new(main_hash);
    for next in [
        Continuation::Stalled,
        Continuation::Stalled,
        Continuation::Complete,
        Continuation::Stalled,
        Continuation::Stalled,
    ] {
        source.next(Some(next));
        recover(&mut other, &source).await;
    }
    assert_eq!(recovery_hold(&other.path, other.account), None);

    // A run that ends waiting for a lagging publication does not: the stall
    // it interrupts is still held.
    let mut lagging = shadow_wallet();
    let source = FixtureSource::new(main_hash);
    let past_the_wait_cap = Continuation::RetryAfter(PUBLICATION_WAIT_CAP * 2);
    for next in [
        Continuation::Stalled,
        past_the_wait_cap,
        Continuation::Stalled,
        past_the_wait_cap,
        Continuation::Stalled,
    ] {
        source.next(Some(next));
        recover(&mut lagging, &source).await;
    }
    assert_eq!(
        recovery_hold(&lagging.path, lagging.account),
        Some(HoldCause::Stalled)
    );
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

#[tokio::test]
async fn cancellation_during_a_pass_applies_nothing_from_it() {
    let mut wallet = shadow_wallet();
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
        shadow(),
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

#[tokio::test]
async fn a_ledger_account_is_paused_and_does_not_block_sync() {
    use crate::wallet::sync_engine::ledger_discovery;

    let mut wallet = wallet();
    let ledger = import_ledger(&wallet);
    // Under public lookups, the Ledger account owes its discovery.
    assert!(!ledger_discovery::is_ready(&wallet.path, NETWORK, ledger).unwrap());
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);

    let RunOutcome::Finished(stats) = run_required(&mut wallet, &source).await else {
        panic!("recovery finishes");
    };
    assert_eq!(
        (stats.paused_ledger, stats.accounts, stats.promoted),
        (1, 1, 1)
    );
    assert_eq!(source.calls_for(ledger), 0);
    assert_eq!(lifecycle(&wallet, ledger), AccountLifecycle::Candidate);
    // The sync's readiness check passes, so the withheld discovery never
    // fails a sync.
    assert!(ledger_discovery::is_ready(&wallet.path, NETWORK, ledger).unwrap());
}

#[tokio::test]
async fn the_followup_reemits_completion_after_recovery() {
    use crate::wallet::sync_engine::transparent_followup;

    let mut wallet = wallet();
    let _mode = activate(&mut wallet).await;
    let source = funded_source(&wallet);
    let events = std::sync::Mutex::new(Vec::<SyncProgressEvent>::new());
    let progress = |event: SyncProgressEvent| events.lock().unwrap().push(event);
    let completed = (u64::from(TIP), u64::from(TIP) + 1);

    transparent_followup(
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
        assert!(event.is_complete && event.has_new_tx && !event.is_syncing);
        assert_eq!((event.scanned_height, event.chain_tip_height), completed);
    }
    // The balance the UI re-reads shows the restored authority.
    assert_eq!(
        balance(&wallet, &wallet.uuid).transparent_authority,
        TransparentBalanceAuthority::Current
    );

    // Nothing is re-reported when recovery is not enabled, or exited.
    let calls = source.calls();
    for (policy, exit) in [
        (policy(TransparentLedgerMode::Public), false),
        (required(), true),
    ] {
        transparent_followup(
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
    assert_eq!(events.lock().unwrap().len(), 1);
    assert_eq!(source.calls(), calls);
}

mod activation;
mod live;
pub(crate) mod pir;
mod policy;
mod qualification;
mod status;
