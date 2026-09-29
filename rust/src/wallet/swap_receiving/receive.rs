//! Incoming address lifecycle. Provider polling stays in Dart; allocation is durable in Rust.
use super::*;
use zcash_client_sqlite::wallet::swap_receiving::ReceiveReservation;

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
    action: impl FnOnce(&mut WalletDatabase, AccountUuid) -> Result<T, String>,
) -> Result<T, String> {
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
) -> Result<ReceiveReservation, String> {
    require_new_address(network)?;
    let reservation = with_db(path, network, uuid, |db, account| {
        require_software_account(db, account)?;
        let tip = db
            .chain_height()
            .map_err(|e| e.to_string())?
            .ok_or("Sync before requesting a swap address")?;
        reservation_scan_from(
            db.block_fully_scanned()
                .map_err(|e| e.to_string())?
                .map(|b| b.block_height()),
            tip,
            live_tip,
            false,
        )?;
        maintain_recovery(db, network)?;
        let birthday = db
            .get_account_birthday(account)
            .map_err(|e| e.to_string())?;
        let activation = network
            .activation_height(NetworkUpgrade::Nu6_3)
            .ok_or("Ironwood is inactive")?;
        db.prepare_swap_receive_reservation(account, now()?, birthday.max(activation))
            .map_err(|e| e.to_string())
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
) -> Result<zakura_swap_receiving::lifecycle::ChainAnchor, String> {
    use futures::Future;
    if network != WalletNetwork::Main {
        return Err("Private receive verification requires mainnet".into());
    }
    if crate::network_privacy::is_tor_desired() {
        return Err("Private receive verification requires Tor off in this test build".into());
    }
    let lease = crate::network_privacy::DirectRouteLease::new();
    let phase = async {
        check_inner(path, network, uuid, id, lightwalletd_url, reuse)
            .await
            .map_err(std::io::Error::other)
    };
    futures::pin_mut!(phase);
    futures::future::poll_fn(|cx| lease.poll(cx, |cx| phase.as_mut().poll(cx)))
        .await
        .map_err(|e| e.to_string())
}

async fn check_inner(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    id: i64,
    lightwalletd_url: &str,
    reuse: bool,
) -> Result<zakura_swap_receiving::lifecycle::ChainAnchor, String> {
    use receiver_directory::Receiver;
    use std::{num::NonZeroU32, time::Duration};
    let (account, key, verified) = with_db(path, network, uuid, |db, account| {
        let key = db
            .swap_receive_reservation(account, id)
            .map_err(|e| e.to_string())?
            .key;
        let verified = if reuse {
            db.verified_swap_receive_reservation(account, id)
                .map_err(|e| e.to_string())?
        } else {
            None
        };
        Ok((account, key, verified))
    })?;
    if let Some(verified) = verified {
        return Ok(verified);
    }
    let http = reqwest::Client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;
    let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
    let (client, accepted, anchor) =
        super::super::sync_engine::swap_private::receiver_client(&mut db, network, http).await?;
    // Avoid a receiver query while the publication is too stale to verify safely.
    db.swap_receive_verification_tail(account, id, anchor)
        .map_err(|e| e.to_string())?;
    let payments = client
        .lookup(
            Receiver::from_bytes(key.receiver().to_raw_address_bytes())
                .map_err(|e| e.to_string())?,
            NonZeroU32::new(32).unwrap(),
            accepted,
        )
        .await
        .map_err(|e| e.to_string())?;
    if !payments.is_empty() {
        with_wallet_db_write_lock("swap_receive.found", || {
            db.request_swap_receive_recheck(account, key.key_id(), anchor)
                .map_err(|e| e.to_string())
        })?;
        return Err("SWAP_RECEIVE_RECOVERY: A payment was found at this address. Finish receive recovery before requesting another quote.".into());
    }
    let tail = db
        .swap_receive_verification_tail(account, id, anchor)
        .map_err(|e| e.to_string())?;
    let blocks = if let Some(tail) = tail {
        super::super::sync_engine::download_swap_verification_tail(lightwalletd_url, network, tail)
            .await
            .map_err(|e| e.to_string())?
    } else {
        Vec::new()
    };
    with_wallet_db_write_lock("swap_receive.check", || {
        if !db
            .verify_swap_receive_history(account, id, anchor, &blocks)
            .map_err(|e| e.to_string())?
        {
            return Err("SWAP_RECEIVE_RECOVERY: A recent payment was found. Finish receive recovery before requesting another quote.".into());
        }
        db.verified_swap_receive_reservation(account, id)
            .map_err(|e| e.to_string())?
            .ok_or_else(|| {
                "SWAP_RECEIVE_COVERAGE: Receive-address coverage changed. Try again shortly.".into()
            })
    })
}

pub(crate) async fn reap(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    lightwalletd_url: &str,
) -> Result<u32, String> {
    with_db(path, network, uuid, |db, account| {
        db.close_received_swap_reservations(account, now()?)
            .map_err(|e| e.to_string())
    })?;
    let candidates = with_db(path, network, uuid, |db, account| {
        db.swap_receive_reclaim_candidates(account, now()?)
            .map_err(|e| e.to_string())
    })?;
    let mut reclaimed = 0;
    for id in candidates {
        // Reclamation always obtains a fresh directory result. Cached draft checks
        // cannot release an old reservation. Failures retain the reservation.
        match check(path, network, uuid, id, lightwalletd_url, false).await {
            Ok(anchor) => {
                if with_db(path, network, uuid, |db, account| {
                    db.reclaim_swap_receive_reservation(account, id, now()?, anchor)
                        .map_err(|e| e.to_string())
                })? {
                    reclaimed += 1;
                }
            }
            Err(error) => log::info!("swap_receive: reconciliation deferred: {error}"),
        }
    }
    Ok(reclaimed)
}
