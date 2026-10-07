//! Loop 4: transparent txid enhancement.
//!
//! A sync runs four loops. (1) Compact scanning, (2) Ironwood payload
//! enhancement ([`super::enhancement`]) and (3) transparent discovery (public
//! lightwalletd lanes, or private recovery in [`super::transparent_ledger`])
//! decide balances, spendability and history. This loop only fills in what a
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
//! one at a time, in the wallet's order, with any due transaction a detail
//! view asked for ([`prioritize`]) ahead of the rest. Lookups run with no
//! database lock held; each result is stored, or each failure deferred, under
//! the wallet write lock in its own short transaction. Failures are logged by
//! kind, never by txid. Nothing this loop does changes balances,
//! spendability, sends or history, and nothing it does can fail the sync:
//! [`transparent_details_followup`] catches errors and panics.

use std::collections::{HashMap, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::{LazyLock, Mutex, PoisonError};
use std::time::{Duration, Instant, SystemTime};

use futures::FutureExt;
use tonic::transport::Channel;
use zcash_client_backend::data_api::{
    transparent_ledger::{
        TransparentDetailOutcome, TransparentDetailRead, TransparentDetailWrite,
        TransparentDisplayStore, TransparentDisplayView, TransparentLedgerMode,
        TransparentLedgerRead,
    },
    wallet::decrypt_and_store_transaction,
};
use zcash_client_backend::proto::service::compact_tx_streamer_client::CompactTxStreamerClient;
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};
use zcash_primitives::transaction::TxId;

use super::enhancement::EnhancementPolicy;
use super::{elapsed, SyncProgressEvent, TransparentLookupGate, WalletDatabase};
use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::network::WalletNetwork;

pub(crate) mod source;
#[cfg(test)]
pub(crate) mod tests;

use source::{DetailAnswer, DetailFailure, DetailSource, GateSource, PirSource};

/// Time one run may take, lookups and stores included.
pub(crate) const RUN_BUDGET: Duration = Duration::from_secs(45);
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

/// Serves `txid` (protocol byte order) first in the next run for the wallet
/// at `db_path`, once the wallet has it due.
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
    let mut work = match db.transparent_detail_work(
        (clock.system)(),
        WORK_WINDOW,
        source.map_sha256(),
    ) {
        Ok(work) => work,
        Err(_) => {
            log::warn!("transparent details: work unreadable; retrying on a later sync");
            return RunOutcome::Failed;
        }
    };
    let prioritized = interest(db_path);
    work.sort_by_key(|request| {
        prioritized
            .iter()
            .position(|txid| txid == request.txid.as_ref())
            .unwrap_or(usize::MAX)
    });
    work.truncate(MAX_LOOKUPS);
    let budget_exit = move || should_exit() || (clock.instant)() >= deadline;

    for request in work {
        if should_exit() {
            return RunOutcome::Exited(stats);
        }
        if (clock.instant)() >= deadline {
            log::info!("transparent details: run budget spent; the rest waits for a later run");
            break;
        }
        let txid = request.txid;
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
                    now,
                    TransparentDetailOutcome::Unavailable { retry_after: None },
                    None,
                    &mut stats,
                );
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
                defer(db, txid, now, outcome, map_sha256, &mut stats);
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
                    defer(db, txid, now, TransparentDetailOutcome::Protocol, None, &mut stats);
                    continue;
                }
                let map_sha256 = Some(facts.provenance.map_sha256);
                let stored =
                    with_wallet_db_write_lock("sync_engine.transparent_details.store", || {
                        db.store_transparent_display(*facts, expected_generation, now)
                    });
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
                        defer(
                            db,
                            txid,
                            now,
                            TransparentDetailOutcome::Unavailable { retry_after: None },
                            map_sha256,
                            &mut stats,
                        );
                    }
                }
            }
            DetailAnswer::Raw {
                transaction,
                mined_height,
            } => {
                let Some(gate) = source.gate() else {
                    defer(db, txid, now, TransparentDetailOutcome::Protocol, None, &mut stats);
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
                            Ok::<_, SqliteClientError>(true)
                        })
                    },
                );
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
                        defer(
                            db,
                            txid,
                            now,
                            TransparentDetailOutcome::Unavailable { retry_after: None },
                            None,
                            &mut stats,
                        );
                    }
                }
            }
        }
    }
    RunOutcome::Finished(stats)
}

