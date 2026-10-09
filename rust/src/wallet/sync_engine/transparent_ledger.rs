//! Private transparent recovery and activation.
//!
//! After each completed sync, [`run`] asks a [`RecoverySource`] about each
//! account in passes, with no database lock held across a source call. A pass
//! answers with a [`SourceBatch`]. The source then settles a `Ready` batch
//! itself ([`RecoverySource::apply`]): its commits are applied in order, each
//! in its own library transaction, under the wallet write lock, and the batch
//! is acknowledged only once every one committed. A `Pending` or `Withdrawn`
//! batch applies nothing and is never acknowledged.
//!
//! Under `PrivateRequired`, a trusted source's commits are qualified as they
//! are applied ([`Trust::Trusted`]): the trusted-indexer decision, which is
//! what lets a recovered account be promoted. Commits of an untrusted source,
//! or under `PrivateShadow`, are only observed, and never qualify an account
//! for promotion.
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
//! rotating cursor. Each account gets at most [`MAX_PASSES_PER_ACCOUNT`]
//! passes and [`ACCOUNT_BUDGET`], the run at most [`RUN_BUDGET`], and waits
//! for a lagging publication or an overloaded service take at most
//! [`PUBLICATION_WAIT_CAP`] in all. An account that cannot progress is held
//! in memory for [`HOLD`] and skipped without traffic, as is a quarantined
//! account and, under `PrivateRequired`, a Ledger account.
//!
//! A default build captures `Public`, so [`run`] returns before any read or
//! request. With the development flag, private queries capture
//! `PrivateRequired`, and [`run`] first raises the wallet's durable policy
//! from a confirmed preference. The coordinator takes no lightwalletd client,
//! so it cannot make a public request.

use std::collections::HashMap;
use std::future::Future;
use std::sync::{LazyLock, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use zakura_pir_transparent::WithdrawnCause;
pub(crate) use zakura_pir_transparent::{ApplyStats, Trust};
use zcash_client_backend::data_api::{
    transparent_ledger::{
        AccountLifecycle, CommitRejection, RecoveryBlocker, TransparentLedgerMode,
        TransparentLedgerRead, TransparentLedgerWrite, TransparentWatchSet,
    },
    Account as _, WalletRead,
};
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};

use super::enhancement::{may_raise, EnhancementPolicy};
use super::{watch_for_exit, SyncError};
use crate::wallet::db::{with_wallet_db_write_lock, WalletDatabase};
use crate::wallet::keys::{self, HardwareSignerKind};
use crate::wallet::network::WalletNetwork;

#[cfg(test)]
pub(crate) mod fixture;
pub(crate) mod pir;
mod policy;
#[cfg(test)]
pub(crate) mod tests;

pub(crate) use pir::TransparentPirSource;
use policy::raise_to_required;
pub(crate) use policy::set_transparent_policy;

/// Answered passes per account in one run. Each pass after the first needs
/// new work: a grown window, a changed watch set, or a continuation that asks
/// for one.
const MAX_PASSES_PER_ACCOUNT: usize = 8;
/// Fresh watch sets tried for one account after stale commits.
const MAX_STALE_RETRIES: usize = 3;
/// Time one run may wait, in all, before asking a source again about a
/// publication that ends below the target or a service that refused for
/// capacity.
const PUBLICATION_WAIT_CAP: Duration = Duration::from_secs(90);
/// Time one account may take in a run, waits included.
const ACCOUNT_BUDGET: Duration = Duration::from_secs(120);
/// Time one run may take. Accounts it does not reach wait for a later run.
const RUN_BUDGET: Duration = Duration::from_secs(180);
/// Abandons a source call that ignores its exit signal. A transparent PIR
/// pass stops itself at [`pir::PASS_DEADLINE`], well before.
const PASS_BACKSTOP: Duration = Duration::from_secs(pir::PASS_DEADLINE.as_secs() + 30);
/// How long an account that cannot progress is skipped.
const HOLD: Duration = Duration::from_secs(60 * 60);
/// Stalled runs, since the account's last complete one, that hold it.
const STALL_RUNS_BEFORE_HOLD: usize = 3;

/// What a source is asked about one account.
#[derive(Clone, Copy)]
pub(crate) struct SourceRequest<'a> {
    pub(crate) account: AccountUuid,
    /// The account's watch set as the wallet reported it. Its context binds
    /// every commit of the answer.
    pub(crate) watch: &'a TransparentWatchSet<AccountUuid>,
    /// Cancellation, or the end of the account's time budget. A source stops
    /// at it, waits for any work it started, and returns
    /// [`SourceError::Cancelled`].
    pub(crate) should_exit: &'a (dyn Fn() -> bool + Sync),
}

