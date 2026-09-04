use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
};

fn sidecar_write_locks() -> &'static Mutex<HashMap<PathBuf, Arc<Mutex<()>>>> {
    static LOCKS: OnceLock<Mutex<HashMap<PathBuf, Arc<Mutex<()>>>>> = OnceLock::new();
    LOCKS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn sidecar_open_locks() -> &'static Mutex<HashMap<PathBuf, Arc<Mutex<()>>>> {
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

fn sidecar_open_lock(db_path: &str) -> Arc<Mutex<()>> {
    let sidecar_path = zcash_voting::storage::VotingDb::wallet_sidecar_path(Path::new(db_path));
    let mut locks = sidecar_open_locks()
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

/// Opens a voting sidecar and runs one write-bearing operation under its lock.
///
/// Opening is part of the critical section because a fresh connection may run
/// schema migration or update SQLite pragmas. The returned database handle can
/// be reused for read-only or internally coordinated work after the lock is
/// released.
pub fn with_open_voting_db_write<T>(
    db_path: &str,
    account_uuid: &str,
    operation: impl FnOnce(&zcash_voting::storage::VotingDb) -> Result<T, String>,
) -> Result<(zcash_voting::storage::VotingDb, T), String> {
    with_voting_sidecar_write_lock(db_path, || {
        let db = open_voting_db(db_path, account_uuid)?;
        let value = operation(&db)?;
        Ok((db, value))
    })
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

/// Retries an idempotent operation under the sidecar writer after a lock race.
///
/// The first attempt remains outside the coordinator so expensive proof work
/// can run concurrently. If its final persistence loses a SQLite writer race,
/// subsequent attempts hold the coordinator for the complete operation. This
/// is intentionally an exceptional recovery path: it guarantees progress
/// against other coordinated writers without serializing successful proofs.
pub fn retry_voting_db_locks_coordinated<T>(
    db_path: &str,
    mut operation: impl FnMut() -> Result<T, String>,
) -> Result<T, String> {
    let mut first_attempt = true;
    retry_voting_db_locks(|| {
        if std::mem::replace(&mut first_attempt, false) {
            operation()
        } else {
            with_voting_sidecar_write_lock(db_path, &mut operation)
        }
    })
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
    // Every upstream open may run a schema migration. Keep that short phase
    // separate from the longer-lived writer coordinator so callers that
    // already hold the write lock can safely open the database. No code may
    // acquire the write lock while holding this open lock; it is released
    // before the database handle is returned.
    let lock = sidecar_open_lock(db_path);
    let _guard = lock
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    open_voting_db_unlocked(db_path, account_uuid)
}

fn open_voting_db_unlocked(
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
    fn open_voting_db_serializes_concurrent_v15_migration() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let sidecar_path = zcash_voting::storage::VotingDb::wallet_sidecar_path(&db_path);

        // Create the current schema through the public API, then faithfully
        // remove the v16 and v17 additions to model a released v15 sidecar.
        drop(open_voting_db(db_path.to_str().unwrap(), "wallet-1").unwrap());
        let conn = rusqlite::Connection::open(&sidecar_path).unwrap();
        conn.execute_batch(
            "DROP TRIGGER clear_helper_share_plan_on_vote_generation_change;
             DROP TABLE helper_share_plans;
             ALTER TABLE share_delegations DROP COLUMN target_count;
             ALTER TABLE share_delegations DROP COLUMN attempting_urls;
             ALTER TABLE share_delegations DROP COLUMN ambiguous_urls;
             PRAGMA user_version = 15;",
        )
        .unwrap();
        drop(conn);

        let db_path = Arc::new(db_path.to_string_lossy().into_owned());
        let start = Arc::new(Barrier::new(16));
        let openers = (0..16)
            .map(|_| {
                let db_path = Arc::clone(&db_path);
                let start = Arc::clone(&start);
                std::thread::spawn(move || {
                    start.wait();
                    open_voting_db(&db_path, "wallet-1").map(|_| ())
                })
            })
            .collect::<Vec<_>>();

        for opener in openers {
            opener.join().unwrap().unwrap();
        }

        let conn = rusqlite::Connection::open(&sidecar_path).unwrap();
        let version: u32 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        let integrity: String = conn
            .query_row("PRAGMA integrity_check", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, 17);
        assert_eq!(integrity, "ok");
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
    fn locked_open_serializes_real_same_sidecar_writes() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = Arc::new(
            temp_dir
                .path()
                .join("zcash_wallet.db")
                .to_string_lossy()
                .into_owned(),
        );
        let start = Arc::new(Barrier::new(3));

        let writers = (0..3)
            .map(|writer| {
                let db_path = Arc::clone(&db_path);
                let start = Arc::clone(&start);
                std::thread::spawn(move || {
                    start.wait();
                    with_open_voting_db_write(&db_path, "wallet-1", |db| {
                        db.conn()
                            .execute_batch(
                                "CREATE TABLE IF NOT EXISTS concurrency_probe (
                                    writer INTEGER NOT NULL
                                 );",
                            )
                            .map_err(|error| error.to_string())?;
                        db.conn()
                            .execute(
                                "INSERT INTO concurrency_probe (writer) VALUES (?1)",
                                [writer],
                            )
                            .map_err(|error| error.to_string())?;
                        Ok(())
                    })
                    .map(|_| ())
                })
            })
            .collect::<Vec<_>>();

        for writer in writers {
            writer.join().unwrap().unwrap();
        }

        let db = open_voting_db(&db_path, "wallet-1").unwrap();
        let count: u32 = db
            .conn()
            .query_row("SELECT COUNT(*) FROM concurrency_probe", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(count, 3);
    }

    #[test]
    fn sidecar_write_locks_allow_different_wallets_to_overlap() {
        let temp_dir = tempfile::tempdir().unwrap();
        let start = Arc::new(Barrier::new(2));
        let active = Arc::new(AtomicUsize::new(0));
        let max_active = Arc::new(AtomicUsize::new(0));

        let writers = (0..2)
            .map(|wallet| {
                let db_path = temp_dir
                    .path()
                    .join(format!("wallet-{wallet}.db"))
                    .to_string_lossy()
                    .into_owned();
                let start = Arc::clone(&start);
                let active = Arc::clone(&active);
                let max_active = Arc::clone(&max_active);
                std::thread::spawn(move || {
                    start.wait();
                    with_open_voting_db_write(&db_path, "wallet-1", |_| {
                        let now_active = active.fetch_add(1, Ordering::SeqCst) + 1;
                        max_active.fetch_max(now_active, Ordering::SeqCst);
                        std::thread::sleep(std::time::Duration::from_millis(100));
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
        assert_eq!(max_active.load(Ordering::SeqCst), 2);
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

    #[test]
    fn coordinated_retry_only_locks_after_the_initial_writer_race() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir
            .path()
            .join("zcash_wallet.db")
            .to_string_lossy()
            .into_owned();
        let attempts = AtomicUsize::new(0);

        let result = retry_voting_db_locks_coordinated(&db_path, || {
            let attempt = attempts.fetch_add(1, Ordering::SeqCst);
            let lock = sidecar_write_lock(&db_path);
            if attempt == 0 {
                assert!(lock.try_lock().is_ok(), "first attempt must stay parallel");
                Err("database is locked".to_string())
            } else {
                assert!(
                    lock.try_lock().is_err(),
                    "retry must hold the sidecar writer coordinator"
                );
                Ok(42)
            }
        });

        assert_eq!(result.unwrap(), 42);
        assert_eq!(attempts.load(Ordering::SeqCst), 2);
    }
}
