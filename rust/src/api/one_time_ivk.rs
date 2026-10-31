//! Private NEAR swap addresses over the wallet's one-time IVKs: reservations, quote
//! records, provider statuses and swap history checks. Provider polling stays in Dart.
//! Allocation is durable in Rust.
use super::sync::parse_network_and_migrate;
use crate::wallet::db::open_existing_wallet_db_with_timeout;
use crate::wallet::one_time_ivk::{self, with_db};
use crate::wallet::sync_engine::{RecoveryError, Wait};
use crate::wallet::{db::WALLET_DB_BUSY_TIMEOUT, keys, network::WalletNetwork};
use zakura_near_intents::{near_observation, NearStatus};
use zakura_one_time_ivk::{
    swap::{Observation, OperationStatus, ReceiptExpectation},
    Purpose,
};
use zcash_client_sqlite::{
    error::SqliteClientError,
    wallet::one_time_ivk::swap::{OperationOutcome, ReservationPolicy},
};
use zcash_keys::address::{Address, UnifiedAddress};
use zcash_protocol::consensus::BlockHeight;

/// Why a private swap call failed, for the app to act on.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReceiveErrorKind {
    /// Any failure the app only shows.
    Other,
    /// The reservation expired or was retired. Prepare a new address.
    Stale,
    /// Unresolved quotes hold every eligible receive address. Refresh their provider
    /// statuses, which can release expired ones, then ask again.
    Limit,
    /// The next receive address's history is still being checked, or filters haven't
    /// been read near the chain tip. Run recovery, then ask again.
    ReceiveHistory,
    /// The receiver service needs a newer app. Pending recovery work is kept.
    UpgradeRequired,
    /// A swap history check cannot start until wallet sync catches up with the
    /// receiver service. Ask again shortly.
    WaitingForSync,
    /// A swap history check cannot start until the receiver service publishes past this
    /// wallet's birthday. Ask again shortly.
    WaitingForService,
}

