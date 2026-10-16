//! Locked shielded value an account still holds.
//!
//! Two kinds of lock keep notes out of selection without committing them to a
//! transaction: a history hold, until older history that may spend them is
//! checked, and a proposal nothing has signed yet (a `session` or `release`
//! row in the proposal lock table), whose notes a cancel or a restart returns.
//! Balances report this value as held: not spendable, but still the account's.
//! Locks whose transaction may already be on the network (signed or
//! broadcasting) and migration locks stay locked.

use std::collections::HashMap;

use rusqlite::{named_params, OptionalExtension};

use super::history_hold::{self, MARGINAL_FEE_ZATS};
use super::proposal_locks;
use crate::wallet::db::{open_wallet_raw_conn_with_timeout, WALLET_DB_BUSY_TIMEOUT};

/// Held value per shielded pool.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct HeldValue {
    pub sapling: u64,
    pub orchard: u64,
    pub ironwood: u64,
}

/// One account's held value by kind. The history hold is kept apart because it
/// also counts as pending for migration and Home names its amount.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct AccountHeld {
    pub history_hold: HeldValue,
    pub reserved: HeldValue,
}

/// Held value per account UUID, with the note eligibility the wallet balance
/// applies at the next block height: an economic note in an unexpired
/// transaction, not spent by an unexpired one, whose lock has not lapsed. A
/// history-held note counts once stabilized, so it is never one the balance
/// reports as pending.
///
/// The query cannot tell whether a reserved note is spendable yet, so callers
/// cap each pool at the locked value the wallet summary reports.
pub(crate) fn by_account(db_path: &str) -> Result<HashMap<[u8; 16], AccountHeld>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
    let mut out = HashMap::<[u8; 16], AccountHeld>::new();
    let Some(target_height) = conn
        .query_row("SELECT MAX(block_range_end) FROM scan_queue", [], |row| {
            row.get::<_, Option<u32>>(0)
        })
        .optional()
        .map_err(|e| format!("read chain tip for held value: {e}"))?
        .flatten()
    else {
        return Ok(out);
    };
    let reserving_owner = if history_hold::table_exists(&conn, proposal_locks::TABLE)? {
        format!(
            "rn.lock_owner IN (SELECT owner FROM {} WHERE phase IN ('session', 'release'))",
            proposal_locks::TABLE
        )
    } else {
        "0".to_string()
    };
    for pool in ["sapling", "orchard", "ironwood"] {
        let sql = format!(
            "SELECT a.uuid,
                    SUM(CASE WHEN rn.lock_owner = :hold_owner AND rn.witness_stabilized = 1
                             THEN rn.value ELSE 0 END),
                    SUM(CASE WHEN {reserving_owner} THEN rn.value ELSE 0 END)
             FROM {pool}_received_notes rn
             JOIN accounts a ON a.id = rn.account_id
             JOIN transactions t ON t.id_tx = rn.transaction_id
             WHERE (rn.lock_owner = :hold_owner OR {reserving_owner})
               AND rn.lock_expiry_height >= :target_height
               AND rn.value > {MARGINAL_FEE_ZATS}
               AND {note_unexpired}
               AND rn.id NOT IN (
                   SELECT rns.{pool}_received_note_id
                   FROM {pool}_received_note_spends rns
                   JOIN transactions stx ON stx.id_tx = rns.transaction_id
                   WHERE {spend_unexpired}
               )
             GROUP BY a.uuid",
            note_unexpired = history_hold::tx_unexpired_condition("t"),
            spend_unexpired = history_hold::tx_unexpired_condition("stx"),
        );
        let mut stmt = conn
            .prepare(&sql)
            .map_err(|e| format!("prepare {pool} held value: {e}"))?;
        let rows = stmt
            .query_map(
                named_params![
                    ":hold_owner": history_hold::hold_owner().as_bytes().as_slice(),
                    ":target_height": target_height,
                ],
                |row| {
                    Ok((
                        row.get::<_, Vec<u8>>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, i64>(2)?,
                    ))
                },
            )
            .map_err(|e| format!("read {pool} held value: {e}"))?;
        for row in rows {
            let (uuid, hold, reserved) =
                row.map_err(|e| format!("read {pool} held value row: {e}"))?;
            let Ok(uuid) = <[u8; 16]>::try_from(uuid.as_slice()) else {
                continue;
            };
            let entry = out.entry(uuid).or_default();
            *slot(&mut entry.history_hold, pool) = u64::try_from(hold).unwrap_or(0);
            *slot(&mut entry.reserved, pool) = u64::try_from(reserved).unwrap_or(0);
        }
    }
    Ok(out)
}

