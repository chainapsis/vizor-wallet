//! Thin application policy over the reusable swap receiving registry and recovery helpers.

pub(crate) mod receive;

use zakura_swap_receiving::lifecycle::{near_observation, ProviderStatus};
use zcash_client_backend::data_api::{
    transparent_ledger::ChainPoint, Account as _, AccountSource, WalletRead,
};
use zcash_client_sqlite::{wallet::swap_receiving::RegisteredKey, AccountUuid};
use zcash_keys::address::{Address, UnifiedAddress};
use zcash_protocol::{
    consensus::{BlockHeight, NetworkUpgrade, Parameters},
    value::Zatoshis,
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
/// The network tip a quote flow fetched, which address issuance checks scanning against.
pub(crate) fn network_tip(live_tip: u64) -> Result<BlockHeight, String> {
    u32::try_from(live_tip)
        .map(BlockHeight::from_u32)
        .map_err(|_| "Invalid chain tip".into())
}

/// Borrows a bridged provider status for the library. Unparseable amounts are
/// treated as unreported.
pub(crate) fn provider_status(
    status: &crate::api::swap_receive::SwapProviderStatus,
) -> ProviderStatus<'_> {
    let amount = |value: &Option<String>| {
        value
            .as_deref()
            .and_then(|v| v.parse::<u64>().ok())
            .and_then(|v| Zatoshis::from_u64(v).ok())
    };
    ProviderStatus {
        status: &status.status,
        swap_type: status.swap_type.as_deref(),
        refunded_amount: amount(&status.refunded_amount),
        amount_out: amount(&status.amount_out),
        deadline: status.deadline_seconds,
    }
}

/// Whether `account` is a software account: seed-derived, without a hardware signer.
fn is_software(db: &WalletDatabase, account: AccountUuid) -> Result<bool, String> {
    let account = db
        .get_account(account)
        .map_err(|e| e.to_string())?
        .ok_or("Account not found")?;
    Ok(matches!(account.source(), AccountSource::Derived { .. })
        && super::keys::hardware_signer_kind(account.source()).is_none())
}

/// Fails unless `account` is a software account (see [`is_software`]).
pub(crate) fn require_software_account(
    db: &WalletDatabase,
    account: AccountUuid,
) -> Result<(), String> {
    if !is_software(db, account)? {
        return Err("Swap receiving requires a software wallet".into());
    }
    Ok(())
}

/// The software accounts that can spend with swap keys.
pub(crate) fn software_accounts(db: &WalletDatabase) -> Result<Vec<AccountUuid>, String> {
    let mut accounts = Vec::new();
    for account in db.get_account_ids().map_err(|e| e.to_string())? {
        if is_software(db, account)? {
            accounts.push(account);
        }
    }
    Ok(accounts)
}

/// Encodes `key`'s receiver as a unified address with no other receiver.
pub(crate) fn encode_address(
    key: &RegisteredKey,
    network: WalletNetwork,
) -> Result<String, String> {
    let address = UnifiedAddress::from_receivers(Some(key.receiver()), None, None)
        .ok_or("Invalid swap receiver")?;
    Ok(Address::Unified(address)
        .to_zcash_address(&network)
        .to_string())
}

/// Reserves the next refund key and returns its address and index.
pub(crate) fn reserve(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    live_tip: u64,
) -> Result<(String, u64), String> {
    receive::with_db(db_path, network, account_uuid, |db, account| {
        require_new_address(network)?;
        require_software_account(db, account)?;
        let tip = db
            .chain_height()
            .map_err(|e| e.to_string())?
            .ok_or("Sync before requesting a swap address")?;
        if !network.is_nu_active(NetworkUpgrade::Nu6_3, tip) {
            return Err("Swap receiving requires an active Ironwood chain".into());
        }
        let key = db
            .reserve_swap_refund_key(account, network_tip(live_tip)?)
            .map_err(|e| e.to_string())?;
        Ok((encode_address(&key, network)?, key.key_id().index()))
    })
}

