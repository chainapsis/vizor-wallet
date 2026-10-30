//! Read-only inspection of mobile Ironwood migration preparation.
//!
//! The iOS C FFI polls confirmations through it; foreground FRB calls own sync
//! and advancement between confirmed waves.

use std::fmt;

use crate::wallet::network::WalletNetwork;
use crate::wallet::sync;

/// Codes cross the iOS C FFI. 1, 3 and 5 came only from the removed Android
/// preparation path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MigrationPreparationState {
    WaitingForDenominationPreparation = 0,
    NeedsUserAction = 2,
    Inactive = 4,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MigrationPreparationProgress {
    pub state: MigrationPreparationState,
    pub confirmation_count: u32,
    pub confirmation_target: u32,
    pub completed_stage_count: u32,
    pub total_stage_count: u32,
}

impl MigrationPreparationProgress {
    fn inactive() -> Self {
        Self {
            state: MigrationPreparationState::Inactive,
            confirmation_count: 0,
            confirmation_target: 0,
            completed_stage_count: 0,
            total_stage_count: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MigrationPreparationError {
    Execution(String),
}

impl fmt::Display for MigrationPreparationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Execution(message) => formatter.write_str(message),
        }
    }
}

impl std::error::Error for MigrationPreparationError {}

pub fn inspect_read_only(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
) -> Result<MigrationPreparationProgress, MigrationPreparationError> {
    let snapshot = sync::migration_preparation_snapshot_read_only(
        db_path,
        account_uuid,
        network,
        expected_run_id,
    )
    .map_err(MigrationPreparationError::Execution)?;
    let Some(snapshot) = snapshot else {
        return Ok(MigrationPreparationProgress::inactive());
    };
    let state = match snapshot.phase.as_str() {
        "waiting_denom_confirmations" => {
            MigrationPreparationState::WaitingForDenominationPreparation
        }
        "broadcast_scheduled" | "broadcasting" | "waiting_migration_confirmations" => {
            MigrationPreparationState::Inactive
        }
        _ => MigrationPreparationState::NeedsUserAction,
    };
    Ok(MigrationPreparationProgress {
        state,
        confirmation_count: 0,
        confirmation_target: sync::denomination_confirmations_required(),
        completed_stage_count: snapshot.completed_stage_count,
        total_stage_count: snapshot.total_stage_count,
    })
}

pub fn observable_transaction_ids(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
) -> Result<Vec<String>, MigrationPreparationError> {
    sync::observable_denomination_transaction_ids(db_path, account_uuid, network, expected_run_id)
        .map_err(MigrationPreparationError::Execution)
}