fn slot<'a>(value: &'a mut HeldValue, pool: &str) -> &'a mut u64 {
    match pool {
        "sapling" => &mut value.sapling,
        "orchard" => &mut value.orchard,
        _ => &mut value.ironwood,
    }
}

#[cfg(test)]
mod tests {
    use rusqlite::{params, Connection};
    use zcash_client_backend::wallet::LockOwner;

    use super::*;
    use crate::wallet::network::WalletNetwork;

    #[test]
    fn holds_and_unsigned_reservations_are_read_by_lock_owner() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("wallet.db");
        let conn = Connection::open(&path).unwrap();
        let mut schema = String::from(
            "CREATE TABLE accounts (id INTEGER PRIMARY KEY, uuid BLOB NOT NULL);
             CREATE TABLE scan_queue (
                 block_range_start INTEGER, block_range_end INTEGER, priority INTEGER);
             CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY, mined_height INTEGER, expiry_height INTEGER,
                 target_height INTEGER, min_observed_height INTEGER NOT NULL);",
        );
        for pool in ["sapling", "orchard", "ironwood"] {
            schema.push_str(&format!(
                "CREATE TABLE {pool}_received_notes (
                     id INTEGER PRIMARY KEY, account_id INTEGER, transaction_id INTEGER,
                     value INTEGER, lock_owner BLOB, lock_expiry_height INTEGER,
                     witness_stabilized INTEGER NOT NULL DEFAULT 1);
                 CREATE TABLE {pool}_received_note_spends (
                     {pool}_received_note_id INTEGER, transaction_id INTEGER);"
            ));
        }
        schema.push_str(
            "INSERT INTO scan_queue VALUES (0, 101, 10); -- next block height 101
             INSERT INTO transactions VALUES (1, 50, 90, NULL, 40);    -- mined funding
             INSERT INTO transactions VALUES (2, NULL, 150, NULL, 95); -- pending spend
             INSERT INTO transactions VALUES (3, NULL, 90, NULL, 80);  -- expired spend
             -- Expiry unknown: live by its target height, not its first sighting.
             INSERT INTO transactions VALUES (4, NULL, NULL, 95, 40);",
        );
        conn.execute_batch(&schema).unwrap();
        proposal_locks::ensure_schema(&conn).unwrap();

        let owner = |byte: u8, phase: &str| {
            let owner = LockOwner::new([byte; 32]);
            conn.execute(
                &format!(
                    "INSERT INTO {}
                        (owner, session_id, txid, pool, output_index, expiry_height, phase)
                     VALUES (?1, x'00', ?2, 3, 0, 140, ?3)",
                    proposal_locks::TABLE
                ),
                params![owner.as_bytes().as_slice(), vec![byte], phase],
            )
            .unwrap();
            owner
        };
        let unsigned = owner(1, "session");
        let released = owner(2, "release");
        let signed = owner(3, "signed");
        let broadcast = owner(4, "broadcast");
        let legacy = owner(5, "legacy");
        let migration = LockOwner::new([7; 32]);
        let hold = history_hold::hold_owner();

        let first = [1u8; 16];
        let second = [2u8; 16];
        conn.execute(
            "INSERT INTO accounts VALUES (1, ?1), (2, ?2)",
            params![first.as_slice(), second.as_slice()],
        )
        .unwrap();
        let note = |pool: &str, id: i64, account: i64, value: i64, owner: LockOwner| {
            conn.execute(
                &format!(
                    "INSERT INTO {pool}_received_notes
                        (id, account_id, transaction_id, value, lock_owner, lock_expiry_height)
                     VALUES (?1, ?2, 1, ?3, ?4, 140)"
                ),
                params![id, account, value, owner.as_bytes().as_slice()],
            )
            .unwrap();
        };
        note("orchard", 1, 1, 1_000_000, unsigned);
        note("orchard", 2, 1, 2_000_000, released);
        note("orchard", 3, 1, 4_000_000, signed);
        note("orchard", 4, 1, 8_000_000, broadcast);
        note("orchard", 5, 1, 16_000_000, legacy);
        note("orchard", 6, 1, 32_000_000, migration);
        note("orchard", 7, 1, 20_000_000, hold);
        note("orchard", 8, 1, 40_000_000, hold); // not stabilized yet
        note("orchard", 9, 1, 3_000_000, unsigned); // lapsed lock
        note("orchard", 10, 1, 5_000_000, unsigned); // spent
        note("orchard", 11, 1, 7_000_000, unsigned); // its spend expired
        note("orchard", 12, 1, 13_000_000, unsigned); // spent, expiry unknown
        note("orchard", 13, 1, 4_000, unsigned); // uneconomic
        note("orchard", 14, 2, 9_000_000, unsigned);
        note("ironwood", 15, 1, 11_000_000, unsigned);
        note("sapling", 16, 2, 6_000_000, hold);
        conn.execute_batch(
            "UPDATE orchard_received_notes SET witness_stabilized = 0 WHERE id = 8;
             UPDATE orchard_received_notes SET lock_expiry_height = 100 WHERE id = 9;
             INSERT INTO orchard_received_note_spends VALUES (10, 2), (11, 3), (12, 4);",
        )
        .unwrap();

        let held = by_account(path.to_str().unwrap()).unwrap();
        assert_eq!(
            held.get(&first),
            Some(&AccountHeld {
                history_hold: HeldValue {
                    sapling: 0,
                    orchard: 20_000_000,
                    ironwood: 0,
                },
                reserved: HeldValue {
                    sapling: 0,
                    orchard: 1_000_000 + 2_000_000 + 7_000_000,
                    ironwood: 11_000_000,
                },
            })
        );
        assert_eq!(
            held.get(&second),
            Some(&AccountHeld {
                history_hold: HeldValue {
                    sapling: 6_000_000,
                    orchard: 0,
                    ironwood: 0,
                },
                reserved: HeldValue {
                    sapling: 0,
                    orchard: 9_000_000,
                    ironwood: 0,
                },
            })
        );
    }

    #[test]
    fn held_value_reads_the_real_wallet_schema() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("wallet.db");
        let path = path.to_str().unwrap();
        crate::wallet::keys::ensure_db_initialized(path, WalletNetwork::Test).unwrap();
        crate::wallet::keys::ensure_db_migrated_once(path, WalletNetwork::Test).unwrap();
        // The query names wallet tables and columns directly. A schema change
        // must fail here, not quietly leave held value out of balances.
        let conn = Connection::open(path).unwrap();
        conn.execute_batch(&format!(
            "INSERT INTO {} (owner, session_id, txid, pool, output_index, expiry_height, phase)
             VALUES (x'01', x'00', x'01', 3, 0, 140, 'session');
             INSERT INTO scan_queue (block_range_start, block_range_end, priority)
             VALUES (1, 2, 10);",
            proposal_locks::TABLE
        ))
        .unwrap();
        assert!(by_account(path).unwrap().is_empty());
    }
}
