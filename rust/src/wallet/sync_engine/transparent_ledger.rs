//! Private transparent recovery and activation.
//!
//! After each completed sync, [`run`] asks a [`RecoverySource`] about each
//! account in passes, with no database lock held across a source call. A pass
//! answers with the adapter's [`PassReport`]: the batch state and progress,
//! whose [`Retry`] says when to pass again. The source then settles a `Ready`
//! batch itself ([`RecoverySource::apply`]): its commits are applied in order,
//! each in its own library transaction, and the batch is acknowledged only
//! once every one committed. The adapter's [`PassPlan`] reads each pass and
//! its settlement and names the next [`Step`]; budgets, waits, holds and
//! promotion are the coordinator's. The transparent PIR source takes the
//! wallet write lock for one commit at a time and steps aside between commits
//! for a waiting writer, so a foreground wallet write waits at most one
//! commit, and cancellation stops a settlement between commits. A `Pending`
//! or `Withdrawn` batch applies nothing and is never acknowledged.
//!
//! Under `PrivateRequired`, a trusted source's commits are qualified as they
//! are applied ([`Trust::Trusted`]): the trusted-indexer decision, which is
//! what lets a recovered account be promoted. Commits of an untrusted source
//! are only observed, and never qualify an account for promotion.
//!
//! A `Ready` batch can resolve retired revisions, provisional revisions an
//! earlier batch exported that its commits succeed. Only trusted commits
//! withdraw their evidence, so an observed settlement refuses such a batch
//! before applying anything, the run holds the account, and the source
//! reports the retirements again until a trusted run reconciles them.
//!
//! A candidate account's state lives only in the library's `tpir_*` tables.
//! It never changes balances, input selection, locks, address allocation, or
//! history, and it shares no checkpoint, queue, retry, or cache with shielded
//! scanning, public UTXO refresh, or the `.receive.redb` receive cache. Under
//! `PrivateRequired`, each recovered candidate is then offered for promotion;
//! the library rechecks everything and refuses while any blocker remains. An
//! active account's later commits project into the wallet in the same
//! transaction.
//!
//! A run is bounded. The active account goes first and the rest follow from a
//! rotating cursor. Each account gets one counted pass per run (stale commits
//! retry from a fresh watch set at most [`LIMITS`] times) within
//! [`ACCOUNT_BUDGET`], and the run at most [`RUN_BUDGET`]. Whatever a pass
//! found, more work waits for the next run, which the app starts after a sync
//! that follows a new block. A lagging publication or an overloaded service
//! names a delay; the account is skipped without traffic until it passes,
//! then may retry at the same block. Such a retry visits only accounts whose
//! service waits expired, so private content cannot unlock another pass.
//! An account that cannot progress is held in memory
//! for [`HOLD`] and skipped without traffic, as is a quarantined account.
//! Software and hardware accounts recover from their stored birthday.
//!
//! Private queries off captures `Public`, so [`run`] returns before any read
//! or request. On supported mainnet, private queries on captures
//! `PrivateRequired`, and [`run`] first raises the wallet's durable policy
//! from a confirmed preference. The coordinator takes no lightwalletd client,
//! so it cannot make a public request.

use std::collections::HashMap;
use std::future::Future;
use std::sync::{LazyLock, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

pub(crate) use zakura_pir_client::transparent::{
    Applied, ApplyAction, ApplyFailure, BatchState, PassReport, Retry, Trust, WithdrawnCause,
};
use zakura_pir_client::transparent::{
    HoldCause as PlanHold, PassLimits, PassPlan, Step, StopCause,
};
use zcash_client_backend::data_api::{
    transparent_ledger::{
        AccountLifecycle, RecoveryBlocker, TransparentAddressWatchSet, TransparentLedgerMode,
        TransparentLedgerRead, TransparentLedgerWrite,
    },
    WalletRead,
};
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};

use super::enhancement::{may_raise, EnhancementPolicy};
use super::SyncError;
use crate::wallet::db::{with_wallet_db_write_lock, WalletDatabase};
use crate::wallet::network::WalletNetwork;

#[cfg(test)]
pub(crate) mod fixture;
pub(crate) mod import_discovery;
pub(crate) mod pir;
mod policy;
#[cfg(test)]
pub(crate) mod tests;

pub(crate) use pir::TransparentPirSource;
use policy::raise_to_required;
pub(crate) use policy::{
    current_transparent_policy, forget_private_ledger, set_transparent_policy,
};

