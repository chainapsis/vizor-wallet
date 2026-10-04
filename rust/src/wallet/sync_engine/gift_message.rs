//! Optional display metadata from the exact shielded output funding a gift.
use std::time::Duration;

use rusqlite::Connection;
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::{
    consensus::BranchId,
    memo::{Memo, MemoBytes},
};

use super::{direct_claim, enhancement::EnhancementPolicy, open_lwd_channel};
use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
    transaction_data::payload::get_transaction_payload,
};

#[derive(Debug, PartialEq)]
struct FundingOutput {
    txid: TxId,
    pool: i64,
    index: u32,
    height: u32,
    memo: Option<Vec<u8>>,
}

fn candidate(
    conn: &Connection,
    account: &[u8],
    amount: u64,
    txid: Option<TxId>,
) -> Result<Option<FundingOutput>, String> {
    let mut stmt = conn.prepare("SELECT t.txid, n.pool, n.idx, t.mined_height, n.memo, n.value FROM transactions t JOIN (
        SELECT account_id, transaction_id, 2 AS pool, output_index AS idx, value, memo FROM sapling_received_notes
        UNION ALL SELECT account_id, transaction_id, 3, action_index, value, memo FROM orchard_received_notes
        UNION ALL SELECT account_id, transaction_id, 4, action_index, value, memo FROM ironwood_received_notes
    ) n ON n.transaction_id=t.id_tx JOIN accounts a ON a.id=n.account_id
    WHERE a.uuid=?1 AND n.value>0 AND t.mined_height>0 AND (?2 IS NULL OR t.txid=?2)")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map(
            rusqlite::params![account, txid.as_ref().map(|id| id.as_ref())],
            |r| {
                Ok((
                    r.get::<_, Vec<u8>>(0)?,
                    r.get::<_, i64>(1)?,
                    r.get::<_, u32>(2)?,
                    r.get::<_, u32>(3)?,
                    r.get::<_, Option<Vec<u8>>>(4)?,
                    r.get::<_, u64>(5)?,
                ))
            },
        )
        .map_err(|e| e.to_string())?;
    let mut outputs = std::collections::HashMap::<Vec<u8>, Vec<(FundingOutput, u64)>>::new();
    for row in rows {
        let (id, pool, index, height, memo, value) = row.map_err(|e| e.to_string())?;
        let parsed = TxId::from_bytes(
            id.as_slice()
                .try_into()
                .map_err(|_| "Invalid stored gift transaction")?,
        );
        outputs.entry(id).or_default().push((
            FundingOutput {
                txid: parsed,
                pool,
                index,
                height,
                memo,
            },
            value,
        ));
    }
    let mut matches = outputs.into_values().filter_map(|mut notes| {
        if notes.len() == 1 && notes[0].1 == amount {
            Some(notes.remove(0).0)
        } else {
            None
        }
    });
    let first = matches.next();
    Ok(if matches.next().is_none() {
        first
    } else {
        None
    })
}

fn text(memo: Option<&[u8]>) -> Option<String> {
    match Memo::try_from(&MemoBytes::from_bytes(memo?).ok()?).ok()? {
        Memo::Text(value) => {
            let value = String::from(value);
            let value = value.trim();
            (!value.is_empty() && !value.contains('\0')).then(|| value.to_owned())
        }
        _ => None,
    }
}

