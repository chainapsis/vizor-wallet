//! Thin application policy over the wallet library's one-time IVKs (see
//! `zcash_client_sqlite::wallet::one_time_ivk`), which Vizor uses for private NEAR swap
//! addresses.

use zcash_client_backend::data_api::{
    one_time_ivk::restore::RecoveryStatus, Account as _, WalletRead,
};
use zcash_client_sqlite::AccountUuid;
use zcash_protocol::value::Zatoshis;

use crate::api::one_time_ivk::{SwapRecoveryStatus, IDLE_STATUS};

use super::{
    db::{
        open_existing_wallet_db_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        WALLET_DB_BUSY_TIMEOUT,
    },
    keys::parse_account_uuid,
    network::WalletNetwork,
    sync_engine::enhancement::EnhancementPolicy,
};

/// Whether `network` runs one-time IVKs at all: wherever Private queries could (see
/// [`EnhancementPolicy`]), whether or not they are on. Issuance also requires the opt-in
/// (see [`require_new_address`]).
pub(crate) fn supported(network: WalletNetwork) -> bool {
    EnhancementPolicy::for_preference(network, true).is_private()
}

/// Fails unless new private swap addresses are allowed: where [`supported`], with NEAR
/// swap privacy on. Only reserving a new address needs it. Turning it off doesn't stop
/// watching addresses already handed out, and a quote for an address already reserved
/// finishes either way.
pub(crate) fn require_new_address(network: WalletNetwork) -> Result<(), String> {
    if !supported(network) || !crate::api::sync::near_swap_privacy_enabled() {
        return Err("Enable NEAR swap privacy before reserving an address".into());
    }
    Ok(())
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

/// The current Unix time in seconds, as the library's lifecycle takes it.
pub(crate) fn now() -> Result<i64, String> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs()
        .try_into()
        .map_err(|_| "Clock overflow".into())
}

/// Runs `action` on `uuid`'s account in the existing wallet at `path`, under the wallet
/// write lock. It never creates a database a reset deleted.
pub(crate) fn with_db<T, E: From<String>>(
    path: &str,
    network: WalletNetwork,
    uuid: &str,
    action: impl FnOnce(&mut WalletDatabase, AccountUuid) -> Result<T, E>,
) -> Result<T, E> {
    with_wallet_db_write_lock("one_time_ivk", || {
        let mut db = open_existing_wallet_db_with_timeout(path, network, WALLET_DB_BUSY_TIMEOUT)?;
        let account = parse_account_uuid(uuid)?;
        action(&mut db, account)
    })
}

/// Whether `state`'s account is in the set rounds and filter steps cover: NEAR swap
/// privacy is on, the account used one-time addresses, or a history check is running for
/// it. A history check's own round covers every software account too.
pub(crate) fn in_set(state: &RecoveryStatus) -> bool {
    crate::api::sync::near_swap_privacy_enabled()
        || state.used
        || state.manual.is_some_and(|m| m.active)
}

/// The software accounts in the set (see [`in_set`]), every one with `history`, each
/// enabled.
pub(crate) fn enable_recovery(
    db: &mut WalletDatabase,
    history: bool,
) -> Result<Vec<AccountUuid>, String> {
    let mut accounts = Vec::new();
    for account in software_accounts(db)? {
        let state = db
            .one_time_recovery(account, now()?, None)
            .map_err(|e| e.to_string())?;
        if history || in_set(&state) {
            db.enable_one_time_recovery(account)
                .map_err(|e| e.to_string())?;
            accounts.push(account);
        }
    }
    Ok(accounts)
}

/// Recovery state across the software accounts. A round is due for an account in the set
/// (see [`in_set`]) that isn't enabled yet, or whose state says so (see
/// `RecoveryStatus::round_due`). Found payments awaiting admission count on any software
/// account.
pub(crate) fn recovery_status(db: &WalletDatabase) -> Result<SwapRecoveryStatus, String> {
    let mut status = IDLE_STATUS;
    for account in software_accounts(db)? {
        let state = db
            .one_time_recovery(account, now()?, None)
            .map_err(|e| e.to_string())?;
        status.awaiting_admission |= state.awaiting_admission > 0;
        if !in_set(&state) {
            continue;
        }
        let manual = state.enabled && state.manual.is_some_and(|m| m.active);
        status.round_due |= !state.enabled || state.round_due;
        status.manual_check_active |= manual;
        status.checking_history |= manual || (state.enabled && !state.restore_complete);
        status.upgrade_required |= state.upgrade_required;
    }
    Ok(status)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::db::open_wallet_db_with_timeout;
    use secrecy::SecretVec;
    use zakura_one_time_ivk::{KeyId, Purpose};
    use zcash_client_backend::data_api::WalletWrite;
    use zcash_client_sqlite::wallet::one_time_ivk::swap::ReservationPolicy;
    use zcash_protocol::consensus::BlockHeight;

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
        db.enable_one_time_recovery(added).unwrap();
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
