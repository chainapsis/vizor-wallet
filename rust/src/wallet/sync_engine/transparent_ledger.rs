//! Private transparent recovery and activation (Phases 3–4 of the transparent
//! PIR ledger).
//!
//! For each account the coordinator captures the library's watch set, asks a
//! [`RecoverySource`] about the watched addresses with no database lock held,
//! and submits the answer as one `apply_transparent_ledger_commit` per pass.
//! It repeats at the same target while the address window grows, the watch
//! set changes, or open pages make progress.
//!
//! A candidate account's state lives only in the library's `tpir_*` tables.
//! It never changes balances, input selection, locks, address allocation, or
//! history, and it shares no checkpoint, queue, retry, or cache with shielded
//! scanning, public UTXO refresh, or the `.receive.redb` receive cache. Neither
//! of those becomes private evidence.
//!
//! Under `PrivateRequired`, each candidate account is then offered for
//! promotion on its own. The library rechecks everything and refuses while
//! any blocker remains, including an unqualified revision; nothing in this
//! build can qualify one, so production never promotes. An active account's
//! later commits project into the wallet in the same transaction.
//!
//! Production has no private source: it captures `Public` and passes
//! [`DisabledSource`], so [`run`] returns before any read or request. The
//! coordinator takes no lightwalletd client, so it cannot make a public
//! request.

use std::future::Future;
use std::time::Duration;

use zcash_client_backend::data_api::{
    transparent_ledger::{
        AccountLifecycle, AddressRange, ChainPoint, CommitRejection, PageRequest, PendingPage,
        ReceiveEvent, RecoveryRevision, RefusedCommit, SpendEvent, TransparentLedgerCommit,
        TransparentLedgerMode, TransparentLedgerRead, TransparentLedgerWrite, TransparentWatchSet,
        WatchedAddress,
    },
    WalletRead,
};
use zcash_client_sqlite::{error::SqliteClientError, AccountUuid};

use super::enhancement::EnhancementPolicy;
use super::{watch_for_exit, SyncError};
use crate::wallet::db::{with_wallet_db_write_lock, WalletDatabase};

#[cfg(test)]
pub(crate) mod fixture;
#[cfg(test)]
mod tests;

/// Passes per account in one run. Each pass after the first needs new work:
/// a grown window, a changed watch set, or progress on open pages.
const MAX_PASSES_PER_ACCOUNT: usize = 8;
/// Fresh watch sets tried for one account after stale commits.
const MAX_STALE_RETRIES: usize = 3;

/// Limits for one source call. A source stops within them and leaves the rest
/// as open pages or for the next pass.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct SourceBounds {
    /// Queries the source may issue.
    pub(crate) max_queries: usize,
    /// Response bytes the source may accept.
    pub(crate) max_bytes: usize,
    /// Pages the source may open or complete.
    pub(crate) max_pages: usize,
    /// Wall-clock limit on the call. The coordinator abandons a call that
    /// exceeds it and commits nothing from it.
    pub(crate) timeout: Duration,
}

pub(crate) const PASS_BOUNDS: SourceBounds = SourceBounds {
    max_queries: 64,
    max_bytes: 4 << 20,
    max_pages: 16,
    timeout: Duration::from_secs(60),
};

/// What a source is asked about one account, from one watch set.
// Production has only `DisabledSource`, which reads none of it.
#[cfg_attr(not(test), allow(dead_code))]
#[derive(Clone, Copy, Debug)]
pub(crate) struct SourceRequest<'a> {
    /// The local block the answer may not extend past.
    pub(crate) target: ChainPoint,
    /// Every address to cover, each from its `required_from`.
    pub(crate) addresses: &'a [WatchedAddress],
    /// Pages earlier passes left open, to resume.
    pub(crate) pending_pages: &'a [PendingPage],
    pub(crate) bounds: SourceBounds,
}

/// A source's normalized answer: one revision's facts, anchored to a local
/// block it verified the revision agrees with.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SourceResult {
    pub(crate) revision: RecoveryRevision,
    pub(crate) anchor: ChainPoint,
    pub(crate) receives: Vec<ReceiveEvent>,
    pub(crate) spends: Vec<SpendEvent>,
    /// Checked ranges, including ranges with no events.
    pub(crate) coverage: Vec<AddressRange>,
    /// Ranges the source cannot check.
    pub(crate) unsupported: Vec<AddressRange>,
    pub(crate) opened_pages: Vec<PageRequest>,
    pub(crate) completed_pages: Vec<Vec<u8>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum SourceError {
    /// No private source is configured or reachable. Nothing was sent.
    Unavailable,
    /// The call failed. Earlier commits stay durable; the account is retried
    /// in a later run. It carries no detail: a private source's errors can
    /// name addresses, outpoints, or pages, and must not reach logs.
    #[cfg_attr(not(test), allow(dead_code))]
    Failed,
}

