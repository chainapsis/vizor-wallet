//! Thin application policy over the reusable swap receiving registry and recovery helpers.

pub(crate) mod receive;

use zakura_swap_receiving::{KeyId, Purpose, RefundMemo};
use zcash_client_backend::data_api::{Account as _, AccountSource, WalletRead};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::address::{Address, UnifiedAddress};
use zcash_protocol::{
    consensus::{BlockHeight, NetworkUpgrade, Parameters},
    memo::MemoBytes,
};

use super::{
    db::{
        open_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
};

pub(crate) fn require_new_address(network: WalletNetwork) -> Result<(), String> {
    if network != WalletNetwork::Main
        || cfg!(ironwood_masquerade)
        || !crate::api::sync::near_swap_privacy_enabled()
    {
        return Err(
            "Enable Private queries and NEAR swap privacy before reserving an address".into(),
        );
    }
    Ok(())
}
const RECEIVE_LOOKAHEAD: u32 =
    zcash_client_sqlite::wallet::swap_receiving::RECEIVE_GAP_LIMIT as u32;
const MAX_RESERVATION_TIP_LAG: u64 = 10;

/// Permit ordinary tip movement without treating a historical restore as ready.
/// Memo enhancement must finish because confirmed funding records advance indices.
fn reservation_scan_from(
    scanned: Option<BlockHeight>,
    known_tip: BlockHeight,
    live_tip: u64,
    pending_enhancement: bool,
) -> Result<BlockHeight, String> {
    let target = live_tip.max(u64::from(u32::from(known_tip)));
    let scanned = scanned.ok_or("Finish wallet sync before requesting a swap address")?;
    if scanned > known_tip
        || target.saturating_sub(u64::from(u32::from(scanned))) > MAX_RESERVATION_TIP_LAG
        || pending_enhancement
    {
        return Err("Finish wallet sync before requesting a swap address".into());
    }
    // Watch the unscanned tail as well as future blocks, including after reopen.
    Ok(scanned + 1)
}

fn require_software_account(db: &WalletDatabase, account: AccountUuid) -> Result<(), String> {
    let account = db
        .get_account(account)
        .map_err(|e| e.to_string())?
        .ok_or("Account not found")?;
    if !matches!(account.source(), AccountSource::Derived { .. })
        || super::keys::hardware_signer_kind(account.source()).is_some()
    {
        return Err("Swap receiving POC requires a software wallet".into());
    }
    Ok(())
}

pub(crate) fn reserve(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    refund: bool,
    live_tip: u64,
) -> Result<(String, u64), String> {
    with_wallet_db_write_lock("swap_receiving.reserve", || {
        require_new_address(network)?;
        let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let account = parse_account_uuid(account_uuid)?;
        require_software_account(&db, account)?;
        let tip = db
            .chain_height()
            .map_err(|e| e.to_string())?
            .ok_or("Sync before requesting a swap address")?;
        if !network.is_nu_active(NetworkUpgrade::Nu6_3, tip) {
            return Err("Swap receiving POC requires an active Ironwood chain".into());
        }
        let scanned = db.block_fully_scanned().map_err(|e| e.to_string())?;
        let scan_from = reservation_scan_from(
            scanned.map(|block| block.block_height()),
            tip,
            live_tip,
            refund
                && db
                    .swap_refund_memos_pending(account)
                    .map_err(|e| e.to_string())?,
        )?;
        db.recover_swap_refund_memos(account)
            .map_err(|e| e.to_string())?;
        let key = db
            .reserve_swap_receiving_key(
                account,
                if refund {
                    Purpose::Refund
                } else {
                    Purpose::Receive
                },
                scan_from,
            )
            .map_err(|e| e.to_string())?;
        let address = Address::Unified(
            UnifiedAddress::from_receivers(Some(key.receiver()), None, None)
                .ok_or("Invalid swap receiver")?,
        )
        .to_zcash_address(&network)
        .to_string();
        Ok((address, key.key_id().index()))
    })
}

/// Called under the wallet write lock before planning more scan work.
/// Refund and incoming-address discovery always use PIR, independently of both
/// privacy switches. Only new address issuance is opt-in.
pub(crate) fn maintain_recovery(
    db: &mut WalletDatabase,
    network: WalletNetwork,
) -> Result<(), String> {
    if cfg!(ironwood_masquerade) {
        return Ok(());
    }
    let Some(activation) = network.activation_height(NetworkUpgrade::Nu6_3) else {
        return Ok(());
    };
    for account in db.get_account_ids().map_err(|e| e.to_string())? {
        let details = db
            .get_account(account)
            .map_err(|e| e.to_string())?
            .ok_or("Account not found")?;
        if !matches!(details.source(), AccountSource::Derived { .. })
            || super::keys::hardware_signer_kind(details.source()).is_some()
        {
            continue;
        }
        // A note found later through the directory still needs its spend history,
        // even when both privacy switches were off during ordinary scanning.
        db.enable_private_swap_recovery(account)
            .map_err(|e| e.to_string())?;
        let Some(scanned) = db.block_fully_scanned().map_err(|e| e.to_string())? else {
            continue;
        };
        if Some(scanned.block_height()) != db.chain_height().map_err(|e| e.to_string())?
            || scanned.block_height() < activation
        {
            continue;
        }
        db.recover_swap_refund_memos(account)
            .map_err(|e| e.to_string())?;
        let birthday = db
            .get_account_birthday(account)
            .map_err(|e| e.to_string())?;
        db.maintain_swap_receive_lookahead(account, RECEIVE_LOOKAHEAD, birthday.max(activation))
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Called after private discovery, under the wallet write lock. The library checks
/// every completion barrier again before releasing temporary spend evidence.
pub(crate) fn finish_nullifier_recovery(
    db: &mut WalletDatabase,
    through: zakura_swap_receiving::lifecycle::ChainAnchor,
) -> Result<(), String> {
    for account in db.get_account_ids().map_err(|e| e.to_string())? {
        let details = db
            .get_account(account)
            .map_err(|e| e.to_string())?
            .ok_or("Account not found")?;
        if matches!(details.source(), AccountSource::Derived { .. })
            && super::keys::hardware_signer_kind(details.source()).is_none()
        {
            db.finish_swap_nullifier_recovery(account, through, RECEIVE_LOOKAHEAD)
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Apply a provider status to the registered local address. Older ordinary wallet
/// addresses are ignored. Address matching also migrates existing activity records
/// without depending on a newly added index field in secure storage.
pub(crate) fn observe_operation(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    operation: &str,
    address: &str,
    status: &str,
    observed_at: i64,
) -> Result<(), String> {
    with_wallet_db_write_lock("swap_receiving.operation", || {
        let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let account = parse_account_uuid(account_uuid)?;
        require_software_account(&db, account)?;
        if db
            .has_swap_receive_quote(account, operation)
            .map_err(|e| e.to_string())?
        {
            return Ok(());
        }
        let Some(Address::Unified(address)) = Address::decode(&network, address) else {
            return Ok(());
        };
        let Some(receiver) = address.orchard() else {
            return Ok(());
        };
        let Some(key) = db
            .get_swap_receiving_key_for_receiver(account, receiver)
            .map_err(|e| e.to_string())?
        else {
            return Ok(());
        };
        if let Some(status) =
            zakura_swap_receiving::lifecycle::near_status(key.key_id().purpose(), status)
        {
            db.record_swap_observation(account, key.key_id(), operation, status, observed_at, true)
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    })
}

/// Funding uses the reserved key and a normal internal memo, never a payout OVK.
pub(crate) fn funding_memo(
    db: &WalletDatabase,
    network: WalletNetwork,
    account: AccountUuid,
    index: u64,
    deposit: &str,
) -> Result<MemoBytes, String> {
    require_software_account(db, account)?;
    let key_id = KeyId::new(Purpose::Refund, index);
    if !db
        .get_swap_receiving_key(account, key_id)
        .map_err(|e| e.to_string())?
        .is_some_and(|key| key.advances_allocation())
    {
        return Err("Refund key was not reserved by this account".into());
    }
    let memo =
        RefundMemo::new(network.network_type(), index, deposit).map_err(|e| e.to_string())?;
    MemoBytes::from_bytes(&memo.encode()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use secrecy::SecretVec;
    use zcash_client_backend::data_api::WalletWrite;
    use zcash_protocol::consensus::BlockHeight;

    #[test]
    fn reservations_tolerate_tip_movement_but_require_recovery_progress() {
        let height = BlockHeight::from_u32;
        // A fresh RPC tip can be ahead of the DB without a quote changing the DB tip.
        assert_eq!(
            reservation_scan_from(Some(height(100)), height(100), 110, false).unwrap(),
            height(101)
        );
        // Use the newer DB tip if the RPC response arrived after another sync update.
        assert_eq!(
            reservation_scan_from(Some(height(100)), height(110), 105, false).unwrap(),
            height(101)
        );
        assert!(reservation_scan_from(Some(height(100)), height(100), 111, false).is_err());
        assert!(reservation_scan_from(Some(height(100)), height(111), 100, false).is_err());
        assert!(reservation_scan_from(None, height(100), 100, false).is_err());
        assert!(reservation_scan_from(Some(height(100)), height(100), 100, true).is_err());
        assert!(reservation_scan_from(Some(height(101)), height(100), 100, false).is_err());
    }

    #[test]
    fn funding_memo_requires_reserved_refund_key_after_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Regtest;
        super::super::network::configure_regtest_nu6_3_activation_height(100).unwrap();
        let (uuid, deposit) = super::super::keys::init_db_and_create_account(
            path,
            network,
            &SecretVec::new(vec![0; 32]),
            Some(100),
            "POC",
        )
        .unwrap();
        let account = parse_account_uuid(&uuid).unwrap();
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        assert!(funding_memo(&db, network, account, 0, &deposit).is_err());
        db.reserve_swap_receiving_key(account, Purpose::Receive, BlockHeight::from_u32(100))
            .unwrap();
        // An incoming reservation cannot authorize a refund record at the same index.
        assert!(funding_memo(&db, network, account, 0, &deposit).is_err());
        db.reserve_swap_receiving_key(account, Purpose::Refund, BlockHeight::from_u32(100))
            .unwrap();
        drop(db);
        let db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        let memo = funding_memo(&db, network, account, 0, &deposit).unwrap();
        let decoded = RefundMemo::decode(network.network_type(), memo.as_array())
            .unwrap()
            .unwrap();
        assert_eq!(decoded.index(), 0);
        assert_eq!(decoded.deposit_address(), deposit);
        assert!(funding_memo(&db, network, account, 1, &deposit).is_err());
        assert!(funding_memo(&db, network, account, 0, "not an address").is_err());
    }

    #[test]
    fn restore_prepares_pir_discovery_with_both_settings_off() {
        assert!(!crate::api::sync::enhance_pir_enabled());
        assert!(!crate::api::sync::near_swap_privacy_enabled());
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Regtest;
        super::super::network::configure_regtest_nu6_3_activation_height(100).unwrap();
        let (uuid, _) = super::super::keys::init_db_and_create_account(
            path,
            network,
            &SecretVec::new(vec![0; 32]),
            Some(100),
            "POC",
        )
        .unwrap();
        let account = parse_account_uuid(&uuid).unwrap();
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        db.update_chain_tip(BlockHeight::from_u32(110)).unwrap();
        maintain_recovery(&mut db, network).unwrap();
        assert!(db.get_swap_receiving_keys(account).unwrap().is_empty());
        // Model completed ordinary scanning. Real note discovery and replay are
        // exercised by the shared library's compact-block recovery tests.
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute_batch(
            "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(110,zeroblob(32),0,X'000000');
             DELETE FROM scan_queue;
             INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(100,111,10);",
        ).unwrap();
        maintain_recovery(&mut db, network).unwrap();
        let keys = db.get_swap_receiving_keys(account).unwrap();
        assert_eq!(keys.len(), RECEIVE_LOOKAHEAD as usize);
        assert!(keys.iter().all(|key| !key.advances_allocation()));
        assert!(db
            .get_swap_scan_window(BlockHeight::from_u32(111))
            .unwrap()
            .0
            .is_empty());
        assert_eq!(
            db.block_fully_scanned().unwrap().unwrap().block_height(),
            BlockHeight::from_u32(110)
        );
        assert!(db
            .get_swap_scan_window(BlockHeight::from_u32(100))
            .unwrap()
            .0
            .is_empty());
        drop(db);
        let mut reopened =
            open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        maintain_recovery(&mut reopened, network).unwrap();
        assert_eq!(
            reopened.get_swap_receiving_keys(account).unwrap().len(),
            RECEIVE_LOOKAHEAD as usize
        );
        let error = reserve(path, network, &uuid, true, 110).unwrap_err();
        assert!(error.contains("Enable Private queries"), "{error}");
    }
}