/// When to ask a batch source about an account again.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Continuation {
    /// Every watched address is covered through the target.
    Complete,
    /// A pass budget stopped the source; the next pass resumes at once.
    More,
    /// The source cannot progress yet: its publication ends below the target,
    /// or its service refused for capacity. Ask again after the wait.
    RetryAfter(Duration),
    /// Progress needs more than a retry, such as an unknown block or spends
    /// the watch set cannot resolve.
    Stalled,
}

/// One pass of a batch source over one account.
///
/// Only a `Ready` batch has commits. The source keeps them, opaque, until
/// [`RecoverySource::apply`] settles the batch.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum SourceBatch {
    Ready {
        next: Continuation,
        /// Blocks between the watch set's target and the height the pass
        /// covered through.
        behind_by: u32,
    },
    /// The publication is behind what the source recorded. Apply nothing.
    Pending { next: Continuation },
    /// The publication contradicts what the source recorded. Apply nothing.
    Withdrawn(WithdrawnCause),
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

    /// One pass over `request.account`.
    fn recover(
        &self,
        request: SourceRequest<'_>,
    ) -> impl Future<Output = Result<SourceBatch, SourceError>> + Send;

    /// Settles `account`'s last `Ready` batch: applies its commits to `db` in
    /// order with `trust`, each in its own wallet transaction under the
    /// wallet write lock, stopping at the first the wallet refuses, then
    /// acknowledges the batch once every one committed. Under
    /// [`Trust::Observed`] a batch resolving retired revisions is refused
    /// before anything applies. No network request is made.
    fn apply(
        &self,
        account: AccountUuid,
        db: &mut WalletDatabase,
        trust: Trust,
    ) -> impl Future<Output = Settlement> + Send;
}

/// How a source settled a `Ready` batch.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Settlement {
    /// Every commit applied and the batch was acknowledged.
    Acknowledged(ApplyStats),
    /// The batch was not acknowledged. `stats` is the committed prefix, which
    /// stays applied; the next pass replays the batch.
    Refused { stats: ApplyStats, refusal: Refusal },
    /// The wallet failed. The message names no address or outpoint.
    Failed { stats: ApplyStats, error: String },
}

/// Why a source refused to settle a batch, as the coordinator acts on it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Refusal {
    /// A commit was stale or the policy changed: retry from a fresh watch set.
    Stale,
    /// The batch resolves retired revisions and the commits were only
    /// observed: hold the account until a trusted run reconciles them.
    Unreconciled,
    /// The account cannot progress in this run: an integrity, malformed or
    /// refused commit, a failed acknowledgment, or no batch to settle.
    Skip,
    /// The handle or the durable policy does not permit private recovery.
    NotEnabled,
}

impl Settlement {
    fn stats(&self) -> ApplyStats {
        match self {
            Settlement::Acknowledged(stats)
            | Settlement::Refused { stats, .. }
            | Settlement::Failed { stats, .. } => *stats,
        }
    }
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
    /// Time spent waiting for a lagging publication or an overloaded service.
    pub(crate) publication_wait: Duration,
    /// Ledger accounts skipped under `PrivateRequired`.
    pub(crate) paused_ledger: usize,
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
/// Holds live in memory only, so a restart retries a held account once.
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
    /// [`STALL_RUNS_BEFORE_HOLD`] runs ended stalled since the account's last
    /// complete one.
    Stalled,
}

/// The cause of `account`'s hold in the wallet at `db_path`, while it lasts.
/// The balance read reports it as the account's stop reason.
pub(crate) fn recovery_hold(db_path: &str, account: AccountUuid) -> Option<HoldCause> {
    hold_at(db_path, account, Instant::now())
}