/// Fresh watch sets tried after stale commits in one run. Each account gets
/// one counted pass per run: a grown window, a changed watch set, or a
/// continuation that asks for more waits for the next run.
const LIMITS: PassLimits = PassLimits { stale_refreshes: 3 };
/// Time one account may take in a run, waits included.
const ACCOUNT_BUDGET: Duration = Duration::from_secs(120);
/// Time one run may take. Accounts it does not reach wait for a later run.
const RUN_BUDGET: Duration = Duration::from_secs(180);
/// Abandons a source call that ignores its exit signal. A transparent PIR
/// pass stops itself at [`pir::PASS_DEADLINE`], well before.
const PASS_BACKSTOP: Duration = Duration::from_secs(pir::PASS_DEADLINE.as_secs() + 30);
/// How long an account that cannot progress is skipped.
const HOLD: Duration = Duration::from_secs(60 * 60);

/// What a source is asked about one account.
#[derive(Clone, Copy)]
pub(crate) struct SourceRequest<'a> {
    pub(crate) account: AccountUuid,
    /// The account's watch set as the wallet reported it. Its context binds
    /// every commit of the answer.
    pub(crate) watch: &'a TransparentAddressWatchSet<AccountUuid>,
    /// Cancellation, or the end of the account's time budget. A source stops
    /// at it, waits for any work it started, and returns
    /// [`SourceError::Cancelled`].
    pub(crate) should_exit: &'a (dyn Fn() -> bool + Sync),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum SourceError {
    /// No private source is configured or reachable. Nothing was sent.
    Unavailable,
    /// The call failed. Earlier commits stay durable; the account is retried
    /// in a later run. It carries no detail: a private source's errors can
    /// name addresses, outpoints, or pages, and must not reach logs.
    Failed,
    /// Cancellation stopped the call. Nothing it retrieved may be applied.
    Cancelled,
}

/// A private transparent recovery source that answers in batches.
///
/// Implementations must not fall back to a public source. They must honor
/// [`SourceRequest::should_exit`] and return only once any work they started
/// has stopped: the coordinator never abandons a call on cancellation. A
/// `Ready` batch stays settleable until the account's next pass.
pub(crate) trait RecoverySource {
    /// Whether every commit comes from an origin the wallet trusts, so that
    /// under `PrivateRequired` the coordinator qualifies its revisions.
    fn trusted(&self) -> bool;

    /// One pass over `request.account`. Only a `Ready` batch has commits; the
    /// source keeps them, opaque, until [`Self::apply`] settles the batch.
    fn recover(
        &self,
        request: SourceRequest<'_>,
    ) -> impl Future<Output = Result<PassReport, SourceError>> + Send;

