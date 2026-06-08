//! Ledger Live transparent-address compatibility discovery.
//!
//! Ledger Live rotates Zcash transparent P2PKH receive/change addresses under
//! `m/44'/133'/0'/0/i` and `m/44'/133'/0'/1/i`. This pass discovers typical
//! Ledger Live transparent activity automatically from the account birthday.

use std::collections::HashSet;

use rusqlite::OptionalExtension;
use tonic::transport::Channel;
use transparent::{
    address::TransparentAddress,
    keys::{NonHardenedChildIndex, TransparentKeyScope},
};
use zcash_client_backend::{
    data_api::{ll::LowLevelWalletWrite, Account as _, AccountPurpose, AccountSource, WalletRead},
    proto::service::compact_tx_streamer_client::CompactTxStreamerClient,
};
use zcash_client_sqlite::AccountUuid;
use zcash_keys::{
    encoding::AddressCodec as _,
    keys::{ReceiverRequirement, UnifiedAddressRequest},
};
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{
        open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock, WalletDatabase,
        LEDGER_TRANSPARENT_SCAN_TABLE, SYNC_DB_BUSY_TIMEOUT,
    },
    network::WalletNetwork,
};

use super::{enhance, SyncError};

#[derive(Clone)]
struct Candidate {
    address: TransparentAddress,
    index: NonHardenedChildIndex,
}

#[derive(Clone, Copy)]
struct ScopeScanState {
    checked_height: Option<BlockHeight>,
    historical_tip_height: BlockHeight,
    historical_complete: bool,
}

pub(super) async fn run_ledger_transparent_discovery(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    tip_height: BlockHeight,
) -> Result<(), SyncError> {
    ensure_scan_table(db_path)?;

    let account_ids = db
        .get_account_ids()
        .map_err(|e| SyncError::db(format!("ledger discovery get_account_ids: {e}")))?;

    for account_id in account_ids {
        let account = db
            .get_account(account_id)
            .map_err(|e| SyncError::db(format!("ledger discovery get_account: {e}")))?
            .ok_or_else(|| SyncError::db("ledger discovery account disappeared"))?;

        if !is_ledger_account_zero(account.source())
            || account.ufvk().and_then(|k| k.transparent()).is_none()
        {
            continue;
        }

        let birthday = account.birthday_height();
        scan_scope(
            client,
            db,
            db_path,
            network,
            account_id,
            TransparentKeyScope::EXTERNAL,
            birthday,
            tip_height,
        )
        .await?;
        scan_scope(
            client,
            db,
            db_path,
            network,
            account_id,
            TransparentKeyScope::INTERNAL,
            birthday,
            tip_height,
        )
        .await?;
    }

    Ok(())
}

/// Clamp Ledger transparent discovery checkpoints after the wallet has been
/// rewound to `height`.
///
/// This function intentionally does not take `with_wallet_db_write_lock`;
/// callers use it from existing rewind critical sections.
pub(super) fn rewind_ledger_transparent_discovery_to_height(
    db_path: &str,
    height: BlockHeight,
) -> Result<(), SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let table_exists = conn
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            rusqlite::params![LEDGER_TRANSPARENT_SCAN_TABLE],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| SyncError::db(format!("ledger discovery table lookup: {e}")))?
        .is_some();

    if !table_exists {
        return Ok(());
    }

    let updated = conn
        .execute(
            &format!(
                "UPDATE {LEDGER_TRANSPARENT_SCAN_TABLE}
                 SET checked_height = MIN(checked_height, :checked_height),
                     historical_complete =
                        CASE
                            WHEN historical_tip_height IS NOT NULL
                             AND historical_tip_height > :checked_height
                            THEN 0
                            ELSE historical_complete
                        END
                 WHERE checked_height > :checked_height
                    OR (
                        historical_complete != 0
                        AND historical_tip_height IS NOT NULL
                        AND historical_tip_height > :checked_height
                    )"
            ),
            rusqlite::named_params![":checked_height": u32::from(height)],
        )
        .map_err(|e| SyncError::db(format!("ledger discovery rewind checkpoint: {e}")))?;

    if updated > 0 {
        log::info!(
            "sync: clamped {updated} Ledger transparent discovery checkpoint(s) to {height}"
        );
    }

    Ok(())
}

