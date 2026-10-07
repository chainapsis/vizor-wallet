//! Loop 4: transparent txid enhancement.
//!
//! A sync runs four loops. (1) Compact scanning, (2) Ironwood payload
//! enhancement ([`super::enhancement`]) and (3) transparent discovery (public
//! lightwalletd lanes, or private recovery in [`super::transparent_ledger`])
//! decide balances, spendability and history. This loop only fills in what a
//! detail view shows: for each mined transparent or mixed transaction of the
//! wallet with no raw bytes, it fetches that transaction's details by txid.
//!
//! The source is chosen once per run from the policy the sync captured:
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
//! one at a time, the most recently mined first, with any transaction a
//! detail view asked for ([`prioritize`]) ahead of the rest. Lookups run with
//! no database lock held; each result is stored under the wallet write lock
//! in its own short transaction. Every failure defers its transaction with a
//! backoff and is logged by kind, never by txid. Nothing this loop does
//! changes balances, spendability, sends or history, and nothing it does can
//! fail the sync: [`transparent_details_followup`] catches errors and panics.

use std::collections::{HashMap, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::{LazyLock, Mutex, PoisonError};
use std::time::{Duration, Instant};

use futures::FutureExt;
use tonic::transport::Channel;
use zcash_client_backend::data_api::{
    transparent_ledger::{TransparentLedgerMode, TransparentLedgerRead},
    wallet::decrypt_and_store_transaction,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;

use super::enhancement::EnhancementPolicy;
use super::{elapsed, SyncProgressEvent, TransparentLookupGate, WalletDatabase};
use crate::wallet::db::{
    open_readonly_conn_with_timeout, with_wallet_db_write_lock, READ_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;

pub(crate) mod client;
pub(crate) mod source;
pub(crate) mod store;
#[cfg(test)]
pub(crate) mod tests;

use source::{DetailAnswer, DetailFailure, DetailSource, GateSource, PirSource};
use store::{DeferOutcome, StoreOutcome};

/// Time one run may take, lookups and stores included.
pub(crate) const RUN_BUDGET: Duration = Duration::from_secs(45);
/// Lookups one run may make.
pub(crate) const MAX_LOOKUPS: usize = 8;
/// Transactions a wallet's detail views may ask for at once.
const MAX_INTEREST: usize = 32;

/// Transactions detail views asked for, by wallet path, most recent first.
/// In memory only: a restart forgets them, and the views ask again.
static INTEREST: LazyLock<Mutex<HashMap<String, VecDeque<[u8; 32]>>>> =
    LazyLock::new(Default::default);

/// Serves `txid` (protocol byte order) first in the next run for the wallet
/// at `db_path`, ahead of its backoff unless the publication does not cover
/// it.
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
    /// Transactions the private publication does not cover.
    pub(crate) not_covered: usize,
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

/// Clocks a run measures its budget and schedules retries on.
#[derive(Clone, Copy)]
pub(crate) struct StageClock {
    pub(crate) instant: fn() -> Instant,
    /// Unix seconds.
    pub(crate) unix: fn() -> i64,
}

impl StageClock {
    pub(crate) fn system() -> Self {
        Self {
            instant: Instant::now,
            unix: unix_now,
        }
    }
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |since| i64::try_from(since.as_secs()).unwrap_or(i64::MAX))
}

/// One bounded run of loop 4 over the wallet at `db_path`, through `source`.
///
/// `expected_generation` is the durable policy generation captured with the
/// source; a private result is stored only while it holds. Never returns an
/// error: failures defer their transaction and are logged by kind.
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
    let wallet = match open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT)) {
        Ok(wallet) => wallet,
        Err(_) => {
            log::warn!("transparent details: wallet unreadable; retrying on a later sync");
            return RunOutcome::Failed;
        }
    };
    let mut details = match store::open_store(db_path) {
        Ok(details) => details,
        Err(_) => {
            log::warn!("transparent details: store unusable; retrying on a later sync");
            return RunOutcome::Failed;
        }
    };
    let prioritized = interest(db_path);
    let work = match store::transparent_detail_work(
        &wallet,
        &details,
        (clock.unix)(),
        MAX_LOOKUPS,
        &prioritized,
    ) {
        Ok(work) => work,
        Err(_) => {
            log::warn!("transparent details: work unreadable; retrying on a later sync");
            return RunOutcome::Failed;
        }
    };
    drop(wallet);
    let budget_exit = move || should_exit() || (clock.instant)() >= deadline;

    for item in work {
        if should_exit() {
            return RunOutcome::Exited(stats);
        }
        if (clock.instant)() >= deadline {
            log::info!("transparent details: run budget spent; the rest waits for a later run");
            break;
        }
        let answer = source
            .lookup(item.txid, item.mined_height, &budget_exit)
            .await;
        stats.lookups += 1;
        served(db_path, &item.txid);
        let now = (clock.unix)();
        let defer = |details: &rusqlite::Connection,
                     outcome: DeferOutcome,
                     map: Option<&str>,
                     stats: &mut RunStats| {
            match store::defer_transparent_detail(details, &item.txid, outcome, map, now) {
                Ok(()) => {
                    if outcome == DeferOutcome::NotCovered {
                        stats.not_covered += 1;
                    } else {
                        stats.deferred += 1;
                    }
                }
                Err(_) => log::warn!("transparent details: could not record a deferral"),
            }
        };
        match answer {
            Err(DetailFailure::Cancelled) => {
                if should_exit() {
                    return RunOutcome::Exited(stats);
                }
                // The budget, not the sync, stopped a slow lookup.
                log::info!("transparent details: run budget spent during a lookup");
                defer(
                    &details,
                    DeferOutcome::Unavailable { retry_after: None },
                    None,
                    &mut stats,
                );
                break;
            }
            Err(DetailFailure::Withheld) => {
                log::info!("transparent details: transparent policy withholds public lookups");
                return RunOutcome::Withheld(stats);
            }
            Err(DetailFailure::Unavailable { retry_after }) => {
                log::info!("transparent details: service unavailable; retrying later");
                defer(
                    &details,
                    DeferOutcome::Unavailable { retry_after },
                    None,
                    &mut stats,
                );
                return RunOutcome::Unavailable(stats);
            }
            Err(DetailFailure::Failed(kind)) => {
                log::warn!("transparent details: lookup failed ({kind})");
                defer(&details, DeferOutcome::Failed, None, &mut stats);
            }
            Ok(DetailAnswer::NotCovered { map_sha256 }) => {
                defer(
                    &details,
                    DeferOutcome::NotCovered,
                    map_sha256.as_deref(),
                    &mut stats,
                );
            }
            Ok(DetailAnswer::Facts { record, provenance }) => {
                if record.txid.0 != item.txid {
                    log::error!("transparent details: source answered another transaction");
                    defer(&details, DeferOutcome::Failed, None, &mut stats);
                    continue;
                }
                let stored = with_wallet_db_write_lock("sync_engine.transparent_details.store", || {
                    let applied = db
                        .applied_transparent_policy()
                        .map_err(|_| "applied policy unreadable".to_owned())?;
                    store::store_transparent_display(
                        &mut details,
                        &record,
                        &provenance,
                        expected_generation,
                        applied.generation,
                        now,
                    )
                });
                match stored {
                    Ok(StoreOutcome::Stored) => stats.stored += 1,
                    Ok(StoreOutcome::Superseded) => {
                        log::info!("transparent details: policy changed; ending the run");
                        return RunOutcome::Superseded(stats);
                    }
                    Ok(StoreOutcome::Contradiction) => {
                        log::warn!("transparent details: facts contradict stored ones; keeping them");
                    }
                    Err(_) => {
                        log::warn!("transparent details: store failed; retrying later");
                        defer(&details, DeferOutcome::Failed, None, &mut stats);
                    }
                }
            }
            Ok(DetailAnswer::Raw {
                transaction,
                mined_height,
            }) => {
                let Some(gate) = source.gate() else {
                    defer(&details, DeferOutcome::Failed, None, &mut stats);
                    continue;
                };
                // A completing write: the policy is read in the same
                // transaction, so a transition while the lookup was in flight
                // leaves the transaction to a later authorized run.
                let stored = with_wallet_db_write_lock(
                    "sync_engine.transparent_details.decrypt_and_store_transaction",
                    || {
                        db.transactionally(|tx| {
                            if !gate.permits_applied(tx.applied_transparent_policy()?) {
                                return Ok(false);
                            }
                            decrypt_and_store_transaction(&network, tx, &transaction, mined_height)?;
                            Ok::<_, zcash_client_sqlite::error::SqliteClientError>(true)
                        })
                    },
                );
                match stored {
                    Ok(true) => stats.stored += 1,
                    Ok(false) => {
                        log::info!("transparent details: transparent policy changed; ending the run");
                        return RunOutcome::Withheld(stats);
                    }
                    Err(_) => {
                        log::warn!("transparent details: store failed; retrying later");
                        defer(&details, DeferOutcome::Failed, None, &mut stats);
                    }
                }
            }
        }
    }
    RunOutcome::Finished(stats)
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
    let gate = match TransparentLookupGate::for_wallet(lookups, db_data_path, network) {
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

/// The detail view of `txid` for `account_uuid`, from the wallet at
/// `db_path`; `None` when the transaction has no transparent part the
/// account recorded.
pub(crate) fn detail_view(
    wallet: &rusqlite::Connection,
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &[u8],
    txid: &[u8],
) -> Result<Option<store::DisplayView>, String> {
    store::transparent_display_view(wallet, db_path, network, account_uuid, txid)
}

/// What a development lookup found, without storing anything.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DebugLookup {
    /// `found`, `absent`, `placementUnknown` or `unsupported`.
    pub(crate) outcome: &'static str,
    pub(crate) outputs: Vec<store::ViewOutput>,
    pub(crate) fee: Option<u64>,
    pub(crate) transparent_input_count: u32,
    pub(crate) coinbase: bool,
    /// Private queries the lookup sent.
    pub(crate) private_queries: u32,
}

