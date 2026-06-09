use std::collections::{BTreeMap, BTreeSet};

use rusqlite::{named_params, OptionalExtension};
use transparent::keys::TransparentKeyScope;
use zcash_client_backend::data_api::{Account as _, WalletRead};
use zcash_client_sqlite::AccountUuid;
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{
        open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        SYNC_DB_BUSY_TIMEOUT, TRANSPARENT_WATCH_TABLE,
    },
    keys::get_transparent_address_from_db,
    network::WalletNetwork,
};

use super::SyncError;

const WATCH_CLASS_RECEIVE: &str = "hot_receive";
const WATCH_CLASS_FRONTIER: &str = "hot_frontier";
const WATCH_CLASS_UNSPENT: &str = "hot_unspent";
const WATCH_CLASS_RECENT: &str = "warm_recent";
const WATCH_CLASS_ARCHIVED: &str = "archived_ledger";
const NO_KEY_SCOPE: i64 = -1;
const NO_CHILD_INDEX: i64 = -1;
const ARCHIVED_SWEEP_LIMIT_PER_ACCOUNT: i64 = 8;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct UtxoRefreshBatch {
    pub(super) start_height: BlockHeight,
    pub(super) addresses: Vec<String>,
}

pub(super) fn ensure_watch_table(db_path: &str) -> Result<(), SyncError> {
    with_wallet_db_write_lock("sync_engine.transparent_watch.ensure_table", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute_batch(&format!(
            "CREATE TABLE IF NOT EXISTS {TRANSPARENT_WATCH_TABLE} (
                account_uuid BLOB NOT NULL,
                address TEXT NOT NULL,
                watch_class TEXT NOT NULL,
                key_scope INTEGER NOT NULL DEFAULT -1,
                child_index INTEGER NOT NULL DEFAULT -1,
                sweep_bucket INTEGER NOT NULL,
                next_utxo_query_height INTEGER NOT NULL,
                last_utxo_query_height INTEGER,
                created_at_height INTEGER NOT NULL,
                updated_at_height INTEGER NOT NULL,
                PRIMARY KEY (account_uuid, address)
            );
            CREATE INDEX IF NOT EXISTS idx_transparent_watch_account_class_next
                ON {TRANSPARENT_WATCH_TABLE} (
                    account_uuid, watch_class, next_utxo_query_height
                );
            CREATE INDEX IF NOT EXISTS idx_transparent_watch_account_bucket_next
                ON {TRANSPARENT_WATCH_TABLE} (
                    account_uuid, sweep_bucket, next_utxo_query_height
                );
            CREATE INDEX IF NOT EXISTS idx_transparent_watch_account_class_last_next
                ON {TRANSPARENT_WATCH_TABLE} (
                    account_uuid, watch_class, last_utxo_query_height,
                    next_utxo_query_height
                );"
        ))
        .map_err(|e| SyncError::db(format!("transparent watch create table: {e}")))
    })
}

pub(super) fn prepare_refresh_batches(
    db_path: &str,
    db: &WalletDatabase,
    network: WalletNetwork,
    account_id: AccountUuid,
    tip_height: BlockHeight,
) -> Result<Vec<UtxoRefreshBatch>, SyncError> {
    ensure_watch_table(db_path)?;

    let account = db
        .get_account(account_id)
        .map_err(|e| SyncError::db(format!("transparent watch get account: {e}")))?
        .ok_or_else(|| SyncError::db("transparent watch account disappeared"))?;
    let birthday = account.birthday_height();

    if let Ok(receive_address) = get_transparent_address_from_db(
        db_path,
        network,
        Some(&account_id.expose_uuid().to_string()),
    ) {
        upsert_watch_address(
            db_path,
            account_id,
            &receive_address,
            WATCH_CLASS_RECEIVE,
            NO_KEY_SCOPE,
            NO_CHILD_INDEX,
            birthday,
            birthday,
        )?;
    }

    sync_unspent_watch_rows(db_path, account_id, birthday, tip_height)?;
    select_refresh_batches(db_path, account_id, tip_height)
}

pub(super) fn record_ledger_address_checked(
    db_path: &str,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    child_index: u32,
    address: &str,
    query_start_height: BlockHeight,
    checked_tip_height: BlockHeight,
    found_history: bool,
) -> Result<(), SyncError> {
    let watch_class = if found_history {
        WATCH_CLASS_RECENT
    } else {
        WATCH_CLASS_ARCHIVED
    };
    let next_height = if found_history {
        query_start_height
    } else {
        checked_tip_height + 1
    };

    upsert_watch_address(
        db_path,
        account_id,
        address,
        watch_class,
        scope_code(scope),
        i64::from(child_index),
        next_height,
        checked_tip_height,
    )
}

