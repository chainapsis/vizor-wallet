//! Voting sidecar handle.
//!
//! `zcash_voting` keeps one SQLite connection per sidecar path for as long as
//! any handle is alive, so every caller here shares it and in-process writers
//! serialize on the SDK's connection mutex. A `SQLITE_BUSY` from another
//! process surfaces as `VotingError::DbBusy`; Vizor does not layer its own
//! path locks or lock-message matching on top.

use std::{path::Path, sync::Arc};

use zcash_voting::storage::VotingDb;

/// Opens the account-scoped voting sidecar next to the wallet database.
///
/// `db_path` is the main wallet database path; the sidecar lives at
/// [`VotingDb::wallet_sidecar_path`].
///
/// # Errors
///
/// Returns an error if the sidecar cannot be opened or migrated.
pub fn open_voting_db(db_path: &str, account_uuid: &str) -> Result<Arc<VotingDb>, String> {
    VotingDb::open_wallet_sidecar(Path::new(db_path), account_uuid)
        .map_err(|error| format!("Error opening voting database: {error}"))
}

#[cfg(test)]
mod tests {
    use super::open_voting_db;

    #[test]
    fn handles_for_one_sidecar_share_a_connection() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let first = open_voting_db(db_path, "account-a").unwrap();
        let second = open_voting_db(db_path, "account-b").unwrap();
        assert!(first.shares_connection_with(&second));
        assert_eq!(first.wallet_id(), "account-a");
        assert_eq!(second.wallet_id(), "account-b");
    }
}