/// A private swap failure. `message` is display text, never a parsing protocol. `kind`
/// says what the app should do about it.
#[derive(Clone, Debug)]
pub struct ReceiveError {
    pub message: String,
    pub kind: ReceiveErrorKind,
    /// Only for `check_swap_history`: `Some(true)` when the check failed after it started
    /// its jobs, which later rounds keep running, and `Some(false)` when it failed before.
    /// `None` for every other call.
    pub history_started: Option<bool>,
}
impl std::fmt::Display for ReceiveError {
    /// Shows the display text.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for ReceiveError {}
impl From<String> for ReceiveError {
    /// A failure the app only shows.
    fn from(message: String) -> Self {
        Self {
            message,
            kind: ReceiveErrorKind::Other,
            history_started: None,
        }
    }
}
impl From<RecoveryError> for ReceiveError {
    /// Keeps the upgrade and both waiting outcomes distinct so the app can act on them.
    fn from(error: RecoveryError) -> Self {
        match error {
            RecoveryError::UpgradeRequired => Self {
                message: "Update Vizor to keep checking private swap addresses. Your saved progress is kept.".into(),
                kind: ReceiveErrorKind::UpgradeRequired,
                history_started: None,
            },
            RecoveryError::NotCaughtUp => Self {
                message: error.to_string(),
                kind: ReceiveErrorKind::WaitingForSync,
                history_started: None,
            },
            RecoveryError::ReceiverBehind => Self {
                message: error.to_string(),
                kind: ReceiveErrorKind::WaitingForService,
                history_started: None,
            },
            RecoveryError::Other(message) => message.into(),
            // The jobs are saved and go on once sync catches up.
            RecoveryError::Started(error) if matches!(*error, RecoveryError::NotCaughtUp) => Self {
                message: "The swap history check is waiting for wallet sync to catch up. It goes on by itself.".into(),
                kind: ReceiveErrorKind::WaitingForSync,
                history_started: Some(true),
            },
            RecoveryError::Started(error) => Self {
                history_started: Some(true),
                ..(*error).into()
            },
        }
    }
}
impl From<SqliteClientError> for ReceiveError {
    /// A wallet database failure the app only shows.
    fn from(error: SqliteClientError) -> Self {
        error.to_string().into()
    }
}
impl From<ReservationPolicy> for ReceiveError {
    /// The wording Vizor shows for each reason issuance or an operation must wait.
    fn from(policy: ReservationPolicy) -> Self {
        let (message, kind) = match policy {
            ReservationPolicy::Limit => (
                "No swap address is free. Wait for a swap in progress to finish.",
                ReceiveErrorKind::Limit,
            ),
            ReservationPolicy::ReceiveHistory => (
                "Preparing a private swap address. Try again in a moment.",
                ReceiveErrorKind::ReceiveHistory,
            ),
            // A reorg that drops the payment which widened the receive window
            // leaves a cached reservation above it for good, so only a new
            // address helps.
            ReservationPolicy::Stale | ReservationPolicy::Gap => (
                "This swap address is no longer available. Request a new quote.",
                ReceiveErrorKind::Stale,
            ),
            ReservationPolicy::FundingHistory => (
                "Finish syncing to the chain tip before requesting a quote.",
                ReceiveErrorKind::Other,
            ),
            ReservationPolicy::Disabled => (
                "Enable NEAR swap privacy to use private swap addresses.",
                ReceiveErrorKind::Other,
            ),
        };
        Self {
            message: message.into(),
            kind,
            history_started: None,
        }
    }
}

/// A durably reserved swap address. A refund address carries its refund key index, an
/// incoming one, its reservation's index.
pub struct SwapAddress {
    pub address: String,
    pub refund_index: Option<u64>,
    pub reservation_index: Option<u64>,
}

/// The NEAR 1Click fields used for quote ownership and expected receipts.
/// Amounts are base-unit decimal strings, as the provider reports them. The hashes are
/// `swapDetails.originChainTxHashes` and `destinationChainTxHashes`, which attribute a
/// recovered refund or payout to its operation.
pub struct SwapProviderStatus {
    pub status: String,
    pub swap_type: Option<String>,
    pub refunded_amount: Option<String>,
    pub amount_out: Option<String>,
    pub origin_tx_hashes: Vec<String>,
    pub destination_tx_hashes: Vec<String>,
}

/// An incoming quote's deposit instructions, as the provider issued them.
pub struct ReceiveDeposit {
    pub address: String,
    pub memo: Option<String>,
    pub deadline_seconds: i64,
}

/// Hands out the next receive address or refund key with no network request. A receive
/// address waits for its own history lookup and for filters near the chain tip, and a
/// refund key for funding history sync. Until then it fails with `ReceiveHistory` or
/// `FundingHistory`, so the app runs a round or sync and asks again.
pub fn reserve_swap_address(
    db_path: String,
    network_name: String,
    account_uuid: String,
    incoming: bool,
    live_tip: u64,
) -> Result<SwapAddress, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    one_time_ivk::require_new_address(network)?;
    let tip = u32::try_from(live_tip)
        .map(BlockHeight::from_u32)
        .map_err(|_| "Invalid chain tip".to_string())?;
    let key = with_db(&db_path, network, &account_uuid, |db, a| {
        one_time_ivk::require_software_account(db, a)?;
        db.enable_one_time_recovery(a)?;
        let now = one_time_ivk::now()?;
        Ok::<_, ReceiveError>(if incoming {
            db.prepare_receive_reservation(a, now)??
        } else {
            db.reserve_refund_key(a, tip)??
        })
    })?;
    let index = key.key_id().index();
    let address = UnifiedAddress::from_receivers(Some(key.receiver()), None, None)
        .ok_or("Invalid swap receiver".to_string())?;
    Ok(SwapAddress {
        address: Address::Unified(address)
            .to_zcash_address(&network)
            .to_string(),
        refund_index: (!incoming).then_some(index),
        reservation_index: incoming.then_some(index),
    })
}