pub(super) fn record_frontier_address(
    db_path: &str,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    child_index: u32,
    address: &str,
    next_query_height: BlockHeight,
    checked_tip_height: BlockHeight,
) -> Result<(), SyncError> {
    ensure_watch_table(db_path)?;
    with_wallet_db_write_lock("sync_engine.transparent_watch.record_frontier", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute(
            &format!(
                "UPDATE {TRANSPARENT_WATCH_TABLE}
                 SET watch_class = :archived,
                     updated_at_height = :height
                 WHERE account_uuid = :account_uuid
                   AND key_scope = :key_scope
                   AND watch_class = :frontier
                   AND address != :address"
            ),
            named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":key_scope": scope_code(scope),
                ":frontier": WATCH_CLASS_FRONTIER,
                ":archived": WATCH_CLASS_ARCHIVED,
                ":address": address,
                ":height": u32::from(checked_tip_height),
            ],
        )
        .map_err(|e| SyncError::db(format!("transparent watch demote frontier: {e}")))?;
        Ok(())
    })?;

    upsert_watch_address(
        db_path,
        account_id,
        address,
        WATCH_CLASS_FRONTIER,
        scope_code(scope),
        i64::from(child_index),
        next_query_height,
        checked_tip_height,
    )
}

pub(super) fn complete_refresh_batch(
    db_path: &str,
    account_id: AccountUuid,
    queried_addresses: &[String],
    observed_addresses: &[String],
    tip_height: BlockHeight,
) -> Result<(), SyncError> {
    if queried_addresses.is_empty() {
        return Ok(());
    }

    ensure_watch_table(db_path)?;
    let next_height = tip_height + 1;
    let observed = observed_addresses
        .iter()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();

    with_wallet_db_write_lock("sync_engine.transparent_watch.complete_batch", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;

        for address in queried_addresses {
            let next_class = if observed.contains(address.as_str()) {
                WATCH_CLASS_RECENT
            } else {
                WATCH_CLASS_ARCHIVED
            };
            conn.execute(
                &format!(
                    "UPDATE {TRANSPARENT_WATCH_TABLE}
                     SET last_utxo_query_height = :tip_height,
                         next_utxo_query_height = :next_height,
                         watch_class = CASE
                            WHEN watch_class = :recent THEN :next_class
                            ELSE watch_class
                         END,
                         updated_at_height = :tip_height
                     WHERE account_uuid = :account_uuid
                       AND address = :address"
                ),
                named_params![
                    ":account_uuid": account_id.expose_uuid(),
                    ":address": address,
                    ":tip_height": u32::from(tip_height),
                    ":next_height": u32::from(next_height),
                    ":recent": WATCH_CLASS_RECENT,
                    ":next_class": next_class,
                ],
            )
            .map_err(|e| SyncError::db(format!("transparent watch mark queried: {e}")))?;
        }

        for address in observed {
            conn.execute(
                &format!(
                    "INSERT INTO {TRANSPARENT_WATCH_TABLE} (
                        account_uuid, address, watch_class, key_scope, child_index,
                        sweep_bucket, next_utxo_query_height, last_utxo_query_height,
                        created_at_height, updated_at_height
                     )
                     VALUES (
                        :account_uuid, :address, :watch_class, :key_scope, :child_index,
                        :sweep_bucket, :next_height, :tip_height,
                        :tip_height, :tip_height
                     )
                     ON CONFLICT (account_uuid, address) DO UPDATE
                     SET watch_class = CASE
                            WHEN watch_class IN (:receive, :frontier)
                            THEN watch_class
                            ELSE :watch_class
                         END,
                         next_utxo_query_height = :next_height,
                         last_utxo_query_height = :tip_height,
                         updated_at_height = :tip_height"
                ),
                named_params![
                    ":account_uuid": account_id.expose_uuid(),
                    ":address": address,
                    ":watch_class": WATCH_CLASS_UNSPENT,
                    ":receive": WATCH_CLASS_RECEIVE,
                    ":frontier": WATCH_CLASS_FRONTIER,
                    ":key_scope": NO_KEY_SCOPE,
                    ":child_index": NO_CHILD_INDEX,
                    ":sweep_bucket": 0,
                    ":next_height": u32::from(next_height),
                    ":tip_height": u32::from(tip_height),
                ],
            )
            .map_err(|e| SyncError::db(format!("transparent watch mark observed: {e}")))?;
        }

        Ok(())
    })
}

