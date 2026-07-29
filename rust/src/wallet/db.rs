use std::{
    sync::{Mutex, OnceLock},
    time::{Duration, Instant},
};

use rand::rngs::OsRng;
use zcash_client_sqlite::{util::SystemClock, WalletDb};

use crate::wallet::network::WalletNetwork;

pub(crate) type WalletDatabase = WalletDb<rusqlite::Connection, WalletNetwork, SystemClock, OsRng>;

const ORCHARD_IRONWOOD_MIGRATIONS_TABLE: &str = "orchard_ironwood_migrations";
const ANCHOR_BUCKET_INTERVAL_COLUMN: &str = "anchor_bucket_interval";
// mobile/v0.0.18 used the production ZIP 318 schedule, whose anchor grid is
// fixed at 144 blocks. zcash_client_sqlite later made that implicit value
// persistent without changing the already-applied migration ID
// 7b2f6a41-9c3d-4e58-8a17-2f6b9d0c4e11, so init_wallet_db cannot repair an
// existing mobile/v0.0.18 database by itself.
const ZIP_318_ANCHOR_BUCKET_INTERVAL: u32 = 144;

/// User-driven wallet operations can afford a longer wait for a short sync write.
pub(crate) const WALLET_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(10);
/// Account creation/import runs after sync is paused, so a shorter wait exposes real stalls.
pub(crate) const ACCOUNT_MUTATION_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(5);
/// The sync loop should absorb brief read/write overlap without stretching cancel too far.
pub(crate) const SYNC_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);
pub(crate) const READ_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);

pub(crate) fn open_wallet_db_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    configure_wallet_connection(&conn, timeout, true)?;
    repair_legacy_ironwood_pool_migration_schema(&conn)?;
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
    repair_legacy_ironwood_pool_migration_schema(&conn)?;
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
    repair_legacy_ironwood_pool_migration_schema(&conn)?;
    Ok(conn)
}

fn repair_legacy_ironwood_pool_migration_schema(conn: &rusqlite::Connection) -> Result<(), String> {
    let table_exists: bool = conn
        .query_row(
            "SELECT EXISTS(
                 SELECT 1 FROM sqlite_schema
                 WHERE type = 'table' AND name = ?1
             )",
            [ORCHARD_IRONWOOD_MIGRATIONS_TABLE],
            |row| row.get(0),
        )
        .map_err(|e| format!("Failed to inspect Ironwood migration schema: {e}"))?;
    if !table_exists || ironwood_anchor_bucket_column_exists(conn)? {
        return Ok(());
    }

    let alter_result = conn.execute_batch(&format!(
        "ALTER TABLE {ORCHARD_IRONWOOD_MIGRATIONS_TABLE}
         ADD COLUMN {ANCHOR_BUCKET_INTERVAL_COLUMN} INTEGER NOT NULL
         DEFAULT {ZIP_318_ANCHOR_BUCKET_INTERVAL};"
    ));
    if let Err(error) = alter_result {
        // A second connection may have repaired the schema after our initial
        // inspection. Only accept the error when the required column now
        // exists; otherwise preserve the original failure.
        if !ironwood_anchor_bucket_column_exists(conn)? {
            return Err(format!(
                "Failed to upgrade legacy Ironwood migration schema: {error}"
            ));
        }
    }

    log::info!(
        "wallet DB compatibility: ensured {ORCHARD_IRONWOOD_MIGRATIONS_TABLE}.{ANCHOR_BUCKET_INTERVAL_COLUMN}"
    );
    Ok(())
}

fn ironwood_anchor_bucket_column_exists(conn: &rusqlite::Connection) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(
             SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2
         )",
        [
            ORCHARD_IRONWOOD_MIGRATIONS_TABLE,
            ANCHOR_BUCKET_INTERVAL_COLUMN,
        ],
        |row| row.get(0),
    )
    .map_err(|e| format!("Failed to inspect Ironwood migration columns: {e}"))
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

    #[test]
    fn with_wallet_db_write_lock_runs_closure() {
        let mut called = false;

        with_wallet_db_write_lock("test", || {
            called = true;
        });

        assert!(called);
    }

    #[test]
    fn repairs_mobile_v0_0_18_ironwood_pool_migration_schema() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE orchard_ironwood_migrations (
                 id INTEGER PRIMARY KEY,
                 account_id INTEGER NOT NULL,
                 status TEXT NOT NULL,
                 note_split_fee_buffer INTEGER NOT NULL,
                 note_split_change INTEGER,
                 note_split_prep_fees INTEGER NOT NULL,
                 note_split_total_input INTEGER NOT NULL,
                 note_split_total_migratable INTEGER NOT NULL
             );
             INSERT INTO orchard_ironwood_migrations (
                 id, account_id, status, note_split_fee_buffer, note_split_change,
                 note_split_prep_fees, note_split_total_input, note_split_total_migratable
             ) VALUES (7, 11, 'committed', 1000, NULL, 2000, 3000, 4000);",
        )
        .unwrap();

        repair_legacy_ironwood_pool_migration_schema(&conn).unwrap();
        repair_legacy_ironwood_pool_migration_schema(&conn).unwrap();

        assert!(ironwood_anchor_bucket_column_exists(&conn).unwrap());
        let repaired: (i64, u32) = conn
            .query_row(
                "SELECT id, anchor_bucket_interval
                 FROM orchard_ironwood_migrations",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(repaired, (7, ZIP_318_ANCHOR_BUCKET_INTERVAL));
    }

    #[test]
    fn preserves_existing_ironwood_anchor_bucket_interval() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE orchard_ironwood_migrations (
                 id INTEGER PRIMARY KEY,
                 anchor_bucket_interval INTEGER NOT NULL
             );
             INSERT INTO orchard_ironwood_migrations
                 (id, anchor_bucket_interval) VALUES (7, 12);",
        )
        .unwrap();

        repair_legacy_ironwood_pool_migration_schema(&conn).unwrap();

        let interval: u32 = conn
            .query_row(
                "SELECT anchor_bucket_interval
                 FROM orchard_ironwood_migrations WHERE id = 7",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(interval, 12);
    }

    #[test]
    fn legacy_ironwood_repair_is_noop_before_table_creation() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        repair_legacy_ironwood_pool_migration_schema(&conn).unwrap();
        assert!(!ironwood_anchor_bucket_column_exists(&conn).unwrap());
    }
}