    /// Settles `account`'s last `Ready` batch: applies its commits to `db` in
    /// order with `trust`, each in its own wallet transaction under the
    /// wallet write lock, stopping at the first the wallet refuses, then
    /// acknowledges the batch once every one committed. The transparent PIR
    /// source takes the lock for one commit at a time, so other wallet writes
    /// wait at most one commit, and stops between commits once `should_exit`
    /// holds ([`ApplyAction::Interrupted`]). Under [`Trust::Observed`] a batch
    /// resolving retired revisions is refused before anything applies. No
    /// network request is made. `Ok(None)` when no unsettled `Ready` batch is
    /// held for the account.
    fn apply(
        &self,
        account: AccountUuid,
        db: &mut WalletDatabase,
        trust: Trust,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> impl Future<Output = Result<Option<Applied>, ApplyFailure>> + Send;
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct RunStats {
    /// Accounts the run visited, not counting those it skipped without a
    /// source call.
    pub(crate) accounts: usize,
    /// Commits the library applied.
    pub(crate) commits: usize,
    /// Of those, commits whose revision was qualified as they applied.
    pub(crate) qualified: usize,
    /// Commits refused as stale and retried from a fresh watch set.
    pub(crate) stale_retries: usize,
    /// Candidate accounts promoted to private authority.
    pub(crate) promoted: usize,
    /// Accounts skipped without a source call because the service asked the
    /// wallet to wait (a lagging publication or a capacity refusal).
    pub(crate) waiting: usize,
    /// Quarantined accounts skipped.
    pub(crate) quarantined: usize,
    /// Held accounts skipped.
    pub(crate) held: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum RunOutcome {
    /// The captured or durable policy does not permit private recovery.
    /// Nothing was read from the source.
    NotEnabled,
    /// The source is unavailable. Nothing was committed after that.
    SourceUnavailable,
    /// Every account was visited, or the run budget ended the run.
    Finished(RunStats),
    /// Cancellation stopped the run. Applied commits stay durable.
    Exited,
}

/// Why an account is held out of recovery for [`HOLD`].
///
/// Holds live in memory only, so a restart retries a held account once. Only
/// the library's own decisions and promotion hold an account: a run that
/// stalls, however often, is asked again at the next block, so a reply that
/// failed never changes when the account is asked next.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum HoldCause {
    /// The source withdrew a publication it had answered from.
    Withdrawn(WithdrawnCause),
    /// A batch resolved retired revisions, but its commits did not go
    /// through the trusted operation, the only one that reconciles them.
    Unreconciled,
    /// Promotion found legacy public evidence the complete ledger cannot
    /// explain, which retrying does not change.
    LegacyDiscrepancy,
    /// A directory entry of the account failed on content three times, so the
    /// library no longer asks for it and the account cannot be covered.
    FailedEntries,
}

/// The cause of `account`'s hold in the wallet at `db_path`, while it lasts.
/// The balance read reports it as the account's stop reason.
pub(crate) fn recovery_hold(db_path: &str, account: AccountUuid) -> Option<HoldCause> {
    hold_at(db_path, account, Instant::now())
}

/// One account's hold, and the time before which the service asked the
/// wallet not to pass it again.
///
/// The wait lives in memory only, so a restart may pass the account sooner:
/// an app start is something the service sees anyway.
#[derive(Clone, Copy, Debug, Default)]
struct Hold {
    held: Option<(HoldCause, Instant)>,
    not_before: Option<Instant>,
}

/// Holds by wallet path and account.
static HOLDS: LazyLock<Mutex<HashMap<(String, AccountUuid), Hold>>> =
    LazyLock::new(Default::default);

/// Each wallet's rotating start among the accounts a run visits after the
/// active one.
static CURSORS: LazyLock<Mutex<HashMap<String, usize>>> = LazyLock::new(Default::default);

fn holds() -> MutexGuard<'static, HashMap<(String, AccountUuid), Hold>> {
    HOLDS.lock().unwrap_or_else(PoisonError::into_inner)
}

fn hold_at(db_path: &str, account: AccountUuid, now: Instant) -> Option<HoldCause> {
    holds()
        .get(&(db_path.to_owned(), account))
        .and_then(|hold| hold.held)
        .filter(|(_, until)| now < *until)
        .map(|(cause, _)| cause)
}

fn set_hold(db_path: &str, account: AccountUuid, cause: HoldCause, now: Instant) {
    holds()
        .entry((db_path.to_owned(), account))
        .or_default()
        .held = Some((cause, now + HOLD));
}

/// Skips `account` until `now + delay`, the delay the service named.
fn set_not_before(db_path: &str, account: AccountUuid, now: Instant, delay: Duration) {
    holds()
        .entry((db_path.to_owned(), account))
        .or_default()
        .not_before = Some(now + delay);
}

/// Whether the service asked the wallet not to pass `account` before a time
/// still to come.
fn waiting_at(db_path: &str, account: AccountUuid, now: Instant) -> bool {
    holds()
        .get(&(db_path.to_owned(), account))
        .and_then(|hold| hold.not_before)
        .is_some_and(|until| now < until)
}

/// Drops every hold and wait of the wallet at `db_path`: forgetting its
/// private ledger removes the evidence and companions they were held over, so
/// the next private run starts each account afresh. It also lets the next
/// sync run recovery at the current block.
pub(crate) fn clear_holds(db_path: &str) {
    holds().retain(|(path, _), _| path != db_path);
    clear_recovery_tip(db_path);
}

/// The chain tip of each wallet's last recovery run in this process.
static RECOVERY_TIPS: LazyLock<Mutex<HashMap<String, u64>>> = LazyLock::new(Default::default);

fn recovery_tips() -> MutexGuard<'static, HashMap<String, u64>> {
    RECOVERY_TIPS.lock().unwrap_or_else(PoisonError::into_inner)
}

/// A new block permits every account to run. At the same block, only an
/// expired service wait permits another pass; private content never creates
/// that deadline.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum RecoverySchedule {
    Block,
    ServiceWait,
}