/// One private txid display lookup of `txid` (protocol byte order) mined at
/// `mined_height`, through the process-wide client, persisting nothing.
///
/// Development builds only: refused unless the
/// `ZCASH_PRIVATE_TRANSPARENT_RECOVERY` flag is set, and off mainnet. Runs
/// on the caller's thread, which must not be a runtime worker.
pub(crate) fn debug_lookup(
    network: WalletNetwork,
    txid: [u8; 32],
    mined_height: u64,
) -> Result<DebugLookup, String> {
    if !super::enhancement::private_transparent_recovery() {
        return Err("Private transparent lookups need a development build".to_owned());
    }
    let origin =
        source::txid_origin(network).ok_or("Private transparent lookups are mainnet only")?;
    lookup_once(&origin, network, txid, mined_height)
}

/// [`debug_lookup`] without the build check, against `origin`.
pub(crate) fn lookup_once(
    origin: &str,
    network: WalletNetwork,
    txid: [u8; 32],
    mined_height: u64,
) -> Result<DebugLookup, String> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .map_err(|error| format!("tokio: {error}"))?;
    let lookup = source::BlockingLookup {
        origin: origin.to_owned(),
        client: source::client_for(origin, network),
        txid,
        mined_height,
        handle: runtime.handle().clone(),
        cancel: Default::default(),
        #[cfg(test)]
        observer: None,
    };
    let (found, _, private_queries) = lookup
        .run()
        .map_err(|error| format!("Private lookup failed ({})", error.name()))?;
    let mut answer = DebugLookup {
        outcome: "found",
        outputs: Vec::new(),
        fee: None,
        transparent_input_count: 0,
        coinbase: false,
        private_queries,
    };
    match found {
        client::TxidLookup::Found { record, .. } => {
            answer.outputs = record
                .outputs
                .iter()
                .enumerate()
                .map(|(index, output)| store::ViewOutput {
                    index: index as u32,
                    value: output.value,
                    address: store::script_address(network, &output.script),
                    own: false,
                })
                .collect();
            answer.fee = match record.metadata.fee {
                transparent_events::FeeState::Exact(fee) => Some(fee),
                _ => None,
            };
            answer.transparent_input_count = record.metadata.transparent_input_count;
            answer.coinbase = record.coinbase;
        }
        client::TxidLookup::Absent => answer.outcome = "absent",
        client::TxidLookup::PlacementUnknown => answer.outcome = "placementUnknown",
        client::TxidLookup::Unsupported => answer.outcome = "unsupported",
    }
    Ok(answer)
}