/// One account's hold and its count of stalled runs since its last complete
/// one.
#[derive(Clone, Copy, Debug, Default)]
struct Hold {
    held: Option<(HoldCause, Instant)>,
    stalled_runs: usize,
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

/// Counts a run whose passes ended stalled. Only a complete run clears the
/// count, so a stall that persists while other runs end waiting for a lagging
/// publication is still held. The [`STALL_RUNS_BEFORE_HOLD`]th holds the
/// account and restarts the count. Returns whether it held the account.
fn record_stall(db_path: &str, account: AccountUuid, now: Instant) -> bool {
    let mut holds = holds();
    let hold = holds.entry((db_path.to_owned(), account)).or_default();
    hold.stalled_runs += 1;
    if hold.stalled_runs < STALL_RUNS_BEFORE_HOLD {
        return false;
    }
    hold.stalled_runs = 0;
    hold.held = Some((HoldCause::Stalled, now + HOLD));
    true
}

fn clear_stalls(db_path: &str, account: AccountUuid) {
    if let Some(hold) = holds().get_mut(&(db_path.to_owned(), account)) {
        hold.stalled_runs = 0;
    }
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
    /// The account's passes ended. Carries the final pass's continuation,
    /// absent when no pass answered: the chain is unknown, the account is
    /// gone, or its budget ran out.
    Done(Option<Continuation>),
    /// A failure, a rejection, or a withdrawal ended the account's passes for
    /// this run; it is not offered for promotion.
    Skipped,
    Stop(RunOutcome),
}

/// Runs private recovery for every account under `policy`, then, under
/// `PrivateRequired`, offers each recovered candidate account for promotion.
///
/// Runs only when both the captured mode and the wallet's durable policy
/// permit private recovery (`PrivateShadow` or `PrivateRequired`). Under a
/// captured `PrivateRequired`, a weaker durable policy is first raised behind
/// the policy fence, but only while [`may_raise`] holds for the wallet at
/// `db_path`: an unconfirmed preference or a concurrent toggle-off raises
/// nothing. `first`, the active account, is visited first. `clock` measures
/// the budgets and holds. Holds the wallet write lock only for each commit or
/// promotion, never across a source call or a wait.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn run<S: RecoverySource>(
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    policy: EnhancementPolicy,
    source: &S,
    first: Option<AccountUuid>,
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
    // The handle has adopted a durable `PrivateRequired` even under a weaker
    // captured mode.
    let required =
        db.transparent_ledger_mode().map_err(db_error)? == TransparentLedgerMode::PrivateRequired;
    let deadline = clock() + RUN_BUDGET;
    let accounts = visiting_order(db_path, db.get_account_ids().map_err(db_error)?, first);
    let mut run = Run {
        db,
        db_path,
        source,
        required,
        // Qualification needs `PrivateRequired` durably as well.
        qualify: source.trusted() && required && durable == TransparentLedgerMode::PrivateRequired,
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
        if run.skip(account, now)? {
            continue;
        }
        match run
            .recover_account(account, (now + ACCOUNT_BUDGET).min(deadline))
            .await?
        {
            AccountOutcome::Done(last) => {
                run.stats.accounts += 1;
                match last {
                    Some(Continuation::Stalled) => {
                        if record_stall(db_path, account, clock()) {
                            log::warn!(
                                "transparent ledger: recovery keeps stalling; holding the account"
                            );
                        }
                    }
                    Some(Continuation::Complete) => clear_stalls(db_path, account),
                    _ => {}
                }
                if required && run.promote(account)? {
                    run.stats.promoted += 1;
                }
            }
            AccountOutcome::Skipped => run.stats.accounts += 1,
            AccountOutcome::Stop(outcome) => return Ok(outcome),
        }
    }
    if run.stats.publication_wait > Duration::ZERO {
        log::info!(
            "transparent ledger: waited {}s for the publication",
            run.stats.publication_wait.as_secs()
        );
    }
    Ok(RunOutcome::Finished(run.stats))
}

