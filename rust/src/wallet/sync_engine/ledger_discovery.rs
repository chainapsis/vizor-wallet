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
                 SET checked_height = :checked_height
                 WHERE checked_height > :checked_height"
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
    let start_height = next_scan_start(db_path, account_id, scope)?.unwrap_or(birthday);
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
            if enhance::process_taddress_history(client, db, db_path, network, addr_str, start, end)
                .await?
            {
                found += 1;
            }
        }
    }

    set_scope_checked_height(db_path, account_id, scope, tip_height)?;

    if queried > 0 || found > 0 {
        log::info!(
            "sync: ledger transparent discovery scope={} checked {} addresses from {} to {} ({} with txs)",
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
                PRIMARY KEY (account_uuid, key_scope)
            )"
        ))
        .map_err(|e| SyncError::db(format!("ledger discovery create table: {e}")))
    })
}

fn next_scan_start(
    db_path: &str,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
) -> Result<Option<BlockHeight>, SyncError> {
    let conn =
        open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT).map_err(SyncError::db)?;
    let checked = conn
        .query_row(
            &format!(
                "SELECT checked_height
                 FROM {LEDGER_TRANSPARENT_SCAN_TABLE}
                 WHERE account_uuid = :account_uuid AND key_scope = :key_scope"
            ),
            rusqlite::named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":key_scope": scope_code(scope),
            ],
            |row| row.get::<_, u32>(0),
        )
        .optional()
        .map_err(|e| SyncError::db(format!("ledger discovery read checkpoint: {e}")))?;

    Ok(checked
        .and_then(|h| h.checked_add(1))
        .map(BlockHeight::from_u32))
}

fn set_scope_checked_height(
    db_path: &str,
    account_id: AccountUuid,
    scope: TransparentKeyScope,
    height: BlockHeight,
) -> Result<(), SyncError> {
    with_wallet_db_write_lock("sync_engine.ledger_discovery.set_checkpoint", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, SYNC_DB_BUSY_TIMEOUT)
            .map_err(SyncError::db)?;
        conn.execute(
            &format!(
                "INSERT INTO {LEDGER_TRANSPARENT_SCAN_TABLE} (account_uuid, key_scope, checked_height)
                 VALUES (:account_uuid, :key_scope, :checked_height)
                 ON CONFLICT (account_uuid, key_scope) DO UPDATE
                 SET checked_height = MAX(checked_height, :checked_height)"
            ),
            rusqlite::named_params![
                ":account_uuid": account_id.expose_uuid(),
                ":key_scope": scope_code(scope),
                ":checked_height": u32::from(height),
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
                "INSERT INTO {LEDGER_TRANSPARENT_SCAN_TABLE} (account_uuid, key_scope, checked_height)
                 VALUES
                    (x'01', 0, 50),
                    (x'02', 0, 100),
                    (x'03', 1, 150)"
            ),
            [],
        )
        .unwrap();

        rewind_ledger_transparent_discovery_to_height(db_path_str, BlockHeight::from_u32(75))
            .unwrap();

        let mut stmt = conn
            .prepare(&format!(
                "SELECT key_scope, checked_height
                 FROM {LEDGER_TRANSPARENT_SCAN_TABLE}
                 ORDER BY account_uuid"
            ))
            .unwrap();
        let rows = stmt
            .query_map([], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, u32>(1)?)))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();

        assert_eq!(rows, vec![(0, 50), (0, 75), (1, 75)]);
    }
}