pub(super) fn mark_ledger_transparent_historical_complete(
    db_path: &str,
    scanned_height: BlockHeight,
) -> Result<(), SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let table_exists = conn
        .query_row(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
            rusqlite::params![LEDGER_TRANSPARENT_SCAN_TABLE],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| SyncError::db(format!("ledger discovery table lookup: {e}")))?
        .is_some();

    if !table_exists {
        return Ok(());
    }

    let updated = conn
        .execute(
            &format!(
                "UPDATE {LEDGER_TRANSPARENT_SCAN_TABLE}
                 SET historical_complete = 1
                 WHERE historical_complete = 0
                   AND historical_tip_height IS NOT NULL
                   AND historical_tip_height <= :scanned_height
                   AND checked_height >= historical_tip_height"
            ),
            rusqlite::named_params![":scanned_height": u32::from(scanned_height)],
        )
        .map_err(|e| SyncError::db(format!("ledger discovery mark complete: {e}")))?;

    if updated > 0 {
        log::info!("sync: marked {updated} Ledger transparent historical scan(s) complete");
    }

    Ok(())
}

fn is_ledger_account_zero(source: &AccountSource) -> bool {
    let derivation = match source {
        AccountSource::Derived { derivation, .. } => Some(derivation),
        AccountSource::Imported {
            purpose:
                AccountPurpose::Spending {
                    derivation: Some(derivation),
                },
            ..
        } => Some(derivation),
        _ => None,
    };

    derivation.is_some_and(|d| d.account_index() == zip32::AccountId::ZERO)
}

async fn scan_scope(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    birthday: BlockHeight,
    tip_height: BlockHeight,
) -> Result<(), SyncError> {
    let state = scan_state(db_path, account_id, scope, tip_height)?;
    if state.historical_complete {
        scan_frontier_scope(
            client, db, db_path, network, account_id, scope, birthday, tip_height, state,
        )
        .await
    } else {
        scan_historical_scope(
            client, db, db_path, network, account_id, scope, birthday, tip_height, state,
        )
        .await
    }
}

async fn scan_historical_scope(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    birthday: BlockHeight,
    tip_height: BlockHeight,
    state: ScopeScanState,
) -> Result<(), SyncError> {
    let Some(start_height) = next_scan_start(state.checked_height).or(Some(birthday)) else {
        return Ok(());
    };
    let end_height = std::cmp::min(tip_height, state.historical_tip_height);
    if start_height > end_height {
        return Ok(());
    }

    let start = u32::from(start_height) as u64;
    let end = u32::from(end_height) as u64;
    let mut scanned = HashSet::<u32>::new();
    let mut queried = 0usize;
    let mut found = 0usize;

    loop {
        generate_gap_addresses(db, account_id, scope)?;
        let candidates = collect_candidates(db, account_id, scope)?;
        let pending = candidates
            .into_iter()
            .filter(|candidate| scanned.insert(candidate.index.index()))
            .collect::<Vec<_>>();

        if pending.is_empty() {
            break;
        }

        for candidate in pending {
            queried += 1;
            let addr_str = candidate.address.encode(&network);
            if enhance::process_taddress_history(
                client,
                db,
                db_path,
                network,
                addr_str,
                start,
                end,
                enhance::TAddressHistoryErrorPolicy::Strict,
            )
            .await?
            .found
            {
                found += 1;
            }
        }
    }

    set_scope_scan_state(
        db_path,
        account_id,
        scope,
        end_height,
        state.historical_tip_height,
        false,
    )?;

    if queried > 0 || found > 0 {
        log::info!(
            "sync: ledger transparent historical discovery scope={} checked {} addresses from {} to {} ({} with txs, historical_tip={})",
            scope_code(scope),
            queried,
            start,
            end,
            found,
            state.historical_tip_height
        );
    }

    Ok(())
}