/// Records request ownership before sending the quote, fencing expired or replaced requests.
/// It needs no setting: a quote for an address already reserved finishes even after NEAR
/// swap privacy is turned off.
pub fn begin_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    reservation_index: u64,
    deadline_seconds: i64,
) -> Result<String, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    with_db(&db_path, network, &account_uuid, |db, a| {
        db.enable_one_time_recovery(a)?;
        Ok(db.begin_receive_operation(
            a,
            reservation_index,
            deadline_seconds,
            one_time_ivk::now()?,
        )??)
    })
}

/// Records how quote request `request_id` ended, even if the requesting UI has changed:
/// `accepted` with its deposit instructions, or, without them, definitively rejected,
/// which releases the request's hold on the address. Never call it for a timeout or a
/// malformed response.
pub fn finish_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
    accepted: Option<ReceiveDeposit>,
) -> Result<(), ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    let outcome = match accepted {
        Some(deposit) => OperationOutcome::Accepted(
            zcash_client_sqlite::wallet::one_time_ivk::swap::ReceiveDeposit {
                address: deposit.address,
                memo: deposit.memo,
                deadline: deposit.deadline_seconds,
            },
        ),
        None => OperationOutcome::Rejected,
    };
    with_db(&db_path, network, &account_uuid, |db, a| {
        Ok(db.finish_receive_operation(a, &request_id, &outcome)?)
    })
}

/// Locks the accepted quote's reservation before exposing provider funding
/// instructions, and returns the instructions to show. Refuses as stale once the
/// deposit deadline has passed by the earlier of this device's clock and the latest
/// block time, or once another request on the same reservation has started.
pub fn start_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
) -> Result<ReceiveDeposit, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    with_db(&db_path, network, &account_uuid, |db, a| {
        let deposit = db.start_receive_operation(a, &request_id, one_time_ivk::now()?)??;
        Ok(ReceiveDeposit {
            address: deposit.address,
            memo: deposit.memo,
            deadline_seconds: deposit.deadline,
        })
    })
}

/// Binds an accepted refund quote's deposit address to the refund key reserved for
/// it, before the quote is shown. Funding requires this record.
pub fn record_swap_refund_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    refund_index: u64,
    deposit_address: String,
    deadline_seconds: i64,
) -> Result<(), ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    with_db(&db_path, network, &account_uuid, |db, a| {
        Ok(db.record_refund_operation(
            a,
            refund_index,
            &deposit_address,
            deadline_seconds,
            one_time_ivk::now()?,
        )?)
    })
}

/// What recording one provider status found (see [`observe_swap_status`]).
pub struct SwapStatusRecord {
    /// The wallet still tracked an operation for this address when the status arrived.
    /// `false` means its incoming reservation, if it had one, was already released, so
    /// later statuses can no longer free a receive slot.
    pub tracked: bool,
    /// The status says ZEC is coming to this address: a payout, or a refund of a ZEC
    /// deposit, as the wallet's normalizer reads it. A recovery round can then find it.
    pub receipt_expected: bool,
}

