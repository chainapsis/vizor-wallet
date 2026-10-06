//! Thin application policy over the reusable swap receiving registry and recovery helpers.

pub(crate) mod receive;

use zakura_swap_receiving::lifecycle::ProviderStatus;
use zcash_client_backend::data_api::{Account as _, AccountSource, WalletRead};
use zcash_client_sqlite::{wallet::swap_receiving::RegisteredKey, AccountUuid};
use zcash_keys::address::{Address, UnifiedAddress};
use zcash_protocol::{consensus::BlockHeight, value::Zatoshis};

use super::{
    db::{
        open_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
};

/// Fails unless new private swap addresses are allowed: on mainnet, with both Private
/// queries and NEAR swap privacy on.
pub(crate) fn require_new_address(network: WalletNetwork) -> Result<(), String> {
    if network != WalletNetwork::Main
        || cfg!(ironwood_masquerade)
        || !crate::api::sync::enhance_pir_enabled()
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

/// Called under the wallet write lock before planning more scan work.
/// Restore sweeps run independently of both privacy switches. Only new address
/// issuance is opt-in.
pub(crate) fn maintain_recovery(db: &mut WalletDatabase) -> Result<(), String> {
    if cfg!(ironwood_masquerade) {
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

#[cfg(test)]
mod tests {
    use super::*;
    use secrecy::SecretVec;
    use zcash_client_backend::data_api::WalletWrite;
    use zcash_client_sqlite::wallet::swap_receiving::RECEIVE_GAP_LIMIT;

    #[test]
    fn restore_prepares_pir_discovery_with_both_settings_off() {
        assert!(!crate::api::sync::enhance_pir_enabled());
        assert!(!crate::api::sync::near_swap_privacy_enabled());
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Regtest;
        super::super::network::configure_regtest_nu6_3_activation_height(100).unwrap();
        super::super::keys::init_db_and_create_account(
            path,
            network,
            &SecretVec::new(vec![0; 32]),
            Some(100),
            "POC",
        )
        .unwrap();
        // The count of registered swap keys, and of those that advance allocation.
        let keys = || -> (u64, u64) {
            rusqlite::Connection::open(path)
                .unwrap()
                .query_row(
                    "SELECT COUNT(*), COALESCE(SUM(advances_allocation), 0)
                     FROM ironwood_receiving_keys",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .unwrap()
        };
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        db.update_chain_tip(BlockHeight::from_u32(110)).unwrap();
        maintain_recovery(&mut db).unwrap();
        assert_eq!(keys(), (0, 0));
        // Model completed ordinary scanning. Real note discovery and replay are
        // exercised by the shared library's compact-block recovery tests.
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute_batch(
            "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(110,zeroblob(32),0,X'000000');
             DELETE FROM scan_queue;
             INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(100,111,10);",
        ).unwrap();
        maintain_recovery(&mut db).unwrap();
        // Restored lookahead keys wait for a directory sweep; they are not scanned.
        assert_eq!(keys(), (RECEIVE_GAP_LIMIT, 0));
        assert!(db.get_swap_scanning_keys().unwrap().is_empty());
        assert_eq!(
            db.block_fully_scanned().unwrap().unwrap().block_height(),
            BlockHeight::from_u32(110)
        );
        drop(db);
        let mut reopened =
            open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        maintain_recovery(&mut reopened).unwrap();
        assert_eq!(keys(), (RECEIVE_GAP_LIMIT, 0));
        let error = require_new_address(WalletNetwork::Main).unwrap_err();
        assert!(error.contains("Enable Private queries"), "{error}");
    }
}
