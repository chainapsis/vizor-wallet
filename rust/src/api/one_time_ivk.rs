//! Private NEAR swap addresses over the wallet's one-time IVKs: reservations, quote
//! records, provider statuses and swap history checks. Provider polling stays in Dart.
//! Allocation is durable in Rust.
use super::sync::parse_network_and_migrate;
use crate::wallet::db::open_existing_wallet_db_with_timeout;
use crate::wallet::one_time_ivk::{self, with_db};
use crate::wallet::sync_engine::RecoveryError;
use crate::wallet::{db::WALLET_DB_BUSY_TIMEOUT, keys};
use zakura_near_intents::{near_observation, NearStatus};
use zakura_one_time_ivk::{swap::Observation, Purpose};
use zcash_client_sqlite::{
    error::SqliteClientError,
    wallet::one_time_ivk::swap::{OperationOutcome, ReservationPolicy},
};

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
    /// The next receive address's history is still being checked. Run recovery, then
    /// ask again.
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
            },
            RecoveryError::NotCaughtUp => Self {
                message: error.to_string(),
                kind: ReceiveErrorKind::WaitingForSync,
            },
            RecoveryError::ReceiverBehind => Self {
                message: error.to_string(),
                kind: ReceiveErrorKind::WaitingForService,
            },
            RecoveryError::Other(message) => message.into(),
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

/// Reserves the lowest eligible receive slot or a refund key after funding history sync.
/// Receive issuance uses the mined four-index window and performs no network request.
pub fn reserve_swap_address(
    db_path: String,
    network_name: String,
    account_uuid: String,
    incoming: bool,
    live_tip: u64,
) -> Result<SwapAddress, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    one_time_ivk::require_new_address(network)?;
    let tip = one_time_ivk::network_tip(live_tip)?;
    let key = with_db(&db_path, network, &account_uuid, |db, a| {
        one_time_ivk::require_software_account(db, a)?;
        one_time_ivk::reconcile_enabled(db, network)?;
        let now = one_time_ivk::now()?;
        Ok::<_, ReceiveError>(if incoming {
            db.prepare_receive_reservation(a, now)??
        } else {
            db.reserve_refund_key(a, tip)??
        })
    })?;
    let index = key.key_id().index();
    Ok(SwapAddress {
        address: one_time_ivk::encode_address(&key, network)?,
        refund_index: (!incoming).then_some(index),
        reservation_index: incoming.then_some(index),
    })
}