/// Records a provider status, requested at `checked_at_seconds`, on the account's swap
/// operations with this deposit address and memo, and reclaims what that makes
/// reclaimable. `incoming` says the swap pays ZEC into the wallet. Otherwise it is the
/// refund side of a ZEC deposit. `funded` says the app has its own evidence that the
/// provider saw a deposit, which the status alone implies only from `KNOWN_DEPOSIT_TX`
/// on (see `near_observation`). Swaps without a private address are ignored. Do not call
/// it for a failed status request.
pub fn observe_swap_status(
    db_path: String,
    network_name: String,
    account_uuid: String,
    incoming: bool,
    deposit_address: String,
    deposit_memo: Option<String>,
    status: SwapProviderStatus,
    funded: bool,
    checked_at_seconds: i64,
) -> Result<SwapStatusRecord, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    if !one_time_ivk::supported(network) {
        return Ok(SwapStatusRecord {
            tracked: false,
            receipt_expected: false,
        });
    }
    let purpose = if incoming {
        Purpose::Receive
    } else {
        Purpose::Refund
    };
    let origin: Vec<&str> = status.origin_tx_hashes.iter().map(String::as_str).collect();
    let destination: Vec<&str> = status
        .destination_tx_hashes
        .iter()
        .map(String::as_str)
        .collect();
    let observation = near_observation(
        purpose,
        &NearStatus {
            status: &status.status,
            swap_type: status.swap_type.as_deref(),
            refunded_amount: one_time_ivk::provider_amount(&status.refunded_amount),
            amount_out: one_time_ivk::provider_amount(&status.amount_out),
            origin_tx_hashes: &origin,
            destination_tx_hashes: &destination,
        },
    );
    let observation = Observation {
        funded: observation.funded || funded,
        ..observation
    };
    let receipt_expected = matches!(
        observation.status,
        OperationStatus::Terminal(ReceiptExpectation::Positive(_))
    );
    let tracked = with_db(&db_path, network, &account_uuid, |db, a| {
        Ok::<_, ReceiveError>(db.record_operation_status(
            a,
            &deposit_address,
            deposit_memo.as_deref(),
            observation,
            checked_at_seconds,
        )?)
    })?;
    Ok(SwapStatusRecord {
        tracked,
        receipt_expected,
    })
}

/// Stops the network worker. Durable manual and automatic progress remains resumable.
#[flutter_rust_bridge::frb(sync)]
pub fn cancel_swap_recovery() {
    crate::wallet::sync_engine::cancel_recovery();
}

/// Why a swap recovery round left work that no round can run yet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SwapRecoveryWait {
    /// No private query server is selected. Choosing one lets it run.
    Server,
    /// Wallet sync hasn't reached the receiver service's latest publication. A round
    /// after the next completed sync can run it.
    Sync,
    /// The receiver service hasn't published the blocks the work needs yet. A round
    /// after a later sync can run it.
    Publication,
    /// A failed lookup is waiting out its retry delay. A later round retries it.
    Backoff,
}

impl From<Wait> for SwapRecoveryWait {
    /// The app's name for each reason.
    fn from(wait: Wait) -> Self {
        match wait {
            Wait::Server => Self::Server,
            Wait::Sync => Self::Sync,
            Wait::Publication => Self::Publication,
            Wait::Backoff => Self::Backoff,
        }
    }
}

/// What one automatic swap recovery round did.
pub struct SwapRecoveryRound {
    /// The round committed receiver results that can change the balance, activity or
    /// address reservations. Only a successful round reports this. A round that fails,
    /// including `check_swap_history`, may already have committed results, so callers
    /// refresh after a failure too.
    pub changed: bool,
    /// The round accepted a receiver inventory, so the service speaks a format this app
    /// supports.
    pub checked: bool,
    /// Work is left that another round can run right away, so the app should start one.
    pub more: bool,
    /// Why work is left that no round can run yet, if any. Never set with `more`.
    pub wait: Option<SwapRecoveryWait>,
    /// Found payments wait for ordinary sync, or a rescan it queued, to admit them, so
    /// the app should start sync now (see [`SwapRecoveryStatus`]).
    pub rescan: bool,
}

/// Runs a bounded private recovery step independently of ordinary wallet sync. The
/// account last passed to `set_active_sync_account` goes first.
pub fn run_swap_recovery(
    db_path: String,
    network_name: String,
) -> Result<SwapRecoveryRound, ReceiveError> {
    let Some(network) = existing_network(&db_path, &network_name)? else {
        return Ok(crate::wallet::sync_engine::Round::default().into());
    };
    let runtime = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    let round = runtime.block_on(crate::wallet::sync_engine::recover(
        &db_path,
        network,
        false,
        active_account(),
    ))?;
    Ok(round.into())
}

/// What one filter step did.
pub struct SwapFilterStep {
    /// Filter coverage is left that only a round can finish: a filter request failed, the
    /// gap to the scanned tip is more than one range, the service's history changed, or an
    /// account needs a complete check. The app owes a round unless one is already pending.
    pub needs_round: bool,
}