pub fn inspect_proof_readiness(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    expected_run_id: &str,
) -> Result<bool, MigrationPreparationError> {
    sync::orchard_migration_proof_readiness_read_only(
        db_path,
        network,
        account_uuid,
        expected_run_id,
    )
    .map_err(MigrationPreparationError::Execution)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_only_inspection_does_not_upgrade_legacy_stage_schema() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE vizor_migration_runs (
                 run_id TEXT PRIMARY KEY,
                 account_uuid TEXT NOT NULL,
                 network TEXT NOT NULL,
                 phase TEXT NOT NULL
             );
             CREATE TABLE vizor_migration_denomination_stages (
                 run_id TEXT NOT NULL,
                 status TEXT NOT NULL
             );
             INSERT INTO vizor_migration_runs
                 (run_id, account_uuid, network, phase)
             VALUES
                 ('run-1', 'account-1', 'test', 'waiting_denom_confirmations');
             INSERT INTO vizor_migration_denomination_stages (run_id, status)
             VALUES
                 ('run-1', 'confirmed'),
                 ('run-1', 'broadcasted');",
        )
        .unwrap();
        let schema_version_before: i64 = conn
            .pragma_query_value(None, "schema_version", |row| row.get(0))
            .unwrap();
        drop(conn);

        let progress = inspect_read_only(
            file.path().to_str().unwrap(),
            WalletNetwork::Test,
            "account-1",
            "run-1",
        )
        .unwrap();

        assert_eq!(
            progress.state,
            MigrationPreparationState::WaitingForDenominationPreparation
        );
        assert_eq!(progress.completed_stage_count, 1);
        assert_eq!(progress.total_stage_count, 2);

        let conn = rusqlite::Connection::open(file.path()).unwrap();
        let schema_version_after: i64 = conn
            .pragma_query_value(None, "schema_version", |row| row.get(0))
            .unwrap();
        let columns = conn
            .prepare("PRAGMA table_info(vizor_migration_denomination_stages)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(schema_version_after, schema_version_before);
        assert_eq!(columns, vec!["run_id", "status"]);
    }

    #[test]
    fn read_only_inspection_defers_missing_stage_schema_to_foreground() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE vizor_migration_runs (
                 run_id TEXT PRIMARY KEY,
                 account_uuid TEXT NOT NULL,
                 network TEXT NOT NULL,
                 phase TEXT NOT NULL
             );
             INSERT INTO vizor_migration_runs
                 (run_id, account_uuid, network, phase)
             VALUES
                 ('run-1', 'account-1', 'test', 'waiting_denom_confirmations');",
        )
        .unwrap();
        drop(conn);

        let error = inspect_read_only(
            file.path().to_str().unwrap(),
            WalletNetwork::Test,
            "account-1",
            "run-1",
        )
        .unwrap_err();

        assert!(error.to_string().contains("requires foreground recovery"));
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        let stage_table_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master
                 WHERE type = 'table'
                   AND name = 'vizor_migration_denomination_stages'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(stage_table_count, 0);
    }

    #[test]
    fn proof_readiness_inspection_does_not_upgrade_legacy_stage_schema() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let conn = rusqlite::Connection::open(file.path()).unwrap();
        conn.execute_batch(
            "CREATE TABLE vizor_migration_runs (
                 run_id TEXT PRIMARY KEY,
                 account_uuid TEXT NOT NULL,
                 network TEXT NOT NULL,
                 phase TEXT NOT NULL,
                 proof_retry_height INTEGER,
                 timing_policy TEXT NOT NULL
             );
             CREATE TABLE vizor_migration_signed_child_pczts (
                 run_id TEXT NOT NULL,
                 message_id TEXT NOT NULL,
                 child_index INTEGER NOT NULL,
                 selected_note_json TEXT NOT NULL,
                 anchor_boundary_height INTEGER
             );
             CREATE TABLE vizor_migration_pending_txs (
                 run_id TEXT NOT NULL,
                 part_index INTEGER NOT NULL
             );
             CREATE TABLE vizor_migration_denomination_stages (
                 run_id TEXT NOT NULL,
                 status TEXT NOT NULL
             );
             INSERT INTO vizor_migration_runs
                 (run_id, account_uuid, network, phase, proof_retry_height,
                  timing_policy)
             VALUES
                 ('run-1', 'account-1', 'test', 'ready_to_migrate',
                  100, 'standard');",
        )
        .unwrap();
        let schema_version_before: i64 = conn
            .pragma_query_value(None, "schema_version", |row| row.get(0))
            .unwrap();
        drop(conn);

        assert!(!inspect_proof_readiness(
            file.path().to_str().unwrap(),
            WalletNetwork::Test,
            "account-1",
            "run-1",
        )
        .unwrap());

        let conn = rusqlite::Connection::open(file.path()).unwrap();
        let schema_version_after: i64 = conn
            .pragma_query_value(None, "schema_version", |row| row.get(0))
            .unwrap();
        let columns = conn
            .prepare("PRAGMA table_info(vizor_migration_denomination_stages)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(schema_version_after, schema_version_before);
        assert_eq!(columns, vec!["run_id", "status"]);
    }
}
