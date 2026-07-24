//! Durable bookkeeping for owner-scoped locks held by in-memory send proposals.
//!
//! `PROPOSAL_STORE` deliberately remains process-local, but the wallet locks it
//! owns live in SQLite. This side table records enough generic `OutputRef`
//! information to release locks left by a previous process without touching
//! long-lived migration owners.

use std::collections::BTreeMap;
use std::sync::LazyLock;

use rand::{rngs::OsRng, RngCore};
use rusqlite::{params, Connection};
use zcash_client_backend::{
    data_api::{WalletRead, WalletWrite},
    wallet::{LockOwner, OutputRef},
};
use zcash_primitives::transaction::TxId;
use zcash_protocol::{consensus::BlockHeight, PoolType, ShieldedPool};

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
};

use super::open_wallet_db;

const TABLE: &str = "vizor_send_proposal_locks";

static PROCESS_SESSION_ID: LazyLock<[u8; 16]> = LazyLock::new(|| {
    let mut bytes = [0; 16];
    OsRng.fill_bytes(&mut bytes);
    bytes
});

fn pool_code(pool: PoolType) -> i64 {
    match pool {
        PoolType::Transparent => 0,
        PoolType::Shielded(ShieldedPool::Sapling) => 2,
        PoolType::Shielded(ShieldedPool::Orchard) => 3,
        PoolType::Shielded(ShieldedPool::Ironwood) => 4,
    }
}

fn pool_from_code(code: i64) -> Result<PoolType, String> {
    match code {
        0 => Ok(PoolType::TRANSPARENT),
        2 => Ok(PoolType::SAPLING),
        3 => Ok(PoolType::ORCHARD),
        4 => Ok(PoolType::IRONWOOD),
        _ => Err(format!("Unknown persisted send lock pool code {code}")),
    }
}

fn ensure_schema(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "CREATE TABLE IF NOT EXISTS {TABLE} (
            owner BLOB NOT NULL,
            session_id BLOB NOT NULL,
            txid BLOB NOT NULL,
            pool INTEGER NOT NULL,
            output_index INTEGER NOT NULL,
            expiry_height INTEGER NOT NULL,
            retain_until_expiry INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (owner, txid, pool, output_index)
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_send_proposal_locks_session
            ON {TABLE}(session_id, retain_until_expiry);"
    ))
    .map_err(|e| format!("Initialize send proposal lock recovery schema: {e}"))
}

pub(super) fn persist(
    db_path: &str,
    owner: LockOwner,
    outputs: &[OutputRef],
    expiry_height: BlockHeight,
) -> Result<(), String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .transaction()
        .map_err(|e| format!("Begin send proposal lock persistence: {e}"))?;
    for output in outputs {
        tx.execute(
            &format!(
                "INSERT OR REPLACE INTO {TABLE}
                    (owner, session_id, txid, pool, output_index, expiry_height,
                     retain_until_expiry)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)"
            ),
            params![
                owner.as_bytes().as_slice(),
                PROCESS_SESSION_ID.as_slice(),
                output.txid().as_ref(),
                pool_code(output.pool()),
                output.output_index(),
                u32::from(expiry_height),
            ],
        )
        .map_err(|e| format!("Persist send proposal input lock: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit send proposal lock persistence: {e}"))
}

pub(super) fn remove(db_path: &str, owner: LockOwner) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.execute(
        &format!("DELETE FROM {TABLE} WHERE owner = ?1"),
        params![owner.as_bytes().as_slice()],
    )
    .map_err(|e| format!("Remove send proposal lock recovery rows: {e}"))?;
    Ok(())
}

pub(super) fn mark_retain_until_expiry(db_path: &str, owner: LockOwner) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {TABLE}
             SET retain_until_expiry = 1
             WHERE owner = ?1"
            ),
            params![owner.as_bytes().as_slice()],
        )
        .map_err(|e| format!("Retain send proposal lock until expiry: {e}"))?;
    if updated == 0 {
        return Err("Send proposal lock recovery row no longer exists".to_string());
    }
    Ok(())
}

pub(super) fn update_expiry(
    db_path: &str,
    owner: LockOwner,
    expiry_height: BlockHeight,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {TABLE}
                 SET expiry_height = ?2
                 WHERE owner = ?1"
            ),
            params![owner.as_bytes().as_slice(), u32::from(expiry_height),],
        )
        .map_err(|e| format!("Update persisted send proposal lock expiry: {e}"))?;
    if updated == 0 {
        return Err("Send proposal lock recovery row no longer exists".to_string());
    }
    Ok(())
}

fn read_previous_session_locks(
    conn: &Connection,
) -> Result<BTreeMap<LockOwner, (u32, bool, Vec<OutputRef>)>, String> {
    ensure_schema(conn)?;
    let mut stmt = conn
        .prepare(&format!(
            "SELECT owner, txid, pool, output_index, expiry_height,
                    retain_until_expiry
             FROM {TABLE}
             WHERE session_id <> ?1
             ORDER BY owner, txid, pool, output_index"
        ))
        .map_err(|e| format!("Prepare orphan send lock recovery query: {e}"))?;
    let rows = stmt
        .query_map(params![PROCESS_SESSION_ID.as_slice()], |row| {
            Ok((
                row.get::<_, Vec<u8>>(0)?,
                row.get::<_, Vec<u8>>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, u32>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, bool>(5)?,
            ))
        })
        .map_err(|e| format!("Query orphan send locks: {e}"))?;

    let mut locks = BTreeMap::new();
    for row in rows {
        let (owner_bytes, txid_bytes, pool, output_index, expiry, retain) =
            row.map_err(|e| format!("Read orphan send lock: {e}"))?;
        let owner = LockOwner::new(
            owner_bytes
                .try_into()
                .map_err(|_| "Persisted send lock owner is not 32 bytes")?,
        );
        let txid = TxId::from_bytes(
            txid_bytes
                .try_into()
                .map_err(|_| "Persisted send lock txid is not 32 bytes")?,
        );
        let entry = locks
            .entry(owner)
            .or_insert_with(|| (expiry, retain, Vec::new()));
        if entry.0 != expiry || entry.1 != retain {
            return Err("Persisted send lock owner has inconsistent metadata".to_string());
        }
        entry
            .2
            .push(OutputRef::new(txid, pool_from_code(pool)?, output_index));
    }
    Ok(locks)
}

