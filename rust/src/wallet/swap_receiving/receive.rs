//! Incoming address lifecycle. Provider polling stays in Dart; allocation is durable in Rust.
use super::*;
use zcash_client_sqlite::wallet::swap_receiving::ReceiveReservation;

/// Stable UI classification. Messages are display text, never a parsing protocol.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReceiveErrorCode {
    Gap,
    Limit,
    Stale,
    Coverage,
    Other,
}
#[derive(Clone, Debug)]
pub struct ReceiveError {
    pub code: ReceiveErrorCode,
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
        Self {
            code: ReceiveErrorCode::Other,
            message,
        }
    }
}
impl From<&str> for ReceiveError {
    fn from(message: &str) -> Self {
        message.to_owned().into()
    }
}
impl From<zcash_client_sqlite::wallet::swap_receiving::ReservationPolicy> for ReceiveError {
    fn from(policy: zcash_client_sqlite::wallet::swap_receiving::ReservationPolicy) -> Self {
        use zcash_client_sqlite::wallet::swap_receiving::ReservationPolicy as P;
        let code = match policy {
            P::Gap => ReceiveErrorCode::Gap,
            P::Limit => ReceiveErrorCode::Limit,
            P::Stale => ReceiveErrorCode::Stale,
            P::Coverage => ReceiveErrorCode::Coverage,
            P::Unreadable => ReceiveErrorCode::Other,
        };
        Self {
            code,
            message: policy.to_string(),
        }
    }
}
impl From<zcash_client_sqlite::wallet::swap_receiving::Error> for ReceiveError {
    fn from(error: zcash_client_sqlite::wallet::swap_receiving::Error) -> Self {
        if let zcash_client_sqlite::wallet::swap_receiving::Error::ReservationPolicy(policy) = error
        {
            policy.into()
        } else {
            error.to_string().into()
        }
    }
}
impl From<zcash_client_sqlite::error::SqliteClientError> for ReceiveError {
    fn from(e: zcash_client_sqlite::error::SqliteClientError) -> Self {
        e.to_string().into()
    }
}
pub(crate) fn now() -> Result<i64, String> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs()
        .try_into()
        .map_err(|_| "Clock overflow".into())
}

pub(crate) fn with_db<T>(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    action: impl FnOnce(&mut WalletDatabase, AccountUuid) -> Result<T, ReceiveError>,
) -> Result<T, ReceiveError> {
    with_wallet_db_write_lock("swap_receive.reservation", || {
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let account = parse_account_uuid(uuid)?;
        action(&mut db, account)
    })
}

/// Resumes the account's draft or reserves the lowest eligible receive index.
///
/// The key is scanned from the next unscanned block until it closes. Quoting
/// later requires that scanning to reach the tip without finding a payment.
pub(crate) fn prepare(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    live_tip: u64,
) -> Result<ReceiveReservation, ReceiveError> {
    require_new_address(network)?;
    with_db(path, network, uuid, |db, account| {
        require_software_account(db, account)?;
        db.prepare_swap_receive_reservation(account, now()?, network_tip(live_tip)?)
            .map_err(ReceiveError::from)
    })
}

/// Closes settled paid reservations and reclaims abandoned unpaid ones whose
/// addresses local scanning shows are still empty. Returns the number reclaimed.
pub(crate) fn reap(path: &str, network: WalletNetwork, uuid: &str) -> Result<u32, ReceiveError> {
    with_db(path, network, uuid, |db, account| {
        db.reap_swap_receive_reservations(account, now()?)
            .map_err(ReceiveError::from)
    })
}