/// Runs a filter step: one filter head and range read that moves the watched accounts'
/// filter markers toward the scanned tip, with no inventory or lookup. It shares a
/// round's admission, so it fails while a round runs. A hit queues a lookup, which owes a
/// round (see [`SwapRecoveryStatus::round_due`]).
pub fn run_swap_filter_step(
    db_path: String,
    network_name: String,
) -> Result<SwapFilterStep, ReceiveError> {
    let Some(network) = existing_network(&db_path, &network_name)? else {
        return Ok(SwapFilterStep { needs_round: false });
    };
    let runtime = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    let step = runtime.block_on(crate::wallet::sync_engine::filter_step(&db_path, network))?;
    Ok(SwapFilterStep {
        needs_round: step.needs_round,
    })
}

impl From<crate::wallet::sync_engine::Round> for SwapRecoveryRound {
    /// The app's view of a finished round.
    fn from(round: crate::wallet::sync_engine::Round) -> Self {
        Self {
            changed: round.changed,
            checked: round.checked,
            more: round.more,
            wait: round.wait.map(Into::into),
            rescan: round.awaiting_admission,
        }
    }
}

/// The active sync account, whose recovery work goes first. An unparsable value has no
/// priority.
fn active_account() -> Option<zcash_client_sqlite::AccountUuid> {
    super::sync::active_sync_account().and_then(|uuid| keys::parse_account_uuid(&uuid).ok())
}

/// Starts or resumes an explicit PIR search of every address the wallet has enrolled, on
/// every software account whatever NEAR swap privacy says, and returns its round. Its
/// jobs start on every account or none. A new check first forgets earlier answers, so
/// every address is read again from its history start, while a paused one resumes. Refunds require known funding memos, so a refund
/// funded before the wallet birthday is found only after restoring with an earlier
/// birthday.
pub fn check_swap_history(
    db_path: String,
    network_name: String,
) -> Result<SwapRecoveryRound, ReceiveError> {
    let not_started = |mut error: ReceiveError| {
        error.history_started.get_or_insert(false);
        error
    };
    let Some(network) = existing_network(&db_path, &network_name).map_err(not_started)? else {
        return Ok(crate::wallet::sync_engine::Round::default().into());
    };
    let runtime = tokio::runtime::Runtime::new().map_err(|e| not_started(e.to_string().into()))?;
    // Every enrolled address, through the library's automatic end.
    runtime
        .block_on(crate::wallet::sync_engine::recover(
            &db_path,
            network,
            true,
            active_account(),
        ))
        .map(Into::into)
        .map_err(|error| not_started(error.into()))
}