/// Called under the wallet write lock before planning more scan work.
/// Restore sweeps run independently of both privacy switches. Only new address
/// issuance is opt-in.
pub(crate) fn maintain_recovery(
    db: &mut WalletDatabase,
    network: WalletNetwork,
) -> Result<(), String> {
    if cfg!(ironwood_masquerade) || network.activation_height(NetworkUpgrade::Nu6_3).is_none() {
        return Ok(());
    }
    for account in software_accounts(db)? {
        db.maintain_swap_receiving(account)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Stops scanning finished swap keys, under the wallet write lock, once sync has
/// scanned to `tip`, the chain tip it revalidated this session.
pub(crate) fn close_finished_keys(db: &mut WalletDatabase, tip: BlockHeight) -> Result<(), String> {
    if cfg!(ironwood_masquerade) {
        return Ok(());
    }
    let now = receive::now()?;
    for account in software_accounts(db)? {
        db.close_finished_swap_keys(account, now, tip)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Called after private discovery, under the wallet write lock. The library checks
/// every completion barrier again before releasing temporary spend evidence.
pub(crate) fn finish_nullifier_recovery(
    db: &mut WalletDatabase,
    through: ChainPoint,
) -> Result<(), String> {
    for account in software_accounts(db)? {
        db.finish_swap_nullifier_recovery(account, through)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Queues one receiver-directory sweep of every closed swap key in the wallet at
/// `db_path`, as a seed restore does, and returns how many were queued.
pub(crate) fn recheck_history(db_path: &str, network: WalletNetwork) -> Result<usize, String> {
    // Only mainnet runs restore sweeps (see `sync_engine::swap_private`).
    if network != WalletNetwork::Main || cfg!(ironwood_masquerade) {
        return Ok(0);
    }
    with_wallet_db_write_lock("swap_receiving.recheck", || {
        let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let mut queued = 0;
        for account in software_accounts(&db)? {
            queued += db
                .recheck_swap_history(account)
                .map_err(|e| e.to_string())?;
        }
        Ok(queued)
    })
}

/// Applies a provider status to the swap key behind `address`, a refund address.
/// Incoming quotes record their statuses through their reservation instead.
/// Addresses without a swap key and unrecognized statuses are ignored.
pub(crate) fn observe_operation(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    operation: &str,
    address: &str,
    status: &crate::api::swap_receive::SwapProviderStatus,
    observed_at: i64,
) -> Result<(), String> {
    receive::with_db(db_path, network, account_uuid, |db, account| {
        require_software_account(db, account)?;
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
        if let Some(observation) =
            near_observation(key.key_id().purpose(), &provider_status(status))
        {
            db.record_swap_observation(account, key.key_id(), operation, observation, observed_at)
                .map_err(|e| e.to_string())?;
        }
        Ok(())
    })
}

/// Binds an accepted refund quote's deposit address to its reserved refund key,
/// before the quote is shown. Funding requires this record.
pub(crate) fn record_refund_quote(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    index: u64,
    deposit: &str,
    deadline: i64,
) -> Result<(), String> {
    // Only software accounts have reserved refund keys, which the library requires.
    receive::with_db(db_path, network, account_uuid, |db, account| {
        db.record_swap_refund_quote(account, index, deposit, deadline, receive::now()?)
            .map_err(|e| e.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use secrecy::SecretVec;
    use transparent::address::TransparentAddress;
    use zakura_swap_receiving::RefundMemo;
    use zcash_client_backend::data_api::WalletWrite;
    use zcash_client_sqlite::wallet::swap_receiving::RECEIVE_GAP_LIMIT;

    /// Records `blocks` and marks the scan queue scanned from the birthday to `tip`.
    fn mark_scanned(path: &str, blocks: impl IntoIterator<Item = u32>, tip: u32) {
        let conn = rusqlite::Connection::open(path).unwrap();
        // Key closing reads the tip's block time, so the blocks are stamped now.
        let now = receive::now().unwrap();
        for h in blocks {
            conn.execute(
                "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(?1,?2,?3,X'000000')",
                rusqlite::params![h, [h as u8; 32], now],
            )
            .unwrap();
        }
        conn.execute("DELETE FROM scan_queue", []).unwrap();
        conn.execute(
            "INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(100,?1,10)",
            [tip + 1],
        )
        .unwrap();
    }

    #[test]
    fn keys_close_only_after_offline_blocks_are_scanned() {
        use zakura_swap_receiving::lifecycle::{CompletionPolicy, Observation, OperationStatus};
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
        mark_scanned(path, [110], 110);
        let key = db
            .reserve_swap_refund_key(account, BlockHeight::from_u32(111))
            .unwrap()
            .key_id();
        // Storing the swap's funding transaction starts the key; model that here.
        rusqlite::Connection::open(path)
            .unwrap()
            .execute(
                "UPDATE ironwood_receiving_keys SET active_from = 111 WHERE purpose = 0",
                [],
            )
            .unwrap();
        // The quote's limit passed while the app was closed.
        let deadline = receive::now().unwrap() - CompletionPolicy::default().limit_secs - 60;
        let pending = Observation {
            status: OperationStatus::Active,
            deadline: Some(deadline),
        };
        db.record_swap_observation(account, key, "deposit", pending, deadline - 60)
            .unwrap();
        let scanning = |db: &WalletDatabase| {
            db.get_swap_scanning_keys()
                .unwrap()
                .iter()
                .any(|k| k.key_id() == key)
        };
        // Sync start runs this before it stores the new tip.
        maintain_recovery(&mut db, network).unwrap();
        let tip = BlockHeight::from_u32(120);
        db.update_chain_tip(tip).unwrap();
        close_finished_keys(&mut db, tip).unwrap();
        assert!(scanning(&db));
        mark_scanned(path, 111..=120, 120);
        close_finished_keys(&mut db, tip).unwrap();
        assert!(!scanning(&db));
    }

    #[test]
    fn funding_memo_requires_a_recorded_refund_quote_after_reopen() {
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
        let deposit = Address::Transparent(TransparentAddress::PublicKeyHash([7; 20]));
        let deposit = deposit.encode(&network);
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        let tip = BlockHeight::from_u32(100);
        db.update_chain_tip(tip).unwrap();
        mark_scanned(path, [100], 100);
        let index = db
            .reserve_swap_refund_key(account, tip)
            .unwrap()
            .key_id()
            .index();
        drop(db);
        let deadline = receive::now().unwrap() + 60 * 60;
        let funding = |deposit: &str| {
            let db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
            db.swap_funding_memo(account, index, deposit)
        };
        assert!(funding(&deposit).is_err());
        record_refund_quote(path, network, &uuid, index, &deposit, deadline).unwrap();
        let memo = funding(&deposit).unwrap();
        assert_eq!(
            RefundMemo::decode(memo.as_array())
                .unwrap()
                .unwrap()
                .index(),
            index
        );
        let mainnet = Address::Transparent(TransparentAddress::PublicKeyHash([7; 20]))
            .encode(&WalletNetwork::Main);
        let error =
            record_refund_quote(path, network, &uuid, index, &mainnet, deadline).unwrap_err();
        assert!(error.contains("invalid swap deposit address"), "{error}");
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
        assert_eq!(keys.len() as u64, RECEIVE_GAP_LIMIT);
        assert!(keys.iter().all(|key| !key.advances_allocation()));
        // Restored lookahead keys wait for a directory sweep; they are not scanned.
        assert!(db.get_swap_scanning_keys().unwrap().is_empty());
        assert_eq!(
            db.block_fully_scanned().unwrap().unwrap().block_height(),
            BlockHeight::from_u32(110)
        );
        drop(db);
        let mut reopened =
            open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        maintain_recovery(&mut reopened, network).unwrap();
        assert_eq!(
            reopened.get_swap_receiving_keys(account).unwrap().len() as u64,
            RECEIVE_GAP_LIMIT
        );
        let error = reserve(path, network, &uuid, 110).unwrap_err();
        assert!(error.contains("Enable Private queries"), "{error}");
    }
}