/// A private transparent recovery source. Implementations must not fall back
/// to a public source.
pub(crate) trait RecoverySource {
    fn recover(
        &self,
        request: SourceRequest<'_>,
    ) -> impl Future<Output = Result<SourceResult, SourceError>> + Send;
}

/// The production source until a private one exists: always unavailable.
pub(crate) struct DisabledSource;

impl RecoverySource for DisabledSource {
    fn recover(
        &self,
        _request: SourceRequest<'_>,
    ) -> impl Future<Output = Result<SourceResult, SourceError>> + Send {
        std::future::ready(Err(SourceError::Unavailable))
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct RunStats {
    /// Accounts processed to the end of their passes.
    pub(crate) accounts: usize,
    /// Commits the library applied.
    pub(crate) commits: usize,
    /// Commits refused as stale and retried from a fresh watch set.
    pub(crate) stale_retries: usize,
    /// Candidate accounts promoted to private authority.
    pub(crate) promoted: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum RunOutcome {
    /// The captured or durable policy does not permit private recovery.
    /// Nothing was read from the source.
    NotEnabled,
    /// The source is unavailable. Nothing was committed after that.
    SourceUnavailable,
    /// Every account was processed.
    Finished(RunStats),
    /// Cancellation or a mode change stopped the run. Applied commits stay
    /// durable.
    Exited,
    /// The source contradicted stored evidence. Its session is no longer
    /// trusted, so the rest of the run was abandoned.
    Untrusted,
}

enum AccountOutcome {
    /// Recovery reached the end of its passes; the account may be promoted.
    Done,
    /// The account was skipped for this run; it is not offered for promotion.
    Skipped,
    Stop(RunOutcome),
}

/// Runs private recovery for every account under `policy`, then, under
/// `PrivateRequired`, offers each recovered candidate account for promotion.
///
/// Runs only when both the captured mode and the wallet's durable policy
/// permit private recovery (`PrivateShadow` or `PrivateRequired`). Holds the
/// wallet write lock only for each commit or promotion, never across a source
/// call.
pub(crate) async fn run<S: RecoverySource>(
    db: &mut WalletDatabase,
    policy: EnhancementPolicy,
    source: &S,
    should_exit: &impl Fn() -> bool,
) -> Result<RunOutcome, SyncError> {
    if policy.transparent_mode() == TransparentLedgerMode::Public {
        return Ok(RunOutcome::NotEnabled);
    }
    policy.configure_db(db);
    if !durably_permitted(db)? {
        return Ok(RunOutcome::NotEnabled);
    }
    let mut stats = RunStats::default();
    for account in db.get_account_ids().map_err(db_error)? {
        match recover_account(db, source, account, should_exit, &mut stats).await? {
            AccountOutcome::Done => {
                stats.accounts += 1;
                if policy.transparent_mode() == TransparentLedgerMode::PrivateRequired
                    && promote(db, account)?
                {
                    stats.promoted += 1;
                }
            }
            AccountOutcome::Skipped => stats.accounts += 1,
            AccountOutcome::Stop(outcome) => return Ok(outcome),
        }
    }
    Ok(RunOutcome::Finished(stats))
}

async fn recover_account<S: RecoverySource>(
    db: &mut WalletDatabase,
    source: &S,
    account: AccountUuid,
    should_exit: &impl Fn() -> bool,
    stats: &mut RunStats,
) -> Result<AccountOutcome, SyncError> {
    let Some(mut watch) = watch_set(db, account)? else {
        return Ok(AccountOutcome::Done);
    };
    let mut passes = 0;
    let mut stale = 0;
    loop {
        if should_exit() {
            return Ok(AccountOutcome::Stop(RunOutcome::Exited));
        }
        let Some(context) = watch.context() else {
            return Ok(AccountOutcome::Done);
        };
        let request = SourceRequest {
            target: context.target,
            addresses: &watch.addresses,
            pending_pages: &watch.pending_pages,
            bounds: PASS_BOUNDS,
        };
        let answer = tokio::select! {
            biased;
            _ = watch_for_exit(should_exit) => {
                return Ok(AccountOutcome::Stop(RunOutcome::Exited));
            }
            answer = tokio::time::timeout(PASS_BOUNDS.timeout, source.recover(request)) => answer,
        };
        let result = match answer {
            Ok(Ok(result)) => result,
            Ok(Err(SourceError::Unavailable)) => {
                return Ok(AccountOutcome::Stop(RunOutcome::SourceUnavailable));
            }
            Ok(Err(SourceError::Failed)) => {
                log::warn!("transparent ledger: source call failed");
                return Ok(AccountOutcome::Skipped);
            }
            Err(_) => {
                log::warn!("transparent ledger: source call timed out");
                return Ok(AccountOutcome::Skipped);
            }
        };
        if should_exit() {
            return Ok(AccountOutcome::Stop(RunOutcome::Exited));
        }
        let commit = TransparentLedgerCommit {
            context,
            revision: result.revision,
            anchor: result.anchor,
            receives: result.receives,
            spends: result.spends,
            coverage: result.coverage,
            unsupported: result.unsupported,
            opened_pages: result.opened_pages,
            completed_pages: result.completed_pages,
        };
        let applied = with_wallet_db_write_lock("sync_engine.transparent_ledger.commit", || {
            db.apply_transparent_ledger_commit(commit)
        });
        // Rejections are logged without their payloads, which name addresses
        // and outpoints.
        match applied {
            Ok(outcome) => {
                stats.commits += 1;
                passes += 1;
                let Some(fresh) = watch_set(db, account)? else {
                    return Ok(AccountOutcome::Done);
                };
                let more = outcome.window_grew
                    || fresh.addresses != watch.addresses
                    || (!fresh.pending_pages.is_empty()
                        && fresh.pending_pages != watch.pending_pages);
                watch = fresh;
                if !more || passes >= MAX_PASSES_PER_ACCOUNT {
                    return Ok(AccountOutcome::Done);
                }
            }
            Err(SqliteClientError::TransparentLedgerCommitRejected(CommitRejection::Stale(_)))
            | Err(SqliteClientError::StaleTransparentPolicy { .. }) => {
                stats.stale_retries += 1;
                stale += 1;
                if stale > MAX_STALE_RETRIES {
                    log::warn!("transparent ledger: commits stayed stale; retrying next run");
                    return Ok(AccountOutcome::Skipped);
                }
                if !durably_permitted(db)? {
                    return Ok(AccountOutcome::Stop(RunOutcome::NotEnabled));
                }
                let Some(fresh) = watch_set(db, account)? else {
                    return Ok(AccountOutcome::Done);
                };
                watch = fresh;
            }
            Err(SqliteClientError::TransparentLedgerCommitRejected(
                CommitRejection::Integrity(_),
            )) => {
                log::warn!("transparent ledger: source contradicted stored evidence; stopping");
                return Ok(AccountOutcome::Stop(RunOutcome::Untrusted));
            }
            Err(SqliteClientError::TransparentLedgerCommitRejected(CommitRejection::Invalid(
                _,
            ))) => {
                log::error!("transparent ledger: source produced a malformed commit");
                return Ok(AccountOutcome::Skipped);
            }
            Err(SqliteClientError::TransparentLedgerCommitRejected(CommitRejection::Refused(
                refused,
            ))) => {
                return Ok(match refused {
                    // An earlier integrity failure ended trust in this source.
                    RefusedCommit::SourceQuarantined => {
                        log::warn!("transparent ledger: source is quarantined; stopping");
                        AccountOutcome::Stop(RunOutcome::Untrusted)
                    }
                    RefusedCommit::AccountQuarantined => {
                        log::warn!("transparent ledger: account is quarantined; skipping");
                        AccountOutcome::Skipped
                    }
                    RefusedCommit::UnqualifiedRevision => {
                        log::warn!(
                            "transparent ledger: source is not qualified for an active account"
                        );
                        AccountOutcome::Skipped
                    }
                });
            }
            Err(SqliteClientError::TransparentRecoveryNotEnabled) => {
                return Ok(AccountOutcome::Stop(RunOutcome::NotEnabled));
            }
            Err(error) => return Err(db_error(error)),
        }
    }
}

/// Offers a recovered candidate account for promotion. Returns whether it was
/// promoted by this call; a blocked promotion changes nothing and is retried
/// after a later run.
fn promote(db: &mut WalletDatabase, account: AccountUuid) -> Result<bool, SyncError> {
    match watch_set(db, account)? {
        Some(watch) if watch.lifecycle == AccountLifecycle::Candidate => {}
        _ => return Ok(false),
    }
    let promoted = with_wallet_db_write_lock("sync_engine.transparent_ledger.promote", || {
        db.promote_transparent_account(account)
    });
    match promoted {
        Ok(()) => Ok(true),
        // Blockers name no address or outpoint; their count is enough to log.
        Err(SqliteClientError::TransparentPromotionBlocked(blockers)) => {
            log::info!(
                "transparent ledger: promotion blocked ({} reasons)",
                blockers.len()
            );
            Ok(false)
        }
        Err(SqliteClientError::TransparentRecoveryNotEnabled)
        | Err(SqliteClientError::AccountUnknown) => Ok(false),
        Err(error) => Err(db_error(error)),
    }
}

/// Whether the wallet's durable policy permits private recovery. The handle's
/// own mode is checked by the caller and again by the library at commit.
fn durably_permitted(db: &WalletDatabase) -> Result<bool, SyncError> {
    let applied = db.applied_transparent_policy().map_err(db_error)?;
    Ok(applied.mode != TransparentLedgerMode::Public)
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