/// Cancels explicit history searches, retaining their cursors and automatic obligations.
pub fn cancel_swap_history(db_path: String, network_name: String) -> Result<(), ReceiveError> {
    let Some(network) = existing_network(&db_path, &network_name)? else {
        return Ok(());
    };
    crate::wallet::db::with_wallet_db_write_lock("swap.cancel", || {
        let mut db =
            open_existing_wallet_db_with_timeout(&db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        for account in one_time_ivk::software_accounts(&db)? {
            db.cancel_one_time_history(account)
                .map_err(|e| e.to_string())?;
        }
        Ok::<_, String>(())
    })?;
    Ok(())
}

/// The network of the wallet at `db_path`, migrated first, or `None` when there is no
/// wallet or one-time IVKs don't run on its network, so the caller has nothing to do. It
/// never creates a database a reset deleted.
fn existing_network(
    db_path: &str,
    network_name: &str,
) -> Result<Option<WalletNetwork>, ReceiveError> {
    if !keys::wallet_exists(db_path) {
        return Ok(None);
    }
    let network = parse_network_and_migrate(db_path, network_name)?;
    Ok(one_time_ivk::supported(network).then_some(network))
}

/// Private swap recovery state across the software accounts, read without network
/// access (see `one_time_ivk::recovery_status`). The work and history fields cover only
/// accounts in the set rounds cover (see `one_time_ivk::in_set`).
pub struct SwapRecoveryStatus {
    /// A round is owed: an account in the set has a due lookup, as a filter hit, a
    /// registered key, refund funding learned from a memo or a repair queues one, an
    /// unfinished seed walk, or filters read more than 10 blocks behind the scanned tip
    /// (see `RecoveryStatus::round_due`).
    pub round_due: bool,
    /// Found payments on any software account wait for ordinary sync, or a rescan it
    /// queued, to admit them, so the app should start sync.
    pub awaiting_admission: bool,
    /// An enabled account has unfinished seed recovery or an active history check.
    pub checking_history: bool,
    /// An enabled account has an active history check the user started, which
    /// later rounds resume, apart from automatic seed recovery.
    pub manual_check_active: bool,
    /// The receiver service needs a newer app. Recovery resumes after an update.
    pub upgrade_required: bool,
}

/// No recovery state, as a wallet without one-time work has.
pub(crate) const IDLE_STATUS: SwapRecoveryStatus = SwapRecoveryStatus {
    round_due: false,
    awaiting_admission: false,
    checking_history: false,
    manual_check_active: false,
    upgrade_required: false,
};

/// Reads [`SwapRecoveryStatus`]. Without a wallet, or where one-time IVKs don't run, there
/// is nothing to report.
pub fn get_swap_recovery_status(
    db_path: String,
    network_name: String,
) -> Result<SwapRecoveryStatus, ReceiveError> {
    let Some(network) = existing_network(&db_path, &network_name)? else {
        return Ok(IDLE_STATUS);
    };
    // A reset may delete the wallet after the existence check, so never create one.
    let db = open_existing_wallet_db_with_timeout(&db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
    Ok(one_time_ivk::recovery_status(&db)?)
}

/// What still blocks private swap issuance, or crediting a found payment, for one
/// account. Recovery rounds finish each of these on their own.
pub struct SwapAccountReadiness {
    /// The restored seed's receive addresses are still being walked.
    pub seed_walk: bool,
    /// Lookups are queued: for a filter hit, a held reservation's re-check or a repair,
    /// including ones waiting out a retry delay.
    pub lookups: bool,
    /// Found payments wait for ordinary sync, or a rescan it queued, to admit them.
    pub awaiting_admission: bool,
}

/// Nothing to wait for (see [`SwapAccountReadiness`]).
const READY: SwapAccountReadiness = SwapAccountReadiness {
    seed_walk: false,
    lookups: false,
    awaiting_admission: false,
};

/// Reads [`SwapAccountReadiness`] for `account_uuid` without network access. A missing
/// wallet, an unsupported network or an account without one-time keys has nothing to
/// wait for.
pub fn get_swap_account_readiness(
    db_path: String,
    network_name: String,
    account_uuid: String,
) -> Result<SwapAccountReadiness, ReceiveError> {
    let Some(network) = existing_network(&db_path, &network_name)? else {
        return Ok(READY);
    };
    let account = keys::parse_account_uuid(&account_uuid)?;
    // A reset may delete the wallet after the existence check, so never create one.
    let db = open_existing_wallet_db_with_timeout(&db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
    // Read at the end of time, so lookups waiting out a retry delay count too.
    let state = db
        .one_time_recovery(account, i64::MAX, None)
        .map_err(|e| e.to_string())?;
    if !state.enabled {
        return Ok(READY);
    }
    Ok(SwapAccountReadiness {
        seed_walk: !state.restore_complete,
        lookups: !state.lookups.is_empty(),
        awaiting_admission: state.awaiting_admission > 0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_reservation_outside_the_window_asks_for_a_new_address() {
        let error = ReceiveError::from(ReservationPolicy::Gap);
        assert_eq!(error.kind, ReceiveErrorKind::Stale);
        assert_eq!(
            error.message,
            ReceiveError::from(ReservationPolicy::Stale).message
        );
    }
}
