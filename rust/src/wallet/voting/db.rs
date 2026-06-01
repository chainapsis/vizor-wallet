/// Opens the voting sidecar database for a wallet and binds it to `account_uuid`.
///
/// `db_path` is the main wallet database path; the voting DB is opened at the
/// deterministic sidecar path returned by
/// [`zcash_voting::round::VotingDb::wallet_sidecar_path`].
///
/// # Errors
///
/// Returns an error if the upstream voting database cannot be opened or
/// initialized.
pub fn open_voting_db(
    db_path: &str,
    account_uuid: &str,
) -> Result<zcash_voting::storage::VotingDb, String> {
    zcash_voting::storage::VotingDb::open_wallet_sidecar(
        std::path::Path::new(db_path),
        account_uuid,
    )
    .map_err(|e| format!("Error opening voting database: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_voting_db_initializes_upstream_schema() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();

        assert!(db.list_rounds().unwrap().is_empty());
        assert!(zcash_voting::storage::VotingDb::wallet_sidecar_path(&db_path).exists());
    }

    #[test]
    fn open_voting_db_uses_sidecar_path_not_wallet_user_version() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let wallet_conn = rusqlite::Connection::open(&db_path).unwrap();
        wallet_conn.pragma_update(None, "user_version", 8).unwrap();

        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();

        assert!(db.list_rounds().unwrap().is_empty());
        let wallet_version: u32 = wallet_conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(wallet_version, 8);
    }
}
