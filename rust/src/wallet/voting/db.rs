use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
};

fn sidecar_write_locks() -> &'static Mutex<HashMap<PathBuf, Arc<Mutex<()>>>> {
    static LOCKS: OnceLock<Mutex<HashMap<PathBuf, Arc<Mutex<()>>>>> = OnceLock::new();
    LOCKS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn sidecar_write_lock(db_path: &str) -> Arc<Mutex<()>> {
    let sidecar_path = zcash_voting::storage::VotingDb::wallet_sidecar_path(Path::new(db_path));
    let mut locks = sidecar_write_locks()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    locks
        .entry(sidecar_path)
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .clone()
}

/// Runs a sidecar-mutating operation exclusively for one wallet database.
///
/// Delegation bundles use independent SQLite connections. WAL permits their
/// reads to overlap, but SQLite still has a single writer; this process-local
/// coordinator keeps the short setup, proof-persistence, submission, and
/// confirmation write phases from racing each other.
pub fn with_voting_sidecar_write_lock<T>(
    db_path: &str,
    operation: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    let lock = sidecar_write_lock(db_path);
    let _guard = lock
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    operation()
}

/// Retries a complete idempotent voting operation after SQLite writer races.
///
/// Proof generation deliberately runs outside the sidecar write lock so up to
/// three bundles can perform PIR and Halo2 work concurrently. Its final SQLite
/// transaction can still lose the single-writer race; retrying the bundle
/// operation is safe because its setup, PIR cache, and proof persistence are
/// bundle-keyed and idempotent.
pub fn retry_voting_db_locks<T>(
    mut operation: impl FnMut() -> Result<T, String>,
) -> Result<T, String> {
    const MAX_LOCK_RETRIES: u32 = 3;
    for attempt in 0..=MAX_LOCK_RETRIES {
        match operation() {
            Ok(value) => return Ok(value),
            Err(error) => {
                let locked = error.to_ascii_lowercase().contains("database is locked");
                if !locked || attempt == MAX_LOCK_RETRIES {
                    return Err(error);
                }
                std::thread::sleep(std::time::Duration::from_millis(
                    50 * u64::from(attempt + 1),
                ));
            }
        }
    }
    unreachable!("the bounded voting database retry loop always returns")
}

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
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Barrier,
    };

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

    #[test]
    fn sidecar_write_lock_serializes_three_writers_for_one_wallet() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let db_path = Arc::new(db_path.to_string_lossy().into_owned());
        let start = Arc::new(Barrier::new(3));
        let active = Arc::new(AtomicUsize::new(0));
        let max_active = Arc::new(AtomicUsize::new(0));

        let writers = (0..3)
            .map(|_| {
                let db_path = Arc::clone(&db_path);
                let start = Arc::clone(&start);
                let active = Arc::clone(&active);
                let max_active = Arc::clone(&max_active);
                std::thread::spawn(move || {
                    start.wait();
                    with_voting_sidecar_write_lock(&db_path, || {
                        let now_active = active.fetch_add(1, Ordering::SeqCst) + 1;
                        max_active.fetch_max(now_active, Ordering::SeqCst);
                        std::thread::sleep(std::time::Duration::from_millis(20));
                        active.fetch_sub(1, Ordering::SeqCst);
                        Ok(())
                    })
                    .unwrap();
                })
            })
            .collect::<Vec<_>>();

        for writer in writers {
            writer.join().unwrap();
        }
        assert_eq!(max_active.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn voting_db_lock_retry_recovers_after_transient_writer_races() {
        let attempts = AtomicUsize::new(0);
        let result = retry_voting_db_locks(|| {
            let attempt = attempts.fetch_add(1, Ordering::SeqCst);
            if attempt < 2 {
                Err("database is locked".to_string())
            } else {
                Ok(42)
            }
        });

        assert_eq!(result.unwrap(), 42);
        assert_eq!(attempts.load(Ordering::SeqCst), 3);
    }
}
