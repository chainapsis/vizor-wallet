use std::{
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex, OnceLock,
    },
    time::{Duration, Instant},
};

use rand::rngs::OsRng;
use zcash_client_sqlite::{util::SystemClock, WalletDb};

use crate::wallet::network::WalletNetwork;

pub(crate) type WalletDatabase = WalletDb<rusqlite::Connection, WalletNetwork, SystemClock, OsRng>;

/// User-driven wallet operations can afford a longer wait for a short sync write.
///
/// This is the tier for any write a user is waiting on, including migration
/// stop, scheduled broadcast, and coordinator advance. `scan_cached_blocks`
/// runs a whole batch inside one transaction, so on a large wallet the writer
/// can be held for seconds; a user-driven write must outlast that rather than
/// fail. The two `wallet::db::tests` busy-timeout tests pin both directions.
pub(crate) const WALLET_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(10);
/// Account creation/import runs after sync is paused, so a shorter wait exposes real stalls.
pub(crate) const ACCOUNT_MUTATION_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(5);
/// The sync loop should absorb brief read/write overlap without stretching cancel too far.
pub(crate) const SYNC_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);
/// Reads only. A write opened with this gives up while a sync batch is still
/// committing -- use [`WALLET_DB_BUSY_TIMEOUT`] for writes a user is waiting on.
pub(crate) const READ_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);

/// Seqlock-style write epoch for in-process wallet-summary cache invalidation.
///
/// Even values mean no write is in progress. Entering
/// [`with_wallet_db_write_lock`] makes the epoch odd; the matching RAII
/// drop (including unwind) makes it even again. Summary readers publish
/// only when the epoch is even and unchanged across the load.
static WALLET_DB_WRITE_EPOCH: AtomicU64 = AtomicU64::new(0);

struct WriteEpochGuard;

impl Drop for WriteEpochGuard {
    fn drop(&mut self) {
        WALLET_DB_WRITE_EPOCH.fetch_add(1, Ordering::Release);
    }
}

/// Current wallet-DB write epoch. Even = idle; odd = a locked write is active.
pub(crate) fn wallet_db_write_epoch() -> u64 {
    WALLET_DB_WRITE_EPOCH.load(Ordering::Acquire)
}

pub(crate) fn open_wallet_db_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, true)?;
    Ok(WalletDb::from_connection(conn, network, SystemClock, OsRng))
}

pub(crate) fn open_wallet_db_for_read_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, false)?;
    Ok(WalletDb::from_connection(conn, network, SystemClock, OsRng))
}

pub(crate) fn open_wallet_db_readonly_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(timeout))?;
    Ok(WalletDb::from_connection(conn, network, SystemClock, OsRng))
}

pub(crate) fn open_wallet_raw_conn_with_timeout(
    db_path: &str,
    timeout: Duration,
) -> Result<rusqlite::Connection, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, true)?;
    Ok(conn)
}

fn configure_wallet_connection(
    conn: &rusqlite::Connection,
    timeout: Duration,
    ensure_wal: bool,
) -> Result<(), String> {
    conn.busy_timeout(timeout)
        .map_err(|e| format!("Failed to configure wallet DB busy timeout: {e}"))?;
    if ensure_wal {
        let journal_mode: String = conn
            .pragma_update_and_check(None, "journal_mode", "WAL", |row| row.get(0))
            .map_err(|e| format!("Failed to enable wallet DB WAL mode: {e}"))?;
        if !journal_mode.eq_ignore_ascii_case("wal") {
            return Err(format!(
                "Failed to enable wallet DB WAL mode: SQLite returned journal_mode={journal_mode}"
            ));
        }
    }
    rusqlite::vtab::array::load_module(conn)
        .map_err(|e| format!("Failed to load SQLite array module: {e}"))?;
    Ok(())
}

pub(crate) fn with_wallet_db_write_lock<T>(
    operation: &'static str,
    write: impl FnOnce() -> T,
) -> T {
    // Serializes wallet-DB writes across FRB foreground calls, C-FFI
    // background sync calls, and Rust sync tasks inside this process. This
    // does not coordinate with a separate OS process that opens the same DB.
    //
    // Also drives a seqlock-style epoch so the process-wide wallet-summary
    // cache can reject loads that overlapped a write. The epoch is global
    // (not keyed by path), which may over-invalidate unrelated wallets —
    // correctness over precision.
    static WALLET_DB_WRITE_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

    let lock = WALLET_DB_WRITE_LOCK.get_or_init(|| Mutex::new(()));
    let wait_start = Instant::now();
    let guard = match lock.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            log::error!("wallet DB write lock poisoned while entering {operation}; continuing");
            poisoned.into_inner()
        }
    };

    let waited = wait_start.elapsed();
    if waited >= Duration::from_millis(50) {
        log::info!(
            "wallet DB write lock waited {:.3}s for {operation}",
            waited.as_secs_f64()
        );
    }

    // Odd while the write closure runs; Drop makes it even on every exit.
    WALLET_DB_WRITE_EPOCH.fetch_add(1, Ordering::AcqRel);
    let _epoch_guard = WriteEpochGuard;

    let hold_start = Instant::now();
    let result = write();
    let held = hold_start.elapsed();
    if held >= Duration::from_secs(1) {
        log::info!(
            "wallet DB write lock held {:.3}s by {operation}",
            held.as_secs_f64()
        );
    }

    drop(_epoch_guard);
    drop(guard);
    result
}