async fn scan_frontier_scope(
    client: &mut CompactTxStreamerClient<Channel>,
    db: &mut WalletDatabase,
    db_path: &str,
    network: WalletNetwork,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    birthday: BlockHeight,
    tip_height: BlockHeight,
    state: ScopeScanState,
) -> Result<(), SyncError> {
    let Some(start_height) = next_scan_start(state.checked_height).or(Some(birthday)) else {
        return Ok(());
    };
    if start_height > tip_height {
        return Ok(());
    }

    let start = u32::from(start_height) as u64;
    let end = u32::from(tip_height) as u64;
    let mut scanned = HashSet::<u32>::new();
    let mut queried = 0usize;
    let mut found = 0usize;

    loop {
        generate_gap_addresses(db, account_id, scope)?;
        let Some(frontier_index) = next_history_frontier_index(db_path, account_id, scope)? else {
            break;
        };
        if !scanned.insert(frontier_index.index()) {
            break;
        }

        let candidates = collect_candidates(db, account_id, scope)?;
        let Some(candidate) = candidates
            .into_iter()
            .find(|candidate| candidate.index == frontier_index)
        else {
            log::warn!(
                "sync: Ledger transparent frontier address missing scope={} index={}",
                scope_code(scope),
                frontier_index.index()
            );
            break;
        };

        queried += 1;
        let addr_str = candidate.address.encode(&network);
        if enhance::process_taddress_history(
            client,
            db,
            db_path,
            network,
            addr_str,
            start,
            end,
            enhance::TAddressHistoryErrorPolicy::Strict,
        )
        .await?
        .found
        {
            found += 1;
        } else {
            break;
        }
    }

    set_scope_scan_state(
        db_path,
        account_id,
        scope,
        tip_height,
        state.historical_tip_height,
        true,
    )?;

    if queried > 0 || found > 0 {
        log::info!(
            "sync: ledger transparent frontier discovery scope={} checked {} address(es) from {} to {} ({} with txs)",
            scope_code(scope),
            queried,
            start,
            end,
            found
        );
    }

    Ok(())
}

fn ledger_transparent_request() -> UnifiedAddressRequest {
    use ReceiverRequirement::*;
    UnifiedAddressRequest::unsafe_custom(Allow, Allow, Require)
}

fn generate_gap_addresses(
    db: &mut WalletDatabase,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock(
        "sync_engine.ledger_discovery.generate_gap_addresses",
        || {
            db.transactionally(|tx_db| {
                tx_db.generate_transparent_gap_addresses(
                    account_id,
                    scope,
                    ledger_transparent_request(),
                )
            })
            .map_err(|e| SyncError::db(format!("ledger discovery generate gap addresses: {e}")))
        },
    )
}

fn collect_candidates(
    db: &WalletDatabase,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
) -> Result<Vec<Candidate>, SyncError> {
    let mut candidates = db
        .get_transparent_receivers(account_id, true, false)
        .map_err(|e| SyncError::db(format!("ledger discovery get transparent receivers: {e}")))?
        .into_iter()
        .filter_map(|(address, metadata)| {
            if metadata.scope() == Some(scope)
                && matches!(address, TransparentAddress::PublicKeyHash(_))
            {
                metadata
                    .address_index()
                    .map(|index| Candidate { address, index })
            } else {
                None
            }
        })
        .collect::<Vec<_>>();

    candidates.sort_by_key(|candidate| candidate.index.index());
    Ok(candidates)
}

