//! Loop 4: transparent txid enhancement.
//!
//! A sync runs four loops. (1) Compact scanning, (2) Ironwood payload
//! enhancement ([`super::enhancement`]) and (3) transparent discovery (public
//! lightwalletd lanes, or private recovery in [`super::transparent_ledger`])
//! decide balances, spendability and history. This loop fills in what a
//! detail view shows: for each transparent or mixed transaction the wallet
//! recorded without raw bytes, it fetches that transaction's details by txid.
//!
//! The wallet owns the work, its backoff, validation and the view
//! (`TransparentDetailRead`/`TransparentDetailWrite`); this loop owns
//! scheduling, the source and its transport. The source is chosen once per
//! run from the policy the sync captured:
//!
//! - `PrivateRequired`: txid display PIR ([`source::PirSource`]), which
//!   returns the transaction's complete transparent outputs and its fee
//!   metadata without the service learning the txid. It never falls back to a
//!   public lookup: a failure leaves the details unavailable until a later
//!   run.
//! - Otherwise: lightwalletd `GetTransaction` through the
//!   [`TransparentLookupGate`] ([`source::GateSource`]), stored with
//!   `decrypt_and_store_transaction` like any enhancement payload. A policy
//!   transition while the run is in flight withholds the rest of it.
//!
//! [`run`] is bounded: [`MAX_LOOKUPS`] lookups and [`RUN_BUDGET`] per run,
//! one at a time, in the wallet's order, with transactions a detail view
//! asked for ([`prioritize`]) ahead of the rest within the 64-row work window.
//! A requested older transaction outside that window must wait to enter it.
//! Lookups run with no
//! database lock held; each result is stored, or each failure deferred, under
//! the wallet write lock in its own short transaction. Once the budget is
//! spent or the sync exits, a lookup gets [`source::CANCEL_GRACE`] to return
//! before it is abandoned, and writes may wait for the lock until
//! [`WRITE_GRACE`] past the budget: a run ends within 47 s, plus at most one
//! SQLite write already under way. Failures are logged by kind, never by txid. The display facts the
//! private source stores change no balance, spendability, send or history;
//! the public source's raw transaction is ordinary wallet data, as from
//! payload enhancement. Nothing this loop does can fail the sync:
//! [`transparent_details_followup`] catches errors and panics.
//!
//! Work a private lookup held for the display map waits for the map to
//! change, and no lookup may be due to fetch a newer one: when nothing is due
//! and work is parked, the private source fetches the map alone and the run
//! lists again (see `list_work`). The database's refresh time bounds these
//! checks to six hours after the latest parked attempt or attempted map check.
//! The process keeps check times by origin across runs, including failed checks.