/// Records request ownership before sending the quote, fencing expired or replaced requests.
pub fn begin_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    reservation_index: u64,
    deadline_seconds: i64,
) -> Result<String, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    one_time_ivk::require_new_address(network)?;
    with_db(&db_path, network, &account_uuid, |db, a| {
        one_time_ivk::reconcile_enabled(db, network)?;
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

/// Records a provider status, requested at `checked_at_seconds`, on the account's swap
/// operations with this deposit address and memo, and reclaims what that makes
/// reclaimable. `incoming` says the swap pays ZEC into the wallet. Otherwise it is the
/// refund side of a ZEC deposit. `funded` says the app has its own evidence that the
/// provider saw a deposit, which the status alone implies only from `KNOWN_DEPOSIT_TX`
/// on (see `near_observation`). Swaps without a private address are ignored. Do not call
/// it for a failed status request.
///
/// Returns whether the wallet still tracked an operation for this address when the
/// status arrived. `false` means its incoming reservation, if it had one, was already
/// released, so later statuses can no longer free a receive slot.
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
) -> Result<bool, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    if !one_time_ivk::supported(network) {
        return Ok(false);
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
    with_db(&db_path, network, &account_uuid, |db, a| {
        Ok(db.record_operation_status(
            a,
            &deposit_address,
            deposit_memo.as_deref(),
            observation,
            checked_at_seconds,
        )?)
    })
}

/// Applies the effective discovery setting immediately, fencing outstanding callbacks.
pub fn reconcile_swap_recovery(db_path: String, network_name: String) -> Result<(), ReceiveError> {
    with_existing_wallet(&db_path, &network_name, "swap.setting", |db, network| {
        one_time_ivk::reconcile_enabled(db, network)
    })
}

/// Stops the network worker. Durable manual and automatic progress remains resumable.
#[flutter_rust_bridge::frb(sync)]
pub fn cancel_swap_recovery() {
    crate::wallet::sync_engine::cancel_recovery();
}

/// Runs a bounded private recovery step independently of ordinary wallet sync. Returns
/// whether any account had recovery work. `false` means the round changed nothing, and
/// with the feature off, that no round is needed until the wallet changes.
pub fn run_swap_recovery(db_path: String, network_name: String) -> Result<bool, ReceiveError> {
    if !keys::wallet_exists(&db_path) {
        return Ok(false);
    }
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    // The app asks after every completed sync, so a wallet with nothing to do returns
    // before building a worker thread pool and an HTTPS client.
    if !one_time_ivk::supported(network) || one_time_ivk::idle_while_off(&db_path, network)? {
        return Ok(false);
    }
    let runtime = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    Ok(runtime.block_on(crate::wallet::sync_engine::recover(&db_path, network, None))?)
}

/// Starts or resumes an explicit PIR search of every address the wallet has enrolled.
/// Refunds require known funding memos, so a refund funded before the wallet birthday is
/// found only after restoring with an earlier birthday.
pub fn check_swap_history(db_path: String, network_name: String) -> Result<(), ReceiveError> {
    if !keys::wallet_exists(&db_path) {
        return Ok(());
    }
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    one_time_ivk::require_new_address(network)?;
    let runtime = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    // Every enrolled address, through the library's automatic end.
    runtime.block_on(crate::wallet::sync_engine::recover(
        &db_path,
        network,
        Some(None),
    ))?;
    Ok(())
}

/// Cancels explicit history searches, retaining their cursors and automatic obligations.
pub fn cancel_swap_history(db_path: String, network_name: String) -> Result<(), ReceiveError> {
    with_existing_wallet(&db_path, &network_name, "swap.cancel", |db, _| {
        for account in one_time_ivk::software_accounts(db)? {
            db.cancel_one_time_history(account)
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    })
}

/// Runs `action` under the wallet write lock on the existing wallet at `db_path`, and
/// does nothing when there is no wallet. It never creates a database a reset deleted.
fn with_existing_wallet(
    db_path: &str,
    network_name: &str,
    operation: &'static str,
    action: impl FnOnce(
        &mut crate::wallet::db::WalletDatabase,
        crate::wallet::network::WalletNetwork,
    ) -> Result<(), String>,
) -> Result<(), ReceiveError> {
    if !keys::wallet_exists(db_path) {
        return Ok(());
    }
    let network = parse_network_and_migrate(db_path, network_name)?;
    crate::wallet::db::with_wallet_db_write_lock(operation, || {
        let mut db = crate::wallet::db::open_existing_wallet_db_with_timeout(
            db_path,
            network,
            WALLET_DB_BUSY_TIMEOUT,
        )?;
        action(&mut db, network)
    })?;
    Ok(())
}

/// Private swap recovery state across the wallet's software accounts.
pub struct SwapRecoveryStatus {
    /// An enabled account has unfinished seed recovery or an active history check.
    pub checking_history: bool,
    /// An enabled account has an active history check the user started, which
    /// later rounds resume, apart from automatic seed recovery.
    pub manual_check_active: bool,
    /// The receiver service needs a newer app. Recovery resumes after an update.
    pub upgrade_required: bool,
}

/// Reads [`SwapRecoveryStatus`] without network access.
pub fn get_swap_recovery_status(
    db_path: String,
    network_name: String,
) -> Result<SwapRecoveryStatus, ReceiveError> {
    let idle = SwapRecoveryStatus {
        checking_history: false,
        manual_check_active: false,
        upgrade_required: false,
    };
    if !keys::wallet_exists(&db_path) {
        return Ok(idle);
    }
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    if !one_time_ivk::supported(network) {
        return Ok(idle);
    }
    // A reset may delete the wallet after the existence check, so never create one.
    let db = open_existing_wallet_db_with_timeout(&db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
    let flags = one_time_ivk::recovery_flags(&db)?;
    Ok(SwapRecoveryStatus {
        checking_history: flags.checking,
        manual_check_active: flags.manual,
        upgrade_required: flags.upgrade,
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
