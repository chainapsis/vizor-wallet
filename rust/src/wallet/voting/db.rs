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
    const MAX_LOCK_RETRIES: u32 = 5;
    let wallet_path = std::path::Path::new(db_path);
    for attempt in 0..=MAX_LOCK_RETRIES {
        match zcash_voting::storage::VotingDb::open_wallet_sidecar(wallet_path, account_uuid) {
            Ok(db) => return Ok(db),
            Err(error) => {
                let message = error.to_string();
                let locked = message.to_ascii_lowercase().contains("database is locked");
                if !locked || attempt == MAX_LOCK_RETRIES {
                    return Err(format!("Error opening voting database: {message}"));
                }
                std::thread::sleep(std::time::Duration::from_millis(
                    50 * u64::from(attempt + 1),
                ));
            }
        }
    }
    unreachable!("the bounded voting database retry loop always returns")
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

    #[test]
    fn open_voting_db_retries_a_transient_schema_lock() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let sidecar_path = zcash_voting::storage::VotingDb::wallet_sidecar_path(&db_path);
        let lock = rusqlite::Connection::open(&sidecar_path).unwrap();
        lock.execute_batch("BEGIN EXCLUSIVE").unwrap();
        let release = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(125));
            lock.execute_batch("ROLLBACK").unwrap();
        });

        let db = open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap();

        release.join().unwrap();
        assert!(db.list_rounds().unwrap().is_empty());
    }
}
