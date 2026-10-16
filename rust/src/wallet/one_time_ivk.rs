//! Thin application policy over the wallet library's one-time IVKs (see
//! `zcash_client_sqlite::wallet::one_time_ivk`), which Vizor uses for private NEAR swap
//! addresses.

use zakura_near_intents::NearStatus;
use zcash_client_backend::data_api::{
    one_time_ivk::restore::OneTimeIvkRestoreWrite as _, Account as _, WalletRead,
};
use zcash_client_sqlite::{wallet::one_time_ivk::OneTimeKey, AccountUuid};
use zcash_keys::address::{Address, UnifiedAddress};
use zcash_protocol::{consensus::BlockHeight, value::Zatoshis};

use super::{
    db::{
        open_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
    sync_engine::enhancement::EnhancementPolicy,
};

/// Debug builds only: runs one-time IVKs on regtest, where Private queries never apply,
/// for the regtest end-to-end tests. Release builds never read it.
const REGTEST_ENV: &str = "VIZOR_REGTEST_ONE_TIME_IVKS";
/// Debug builds only: seconds added to [`now`], so the regtest end-to-end tests can move
/// swap lifecycles forward with their chain's mock time. Release builds never read it.
const CLOCK_OFFSET_ENV: &str = "VIZOR_E2E_CLOCK_OFFSET_SECS";

/// Whether a debug build's regtest end-to-end run turned one-time IVKs on (see
/// [`REGTEST_ENV`]). It stands in for Private queries, which regtest cannot run.
fn regtest_e2e(network: WalletNetwork) -> bool {
    cfg!(debug_assertions)
        && network == WalletNetwork::Regtest
        && std::env::var_os(REGTEST_ENV).is_some()
}

/// Whether `network` runs one-time IVKs at all: wherever Private queries could (see
/// [`EnhancementPolicy`]), whatever the switches say, or in a regtest end-to-end run
/// (see [`regtest_e2e`]). Restore sweeps, key maintenance and provider statuses need
/// nothing more; new addresses do (see [`require_new_address`]).
pub(crate) fn supported(network: WalletNetwork) -> bool {
    regtest_e2e(network) || EnhancementPolicy::for_preference(network, true).is_private()
}

/// Fails unless new private swap addresses are allowed: where [`supported`], with both
/// Private queries and NEAR swap privacy on.
pub(crate) fn require_new_address(network: WalletNetwork) -> Result<(), String> {
    let private = regtest_e2e(network) || EnhancementPolicy::current(network).is_private();
    if !private || !crate::api::sync::near_swap_privacy_enabled() {
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
pub(crate) fn near_status(status: &crate::api::one_time_ivk::SwapProviderStatus) -> NearStatus<'_> {
    let amount = |value: &Option<String>| {
        value
            .as_deref()
            .and_then(|v| v.parse::<u64>().ok())
            .and_then(|v| Zatoshis::from_u64(v).ok())
    };
    NearStatus {
        status: &status.status,
        swap_type: status.swap_type.as_deref(),
        refunded_amount: amount(&status.refunded_amount),
        amount_out: amount(&status.amount_out),
    }
}

/// Whether `account` is a software account: one with ZIP 32 derivation metadata, from
/// which Vizor derives its spending key (see `execute_stored_proposal`), and without a
/// hardware signer. That includes the first account, created as `Derived`, and accounts
/// added later as spending UFVK imports; view-only imports have no derivation.
fn is_software(db: &WalletDatabase, account: AccountUuid) -> Result<bool, String> {
    let account = db
        .get_account(account)
        .map_err(|e| e.to_string())?
        .ok_or("Account not found")?;
    let source = account.source();
    Ok(source.key_derivation().is_some() && super::keys::hardware_signer_kind(source).is_none())
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

/// The software accounts that can spend with one-time keys.
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
pub(crate) fn encode_address(key: &OneTimeKey, network: WalletNetwork) -> Result<String, String> {
    let address = UnifiedAddress::from_receivers(Some(key.receiver()), None, None)
        .ok_or("Invalid swap receiver")?;
    Ok(Address::Unified(address)
        .to_zcash_address(&network)
        .to_string())
}

/// The current Unix time in seconds, as the library's lifecycle takes it, moved by
/// [`CLOCK_OFFSET_ENV`] in a debug build.
pub(crate) fn now() -> Result<i64, String> {
    let now: i64 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs()
        .try_into()
        .map_err(|_| "Clock overflow")?;
    let offset = if cfg!(debug_assertions) {
        std::env::var(CLOCK_OFFSET_ENV)
            .ok()
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(0)
    } else {
        0
    };
    now.checked_add(offset)
        .ok_or_else(|| "Clock overflow".into())
}

/// Runs `action` on `uuid`'s account in the wallet at `path`, under the wallet write lock.
pub(crate) fn with_db<T, E: From<String>>(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    action: impl FnOnce(&mut WalletDatabase, AccountUuid) -> Result<T, E>,
) -> Result<T, E> {
    with_wallet_db_write_lock("one_time_ivk", || {
        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let account = parse_account_uuid(uuid)?;
        action(&mut db, account)
    })
}

/// Declares `uuid`'s account newly created from a seed generated for it, so it has no
/// one-time payments to restore (see `WalletDb::mark_one_time_account_fresh`). Account
/// creation calls it before returning, so before any sync sees the account. A failure
/// leaves the account treated as restored, which costs only lookups.
pub(crate) fn mark_fresh(path: &str, network: WalletNetwork, uuid: &str) {
    let marked = with_db(path, network, uuid, |db, account| {
        db.mark_one_time_account_fresh(account)
            .map_err(|e| e.to_string())
    });
    if let Err(e) = marked {
        log::warn!("one-time IVKs: could not mark a new account fresh: {e}");
    }
}

/// Keeps every software account's one-time key recovery current, under the wallet write
/// lock. Sync calls it only at its start (see `run_sync_impl`), and only where
/// [`supported`]; it runs with both privacy switches off, since only new address
/// issuance is opt-in.
pub(crate) fn maintain_recovery(db: &mut WalletDatabase) -> Result<(), String> {
    for account in software_accounts(db)? {
        db.maintain_one_time_ivks(account)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Stops scanning finished one-time keys, under the wallet write lock, once sync has
/// scanned to `tip`, the chain tip it revalidated this session. Sync calls it only where
/// [`supported`].
pub(crate) fn close_finished_keys(db: &mut WalletDatabase, tip: BlockHeight) -> Result<(), String> {
    let now = now()?;
    for account in software_accounts(db)? {
        db.close_finished_one_time_keys(account, now, tip)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use secrecy::SecretVec;
    use zcash_client_backend::data_api::{one_time_ivk::OneTimeIvkRead as _, WalletWrite};
    use zcash_client_sqlite::wallet::one_time_ivk::swap::RECEIVE_GAP_LIMIT;

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
                     FROM ironwood_one_time_keys",
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
        assert!(db.get_one_time_scanning_keys().unwrap().is_empty());
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

    /// A refund memo that Enhance retrieves during sync S neither registers its key nor
    /// queues work before S ends: S's restore sweep selects no refund key and no rescan is
    /// queued. Maintenance at the start of S+1 registers the key, and S+1's sweep selects
    /// it. Sync runs `maintain_recovery` at its start and `close_finished_keys` at the tip.
    #[test]
    fn a_refund_memo_found_during_a_sync_is_swept_the_next_sync() {
        use std::num::NonZeroU32;
        use zakura_one_time_ivk::{swap::RefundMemo, KeyId, Purpose};
        use zcash_client_backend::data_api::transparent_ledger::ChainPoint;
        use zcash_primitives::block::BlockHash;

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
        // Scanned through 110, with the change of a funding transaction mined at 105 whose
        // memo compact scanning did not carry.
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute_batch(
            "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(110,zeroblob(32),0,X'000000');
             DELETE FROM scan_queue;
             INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(100,111,10);
             INSERT INTO transactions(id_tx,txid,mined_height,min_observed_height)
                 VALUES(1,randomblob(32),105,105);
             INSERT INTO ironwood_received_notes(transaction_id,action_index,account_id,
                 diversifier,value,rho,rseed,is_change,recipient_key_scope,note_version)
                 SELECT 1,0,id,zeroblob(11),0,zeroblob(32),zeroblob(32),1,1,0 FROM accounts;",
        )
        .unwrap();
        let through = ChainPoint {
            height: BlockHeight::from_u32(110),
            hash: BlockHash([0; 32]),
        };
        let refund = KeyId::new(Purpose::Refund, 7);
        // Whether the restore sweep a sync ends with selects the refund key.
        let swept = |db: &mut WalletDatabase| {
            db.prepare_one_time_sweeps(account, through, now().unwrap(), NonZeroU32::MAX)
                .unwrap()
                .unwrap()
                .iter()
                .any(|work| work.key == refund)
        };
        let rescan_queued = |db: &WalletDatabase| !db.suggest_scan_ranges().unwrap().is_empty();

        // Sync S starts, then its Enhance drain retrieves the memo.
        maintain_recovery(&mut db).unwrap();
        conn.execute(
            "UPDATE ironwood_received_notes SET memo = ?1",
            [RefundMemo::new(7).encode().as_slice()],
        )
        .unwrap();
        close_finished_keys(&mut db, through.height).unwrap();
        assert!(!swept(&mut db), "S's sweep waits");
        assert!(!rescan_queued(&db), "S queues no rescan");

        // Sync S+1 starts.
        maintain_recovery(&mut db).unwrap();
        assert!(swept(&mut db), "S+1's sweep selects the key");
        assert!(!rescan_queued(&db), "its rescan follows that sweep");
    }

    /// Accounts the app creates from a seed it generated start fresh, so no early restore
    /// or restore sweep runs for them. A payment-link claim imports the link's seed, which
    /// is not fresh.
    #[test]
    fn created_accounts_are_fresh_but_a_claimed_seed_is_not() {
        use super::super::keys::generate_mnemonic;
        use crate::api::wallet as api;

        let dir = tempfile::tempdir().unwrap();
        super::super::network::configure_regtest_nu6_3_activation_height(100).unwrap();
        let fresh = |path: &str, uuid: &str| -> bool {
            rusqlite::Connection::open(path)
                .unwrap()
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM ironwood_one_time_fresh_accounts f
                     JOIN accounts a ON a.id = f.account_id WHERE a.uuid = ?1)",
                    [parse_account_uuid(uuid).unwrap().expose_uuid()],
                    |r| r.get(0),
                )
                .unwrap()
        };
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let created = api::create_wallet("regtest".into(), path.clone(), Some(100), None).unwrap();
        let added = api::add_account(
            path.clone(),
            "regtest".into(),
            "Added".into(),
            generate_mnemonic(),
            String::new(),
            Some(100),
        )
        .unwrap();
        assert!(fresh(&path, &created.account_uuid));
        assert!(fresh(&path, &added.account_uuid));

        let claim = dir.path().join("claim.db").to_str().unwrap().to_owned();
        let claimed = api::import_wallet(
            generate_mnemonic(),
            String::new(),
            Some(100),
            "regtest".into(),
            claim.clone(),
            None,
            false,
        )
        .unwrap();
        assert!(!fresh(&claim, &claimed.account_uuid));
    }

    /// One-time IVKs cover the first account and accounts added from another seed,
    /// whose swap notes Vizor can spend, but not hardware or view-only accounts.
    #[test]
    fn added_seed_accounts_are_software_but_hardware_and_view_only_accounts_are_not() {
        use super::super::keys;
        use secrecy::ExposeSecret;
        use std::collections::HashSet;
        use zakura_one_time_ivk::{KeyId, Purpose};
        use zcash_keys::keys::UnifiedSpendingKey;

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let network = WalletNetwork::Regtest;
        super::super::network::configure_regtest_nu6_3_activation_height(100).unwrap();
        let uuid = |uuid: String| parse_account_uuid(&uuid).unwrap();
        let derived = SecretVec::new(vec![0; 32]);
        let derived = uuid(
            keys::init_db_and_create_account(path, network, &derived, Some(100), "Derived")
                .unwrap()
                .0,
        );
        // Accounts added to a wallet are spending UFVK imports with ZIP 32 metadata.
        let added_seed = SecretVec::new(vec![1; 32]);
        let added = uuid(
            keys::add_account(path, network, "Added", &added_seed, Some(100))
                .unwrap()
                .0,
        );
        let hardware_ufvk =
            UnifiedSpendingKey::from_seed(&network, &[2; 32], zip32::AccountId::ZERO)
                .unwrap()
                .to_unified_full_viewing_key();
        let hardware = uuid(
            keys::import_hardware_account(
                path,
                network,
                "Keystone",
                &hardware_ufvk.encode(&network),
                &[2; 32],
                0,
                Some(100),
                keys::HardwareSignerKind::Keystone,
            )
            .unwrap()
            .0,
        );
        let observer_phrase = keys::generate_mnemonic();
        let observer_seed = keys::mnemonic_to_seed(&observer_phrase).unwrap();
        let observer = uuid(
            keys::register_gift_card_observer(
                path,
                network,
                observer_phrase.as_bytes(),
                &keys::derive_gift_address(network, &observer_seed, 0).unwrap(),
                100,
            )
            .unwrap(),
        );

        let mut db = open_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT).unwrap();
        assert_eq!(
            software_accounts(&db)
                .unwrap()
                .into_iter()
                .collect::<HashSet<_>>(),
            HashSet::from([derived, added])
        );
        for account in [hardware, observer] {
            assert!(require_software_account(&db, account).is_err());
        }

        // Restore maintenance runs for both software accounts, as in the test above.
        db.update_chain_tip(BlockHeight::from_u32(110)).unwrap();
        rusqlite::Connection::open(path)
            .unwrap()
            .execute_batch(
                "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(110,zeroblob(32),0,X'000000');
                 DELETE FROM scan_queue;
                 INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(100,111,10);",
            )
            .unwrap();
        maintain_recovery(&mut db).unwrap();
        let registered: u64 = rusqlite::Connection::open(path)
            .unwrap()
            .query_row("SELECT COUNT(*) FROM ironwood_one_time_keys", [], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(registered, 2 * RECEIVE_GAP_LIMIT);
        let first_receiver = |fvk: &orchard::keys::FullViewingKey| {
            KeyId::new(Purpose::Receive, 0)
                .derive(fvk)
                .unwrap()
                .address_at(0u32, orchard::keys::Scope::External)
        };
        let observer_ufvk = UnifiedSpendingKey::from_seed(
            &network,
            observer_seed.expose_secret(),
            zip32::AccountId::ZERO,
        )
        .unwrap()
        .to_unified_full_viewing_key();
        for (account, ufvk) in [(hardware, hardware_ufvk), (observer, observer_ufvk)] {
            let receiver = first_receiver(ufvk.orchard().unwrap());
            assert!(db
                .get_one_time_key_for_receiver(account, &receiver)
                .unwrap()
                .is_none());
        }

        // Spending derives the added account's key from its seed and ZIP 32 index, as
        // `execute_stored_proposal` does. The builder finds the account by that key's
        // UFVK, and the swap FVK it derives shares the account's spending authority
        // and matches the registered key.
        let index = db
            .get_account(added)
            .unwrap()
            .unwrap()
            .source()
            .key_derivation()
            .unwrap()
            .account_index();
        let usk =
            UnifiedSpendingKey::from_seed(&network, added_seed.expose_secret(), index).unwrap();
        assert_eq!(
            db.get_account_for_ufvk(&usk.to_unified_full_viewing_key())
                .unwrap()
                .map(|account| account.id()),
            Some(added)
        );
        let fvk = orchard::keys::FullViewingKey::from(usk.orchard());
        let swap_fvk = KeyId::new(Purpose::Receive, 0).derive(&fvk).unwrap();
        // A one-time FVK keeps the account's ak and nk, its first 64 bytes.
        assert_eq!(fvk.to_bytes()[..64], swap_fvk.to_bytes()[..64]);
        let key = db
            .get_one_time_key_for_receiver(added, &first_receiver(&fvk))
            .unwrap()
            .unwrap();
        assert_eq!(key.key_id(), KeyId::new(Purpose::Receive, 0));
    }
}