pub(crate) fn recovery_schedule(db_path: &str, tip: u64) -> Option<RecoverySchedule> {
    if recovery_tips().get(db_path).is_none_or(|&last| tip > last) {
        Some(RecoverySchedule::Block)
    } else if service_retry_due(db_path) {
        Some(RecoverySchedule::ServiceWait)
    } else {
        None
    }
}

#[cfg(test)]
pub(crate) fn recovery_due(db_path: &str, tip: u64) -> bool {
    recovery_schedule(db_path, tip).is_some()
}

/// Whether a service deadline has expired for an account that is not held.
/// Read by the app's tip poll so catch-up does not need another block.
pub(crate) fn service_retry_due(db_path: &str) -> bool {
    let now = Instant::now();
    holds().iter().any(|((path, _), hold)| {
        path == db_path
            && hold.not_before.is_some_and(|until| now >= until)
            && hold.held.is_none_or(|(_, until)| now >= until)
    })
}

/// Takes an account's expired service deadline exactly once. Accounts with
/// no deadline must not gain a pass from another account's service retry.
fn take_service_retry(db_path: &str, account: AccountUuid, now: Instant) -> bool {
    let mut holds = holds();
    let Some(hold) = holds.get_mut(&(db_path.to_owned(), account)) else {
        return false;
    };
    if hold.not_before.is_some_and(|until| now >= until) {
        hold.not_before = None;
        true
    } else {
        false
    }
}

/// Records that the wallet at `db_path` ran recovery at chain tip `tip`.
pub(crate) fn recovery_ran(db_path: &str, tip: u64) {
    recovery_tips().insert(db_path.to_owned(), tip);
}

/// Lets the next sync of the wallet at `db_path` run recovery at the current
/// tip: a settings change is something the service sees anyway.
pub(crate) fn clear_recovery_tip(db_path: &str) {
    recovery_tips().remove(db_path);
}

/// The order a run visits `accounts` in: `first`, when it is one of them,
/// then the rest from the wallet's cursor. The cursor advances one account
/// per run, so a run its budget cuts short does not always leave out the same
/// accounts.
fn visiting_order(
    db_path: &str,
    accounts: Vec<AccountUuid>,
    first: Option<AccountUuid>,
) -> Vec<AccountUuid> {
    let first = first.filter(|first| accounts.contains(first));
    let mut rest: Vec<_> = accounts
        .into_iter()
        .filter(|account| Some(*account) != first)
        .collect();
    if !rest.is_empty() {
        let mut cursors = CURSORS.lock().unwrap_or_else(PoisonError::into_inner);
        let cursor = cursors.entry(db_path.to_owned()).or_default();
        let start = *cursor % rest.len();
        rest.rotate_left(start);
        *cursor = cursor.wrapping_add(1);
    }
    first.into_iter().chain(rest).collect()
}

enum AccountOutcome {
    /// The account's pass ended. Public service waits are recorded as soon
    /// as the source answers, independently of the content-aware plan.
    Done,
    /// A failure, a rejection, or a withdrawal ended the account's passes for
    /// this run; it is not offered for promotion.
    Skipped,
    Stop(RunOutcome),
}