fn should_release_after_restart(
    retain_until_expiry: bool,
    target_height: Option<u32>,
    expiry_height: u32,
) -> bool {
    !retain_until_expiry || target_height.is_some_and(|height| height >= expiry_height)
}

/// Releases only recoverable send locks left by an earlier process. Migration
/// locks are never registered in this table and therefore cannot be cleared by
/// this recovery pass. Ambiguous-broadcast locks remain until their recorded
/// expiry height has passed.
pub(crate) fn recover_previous_process(
    db_path: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    with_wallet_db_write_lock("proposal_locks.recover_previous_process", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        let locks = read_previous_session_locks(&conn)?;
        if locks.is_empty() {
            return Ok(());
        }
        drop(conn);

        let mut db = open_wallet_db(db_path, network)?;
        let target_height = db
            .get_target_and_anchor_heights(
                zcash_client_backend::data_api::wallet::ConfirmationsPolicy::default().trusted(),
            )
            .map_err(|e| format!("Read target height for send lock recovery: {e}"))?
            .map(|(height, _)| u32::from(height));

        let mut owners_to_remove = Vec::new();
        for (owner, (expiry, retain, outputs)) in locks {
            if !should_release_after_restart(retain, target_height, expiry) {
                continue;
            }
            for output in &outputs {
                db.unlock_output(output, owner)
                    .map_err(|e| format!("Release orphan send proposal input: {e}"))?;
            }
            owners_to_remove.push(owner);
        }
        drop(db);

        let mut conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        ensure_schema(&conn)?;
        let tx = conn
            .transaction()
            .map_err(|e| format!("Begin orphan send lock cleanup: {e}"))?;
        for owner in owners_to_remove {
            tx.execute(
                &format!("DELETE FROM {TABLE} WHERE owner = ?1"),
                params![owner.as_bytes().as_slice()],
            )
            .map_err(|e| format!("Delete recovered send lock rows: {e}"))?;
        }
        tx.commit()
            .map_err(|e| format!("Commit orphan send lock cleanup: {e}"))?;
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persisted_pool_codes_round_trip() {
        for pool in [
            PoolType::TRANSPARENT,
            PoolType::SAPLING,
            PoolType::ORCHARD,
            PoolType::IRONWOOD,
        ] {
            assert_eq!(pool_from_code(pool_code(pool)).unwrap(), pool);
        }
    }

    #[test]
    fn current_session_rows_are_not_orphans() {
        let conn = Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {TABLE}
                    (owner, session_id, txid, pool, output_index, expiry_height)
                 VALUES (?1, ?2, ?3, 3, 0, 100)"
            ),
            params![
                [1u8; 32].as_slice(),
                PROCESS_SESSION_ID.as_slice(),
                [2u8; 32].as_slice(),
            ],
        )
        .unwrap();
        assert!(read_previous_session_locks(&conn).unwrap().is_empty());
    }

    #[test]
    fn restart_releases_only_recoverable_or_expired_locks() {
        assert!(should_release_after_restart(false, None, 100));
        assert!(should_release_after_restart(false, Some(50), 100));
        assert!(!should_release_after_restart(true, None, 100));
        assert!(!should_release_after_restart(true, Some(99), 100));
        assert!(should_release_after_restart(true, Some(100), 100));
        assert!(should_release_after_restart(true, Some(101), 100));
    }

    #[test]
    fn hardware_handoff_policy_is_persisted_durably() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let owner = LockOwner::new([7; 32]);
        {
            let conn = Connection::open(&db_path).unwrap();
            ensure_schema(&conn).unwrap();
            conn.execute(
                &format!(
                    "INSERT INTO {TABLE}
                        (owner, session_id, txid, pool, output_index, expiry_height)
                     VALUES (?1, ?2, ?3, 3, 0, 100)"
                ),
                params![
                    owner.as_bytes().as_slice(),
                    PROCESS_SESSION_ID.as_slice(),
                    [9u8; 32].as_slice(),
                ],
            )
            .unwrap();
        }

        mark_retain_until_expiry(db_path.to_str().unwrap(), owner).unwrap();

        let conn = Connection::open(db_path).unwrap();
        let retain: bool = conn
            .query_row(
                &format!("SELECT retain_until_expiry FROM {TABLE} WHERE owner = ?1"),
                params![owner.as_bytes().as_slice()],
                |row| row.get(0),
            )
            .unwrap();
        assert!(retain);
    }

    #[test]
    fn durable_updates_reject_missing_owner() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let owner = LockOwner::new([7; 32]);

        assert!(mark_retain_until_expiry(db_path, owner)
            .unwrap_err()
            .contains("no longer exists"));
        assert!(update_expiry(db_path, owner, BlockHeight::from_u32(100))
            .unwrap_err()
            .contains("no longer exists"));
    }
}
