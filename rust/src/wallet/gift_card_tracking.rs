//! Sender-side observation. No signing, submission, or claim-wallet ownership.
use super::{keys, network::WalletNetwork};
use rusqlite::{Connection, OptionalExtension};
use std::{collections::BTreeSet, sync::Mutex};

// All entry points serialize against scans; the main wallet and claim DBs never
// enter this lock. Cancellation deliberately does not acquire it.
pub(crate) static OPERATIONS: Mutex<()> = Mutex::new(());

#[derive(Debug)]
pub struct GiftCardUsageEvidence {
    pub status: String,
    pub reason: Option<String>,
    pub verified_height: u64,
    pub spending_txids: Vec<String>,
    pub spent_height: u64,
    pub can_delete: bool,
}

pub(crate) fn inspect(
    db_path: &str,
    account_uuid: &str,
    funding_txids: &str,
    expected: u64,
) -> Result<GiftCardUsageEvidence, String> {
    let uuid = keys::parse_account_uuid(account_uuid)?;
    let conn = super::db::open_readonly_conn_with_timeout(db_path, None)?;
    let tx = conn.unchecked_transaction().map_err(|e| e.to_string())?;
    inspect_connection(&tx, uuid.expose_uuid().as_bytes(), funding_txids, expected)
        .map_err(|e| e.to_string())
}

fn matches_id(stored: &str, wire: &str) -> bool {
    stored.eq_ignore_ascii_case(wire)
        || hex::decode(wire).ok().is_some_and(|mut bytes| {
            bytes.reverse();
            hex::encode(bytes).eq_ignore_ascii_case(stored)
        })
}

