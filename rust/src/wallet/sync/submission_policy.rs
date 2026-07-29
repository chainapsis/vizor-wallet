use std::io::Cursor;

use rusqlite::{params, Connection, OptionalExtension};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BranchId;

use crate::wallet::db::{
    open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, WALLET_DB_BUSY_TIMEOUT,
};

use super::open_readonly_conn;

pub(crate) const SEPARATE_RELAY_TABLE: &str = "ext_vizor_separate_relay_transactions";

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SeparateRelayTransaction {
    pub(crate) raw_tx: Vec<u8>,
    pub(crate) expiry_height: u32,
}

/// Marks a denomination transaction before it is submitted through a separate relay.
pub(crate) fn register_separate_relay_transaction(
    db_path: &str,
    run_id: &str,
    expected_txid_hex: &str,
    raw_tx: &[u8],
    expiry_height: u32,
) -> Result<(), String> {
    if run_id.trim().is_empty() {
        return Err("Separate-relay transaction run ID is empty".to_string());
    }
    let tx = validate_transaction(expected_txid_hex, raw_tx, expiry_height)?;
    let txid = tx.txid();

    with_wallet_db_write_lock(
        "submission_policy.register_separate_relay_transaction",
        || {
            let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
            ensure_separate_relay_table(&conn)?;
            store_validated_marker(&conn, run_id, txid, raw_tx, expiry_height)
        },
    )
}

