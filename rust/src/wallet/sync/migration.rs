use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

pub(crate) fn delete_account_migration_rows_with_tx(
    tx: &rusqlite::Transaction<'_>,
    account_uuid: &str,
) -> Result<(), String> {
    let metadata_table_exists = tx
        .query_row(
            "SELECT 1 FROM sqlite_schema
             WHERE type = 'table' AND name = 'vizor_shared_migration_run_ids'",
            [],
            |_| Ok(()),
        )
        .optional()
        .map_err(|e| format!("Check shared migration metadata store: {e}"))?
        .is_some();
    if metadata_table_exists {
        if let Ok(account_uuid) = uuid::Uuid::parse_str(account_uuid) {
            tx.execute(
                "DELETE FROM vizor_shared_migration_run_ids WHERE account_uuid = ?1",
                params![account_uuid.as_bytes().as_slice()],
            )
            .map_err(|e| format!("Delete shared migration metadata: {e}"))?;
        }
    }
    Ok(())
}

pub(crate) const PHASE_NO_ORCHARD_FUNDS: &str = "no_orchard_funds";
pub(crate) const PHASE_WAITING_FOR_SPENDABLE_ORCHARD: &str = "waiting_for_spendable_orchard";
pub(crate) const PHASE_WAITING_FOR_IRONWOOD_SPENDABILITY: &str =
    "waiting_for_ironwood_spendability";
pub(crate) const PHASE_READY_TO_PREPARE: &str = "ready_to_prepare";
pub(crate) const PHASE_WAITING_DENOM_CONFIRMATIONS: &str = "waiting_denom_confirmations";
pub(crate) const PHASE_READY_TO_MIGRATE: &str = "ready_to_migrate";
pub(crate) const PHASE_BROADCAST_SCHEDULED: &str = "broadcast_scheduled";
pub(crate) const PHASE_BROADCASTING: &str = "broadcasting";
pub(crate) const PHASE_WAITING_MIGRATION_CONFIRMATIONS: &str = "waiting_migration_confirmations";
pub(crate) const PHASE_COMPLETE: &str = "complete";
pub(crate) const PHASE_FAILED_TERMINAL: &str = "failed_terminal";

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct MigrationScheduleEntry {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub part_index: Option<u32>,
    pub value_zatoshi: u64,
    pub block_offset: u32,
}

#[derive(Debug)]
pub(crate) struct MigrationOutboxItem {
    pub item_id: String,
    pub part_index: u32,
    pub txid_hex: String,
    pub raw_tx: Vec<u8>,
    pub anchor_boundary_height: u32,
    pub scheduled_height: u32,
    pub schedule_start_height: u32,
    pub expiry_height: u32,
}

#[derive(Debug)]
pub(crate) struct MigrationOutboxBatch {
    pub run_id: String,
    pub timing_mean_blocks: u32,
    pub timing_max_blocks: u32,
    pub next_proof_height: Option<u32>,
    pub items: Vec<MigrationOutboxItem>,
}

#[derive(Clone, Debug)]
pub(crate) struct ScheduledMigrationBroadcast {
    pub txid_hex: String,
    pub value_zatoshi: u64,
    pub scheduled_at_ms: i64,
    pub schedule_start_height: Option<u32>,
    pub scheduled_height: u32,
    pub status: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationPartState {
    Preparing,
    Scheduled,
    Migrating,
    Confirming,
    Completed,
    NeedsInput,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct MigrationPartStatus {
    pub part_index: u32,
    pub schedule_order: Option<u32>,
    pub value_zatoshi: u64,
    pub state: MigrationPartState,
    pub txid_hex: Option<String>,
    pub schedule_start_height: Option<u32>,
    pub scheduled_height: Option<u32>,
    pub confirmation_count: u32,
    pub confirmation_target: u32,
}

#[derive(Clone, Debug)]
pub(crate) struct MigrationStatus {
    pub phase: String,
    pub active_run_id: Option<String>,
    pub target_values_zatoshi: Vec<u64>,
    pub prepared_note_count: u32,
    pub denomination_confirmation_count: u32,
    pub denomination_confirmation_target: u32,
    pub denomination_split_completed_count: u32,
    pub denomination_split_total_count: u32,
    pub pending_tx_count: u32,
    pub broadcasted_tx_count: u32,
    pub confirmed_tx_count: u32,
    pub total_count: u32,
    pub signed_child_pczt_count: u32,
    pub pending_split_stage_count: u32,
    pub message: Option<String>,
    pub can_abandon: bool,
    pub signing_batch_limit: u32,
    pub schedule_mean_delay_blocks: u32,
    pub schedule_max_delay_blocks: u32,
    pub max_prepared_notes_per_run: u32,
    pub next_action_height: Option<u32>,
    pub estimated_completion_height: Option<u32>,
    pub next_action_part_index: Option<u32>,
    pub scheduled_broadcasts: Vec<ScheduledMigrationBroadcast>,
    pub parts: Vec<MigrationPartStatus>,
}