/// Direct locators only read their existing decrypted payload. Birthday mode
/// may fetch one missing payload in public mode, with a bounded display budget.
/// Errors are optional metadata failures; callers keep claim validation separate.
pub(crate) async fn read(
    path: &str,
    url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_amount: u64,
    funding_txid: Option<&str>,
    funding_height: Option<u32>,
) -> Result<Option<String>, String> {
    let account = uuid::Uuid::parse_str(account_uuid).map_err(|e| e.to_string())?;
    let direct = funding_txid.is_some() || funding_height.is_some();
    let id = match (funding_txid, funding_height) {
        (Some(id), None) => Some(direct_claim::parse_txid(id)?),
        (None, Some(height)) => {
            match direct_claim::resolved_funding(path, height, expected_amount)? {
                Some(id) => Some(id),
                None => return Ok(None),
            }
        }
        (None, None) => None,
        _ => return Ok(None),
    };
    let selected = {
        let conn = open_wallet_raw_conn_with_timeout(path, READ_DB_BUSY_TIMEOUT)?;
        candidate(&conn, account.as_bytes(), expected_amount, id)?
    };
    let Some(selected) = selected else {
        return Ok(None);
    };
    if selected.memo.is_some() {
        return Ok(text(selected.memo.as_deref()));
    }
    if direct || EnhancementPolicy::current(network).is_private() {
        return Ok(None);
    }

    let raw = tokio::time::timeout(Duration::from_secs(5), async {
        let mut client = open_lwd_channel(url).await.map_err(|e| e.to_string())?;
        get_transaction_payload(&mut client, selected.txid)
            .await
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|_| "Gift message lookup timed out")??;
    let tx =
        Transaction::read(raw.data.as_slice(), BranchId::Sapling).map_err(|e| e.to_string())?;
    // A metadata fetch must not rewrite a concurrently changed funding state.
    if tx.txid() != selected.txid || raw.height != u64::from(selected.height) {
        return Ok(None);
    }
    crate::wallet::sync::decrypt_and_store_transaction(path, network, &raw.data, Some(raw.height))?;
    let conn = open_wallet_raw_conn_with_timeout(path, READ_DB_BUSY_TIMEOUT)?;
    let updated = candidate(
        &conn,
        account.as_bytes(),
        expected_amount,
        Some(selected.txid),
    )?;
    Ok(updated
        .filter(|note| note.pool == selected.pool && note.index == selected.index)
        .and_then(|note| text(note.memo.as_deref())))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn db() -> Connection {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch("CREATE TABLE accounts(id INTEGER, uuid BLOB);
            CREATE TABLE transactions(id_tx INTEGER, txid BLOB, mined_height INTEGER);
            CREATE TABLE sapling_received_notes(account_id INTEGER, transaction_id INTEGER, output_index INTEGER, value INTEGER, memo BLOB);
            CREATE TABLE orchard_received_notes(account_id INTEGER, transaction_id INTEGER, action_index INTEGER, value INTEGER, memo BLOB);
            CREATE TABLE ironwood_received_notes(account_id INTEGER, transaction_id INTEGER, action_index INTEGER, value INTEGER, memo BLOB);").unwrap();
        db.execute(
            "INSERT INTO accounts VALUES(1, ?1), (2, ?2)",
            rusqlite::params![[1u8; 16].as_slice(), [2u8; 16].as_slice()],
        )
        .unwrap();
        db
    }
    fn fund(db: &Connection, id: u8, account: i64, amount: u64, message: Option<&[u8]>) {
        db.execute(
            "INSERT INTO transactions VALUES(?1, ?2, 100)",
            rusqlite::params![id, [id; 32].as_slice()],
        )
        .unwrap();
        db.execute(
            "INSERT INTO orchard_received_notes VALUES(?1, ?2, 0, ?3, ?4)",
            rusqlite::params![account, id, amount, message],
        )
        .unwrap();
    }
    #[test]
    fn funding_message_is_bound_to_account_transaction_and_positive_output() {
        let db = db();
        fund(&db, 1, 1, 20_000, Some(b"First gift"));
        fund(&db, 2, 2, 20_000, Some(b"Other card"));
        db.execute(
            "INSERT INTO ironwood_received_notes VALUES(1, 1, 1, 0, ?1)",
            [b"Unsolicited memo".as_slice()],
        )
        .unwrap();
        let note = candidate(&db, &[1; 16], 20_000, None).unwrap().unwrap();
        assert_eq!(text(note.memo.as_deref()).as_deref(), Some("First gift"));
        assert_eq!(note.index, 0);
        assert!(candidate(&db, &[1; 16], 30_000, Some(note.txid))
            .unwrap()
            .is_none());
        fund(&db, 3, 1, 20_000, Some(b"Top up"));
        assert!(candidate(&db, &[1; 16], 20_000, None).unwrap().is_none());
        assert_eq!(
            candidate(&db, &[1; 16], 20_000, Some(note.txid))
                .unwrap()
                .unwrap(),
            note
        );
        db.execute(
            "INSERT INTO sapling_received_notes VALUES(1,1,0,1,?1)",
            [b"Split".as_slice()],
        )
        .unwrap();
        assert!(candidate(&db, &[1; 16], 20_000, Some(note.txid))
            .unwrap()
            .is_none());
    }
    #[test]
    fn absent_invalid_and_nontext_memos_are_optional() {
        assert_eq!(text(Some(b"  Hello  ")).as_deref(), Some("Hello"));
        for bytes in [b"".as_slice(), b" \n", &[0xf6], &[0xff], &[0xc0], b"a\0b"] {
            assert!(text(Some(bytes)).is_none());
        }
        assert!(text(None).is_none());
    }
}