/// Runs private recovery for every account under `policy`, then offers each
/// recovered candidate account for promotion.
///
/// Runs only when the captured mode is `PrivateRequired`. A `Public` durable
/// policy is first raised behind the policy fence, but only while [`may_raise`] holds for the wallet at
/// `db_path`: an unconfirmed preference or a concurrent toggle-off raises
/// nothing. `first`, the active account, is visited first. `clock` measures
/// the budgets and holds. Holds the wallet write lock for each commit of a
/// settlement, its acknowledgment, and each promotion, never across a source
/// call or a wait. A foreground wallet write, such as a send, waits for at
/// most one commit.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn run<S: RecoverySource>(
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    source: &S,
    first: Option<AccountUuid>,
    schedule: RecoverySchedule,
    clock: fn() -> Instant,
    should_exit: &(dyn Fn() -> bool + Sync),
) -> Result<RunOutcome, SyncError> {
    if policy.transparent_mode() == TransparentLedgerMode::Public {
        return Ok(RunOutcome::NotEnabled);
    }
    policy.configure_db(db);
    if policy.transparent_mode() == TransparentLedgerMode::PrivateRequired
        && raise_to_required(db, db_path, || may_raise(db_path, network)).await?
    {
        log::info!("transparent policy: applied PrivateRequired");
    }
    let durable = db.applied_transparent_policy().map_err(db_error)?.mode;
    if durable == TransparentLedgerMode::Public {
        return Ok(RunOutcome::NotEnabled);
    }
    let deadline = clock() + RUN_BUDGET;
    let accounts = db.get_account_ids().map_err(db_error)?;
    // Deleted accounts must not leave a deadline that restarts every poll.
    holds().retain(|(path, account), _| path != db_path || accounts.contains(account));
    let accounts = visiting_order(db_path, accounts, first);
    let mut run = Run {
        db,
        db_path,
        source,
        // Qualification needs `PrivateRequired` durably as well.
        qualify: source.trusted() && durable == TransparentLedgerMode::PrivateRequired,
        clock,
        should_exit,
        stats: RunStats::default(),
    };
    for account in accounts {
        if should_exit() {
            return Ok(RunOutcome::Exited);
        }
        let now = clock();
        if now >= deadline {
            log::info!("transparent ledger: run budget spent; other accounts wait for a later run");
            break;
        }
        let service_retry = take_service_retry(db_path, account, now);
        if run.skip(account, now)? {
            continue;
        }
        if schedule == RecoverySchedule::ServiceWait && !service_retry {
            continue;
        }
        match run
            .recover_account(account, (now + ACCOUNT_BUDGET).min(deadline))
            .await?
        {
            AccountOutcome::Done => {
                run.stats.accounts += 1;
                if run.promote(account)? {
                    run.stats.promoted += 1;
                }
            }
            AccountOutcome::Skipped => run.stats.accounts += 1,
            AccountOutcome::Stop(outcome) => {
                // Restore a consumed retry when cancellation interrupted it,
                // but keep any newer delay the source reported before settlement.
                if service_retry && matches!(outcome, RunOutcome::Exited) {
                    holds()
                        .entry((db_path.to_owned(), account))
                        .or_default()
                        .not_before
                        .get_or_insert_with(clock);
                }
                return Ok(outcome);
            }
        }
    }
    Ok(RunOutcome::Finished(run.stats))
}

/// One run's fixed inputs and running totals.
struct Run<'a, S> {
    db: &'a mut WalletDatabase,
    db_path: &'a str,
    source: &'a S,
    /// Commits are qualified as they are applied.
    qualify: bool,
    clock: fn() -> Instant,
    should_exit: &'a (dyn Fn() -> bool + Sync),
    stats: RunStats,
}