fn store_validated_marker(
    conn: &Connection,
    run_id: &str,
    txid: TxId,
    raw_tx: &[u8],
    expiry_height: u32,
) -> Result<(), String> {
    let existing = conn
        .query_row(
            &format!(
                "SELECT run_id, raw, expiry_height FROM {SEPARATE_RELAY_TABLE} WHERE txid = ?1"
            ),
            params![txid.as_ref()],
            |row| {
                Ok((
                    row.get::<_, Option<String>>(0)?,
                    row.get::<_, Vec<u8>>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read separate-relay transaction marker: {e}"))?;

    if let Some((stored_run_id, stored_raw, stored_expiry)) = existing {
        if stored_run_id
            .as_deref()
            .is_none_or(|stored| stored == run_id)
            && stored_expiry == i64::from(expiry_height)
        {
            if stored_run_id.as_deref() != Some(run_id) || stored_raw != raw_tx {
                conn.execute(
                    &format!(
                        "UPDATE {SEPARATE_RELAY_TABLE} SET run_id = ?1, raw = ?2 WHERE txid = ?3"
                    ),
                    params![run_id, raw_tx, txid.as_ref()],
                )
                .map_err(|e| format!("Update separate-relay transaction marker: {e}"))?;
            }
            return Ok(());
        }
        return Err(format!(
            "Separate-relay transaction marker conflicts with {txid}"
        ));
    }

    conn.execute(
        &format!(
            "INSERT INTO {SEPARATE_RELAY_TABLE} (txid, run_id, raw, expiry_height) VALUES (?1, ?2, ?3, ?4)"
        ),
        params![txid.as_ref(), run_id, raw_tx, i64::from(expiry_height)],
    )
    .map_err(|e| format!("Store separate-relay transaction marker: {e}"))?;
    Ok(())
}

pub(crate) fn separate_relay_transaction(
    db_path: &str,
    txid: TxId,
) -> Result<Option<SeparateRelayTransaction>, String> {
    let conn = open_readonly_conn(db_path)?;
    if !separate_relay_table_exists(&conn)? {
        return Ok(None);
    }

    let row = conn
        .query_row(
            &format!(
                "SELECT run_id, raw, expiry_height FROM {SEPARATE_RELAY_TABLE} WHERE txid = ?1"
            ),
            params![txid.as_ref()],
            |row| {
                Ok((
                    row.get::<_, Option<String>>(0)?,
                    row.get::<_, Vec<u8>>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read separate-relay transaction marker: {e}"))?;

    let Some((run_id, raw_tx, expiry_height)) = row else {
        return Ok(None);
    };
    run_id
        .filter(|run_id| !run_id.trim().is_empty())
        .ok_or_else(|| format!("Separate-relay transaction {txid} has no owning migration run"))?;
    let expiry_height = u32::try_from(expiry_height)
        .map_err(|_| format!("Separate-relay transaction {txid} has an invalid expiry height"))?;
    validate_transaction(&txid.to_string(), &raw_tx, expiry_height)?;

    Ok(Some(SeparateRelayTransaction {
        raw_tx,
        expiry_height,
    }))
}

pub(super) fn separate_relay_table_exists(conn: &Connection) -> Result<bool, String> {
    conn.query_row(
        "SELECT EXISTS(
             SELECT 1 FROM sqlite_schema
             WHERE type = 'table' AND name = ?1
         )",
        [SEPARATE_RELAY_TABLE],
        |row| row.get(0),
    )
    .map_err(|e| format!("Inspect separate-relay transaction markers: {e}"))
}

pub(super) fn ensure_separate_relay_table(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "CREATE TABLE IF NOT EXISTS {SEPARATE_RELAY_TABLE} (
             txid BLOB PRIMARY KEY NOT NULL CHECK(length(txid) = 32),
             run_id TEXT NOT NULL CHECK(length(trim(run_id)) > 0),
             raw BLOB NOT NULL,
             expiry_height INTEGER NOT NULL CHECK(expiry_height > 0 AND expiry_height <= 4294967295)
         ) WITHOUT ROWID;"
    ))
    .map_err(|e| format!("Create separate-relay transaction marker table: {e}"))?;
    let has_run_id = conn
        .query_row(
            "SELECT 1 FROM pragma_table_info(?1) WHERE name = 'run_id'",
            [SEPARATE_RELAY_TABLE],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| format!("Inspect separate-relay marker ownership: {e}"))?
        .is_some();
    if !has_run_id {
        conn.execute(
            &format!("ALTER TABLE {SEPARATE_RELAY_TABLE} ADD COLUMN run_id TEXT"),
            [],
        )
        .map_err(|e| format!("Add separate-relay marker ownership: {e}"))?;
    }
    Ok(())
}

fn validate_transaction(
    expected_txid_hex: &str,
    raw_tx: &[u8],
    expiry_height: u32,
) -> Result<Transaction, String> {
    if expiry_height == 0 {
        return Err("Separate-relay transactions require a nonzero expiry height".to_string());
    }

    let mut reader = Cursor::new(raw_tx);
    let tx = Transaction::read(&mut reader, BranchId::Sapling)
        .map_err(|e| format!("Parse separate-relay transaction: {e}"))?;
    if reader.position() != raw_tx.len() as u64 {
        return Err("Separate-relay transaction has trailing bytes".to_string());
    }
    if !tx
        .txid()
        .to_string()
        .eq_ignore_ascii_case(expected_txid_hex)
    {
        return Err(format!(
            "Separate-relay transaction does not match expected txid {expected_txid_hex}"
        ));
    }
    if u32::from(tx.expiry_height()) != expiry_height {
        return Err(format!(
            "Separate-relay transaction {expected_txid_hex} does not match expiry height {expiry_height}"
        ));
    }
    if tx.sapling_bundle().is_none()
        && tx.orchard_bundle().is_none()
        && tx.ironwood_bundle().is_none()
    {
        return Err(format!(
            "Separate-relay transaction {expected_txid_hex} is not shielded"
        ));
    }

    Ok(tx)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absent_table_is_an_unmarked_wallet() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let txid = TxId::from_bytes([7; 32]);

        assert_eq!(
            separate_relay_transaction(file.path().to_str().unwrap(), txid).unwrap(),
            None
        );
    }

    #[test]
    fn corrupt_marker_fails_closed() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        ensure_separate_relay_table(&conn).unwrap();
        let txid = TxId::from_bytes([8; 32]);
        conn.execute(
            &format!(
                "INSERT INTO {SEPARATE_RELAY_TABLE} (txid, run_id, raw, expiry_height) VALUES (?1, 'run-1', ?2, ?3)"
            ),
            params![txid.as_ref(), [1u8, 2, 3], 100i64],
        )
        .unwrap();
        drop(conn);

        assert!(separate_relay_transaction(file.path().to_str().unwrap(), txid).is_err());
    }

    #[test]
    fn zero_expiry_cannot_be_marked() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let error = register_separate_relay_transaction(
            file.path().to_str().unwrap(),
            "run-1",
            &"00".repeat(32),
            &[1, 2, 3],
            0,
        )
        .unwrap_err();

        assert!(error.contains("nonzero expiry"));
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        assert!(!separate_relay_table_exists(&conn).unwrap());
    }

    #[test]
    fn reproved_authorizing_bytes_replace_the_same_runs_marker() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        ensure_separate_relay_table(&conn).unwrap();
        let txid = TxId::from_bytes([9; 32]);

        store_validated_marker(&conn, "run-1", txid, &[1, 2, 3], 100).unwrap();
        store_validated_marker(&conn, "run-1", txid, &[4, 5, 6], 100).unwrap();

        let stored: Vec<u8> = conn
            .query_row(
                &format!("SELECT raw FROM {SEPARATE_RELAY_TABLE} WHERE txid = ?1"),
                params![txid.as_ref()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(stored, vec![4, 5, 6]);
        assert!(store_validated_marker(&conn, "run-2", txid, &[7], 100).is_err());
    }
}
