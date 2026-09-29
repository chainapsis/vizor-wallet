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
    Recovery,
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
            P::Recovery => ReceiveErrorCode::Recovery,
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
impl From<receiver_pir::Error> for ReceiveError {
    fn from(e: receiver_pir::Error) -> Self {
        e.to_string().into()
    }
}
impl From<receiver_directory::Error> for ReceiveError {
    fn from(e: receiver_directory::Error) -> Self {
        e.to_string().into()
    }
}

impl From<crate::wallet::sync_engine::SyncError> for ReceiveError {
    fn from(e: crate::wallet::sync_engine::SyncError) -> Self {
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

pub(crate) async fn prepare(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    live_tip: u64,
    lightwalletd_url: &str,
) -> Result<ReceiveReservation, ReceiveError> {
    require_new_address(network)?;
    let reservation = with_db(path, network, uuid, |db, account| {
        require_software_account(db, account)?;
        let tip = db
            .chain_height()
            .map_err(ReceiveError::from)?
            .ok_or("Sync before requesting a swap address")?;
        reservation_scan_from(
            db.block_fully_scanned()
                .map_err(ReceiveError::from)?
                .map(|b| b.block_height()),
            tip,
            live_tip,
            false,
        )?;
        maintain_recovery(db, network)?;
        let birthday = db
            .get_account_birthday(account)
            .map_err(ReceiveError::from)?;
        let activation = network
            .activation_height(NetworkUpgrade::Nu6_3)
            .ok_or("Ironwood is inactive")?;
        db.prepare_swap_receive_reservation(account, now()?, birthday.max(activation))
            .map_err(ReceiveError::from)
    })?;
    check(path, network, uuid, reservation.id, lightwalletd_url, true).await?;
    Ok(reservation)
}

async fn check(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    id: i64,
    lightwalletd_url: &str,
    reuse: bool,
) -> Result<zakura_swap_receiving::lifecycle::ChainAnchor, ReceiveError> {
    if network != WalletNetwork::Main {
        return Err("Private receive verification requires mainnet".into());
    }
    check_inner(path, network, uuid, id, lightwalletd_url, reuse).await
}

async fn check_inner(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    id: i64,
    lightwalletd_url: &str,
    reuse: bool,
) -> Result<zakura_swap_receiving::lifecycle::ChainAnchor, ReceiveError> {
    use receiver_directory::Receiver;
    use std::num::NonZeroU32;
    let (account, key, verified) = with_db(path, network, uuid, |db, account| {
        let key = db
            .swap_receive_reservation(account, id)
            .map_err(ReceiveError::from)?
            .key;
        let verified = if reuse {
            db.verified_swap_receive_reservation(account, id)
                .map_err(ReceiveError::from)?
        } else {
            None
        };
        Ok((account, key, verified))
    })?;
    if let Some(verified) = verified {
        return Ok(verified);
    }
    let should_exit = || false;
    let transport = super::super::sync_engine::swap_private::SwapTransport::new(&should_exit);
    let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
    let (client, accepted, anchor) =
        super::super::sync_engine::swap_private::receiver_client(&mut db, network, &transport, 1)
            .await?;
    // Avoid a receiver query while the publication is too stale to verify safely.
    db.swap_receive_verification_tail(account, id, anchor)
        .map_err(ReceiveError::from)?;
    let payments = client
        .lookup(
            Receiver::from_bytes(key.receiver().to_raw_address_bytes())
                .map_err(ReceiveError::from)?,
            NonZeroU32::new(32).unwrap(),
            accepted,
        )
        .await
        .map_err(ReceiveError::from)?;
    if !payments.is_empty() {
        with_wallet_db_write_lock("swap_receive.found", || {
            db.request_swap_receive_recheck(account, key.key_id(), anchor)
                .map_err(ReceiveError::from)
        })?;
        return Err(
            zcash_client_sqlite::wallet::swap_receiving::ReservationPolicy::Recovery.into(),
        );
    }
    let tail = db
        .swap_receive_verification_tail(account, id, anchor)
        .map_err(ReceiveError::from)?;
    let blocks = if let Some(tail) = tail {
        super::super::sync_engine::download_swap_verification_tail(lightwalletd_url, network, tail)
            .await
            .map_err(ReceiveError::from)?
    } else {
        Vec::new()
    };
    with_wallet_db_write_lock("swap_receive.check", || {
        if !db
            .verify_swap_receive_history(account, id, anchor, &blocks)
            .map_err(ReceiveError::from)?
        {
            return Err(
                zcash_client_sqlite::wallet::swap_receiving::ReservationPolicy::Recovery.into(),
            );
        }
        db.verified_swap_receive_reservation(account, id)
            .map_err(ReceiveError::from)?
            .ok_or_else(|| {
                zcash_client_sqlite::wallet::swap_receiving::ReservationPolicy::Coverage.into()
            })
    })
}

pub(crate) async fn reap(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    lightwalletd_url: &str,
) -> Result<u32, ReceiveError> {
    with_db(path, network, uuid, |db, account| {
        db.close_received_swap_reservations(account, now()?)
            .map_err(ReceiveError::from)
    })?;
    let candidates = with_db(path, network, uuid, |db, account| {
        db.swap_receive_reclaim_candidates(account, now()?)
            .map_err(ReceiveError::from)
    })?;
    let mut reclaimed = 0;
    for id in candidates {
        // Reclamation always obtains a fresh directory result. Cached draft checks
        // cannot release an old reservation. Failures retain the reservation.
        match check(path, network, uuid, id, lightwalletd_url, false).await {
            Ok(anchor) => {
                if with_db(path, network, uuid, |db, account| {
                    db.reclaim_swap_receive_reservation(account, id, now()?, anchor)
                        .map_err(ReceiveError::from)
                })? {
                    reclaimed += 1;
                }
            }
            Err(error) => log::info!("swap_receive: reconciliation deferred: {error}"),
        }
    }
    Ok(reclaimed)
}