fn ensure_scan_table(db_path: &str) -> Result<(), SyncError> {
    with_wallet_db_write_lock("sync_engine.ledger_discovery.ensure_table", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute_batch(&format!(
            "CREATE TABLE IF NOT EXISTS {LEDGER_TRANSPARENT_SCAN_TABLE} (
                account_uuid BLOB NOT NULL,
                key_scope INTEGER NOT NULL,
                checked_height INTEGER NOT NULL,
                historical_tip_height INTEGER,
                historical_complete INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (account_uuid, key_scope)
            )"
        ))
        .map_err(|e| SyncError::db(format!("ledger discovery create table: {e}")))?;
        ensure_scan_table_column(&conn, "historical_tip_height", "INTEGER")?;
        ensure_scan_table_column(&conn, "historical_complete", "INTEGER NOT NULL DEFAULT 0")?;
        conn.execute(
            &format!(
                "UPDATE {LEDGER_TRANSPARENT_SCAN_TABLE}
                 SET historical_tip_height = checked_height,
                     historical_complete = 1
                 WHERE historical_tip_height IS NULL"
            ),
            [],
        )
        .map_err(|e| SyncError::db(format!("ledger discovery migrate scan table: {e}")))?;
        Ok(())
    })
}

fn ensure_scan_table_column(
    conn: &rusqlite::Connection,
    column_name: &str,
    column_definition: &str,
) -> Result<(), SyncError> {
    let mut stmt = conn
        .prepare(&format!(
            "PRAGMA table_info({LEDGER_TRANSPARENT_SCAN_TABLE})"
        ))
        .map_err(|e| SyncError::db(format!("ledger discovery table_info: {e}")))?;
    let exists = stmt
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(|e| SyncError::db(format!("ledger discovery table_info rows: {e}")))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| SyncError::db(format!("ledger discovery table_info column: {e}")))?
        .into_iter()
        .any(|name| name == column_name);

    if !exists {
        conn.execute(
            &format!(
                "ALTER TABLE {LEDGER_TRANSPARENT_SCAN_TABLE}
                 ADD COLUMN {column_name} {column_definition}"
            ),
            [],
        )
        .map_err(|e| SyncError::db(format!("ledger discovery add column {column_name}: {e}")))?;
    }

    Ok(())
}

fn scan_state(
    db_path: &str,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    tip_height: BlockHeight,
) -> Result<ScopeScanState, SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let row = conn
        .query_row(
            &format!(
                "SELECT checked_height,
                        COALESCE(historical_tip_height, checked_height),
                        historical_complete
                 FROM {LEDGER_TRANSPARENT_SCAN_TABLE}
                 WHERE account_uuid = :account_uuid AND key_scope = :key_scope"
            ),
            rusqlite::named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":key_scope": scope_code(scope),
            ],
            |row| {
                Ok((
                    row.get::<_, u32>(0)?,
                    row.get::<_, u32>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| SyncError::db(format!("ledger discovery read checkpoint: {e}")))?;

    match row {
        Some((checked_height, historical_tip_height, historical_complete)) => Ok(ScopeScanState {
            checked_height: Some(BlockHeight::from_u32(checked_height)),
            historical_tip_height: BlockHeight::from_u32(historical_tip_height),
            historical_complete: historical_complete != 0,
        }),
        None => Ok(ScopeScanState {
            checked_height: None,
            historical_tip_height: tip_height,
            historical_complete: false,
        }),
    }
}

fn next_scan_start(checked_height: Option<BlockHeight>) -> Option<BlockHeight> {
    checked_height
        .and_then(|h| u32::from(h).checked_add(1))
        .map(BlockHeight::from_u32)
}

fn next_history_frontier_index(
    db_path: &str,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
) -> Result<Option<NonHardenedChildIndex>, SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let account_uuid = account_id.expose_uuid();
    let frontier = conn
        .query_row(
            r#"
            WITH wallet_account AS (
                SELECT id FROM accounts WHERE uuid = :account_uuid
            )
            SELECT COALESCE(MAX(a.transparent_child_index) + 1, 0)
            FROM v_address_first_use a
            JOIN wallet_account wa ON wa.id = a.account_id
            WHERE a.key_scope = :key_scope
              AND a.transparent_child_index IS NOT NULL
              AND a.first_use_height IS NOT NULL
            "#,
            rusqlite::named_params![
                ":account_uuid": account_uuid,
                ":key_scope": scope_code(scope),
            ],
            |row| row.get::<_, u32>(0),
        )
        .map_err(|e| SyncError::db(format!("ledger discovery find history frontier: {e}")))?;

    Ok(NonHardenedChildIndex::from_index(frontier))
}