pub(super) fn rewind_transparent_watch_to_height(
    db_path: &str,
    height: BlockHeight,
) -> Result<(), SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let table_exists = conn
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            rusqlite::params![TRANSPARENT_WATCH_TABLE],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| SyncError::db(format!("transparent watch table lookup: {e}")))?
        .is_some();

    if !table_exists {
        return Ok(());
    }

    conn.execute(
        &format!(
            "UPDATE {TRANSPARENT_WATCH_TABLE}
             SET next_utxo_query_height = MIN(next_utxo_query_height, :height),
                 last_utxo_query_height = CASE
                    WHEN last_utxo_query_height > :height THEN NULL
                    ELSE last_utxo_query_height
                 END,
                 updated_at_height = MIN(updated_at_height, :height)"
        ),
        named_params![":height": u32::from(height)],
    )
    .map(|_| ())
    .map_err(|e| SyncError::db(format!("transparent watch rewind: {e}")))
}

fn sync_unspent_watch_rows(
    db_path: &str,
    account_id: AccountUuid,
    birthday: BlockHeight,
    tip_height: BlockHeight,
) -> Result<(), SyncError> {
    let unspent_addresses = query_unspent_addresses(db_path, account_id, tip_height)?;

    for address in &unspent_addresses {
        upsert_watch_address(
            db_path,
            account_id,
            address,
            WATCH_CLASS_UNSPENT,
            NO_KEY_SCOPE,
            NO_CHILD_INDEX,
            birthday,
            tip_height,
        )?;
    }

    with_wallet_db_write_lock("sync_engine.transparent_watch.demote_spent", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        let mut stmt = conn
            .prepare(&format!(
                "SELECT address
                 FROM {TRANSPARENT_WATCH_TABLE}
                 WHERE account_uuid = :account_uuid
                   AND watch_class = :unspent"
            ))
            .map_err(|e| SyncError::db(format!("transparent watch select hot unspent: {e}")))?;
        let hot_unspent = stmt
            .query_map(
                named_params![
                    ":account_uuid": account_id.expose_uuid(),
                    ":unspent": WATCH_CLASS_UNSPENT,
                ],
                |row| row.get::<_, String>(0),
            )
            .map_err(|e| SyncError::db(format!("transparent watch hot unspent rows: {e}")))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| SyncError::db(format!("transparent watch hot unspent address: {e}")))?;

        let current = unspent_addresses.iter().collect::<BTreeSet<_>>();
        for address in hot_unspent {
            if !current.contains(&address) {
                conn.execute(
                    &format!(
                        "UPDATE {TRANSPARENT_WATCH_TABLE}
                         SET watch_class = :archived,
                             updated_at_height = :height
                         WHERE account_uuid = :account_uuid
                           AND address = :address
                           AND watch_class = :unspent"
                    ),
                    named_params![
                        ":account_uuid": account_id.expose_uuid(),
                        ":address": address,
                        ":unspent": WATCH_CLASS_UNSPENT,
                        ":archived": WATCH_CLASS_ARCHIVED,
                        ":height": u32::from(tip_height),
                    ],
                )
                .map_err(|e| SyncError::db(format!("transparent watch demote spent: {e}")))?;
            }
        }

        Ok(())
    })
}

fn select_refresh_batches(
    db_path: &str,
    account_id: AccountUuid,
    tip_height: BlockHeight,
) -> Result<Vec<UtxoRefreshBatch>, SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let hot_rows = select_rows(
        &conn,
        account_id,
        tip_height,
        &format!(
            "watch_class IN ('{WATCH_CLASS_RECEIVE}', '{WATCH_CLASS_FRONTIER}', '{WATCH_CLASS_UNSPENT}', '{WATCH_CLASS_RECENT}')"
        ),
        "next_utxo_query_height, child_index, address",
        None,
    )?;
    let archived_rows = select_rows(
        &conn,
        account_id,
        tip_height,
        "watch_class = 'archived_ledger'",
        "last_utxo_query_height IS NOT NULL,
             last_utxo_query_height,
             next_utxo_query_height,
             child_index,
             address",
        Some(ARCHIVED_SWEEP_LIMIT_PER_ACCOUNT),
    )?;

    let mut grouped = BTreeMap::<u32, BTreeSet<String>>::new();
    for row in hot_rows.into_iter().chain(archived_rows) {
        grouped
            .entry(row.next_utxo_query_height)
            .or_default()
            .insert(row.address);
    }

    Ok(grouped
        .into_iter()
        .map(|(height, addresses)| UtxoRefreshBatch {
            start_height: BlockHeight::from_u32(height),
            addresses: addresses.into_iter().collect(),
        })
        .collect())
}

