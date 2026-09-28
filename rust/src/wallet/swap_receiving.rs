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

/// Existing swap keys still need recovery when new address issuance is disabled.
pub(crate) fn private_recovery_enabled() -> bool {
    crate::api::sync::enhance_pir_enabled()
}

pub(crate) fn require_new_address(network: WalletNetwork) -> Result<(), String> {
    if network != WalletNetwork::Main
        || cfg!(ironwood_masquerade)
        || !crate::api::sync::near_swap_privacy_enabled()
    {
        return Err(
            "Enable Private queries and NEAR swap privacy before reserving an address".into(),
        );
    }
    if crate::network_privacy::is_tor_desired() {
        return Err("Private swap recovery is not available over Tor yet".into());
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
/// Private restore derives keys for PIR; local operation records bound compact scanning.
pub(crate) fn maintain_recovery(
    db: &mut WalletDatabase,
    network: WalletNetwork,
) -> Result<(), String> {
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
        let new_addresses = crate::api::sync::near_swap_privacy_enabled();
        let has_keys = !db
            .get_swap_receiving_keys(account)
            .map_err(|e| e.to_string())?
            .is_empty();
        if private_recovery_enabled() && (new_addresses || has_keys) {
            db.enable_private_swap_recovery(account)
                .map_err(|e| e.to_string())?;
            // Finish ordinary scanning before adding historical directory work.
            let scanned = db
                .block_fully_scanned()
                .map_err(|e| e.to_string())?
                .map(|b| b.block_height());
            if scanned.is_none() || scanned != db.chain_height().map_err(|e| e.to_string())? {
                continue;
            }
        }
        db.recover_swap_refund_memos(account)
            .map_err(|e| e.to_string())?;
        if !new_addresses
            && db
                .get_swap_receiving_keys(account)
                .map_err(|e| e.to_string())?
                .is_empty()
        {
            continue;
        }
        let birthday = db
            .get_account_birthday(account)
            .map_err(|e| e.to_string())?;
        db.maintain_swap_receive_lookahead(account, RECEIVE_LOOKAHEAD, birthday.max(activation))
            .map_err(|e| e.to_string())?;
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
    terminal: bool,
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
            .get_swap_receiving_keys(account)
            .map_err(|e| e.to_string())?
            .into_iter()
            .find(|key| key.receiver() == *receiver)
        else {
            return Ok(());
        };
        let height = db
            .chain_height()
            .map_err(|e| e.to_string())?
            .ok_or("Sync before tracking a swap")?;
        db.observe_swap_operation(account, key.key_id(), operation, terminal, height)
            .map_err(|e| e.to_string())
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
        .get_swap_receiving_keys(account)
        .map_err(|e| e.to_string())?
        .iter()
        .any(|key| key.key_id() == key_id && key.advances_allocation())
    {
        return Err("Refund key was not reserved by this account".into());
    }
    let memo =
        RefundMemo::new(network.network_type(), index, deposit).map_err(|e| e.to_string())?;
    MemoBytes::from_bytes(&memo.encode()).map_err(|e| e.to_string())
}

#[cfg(all(test, feature = "swap-receiving-poc"))]
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
    fn default_setting_does_not_create_lookahead_or_allow_reservations() {
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
        let keys = db.get_swap_receiving_keys(account).unwrap();
        assert!(keys.is_empty());
        assert!(keys.iter().all(|key| !key.advances_allocation()));
        let error = reserve(path, network, &uuid, true, 110).unwrap_err();
        assert!(error.contains("Enable Private queries"), "{error}");
    }
}