use std::collections::{HashMap, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::{LazyLock, Mutex, PoisonError};
use std::time::{Duration, Instant, SystemTime};

use futures::FutureExt;
use rusqlite::OptionalExtension as _;
use tonic::transport::Channel;
use zcash_client_backend::data_api::{
    transparent_ledger::{
        TransparentDetailOutcome, TransparentDetailRead, TransparentDetailWork,
        TransparentDetailWrite, TransparentDisplayStore, TransparentDisplayView,
        TransparentLedgerMode, TransparentLedgerRead,
    },
    wallet::decrypt_and_store_transaction,
    WalletRead,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};
use zcash_primitives::transaction::TxId;
use zcash_protocol::consensus::BlockHeight;

use super::enhancement::EnhancementPolicy;
use super::{elapsed, SyncProgressEvent, TransparentLookupGate, WalletDatabase};
use crate::wallet::db::with_wallet_db_write_lock_unless;
use crate::wallet::network::WalletNetwork;

pub(crate) mod source;
#[cfg(test)]
pub(crate) mod tests;

use source::{DetailAnswer, DetailFailure, DetailSource, GateSource, PirSource};

/// Time one run's lookups may take; see the module documentation for the
/// grace a run takes past it.
pub(crate) const RUN_BUDGET: Duration = Duration::from_secs(45);
/// How long past the budget a run may wait to record the lookup the budget
/// stopped.
const WRITE_GRACE: Duration = Duration::from_secs(2);
/// Lookups one run may make.
pub(crate) const MAX_LOOKUPS: usize = 8;
/// Due work one run reads, so that prioritized transactions can go first.
const WORK_WINDOW: usize = 64;
/// Transactions a wallet's detail views may ask for at once.
const MAX_INTEREST: usize = 32;

/// Transactions detail views asked for, by wallet path, most recent first.
/// In memory only: a restart forgets them, and the views ask again.
static INTEREST: LazyLock<Mutex<HashMap<String, VecDeque<[u8; 32]>>>> =
    LazyLock::new(Default::default);

/// Prioritizes `txid` (protocol byte order) for the wallet at `db_path` when
/// it is due and included in the next run's 64-row work window. The hint does
/// not pull older work outside that window into the run.
pub(crate) fn prioritize(db_path: &str, txid: [u8; 32]) {
    let mut interest = INTEREST.lock().unwrap_or_else(PoisonError::into_inner);
    let queue = interest.entry(db_path.to_owned()).or_default();
    queue.retain(|queued| *queued != txid);
    queue.push_front(txid);
    queue.truncate(MAX_INTEREST);
}

fn interest(db_path: &str) -> Vec<[u8; 32]> {
    INTEREST
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .get(db_path)
        .map(|queue| queue.iter().copied().collect())
        .unwrap_or_default()
}

fn served(db_path: &str, txid: &[u8; 32]) {
    if let Some(queue) = INTEREST
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .get_mut(db_path)
    {
        queue.retain(|queued| queued != txid);
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct RunStats {
    /// Lookups the run made.
    pub(crate) lookups: usize,
    /// Transactions whose details it stored.
    pub(crate) stored: usize,
    /// Transactions it deferred after a failure.
    pub(crate) deferred: usize,
    /// Transactions the private publication does not cover or offer.
    pub(crate) not_covered: usize,
    /// Facts the wallet refused as contradicting what it knows.
    pub(crate) contradicted: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum RunOutcome {
    /// The work ran out, or the budget or lookup cap ended the run.
    Finished(RunStats),
    /// The service was unavailable; the rest waits for a later run.
    Unavailable(RunStats),
    /// The policy generation moved: the run stored nothing after it.
    Superseded(RunStats),
    /// A policy transition withdrew the public source's authority.
    Withheld(RunStats),
    /// Cancellation stopped the run. What it stored stays.
    Exited(RunStats),
    /// The run could not read its work. Nothing was looked up.
    Failed,
}

impl RunOutcome {
    pub(crate) fn stats(self) -> RunStats {
        match self {
            RunOutcome::Finished(stats)
            | RunOutcome::Unavailable(stats)
            | RunOutcome::Superseded(stats)
            | RunOutcome::Withheld(stats)
            | RunOutcome::Exited(stats) => stats,
            RunOutcome::Failed => RunStats::default(),
        }
    }
}

/// Clocks a run measures its budget and dates its work on.
#[derive(Clone, Copy)]
pub(crate) struct StageClock {
    pub(crate) instant: fn() -> Instant,
    pub(crate) system: fn() -> SystemTime,
}

impl StageClock {
    pub(crate) fn system() -> Self {
        Self {
            instant: Instant::now,
            system: SystemTime::now,
        }
    }
}

/// One bounded run of loop 4 over the wallet behind `db`, through `source`.
///
/// `expected_generation` is the durable policy generation captured with the
/// source; the wallet stores private facts only while it holds. Never returns
/// an error: failures defer their transaction and are logged by kind.
pub(crate) async fn run<S: DetailSource>(
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    source: &mut S,
    expected_generation: u64,
    clock: StageClock,
    should_exit: &(dyn Fn() -> bool + Sync),
) -> RunOutcome {
    let mut stats = RunStats::default();
    if should_exit() {
        return RunOutcome::Exited(stats);
    }
    let deadline = (clock.instant)() + RUN_BUDGET;
    let budget_exit = move || should_exit() || (clock.instant)() >= deadline;
    // Writes may finish the budget's last lookup, but never wait on the
    // wallet's write lock past a short grace, nor once the sync exits.
    let write_exit = move || should_exit() || (clock.instant)() >= deadline + WRITE_GRACE;
    let Some(work) = list_work(db, source, clock, &budget_exit).await else {
        return RunOutcome::Failed;
    };
    if should_exit() {
        return RunOutcome::Exited(stats);
    }
    // The listing's snapshot decides: a policy moved since the run captured
    // its source ends the run, and public transport needs the listed mode to
    // retain public authority.
    if work.policy_generation != expected_generation {
        log::info!("transparent details: policy changed before the run; ending it");
        return RunOutcome::Superseded(stats);
    }
    if source.gate().is_some() && !work.public_transport() {
        log::info!("transparent details: transparent policy withholds public lookups");
        return RunOutcome::Withheld(stats);
    }
    let expected_generation = work.policy_generation;
    let mut work = work.requests;
    let prioritized = interest(db_path);
    work.sort_by_key(|request| {
        prioritized
            .iter()
            .position(|txid| txid == request.txid.as_ref())
            .unwrap_or(usize::MAX)
    });
    work.truncate(MAX_LOOKUPS);

    for request in work {
        if should_exit() {
            return RunOutcome::Exited(stats);
        }
        if (clock.instant)() >= deadline {
            log::info!("transparent details: run budget spent; the rest waits for a later run");
            break;
        }
        let txid = request.txid;
        let looked_up_height = request.mined_height;
        let answer = source
            .lookup(txid, request.mined_height, &budget_exit)
            .await;
        stats.lookups += 1;
        served(db_path, txid.as_ref());
        let now = (clock.system)();
        let answer = match answer {
            Ok(answer) => answer,
            Err(DetailFailure::Cancelled) => {
                if should_exit() {
                    return RunOutcome::Exited(stats);
                }
                // The budget, not the sync, stopped a slow lookup.
                log::info!("transparent details: run budget spent during a lookup");
                defer(
                    db,
                    txid,
                    looked_up_height,
                    now,
                    TransparentDetailOutcome::Unavailable { retry_after: None },
                    None,
                    &mut stats,
                    &write_exit,
                )
                .await;
                break;
            }
            Err(DetailFailure::Withheld) => {
                log::info!("transparent details: transparent policy withholds public lookups");
                return RunOutcome::Withheld(stats);
            }
            Err(DetailFailure::Deferred {
                outcome,
                map_sha256,
            }) => {
                log::info!(
                    "transparent details: lookup deferred ({})",
                    outcome_name(outcome)
                );
                if !defer(
                    db,
                    txid,
                    looked_up_height,
                    now,
                    outcome,
                    map_sha256,
                    &mut stats,
                    &write_exit,
                )
                .await
                {
                    return gave_up(should_exit, stats);
                }
                if matches!(outcome, TransparentDetailOutcome::Unavailable { .. }) {
                    return RunOutcome::Unavailable(stats);
                }
                continue;
            }
        };
        match answer {
            DetailAnswer::Facts(facts) => {
                if facts.txid != txid {
                    log::error!("transparent details: source answered another transaction");
                    if !defer(
                        db,
                        txid,
                        looked_up_height,
                        now,
                        TransparentDetailOutcome::Protocol,
                        None,
                        &mut stats,
                        &write_exit,
                    )
                    .await
                    {
                        return gave_up(should_exit, stats);
                    }
                    continue;
                }
                let map_sha256 = Some(facts.provenance.map_sha256);
                let stored = with_wallet_db_write_lock_unless(
                    "sync_engine.transparent_details.store",
                    &write_exit,
                    || db.store_transparent_display(*facts, expected_generation, now),
                )
                .await;
                let Some(stored) = stored else {
                    return gave_up(should_exit, stats);
                };
                match stored {
                    Ok(TransparentDisplayStore::Stored) => stats.stored += 1,
                    // Raw bytes arrived meanwhile, or the transaction left.
                    Ok(TransparentDisplayStore::Superseded) => {}
                    Ok(TransparentDisplayStore::Contradiction(kind)) => {
                        log::warn!(
                            "transparent details: facts contradict the wallet ({kind:?}); held"
                        );
                        stats.contradicted += 1;
                    }
                    Err(SqliteClientError::StaleTransparentPolicy { .. }) => {
                        log::info!("transparent details: policy changed; ending the run");
                        return RunOutcome::Superseded(stats);
                    }
                    Err(_) => {
                        log::warn!("transparent details: store failed; retrying later");
                        if !defer(
                            db,
                            txid,
                            looked_up_height,
                            now,
                            TransparentDetailOutcome::Unavailable { retry_after: None },
                            map_sha256,
                            &mut stats,
                            &write_exit,
                        )
                        .await
                        {
                            return gave_up(should_exit, stats);
                        }
                    }
                }
            }
            DetailAnswer::Raw {
                transaction,
                mined_height,
            } => {
                let Some(gate) = source.gate() else {
                    if !defer(
                        db,
                        txid,
                        looked_up_height,
                        now,
                        TransparentDetailOutcome::Protocol,
                        None,
                        &mut stats,
                        &write_exit,
                    )
                    .await
                    {
                        return gave_up(should_exit, stats);
                    }
                    continue;
                };
                // A completing write: the policy is read in the same
                // transaction, so a transition while the lookup was in flight
                // leaves the transaction to a later authorized run.
                let stored = with_wallet_db_write_lock_unless(
                    "sync_engine.transparent_details.decrypt_and_store_transaction",
                    &write_exit,
                    || {
                        db.transactionally(|tx| {
                            if !gate.permits_applied(tx.applied_transparent_policy()?) {
                                return Ok(false);
                            }
                            decrypt_and_store_transaction(
                                &network,
                                tx,
                                &transaction,
                                mined_height,
                            )?;
                            Ok::<_, SqliteClientError>(true)
                        })
                    },
                )
                .await;
                let Some(stored) = stored else {
                    return gave_up(should_exit, stats);
                };
                match stored {
                    Ok(true) => stats.stored += 1,
                    Ok(false) => {
                        log::info!(
                            "transparent details: transparent policy changed; ending the run"
                        );
                        return RunOutcome::Withheld(stats);
                    }
                    Err(_) => {
                        log::warn!("transparent details: store failed; retrying later");
                        if !defer(
                            db,
                            txid,
                            looked_up_height,
                            now,
                            TransparentDetailOutcome::Unavailable { retry_after: None },
                            None,
                            &mut stats,
                            &write_exit,
                        )
                        .await
                        {
                            return gave_up(should_exit, stats);
                        }
                    }
                }
            }
        }
    }
    RunOutcome::Finished(stats)
}

/// The due work. When nothing is due but lookups are parked on the display
/// map they last saw, the source refreshes its map once and the work is
/// listed again under the new map hash. `None` when the work is unreadable.
async fn list_work<S: DetailSource>(
    db: &WalletDatabase,
    source: &mut S,
    clock: StageClock,
    should_exit: &(dyn Fn() -> bool + Sync),
) -> Option<TransparentDetailWork> {
    let list = |map: Option<[u8; 32]>| {
        db.transparent_detail_work((clock.system)(), WORK_WINDOW, map)
            .map_err(|_| log::warn!("transparent details: work unreadable; retrying later"))
            .ok()
    };
    let map = source.map_sha256();
    let work = list(map)?;
    if !work.requests.is_empty() {
        return Some(work);
    }
    let now = (clock.system)();
    let parked = db
        .transparent_detail_parked(now, map, source.map_checked_at())
        .ok();
    if !parked
        .is_some_and(|parked| parked.count > 0 && parked.refresh_at.is_some_and(|at| at <= now))
        || should_exit()
    {
        return Some(work);
    }
    source.map_check_started(now);
    match source.refresh_map(should_exit).await {
        Some(refreshed) if Some(refreshed) != map => {
            log::info!("transparent details: display map changed; re-listing parked work");
            list(Some(refreshed))
        }
        _ => Some(work),
    }
}

/// How the run ends when it gave up waiting for the wallet's write lock:
/// what it stored stays, and the transaction it could not record stays due.
fn gave_up(should_exit: &(dyn Fn() -> bool + Sync), stats: RunStats) -> RunOutcome {
    if should_exit() {
        return RunOutcome::Exited(stats);
    }
    log::info!("transparent details: run budget spent waiting to write; the rest waits");
    RunOutcome::Finished(stats)
}

/// Records a failed lookup of `txid` in the wallet, which schedules the next
/// attempt, and counts it. `false` when it gave up waiting for the wallet's
/// write lock at `write_exit`, recording nothing.
async fn defer(
    db: &mut WalletDatabase,
    txid: TxId,
    looked_up_height: BlockHeight,
    now: SystemTime,
    outcome: TransparentDetailOutcome,
    map_sha256: Option<[u8; 32]>,
    stats: &mut RunStats,
    write_exit: &(dyn Fn() -> bool + Sync),
) -> bool {
    let deferred = with_wallet_db_write_lock_unless(
        "sync_engine.transparent_details.defer",
        write_exit,
        || db.defer_transparent_detail(txid, looked_up_height, outcome, map_sha256, now),
    )
    .await;
    let Some(deferred) = deferred else {
        return false;
    };
    match deferred {
        Ok(()) => match outcome {
            TransparentDetailOutcome::NotCovered | TransparentDetailOutcome::Unsupported => {
                stats.not_covered += 1
            }
            _ => stats.deferred += 1,
        },
        Err(_) => log::warn!("transparent details: could not record a deferral"),
    }
    true
}

/// An outcome's name, for logs.
fn outcome_name(outcome: TransparentDetailOutcome) -> &'static str {
    match outcome {
        TransparentDetailOutcome::Unavailable { .. } => "unavailable",
        TransparentDetailOutcome::NotYetPublished => "not yet published",
        TransparentDetailOutcome::Absent => "absent",
        TransparentDetailOutcome::NotCovered => "not covered",
        TransparentDetailOutcome::Unsupported => "unsupported",
        TransparentDetailOutcome::Protocol => "protocol",
        TransparentDetailOutcome::Contradiction => "contradiction",
    }
}

/// Runs loop 4 once a sync has completed and reported completion at
/// `completed` (scanned height, chain tip), and reports completion again,
/// flagged with new transactions, when it stored anything.
///
/// The source is chosen once from `policy`: `PrivateRequired` builds only
/// the private source (mainnet only), anything else only the gate, and only
/// while the durable policy authorizes public lookups. Errors and panics are
/// logged, never returned: this loop cannot fail a sync.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn transparent_details_followup(
    db: &mut WalletDatabase,
    db_data_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    client: &CompactTxStreamerClient<Channel>,
    should_exit: &(dyn Fn() -> bool + Sync),
    progress_fn: &(impl Fn(SyncProgressEvent) + Send + Sync),
    completed: (u64, u64),
) {
    let outcome = guarded(followup(
        db,
        db_data_path,
        network,
        policy,
        client,
        StageClock::system(),
        should_exit,
    ))
    .await;
    report(outcome, should_exit, progress_fn, completed);
}

/// Awaits `run`, turning a panic into no outcome.
pub(crate) async fn guarded(
    run: impl std::future::Future<Output = Option<RunOutcome>>,
) -> Option<RunOutcome> {
    match AssertUnwindSafe(run).catch_unwind().await {
        Ok(outcome) => outcome,
        Err(_) => {
            log::error!("[{}] sync: transparent details panicked", elapsed());
            None
        }
    }
}

/// Logs a run's outcome and, when it stored anything, reports completion at
/// `completed` again, flagged with new transactions.
pub(crate) fn report(
    outcome: Option<RunOutcome>,
    should_exit: &(dyn Fn() -> bool + Sync),
    progress_fn: &(impl Fn(SyncProgressEvent) + Send + Sync),
    completed: (u64, u64),
) {
    let Some(outcome) = outcome else {
        return;
    };
    if outcome != RunOutcome::Finished(RunStats::default()) {
        log::info!("[{}] sync: transparent details: {:?}", elapsed(), outcome);
    }
    if outcome.stats().stored > 0 && !should_exit() {
        let (scanned_height, chain_tip_height) = completed;
        progress_fn(SyncProgressEvent {
            scanned_height,
            chain_tip_height,
            percentage: 1.0,
            display_target_percentage: 1.0,
            display_target_blocks: 0,
            is_syncing: false,
            is_complete: true,
            has_new_tx: true,
            phase_completed_units: 0,
            phase_total_units: 0,
            phase: String::new(),
        });
    }
}

/// Chooses the source and runs. `None` when no source applies.
pub(crate) async fn followup(
    db: &mut WalletDatabase,
    db_data_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    client: &CompactTxStreamerClient<Channel>,
    clock: StageClock,
    should_exit: &(dyn Fn() -> bool + Sync),
) -> Option<RunOutcome> {
    if should_exit() {
        return None;
    }
    policy.configure_db(db);
    let generation = match db.applied_transparent_policy() {
        Ok(applied) => applied.generation,
        Err(_) => {
            log::warn!("transparent details: policy unreadable; retrying on a later sync");
            return None;
        }
    };
    if policy.transparent_mode() == TransparentLedgerMode::PrivateRequired {
        let mut source = PirSource::new(db_data_path, network)?;
        return Some(
            run(
                db,
                db_data_path,
                network,
                &mut source,
                generation,
                clock,
                should_exit,
            )
            .await,
        );
    }
    let lookups = match policy.public_transparent_lookups(db) {
        Ok(lookups) if lookups.is_allowed() => lookups,
        // A wallet whose durable policy withholds public lookups gets no
        // details from this build: never a public fallback, and the private
        // source is for a `PrivateRequired` capture only.
        Ok(_) => return None,
        Err(_) => {
            log::warn!("transparent details: policy unreadable; retrying on a later sync");
            return None;
        }
    };
    let gate = match TransparentLookupGate::for_sync(lookups, db_data_path, network) {
        Ok(gate) => gate,
        Err(_) => {
            log::warn!("transparent details: gate unavailable; retrying on a later sync");
            return None;
        }
    };
    let mut source = GateSource::new(client.clone(), gate);
    Some(
        run(
            db,
            db_data_path,
            network,
            &mut source,
            generation,
            clock,
            should_exit,
        )
        .await,
    )
}

/// The accounts and policy generation of the wallet a public load started
/// from. Read together, and checked again in the storage transaction.
#[derive(Clone, Debug, PartialEq, Eq)]
struct PublicLoadIdentity {
    accounts: Vec<AccountUuid>,
    generation: u64,
}

impl PublicLoadIdentity {
    fn of(
        db: &impl TransparentLedgerRead<AccountId = AccountUuid, Error = SqliteClientError>,
    ) -> Result<Self, SqliteClientError> {
        let mut accounts = db.get_account_ids()?;
        accounts.sort();
        Ok(Self {
            accounts,
            generation: db.applied_transparent_policy()?.generation,
        })
    }
}

/// Fetches `txid` (protocol byte order) from lightwalletd and stores it,
/// because the user asked to load this one transaction's full details
/// publicly. The request reveals the txid to lightwalletd, over an isolated
/// Tor circuit when Tor is on. Only that explicit request runs it, under any
/// transparent policy; loop 4 and every automatic path keep to the policy.
/// Errors carry no txid. Runs on the caller's thread, which must not be a
/// runtime worker.
///
/// Retains the original existing SQLite handle and physical file identity.
/// The network wait holds no SQL transaction or wallet write lock. A reset,
/// file replacement, account change or policy transition discards the result;
/// validation and storage share one wallet transaction, including the final
/// read that checks whether the wallet accepted the transaction.
pub(crate) fn enhance_publicly(
    db_path: &str,
    network: WalletNetwork,
    lightwalletd_url: &str,
    txid: [u8; 32],
) -> Result<(), String> {
    use crate::wallet::db::{
        open_existing_wallet_db_with_timeout, with_wallet_db_write_lock, WALLET_DB_BUSY_TIMEOUT,
    };
    let txid = TxId::from_bytes(txid);
    let file = same_file::Handle::from_path(db_path)
        .map_err(|_| "the wallet is unavailable".to_owned())?;
    let same_file = || {
        same_file::Handle::from_path(db_path)
            .map(|current| current == file)
            .unwrap_or(false)
    };
    let mut db = open_existing_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)
        .map_err(|error| format!("the wallet is unavailable ({error})"))?;
    if !same_file() {
        return Err("the wallet changed before the lookup; nothing was sent".to_owned());
    }
    let started = db
        .transactionally(|tx| PublicLoadIdentity::of(tx))
        .map_err(|error| format!("reading the wallet failed ({error})"))?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .map_err(|error| format!("tokio: {error}"))?;
    let raw = runtime.block_on(async {
        let transport = super::lwd::open_isolated_lwd_transport(lightwalletd_url)
            .await
            .map_err(|error| format!("lightwalletd unavailable ({error})"))?;
        let mut client = CompactTxStreamerClient::new(transport.clone());
        TransparentLookupGate::user_requested(db_path)
            .with_transport(transport)
            .transaction(&mut client, txid)
            .await
            .map_err(|error| format!("lightwalletd lookup failed ({error})"))
    })?;
    let raw = match raw {
        Some(Ok(raw)) => raw,
        Some(Err(status)) => {
            return Err(format!(
                "lightwalletd refused the lookup ({:?})",
                status.code()
            ))
        }
        None => return Err("the public lookup was withheld".to_owned()),
    };
    let (transaction, mined_height) = super::enhancement::decode_enhancement_payload(&raw, txid)
        .map_err(|error| format!("lightwalletd answered with an invalid transaction ({error})"))?;
    let stored =
        with_wallet_db_write_lock("sync_engine.transparent_details.enhance_publicly", || {
            if !same_file() {
                return Err("the wallet changed during the lookup; nothing was stored".to_owned());
            }
            let stored = db
                .transactionally(|tx| {
                    if PublicLoadIdentity::of(tx)? != started {
                        return Ok(None);
                    }
                    decrypt_and_store_transaction(&network, tx, &transaction, mined_height)?;
                    // Read through this transaction, not a second connection
                    // that could be opened on replacement storage.
                    Ok::<_, SqliteClientError>(Some(tx.get_transaction(txid)?.is_some()))
                })
                .map_err(|error| format!("storing the transaction failed ({error})"))?;
            if !same_file() {
                return Err("the wallet changed while storing the lookup".to_owned());
            }
            Ok(stored)
        })?;
    match stored {
        Some(true) => Ok(()),
        Some(false) => Err("the wallet found nothing of its own in the transaction".to_owned()),
        None => Err("the wallet changed during the lookup; nothing was stored".to_owned()),
    }
}

/// The detail view of `txid` (protocol byte order) for `account`, from the
/// wallet behind `db` and its connection `conn`; `None` when the transaction
/// has no transparent part the account takes part in. The caller must bind
/// both to the same read snapshot, including any receipt reads this overlays.
pub(crate) fn detail_view(
    db: &impl TransparentDetailRead<AccountId = AccountUuid, Error = SqliteClientError>,
    conn: &rusqlite::Connection,
    account: AccountUuid,
    txid: &[u8],
) -> Result<Option<TransparentDisplayView>, String> {
    let txid: [u8; 32] = txid.try_into().map_err(|_| "txid length".to_owned())?;
    let part = transparent_part(conn, account, &txid)?;
    if part == TransparentPart::None {
        return Ok(None);
    }
    let view = db
        .transparent_display_view(account, TxId::from_bytes(txid))
        .map_err(|error| format!("transparent detail view: {error}"))?;
    // Raw bytes show whether the transaction has a transparent side at all.
    if part == TransparentPart::IfRawShowsOne
        && !matches!(&view, Some(TransparentDisplayView::Available(details))
            if !details.outputs.is_empty() || details.input_count > 0)
    {
        return Ok(None);
    }
    Ok(view)
}

/// What the wallet records of an account's part in a transaction's
/// transparent side.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TransparentPart {
    /// The account has no part in the transaction, or the wallet records no
    /// transparent side of it.
    None,
    /// The account has a transparent output or spend in the transaction, or
    /// a shielded part in a transaction the wallet records as mixed.
    Recorded,
    /// The account has a shielded part in a transaction whose raw bytes the
    /// wallet holds; they show whether it has a transparent side.
    IfRawShowsOne,
}

