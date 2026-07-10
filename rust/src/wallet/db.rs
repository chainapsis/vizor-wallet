use std::{
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};

use rand::rngs::OsRng;
use zcash_client_sqlite::{util::SystemClock, WalletDb};

use crate::wallet::network::WalletNetwork;

pub(crate) type WalletDatabase = WalletDb<rusqlite::Connection, WalletNetwork, SystemClock, OsRng>;

/// User-driven wallet operations can afford a longer wait for a short sync write.
pub(crate) const WALLET_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(10);
/// Account creation/import runs after sync is paused, so a shorter wait exposes real stalls.
pub(crate) const ACCOUNT_MUTATION_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(5);
/// The sync loop should absorb brief read/write overlap without stretching cancel too far.
pub(crate) const SYNC_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);
pub(crate) const READ_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);

/// SQLite tuning profile for wallet database connections.
///
/// Only the sync engine may use `Sync`: its writes are derived from chain
/// data and can be replayed after an interrupted commit. Account mutations,
/// sends, and other interactive operations keep SQLite's durable defaults.
#[derive(Clone, Copy)]
enum ConnTuning {
    Interactive,
    Sync,
}

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const SYNC_CONN_CACHE_SIZE: i64 = -65_536; // 64 MiB
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const SYNC_CONN_CACHE_SIZE: i64 = -32_768; // 32 MiB

const SYNC_CONN_WAL_AUTOCHECKPOINT_PAGES: i64 = 10_000;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
const SYNC_CONN_MMAP_BYTES: i64 = 268_435_456; // 256 MiB
#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
const SYNC_CONN_MMAP_BYTES: i64 = 67_108_864; // 64 MiB

pub(crate) fn open_wallet_db_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, true, ConnTuning::Interactive)?;
    Ok(WalletDb::from_connection(conn, network, SystemClock, OsRng))
}

/// Opens the sync engine's long-lived, chain-derived bulk-write connection.
pub(crate) fn open_sync_wallet_db_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, true, ConnTuning::Sync)?;
    Ok(WalletDb::from_connection(conn, network, SystemClock, OsRng))
}

pub(crate) fn open_wallet_db_for_read_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, false, ConnTuning::Interactive)?;
    Ok(WalletDb::from_connection(conn, network, SystemClock, OsRng))
}

pub(crate) fn open_wallet_raw_conn_with_timeout(
    db_path: &str,
    timeout: Duration,
) -> Result<rusqlite::Connection, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, true, ConnTuning::Interactive)?;
    Ok(conn)
}

fn configure_wallet_connection(
    conn: &rusqlite::Connection,
    timeout: Duration,
    ensure_wal: bool,
    tuning: ConnTuning,
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
    if matches!(tuning, ConnTuning::Sync) {
        debug_assert!(ensure_wal, "sync tuning requires WAL mode");
        // These are performance hints, not correctness requirements. If a
        // platform SQLite build rejects one, retain its safer default instead
        // of making wallet sync unavailable.
        apply_optional_pragma(conn, "mmap_size", SYNC_CONN_MMAP_BYTES);
        #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
        apply_optional_pragma(conn, "temp_store", "MEMORY");
        apply_optional_pragma(conn, "cache_size", SYNC_CONN_CACHE_SIZE);
        apply_optional_pragma(conn, "synchronous", "NORMAL");
        apply_optional_pragma(
            conn,
            "wal_autocheckpoint",
            SYNC_CONN_WAL_AUTOCHECKPOINT_PAGES,
        );
    }
    rusqlite::vtab::array::load_module(conn)
        .map_err(|e| format!("Failed to load SQLite array module: {e}"))?;
    Ok(())
}

fn apply_optional_pragma(conn: &rusqlite::Connection, name: &str, value: impl rusqlite::ToSql) {
    if let Err(e) = conn.pragma_update(None, name, value) {
        log::warn!("wallet DB: optional sync PRAGMA {name} was not applied: {e}");
    }
}

/// Reclaims the WAL accumulated by a completed bulk sync. Concurrent readers
/// can make TRUNCATE report busy; that is harmless and is retried after the
/// next successful sync rather than failing this one.
pub(crate) fn truncate_wallet_wal_best_effort(db_path: &str) {
    let outcome = (|| -> Result<(i64, i64, i64), String> {
        let conn = rusqlite::Connection::open(db_path).map_err(|e| format!("open: {e}"))?;
        conn.busy_timeout(READ_DB_BUSY_TIMEOUT)
            .map_err(|e| format!("busy_timeout: {e}"))?;
        conn.query_row("PRAGMA wal_checkpoint(TRUNCATE)", [], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })
        .map_err(|e| format!("wal_checkpoint: {e}"))
    })();

    match outcome {
        Ok((0, wal_frames, checkpointed)) => {
            log::info!("wallet DB WAL truncated ({checkpointed}/{wal_frames} frames checkpointed)")
        }
        Ok((_, wal_frames, checkpointed)) => log::info!(
            "wallet DB WAL truncate skipped (busy; {checkpointed}/{wal_frames} frames checkpointed)"
        ),
        Err(e) => log::warn!("wallet DB WAL truncate failed (harmless): {e}"),
    }
}

