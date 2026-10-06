//! Incoming swap reservation lifecycle. Refund allocation uses the existing API.
use super::sync::parse_network_and_migrate;
use crate::wallet::swap_receiving::receive::ReceiveError;
use crate::wallet::swap_receiving::{self, receive};
use zcash_client_sqlite::wallet::swap_receiving::{QuoteOutcome, ReceiveDeposit};

/// An account-scoped durable receive draft, whose key is scanned from issuance.
pub struct ReceiveReservation {
    pub id: i64,
    pub address: String,
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

/// The deposit instructions of a started incoming quote: the only ones to show.
pub struct ReceiveDepositInstruction {
    pub address: String,
    pub memo: Option<String>,
}

/// Provider lookup for a persisted quote, including quotes never started in the UI.
pub struct ReceiveQuoteStatusRequest {
    pub request_id: String,
    pub operation_id: String,
    pub deposit_memo: Option<String>,
}

/// Resumes the account's draft or reserves the lowest eligible index. Its key is
/// scanned from the next unscanned block until it closes, and quoting later
/// requires that scanning to reach the tip without finding a payment. Does not
/// start or restart ordinary wallet sync.
pub fn prepare_receive_reservation(
    db_path: String,
    network_name: String,
    account_uuid: String,
    live_tip: u64,
) -> Result<ReceiveReservation, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    swap_receiving::require_new_address(network)?;
    let r = receive::with_db(&db_path, network, &account_uuid, |db, a| {
        swap_receiving::require_software_account(db, a)?;
        db.prepare_swap_receive_reservation(
            a,
            receive::now()?,
            swap_receiving::network_tip(live_tip)?,
        )
        .map_err(ReceiveError::from)
    })?;
    Ok(ReceiveReservation {
        id: r.id,
        address: swap_receiving::encode_address(&r.key, network)?,
    })
}

/// Persists an unknown outcome and scan watch just before a provider quote request
/// leaves the device, and returns the request's identity. `deadline_seconds` is the
/// deposit deadline the request sends.
pub fn begin_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    reservation_id: i64,
    deadline_seconds: i64,
) -> Result<String, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    receive::with_db(&db_path, network, &account_uuid, |db, a| {
        swap_receiving::require_new_address(network)?;
        db.begin_swap_receive_quote(a, reservation_id, deadline_seconds, receive::now()?)
            .map_err(ReceiveError::from)
    })
}

/// Saves accepted payment instructions even if the requesting UI has changed.
pub fn record_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
    operation_id: String,
    deposit_memo: Option<String>,
    deadline_seconds: i64,
) -> Result<(), ReceiveError> {
    receive::with_db(
        &db_path,
        parse_network_and_migrate(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            let deposit = ReceiveDeposit {
                address: operation_id,
                memo: deposit_memo,
                deadline: deadline_seconds,
            };
            db.finish_swap_receive_quote(a, &request_id, &QuoteOutcome::Accepted(deposit))
                .map_err(ReceiveError::from)
        },
    )
}

/// Removes only a definitively rejected request watch; never call for a timeout.
pub fn reject_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
) -> Result<(), ReceiveError> {
    receive::with_db(
        &db_path,
        parse_network_and_migrate(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.finish_swap_receive_quote(a, &request_id, &QuoteOutcome::Rejected)
                .map_err(ReceiveError::from)
        },
    )
}

/// Locks the accepted draft before exposing provider funding instructions, and
/// returns the instructions to show.
pub fn start_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
) -> Result<ReceiveDepositInstruction, ReceiveError> {
    receive::with_db(
        &db_path,
        parse_network_and_migrate(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            let deposit = db
                .start_swap_receive_quote(a, &request_id)
                .map_err(ReceiveError::from)?;
            Ok(ReceiveDepositInstruction {
                address: deposit.address,
                memo: deposit.memo,
            })
        },
    )
}

/// Returns operations whose provider status needs refreshing.
pub fn receive_quotes_due(
    db_path: String,
    network_name: String,
    account_uuid: String,
) -> Result<Vec<ReceiveQuoteStatusRequest>, ReceiveError> {
    receive::with_db(
        &db_path,
        parse_network_and_migrate(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            Ok(db
                .swap_receive_quotes_due(a, receive::now()?)
                .map_err(ReceiveError::from)?
                .into_iter()
                .map(|q| ReceiveQuoteStatusRequest {
                    request_id: q.request_id,
                    operation_id: q.operation_id,
                    deposit_memo: q.deposit_memo,
                })
                .collect())
        },
    )
}

/// Saves a successful status response using the request start time to reject stale observations.
pub fn observe_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
    status: SwapProviderStatus,
    funded: bool,
    checked_at_seconds: i64,
) -> Result<(), ReceiveError> {
    receive::with_db(
        &db_path,
        parse_network_and_migrate(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            let status = swap_receiving::provider_status(&status);
            db.observe_swap_receive_quote(a, &request_id, &status, funded, checked_at_seconds)
                .map_err(ReceiveError::from)
        },
    )
}

/// Closes settled paid reservations and releases abandoned unpaid ones whose
/// addresses local scanning shows are still empty.
pub fn reap_receive_reservations(
    db_path: String,
    network_name: String,
    account_uuid: String,
) -> Result<(), ReceiveError> {
    receive::with_db(
        &db_path,
        parse_network_and_migrate(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.reap_swap_receive_reservations(a, receive::now()?)?;
            Ok(())
        },
    )
}