/// The account's part in `txid`'s transparent side.
///
/// Its own transparent outputs and spends, recovered or scanned, count. So
/// does a shielded part (a received, spent or sent note, a payment to a
/// transparent recipient among them) in a transaction the wallet durably
/// records as mixed: by detail work, stored display facts or the route-2
/// marker, which outlive the work they replace. Raw bytes replace work and
/// display facts alike, so for a shielded part in a transaction with raw
/// bytes, those bytes decide.
fn transparent_part(
    conn: &rusqlite::Connection,
    account: AccountUuid,
    txid: &[u8; 32],
) -> Result<TransparentPart, String> {
    let (own, shielded, mixed, raw): (bool, bool, bool, bool) = conn
        .query_row(
            "SELECT
                 EXISTS (
                     SELECT 1 FROM transparent_received_outputs o
                     WHERE o.transaction_id = t.id_tx AND o.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM transparent_received_output_spends s
                     JOIN transparent_received_outputs o
                       ON o.id = s.transparent_received_output_id
                     WHERE s.transaction_id = t.id_tx AND o.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM tpir_receive_events r
                     WHERE r.txid = t.txid AND r.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM tpir_spend_events s
                     WHERE s.spending_txid = t.txid AND s.account_id = a.id
                 ),
                 EXISTS (
                     SELECT 1 FROM sapling_received_notes n
                     WHERE n.transaction_id = t.id_tx AND n.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM orchard_received_notes n
                     WHERE n.transaction_id = t.id_tx AND n.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM ironwood_received_notes n
                     WHERE n.transaction_id = t.id_tx AND n.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM sapling_received_note_spends s
                     JOIN sapling_received_notes n ON n.id = s.sapling_received_note_id
                     WHERE s.transaction_id = t.id_tx AND n.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM orchard_received_note_spends s
                     JOIN orchard_received_notes n ON n.id = s.orchard_received_note_id
                     WHERE s.transaction_id = t.id_tx AND n.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM ironwood_received_note_spends s
                     JOIN ironwood_received_notes n ON n.id = s.ironwood_received_note_id
                     WHERE s.transaction_id = t.id_tx AND n.account_id = a.id
                     UNION ALL
                     SELECT 1 FROM sent_notes n
                     WHERE n.transaction_id = t.id_tx AND n.from_account_id = a.id
                 ),
                 EXISTS (
                     SELECT 1 FROM transparent_detail_work w WHERE w.transaction_id = t.id_tx
                     UNION ALL
                     SELECT 1 FROM transparent_tx_display d WHERE d.transaction_id = t.id_tx
                     UNION ALL
                     SELECT 1 FROM ironwood_enhance_routing r
                     WHERE r.transaction_id = t.id_tx AND r.route = 2
                 ),
                 t.raw IS NOT NULL
             FROM transactions t, accounts a
             WHERE t.txid = ?2 AND a.uuid = ?1",
            rusqlite::params![account.expose_uuid().as_bytes().as_slice(), txid.as_slice()],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .optional()
        .map_err(|error| format!("transparent detail view: {error}"))?
        .unwrap_or_default();
    Ok(if own || (shielded && mixed) {
        TransparentPart::Recorded
    } else if shielded && raw {
        TransparentPart::IfRawShowsOne
    } else {
        TransparentPart::None
    })
}

/// What a development lookup found, without storing anything.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DebugLookup {
    /// `found`, `absent`, `placementUnknown` or `unsupported`.
    pub(crate) outcome: &'static str,
    /// Every transparent output: value and, for a standard script, address.
    pub(crate) outputs: Vec<(u64, Option<String>)>,
    pub(crate) fee: Option<u64>,
    pub(crate) transparent_input_count: u32,
    pub(crate) coinbase: bool,
}