/// One run's fixed inputs and running totals.
struct Run<'a, S> {
    db: &'a mut WalletDatabase,
    db_path: &'a str,
    source: &'a S,
    /// The handle is `PrivateRequired`: Ledger and quarantined accounts are
    /// skipped, and recovered candidates are offered for promotion.
    required: bool,
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
        // Recovery from the birthday would miss a Ledger account's earlier
        // history, and its public discovery is withheld.
        if self.required && is_ledger(self.db, account)? {
            self.stats.paused_ledger += 1;
            return Ok(true);
        }
        if let Some(cause) = hold_at(self.db_path, account, now) {
            log::info!("transparent ledger: skipping a held account ({cause:?})");
            self.stats.held += 1;
            return Ok(true);
        }
        // A quarantined account accepts no commit, so a pass would only cost
        // traffic. Only a private snapshot reports quarantine.
        if self.required && quarantined(self.db, account)? {
            self.stats.quarantined += 1;
            return Ok(true);
        }
        Ok(false)
    }

    /// Recovers `account` in passes until its source and watch set settle, or
    /// until `deadline`.
    async fn recover_account(
        &mut self,
        account: AccountUuid,
        deadline: Instant,
    ) -> Result<AccountOutcome, SyncError> {
        let Some(mut watch) = watch_set(self.db, account)? else {
            return Ok(AccountOutcome::Done(None));
        };
        let (clock, should_exit) = (self.clock, self.should_exit);
        let pass_exit = move || should_exit() || clock() >= deadline;
        let mut passes = 0;
        let mut stale = 0;
        loop {
            if should_exit() {
                return Ok(AccountOutcome::Stop(RunOutcome::Exited));
            }
            if watch.context().is_none() {
                return Ok(AccountOutcome::Done(None));
            }
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
            let batch = match answer {
                Ok(Ok(batch)) => batch,
                Ok(Err(SourceError::Unavailable)) => {
                    return Ok(AccountOutcome::Stop(RunOutcome::SourceUnavailable));
                }
                Ok(Err(SourceError::Failed)) => {
                    log::warn!("transparent ledger: source call failed");
                    return Ok(AccountOutcome::Skipped);
                }
                Ok(Err(SourceError::Cancelled)) => {
                    log::info!("transparent ledger: account budget spent");
                    return Ok(AccountOutcome::Done(None));
                }
                Err(_) => {
                    log::warn!("transparent ledger: source call passed its backstop");
                    return Ok(AccountOutcome::Skipped);
                }
            };
            let (next, window_grew) = match batch {
                SourceBatch::Withdrawn(cause) => {
                    log::warn!(
                        "transparent ledger: publication withdrawn ({cause:?}); holding the account"
                    );
                    set_hold(self.db_path, account, HoldCause::Withdrawn(cause), clock());
                    return Ok(AccountOutcome::Skipped);
                }
                SourceBatch::Pending { next } => {
                    log::info!("transparent ledger: source batch pending ({next:?})");
                    (next, false)
                }
                SourceBatch::Ready { next, behind_by } => {
                    let window_grew = match self.apply(account).await? {
                        Settlement::Acknowledged(stats) => stats.window_grew,
                        Settlement::Refused {
                            refusal: Refusal::Stale,
                            ..
                        } => {
                            self.stats.stale_retries += 1;
                            stale += 1;
                            if stale > MAX_STALE_RETRIES {
                                log::warn!(
                                    "transparent ledger: commits stayed stale; retrying next run"
                                );
                                return Ok(AccountOutcome::Skipped);
                            }
                            if !durably_permitted(self.db)? {
                                return Ok(AccountOutcome::Stop(RunOutcome::NotEnabled));
                            }
                            let Some(fresh) = watch_set(self.db, account)? else {
                                return Ok(AccountOutcome::Done(None));
                            };
                            watch = fresh;
                            continue;
                        }
                        // Only trusted commits withdraw the retired
                        // revisions' evidence, so nothing was applied or
                        // acknowledged, and the source reports them again.
                        Settlement::Refused {
                            refusal: Refusal::Unreconciled,
                            ..
                        } => {
                            log::warn!(
                                "transparent ledger: retired revisions need trusted \
                                 reconciliation; holding the account"
                            );
                            set_hold(self.db_path, account, HoldCause::Unreconciled, clock());
                            return Ok(AccountOutcome::Skipped);
                        }
                        Settlement::Refused {
                            refusal: Refusal::Skip,
                            ..
                        } => return Ok(AccountOutcome::Skipped),
                        Settlement::Refused {
                            refusal: Refusal::NotEnabled,
                            ..
                        } => return Ok(AccountOutcome::Stop(RunOutcome::NotEnabled)),
                        Settlement::Failed { error, .. } => {
                            return Err(SyncError::db(format!("transparent ledger: {error}")))
                        }
                    };
                    if behind_by > 0 {
                        log::info!("transparent ledger: publication {behind_by} blocks behind");
                    }
                    (next, window_grew)
                }
            };
            passes += 1;
            let Some(fresh) = watch_set(self.db, account)? else {
                return Ok(AccountOutcome::Done(None));
            };
            let changed = window_grew || fresh.addresses != watch.addresses;
            watch = fresh;
            if passes >= MAX_PASSES_PER_ACCOUNT {
                return Ok(AccountOutcome::Done(Some(next)));
            }
            match next {
                Continuation::More => {}
                Continuation::RetryAfter(wait) => match self.wait(wait, deadline).await {
                    None => return Ok(AccountOutcome::Stop(RunOutcome::Exited)),
                    Some(false) => return Ok(AccountOutcome::Done(Some(next))),
                    Some(true) => {}
                },
                Continuation::Complete | Continuation::Stalled if changed => {}
                Continuation::Complete | Continuation::Stalled => {
                    return Ok(AccountOutcome::Done(Some(next)));
                }
            }
        }
    }

    /// Has the source settle `account`'s `Ready` batch, trusted exactly when
    /// the run qualifies, and counts the commits that applied, the committed
    /// prefix of a refused batch included.
    async fn apply(&mut self, account: AccountUuid) -> Result<Settlement, SyncError> {
        let trust = if self.qualify {
            Trust::Trusted
        } else {
            Trust::Observed
        };
        let settled = self.source.apply(account, self.db, trust).await;
        let stats = settled.stats();
        self.stats.commits += stats.applied;
        self.stats.qualified += stats.qualified;
        Ok(settled)
    }

    /// Waits `wait` before the account's next pass, if the run's wait cap and
    /// the account's `deadline` allow it. Returns whether it waited, or `None`
    /// when cancellation interrupted the wait.
    async fn wait(&mut self, wait: Duration, deadline: Instant) -> Option<bool> {
        if self.stats.publication_wait + wait > PUBLICATION_WAIT_CAP
            || (self.clock)() + wait >= deadline
        {
            return Some(false);
        }
        let should_exit = self.should_exit;
        tokio::select! {
            biased;
            _ = watch_for_exit(&should_exit) => return None,
            _ = tokio::time::sleep(wait) => {}
        }
        self.stats.publication_wait += wait;
        Some(true)
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
            db.promote_transparent_account(account)
        });
        match promoted {
            Ok(()) => Ok(true),
            // Blocker kinds name no address or outpoint.
            Err(SqliteClientError::TransparentPromotionBlocked(blockers)) => {
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

/// How a run continues after the library refused a commit, for a source that
/// applies commits itself. Rejections are logged without their payloads,
/// which name addresses and outpoints. Any other error is a wallet failure.
pub(crate) fn refusal(error: &SqliteClientError) -> Option<Refusal> {
    Some(match error {
        SqliteClientError::TransparentLedgerCommitRejected(rejection) => {
            return Some(commit_refusal(rejection))
        }
        SqliteClientError::StaleTransparentPolicy { .. } => Refusal::Stale,
        SqliteClientError::TransparentRecoveryNotEnabled => Refusal::NotEnabled,
        _ => return None,
    })
}

/// How a run continues after the library rejected a commit.
pub(crate) fn commit_refusal(rejection: &CommitRejection) -> Refusal {
    match rejection {
        CommitRejection::Stale(_) => Refusal::Stale,
        CommitRejection::Integrity(_) => {
            log::warn!(
                "transparent ledger: source contradicted stored evidence; skipping the account"
            );
            Refusal::Skip
        }
        CommitRejection::Invalid(_) => {
            log::error!(
                "transparent ledger: source produced a malformed commit; skipping the account"
            );
            Refusal::Skip
        }
        CommitRejection::Refused(refused) => {
            log::warn!("transparent ledger: commit refused ({refused:?}); skipping the account");
            Refusal::Skip
        }
    }
}

/// Whether the wallet's durable policy permits private recovery. The handle's
/// own mode is checked by the caller and again by the library at commit.
fn durably_permitted(db: &WalletDatabase) -> Result<bool, SyncError> {
    let applied = db.applied_transparent_policy().map_err(db_error)?;
    Ok(applied.mode != TransparentLedgerMode::Public)
}

/// Whether `account` is a Ledger account.
fn is_ledger(db: &WalletDatabase, account: AccountUuid) -> Result<bool, SyncError> {
    Ok(db
        .get_account(account)
        .map_err(db_error)?
        .is_some_and(|account| {
            keys::hardware_signer_kind(account.source()) == Some(HardwareSignerKind::Ledger)
        }))
}

/// Whether `account` is quarantined, from its private snapshot.
fn quarantined(db: &WalletDatabase, account: AccountUuid) -> Result<bool, SyncError> {
    match db.transparent_ledger_snapshot(account, crate::wallet::confirmations_policy()) {
        Ok(snapshot) => Ok(snapshot.blockers.contains(&RecoveryBlocker::Quarantined)),
        // Its first pass finds a deleted account gone.
        Err(SqliteClientError::AccountUnknown) => Ok(false),
        Err(error) => Err(db_error(error)),
    }
}

/// The account's watch set, or `None` once the account is gone.
fn watch_set(
    db: &WalletDatabase,
    account: AccountUuid,
) -> Result<Option<TransparentWatchSet<AccountUuid>>, SyncError> {
    match db.transparent_watch_set(account) {
        Ok(watch) => Ok(Some(watch)),
        Err(SqliteClientError::AccountUnknown) => Ok(None),
        Err(error) => Err(db_error(error)),
    }
}

fn db_error(error: SqliteClientError) -> SyncError {
    SyncError::db(format!("transparent ledger: {error}"))
}