fn select_rows(
    conn: &rusqlite::Connection,
    account_id: AccountUuid,
    tip_height: BlockHeight,
    filter: &str,
    order_by: &str,
    limit: Option<i64>,
) -> Result<Vec<WatchRow>, SyncError> {
    let limit_clause = if let Some(limit) = limit {
        format!("LIMIT {limit}")
    } else {
        String::new()
    };
    let mut stmt = conn
        .prepare(&format!(
            "SELECT address, next_utxo_query_height
             FROM {TRANSPARENT_WATCH_TABLE}
             WHERE account_uuid = :account_uuid
               AND next_utxo_query_height <= :tip_height
               AND {filter}
             ORDER BY {order_by}
             {limit_clause}"
        ))
        .map_err(|e| SyncError::db(format!("transparent watch select rows: {e}")))?;

    let rows = stmt
        .query_map(
            named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":tip_height": u32::from(tip_height),
            ],
            |row| {
                Ok(WatchRow {
                    address: row.get(0)?,
                    next_utxo_query_height: row.get(1)?,
                })
            },
        )
        .map_err(|e| SyncError::db(format!("transparent watch rows: {e}")))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| SyncError::db(format!("transparent watch row decode: {e}")))?;

    Ok(rows)
}

fn query_unspent_addresses(
    db_path: &str,
    account_id: AccountUuid,
    tip_height: BlockHeight,
) -> Result<Vec<String>, SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let mut stmt = conn
        .prepare(
            r#"
            SELECT DISTINCT tro.address
            FROM transparent_received_outputs tro
            JOIN accounts a ON a.id = tro.account_id
            LEFT JOIN (
                SELECT txo_spends.transparent_received_output_id
                FROM transparent_received_output_spends txo_spends
                JOIN transactions stx ON stx.id_tx = txo_spends.transaction_id
                WHERE stx.mined_height IS NOT NULL
                   OR stx.expiry_height > :tip_height
            ) spent ON spent.transparent_received_output_id = tro.id
            WHERE a.uuid = :account_uuid
              AND spent.transparent_received_output_id IS NULL
            "#,
        )
        .map_err(|e| SyncError::db(format!("transparent watch prepare unspent query: {e}")))?;
    let rows = stmt
        .query_map(
            named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":tip_height": u32::from(tip_height),
            ],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| SyncError::db(format!("transparent watch unspent rows: {e}")))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| SyncError::db(format!("transparent watch unspent address: {e}")))?;
    Ok(rows)
}

fn upsert_watch_address(
    db_path: &str,
    account_id: AccountUuid,
    address: &str,
    watch_class: &str,
    key_scope: i64,
    child_index: i64,
    next_query_height: BlockHeight,
    updated_height: BlockHeight,
) -> Result<(), SyncError> {
    ensure_watch_table(db_path)?;
    with_wallet_db_write_lock("sync_engine.transparent_watch.upsert", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute(
            &format!(
                "INSERT INTO {TRANSPARENT_WATCH_TABLE} (
                    account_uuid, address, watch_class, key_scope, child_index,
                    sweep_bucket, next_utxo_query_height, last_utxo_query_height,
                    created_at_height, updated_at_height
                 )
                 VALUES (
                    :account_uuid, :address, :watch_class, :key_scope, :child_index,
                    :sweep_bucket, :next_height, NULL,
                    :updated_height, :updated_height
                 )
                 ON CONFLICT (account_uuid, address) DO UPDATE
                 SET watch_class = CASE
                        WHEN watch_class = :receive AND :watch_class != :receive THEN watch_class
                        WHEN watch_class = :frontier AND :watch_class = :archived
                            THEN watch_class
                        WHEN watch_class = :unspent AND :watch_class = :archived
                            THEN watch_class
                        ELSE :watch_class
                     END,
                     key_scope = CASE
                        WHEN :key_scope >= 0 THEN :key_scope
                        ELSE key_scope
                     END,
                     child_index = CASE
                        WHEN :child_index >= 0 THEN :child_index
                        ELSE child_index
                     END,
                     sweep_bucket = :sweep_bucket,
                     next_utxo_query_height = CASE
                        WHEN watch_class IN (:receive, :frontier, :unspent)
                         AND :watch_class != :recent
                        THEN next_utxo_query_height
                        WHEN :watch_class = :archived
                        THEN MAX(next_utxo_query_height, :next_height)
                        ELSE MIN(next_utxo_query_height, :next_height)
                     END,
                     updated_at_height = MAX(updated_at_height, :updated_height)"
            ),
            named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":address": address,
                ":watch_class": watch_class,
                ":receive": WATCH_CLASS_RECEIVE,
                ":frontier": WATCH_CLASS_FRONTIER,
                ":unspent": WATCH_CLASS_UNSPENT,
                ":recent": WATCH_CLASS_RECENT,
                ":archived": WATCH_CLASS_ARCHIVED,
                ":key_scope": key_scope,
                ":child_index": child_index,
                ":sweep_bucket": 0,
                ":next_height": u32::from(next_query_height),
                ":updated_height": u32::from(updated_height),
            ],
        )
        .map(|_| ())
        .map_err(|e| SyncError::db(format!("transparent watch upsert address: {e}")))
    })
}

