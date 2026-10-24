//! Thin application policy over the wallet library's one-time IVKs (see
//! `zcash_client_sqlite::wallet::one_time_ivk`), which Vizor uses for private NEAR swap
//! addresses.

use zcash_client_backend::data_api::{
    one_time_ivk::restore::RecoveryStatus, Account as _, WalletRead,
};
use zcash_client_sqlite::{wallet::one_time_ivk::OneTimeKey, AccountUuid};
use zcash_keys::address::{Address, UnifiedAddress};
use zcash_protocol::{consensus::BlockHeight, value::Zatoshis};

use super::{
    db::{
        open_existing_wallet_db_with_timeout, open_wallet_db_with_timeout,
        with_wallet_db_write_lock, WalletDatabase, WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
    sync_engine::enhancement::EnhancementPolicy,
};

/// Whether `network` runs one-time IVKs at all: wherever Private queries could (see
/// [`EnhancementPolicy`]). Discovery and issuance also require the effective opt-in.
pub(crate) fn supported(network: WalletNetwork) -> bool {
    EnhancementPolicy::for_preference(network, true).is_private()
}

/// Fails unless new private swap addresses are allowed: where [`supported`], with both
/// Private queries and NEAR swap privacy on.
pub(crate) fn require_new_address(network: WalletNetwork) -> Result<(), String> {
    if !discovery_enabled(network) {
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

/// Parses a bridged base-unit amount. An unparseable amount counts as unreported.
pub(crate) fn provider_amount(value: &Option<String>) -> Option<Zatoshis> {
    value
        .as_deref()
        .and_then(|v| v.parse::<u64>().ok())
        .and_then(|v| Zatoshis::from_u64(v).ok())
}

/// Whether `account` is a software account: one with ZIP 32 derivation metadata, from
/// which Vizor derives its spending key (see `execute_stored_proposal`), without a
/// hardware signer, and with an Orchard full viewing key to derive one-time keys from.
/// That includes the first account, created as `Derived`, and accounts added later as
/// spending UFVK imports. View-only imports have no derivation.
fn is_software(db: &WalletDatabase, account: AccountUuid) -> Result<bool, String> {
    let account = db
        .get_account(account)
        .map_err(|e| e.to_string())?
        .ok_or("Account not found")?;
    let source = account.source();
    Ok(source.key_derivation().is_some()
        && super::keys::hardware_signer_kind(source).is_none()
        && account.ufvk().is_some_and(|ufvk| ufvk.orchard().is_some()))
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

/// The current Unix time in seconds, as the library's lifecycle takes it.
pub(crate) fn now() -> Result<i64, String> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs()
        .try_into()
        .map_err(|_| "Clock overflow".into())
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

/// Whether the install setting turns discovery on: where [`supported`], with both Private
/// queries and NEAR swap privacy on. Private queries are effective only where
/// [`supported`], so that check is implied.
pub(crate) fn discovery_enabled(network: WalletNetwork) -> bool {
    EnhancementPolicy::current(network).is_private()
        && crate::api::sync::near_swap_privacy_enabled()
}

/// Mirrors the install setting into every eligible account before any recovery or issuance.
pub(crate) fn reconcile_enabled(
    db: &mut WalletDatabase,
    network: WalletNetwork,
) -> Result<(), String> {
    let enabled = discovery_enabled(network);
    for account in software_accounts(db)? {
        db.set_one_time_recovery_enabled(account, enabled)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Whether an account in `state` needs a recovery round: it is enabled, or it holds
/// receipts whose repair is due, which runs even while the feature is off.
pub(crate) fn has_recovery_work(state: &RecoveryStatus) -> bool {
    state.enabled || !state.lookups.is_empty() || !state.witnesses.is_empty()
}

/// Whether any software account needs a recovery round (see [`has_recovery_work`]). A
/// pure read, so it needs no write lock.
pub(crate) fn any_recovery_work(db: &WalletDatabase) -> Result<bool, String> {
    for account in software_accounts(db)? {
        let state = db
            .one_time_recovery(account, now()?)
            .map_err(|e| e.to_string())?;
        if has_recovery_work(&state) {
            return Ok(true);
        }
    }
    Ok(false)
}

/// Whether an automatic round at `path` would do nothing: discovery is off and no
/// account has repair due (see [`any_recovery_work`]). A read that takes no write lock
/// and never creates the wallet, so callers can check it before building a runtime or
/// an HTTPS client.
pub(crate) fn idle_while_off(path: &str, network: WalletNetwork) -> Result<bool, String> {
    if discovery_enabled(network) {
        return Ok(false);
    }
    let db = open_existing_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
    Ok(!any_recovery_work(&db)?)
}

/// Saved swap recovery state across the software accounts (see
/// `api::one_time_ivk::SwapRecoveryStatus`).
pub(crate) struct RecoveryFlags {
    /// An enabled account has unfinished seed recovery or an active manual job.
    pub(crate) checking: bool,
    /// An enabled account has an active manual history check.
    pub(crate) manual: bool,
    /// The receiver service asked an account for a newer client.
    pub(crate) upgrade: bool,
}

/// Reads [`RecoveryFlags`] from the wallet without network access.
pub(crate) fn recovery_flags(db: &WalletDatabase) -> Result<RecoveryFlags, String> {
    let mut flags = RecoveryFlags {
        checking: false,
        manual: false,
        upgrade: false,
    };
    for account in software_accounts(db)? {
        let state = db
            .one_time_recovery(account, now()?)
            .map_err(|e| e.to_string())?;
        let manual = state.enabled && state.manual.is_some_and(|m| m.active);
        flags.manual |= manual;
        flags.checking |= manual || (state.enabled && !state.restore_complete);
        flags.upgrade |= state.upgrade_required;
    }
    Ok(flags)
}

#[cfg(test)]
mod tests {
    use super::*;
    use secrecy::SecretVec;
    use zakura_one_time_ivk::{KeyId, Purpose};
    use zcash_client_backend::data_api::WalletWrite;
    use zcash_client_sqlite::wallet::one_time_ivk::swap::ReservationPolicy;

    /// One-time IVKs cover the first account and accounts added from another seed,
    /// whose swap notes Vizor can spend, but not hardware or view-only accounts.
    #[test]
    fn added_seed_accounts_are_software_but_hardware_and_view_only_accounts_are_not() {
        use super::super::keys;
        use secrecy::ExposeSecret;
        use std::collections::HashSet;
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

        // An enabled added account registers its initial four-index window. Issuing I0
        // waits until its own history lookup completes, which a restored seed needs.
        db.update_chain_tip(BlockHeight::from_u32(110)).unwrap();
        rusqlite::Connection::open(path)
            .unwrap()
            .execute_batch(
                "INSERT INTO blocks(height,hash,time,sapling_tree) VALUES(110,zeroblob(32),0,X'000000');
                 DELETE FROM scan_queue;
                 INSERT INTO scan_queue(block_range_start,block_range_end,priority) VALUES(100,111,10);",
            )
            .unwrap();
        db.set_one_time_recovery_enabled(added, true).unwrap();
        assert_eq!(
            db.prepare_receive_reservation(added, now().unwrap())
                .unwrap()
                .err(),
            Some(ReservationPolicy::ReceiveHistory)
        );
        let registered = |account: AccountUuid| -> Vec<Vec<u8>> {
            let conn = rusqlite::Connection::open(path).unwrap();
            let mut statement = conn
                .prepare(
                    "SELECT k.receiver FROM ironwood_one_time_keys k
                     JOIN accounts a ON a.id = k.account_id
                     WHERE a.uuid = ?1 ORDER BY k.purpose, k.key_index",
                )
                .unwrap();
            let rows = statement
                .query_map([account.expose_uuid().as_bytes()], |r| r.get(0))
                .unwrap();
            rows.collect::<Result<_, _>>().unwrap()
        };
        assert_eq!(registered(added).len(), 4);
        for account in [derived, hardware, observer] {
            assert!(registered(account).is_empty());
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
        assert_eq!(
            registered(added)[0],
            swap_fvk
                .address_at(0u32, orchard::keys::Scope::External)
                .to_raw_address_bytes()
        );
    }
}
