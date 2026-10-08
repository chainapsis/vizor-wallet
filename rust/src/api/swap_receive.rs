//! Swap receiving: refund and incoming address reservations, provider statuses, and
//! history rechecks.
use super::sync::parse_network_and_migrate;
use crate::wallet::db::{open_wallet_db_with_timeout, with_wallet_db_write_lock};
use crate::wallet::swap_receiving::receive::ReceiveError;
use crate::wallet::swap_receiving::{self, receive};
use crate::wallet::{db::WALLET_DB_BUSY_TIMEOUT, keys, network::WalletNetwork};
use zakura_swap_receiving::lifecycle::near_observation;
use zcash_client_sqlite::wallet::swap_receiving::{ProviderSeen, QuoteOutcome, ReceiveDeposit};
use zcash_keys::address::Address;

/// A durably reserved refund address and its key index.
pub struct SwapReceivingAddress {
    pub address: String,
    pub index: u64,
}

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

/// Resumes the account's draft or reserves the lowest eligible index, checking the swap
/// provider's seen set from the receiver directory (see
/// `prepare_swap_receive_reservation`). Its key is scanned from the next unscanned block
/// until it closes, and quoting later requires that scanning to reach the tip without
/// finding a payment. Does not start or restart ordinary wallet sync.
pub fn prepare_receive_reservation(
    db_path: String,
    network_name: String,
    account_uuid: String,
    live_tip: u64,
) -> Result<ReceiveReservation, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    swap_receiving::require_new_address(network)?;
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
    let r = receive::with_db(&db_path, network, &account_uuid, |db, a| {
        swap_receiving::require_software_account(db, a)?;
        db.prepare_swap_receive_reservation(
            a,
            receive::now()?,
            swap_receiving::network_tip(live_tip)?,
            view.as_ref(),
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

/// Reserves the next refund address. Its key starts scanning when the wallet stores
/// the swap's funding transaction. `live_tip` is the chain tip the quote flow fetched.
pub fn reserve_swap_receiving_address(
    db_path: String,
    network_name: String,
    account_uuid: String,
    live_tip: u64,
) -> Result<SwapReceivingAddress, ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    swap_receiving::require_new_address(network)?;
    receive::with_db(&db_path, network, &account_uuid, |db, a| {
        swap_receiving::require_software_account(db, a)?;
        let key = db.reserve_swap_refund_key(a, swap_receiving::network_tip(live_tip)?)?;
        Ok(SwapReceivingAddress {
            address: swap_receiving::encode_address(&key, network)?,
            index: key.key_id().index(),
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
    receive::with_db(
        &db_path,
        parse_network_and_migrate(&db_path, &network_name)?,
        &account_uuid,
        |db, a| {
            db.record_swap_refund_quote(
                a,
                refund_index,
                &deposit_address,
                deadline_seconds,
                receive::now()?,
            )
            .map_err(ReceiveError::from)
        },
    )
}

/// Records a provider status, fetched at `observed_at_seconds`, for the refund key
/// behind `refund_address`. Addresses without a swap key and unrecognized statuses
/// are ignored. Do not call it for a failed status request.
pub fn observe_swap_refund_quote(
    db_path: String,
    network_name: String,
    account_uuid: String,
    operation_id: String,
    refund_address: String,
    status: SwapProviderStatus,
    observed_at_seconds: i64,
) -> Result<(), ReceiveError> {
    let network = parse_network_and_migrate(&db_path, &network_name)?;
    receive::with_db(&db_path, network, &account_uuid, |db, a| {
        let Some(Address::Unified(address)) = Address::decode(&network, &refund_address) else {
            return Ok(());
        };
        let Some(receiver) = address.orchard() else {
            return Ok(());
        };
        let Some(key) = db.get_swap_receiving_key_for_receiver(a, receiver)? else {
            return Ok(());
        };
        let status = swap_receiving::provider_status(&status);
        if let Some(observation) = near_observation(key.key_id().purpose(), &status) {
            db.record_swap_observation(
                a,
                key.key_id(),
                &operation_id,
                observation,
                observed_at_seconds,
            )?;
        }
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
    // Only mainnet runs restore sweeps (see `sync_engine::swap_private`).
    if network != WalletNetwork::Main || cfg!(ironwood_masquerade) {
        return Ok(());
    }
    with_wallet_db_write_lock("swap_receiving.recheck", || {
        let mut db = open_wallet_db_with_timeout(&db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        for account in swap_receiving::software_accounts(&db)? {
            db.recheck_swap_history(account)?;
        }
        Ok(())
    })
}
