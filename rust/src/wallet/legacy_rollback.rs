//! Handover of a wallet database to an older published build (a downgrade).
//!
//! This build's library drops `transactions.zip318_kind`, which the published
//! rc5 and rc7 writers still insert. Without a handover, such a build can open
//! a wallet this build has upgraded and read it, but fails to store any
//! transaction. [`prepare_for_legacy_build`] restores the column for a public
//! wallet. The handover needs nothing on the way back: the next launch of this
//! build runs the migration gate (`init_wallet_db`), which reconciles what the
//! older build wrote and drops the column again.
//!
//! No production path calls this yet: a running build cannot know that an
//! older one will open the wallet next. The upgrade probe
//! (`examples/db_upgrade.rs`) exercises it.

use zcash_client_sqlite::wallet::init::prepare_legacy_rollback;

use crate::wallet::{
    db::{open_wallet_db_with_timeout, with_wallet_db_write_lock, WALLET_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

/// Prepares the wallet at `db_path` for a published rc5/rc7 build.
///
/// The caller must have stopped every wallet worker, and this process must
/// not use the wallet afterwards: the library refuses its transparent ledger
/// APIs on a prepared database until initialization runs again, and this
/// process's migration gate has already run. Refuses a wallet whose
/// transparent policy changed or that holds private recovery state; such a
/// wallet cannot be handed to a build that knows no transparent policy.
/// Calling it again on a prepared wallet is safe.
pub fn prepare_for_legacy_build(db_path: &str, network: WalletNetwork) -> Result<(), String> {
    with_wallet_db_write_lock("legacy_rollback.prepare", || {
        let mut db = open_wallet_db_with_timeout(db_path, network, WALLET_DB_BUSY_TIMEOUT)?;
        prepare_legacy_rollback(&mut db)
            .map_err(|e| format!("Prepare wallet DB for an older build: {e}"))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::{
        db::{open_wallet_db_with_timeout, SYNC_DB_BUSY_TIMEOUT},
        keys,
    };
    use zcash_client_backend::data_api::transparent_ledger::{
        TransparentLedgerMode, TransparentLedgerRead, TransparentLedgerWrite,
    };

    fn zip318_column(path: &str) -> bool {
        rusqlite::Connection::open(path)
            .unwrap()
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM pragma_table_info('transactions')
                 WHERE name = 'zip318_kind')",
                [],
                |row| row.get(0),
            )
            .unwrap()
    }

    fn wallet() -> (tempfile::TempDir, String) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_owned();
        let seed = keys::mnemonic_to_seed(&keys::generate_mnemonic()).unwrap();
        keys::init_db_and_create_account(&path, WalletNetwork::Regtest, &seed, Some(100), "a")
            .unwrap();
        (dir, path)
    }

    /// The handover restores the column old writers insert, refuses the
    /// ledger until initialization runs again, and initialization drops it.
    #[test]
    fn prepared_wallet_returns_through_initialization() {
        let (_dir, path) = wallet();
        let network = WalletNetwork::Regtest;
        assert!(!zip318_column(&path));

        prepare_for_legacy_build(&path, network).unwrap();
        prepare_for_legacy_build(&path, network).unwrap();
        assert!(zip318_column(&path));
        let db = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
        assert!(db.applied_transparent_policy().is_err());
        drop(db);

        keys::ensure_db_initialized(&path, network).unwrap();
        assert!(!zip318_column(&path));
        let db = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
        assert_eq!(
            db.applied_transparent_policy().unwrap().mode,
            TransparentLedgerMode::Public
        );
    }

    /// A wallet whose transparent policy ever changed cannot be handed back.
    #[test]
    fn a_changed_policy_refuses_the_handover() {
        let (_dir, path) = wallet();
        let network = WalletNetwork::Regtest;
        let mut db = open_wallet_db_with_timeout(&path, network, SYNC_DB_BUSY_TIMEOUT).unwrap();
        db.apply_transparent_policy(TransparentLedgerMode::PrivateShadow)
            .unwrap();
        db.apply_transparent_policy(TransparentLedgerMode::Public)
            .unwrap();
        drop(db);

        assert!(prepare_for_legacy_build(&path, network).is_err());
        assert!(!zip318_column(&path));
    }
}