fn inspect_connection(
    conn: &Connection,
    uuid: &[u8],
    funding_txids: &str,
    expected: u64,
) -> rusqlite::Result<GiftCardUsageEvidence> {
    let account: i64 = conn.query_row("SELECT id FROM accounts WHERE uuid=?1", [uuid], |r| {
        r.get(0)
    })?;
    let height: u64 = conn.query_row(
        r#"SELECT MAX(0, MIN(COALESCE((SELECT MAX(height) FROM blocks),0),
        COALESCE((SELECT MIN(block_range_start)-1 FROM scan_queue WHERE priority>10),
        (SELECT MAX(height) FROM blocks),0)))"#,
        [],
        |r| r.get(0),
    )?;
    let expected_ids: BTreeSet<_> = funding_txids
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    let mut found = BTreeSet::new();
    let mut value = 0u64;
    let mut all_settled = true;
    let mut any_spent = false;
    let mut remaining = false;
    let mut spent_height = 0;
    let mut spending = BTreeSet::new();
    let mut query = conn.prepare(
        r#"SELECT ro.pool, ro.id_within_pool_table, ro.value,
        lower(hex(t.txid)), t.mined_height FROM v_received_outputs ro
        JOIN transactions t ON t.id_tx=ro.transaction_id
        WHERE ro.account_id=?1 AND ro.value>0"#,
    )?;
    let outputs = query
        .query_map([account], |r| {
            Ok((
                r.get::<_, i64>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, u64>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, Option<u64>>(4)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    for (pool, note, amount, txid, mined) in outputs {
        let is_funding = pool != 0 && expected_ids.iter().any(|id| matches_id(&txid, id));
        // A scanned observer sees mined spends via nullifiers, independent of
        // who signed them. Pending local sends must never count as final.
        let spent: Option<(String, u64)> = conn
            .query_row(
                r#"SELECT lower(hex(t.txid)),t.mined_height
            FROM v_received_output_spends s JOIN transactions t ON t.id_tx=s.transaction_id
            WHERE s.pool=?1 AND s.received_output_id=?2 AND t.mined_height BETWEEN 1 AND ?3
            ORDER BY t.mined_height LIMIT 1"#,
                rusqlite::params![pool, note, height],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        let settled = spent
            .as_ref()
            .is_some_and(|(_, h)| height >= h.saturating_add(5));
        if !settled {
            remaining = true;
        }
        if !is_funding {
            continue;
        }
        if !mined.is_some_and(|h| h > 0 && h <= height) {
            all_settled = false;
            continue;
        }
        for id in &expected_ids {
            if matches_id(&txid, id) {
                found.insert(*id);
            }
        }
        value = value.saturating_add(amount);
        all_settled &= settled;
        if let Some((id, h)) = spent {
            any_spent = true;
            spent_height = spent_height.max(h);
            spending.insert(id);
        }
    }
    let funded =
        !expected_ids.is_empty() && found == expected_ids && expected > 0 && value >= expected;
    let status = if !funded {
        "unknown"
    } else if all_settled {
        "used"
    } else if any_spent {
        "spendDetected"
    } else {
        "unused"
    };
    let reason = if funded {
        None
    } else if expected_ids.is_empty() || expected == 0 {
        Some("missingFundingInfo")
    } else if found != expected_ids {
        Some("fundingNotObserved")
    } else {
        Some("amountMismatch")
    };
    Ok(GiftCardUsageEvidence {
        reason: reason.map(str::to_owned),
        status: status.into(),
        verified_height: height,
        spending_txids: spending.into_iter().collect(),
        spent_height,
        can_delete: status == "used" && !remaining,
    })
}

/// Idempotent cleanup, called only after the durable receipt has been saved.
pub(crate) fn remove(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<(), String> {
    if !std::path::Path::new(db_path).exists() {
        return Ok(());
    }
    let id = keys::parse_account_uuid(account_uuid)?;
    let conn = super::db::open_readonly_conn_with_timeout(db_path, None)?;
    let exists: bool = conn
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM accounts WHERE uuid=?1)",
            [id.expose_uuid().as_bytes()],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    drop(conn);
    if exists {
        keys::delete_account(db_path, network, account_uuid)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn db() -> Connection {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch("CREATE TABLE accounts(id INTEGER,uuid BLOB); INSERT INTO accounts VALUES(1,X'01'),(2,X'02'); CREATE TABLE blocks(height INTEGER); INSERT INTO blocks VALUES(105); CREATE TABLE scan_queue(block_range_start INTEGER,priority INTEGER); CREATE TABLE transactions(id_tx INTEGER,txid BLOB,mined_height INTEGER); CREATE TABLE v_received_outputs(account_id INTEGER,pool INTEGER,id_within_pool_table INTEGER,value INTEGER,transaction_id INTEGER); CREATE TABLE v_received_output_spends(pool INTEGER,received_output_id INTEGER,transaction_id INTEGER);").unwrap();
        c
    }
    fn fund(c: &Connection) {
        c.execute_batch("INSERT INTO transactions VALUES(1,X'AABB',90); INSERT INTO v_received_outputs VALUES(1,3,1,10010000,1);").unwrap();
    }
    fn check(c: &Connection) -> GiftCardUsageEvidence {
        inspect_connection(c, &[1], "bbaa", 10010000).unwrap()
    }
    #[test]
    fn insufficient_evidence_has_specific_reason() {
        let c = db();
        assert_eq!(check(&c).reason.as_deref(), Some("fundingNotObserved"));
        assert_eq!(
            inspect_connection(&c, &[1], "", 100)
                .unwrap()
                .reason
                .as_deref(),
            Some("missingFundingInfo")
        );
        fund(&c);
        assert_eq!(check(&c).reason, None);
        assert_eq!(
            inspect_connection(&c, &[1], "bbaa", 10010001)
                .unwrap()
                .reason
                .as_deref(),
            Some("amountMismatch")
        );
        assert_eq!(
            inspect_connection(&c, &[1], "bbaa,ccdd", 100)
                .unwrap()
                .reason
                .as_deref(),
            Some("fundingNotObserved")
        );
    }
    #[test]
    fn observer_registration_is_view_only_idempotent_and_supports_older_accounts() {
        use zcash_client_backend::data_api::{
            Account as _, AccountPurpose, WalletRead, WalletWrite,
        };
        use zcash_protocol::consensus::BlockHeight;
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("observer.db");
        let path = path.to_str().unwrap();
        let network = keys::parse_network("regtest").unwrap();
        let phrase = keys::generate_mnemonic();
        let seed = keys::mnemonic_to_seed(&phrase).unwrap();
        let address = keys::derive_gift_address(network, &seed, 0).unwrap();
        let uuid =
            keys::register_gift_card_observer(path, network, phrase.as_bytes(), &address, 100)
                .unwrap();
        assert_eq!(
            uuid,
            keys::register_gift_card_observer(path, network, phrase.as_bytes(), &address, 100)
                .unwrap()
        );
        assert!(
            keys::register_gift_card_observer(path, network, phrase.as_bytes(), "wrong", 100)
                .is_err()
        );
        let mut db = super::super::db::open_wallet_db_with_timeout(
            path,
            network,
            std::time::Duration::from_secs(2),
        )
        .unwrap();
        let account = db
            .get_account(keys::parse_account_uuid(&uuid).unwrap())
            .unwrap()
            .unwrap();
        assert!(matches!(account.purpose(), AccountPurpose::ViewOnly));
        db.update_chain_tip(BlockHeight::from_u32(200)).unwrap();
        drop(db);
        let other = keys::generate_mnemonic();
        let other_seed = keys::mnemonic_to_seed(&other).unwrap();
        let other_address = keys::derive_gift_address(network, &other_seed, 0).unwrap();
        let second =
            keys::register_gift_card_observer(path, network, other.as_bytes(), &other_address, 50)
                .unwrap();
        assert_ne!(uuid, second);
        let db = super::super::db::open_wallet_db_with_timeout(
            path,
            network,
            std::time::Duration::from_secs(2),
        )
        .unwrap();
        assert_eq!(db.get_account_ids().unwrap().len(), 2);
        assert!(db
            .suggest_scan_ranges()
            .unwrap()
            .iter()
            .any(|r| u32::from(r.block_range().start) <= 50));
        drop(db);
        // Exercise the evidence query against the real migrated schema too.
        assert_eq!(
            inspect(path, &uuid, &"aa".repeat(32), 10000)
                .unwrap()
                .status,
            "unknown"
        );
        remove(path, network, &uuid).unwrap();
        remove(path, network, &uuid).unwrap();
        let db = super::super::db::open_wallet_db_with_timeout(
            path,
            network,
            std::time::Duration::from_secs(2),
        )
        .unwrap();
        assert_eq!(db.get_account_ids().unwrap().len(), 1);
    }

    #[test]
    fn funding_identity_and_complete_scan_are_required() {
        let c = db();
        assert_eq!(check(&c).status, "unknown");
        fund(&c);
        assert_eq!(check(&c).status, "unused");
        assert_eq!(
            inspect_connection(&c, &[2], "bbaa", 10010000)
                .unwrap()
                .status,
            "unknown"
        );
        assert_eq!(
            inspect_connection(&c, &[1], "ccdd", 10010000)
                .unwrap()
                .status,
            "unknown"
        );
        c.execute_batch("INSERT INTO scan_queue VALUES(90,20)")
            .unwrap();
        assert_eq!(check(&c).status, "unknown");
    }
    #[test]
    fn used_requires_six_scanned_confirmations_and_survives_topups() {
        let c = db();
        fund(&c);
        c.execute_batch("INSERT INTO transactions VALUES(2,X'CCDD',101); INSERT INTO v_received_output_spends VALUES(3,1,2)").unwrap();
        assert_eq!(check(&c).status, "spendDetected");
        c.execute_batch("UPDATE blocks SET height=106").unwrap();
        assert!(check(&c).can_delete);
        c.execute_batch("INSERT INTO transactions VALUES(3,X'EEFF',102); INSERT INTO v_received_outputs VALUES(1,3,2,1,3)").unwrap();
        let e = check(&c);
        assert_eq!(e.status, "used");
        assert!(!e.can_delete);
        assert_eq!(e.spending_txids, ["ccdd"]);
        c.execute_batch("UPDATE v_received_outputs SET value=0 WHERE id_within_pool_table=2")
            .unwrap();
        assert!(check(&c).can_delete);
        c.execute_batch("INSERT INTO scan_queue VALUES(105,20)")
            .unwrap();
        assert_eq!(check(&c).status, "spendDetected");
        c.execute_batch("UPDATE transactions SET mined_height=NULL WHERE id_tx=2")
            .unwrap();
        assert_eq!(check(&c).status, "unused");
    }
}