fn scope_code(scope: TransparentKeyScope) -> i64 {
    if scope == TransparentKeyScope::EXTERNAL {
        0
    } else if scope == TransparentKeyScope::INTERNAL {
        1
    } else {
        2
    }
}

struct WatchRow {
    address: String,
    next_utxo_query_height: u32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn batches_group_by_next_query_height() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let account_id = AccountUuid::from_uuid(uuid::Uuid::from_u128(1));

        upsert_watch_address(
            db_path,
            account_id,
            "tmA",
            WATCH_CLASS_RECEIVE,
            NO_KEY_SCOPE,
            NO_CHILD_INDEX,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(20),
        )
        .unwrap();
        upsert_watch_address(
            db_path,
            account_id,
            "tmB",
            WATCH_CLASS_UNSPENT,
            NO_KEY_SCOPE,
            NO_CHILD_INDEX,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(20),
        )
        .unwrap();
        upsert_watch_address(
            db_path,
            account_id,
            "tmC",
            WATCH_CLASS_FRONTIER,
            0,
            1,
            BlockHeight::from_u32(15),
            BlockHeight::from_u32(20),
        )
        .unwrap();

        let batches = select_refresh_batches(db_path, account_id, BlockHeight::from_u32(20))
            .expect("select batches");
        assert_eq!(batches.len(), 2);
        assert_eq!(batches[0].start_height, BlockHeight::from_u32(10));
        assert_eq!(batches[0].addresses, vec!["tmA", "tmB"]);
        assert_eq!(batches[1].start_height, BlockHeight::from_u32(15));
        assert_eq!(batches[1].addresses, vec!["tmC"]);
    }

    #[test]
    fn complete_batch_advances_watermark_and_demotes_recent_without_utxo() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let account_id = AccountUuid::from_uuid(uuid::Uuid::from_u128(2));

        upsert_watch_address(
            db_path,
            account_id,
            "tmA",
            WATCH_CLASS_RECENT,
            0,
            0,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(20),
        )
        .unwrap();

        complete_refresh_batch(
            db_path,
            account_id,
            &[String::from("tmA")],
            &[],
            BlockHeight::from_u32(20),
        )
        .unwrap();

        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).unwrap();
        let row = conn
            .query_row(
                &format!(
                    "SELECT watch_class, next_utxo_query_height
                     FROM {TRANSPARENT_WATCH_TABLE}
                     WHERE account_uuid = :account_uuid AND address = 'tmA'"
                ),
                named_params![":account_uuid": account_id.expose_uuid()],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?)),
            )
            .unwrap();
        assert_eq!(row, (WATCH_CLASS_ARCHIVED.to_string(), 21));
    }

    #[test]
    fn hot_receive_upsert_preserves_existing_watermark() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let account_id = AccountUuid::from_uuid(uuid::Uuid::from_u128(3));

        upsert_watch_address(
            db_path,
            account_id,
            "tmA",
            WATCH_CLASS_RECEIVE,
            NO_KEY_SCOPE,
            NO_CHILD_INDEX,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(10),
        )
        .unwrap();
        complete_refresh_batch(
            db_path,
            account_id,
            &[String::from("tmA")],
            &[],
            BlockHeight::from_u32(20),
        )
        .unwrap();
        upsert_watch_address(
            db_path,
            account_id,
            "tmA",
            WATCH_CLASS_RECEIVE,
            NO_KEY_SCOPE,
            NO_CHILD_INDEX,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(21),
        )
        .unwrap();

        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).unwrap();
        let next_height = conn
            .query_row(
                &format!(
                    "SELECT next_utxo_query_height
                     FROM {TRANSPARENT_WATCH_TABLE}
                     WHERE account_uuid = :account_uuid AND address = 'tmA'"
                ),
                named_params![":account_uuid": account_id.expose_uuid()],
                |row| row.get::<_, u32>(0),
            )
            .unwrap();
        assert_eq!(next_height, 21);
    }

    #[test]
    fn archived_upsert_does_not_demote_hot_unspent() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let account_id = AccountUuid::from_uuid(uuid::Uuid::from_u128(4));

        upsert_watch_address(
            db_path,
            account_id,
            "tmA",
            WATCH_CLASS_UNSPENT,
            NO_KEY_SCOPE,
            NO_CHILD_INDEX,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(10),
        )
        .unwrap();
        complete_refresh_batch(
            db_path,
            account_id,
            &[String::from("tmA")],
            &[String::from("tmA")],
            BlockHeight::from_u32(20),
        )
        .unwrap();
        upsert_watch_address(
            db_path,
            account_id,
            "tmA",
            WATCH_CLASS_ARCHIVED,
            0,
            0,
            BlockHeight::from_u32(30),
            BlockHeight::from_u32(30),
        )
        .unwrap();

        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).unwrap();
        let row = conn
            .query_row(
                &format!(
                    "SELECT watch_class, next_utxo_query_height
                     FROM {TRANSPARENT_WATCH_TABLE}
                     WHERE account_uuid = :account_uuid AND address = 'tmA'"
                ),
                named_params![":account_uuid": account_id.expose_uuid()],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?)),
            )
            .unwrap();
        assert_eq!(row, (WATCH_CLASS_UNSPENT.to_string(), 21));
    }

    #[test]
    fn archived_selection_ignores_sweep_bucket() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let account_id = AccountUuid::from_uuid(uuid::Uuid::from_u128(5));

        upsert_watch_address(
            db_path,
            account_id,
            "tmArchived",
            WATCH_CLASS_ARCHIVED,
            0,
            0,
            BlockHeight::from_u32(10),
            BlockHeight::from_u32(10),
        )
        .unwrap();

        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).unwrap();
        conn.execute(
            &format!(
                "UPDATE {TRANSPARENT_WATCH_TABLE}
                 SET sweep_bucket = 19
                 WHERE account_uuid = :account_uuid AND address = 'tmArchived'"
            ),
            named_params![":account_uuid": account_id.expose_uuid()],
        )
        .unwrap();
        drop(conn);

        let selected = selected_addresses(db_path, account_id, BlockHeight::from_u32(20)).unwrap();
        assert_eq!(selected, vec!["tmArchived"]);
    }

    #[test]
    fn archived_limit_rotates_to_never_checked_rows() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let account_id = AccountUuid::from_uuid(uuid::Uuid::from_u128(6));

        for index in 0..10 {
            upsert_watch_address(
                db_path,
                account_id,
                &format!("tm{index:02}"),
                WATCH_CLASS_ARCHIVED,
                0,
                index,
                BlockHeight::from_u32(10),
                BlockHeight::from_u32(10),
            )
            .unwrap();
        }

        let first = selected_addresses(db_path, account_id, BlockHeight::from_u32(10)).unwrap();
        assert_eq!(first.len(), ARCHIVED_SWEEP_LIMIT_PER_ACCOUNT as usize);
        assert!(first.contains(&"tm00".to_string()));
        assert!(first.contains(&"tm07".to_string()));
        assert!(!first.contains(&"tm08".to_string()));
        assert!(!first.contains(&"tm09".to_string()));

        complete_refresh_batch(db_path, account_id, &first, &[], BlockHeight::from_u32(20))
            .unwrap();

        let second = selected_addresses(db_path, account_id, BlockHeight::from_u32(21)).unwrap();
        assert_eq!(second.len(), ARCHIVED_SWEEP_LIMIT_PER_ACCOUNT as usize);
        assert!(second.contains(&"tm08".to_string()));
        assert!(second.contains(&"tm09".to_string()));
    }

    fn selected_addresses(
        db_path: &str,
        account_id: AccountUuid,
        tip_height: BlockHeight,
    ) -> Result<Vec<String>, SyncError> {
        Ok(select_refresh_batches(db_path, account_id, tip_height)?
            .into_iter()
            .flat_map(|batch| batch.addresses)
            .collect())
    }
}
