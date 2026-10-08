//! Private NEAR swap addresses over the wallet's dynamic IVKs: reservations, quote
//! records, provider statuses and history rechecks. Provider polling stays in Dart;
//! allocation is durable in Rust.
use super::sync::parse_network_and_migrate;
use crate::wallet::db::{open_wallet_db_with_timeout, with_wallet_db_write_lock};
use crate::wallet::dynamic_ivk::{self, with_db};
use crate::wallet::{db::WALLET_DB_BUSY_TIMEOUT, keys};
use zakura_dynamic_ivk::{lifecycle::near_observation, Purpose};
use zcash_client_sqlite::{
    error::SqliteClientError,
    wallet::dynamic_ivk::{OperationOutcome, ProviderSeen, ReservationPolicy},
};

/// A private swap failure. `message` is display text, never a parsing protocol.
#[derive(Clone, Debug)]
pub struct ReceiveError {
    pub message: String,
}
impl std::fmt::Display for ReceiveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for ReceiveError {}
impl From<String> for ReceiveError {
    fn from(message: String) -> Self {
        Self { message }
    }
}
impl From<&str> for ReceiveError {
    fn from(message: &str) -> Self {
        message.to_owned().into()
    }
}
impl From<SqliteClientError> for ReceiveError {
    fn from(error: SqliteClientError) -> Self {
        error.to_string().into()
    }
}
/// The wording Vizor shows for each reason issuance or an operation must wait.
impl From<ReservationPolicy> for ReceiveError {
    fn from(policy: ReservationPolicy) -> Self {
        match policy {
            ReservationPolicy::Gap => {
                "Restored swap addresses are still being checked. \
                 Try again after the wallet finishes syncing."
            }
            ReservationPolicy::Limit => {
                "No swap address is free. Wait for a swap in progress to finish."
            }
            ReservationPolicy::Stale => {
                "This receive reservation is no longer available. Request a new quote."
            }
            ReservationPolicy::Coverage => {
                "Finish syncing to the chain tip before requesting a quote."
            }
            ReservationPolicy::Unreadable => {
                "A swap refund record could not be read. \
                 Update the app before swapping ZEC again."
            }
        }
        .into()
    }
}

/// A durably reserved swap address. A refund address carries its refund key index; an
/// incoming one, its reservation's index.
pub struct SwapAddress {
    pub address: String,
    pub refund_index: Option<u64>,
    pub reservation_index: Option<u64>,
}

/// The NEAR 1Click status fields that decide when a swap key stops scanning.
/// Amounts are base-unit decimal strings, as the provider reports them.
pub struct SwapProviderStatus {
    pub status: String,
    pub swap_type: Option<String>,
    pub refunded_amount: Option<String>,
    pub amount_out: Option<String>,
    pub deadline_seconds: Option<i64>,
}

/// An incoming quote's deposit instructions, as the provider issued them.
pub struct ReceiveDeposit {
    pub address: String,
    pub memo: Option<String>,
    pub deadline_seconds: i64,
}

/// Reserves a swap address on a software account. `incoming` resumes the account's
/// draft or reserves the lowest eligible incoming index, after checking the swap
/// provider's seen set from the receiver directory (see `prepare_receive_reservation`);
/// its key scans from the next unscanned block until it closes. Otherwise it reserves
/// the next refund index, whose key starts scanning when the wallet stores the swap's
/// funding transaction. `live_tip` is the chain tip the quote flow fetched. Does not
/// start or restart ordinary wallet sync.
pub fn reserve_swap_address(
    db_path: String,
    network_name: String,
    account_uuid: String,
    incoming: bool,
    live_tip: u64,
) -> Result<SwapAddress, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    dynamic_ivk::require_new_address(network)?;
    let tip = dynamic_ivk::network_tip(live_tip)?;
    let key = if incoming {
        // Fetched before taking the wallet lock, so a slow directory never holds it.
        let seen = tokio::runtime::Runtime::new()
            .map_err(|e| format!("tokio: {e}"))?
            .block_on(crate::wallet::sync_engine::fetch_seen(network));
        let contains = |receivers: &[[u8; 43]]| {
            seen.as_ref()
                .map_or_else(|| vec![true; receivers.len()], |s| s.contains(receivers))
        };
        let view = seen.as_ref().map(|s| ProviderSeen {
            since: s.since(),
            until: s.until(),
            contains: &contains,
        });
        with_db(&db_path, network, &account_uuid, |db, a| {
            dynamic_ivk::require_software_account(db, a)?;
            Ok::<_, ReceiveError>(db.prepare_receive_reservation(
                a,
                dynamic_ivk::now()?,
                tip,
                view.as_ref(),
            )??)
        })?
    } else {
        with_db(&db_path, network, &account_uuid, |db, a| {
            dynamic_ivk::require_software_account(db, a)?;
            Ok::<_, ReceiveError>(db.reserve_refund_key(a, tip)??)
        })?
    };
    let index = key.key_id().index();
    Ok(SwapAddress {
        address: dynamic_ivk::encode_address(&key, network)?,
        refund_index: (!incoming).then_some(index),
        reservation_index: incoming.then_some(index),
    })
}