pub(crate) fn with_wallet_db_write_lock<T>(
    operation: &'static str,
    write: impl FnOnce() -> T,
) -> T {
    // Serializes wallet-DB writes across FRB foreground calls, C-FFI
    // background sync calls, and Rust sync tasks inside this process. This
    // does not coordinate with a separate OS process that opens the same DB.
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

    let hold_start = Instant::now();
    let result = write();
    let held = hold_start.elapsed();
    if held >= Duration::from_secs(1) {
        log::info!(
            "wallet DB write lock held {:.3}s by {operation}",
            held.as_secs_f64()
        );
    }

    drop(guard);
    result
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
    Ok(conn)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pragma_i64(conn: &rusqlite::Connection, pragma: &str) -> i64 {
        conn.pragma_query_value(None, pragma, |row| row.get(0))
            .unwrap()
    }

    #[test]
    fn configure_wallet_connection_enables_wal_mode() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();

        configure_wallet_connection(
            &conn,
            Duration::from_millis(1),
            true,
            ConnTuning::Interactive,
        )
        .unwrap();

        let journal_mode: String = conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_eq!(journal_mode.to_ascii_lowercase(), "wal");
    }

    #[test]
    fn configure_wallet_connection_can_skip_wal_for_read_paths() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();

        configure_wallet_connection(
            &conn,
            Duration::from_millis(1),
            false,
            ConnTuning::Interactive,
        )
        .unwrap();

        let journal_mode: String = conn
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .unwrap();
        assert_ne!(journal_mode.to_ascii_lowercase(), "wal");
    }

    #[test]
    fn sync_tuning_applies_only_bulk_write_pragmas() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();

        configure_wallet_connection(&conn, Duration::from_millis(1), true, ConnTuning::Sync)
            .unwrap();

        assert_eq!(pragma_i64(&conn, "synchronous"), 1); // NORMAL
        assert_eq!(pragma_i64(&conn, "cache_size"), SYNC_CONN_CACHE_SIZE);
        assert_eq!(
            pragma_i64(&conn, "wal_autocheckpoint"),
            SYNC_CONN_WAL_AUTOCHECKPOINT_PAGES
        );
        assert_eq!(pragma_i64(&conn, "temp_store"), 2); // MEMORY
        assert_eq!(pragma_i64(&conn, "mmap_size"), SYNC_CONN_MMAP_BYTES);
    }

    #[test]
    fn interactive_tuning_keeps_durable_defaults() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        let default_temp_store = pragma_i64(&conn, "temp_store");
        let default_mmap_size = pragma_i64(&conn, "mmap_size");

        configure_wallet_connection(
            &conn,
            Duration::from_millis(1),
            true,
            ConnTuning::Interactive,
        )
        .unwrap();

        assert_eq!(pragma_i64(&conn, "synchronous"), 2); // FULL
        assert_eq!(pragma_i64(&conn, "wal_autocheckpoint"), 1_000);
        assert_eq!(pragma_i64(&conn, "temp_store"), default_temp_store);
        assert_eq!(pragma_i64(&conn, "mmap_size"), default_mmap_size);
    }

    #[test]
    fn truncate_wallet_wal_best_effort_resets_the_wal_file() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();

        configure_wallet_connection(&conn, Duration::from_millis(100), true, ConnTuning::Sync)
            .unwrap();
        conn.execute_batch("CREATE TABLE t (x BLOB);").unwrap();
        for _ in 0..50 {
            conn.execute("INSERT INTO t VALUES (randomblob(4096))", [])
                .unwrap();
        }

        let wal_path = format!("{db_path}-wal");
        assert!(std::fs::metadata(&wal_path).unwrap().len() > 0);
        truncate_wallet_wal_best_effort(db_path);
        assert_eq!(std::fs::metadata(&wal_path).unwrap().len(), 0);
    }

    #[test]
    fn with_wallet_db_write_lock_runs_closure() {
        let mut called = false;

        with_wallet_db_write_lock("test", || {
            called = true;
        });

        assert!(called);
    }
}
