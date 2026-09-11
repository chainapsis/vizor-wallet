//! Gift Card outcomes must use positive spend evidence, never an empty history.
use rusqlite::{Connection, OptionalExtension};
use std::collections::HashSet;

pub(crate) struct SpendEvidence {
    pub all_funds_spent_elsewhere: bool,
    pub conflicted_txids: Vec<String>,
    pub local_claim_txids: Vec<String>,
    pub verified_height: u64,
}

pub(crate) fn payment_link_spend_evidence(
    db_path: &str,
    account_uuid: &str,
    claim_txids: &str,
) -> Result<SpendEvidence, String> {
    let uuid = uuid::Uuid::parse_str(account_uuid).map_err(|e| e.to_string())?;
    let conn = super::open_readonly_conn(db_path)?;
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    inspect(&tx, uuid.as_bytes(), claim_txids).map_err(|e| e.to_string())
}

fn inspect(
    conn: &Connection,
    account_uuid: &[u8],
    claim_txids: &str,
) -> rusqlite::Result<SpendEvidence> {
    let account: i64 = conn.query_row(
        "SELECT id FROM accounts WHERE uuid = ?1",
        [account_uuid],
        |r| r.get(0),
    )?;
    let height: u64 = conn.query_row(
        r#"SELECT MAX(0, MIN(COALESCE((SELECT MAX(height)
        FROM blocks), 0), COALESCE((SELECT MIN(block_range_start) - 1
        FROM scan_queue
        WHERE priority > 10), (SELECT MAX(height)
        FROM blocks), 0)))"#,
        [],
        |r| r.get(0),
    )?;
    // Six scanned confirmations, matching the retained claim recovery window.
    let settled_height = height.saturating_sub(5);
    let requested: HashSet<String> = claim_txids
        .split(',')
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    // OVK recovery can add a competitor to sent_notes because all claimants
    // share the card's keys. Only locally created sends have transactions.created
    // set (store_transaction_to_be_sent); scanned/decrypted transactions do not.
    let mut stmt = conn.prepare(
        "SELECT DISTINCT lower(hex(t.txid)) FROM sent_notes s \
         JOIN transactions t ON t.id_tx = s.transaction_id \
         WHERE s.from_account_id = ?1 AND t.created IS NOT NULL ORDER BY 1",
    )?;
    // Include failed legs too. Recovery uses a persisted pre-attempt snapshot
    // to distinguish attempts; excluding expired/conflicted legs here would
    // strand partially completed claims.
    let local_claim_txids = stmt
        .query_map([account], |r| r.get::<_, String>(0))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let mut requested = requested;
    requested.extend(local_claim_txids.iter().cloned());
    // Zero-value change is not funding; real sends can leave these outputs
    // in both the losing local transaction and the recovered winner.
    let mut notes = conn.prepare("SELECT pool, id_within_pool_table FROM v_received_outputs WHERE account_id = ?1 AND pool != 0 AND value > 0")?;
    let notes = notes
        .query_map([account], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let mut all_spent = !notes.is_empty();
    let mut conflicts = HashSet::new();
    for (pool, note) in notes {
        let spent: Option<String> = conn
            .query_row(
                r#"SELECT lower(hex(t.txid))
        FROM v_received_output_spends s
        JOIN transactions t ON t.id_tx = s.transaction_id
        WHERE s.pool = ?1
          AND s.received_output_id = ?2
          AND t.mined_height BETWEEN 1
          AND ?3 LIMIT 1"#,
                rusqlite::params![pool, note, settled_height],
                |r| r.get(0),
            )
            .optional()?;
        let Some(spender) = spent else {
            all_spent = false;
            continue;
        };
        if requested.contains(&spender) {
            all_spent = false;
        }
        let mut stmt = conn.prepare(
            r#"SELECT lower(hex(t.txid))
        FROM v_received_output_spends s
        JOIN transactions t ON t.id_tx = s.transaction_id
        WHERE s.pool = ?1
          AND s.received_output_id = ?2
          AND t.mined_height IS NULL"#,
        )?;
        for id in stmt.query_map(rusqlite::params![pool, note], |r| r.get::<_, String>(0))? {
            let id = id?;
            if requested.contains(&id) && id != spender {
                conflicts.insert(id);
            }
        }
    }
    let mut conflicted_txids: Vec<_> = conflicts.into_iter().collect();
    conflicted_txids.sort();
    Ok(SpendEvidence {
        all_funds_spent_elsewhere: all_spent,
        conflicted_txids,
        local_claim_txids,
        verified_height: height,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch("CREATE TABLE accounts(id INTEGER, uuid BLOB); INSERT INTO accounts VALUES(1, X'01'); CREATE TABLE scan_queue(block_range_start INTEGER, block_range_end INTEGER, priority INTEGER); CREATE TABLE blocks(height INTEGER); INSERT INTO blocks VALUES(105); CREATE TABLE transactions(id_tx INTEGER, txid BLOB, mined_height INTEGER, expiry_height INTEGER, created INTEGER DEFAULT 1); CREATE TABLE sent_notes(from_account_id INTEGER, transaction_id INTEGER); CREATE TABLE v_received_outputs(account_id INTEGER, pool INTEGER, id_within_pool_table INTEGER, value INTEGER); CREATE TABLE v_received_output_spends(pool INTEGER, received_output_id INTEGER, transaction_id INTEGER);").unwrap();
        c
    }
    #[test]
    fn absence_is_not_spend_evidence() {
        let c = db();
        assert!(!inspect(&c, &[1], "").unwrap().all_funds_spent_elsewhere);
        c.execute_batch("INSERT INTO v_received_outputs VALUES(1,3,1,10010000)")
            .unwrap();
        assert!(!inspect(&c, &[1], "").unwrap().all_funds_spent_elsewhere);
    }
    #[test]
    fn competing_spend_needs_six_confirmations_and_conflicts_with_our_input() {
        let c = db();
        c.execute_batch("INSERT INTO v_received_outputs VALUES(1,3,1,10010000); INSERT INTO transactions(id_tx, txid, mined_height, expiry_height) VALUES(1,X'AA',NULL,140),(2,X'BB',101,140); INSERT INTO sent_notes VALUES(1,1),(1,2); UPDATE transactions SET created=NULL WHERE id_tx=2; INSERT INTO v_received_output_spends VALUES(3,1,1),(3,1,2)").unwrap();
        assert!(!inspect(&c, &[1], "aa").unwrap().all_funds_spent_elsewhere);
        c.execute("UPDATE blocks SET height=106", []).unwrap();
        let e = inspect(&c, &[1], "aa").unwrap();
        assert!(e.all_funds_spent_elsewhere);
        assert_eq!(e.conflicted_txids, ["aa"]);
        assert_eq!(e.local_claim_txids, ["aa"]);
        c.execute_batch("INSERT INTO scan_queue VALUES(104,107,20)")
            .unwrap();
        assert!(!inspect(&c, &[1], "aa").unwrap().all_funds_spent_elsewhere);
        c.execute_batch("DELETE FROM scan_queue").unwrap();
        c.execute_batch("INSERT INTO v_received_outputs VALUES(1,3,2,1)")
            .unwrap();
        assert!(!inspect(&c, &[1], "aa").unwrap().all_funds_spent_elsewhere);
    }
    #[test]
    fn zero_value_change_is_not_remaining_gift_card_funding() {
        let c = db();
        c.execute_batch("INSERT INTO v_received_outputs VALUES(1,3,1,10010000),(1,3,2,0),(1,3,3,0); INSERT INTO transactions(id_tx,txid,mined_height,created) VALUES(1,X'AA',NULL,1),(2,X'BB',100,NULL); INSERT INTO sent_notes VALUES(1,1),(1,2); INSERT INTO v_received_output_spends VALUES(3,1,1),(3,1,2)").unwrap();
        let evidence = inspect(&c, &[1], "aa").unwrap();
        assert!(evidence.all_funds_spent_elsewhere);
        assert_eq!(evidence.conflicted_txids, ["aa"]);
        assert_eq!(evidence.local_claim_txids, ["aa"]);
        // Zero-value notes alone are not evidence that any funds were claimed.
        c.execute("DELETE FROM v_received_outputs WHERE value > 0", [])
            .unwrap();
        assert!(!inspect(&c, &[1], "aa").unwrap().all_funds_spent_elsewhere);
        // A positive top-up, however small, must still block that conclusion.
        c.execute_batch("INSERT INTO v_received_outputs VALUES(1,3,1,10010000),(1,3,4,1)")
            .unwrap();
        assert!(!inspect(&c, &[1], "aa").unwrap().all_funds_spent_elsewhere);
    }

    #[test]
    fn metadata_recovery_keeps_expired_local_legs() {
        let c = db();
        c.execute_batch("INSERT INTO transactions(id_tx, txid, mined_height, expiry_height) VALUES(1,X'AA',NULL,100),(2,X'BB',99,100); INSERT INTO sent_notes VALUES(1,1),(1,2)").unwrap();
        assert_eq!(
            inspect(&c, &[1], "").unwrap().local_claim_txids,
            ["aa", "bb"]
        );
    }
    #[test]
    fn own_receipt_and_reorg_are_not_losses() {
        let c = db();
        c.execute_batch("INSERT INTO v_received_outputs VALUES(1,3,1,10010000); INSERT INTO transactions(id_tx, txid, mined_height, expiry_height) VALUES(1,X'AA',100,140); INSERT INTO sent_notes VALUES(1,1); INSERT INTO v_received_output_spends VALUES(3,1,1)").unwrap();
        assert!(!inspect(&c, &[1], "").unwrap().all_funds_spent_elsewhere);
        c.execute_batch("DELETE FROM sent_notes; UPDATE transactions SET mined_height=NULL")
            .unwrap();
        assert!(!inspect(&c, &[1], "").unwrap().all_funds_spent_elsewhere);
    }
}

/// Exclude confirmed conflicts from automatic retry, even after app restart.
pub(crate) fn payment_link_resubmit_exclusions(db_path: &str) -> Result<HashSet<Vec<u8>>, String> {
    let conn = super::open_readonly_conn(db_path)?;
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    let mut stmt = tx
        .prepare("SELECT uuid FROM accounts")
        .map_err(|e| e.to_string())?;
    let accounts = stmt
        .query_map([], |r| r.get::<_, Vec<u8>>(0))
        .map_err(|e| e.to_string())?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| e.to_string())?;
    let mut excluded = HashSet::new();
    for account in accounts {
        for id in inspect(&tx, &account, "")
            .map_err(|e| e.to_string())?
            .conflicted_txids
        {
            excluded.insert(hex::decode(id).map_err(|e| e.to_string())?);
        }
    }
    Ok(excluded)
}