/// Persists an unknown outcome and scan watch just before a provider quote request
/// leaves the device, and returns the request's identity. `reservation_index` is the
/// incoming reservation [`reserve_swap_address`] returned, and `deadline_seconds` the
/// deposit deadline the request sends.
pub fn begin_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    reservation_index: u64,
    deadline_seconds: i64,
) -> Result<String, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    with_db(&db_path, network, &account_uuid, |db, a| {
        dynamic_ivk::require_new_address(network)?;
        Ok(db.begin_receive_operation(
            a,
            reservation_index,
            deadline_seconds,
            dynamic_ivk::now()?,
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
        Some(deposit) => {
            OperationOutcome::Accepted(zcash_client_sqlite::wallet::dynamic_ivk::ReceiveDeposit {
                address: deposit.address,
                memo: deposit.memo,
                deadline: deposit.deadline_seconds,
            })
        }
        None => OperationOutcome::Rejected,
    };
    with_db(&db_path, network, &account_uuid, |db, a| {
        Ok(db.finish_receive_operation(a, &request_id, &outcome)?)
    })
}

/// Locks the accepted quote's reservation before exposing provider funding
/// instructions, and returns the instructions to show.
pub fn start_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
) -> Result<ReceiveDeposit, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    with_db(&db_path, network, &account_uuid, |db, a| {
        let deposit = db.start_receive_operation(a, &request_id)??;
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
            dynamic_ivk::now()?,
        )?)
    })
}

/// Records a provider status, requested at `checked_at_seconds`, on the account's swap
/// operations with this deposit address and memo, and reclaims what that makes
/// reclaimable. `incoming` says the swap pays ZEC into the wallet; otherwise it is the
/// refund side of a ZEC deposit. `funded` says the provider saw a deposit. Swaps
/// without a private address are ignored. Do not call it for a failed status request.
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
) -> Result<(), ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    if !dynamic_ivk::supported(network) {
        return Ok(());
    }
    let purpose = if incoming {
        Purpose::Receive
    } else {
        Purpose::Refund
    };
    let observation = near_observation(purpose, &dynamic_ivk::near_status(&status));
    with_db(&db_path, network, &account_uuid, |db, a| {
        db.record_operation_status(
            a,
            &deposit_address,
            deposit_memo.as_deref(),
            observation,
            funded,
            checked_at_seconds,
        )?;
        Ok(())
    })
}

/// Queues one receiver-directory sweep of every closed swap key for the next sync,
/// which finds a second refund or a late payout that arrived after its key stopped
/// scanning. Called when the user turns NEAR swap privacy on.
pub fn recheck_swap_history(db_path: String, network_name: String) -> Result<(), ReceiveError> {
    // Without a wallet there is nothing to recheck; do not create its database.
    if !keys::wallet_exists(&db_path) {
        return Ok(());
    }
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    // Only supported networks run restore sweeps.
    if !dynamic_ivk::supported(network) {
        return Ok(());
    }
    with_wallet_db_write_lock("dynamic_ivk.recheck", || {
        let mut db = open_wallet_db_with_timeout(&db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        for account in dynamic_ivk::software_accounts(&db)? {
            db.recheck_dynamic_key_history(account)?;
        }
        Ok(())
    })
}