/// Raw connection for a wallet write a user is waiting on.
///
/// Two settings, and both are needed for either to matter:
///
/// - [`WALLET_DB_BUSY_TIMEOUT`], so the write waits out a sync batch rather
///   than failing. `scan_cached_blocks` runs a whole batch in one transaction,
///   which on a large wallet holds the writer for seconds.
/// - [`rusqlite::TransactionBehavior::Immediate`], so that wait can actually
///   happen. SQLite deliberately does *not* invoke the busy handler when a
///   deferred transaction tries to upgrade a read to a write, because two
///   connections both waiting to upgrade would deadlock; such a transaction
///   gets `SQLITE_BUSY` immediately no matter how large the timeout is. Taking
///   the write lock at `BEGIN` puts the wait back under the timeout.
///
/// `unchecked_transaction()` reads this connection-level default, so callers
/// need no change beyond opening through this function.
pub(crate) fn open_wallet_write_conn(db_path: &str) -> Result<rusqlite::Connection, String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
    conn.set_transaction_behavior(rusqlite::TransactionBehavior::Immediate);
    Ok(conn)
}

pub(crate) fn open_readonly_conn_with_timeout(
    db_path: &str,
    timeout: Option<Duration>,
) -> Result<rusqlite::Connection, String> {
    let conn =
        rusqlite::Connection::open_with_flags(db_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .map_err(|e| format!("Failed to open DB: {e}"))?;
    if let Some(timeout) = timeout {
        conn.busy_timeout(timeout)
            .map_err(|e| format!("Failed to configure DB busy timeout: {e}"))?;
    }
    // Same module write paths get via `configure_wallet_connection`.
    // Needed so read-only history queries can bind txid sets with `rarray`
    // instead of re-scanning `v_transactions` (and its `raw` blobs).
    rusqlite::vtab::array::load_module(&conn)
        .map_err(|e| format!("Failed to load SQLite array module: {e}"))?;
    Ok(conn)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::panic::{catch_unwind, AssertUnwindSafe};

    #[test]
    fn configure_wallet_connection_enables_wal_mode() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();

        configure_wallet_connection(&conn, Duration::from_millis(1), true).unwrap();

        let journal_mode: String = conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_eq!(journal_mode.to_ascii_lowercase(), "wal");
    }

    #[test]
    fn configure_wallet_connection_can_skip_wal_for_read_paths() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();

        configure_wallet_connection(&conn, Duration::from_millis(1), false).unwrap();

        let journal_mode: String = conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_ne!(journal_mode.to_ascii_lowercase(), "wal");
    }

    /// Holds a write transaction on `path` for `hold`, then commits.
    ///
    /// Stands in for a scan batch: `scan_cached_blocks` runs a whole batch
    /// inside one transaction, so on a large wallet the DB has an open writer
    /// for as long as that batch takes.
    fn hold_writer_for(
        path: std::path::PathBuf,
        hold: Duration,
    ) -> (std::thread::JoinHandle<()>, std::sync::mpsc::Receiver<()>) {
        let (tx, rx) = std::sync::mpsc::channel();
        let handle = std::thread::spawn(move || {
            let conn = rusqlite::Connection::open(&path).unwrap();
            conn.busy_timeout(Duration::from_secs(30)).unwrap();
            conn.execute_batch("BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS held (v);")
                .unwrap();
            tx.send(()).unwrap();
            std::thread::sleep(hold);
            conn.execute_batch("COMMIT").unwrap();
        });
        (handle, rx)
    }

    fn try_write(path: &std::path::Path, timeout: Duration) -> Result<(), rusqlite::Error> {
        let conn = rusqlite::Connection::open(path).unwrap();
        configure_wallet_connection(&conn, timeout, true).unwrap();
        conn.execute_batch("CREATE TABLE IF NOT EXISTS other (v)")
    }

    fn wal_db(dir: &tempfile::TempDir) -> std::path::PathBuf {
        let path = dir.path().join("wallet.db");
        let conn = rusqlite::Connection::open(&path).unwrap();
        configure_wallet_connection(&conn, Duration::from_secs(5), true).unwrap();
        path
    }

    /// A migration write opened with the *read* timeout gives up while a sync
    /// batch still holds the writer. The user sees a failed stop or a failed
    /// scheduled broadcast rather than a slow one.
    #[test]
    fn read_timeout_write_fails_under_a_long_sync_write() {
        let dir = tempfile::tempdir().unwrap();
        let path = wal_db(&dir);

        // 2x the read timeout, so a loaded CI box cannot accidentally satisfy
        // the wait and flip this assertion.
        let (writer, started) = hold_writer_for(path.clone(), READ_DB_BUSY_TIMEOUT * 2);
        started.recv().unwrap();

        let result = try_write(&path, READ_DB_BUSY_TIMEOUT);

        assert!(
            matches!(
                result,
                Err(rusqlite::Error::SqliteFailure(
                    rusqlite::ffi::Error {
                        code: rusqlite::ErrorCode::DatabaseBusy,
                        ..
                    },
                    _
                ))
            ),
            "expected SQLITE_BUSY from a read-timeout write under a longer sync write, got {result:?}"
        );
        writer.join().unwrap();
    }

    /// The user-operation timeout waits it out instead.
    #[test]
    fn wallet_timeout_write_survives_a_long_sync_write() {
        let dir = tempfile::tempdir().unwrap();
        let path = wal_db(&dir);

        // Same hold as the read-timeout case, so the pair differs only in the
        // timeout under test.
        let (writer, started) = hold_writer_for(path.clone(), READ_DB_BUSY_TIMEOUT * 2);
        started.recv().unwrap();

        let result = try_write(&path, WALLET_DB_BUSY_TIMEOUT);

        assert!(
            result.is_ok(),
            "a 10s user-operation timeout absorbs a longer sync write, got {result:?}"
        );
        writer.join().unwrap();
    }

    /// Seeds a row so a transaction can read before it writes.
    fn seeded_wal_db(dir: &tempfile::TempDir) -> std::path::PathBuf {
        let path = wal_db(dir);
        let conn = rusqlite::Connection::open(&path).unwrap();
        conn.execute_batch(
            "CREATE TABLE rows (id INTEGER PRIMARY KEY, v INTEGER); INSERT INTO rows VALUES (1, 1);",
        )
        .unwrap();
        path
    }

    /// Why [`open_wallet_write_conn`] sets `Immediate`.
    ///
    /// A deferred transaction that reads before it writes has to upgrade its
    /// read lock. SQLite skips the busy handler for that upgrade -- two
    /// connections both waiting to upgrade would deadlock -- so it fails
    /// instantly however large the timeout is. A long busy timeout alone does
    /// not fix a read-then-write transaction.
    #[test]
    fn deferred_read_then_write_ignores_the_busy_timeout() {
        let dir = tempfile::tempdir().unwrap();
        let path = seeded_wal_db(&dir);

        let (writer, started) = hold_writer_for(path.clone(), READ_DB_BUSY_TIMEOUT * 2);
        started.recv().unwrap();

        let conn = rusqlite::Connection::open(&path).unwrap();
        configure_wallet_connection(&conn, WALLET_DB_BUSY_TIMEOUT, true).unwrap();
        let tx = conn.unchecked_transaction().unwrap();
        let _: i64 = tx
            .query_row("SELECT v FROM rows WHERE id = 1", [], |row| row.get(0))
            .unwrap();
        let result = tx.execute("UPDATE rows SET v = 2 WHERE id = 1", []);

        assert!(
            result.is_err(),
            "a deferred read-then-write should fail instantly despite a 10s timeout, got {result:?}"
        );
        writer.join().unwrap();
    }

    /// And that taking the write lock at `BEGIN` puts the wait back under the
    /// timeout, which is what `open_wallet_write_conn` configures.
    #[test]
    fn immediate_read_then_write_waits_out_the_sync_write() {
        let dir = tempfile::tempdir().unwrap();
        let path = seeded_wal_db(&dir);

        let (writer, started) = hold_writer_for(path.clone(), READ_DB_BUSY_TIMEOUT * 2);
        started.recv().unwrap();

        let conn = open_wallet_write_conn(path.to_str().unwrap()).unwrap();
        let tx = conn.unchecked_transaction().unwrap();
        let _: i64 = tx
            .query_row("SELECT v FROM rows WHERE id = 1", [], |row| row.get(0))
            .unwrap();
        let result = tx.execute("UPDATE rows SET v = 2 WHERE id = 1", []);

        assert!(
            result.is_ok(),
            "an immediate transaction should wait out the sync write, got {result:?}"
        );
        writer.join().unwrap();
    }

    #[test]
    fn with_wallet_db_write_lock_runs_closure() {
        let mut called = false;

        with_wallet_db_write_lock("test", || {
            called = true;
        });

        assert!(called);
    }

    #[test]
    fn write_lock_epoch_is_odd_inside_critical_section() {
        // Under `cargo test` parallelism other suites may hold the write lock,
        // so only assert the epoch parity that is exclusive to our section.
        with_wallet_db_write_lock("test_epoch", || {
            assert_eq!(wallet_db_write_epoch() % 2, 1);
        });
    }

    #[test]
    fn write_lock_epoch_completes_on_unwind() {
        let result = catch_unwind(AssertUnwindSafe(|| {
            with_wallet_db_write_lock("test_panic", || {
                panic!("force unwind while write epoch is odd");
            });
        }));
        assert!(result.is_err());

        // The Drop guard must have made the epoch even again and released the
        // mutex; otherwise this acquisition would hang or see a stuck odd epoch
        // owned by the panicked section.
        with_wallet_db_write_lock("test_after_panic", || {
            assert_eq!(wallet_db_write_epoch() % 2, 1);
        });
    }
}
