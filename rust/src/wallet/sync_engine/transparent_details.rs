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
//! The library's [`DetailRun`] lists the work, decides when to check the
//! display map, and turns each lookup's result into what the wallet records;
//! [`run`] drives it. A run is bounded by [`RUN_BUDGET`] and makes one lookup
//! at a time: the due transactions a detail view asked for ([`prioritize`])
//! first, whatever their age, then up to [`MAX_LOOKUPS`] others in the
//! wallet's order. Lookups run with no database lock held; each result is
//! stored, or each failure deferred, under the wallet write lock in its own
//! short transaction. A lookup the budget stopped timed out and is deferred
//! like an unavailable service; one the sync's exit stopped is not an
//! attempt: nothing is recorded, and the transaction stays due. Once the
//! budget is spent or the sync exits, a lookup gets [`CANCEL_GRACE`] to
//! return before it is abandoned, and writes may wait for the lock until
//! [`WRITE_GRACE`] past the budget: a run ends within 47 s, plus at most one
//! SQLite write already under way. Failures are logged by kind, never by
//! txid. The display facts the private source stores change no balance,
//! spendability, send or history; the public source's raw transaction is
//! ordinary wallet data, as from payload enhancement. Nothing this loop does
//! can fail the sync: [`transparent_details_followup`] catches errors and
//! panics.
//!
//! Work a private lookup held for the display map waits for the map to
//! change, and no lookup may be due to fetch a newer one: when nothing is due
//! and work is parked, the private source fetches the map alone and the run
//! lists again ([`DetailStep::RefreshMap`]). The database's refresh time
//! bounds these checks to six hours after the latest parked attempt or
//! attempted map check. The process keeps check times by origin across runs,
//! including failed checks.