impl<S: RecoverySource> Run<'_, S> {
    /// Whether `account` is skipped in this run without a source call,
    /// counting why.
    fn skip(&mut self, account: AccountUuid, now: Instant) -> Result<bool, SyncError> {
        if let Some(cause) = hold_at(self.db_path, account, now) {
            log::info!("transparent ledger: skipping a held account ({cause:?})");
            self.stats.held += 1;
            return Ok(true);
        }
        if waiting_at(self.db_path, account, now) {
            self.stats.waiting += 1;
            return Ok(true);
        }
        // A quarantined account accepts no commit, so a pass would only cost
        // traffic. Only a private snapshot reports quarantine.
        if quarantined(self.db, account)? {
            self.stats.quarantined += 1;
            return Ok(true);
        }
        Ok(false)
    }

    /// Recovers `account` in one counted pass, retried from a fresh watch set
    /// only when its commits went stale, until `deadline`. The adapter's
    /// [`PassPlan`] names each next step; the coordinator holds the account
    /// and stops the run.
    async fn recover_account(
        &mut self,
        account: AccountUuid,
        deadline: Instant,
    ) -> Result<AccountOutcome, SyncError> {
        let Some(watch) = watch_set(self.db, account)? else {
            return Ok(AccountOutcome::Done);
        };
        let (clock, should_exit) = (self.clock, self.should_exit);
        let pass_exit = move || should_exit() || clock() >= deadline;
        let mut plan = PassPlan::new(watch, LIMITS);
        if let Step::Done(_) = plan.first() {
            return Ok(AccountOutcome::Done);
        }
        loop {
            if should_exit() {
                return Ok(AccountOutcome::Stop(RunOutcome::Exited));
            }
            // The plan keys its watch set by the PIR protocol's block hash;
            // sources take the wallet's, which has the same bytes.
            let watch = plan
                .watch()
                .clone()
                .map_block_hash(|hash| zcash_primitives::block::BlockHash(hash.0));
            let request = SourceRequest {
                account,
                watch: &watch,
                should_exit: &pass_exit,
            };
            let answer = tokio::time::timeout(PASS_BACKSTOP, self.source.recover(request)).await;
            // An answer that raced cancellation is discarded whole.
            if should_exit() {
                return Ok(AccountOutcome::Stop(RunOutcome::Exited));
            }
            let report = match answer {
                Ok(Ok(report)) => report,
                Ok(Err(SourceError::Unavailable)) => {
                    return Ok(AccountOutcome::Stop(RunOutcome::SourceUnavailable));
                }
                Ok(Err(SourceError::Failed)) => {
                    log::warn!("transparent ledger: source call failed");
                    return Ok(AccountOutcome::Skipped);
                }
                Ok(Err(SourceError::Cancelled)) => {
                    log::info!("transparent ledger: account budget spent");
                    return Ok(AccountOutcome::Done);
                }
                Err(_) => {
                    log::warn!("transparent ledger: source call passed its backstop");
                    return Ok(AccountOutcome::Skipped);
                }
            };
            // Content-aware `report.retry()` deliberately stalls failed
            // entries. It must not remove the publication/capacity wait the
            // service requested, including when settlement holds the account.
            if let Retry::After(delay) = report.progress.retry() {
                set_not_before(self.db_path, account, clock(), delay);
            }
            if report.state == BatchState::Pending {
                log::info!(
                    "transparent ledger: source batch pending ({:?})",
                    report.retry()
                );
            }
            let target = plan
                .watch()
                .target
                .map_or(0, |target| u32::from(target.height));
            // Settled whatever the pass reported: nothing is held unless it
            // was `Ready`.
            let settled = self.apply(account, &pass_exit).await;
            match &settled {
                Ok(Some(_)) => {
                    let behind = report.progress.behind(u64::from(target));
                    if behind > 0 {
                        log::info!("transparent ledger: publication {behind} blocks behind");
                    }
                }
                Err(failure) if failure.action() == ApplyAction::Refresh => {
                    self.stats.stale_retries += 1;
                }
                _ => {}
            }
            let Some(fresh) = watch_set(self.db, account)? else {
                return Ok(AccountOutcome::Done);
            };
            match plan.next(&report, &settled, fresh) {
                // Even a stale commit cannot bypass a public service wait.
                // A later run starts from the fresh watch set.
                Step::Pass | Step::Refresh => {
                    if matches!(report.progress.retry(), Retry::After(_)) {
                        return Ok(AccountOutcome::Done);
                    }
                }
                Step::Hold(cause) => {
                    let cause = match cause {
                        PlanHold::Withdrawn(cause) => {
                            log::warn!(
                                "transparent ledger: publication withdrawn ({cause:?}); \
                                 holding the account"
                            );
                            HoldCause::Withdrawn(cause)
                        }
                        // Only trusted commits withdraw the retired
                        // revisions' evidence, so nothing was applied or
                        // acknowledged, and the source reports them again.
                        PlanHold::Unreconciled => {
                            log::warn!(
                                "transparent ledger: retired revisions need trusted \
                                 reconciliation; holding the account"
                            );
                            HoldCause::Unreconciled
                        }
                        // Everything else the pass read settled; the entry is
                        // no longer asked for.
                        PlanHold::FailedEntries => {
                            log::warn!(
                                "transparent ledger: a directory entry failed three times; \
                                 holding the account"
                            );
                            HoldCause::FailedEntries
                        }
                    };
                    set_hold(self.db_path, account, cause, clock());
                    return Ok(AccountOutcome::Skipped);
                }
                // Logs carry the error's message, which names only its kind:
                // nested errors can quote wallet history.
                Step::Skip => {
                    match &settled {
                        // Stopped between commits: what applied stays, and
                        // the next pass replays the rest. Neither a hold nor
                        // a stall.
                        Err(failure) if failure.action() == ApplyAction::Interrupted => {
                            if should_exit() {
                                return Ok(AccountOutcome::Stop(RunOutcome::Exited));
                            }
                            log::info!(
                                "transparent ledger: account budget spent while settling; \
                                 the next run continues"
                            );
                        }
                        Ok(_) => log::warn!(
                            "transparent ledger: nothing to settle; skipping the account"
                        ),
                        Err(failure) if failure.action() == ApplyAction::Refresh => log::warn!(
                            "transparent ledger: commits stayed stale; retrying next run"
                        ),
                        Err(failure) => log::warn!(
                            "transparent ledger: {}; skipping the account",
                            failure.error
                        ),
                    }
                    return Ok(AccountOutcome::Skipped);
                }
                // The policy no longer permits this run's recovery, or
                // changed since it was captured: a later run decides afresh.
                Step::Stop(StopCause::NotEnabled | StopCause::PolicyChanged) => {
                    return Ok(AccountOutcome::Stop(RunOutcome::NotEnabled))
                }
                // Only a failed settlement fails.
                Step::Fail => {
                    return Err(SyncError::db(match settled {
                        Err(failure) => format!("transparent ledger: {}", failure.error),
                        Ok(_) => "transparent ledger: settlement failed".to_owned(),
                    }))
                }
                Step::Done(_) => return Ok(AccountOutcome::Done),
            }
        }
    }

    /// Has the source settle `account`'s `Ready` batch, trusted exactly when
    /// the run qualifies, until `should_exit` stops it between commits, and
    /// counts the commits that applied, the committed prefix of a refused or
    /// interrupted batch included.
    async fn apply(
        &mut self,
        account: AccountUuid,
        should_exit: &(dyn Fn() -> bool + Sync),
    ) -> Result<Option<Applied>, ApplyFailure> {
        let trust = if self.qualify {
            Trust::Trusted
        } else {
            Trust::Observed
        };
        let settled = self
            .source
            .apply(account, self.db, trust, should_exit)
            .await;
        let stats = match &settled {
            Ok(None) => return settled,
            Ok(Some(applied)) => applied.stats,
            Err(failure) => failure.stats,
        };
        self.stats.commits += stats.applied;
        self.stats.qualified += stats.qualified;
        settled
    }

    /// Offers a recovered candidate account for promotion. Returns whether it
    /// was promoted by this call. A blocked promotion changes nothing and is
    /// retried after a later run, except that legacy evidence the ledger
    /// cannot explain holds the account.
    fn promote(&mut self, account: AccountUuid) -> Result<bool, SyncError> {
        match watch_set(self.db, account)? {
            Some(watch) if watch.lifecycle == AccountLifecycle::Candidate => {}
            _ => return Ok(false),
        }
        let db = &mut *self.db;
        let promoted = with_wallet_db_write_lock("sync_engine.transparent_ledger.promote", || {
            db.activate_transparent_ledger(account)
        });
        match promoted {
            Ok(()) => Ok(true),
            // Blocker kinds name no address or outpoint.
            Err(SqliteClientError::TransparentActivationBlocked(blockers)) => {
                log::info!("transparent ledger: promotion blocked ({blockers:?})");
                if blockers.contains(&RecoveryBlocker::LegacyDiscrepancy) {
                    log::warn!(
                        "transparent ledger: legacy evidence disagrees; holding the account"
                    );
                    set_hold(
                        self.db_path,
                        account,
                        HoldCause::LegacyDiscrepancy,
                        (self.clock)(),
                    );
                }
                Ok(false)
            }
            Err(SqliteClientError::TransparentRecoveryNotEnabled)
            | Err(SqliteClientError::AccountUnknown) => Ok(false),
            Err(error) => Err(db_error(error)),
        }
    }
}

/// Whether `account` is quarantined, from its private snapshot.
fn quarantined(db: &WalletDatabase, account: AccountUuid) -> Result<bool, SyncError> {
    match db.transparent_ledger_snapshot(account, crate::wallet::confirmations_policy()) {
        Ok(snapshot) => Ok(snapshot
            .blockers
            .contains(&RecoveryBlocker::RecoverySuspended)),
        // Its first pass finds a deleted account gone.
        Err(SqliteClientError::AccountUnknown) => Ok(false),
        Err(error) => Err(db_error(error)),
    }
}

/// The account's watch set, or `None` once the account is gone.
fn watch_set(
    db: &WalletDatabase,
    account: AccountUuid,
) -> Result<Option<TransparentAddressWatchSet<AccountUuid>>, SyncError> {
    match db.transparent_watch_set(account) {
        Ok(watch) => Ok(Some(watch)),
        Err(SqliteClientError::AccountUnknown) => Ok(None),
        Err(error) => Err(db_error(error)),
    }
}

fn db_error(error: SqliteClientError) -> SyncError {
    SyncError::db(format!("transparent ledger: {error}"))
}