/// Records a failed lookup of `txid` in the wallet, which schedules the next
/// attempt, and counts it.
fn defer(
    db: &mut WalletDatabase,
    txid: TxId,
    now: SystemTime,
    outcome: TransparentDetailOutcome,
    map_sha256: Option<[u8; 32]>,
    stats: &mut RunStats,
) {
    let deferred = with_wallet_db_write_lock("sync_engine.transparent_details.defer", || {
        db.defer_transparent_detail(txid, outcome, map_sha256, now)
    });
    match deferred {
        Ok(()) => match outcome {
            TransparentDetailOutcome::NotCovered | TransparentDetailOutcome::Unsupported => {
                stats.not_covered += 1
            }
            _ => stats.deferred += 1,
        },
        Err(_) => log::warn!("transparent details: could not record a deferral"),
    }
}

/// An outcome's name, for logs.
fn outcome_name(outcome: TransparentDetailOutcome) -> &'static str {
    match outcome {
        TransparentDetailOutcome::Unavailable { .. } => "unavailable",
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

/// The detail view of `txid` (protocol byte order) for `account`, from the
/// wallet behind `db` and its connection `conn`; `None` when the account
/// recorded no transparent part of it and the wallet keeps no detail work for
/// it.
pub(crate) fn detail_view(
    db: &WalletDatabase,
    conn: &rusqlite::Connection,
    account: AccountUuid,
    txid: &[u8],
) -> Result<Option<TransparentDisplayView>, String> {
    let txid: [u8; 32] = txid.try_into().map_err(|_| "txid length".to_owned())?;
    if !transparent_part(conn, account, &txid)? {
        return Ok(None);
    }
    db.transparent_display_view(account, TxId::from_bytes(txid))
        .map_err(|error| format!("transparent detail view: {error}"))
}

/// Whether the account recorded a transparent output or spend of `txid`, or
/// the wallet keeps detail work for it (a mixed transaction).
fn transparent_part(
    conn: &rusqlite::Connection,
    account: AccountUuid,
    txid: &[u8; 32],
) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS (
             SELECT 1 FROM transparent_received_outputs o
             JOIN transactions t ON t.id_tx = o.transaction_id
             JOIN accounts a ON a.id = o.account_id
             WHERE t.txid = ?2 AND a.uuid = ?1
             UNION ALL
             SELECT 1 FROM transparent_received_output_spends s
             JOIN transparent_received_outputs o ON o.id = s.transparent_received_output_id
             JOIN transactions t ON t.id_tx = s.transaction_id
             JOIN accounts a ON a.id = o.account_id
             WHERE t.txid = ?2 AND a.uuid = ?1
             UNION ALL
             SELECT 1 FROM tpir_receive_events r JOIN accounts a ON a.id = r.account_id
             WHERE r.txid = ?2 AND a.uuid = ?1
             UNION ALL
             SELECT 1 FROM tpir_spend_events s JOIN accounts a ON a.id = s.account_id
             WHERE s.spending_txid = ?2 AND a.uuid = ?1
             UNION ALL
             SELECT 1 FROM transparent_detail_work w
             JOIN transactions t ON t.id_tx = w.transaction_id
             WHERE t.txid = ?2
         )",
        rusqlite::params![account.expose_uuid().as_bytes().as_slice(), txid.as_slice()],
        |row| row.get(0),
    )
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
        found.map_err(|error| format!("Private lookup failed ({error})"))?,
        mined_height,
    )
}

/// A lookup's result as a development answer.
pub(crate) fn debug_answer(
    network: WalletNetwork,
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
        TxidLookup::Found { record, provenance } => {
            let height = u32::try_from(mined_height).map_err(|_| "height out of range")?;
            let facts =
                zakura_pir_transparent::display_facts(&record, &provenance, height.into())
                    .map_err(|_| "the service returned unusable facts".to_owned())?;
            answer.outputs = facts
                .outputs
                .iter()
                .map(|output| {
                    let address = transparent::bundle::TxOut::new(
                        output.value,
                        transparent::address::Script(zcash_script::script::Code(
                            output.script.clone(),
                        )),
                    )
                    .recipient_address()
                    .map(|address| {
                        zcash_keys::encoding::encode_transparent_address_p(&network, &address)
                    });
                    (output.value.into_u64(), address)
                })
                .collect();
            answer.fee = match facts.metadata.fee {
                WholeTransactionFee::Exact(fee) => Some(fee.into_u64()),
                _ => None,
            };
            answer.transparent_input_count = facts.metadata.transparent_input_count;
            answer.coinbase = facts.coinbase;
        }
        TxidLookup::Absent => answer.outcome = "absent",
        TxidLookup::PlacementUnknown(_) => answer.outcome = "placementUnknown",
        TxidLookup::Unsupported => answer.outcome = "unsupported",
    }
    Ok(answer)
}