use std::collections::{HashMap, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::{LazyLock, Mutex, PoisonError};
use std::time::{Duration, Instant, SystemTime};

use futures::FutureExt;
use tonic::transport::Channel;
use zakura_pir_client::transparent::{
    DetailAnswer, DetailApplied, DetailRun, DetailStep, DetailWrite,
};
use zcash_client_backend::data_api::{
    transparent_ledger::{
        TransparentDetailOutcome, TransparentDetailRequest, TransparentDetailWrite,
        TransparentDisplayStore, TransparentLedgerMode, TransparentLedgerRead,
    },
    wallet::decrypt_and_store_transaction,
    WalletRead,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};
use zcash_primitives::transaction::TxId;

use super::enhancement::EnhancementPolicy;
use super::{
    elapsed, followup_updated_event, SyncProgressEvent, TransparentLookupGate, WalletDatabase,
};
use crate::wallet::bounded_runtime::CANCEL_GRACE;
use crate::wallet::db::with_wallet_db_write_lock_unless;
use crate::wallet::network::WalletNetwork;

pub(crate) mod source;
#[cfg(test)]
pub(crate) mod tests;

use source::{DetailSource, GateSource, PirSource, PublicTransaction};

/// Time one run's lookups may take; see the module documentation for the
/// grace a run takes past it.
pub(crate) const RUN_BUDGET: Duration = Duration::from_secs(45);
/// How long past the budget a run may wait to record the lookup the budget
/// stopped: as long as that lookup had to return.
const WRITE_GRACE: Duration = CANCEL_GRACE;
/// Lookups one run may make besides the transactions detail views asked for.
pub(crate) const MAX_LOOKUPS: usize = 8;
/// Transactions a wallet's detail views may ask for at once.
const MAX_INTEREST: usize = 32;

/// Transactions detail views asked for, by wallet path, most recent first.
/// In memory only: a restart forgets them, and the views ask again.
static INTEREST: LazyLock<Mutex<HashMap<String, VecDeque<[u8; 32]>>>> =
    LazyLock::new(Default::default);

/// Looks up `txid` (protocol byte order) first in the next run over the
/// wallet at `db_path`, whatever its age, when it is due. A cancelled lookup
/// keeps it first; any recorded outcome serves it.
pub(crate) fn prioritize(db_path: &str, txid: [u8; 32]) {
    let mut interest = INTEREST.lock().unwrap_or_else(PoisonError::into_inner);
    let queue = interest.entry(db_path.to_owned()).or_default();
    queue.retain(|queued| *queued != txid);
    queue.push_front(txid);
    queue.truncate(MAX_INTEREST);
}

fn interest(db_path: &str) -> Vec<TxId> {
    INTEREST
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .get(db_path)
        .map(|queue| queue.iter().copied().map(TxId::from_bytes).collect())
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
    let service = source.service();
    let planned = DetailRun::plan(
        &*db,
        service.as_deref(),
        (clock.system)(),
        MAX_LOOKUPS,
        &interest(db_path),
    );
    let Ok(mut work) = planned else {
        log::warn!("transparent details: work unreadable; retrying later");
        return RunOutcome::Failed;
    };
    if should_exit() {
        return RunOutcome::Exited(stats);
    }
    // The listing's snapshot decides, for the whole run: a policy moved since
    // the run captured its source ends the run, and public transport needs
    // the listed mode to retain public authority.
    if work.policy_generation() != expected_generation {
        log::info!("transparent details: policy changed before the run; ending it");
        return RunOutcome::Superseded(stats);
    }
    if source.gate().is_some() && !work.public_transport() {
        log::info!("transparent details: transparent policy withholds public lookups");
        return RunOutcome::Withheld(stats);
    }

    while let Some(step) = work.next() {
        if should_exit() {
            return RunOutcome::Exited(stats);
        }
        if (clock.instant)() >= deadline {
            log::info!("transparent details: run budget spent; the rest waits for a later run");
            break;
        }
        let request = match step {
            DetailStep::Lookup(request) => request,
            DetailStep::RefreshMap(check) => {
                let checked = source.check_map(check, &budget_exit).await;
                if should_exit() {
                    return RunOutcome::Exited(stats);
                }
                let Some(checked) = checked else {
                    continue;
                };
                if checked.changed().is_some() {
                    log::info!("transparent details: display map changed; re-listing parked work");
                }
                if work.relist(&*db, checked, (clock.system)()).is_err() {
                    log::warn!("transparent details: work unreadable; retrying later");
                    return RunOutcome::Failed;
                }
                continue;
            }
        };
        let answer = source
            .lookup(request.txid, request.mined_height, &budget_exit)
            .await;
        stats.lookups += 1;
        let answer = match answer {
            Ok(DetailAnswer::Cancelled) if !should_exit() => {
                // The budget, not the sync, stopped a slow lookup: it timed
                // out, and backs off like any unavailable service.
                log::info!("transparent details: run budget spent during a lookup");
                DetailAnswer::TimedOut
            }
            Ok(answer) => answer,
            Err(_) => {
                log::info!("transparent details: transparent policy withholds public lookups");
                return RunOutcome::Withheld(stats);
            }
        };
        let now = (clock.system)();
        // Only the sync's exit cancels a lookup, which records nothing; its
        // transaction stays due.
        let Some(write) = work.record(&request, answer) else {
            return RunOutcome::Exited(stats);
        };
        // What a failed write leaves to record: the deferral it was, or
        // the map of the facts it could not store.
        let (deferral, facts_map) = match &write {
            DetailWrite::Defer { outcome, .. } => {
                log::info!(
                    "transparent details: lookup deferred ({})",
                    outcome_name(*outcome)
                );
                (Some(*outcome), None)
            }
            DetailWrite::Store { facts, .. } => (None, Some(facts.provenance.map_sha256)),
            DetailWrite::Raw { .. } => (None, None),
        };
        let Some(applied) = apply(db, write, now, &write_exit).await else {
            return gave_up(should_exit, stats);
        };
        let transaction = match applied {
            Ok(DetailApplied::Raw(transaction)) => transaction,
            Ok(DetailApplied::Stored(stored)) => {
                served(db_path, request.txid.as_ref());
                match stored {
                    TransparentDisplayStore::Stored => stats.stored += 1,
                    // Raw bytes arrived meanwhile, or the transaction left.
                    TransparentDisplayStore::Superseded => {}
                    TransparentDisplayStore::Contradiction(kind) => {
                        log::warn!(
                            "transparent details: facts contradict the wallet ({kind:?}); held"
                        );
                        stats.contradicted += 1;
                    }
                }
                continue;
            }
            Ok(DetailApplied::Deferred(outcome)) => {
                served(db_path, request.txid.as_ref());
                count_deferral(outcome, &mut stats);
                if matches!(outcome, TransparentDetailOutcome::Unavailable { .. }) {
                    return RunOutcome::Unavailable(stats);
                }
                continue;
            }
            Err(SqliteClientError::StaleTransparentPolicy { .. }) => return superseded(stats),
            Err(_) => {
                if let Some(outcome) = deferral {
                    log::warn!("transparent details: could not record a deferral");
                    if matches!(outcome, TransparentDetailOutcome::Unavailable { .. }) {
                        return RunOutcome::Unavailable(stats);
                    }
                    continue;
                }
                log::warn!("transparent details: store failed; retrying later");
                let unavailable = TransparentDetailOutcome::Unavailable { retry_after: None };
                match defer(
                    db,
                    &request,
                    expected_generation,
                    now,
                    unavailable,
                    facts_map,
                    &mut stats,
                    &write_exit,
                )
                .await
                {
                    Deferral::GaveUp => return gave_up(should_exit, stats),
                    Deferral::Superseded => return superseded(stats),
                    Deferral::Recorded => {}
                }
                served(db_path, request.txid.as_ref());
                continue;
            }
        };
        let Some(gate) = source.gate() else {
            match defer(
                db,
                &request,
                expected_generation,
                now,
                TransparentDetailOutcome::Protocol,
                None,
                &mut stats,
                &write_exit,
            )
            .await
            {
                Deferral::GaveUp => return gave_up(should_exit, stats),
                Deferral::Superseded => return superseded(stats),
                Deferral::Recorded => {}
            }
            served(db_path, request.txid.as_ref());
            continue;
        };
        let PublicTransaction {
            transaction,
            mined_height,
        } = transaction;
        // A completing write: the policy is read in the same transaction, so
        // a transition while the lookup was in flight leaves the transaction
        // to a later authorized run.
        let stored = with_wallet_db_write_lock_unless(
            "sync_engine.transparent_details.decrypt_and_store_transaction",
            &write_exit,
            || {
                db.transactionally(|tx| {
                    if !gate.permits_applied(tx.applied_transparent_policy()?) {
                        return Ok(false);
                    }
                    decrypt_and_store_transaction(&network, tx, &transaction, mined_height)?;
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
                log::info!("transparent details: transparent policy changed; ending the run");
                return RunOutcome::Withheld(stats);
            }
            Err(_) => {
                log::warn!("transparent details: store failed; retrying later");
                let unavailable = TransparentDetailOutcome::Unavailable { retry_after: None };
                match defer(
                    db,
                    &request,
                    expected_generation,
                    now,
                    unavailable,
                    None,
                    &mut stats,
                    &write_exit,
                )
                .await
                {
                    Deferral::GaveUp => return gave_up(should_exit, stats),
                    Deferral::Superseded => return superseded(stats),
                    Deferral::Recorded => {}
                }
            }
        }
        served(db_path, request.txid.as_ref());
    }
    RunOutcome::Finished(stats)
}

/// Writes what a lookup's result writes under the wallet's write lock: facts
/// or a deferral, each in its own short transaction. A public transaction is
/// handed back unwritten. `None` when it gave up waiting for the lock at
/// `write_exit`, writing nothing.
async fn apply(
    db: &mut WalletDatabase,
    write: DetailWrite<PublicTransaction>,
    now: SystemTime,
    write_exit: &(dyn Fn() -> bool + Sync),
) -> Option<Result<DetailApplied<PublicTransaction>, SqliteClientError>> {
    let operation = match &write {
        DetailWrite::Store { .. } => "sync_engine.transparent_details.store",
        DetailWrite::Defer { .. } => "sync_engine.transparent_details.defer",
        DetailWrite::Raw { .. } => "sync_engine.transparent_details.raw",
    };
    with_wallet_db_write_lock_unless(operation, write_exit, || write.apply(db, now)).await
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

/// What [`defer`] did.
enum Deferral {
    /// Recorded, or failed and logged: the transaction waits for a later run.
    Recorded,
    /// Gave up waiting for the wallet's write lock, recording nothing.
    GaveUp,
    /// The policy generation moved since the listing, recording nothing.
    Superseded,
}

/// Records a lookup of `request` whose result could not be stored, which
/// schedules the next attempt, and counts it. The deferral is written under
/// `expected_generation`, the listing's policy generation, so a lookup made
/// under another policy schedules nothing under this one.
async fn defer(
    db: &mut WalletDatabase,
    request: &TransparentDetailRequest,
    expected_generation: u64,
    now: SystemTime,
    outcome: TransparentDetailOutcome,
    map_sha256: Option<[u8; 32]>,
    stats: &mut RunStats,
    write_exit: &(dyn Fn() -> bool + Sync),
) -> Deferral {
    let deferred = with_wallet_db_write_lock_unless(
        "sync_engine.transparent_details.defer",
        write_exit,
        || {
            db.defer_transparent_detail(
                request.txid,
                request.mined_height,
                outcome,
                map_sha256,
                expected_generation,
                now,
            )
        },
    )
    .await;
    match deferred {
        None => Deferral::GaveUp,
        Some(Ok(())) => {
            count_deferral(outcome, stats);
            Deferral::Recorded
        }
        Some(Err(SqliteClientError::StaleTransparentPolicy { .. })) => Deferral::Superseded,
        Some(Err(_)) => {
            log::warn!("transparent details: could not record a deferral");
            Deferral::Recorded
        }
    }
}

/// How the run ends when a write found the policy generation moved: what it
/// stored before stays, and nothing is written under the new policy.
fn superseded(stats: RunStats) -> RunOutcome {
    log::info!("transparent details: policy changed; ending the run");
    RunOutcome::Superseded(stats)
}

/// Counts a recorded deferral by its outcome.
fn count_deferral(outcome: TransparentDetailOutcome, stats: &mut RunStats) {
    match outcome {
        TransparentDetailOutcome::NotCovered | TransparentDetailOutcome::Unsupported => {
            stats.not_covered += 1
        }
        _ => stats.deferred += 1,
    }
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
/// `completed` (scanned height, chain tip), and reports a follow-up update
/// when it stored anything.
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

/// Logs a run's outcome and, when it stored anything, reports a follow-up
/// update of the sync that completed at `completed`.
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
        progress_fn(followup_updated_event(completed));
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

/// Public loads in flight, by id: the wallet each would store into and the
/// flag that cancels it.
static PUBLIC_LOADS: std::sync::LazyLock<
    std::sync::Mutex<
        std::collections::HashMap<u64, (String, std::sync::Arc<std::sync::atomic::AtomicBool>)>,
    >,
> = std::sync::LazyLock::new(Default::default);
static NEXT_PUBLIC_LOAD: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
/// Moved by every [`cancel_public_loads`], under the [`PUBLIC_LOADS`] lock.
static PUBLIC_LOAD_EPOCH: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// The cancellation epoch a public load registered now belongs to. The app
/// reads it when the user's load begins, before any asynchronous step, and
/// passes it to [`enhance_publicly`], so a cancellation between that moment
/// and the load reaching Rust still stops it.
pub(crate) fn public_load_epoch() -> u64 {
    let _loads = public_loads();
    PUBLIC_LOAD_EPOCH.load(std::sync::atomic::Ordering::SeqCst)
}

/// One [`enhance_publicly`] in flight, registered so a lock or a destructive
/// wallet change can cancel it ([`cancel_public_loads`]).
struct PublicLoad {
    id: u64,
    cancelled: std::sync::Arc<std::sync::atomic::AtomicBool>,
}

impl PublicLoad {
    /// Registers a load that began in `epoch`; it starts cancelled when a
    /// [`cancel_public_loads`] has run since.
    fn start(db_path: &str, epoch: u64) -> Self {
        let id = NEXT_PUBLIC_LOAD.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let mut loads = public_loads();
        let stale = PUBLIC_LOAD_EPOCH.load(std::sync::atomic::Ordering::SeqCst) != epoch;
        let cancelled = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(stale));
        loads.insert(id, (db_path.to_owned(), cancelled.clone()));
        Self { id, cancelled }
    }

    fn cancelled(&self) -> bool {
        self.cancelled.load(std::sync::atomic::Ordering::SeqCst)
    }
}

impl Drop for PublicLoad {
    fn drop(&mut self) {
        public_loads().remove(&self.id);
    }
}

fn public_loads() -> std::sync::MutexGuard<
    'static,
    std::collections::HashMap<u64, (String, std::sync::Arc<std::sync::atomic::AtomicBool>)>,
> {
    PUBLIC_LOADS
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Cancels every public load in flight, including one that began in an
/// earlier epoch and has not registered yet: one still connecting sends
/// nothing, and none stores what it receives. For a lock or sign-out, and
/// before an account or the wallet is deleted.
pub(crate) fn cancel_public_loads() {
    let loads = public_loads();
    PUBLIC_LOAD_EPOCH.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    for (_, cancelled) in loads.values() {
        cancelled.store(true, std::sync::atomic::Ordering::SeqCst);
    }
}

/// [`cancel_public_loads`] for the wallet at `db_path` only, so a test leaves
/// other tests' loads alone.
#[cfg(test)]
pub(crate) fn cancel_public_loads_at(db_path: &str) {
    for (path, cancelled) in public_loads().values() {
        if path == db_path {
            cancelled.store(true, std::sync::atomic::Ordering::SeqCst);
        }
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
/// Consent is the caller's to ask for, but the wallet decides what may be
/// revealed: `account` must hold a transparent part of `txid`, or nothing is
/// sent. An arbitrary txid never reaches lightwalletd through this path.
///
/// Retains the original existing SQLite handle and physical file identity.
/// The network wait holds no SQL transaction or wallet write lock. A reset,
/// file replacement, account change or policy transition discards the result;
/// validation and storage share one wallet transaction, including the final
/// read that checks whether the wallet accepted the transaction.
/// [`cancel_public_loads`] stops it before the request, or discards what it
/// received; one run since `cancel_epoch` ([`public_load_epoch`]) stops it
/// before it opens the wallet.
pub(crate) fn enhance_publicly(
    db_path: &str,
    network: WalletNetwork,
    lightwalletd_url: &str,
    account: AccountUuid,
    txid: [u8; 32],
    cancel_epoch: u64,
) -> Result<(), String> {
    use crate::wallet::db::{
        open_existing_wallet_db_with_timeout, with_wallet_db_write_lock, WALLET_DB_BUSY_TIMEOUT,
    };
    use zcash_client_backend::data_api::transparent_ledger::TransparentDetailRead;
    const CANCELLED: &str = "the lookup was cancelled; nothing was stored";
    let txid = TxId::from_bytes(txid);
    let load = PublicLoad::start(db_path, cancel_epoch);
    if load.cancelled() {
        return Err(CANCELLED.to_owned());
    }
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
    let (started, held) = db
        .transactionally(|tx| {
            Ok::<_, SqliteClientError>((
                PublicLoadIdentity::of(tx)?,
                tx.transparent_display_view(account, txid)?.is_some(),
            ))
        })
        .map_err(|error| format!("reading the wallet failed ({error})"))?;
    if !held {
        return Err(
            "the account holds no transparent part of this transaction; nothing was sent"
                .to_owned(),
        );
    }
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .map_err(|error| format!("tokio: {error}"))?;
    let raw = runtime.block_on(async {
        // Account deletion and wallet reset wait for this load, so a Tor
        // route still bootstrapping must not hold them for its deadline.
        let transport =
            super::lwd::open_isolated_lwd_transport_until(lightwalletd_url, || load.cancelled())
                .await;
        if load.cancelled() {
            return Err(CANCELLED.to_owned());
        }
        let transport = transport.map_err(|error| format!("lightwalletd unavailable ({error})"))?;
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
            if load.cancelled() {
                return Err(CANCELLED.to_owned());
            }
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
/// wallet behind `db`; `None` when the transaction has no transparent part
/// the account takes part in. Receipts read it with their history view
/// through the library's receipt read.
#[cfg(test)]
pub(crate) fn detail_view(
    db: &impl zcash_client_backend::data_api::transparent_ledger::TransparentDetailRead<
        AccountId = AccountUuid,
        Error = SqliteClientError,
    >,
    account: AccountUuid,
    txid: &[u8],
) -> Result<
    Option<zcash_client_backend::data_api::transparent_ledger::TransparentDisplayView>,
    String,
> {
    let txid: [u8; 32] = txid.try_into().map_err(|_| "txid length".to_owned())?;
    db.transparent_display_view(account, TxId::from_bytes(txid))
        .map_err(|error| format!("transparent detail view: {error}"))
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
    let found = source::BlockingLookup {
        service: source::service_for(&origin),
        origin,
        txid,
        mined_height,
        handle: runtime.handle().clone(),
        cancel: Default::default(),
        #[cfg(test)]
        observer: None,
    }
    .run()
    .found;
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
    found: zakura_pir_client::transparent::TxidLookup,
    mined_height: u64,
) -> Result<DebugLookup, String> {
    use zakura_pir_client::transparent::TxidLookup;
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
            let facts = zakura_pir_client::transparent::display_facts(
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
        TxidLookup::RecentBelowFloor => answer.outcome = "recentBelowFloor",
        TxidLookup::Unsupported => answer.outcome = "unsupported",
    }
    Ok(answer)
}
