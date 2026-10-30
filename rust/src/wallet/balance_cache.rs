//! Best-effort display snapshots. These never participate in spend validation.
use rusqlite::{Connection, OpenFlags, OptionalExtension};
use std::time::Duration;

use super::db::open_readonly_conn_with_timeout;

const VERSION: i64 = 1;
const TIMEOUT: Duration = Duration::from_millis(100);

pub(crate) fn load(path: &str, network: &str, account: &str) -> Result<Option<String>, String> {
    let uuid = uuid::Uuid::parse_str(account).map_err(|e| e.to_string())?;
    let conn = open_readonly_conn_with_timeout(path, Some(TIMEOUT))?;
    if !exists(&conn)? {
        return Ok(None);
    }
    conn.query_row(
        "SELECT c.payload FROM ext_vizor_balance_cache c
         JOIN accounts a ON a.uuid = c.account_uuid
         WHERE c.account_uuid = ?1 AND c.network = ?2 AND c.version = ?3",
        rusqlite::params![uuid.as_bytes().as_slice(), network, VERSION],
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| e.to_string())
}

pub(crate) fn save(path: &str, network: &str, account: &str, payload: &str) -> Result<(), String> {
    if payload.len() > 16 * 1024 {
        return Err("Balance cache payload too large".to_string());
    }
    let uuid = uuid::Uuid::parse_str(account).map_err(|e| e.to_string())?;
    // Never create a wallet file: a queued write may reach Rust after reset.
    let mut conn = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_WRITE)
        .map_err(|e| e.to_string())?;
    conn.busy_timeout(TIMEOUT).map_err(|e| e.to_string())?;
    let tx = conn
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(|e| e.to_string())?;
    let present: bool = tx
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM accounts WHERE uuid = ?1)",
            [uuid.as_bytes().as_slice()],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;
    if !present {
        return Ok(());
    }
    tx.execute_batch(
        "CREATE TABLE IF NOT EXISTS ext_vizor_balance_cache (
            account_uuid BLOB PRIMARY KEY NOT NULL,
            network TEXT NOT NULL,
            version INTEGER NOT NULL,
            payload TEXT NOT NULL
        )",
    )
    .map_err(|e| e.to_string())?;
    tx.execute("INSERT INTO ext_vizor_balance_cache VALUES (?1, ?2, ?3, ?4)
                    ON CONFLICT(account_uuid) DO UPDATE SET
                    network = excluded.network, version = excluded.version, payload = excluded.payload",
            rusqlite::params![uuid.as_bytes().as_slice(), network, VERSION, payload])
            .map_err(|e| e.to_string())?;
    tx.commit().map_err(|e| e.to_string())
}

fn exists(conn: &Connection) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master
                   WHERE type = 'table' AND name = 'ext_vizor_balance_cache')",
        [],
        |row| row.get(0),
    )
    .map_err(|e| e.to_string())
}

pub(crate) fn delete_account(conn: &Connection, uuid: &[u8]) -> Result<(), String> {
    if exists(conn)? {
        conn.execute(
            "DELETE FROM ext_vizor_balance_cache WHERE account_uuid = ?1",
            [uuid],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshots_are_scoped_and_never_recreate_deleted_wallets() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        let first = uuid::Uuid::new_v4();
        let second = uuid::Uuid::new_v4();
        let conn = Connection::open(path).unwrap();
        conn.execute_batch("CREATE TABLE accounts (uuid BLOB PRIMARY KEY)")
            .unwrap();
        conn.execute(
            "INSERT INTO accounts VALUES (?1)",
            [first.as_bytes().as_slice()],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO accounts VALUES (?1)",
            [second.as_bytes().as_slice()],
        )
        .unwrap();
        assert_eq!(load(path, "mainnet", &first.to_string()).unwrap(), None);
        save(path, "mainnet", &first.to_string(), "first").unwrap();
        save(path, "mainnet", &second.to_string(), "second").unwrap();
        assert_eq!(
            load(path, "mainnet", &first.to_string())
                .unwrap()
                .as_deref(),
            Some("first")
        );
        assert_eq!(load(path, "testnet", &first.to_string()).unwrap(), None);
        conn.execute(
            "DELETE FROM accounts WHERE uuid = ?1",
            [first.as_bytes().as_slice()],
        )
        .unwrap();
        save(path, "mainnet", &first.to_string(), "late").unwrap();
        assert_eq!(load(path, "mainnet", &first.to_string()).unwrap(), None);
        delete_account(&conn, first.as_bytes()).unwrap();
        assert_eq!(
            load(path, "mainnet", &second.to_string())
                .unwrap()
                .as_deref(),
            Some("second")
        );
        drop(conn);
        std::fs::remove_file(path).unwrap();
        assert!(save(path, "mainnet", &second.to_string(), "late").is_err());
        assert!(!std::path::Path::new(path).exists());
    }
}