/// One private txid display lookup of `txid` (protocol byte order) mined at
/// `mined_height`, through the process-wide client, persisting nothing.
///
/// Debug builds only: refused in release builds and off mainnet. Runs
/// on the caller's thread, which must not be a runtime worker.
pub(crate) fn debug_lookup(
    network: WalletNetwork,
    txid: [u8; 32],
    mined_height: u64,
) -> Result<DebugLookup, String> {
    if !cfg!(debug_assertions) {
        return Err("Private transparent lookups need a development build".to_owned());
    }
    let origin =
        source::txid_origin(network).ok_or("Private transparent lookups are mainnet only")?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .map_err(|error| format!("tokio: {error}"))?;
    let (found, _) = source::BlockingLookup {
        client: source::client_for(&origin),
        origin,
        txid,
        mined_height,
        handle: runtime.handle().clone(),
        cancel: Default::default(),
        #[cfg(test)]
        observer: None,
    }
    .run();
    debug_answer(
        network,
        txid,
        found.map_err(|error| format!("Private lookup failed ({error})"))?,
        mined_height,
    )
}

/// A lookup's result as a development answer.
pub(crate) fn debug_answer(
    network: WalletNetwork,
    txid: [u8; 32],
    found: zakura_pir_transparent::TxidLookup,
    mined_height: u64,
) -> Result<DebugLookup, String> {
    use zakura_pir_transparent::TxidLookup;
    use zcash_client_backend::data_api::transparent_ledger::WholeTransactionFee;
    let mut answer = DebugLookup {
        outcome: "found",
        outputs: Vec::new(),
        fee: None,
        transparent_input_count: 0,
        coinbase: false,
    };
    match found {
        TxidLookup::Found { entry, provenance } => {
            let height = u32::try_from(mined_height).map_err(|_| "height out of range")?;
            let facts = zakura_pir_transparent::display_facts(
                TxId::from_bytes(txid),
                &entry,
                &provenance,
                height.into(),
            )
            .map_err(|_| "the service returned unusable facts".to_owned())?;
            answer.outputs = facts
                .outputs
                .iter()
                .map(|output| {
                    let address = output.address.map(|address| {
                        zcash_keys::encoding::encode_transparent_address_p(&network, &address)
                    });
                    (output.value.into_u64(), address)
                })
                .collect();
            answer.fee = match facts.metadata().fee {
                WholeTransactionFee::Exact(fee) => Some(fee.into_u64()),
                _ => None,
            };
            answer.transparent_input_count = facts.input_count;
            answer.coinbase = facts.coinbase;
        }
        TxidLookup::Absent => answer.outcome = "absent",
        TxidLookup::PlacementUnknown(_) => answer.outcome = "placementUnknown",
        TxidLookup::Unsupported => answer.outcome = "unsupported",
    }
    Ok(answer)
}