fn set_scope_scan_state(
    db_path: &str,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    height: BlockHeight,
    historical_tip_height: BlockHeight,
    historical_complete: bool,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock("sync_engine.ledger_discovery.set_checkpoint", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute(
            &format!(
                "INSERT INTO {LEDGER_TRANSPARENT_SCAN_TABLE} (
                    account_uuid, key_scope, checked_height,
                    historical_tip_height, historical_complete
                 )
                 VALUES (
                    :account_uuid, :key_scope, :checked_height,
                    :historical_tip_height, :historical_complete
                 )
                 ON CONFLICT (account_uuid, key_scope) DO UPDATE
                 SET checked_height = MAX(checked_height, :checked_height),
                     historical_tip_height = COALESCE(
                        historical_tip_height,
                        :historical_tip_height
                     ),
                     historical_complete =
                        CASE
                            WHEN :historical_complete != 0 THEN 1
                            ELSE historical_complete
                        END"
            ),
            rusqlite::named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":key_scope": scope_code(scope),
                ":checked_height": u32::from(height),
                ":historical_tip_height": u32::from(historical_tip_height),
                ":historical_complete": if historical_complete { 1 } else { 0 },
            ],
        )
        .map(|_| ())
        .map_err(|e| SyncError::db(format!("ledger discovery write checkpoint: {e}")))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scope_codes_match_bip44_change_level() {
        assert_eq!(scope_code(TransparentKeyScope::EXTERNAL), 0);
        assert_eq!(scope_code(TransparentKeyScope::INTERNAL), 1);
    }

    #[test]
    fn ledger_gap_limit_is_reduced_for_sync_overhead() {
        assert_eq!(crate::wallet::db::LEDGER_TRANSPARENT_GAP_LIMIT, 10);
    }

    #[test]
    fn rewind_noops_before_scan_table_exists() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        rewind_ledger_transparent_discovery_to_height(db_path_str, BlockHeight::from_u32(75))
            .unwrap();
    }

    #[test]
    fn rewind_clamps_checkpoints_above_height() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        ensure_scan_table(db_path_str).unwrap();
        let conn = open_wallet_raw_conn_with_timeout(db_path_str, SYNC_DB_BUSY_TIMEOUT).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {LEDGER_TRANSPARENT_SCAN_TABLE} (
                    account_uuid, key_scope, checked_height,
                    historical_tip_height, historical_complete
                 )
                 VALUES
                    (x'01', 0, 50, 40, 1),
                    (x'02', 0, 100, 90, 1),
                    (x'03', 1, 150, 70, 1),
                    (x'04', 1, 40, 100, 1)"
            ),
            [],
        )
        .unwrap();

        rewind_ledger_transparent_discovery_to_height(db_path_str, BlockHeight::from_u32(75))
            .unwrap();

        let mut stmt = conn
            .prepare(&format!(
                "SELECT key_scope, checked_height, historical_complete
                 FROM {LEDGER_TRANSPARENT_SCAN_TABLE}
                 ORDER BY account_uuid"
            ))
            .unwrap();
        let rows = stmt
            .query_map([], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, u32>(1)?,
                    row.get::<_, i64>(2)?,
                ))
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();

        assert_eq!(rows, vec![(0, 50, 1), (0, 75, 0), (1, 75, 1), (1, 40, 0)]);
    }

    #[test]
    fn mark_historical_complete_waits_for_history_and_wallet_scan() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        ensure_scan_table(db_path_str).unwrap();
        let conn = open_wallet_raw_conn_with_timeout(db_path_str, SYNC_DB_BUSY_TIMEOUT).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {LEDGER_TRANSPARENT_SCAN_TABLE} (
                    account_uuid, key_scope, checked_height,
                    historical_tip_height, historical_complete
                 )
                 VALUES
                    (x'01', 0, 100, 100, 0),
                    (x'02', 0, 90, 100, 0),
                    (x'03', 1, 120, 130, 0),
                    (x'04', 1, 70, 60, 1)"
            ),
            [],
        )
        .unwrap();

        mark_ledger_transparent_historical_complete(db_path_str, BlockHeight::from_u32(100))
            .unwrap();

        let rows = historical_complete_rows(&conn);
        assert_eq!(rows, vec![1, 0, 0, 1]);
    }

    #[test]
    fn ensure_scan_table_migrates_legacy_checkpoints_as_complete() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();

        let conn = open_wallet_raw_conn_with_timeout(db_path_str, SYNC_DB_BUSY_TIMEOUT).unwrap();
        conn.execute_batch(&format!(
            "CREATE TABLE {LEDGER_TRANSPARENT_SCAN_TABLE} (
                account_uuid BLOB NOT NULL,
                key_scope INTEGER NOT NULL,
                checked_height INTEGER NOT NULL,
                PRIMARY KEY (account_uuid, key_scope)
            );
            INSERT INTO {LEDGER_TRANSPARENT_SCAN_TABLE}
                (account_uuid, key_scope, checked_height)
            VALUES (x'01', 0, 88);"
        ))
        .unwrap();
        drop(conn);

        ensure_scan_table(db_path_str).unwrap();

        let conn = open_wallet_raw_conn_with_timeout(db_path_str, SYNC_DB_BUSY_TIMEOUT).unwrap();
        let row = conn
            .query_row(
                &format!(
                    "SELECT checked_height, historical_tip_height, historical_complete
                     FROM {LEDGER_TRANSPARENT_SCAN_TABLE}"
                ),
                [],
                |row| {
                    Ok((
                        row.get::<_, u32>(0)?,
                        row.get::<_, u32>(1)?,
                        row.get::<_, i64>(2)?,
                    ))
                },
            )
            .unwrap();

        assert_eq!(row, (88, 88, 1));
    }

    #[test]
    fn next_history_frontier_uses_highest_seen_index_plus_one() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path_str = db_path.to_str().unwrap();
        let account_id = AccountUuid::from_uuid(
            uuid::Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap(),
        );

        let conn = open_wallet_raw_conn_with_timeout(db_path_str, SYNC_DB_BUSY_TIMEOUT).unwrap();
        conn.execute_batch(
            "CREATE TABLE accounts (
                id INTEGER PRIMARY KEY,
                uuid BLOB NOT NULL
            );
            CREATE TABLE v_address_first_use (
                account_id INTEGER NOT NULL,
                key_scope INTEGER NOT NULL,
                transparent_child_index INTEGER,
                first_use_height INTEGER
            );",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO accounts (id, uuid) VALUES (7, ?1)",
            rusqlite::params![account_id.expose_uuid()],
        )
        .unwrap();

        let first =
            next_history_frontier_index(db_path_str, account_id, TransparentKeyScope::EXTERNAL)
                .unwrap();
        assert_eq!(first, Some(NonHardenedChildIndex::ZERO));

        conn.execute(
            "INSERT INTO v_address_first_use
                (account_id, key_scope, transparent_child_index, first_use_height)
             VALUES
                (7, 0, 3, 110),
                (7, 0, 30, 120),
                (7, 1, 200, 130)",
            [],
        )
        .unwrap();

        let next_external =
            next_history_frontier_index(db_path_str, account_id, TransparentKeyScope::EXTERNAL)
                .unwrap();
        assert_eq!(next_external.map(|i| i.index()), Some(31));

        let next_internal =
            next_history_frontier_index(db_path_str, account_id, TransparentKeyScope::INTERNAL)
                .unwrap();
        assert_eq!(next_internal.map(|i| i.index()), Some(201));
    }

    fn historical_complete_rows(conn: &rusqlite::Connection) -> Vec<i64> {
        let mut stmt = conn
            .prepare(&format!(
                "SELECT historical_complete
                 FROM {LEDGER_TRANSPARENT_SCAN_TABLE}
                 ORDER BY account_uuid"
            ))
            .unwrap();
        stmt.query_map([], |row| row.get::<_, i64>(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
    }
}
