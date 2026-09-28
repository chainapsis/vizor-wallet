//! Incoming swap reservation lifecycle. Refund allocation uses the existing API.
use crate::wallet::{keys, network::WalletNetwork, swap_receiving::receive};
use zcash_keys::address::{Address, UnifiedAddress};

/// An account-scoped durable receive draft; its address has complete canonical discovery coverage.
pub struct ReceiveReservation {
    pub id: i64,
    pub index: u64,
    pub address: String,
}

/// Provider lookup for a persisted quote, including quotes never started in the UI.
pub struct ReceiveQuoteStatusRequest {
    pub request_id: String,
    pub operation_id: String,
    pub deposit_memo: Option<String>,
}

fn network(path: &str, value: &str) -> Result<WalletNetwork, String> {
    let network = keys::parse_network(value)?;
    keys::ensure_db_migrated_once(path, network)?;
    Ok(network)
}

/// Resumes a draft or reserves the lowest eligible index and verifies its history and recent tail.
/// Does not start or restart ordinary wallet sync.
pub async fn prepare_receive_reservation(
    db_path: String,
    network_name: String,
    account_uuid: String,
    live_tip: u64,
    lightwalletd_url: String,
) -> Result<ReceiveReservation, String> {
    let network = network(&db_path, &network_name)?;
    let r = receive::prepare(
        &db_path,
        network,
        &account_uuid,
        live_tip,
        &lightwalletd_url,
    )
    .await?;
    let address = Address::Unified(
        UnifiedAddress::from_receivers(Some(r.key.receiver()), None, None)
            .ok_or("Invalid receive address")?,
    )
    .to_zcash_address(&network)
    .to_string();
    Ok(ReceiveReservation {
        id: r.id,
        index: r.key.key_id().index(),
        address,
    })
}

/// Persists an unknown outcome and scan watch before sending a provider quote request.
pub fn begin_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    reservation_id: i64,
    request_id: String,
) -> Result<(), String> {
    receive::with_db(
        &db_path,
        network(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.begin_swap_receive_quote(a, reservation_id, &request_id, receive::now()?)
                .map_err(|e| e.to_string())
        },
    )
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
) -> Result<(), String> {
    receive::with_db(
        &db_path,
        network(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.record_swap_receive_quote(
                a,
                &request_id,
                &operation_id,
                deposit_memo.as_deref(),
                deadline_seconds,
            )
            .map_err(|e| e.to_string())
        },
    )
}

/// Removes only a definitively rejected request watch; never call for a timeout.
pub fn reject_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    request_id: String,
) -> Result<(), String> {
    receive::with_db(
        &db_path,
        network(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.reject_swap_receive_quote(a, &request_id)
                .map_err(|e| e.to_string())
        },
    )
}

/// Locks the accepted draft before exposing provider funding instructions.
pub fn start_receive_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    operation_id: String,
) -> Result<(), String> {
    receive::with_db(
        &db_path,
        network(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.start_swap_receive_quote(a, &operation_id)
                .map_err(|e| e.to_string())
        },
    )
}

/// Returns operations whose provider status needs refreshing.
pub fn receive_quotes_due(
    db_path: String,
    network_name: String,
    account_uuid: String,
) -> Result<Vec<ReceiveQuoteStatusRequest>, String> {
    receive::with_db(
        &db_path,
        network(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            Ok(db
                .swap_receive_quotes_due(a, receive::now()?)
                .map_err(|e| e.to_string())?
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
    status: String,
    funded: bool,
    checked_at_seconds: i64,
) -> Result<(), String> {
    receive::with_db(
        &db_path,
        network(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.observe_swap_receive_quote(a, &request_id, &status, funded, checked_at_seconds)
                .map_err(|e| e.to_string())
        },
    )
}

/// Rechecks eligible abandoned addresses against PIR and releases only verified empty ones.
pub async fn reap_receive_reservations(
    db_path: String,
    network_name: String,
    account_uuid: String,
    lightwalletd_url: String,
) -> Result<u32, String> {
    receive::reap(
        &db_path,
        network(&db_path, &network_name)?,
        &account_uuid,
        &lightwalletd_url,
    )
    .await
}
