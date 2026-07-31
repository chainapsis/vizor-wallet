use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use rand::{rngs::OsRng, seq::SliceRandom, CryptoRng, Rng, RngCore};
use rusqlite::{params, OptionalExtension, TransactionBehavior};
use serde::{Deserialize, Serialize};
use zcash_client_backend::data_api::{
    anchor_retention::AnchorRetentionInterval, wallet::ConfirmationsPolicy,
};
use zeroize::Zeroizing;

use crate::wallet::db::{
    open_readonly_conn_with_timeout, open_wallet_raw_conn_with_timeout, with_wallet_db_write_lock,
    WALLET_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::secret_payload;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

use super::READ_DB_BUSY_TIMEOUT;

#[allow(dead_code)]
mod preparation_plan;
mod split_plan;
mod stages;
pub(crate) use split_plan::{
    plan_padded_denominations, SplitStageInput, SplitTerminalKind, DENOMINATION_SPLIT_ACTIONS,
};
#[allow(unused_imports)]
pub(crate) use stages::{
    all_denomination_stages_confirmed, denomination_stage_chain_records,
    denomination_stage_expected_txids, denomination_stage_status, denomination_stage_status_counts,
    denomination_stages_for_run, expired_broadcasted_denomination_stage_count,
    expired_unbroadcast_denomination_stage_count, insert_denomination_stages_with_tx,
    locked_denomination_stage_input_outpoints, mark_denomination_stage_broadcasted,
    mark_denomination_stage_confirmed_at, pending_raw_denomination_stages,
    promote_awaiting_denomination_stage, replace_denomination_stage_confirmation_identity,
    reset_denomination_stage_exact, reset_denomination_stage_for_reorg, DenominationStage,
    DenominationStageChainRecord, DenominationStageInputRef, DenominationStageInsert,
    DenominationStageOutputKind, DenominationStageOutputRef, DenominationStageStatus,
    DenominationStageStatusCounts, PendingRawDenominationStage,
};
use stages::{STAGES_TABLE, STAGE_INPUTS_TABLE, STAGE_OUTPUTS_TABLE};

include!("migration/policy.rs");
include!("migration/preparation_policy.rs");

const RUNS_TABLE: &str = "vizor_migration_runs";
const PREPARED_NOTES_TABLE: &str = "vizor_migration_prepared_notes";
const PENDING_TXS_TABLE: &str = "vizor_migration_pending_txs";
const SIGNED_CHILD_PCZTS_TABLE: &str = "vizor_migration_signed_child_pczts";
const RETAINED_ANCHORS_TABLE: &str = "vizor_migration_retained_orchard_anchors";
const RETENTION_RELEASE_SENTINEL_RUN_ID: &str = "";
pub(crate) fn delete_account_migration_rows_with_tx(
    tx: &rusqlite::Transaction<'_>,
    account_uuid: &str,
) -> Result<(), String> {
    if !table_exists(tx, RUNS_TABLE)? {
        return Ok(());
    }

    for table in [
        STAGE_INPUTS_TABLE,
        STAGE_OUTPUTS_TABLE,
        STAGES_TABLE,
        PREPARED_NOTES_TABLE,
        PENDING_TXS_TABLE,
        SIGNED_CHILD_PCZTS_TABLE,
    ] {
        if table_exists(tx, table)? {
            tx.execute(
                &format!(
                    "DELETE FROM {table}
                     WHERE run_id IN (
                         SELECT run_id FROM {RUNS_TABLE} WHERE account_uuid = ?1
                     )"
                ),
                params![account_uuid],
            )
            .map_err(|e| format!("Delete account migration rows from {table}: {e}"))?;
        }
    }

    tx.execute(
        &format!("DELETE FROM {RUNS_TABLE} WHERE account_uuid = ?1"),
        params![account_uuid],
    )
    .map_err(|e| format!("Delete account migration runs: {e}"))?;
    Ok(())
}

pub(crate) const PHASE_NO_ORCHARD_FUNDS: &str = "no_orchard_funds";
pub(crate) const PHASE_WAITING_FOR_SPENDABLE_ORCHARD: &str = "waiting_for_spendable_orchard";
pub(crate) const PHASE_WAITING_FOR_IRONWOOD_SPENDABILITY: &str =
    "waiting_for_ironwood_spendability";
pub(crate) const PHASE_READY_TO_PREPARE: &str = "ready_to_prepare";
pub(crate) const PHASE_AWAITING_PREPARATION: &str = "awaiting_preparation";
// Never written. This phase is only ever read: it widens draft matching and
// the `WHERE phase IN (...)` filters below, and it has been read-only since it
// was introduced, so no shipped build can have stored it. A hardware draft that
// still needs its split signature is stored as `PHASE_AWAITING_PREPARATION`.
pub(crate) const PHASE_AWAITING_DENOMINATION_SIGNATURE: &str = "awaiting_denomination_signature";
pub(crate) const PHASE_WAITING_DENOM_CONFIRMATIONS: &str = "waiting_denom_confirmations";
pub(crate) const PHASE_READY_TO_MIGRATE: &str = "ready_to_migrate";
pub(crate) const MIGRATION_KEYSTONE_BATCH_MAX_PARTS: u32 = 8;
pub(crate) const PHASE_BROADCAST_SCHEDULED: &str = "broadcast_scheduled";
pub(crate) const PHASE_BROADCASTING: &str = "broadcasting";
pub(crate) const PHASE_WAITING_MIGRATION_CONFIRMATIONS: &str = "waiting_migration_confirmations";
pub(crate) const PHASE_COMPLETE: &str = "complete";
// Never written either. Reads only: an anchor-retention filter and the
// user-action decision below both accept it, but nothing stores it, so any
// surface that exists solely to present a paused run is unreachable.
pub(crate) const PHASE_PAUSED: &str = "paused";
pub(crate) const PHASE_FAILED_RECOVERABLE: &str = "failed_recoverable";
pub(crate) const PHASE_FAILED_TERMINAL: &str = "failed_terminal";
pub(crate) const PHASE_ABANDONED: &str = "abandoned";

include!("migration/denomination_policy.rs");

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct PreparedOrchardNoteRef {
    pub txid_hex: String,
    pub output_index: u32,
    pub value_zatoshi: u64,
    pub note_version: u8,
    pub nullifier_hex: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct PreparedAnchorRetentionCandidate {
    pub run_id: String,
    pub account_uuid: String,
    pub note: PreparedOrchardNoteRef,
    pub timing_policy: MigrationTimingPolicy,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct PendingMigrationTxMetadata {
    pub tx_kind: String,
    pub funding_account_uuid: String,
    pub selected_note: PreparedOrchardNoteRef,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct MigrationScheduleEntry {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub part_index: Option<u32>,
    pub value_zatoshi: u64,
    pub block_offset: u32,
}

pub(crate) struct PendingMigrationTxInsert {
    pub part_index: u32,
    pub txid_hex: String,
    pub raw_tx: Vec<u8>,
    pub target_height: u32,
    pub anchor_boundary_height: Option<u32>,
    pub expiry_height: u32,
    /// Absolute ZIP 318 broadcast height committed before this transaction is
    /// signed. Its canonical expiry is derived from this height.
    pub scheduled_height: u32,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct PendingMigrationPartRecovery {
    pub part_index: u32,
    pub old_txid_hex: String,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
}

pub(crate) struct PendingMigrationTxReplacement {
    pub old_txid_hex: String,
    pub replacement: PendingMigrationTxInsert,
}

pub(crate) struct SignedMigrationPcztInsert {
    pub message_id: String,
    pub child_index: u32,
    pub base_pczt: Vec<u8>,
    /// The produced spend-authorization signatures for this child, persisted in
    /// place of a full signed PCZT (the "signatures-only" round-trip). Stored
    /// encrypted as a compact blob; the wallet re-applies them onto the
    /// re-proofed base at finalization time.
    pub sigs: Vec<pczt::roles::signer::SpendAuthSignature>,
    pub target_height: u32,
    pub anchor_boundary_height: Option<u32>,
    pub expiry_height: u32,
    pub scheduled_height: u32,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
}

pub(crate) struct SignedMigrationPczt {
    pub message_id: String,
    pub child_index: u32,
    pub base_pczt: Vec<u8>,
    /// Decoded compact spend-authorization signatures for this child (see
    /// [`SignedMigrationPcztInsert::sigs`]).
    pub sigs: Vec<pczt::roles::signer::SpendAuthSignature>,
    pub target_height: u32,
    pub anchor_boundary_height: Option<u32>,
    pub expiry_height: u32,
    pub scheduled_height: u32,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SignedChildProofCandidate {
    pub selected_note: PreparedOrchardNoteRef,
    pub anchor_boundary_height: Option<u32>,
}

pub(crate) struct DuePendingMigrationTx {
    pub txid_hex: String,
    pub raw_tx: Vec<u8>,
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

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct MigrationOutboxScheduleUpdate {
    pub item_id: String,
    pub scheduled_height: u32,
    pub schedule_start_height: u32,
}

pub(crate) struct MigrationOutboxTxState {
    pub run_phase: String,
    pub status: String,
    pub expiry_height: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct UnbroadcastMigrationRecoveryCandidate {
    pub txid_hex: String,
    pub status: String,
    pub scheduled_height: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationStopCandidateKind {
    DenominationStage,
    MigrationTransaction,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationBroadcastAttemptState {
    NotAttempted,
    Attempted,
    UnknownLegacy,
}

impl MigrationBroadcastAttemptState {
    fn from_db(value: i64) -> Result<Self, String> {
        match value {
            0 => Ok(Self::NotAttempted),
            1 => Ok(Self::Attempted),
            2 => Ok(Self::UnknownLegacy),
            _ => Err(format!("Invalid migration broadcast attempt state {value}")),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct MigrationStopCandidate {
    pub kind: MigrationStopCandidateKind,
    pub txid_hex: String,
    pub broadcast_height: u32,
    pub expiry_height: u32,
    pub attempt_state: MigrationBroadcastAttemptState,
}

pub(crate) struct PendingMigrationTotals {
    pub txids: Vec<String>,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub total_count: u32,
    pub broadcasted_count: u32,
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
    pub original_scheduled_height: Option<u32>,
    pub effective_scheduled_height: Option<u32>,
    pub mined_height: Option<u32>,
    pub confirmation_count: u32,
    pub confirmation_target: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationPreparationTransactionState {
    AwaitingInputs,
    Scheduled,
    Broadcasted,
    Confirming,
    Completed,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationPreparationOutputKind {
    Migration,
    Change,
    Continuation,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct MigrationPreparationOutputStatus {
    /// Actual Orchard note value, including any fee reserved for its migration.
    pub value_zatoshi: u64,
    /// Canonical ZIP 318 value that will reach Ironwood for migration outputs.
    pub target_value_zatoshi: Option<u64>,
    pub kind: MigrationPreparationOutputKind,
    pub next_round: Option<u32>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct MigrationPreparationTransactionStatus {
    pub stage_index: u32,
    pub approximate_value_zatoshi: u64,
    pub round: u32,
    pub fee_zatoshi: u64,
    pub planned_height: u32,
    pub projected_height: u32,
    pub projected_completion_height: u32,
    pub outputs: Vec<MigrationPreparationOutputStatus>,
    pub state: MigrationPreparationTransactionState,
    pub scheduled_height: Option<u32>,
    pub mined_height: Option<u32>,
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
    /// Planned denomination stages that have reached trusted depth.
    pub denomination_split_completed_count: u32,
    /// Total denomination stages planned for this run.
    pub denomination_split_total_count: u32,
    pub pending_tx_count: u32,
    pub broadcasted_tx_count: u32,
    pub confirmed_tx_count: u32,
    pub total_count: u32,
    pub signed_child_pczt_count: u32,
    /// Staged split transactions that still need reconciliation or broadcast.
    pub pending_split_stage_count: u32,
    pub message: Option<String>,
    pub can_abandon: bool,
    pub signing_batch_limit: u32,
    pub schedule_mean_delay_blocks: u32,
    pub schedule_max_delay_blocks: u32,
    pub preparation_mean_delay_blocks: u32,
    /// Earliest block height at which the wallet can make more progress.
    pub next_action_height: Option<u32>,
    /// Earliest chain height at which the wallet should retry proofs against
    /// the next usable ZIP 318 anchor window.
    pub next_proof_window_height: Option<u32>,
    /// Unpromoted migration parts waiting for that proof window.
    pub next_proof_window_part_indices: Vec<u32>,
    /// Projected height at which every migration part reaches trusted depth.
    pub estimated_completion_height: Option<u32>,
    /// Part associated with `next_action_height`, when it can be identified.
    pub next_action_part_index: Option<u32>,
    /// Exact migration parts the next signing operation will include.
    pub current_signing_part_indices: Vec<u32>,
    pub scheduled_broadcasts: Vec<ScheduledMigrationBroadcast>,
    pub preparation_transactions: Vec<MigrationPreparationTransactionStatus>,
    pub parts: Vec<MigrationPartStatus>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
struct MigrationTimingProjection {
    next_action_height: Option<u32>,
    next_proof_window_height: Option<u32>,
    next_proof_window_part_indices: Vec<u32>,
    estimated_completion_height: Option<u32>,
    next_action_part_index: Option<u32>,
    schedule_order_by_part: BTreeMap<u32, u32>,
    projected_signed_parts: Vec<MigrationTimingProjectedSignedPart>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct MigrationTimingProjectedSignedPart {
    part_index: u32,
    schedule_start_height: u32,
    scheduled_height: u32,
}

#[derive(Clone, Debug)]
struct MigrationTimingPendingPart {
    part_index: Option<u32>,
    target_height: u32,
    schedule_start_height: Option<u32>,
    scheduled_height: u32,
    status: String,
    mined_height: Option<u32>,
}

#[derive(Clone, Copy, Debug)]
struct MigrationTimingSignedChild {
    part_index: u32,
    target_height: u32,
}

pub(crate) fn migration_status(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    orchard_spendable: u64,
    orchard_pending: u64,
    ironwood_spendable: u64,
    ironwood_pending: u64,
) -> Result<MigrationStatus, String> {
    migration_status_with_projection_height(
        db_path,
        network,
        account_uuid,
        orchard_spendable,
        orchard_pending,
        ironwood_spendable,
        ironwood_pending,
        None,
    )
}

#[allow(clippy::too_many_arguments)]
fn migration_status_with_projection_height(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    orchard_spendable: u64,
    orchard_pending: u64,
    ironwood_spendable: u64,
    ironwood_pending: u64,
    projection_scanned_height: Option<u32>,
) -> Result<MigrationStatus, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;

    if let Some(run) = active_run(&conn, account_uuid, network)? {
        let current_scanned_height = projection_scanned_height
            .map(Ok)
            .unwrap_or_else(|| migration_projection_scanned_height(db_path, network))?;
        return status_for_run(&conn, run, current_scanned_height);
    }

    let orchard_migratable = orchard_balance_can_create_migration_output(orchard_spendable)?;
    if orchard_pending == 0 && !orchard_migratable {
        if let Some(run) = latest_completed_run(&conn, account_uuid, network)? {
            let current_scanned_height = projection_scanned_height
                .map(Ok)
                .unwrap_or_else(|| migration_projection_scanned_height(db_path, network))?;
            let mut status = status_for_run(&conn, run, current_scanned_height)?;
            // Completed runs are receipts, not resumable work. Preserve their
            // target values for completion UI without exposing an active run.
            status.active_run_id = None;
            return Ok(status);
        }
    }
    let phase = if orchard_pending > 0 {
        PHASE_WAITING_FOR_SPENDABLE_ORCHARD
    } else if orchard_migratable {
        PHASE_READY_TO_PREPARE
    } else if ironwood_spendable > 0 {
        PHASE_COMPLETE
    } else if ironwood_pending > 0 {
        PHASE_WAITING_FOR_IRONWOOD_SPENDABILITY
    } else {
        PHASE_NO_ORCHARD_FUNDS
    };

    Ok(MigrationStatus {
        phase: phase.to_string(),
        active_run_id: None,
        target_values_zatoshi: Vec::new(),
        prepared_note_count: 0,
        denomination_confirmation_count: 0,
        denomination_confirmation_target: denomination_confirmations_required(),
        denomination_split_completed_count: 0,
        denomination_split_total_count: 0,
        pending_tx_count: 0,
        broadcasted_tx_count: 0,
        confirmed_tx_count: 0,
        total_count: 0,
        signed_child_pczt_count: 0,
        pending_split_stage_count: 0,
        message: None,
        can_abandon: false,
        signing_batch_limit: MIGRATION_KEYSTONE_BATCH_MAX_PARTS,
        schedule_mean_delay_blocks: schedule_parameters_with_policy(
            network,
            configured_timing_policy(network),
        )
        .0,
        schedule_max_delay_blocks: schedule_parameters_with_policy(
            network,
            configured_timing_policy(network),
        )
        .1,
        preparation_mean_delay_blocks: 0,
        next_action_height: None,
        next_proof_window_height: None,
        next_proof_window_part_indices: Vec::new(),
        estimated_completion_height: None,
        next_action_part_index: None,
        current_signing_part_indices: Vec::new(),
        scheduled_broadcasts: Vec::new(),
        preparation_transactions: Vec::new(),
        parts: Vec::new(),
    })
}

fn migration_projection_scanned_height(
    db_path: &str,
    network: WalletNetwork,
) -> Result<u32, String> {
    super::get_sync_progress(db_path, network).and_then(|progress| {
        u32::try_from(progress.scanned_height)
            .map_err(|_| "Migration scanned height exceeds u32".to_string())
    })
}

/// Reconciles the final denomination outputs for a staged run without needing
/// balance information from the UI status call.
pub(crate) fn reconcile_denomination_run(db_path: &str, run_id: &str) -> Result<bool, String> {
    reconcile_denomination_stage_chain_state(db_path, run_id)?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let run = conn
        .query_row(
            &format!(
                "SELECT run_id, phase, target_values_json, last_error
                 FROM {RUNS_TABLE}
                 WHERE run_id = ?1"
            ),
            params![run_id],
            |row| {
                let target_values_json: String = row.get(2)?;
                Ok(ActiveRun {
                    run_id: row.get(0)?,
                    phase: row.get(1)?,
                    target_values_zatoshi: serde_json::from_str(&target_values_json)
                        .unwrap_or_default(),
                    last_error: row.get(3)?,
                })
            },
        )
        .optional()
        .map_err(|e| format!("Read staged migration run: {e}"))?
        .ok_or_else(|| format!("Migration run {run_id} was not found"))?;
    reconcile_denomination_confirmations(&conn, &run)?;
    let phase = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read reconciled migration phase: {e}"))?;
    if phase == PHASE_WAITING_DENOM_CONFIRMATIONS {
        // Trusted confirmations are not sufficient until every terminal note
        // also has the spend metadata populated by reconciliation above.
        return Ok(false);
    }
    if phase == PHASE_READY_TO_MIGRATE {
        return Ok(true);
    }
    if !matches!(
        phase.as_str(),
        PHASE_BROADCAST_SCHEDULED | PHASE_BROADCASTING | PHASE_WAITING_MIGRATION_CONFIRMATIONS
    ) {
        return Ok(false);
    }

    let progress = denomination_split_progress_for_run(&conn, run_id)?;
    Ok(progress.total_count == 0 || progress.completed_count == progress.total_count)
}

fn orchard_balance_can_create_migration_output(orchard_spendable: u64) -> Result<bool, String> {
    if orchard_spendable == 0 {
        return Ok(false);
    }
    let plan = plan_denominations(
        orchard_spendable,
        DENOMINATION_SPLIT_STATUS_FEE_ESTIMATE_ZATOSHI,
        MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI,
        MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI,
    )?;
    Ok(!plan.migration_outputs.is_empty())
}

#[derive(Clone, Debug)]
pub(crate) struct ActiveRun {
    pub run_id: String,
    pub phase: String,
    pub target_values_zatoshi: Vec<u64>,
    pub last_error: Option<String>,
}

fn timing_policy_for_run_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
    _network: WalletNetwork,
) -> Result<MigrationTimingPolicy, String> {
    let value = conn
        .query_row(
            &format!("SELECT timing_policy FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration timing policy: {e}"))?;
    MigrationTimingPolicy::from_str(&value)
}

fn adopt_configured_timing_policy_for_active_run(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    adopt_timing_policy_for_active_run(
        conn,
        account_uuid,
        network,
        configured_timing_policy(network),
    )
}

fn adopt_timing_policy_for_active_run(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
    desired_policy: MigrationTimingPolicy,
) -> Result<(), String> {
    if !matches!(network, WalletNetwork::Test | WalletNetwork::Regtest)
        || desired_policy != MigrationTimingPolicy::FastTestnet
    {
        return Ok(());
    }
    let Some(run) = active_run(conn, account_uuid, network)? else {
        return Ok(());
    };
    if timing_policy_for_run_with_conn(conn, &run.run_id, network)?
        == MigrationTimingPolicy::FastTestnet
    {
        return Ok(());
    }
    let pending_tx_count = count_for_run(conn, PENDING_TXS_TABLE, &run.run_id)?;
    if pending_tx_count > 0 {
        return Ok(());
    }

    // This opt-in exists only for local Testnet validation. Before any child
    // transaction is constructed, preserve signed preparation transactions
    // while replacing the long child schedule with the fast policy.
    let schedule = planned_transfer_schedule_with_policy(
        run.target_values_zatoshi.iter().copied(),
        network,
        MigrationTimingPolicy::FastTestnet,
        &mut OsRng,
    );
    let schedule_json = serde_json::to_string(&schedule)
        .map_err(|e| format!("Encode fast Testnet migration schedule: {e}"))?;
    let now = now_ms()?;
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET timing_policy = ?1, schedule_json = ?2, updated_at_ms = ?3
             WHERE run_id = ?4 AND timing_policy != 'fast_testnet'"
        ),
        params![
            MigrationTimingPolicy::FastTestnet.as_str(),
            schedule_json,
            now,
            run.run_id,
        ],
    )
    .map_err(|e| format!("Adopt fast Testnet migration timing: {e}"))?;
    Ok(())
}

pub(crate) fn active_migration_run(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<Option<ActiveRun>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    // This predicate is on ordinary send/fee-estimate hot paths. Recovery and
    // wallet-lock reconciliation run after sync, outside the wallet write
    // mutex, so callers can safely use this while holding that mutex.
    active_run(&conn, account_uuid, network)
}

/// Lists denomination transactions that have been materialized and can
/// therefore be observed through lightwalletd without decrypting wallet data.
pub(crate) fn observable_denomination_transaction_ids(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    expected_run_id: &str,
) -> Result<Vec<String>, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))?;
    let Some(run) = active_run(&conn, account_uuid, network)? else {
        return Ok(Vec::new());
    };
    if run.run_id != expected_run_id {
        return Ok(Vec::new());
    }
    // This is the iOS background tracker's read-only boundary. Do not call the
    // normal stage helpers here: they run `ensure_schema`, which may ALTER or
    // rebuild legacy tables. Foreground migration setup owns schema upgrades.
    let mut stmt = conn
        .prepare(&format!(
            "SELECT expected_txid_hex
             FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND status IN ('broadcasted', 'confirmed')
             ORDER BY stage_index ASC"
        ))
        .map_err(|e| format!("Prepare observable migration txid query: {e}"))?;
    let rows = stmt
        .query_map(params![expected_run_id], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Query observable migration txids: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read observable migration txids: {e}"))
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct ReadOnlyMigrationPreparationSnapshot {
    pub phase: String,
    pub completed_stage_count: u32,
    pub total_stage_count: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct ReadOnlyMigrationProofSnapshot {
    pub next_proof_height: Option<u32>,
    pub timing_policy: MigrationTimingPolicy,
}

/// Reads only the state required by the iOS confirmation tracker.
///
/// This deliberately bypasses `migration_status` and the denomination stage
/// helpers because those foreground paths may run schema upgrades. A missing
/// or legacy-incompatible table is returned as an error so iOS hands the run
/// back to the foreground instead of mutating the wallet from a background
/// confirmation task.
pub(crate) fn migration_preparation_snapshot_read_only(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    expected_run_id: &str,
) -> Result<Option<ReadOnlyMigrationPreparationSnapshot>, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))?;
    if !table_exists(&conn, RUNS_TABLE)? {
        return Ok(None);
    }
    let phase = conn
        .query_row(
            &format!(
                "SELECT phase
                 FROM {RUNS_TABLE}
                 WHERE run_id = ?1 AND account_uuid = ?2 AND network = ?3
                   AND phase NOT IN ('{PHASE_NO_ORCHARD_FUNDS}', '{PHASE_COMPLETE}',
                                     '{PHASE_FAILED_TERMINAL}', '{PHASE_ABANDONED}')"
            ),
            params![expected_run_id, account_uuid, network_name(network)],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| format!("Read migration preparation phase: {e}"))?;
    let Some(phase) = phase else {
        return Ok(None);
    };

    let (completed_stage_count, total_stage_count) = if phase == PHASE_WAITING_DENOM_CONFIRMATIONS {
        if !table_exists(&conn, STAGES_TABLE)? {
            return Err(
                "Migration preparation stage schema requires foreground recovery".to_string(),
            );
        }
        let counts = conn
            .query_row(
                &format!(
                    "SELECT COALESCE(SUM(status = 'confirmed'), 0), COUNT(*)
                         FROM {STAGES_TABLE}
                         WHERE run_id = ?1"
                ),
                params![expected_run_id],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
            )
            .map_err(|e| format!("Read migration preparation stage counts: {e}"))?;
        (
            u32::try_from(counts.0)
                .map_err(|_| "Completed migration stage count exceeds u32".to_string())?,
            u32::try_from(counts.1).map_err(|_| "Migration stage count exceeds u32".to_string())?,
        )
    } else {
        (0, 0)
    };

    Ok(Some(ReadOnlyMigrationPreparationSnapshot {
        phase,
        completed_stage_count,
        total_stage_count,
    }))
}

/// Reads the run fields required by the iOS proof-readiness check.
///
/// This is intentionally separate from `migration_status`: that foreground
/// status path can repair migration schemas, while a background notification
/// wake must hand an incompatible database back to the foreground unchanged.
pub(crate) fn migration_proof_snapshot_read_only(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    expected_run_id: &str,
) -> Result<Option<ReadOnlyMigrationProofSnapshot>, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))?;
    if !table_exists(&conn, RUNS_TABLE)? {
        return Ok(None);
    }
    let snapshot = conn
        .query_row(
            &format!(
                "SELECT phase, proof_retry_height, timing_policy
                 FROM {RUNS_TABLE}
                 WHERE run_id = ?1 AND account_uuid = ?2 AND network = ?3"
            ),
            params![expected_run_id, account_uuid, network_name(network)],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<u32>>(1)?,
                    row.get::<_, String>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read migration proof snapshot: {e}"))?;
    let Some((phase, next_proof_height, timing_policy)) = snapshot else {
        return Ok(None);
    };
    match phase.as_str() {
        PHASE_READY_TO_MIGRATE | PHASE_BROADCAST_SCHEDULED => {}
        _ => return Ok(None),
    };
    Ok(Some(ReadOnlyMigrationProofSnapshot {
        next_proof_height,
        timing_policy: MigrationTimingPolicy::from_str(&timing_policy)?,
    }))
}

/// Returns whether Orchard inputs remain reserved by either an active
/// migration or a false-terminal run awaiting explicit post-sync recovery.
///
/// This is a read-only, fail-closed gate for any operation that could select
/// those inputs before recovery has restored their generic wallet locks.
pub(crate) fn migration_reserves_orchard_inputs(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<bool, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration reservation snapshot: {e}"))?;
    let reserved = migration_reserves_orchard_inputs_in_snapshot(&tx, account_uuid, network)?;
    tx.commit()
        .map_err(|e| format!("Close migration reservation snapshot: {e}"))?;
    Ok(reserved)
}

fn migration_reserves_orchard_inputs_in_snapshot(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<bool, String> {
    Ok(active_run(conn, account_uuid, network)?.is_some()
        || latest_idempotent_broadcast_failure(conn, account_uuid, network)?.is_some())
}

fn migration_phase_releases_wallet_locks(phase: &str) -> bool {
    matches!(
        phase,
        PHASE_COMPLETE | PHASE_FAILED_TERMINAL | PHASE_ABANDONED
    )
}

fn wallet_lock_reconciliation_is_stable(applied_release: bool, current_release: bool) -> bool {
    applied_release == current_release
}

fn wallet_lock_reconciliation_snapshot(
    db_path: &str,
    run_id: &str,
) -> Result<Option<(bool, Vec<(String, u32)>)>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    #[cfg(test)]
    {
        // Migration persistence tests intentionally exercise the extension
        // tables without constructing a full librustzcash wallet schema.
        if !table_exists(&conn, "schemer_migrations")? {
            return Ok(None);
        }
    }
    let phase = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| format!("Read migration phase for wallet-lock reconciliation: {e}"))?;
    phase
        .map(|phase| {
            Ok((
                migration_phase_releases_wallet_locks(&phase),
                wallet_lock_candidates_with_conn(&conn, run_id)?,
            ))
        })
        .transpose()
}

fn wallet_lock_candidates_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<Vec<(String, u32)>, String> {
    let mut candidates = BTreeSet::new();
    let mut prepared = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, output_index
             FROM {PREPARED_NOTES_TABLE}
             WHERE run_id = ?1"
        ))
        .map_err(|e| format!("Prepare migration wallet-lock note query: {e}"))?;
    let prepared_rows = prepared
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?))
        })
        .map_err(|e| format!("Query migration wallet-lock notes: {e}"))?;
    for row in prepared_rows {
        candidates.insert(row.map_err(|e| format!("Read migration wallet-lock note: {e}"))?);
    }

    let mut stage_inputs = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, output_index
             FROM {STAGE_INPUTS_TABLE}
             WHERE run_id = ?1"
        ))
        .map_err(|e| format!("Prepare denomination wallet-lock input query: {e}"))?;
    let input_rows = stage_inputs
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?))
        })
        .map_err(|e| format!("Query denomination wallet-lock inputs: {e}"))?;
    for row in input_rows {
        candidates.insert(row.map_err(|e| format!("Read denomination wallet-lock input: {e}"))?);
    }
    Ok(candidates.into_iter().collect())
}

/// Reconciles Vizor's durable migration state with librustzcash's generic,
/// owner-scoped output locks.
///
/// This is intentionally idempotent. It also discovers denomination outputs
/// that did not exist when the run was created but have since been scanned
/// into the wallet.
pub(crate) fn reconcile_wallet_locks_for_run(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
) -> Result<(), String> {
    reconcile_wallet_locks_for_run_with_outcome(db_path, network, run_id).map(|_| ())
}

/// Returns `false` when the wallet has not restored a usable target height and
/// lock creation must be retried after sync.
fn reconcile_wallet_locks_for_run_with_outcome(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
) -> Result<bool, String> {
    reconcile_wallet_locks_for_run_inner(db_path, network, run_id)
}

fn reconcile_wallet_locks_for_run_inner(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
) -> Result<bool, String> {
    // Phase transitions and wallet locks live behind different public APIs, so
    // they cannot share one SQLite transaction. Re-check the desired terminal
    // disposition after every wallet mutation. If a concurrent status/advance
    // call crossed this one, the loser immediately applies the newer state.
    // The phase-changing paths also call this function, so a transition that
    // begins after the final check supplies the matching final reconciliation.
    for _ in 0..8 {
        let Some((release_locks, candidates)) =
            wallet_lock_reconciliation_snapshot(db_path, run_id)?
        else {
            return Ok(true);
        };
        let completed = if release_locks {
            super::migration_wallet_ops::unlock_orchard_migration_outputs(
                db_path,
                network,
                run_id,
                &candidates,
            )?;
            true
        } else {
            super::migration_wallet_ops::ensure_orchard_migration_locks(
                db_path,
                network,
                run_id,
                &candidates,
            )?
        };

        let Some((current_release_locks, _)) =
            wallet_lock_reconciliation_snapshot(db_path, run_id)?
        else {
            // If the run was deleted concurrently, remove any owner-scoped
            // locks that this pass may just have created.
            super::migration_wallet_ops::unlock_orchard_migration_outputs(
                db_path,
                network,
                run_id,
                &candidates,
            )?;
            return Ok(true);
        };
        if wallet_lock_reconciliation_is_stable(release_locks, current_release_locks) {
            return Ok(completed);
        }
    }
    Err("Migration phase changed repeatedly during wallet-lock reconciliation".to_string())
}

/// Applies migration recovery that depends on freshly scanned chain state,
/// then reconciles the corresponding generic wallet locks.
///
/// This explicit post-sync entry point stays outside the wallet write mutex.
/// Status projection and ordinary-send predicates must not perform any of
/// these mutations.
pub(crate) fn reconcile_wallet_locks_after_sync(
    db_path: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut account_stmt = conn
        .prepare_cached(&format!(
            "SELECT DISTINCT account_uuid
             FROM {RUNS_TABLE}
             WHERE network = ?1
             ORDER BY account_uuid"
        ))
        .map_err(|e| format!("Prepare post-sync migration account query: {e}"))?;
    let account_uuids = account_stmt
        .query_map(params![network_name(network)], |row| {
            row.get::<_, String>(0)
        })
        .map_err(|e| format!("Query post-sync migration accounts: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read post-sync migration accounts: {e}"))?;
    drop(account_stmt);

    for account_uuid in &account_uuids {
        adopt_configured_timing_policy_for_active_run(&conn, account_uuid, network)?;
        recover_latest_idempotent_broadcast_failure(&conn, account_uuid, network)?;
    }
    let active_runs = account_uuids
        .iter()
        .map(|account_uuid| active_run(&conn, account_uuid, network))
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .flatten()
        .collect::<Vec<_>>();
    drop(conn);

    for run in active_runs {
        reconcile_denomination_stage_chain_state(db_path, &run.run_id)?;
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        ensure_schema(&conn)?;
        let run = conn
            .query_row(
                &format!(
                    "SELECT run_id, phase, target_values_json, last_error
                     FROM {RUNS_TABLE}
                     WHERE run_id = ?1"
                ),
                params![run.run_id],
                |row| {
                    let target_values_json: String = row.get(2)?;
                    Ok(ActiveRun {
                        run_id: row.get(0)?,
                        phase: row.get(1)?,
                        target_values_zatoshi: serde_json::from_str(&target_values_json)
                            .unwrap_or_default(),
                        last_error: row.get(3)?,
                    })
                },
            )
            .optional()
            .map_err(|e| format!("Read post-sync migration run: {e}"))?;
        if let Some(run) = run {
            if !migration_phase_releases_wallet_locks(&run.phase) {
                reconcile_denomination_confirmations(&conn, &run)?;
                reconcile_run_confirmations(&conn, &run.run_id)?;
                backfill_ready_migration_proof_retry_height(&conn, &run.run_id)?;
            }
        }
    }

    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT run_id
             FROM {RUNS_TABLE}
             WHERE network = ?1
             ORDER BY created_at_ms"
        ))
        .map_err(|e| format!("Prepare post-sync migration wallet-lock query: {e}"))?;
    let run_ids = stmt
        .query_map(params![network_name(network)], |row| {
            row.get::<_, String>(0)
        })
        .map_err(|e| format!("Query post-sync migration wallet locks: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read post-sync migration wallet locks: {e}"))?;
    drop(stmt);
    drop(conn);

    for run_id in run_ids {
        // Re-run this idempotent reconciliation after every completed scan.
        // Some candidates refer to denomination outputs that were not mined
        // or visible during an earlier sync, so process-lifetime caching would
        // leave them unlocked when a later scan finally discovers them.
        reconcile_wallet_locks_for_run_with_outcome(db_path, network, &run_id)?;
    }
    Ok(())
}

pub(crate) fn timing_policy_for_run(
    db_path: &str,
    run_id: &str,
    network: WalletNetwork,
) -> Result<MigrationTimingPolicy, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    timing_policy_for_run_with_conn(&conn, run_id, network)
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn create_run_with_staged_denominations_and_signed_children(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    plan: &DenominationPlan,
    prepared_notes: &[PreparedOrchardNoteRef],
    signed_children: Vec<SignedMigrationPcztInsert>,
    denomination_stages: Vec<DenominationStageInsert>,
    approved_schedule: Option<&[MigrationScheduleEntry]>,
    preparation_timing_policy: PreparationTimingPolicy,
    password: &[u8],
    salt_base64: &str,
) -> Result<String, String> {
    if denomination_stages.is_empty() && prepared_notes.is_empty() {
        return Err("Migration run has no prepared funding notes".to_string());
    }
    // Preserve the complete initial candidate set outside the custom
    // migration tables. If generic lock reconciliation succeeds and a later
    // snapshot read fails, cleanup must still be able to unlock every output
    // before deleting the durable run that defines its owner.
    let initial_wallet_lock_candidates = prepared_notes
        .iter()
        .map(|note| (note.txid_hex.clone(), note.output_index))
        .chain(denomination_stages.iter().flat_map(|stage| {
            stage
                .inputs
                .iter()
                .map(|input| (input.txid_hex.clone(), input.output_index))
        }))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    if let Some(run) = active_run(&conn, account_uuid, network)? {
        return Err(format!("Migration already active: {}", run.run_id));
    }

    let run_id = new_run_id(account_uuid);
    let now = now_ms()?;
    let target_values_json = serde_json::to_string(&plan.migration_outputs)
        .map_err(|e| format!("Encode migration targets: {e}"))?;
    let timing_policy = configured_timing_policy(network);
    let initial_phase = if denomination_stages.is_empty() {
        PHASE_READY_TO_MIGRATE
    } else {
        PHASE_WAITING_DENOM_CONFIRMATIONS
    };
    let schedule_json = match approved_schedule {
        Some(schedule) => {
            validate_schedule_with_policy(
                schedule,
                &plan.migration_outputs,
                network,
                timing_policy,
            )?;
            serde_json::to_string(schedule)
                .map_err(|e| format!("Encode approved migration schedule: {e}"))?
        }
        None => "[]".to_string(),
    };
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin staged migration run: {e}"))?;
    tx.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase, created_at_ms,
              updated_at_ms, target_values_json, timing_policy, schedule_json,
              preparation_timing_policy)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8, ?9, ?10)"
        ),
        params![
            run_id,
            account_uuid,
            network_name(network),
            db_path,
            initial_phase,
            now,
            target_values_json,
            timing_policy.as_str(),
            schedule_json,
            preparation_timing_policy.as_str(),
        ],
    )
    .map_err(|e| format!("Create staged migration run: {e}"))?;
    insert_prepared_notes_with_tx(&tx, &run_id, prepared_notes, true)?;
    insert_denomination_stages_with_tx(&tx, &run_id, denomination_stages, password, salt_base64)?;
    insert_signed_child_pczts_with_tx(
        &tx,
        &run_id,
        signed_children,
        password,
        salt_base64,
        SignedChildInsertMode::Initial,
    )?;
    tx.commit()
        .map_err(|e| format!("Commit staged migration run: {e}"))?;
    if let Err(error) = reconcile_wallet_locks_for_run(db_path, network, &run_id) {
        return Err(cleanup_failed_created_run(
            error,
            || {
                super::migration_wallet_ops::unlock_orchard_migration_outputs(
                    db_path,
                    network,
                    &run_id,
                    &initial_wallet_lock_candidates,
                )
            },
            || {
                conn.execute(
                    &format!("DELETE FROM {RUNS_TABLE} WHERE run_id = ?1"),
                    params![run_id],
                )
                .map(|_| ())
                .map_err(|e| format!("Delete unlocked migration run: {e}"))
            },
        ));
    }
    Ok(run_id)
}

pub(crate) fn create_or_resume_private_migration_draft(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    target_values_zatoshi: &[u64],
    approved_schedule: &[MigrationScheduleEntry],
    preparation_timing_policy: PreparationTimingPolicy,
) -> Result<String, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin private migration draft creation: {e}"))?;
    if let Some(run) = active_run(&tx, account_uuid, network)? {
        if is_private_migration_draft_phase(&run.phase) {
            if run.target_values_zatoshi != target_values_zatoshi {
                return Err(
                    "Saved private migration plan no longer matches this balance".to_string(),
                );
            }
            return Ok(run.run_id);
        }
        return Err(format!("Migration already active: {}", run.run_id));
    }
    if latest_idempotent_broadcast_failure(&tx, account_uuid, network)?.is_some() {
        return Err("Migration recovery must complete before creating another run".to_string());
    }

    let timing_policy = configured_timing_policy(network);
    validate_schedule_with_policy(
        approved_schedule,
        target_values_zatoshi,
        network,
        timing_policy,
    )?;
    let run_id = new_run_id(account_uuid);
    let now = now_ms()?;
    let target_values_json = serde_json::to_string(target_values_zatoshi)
        .map_err(|e| format!("Encode Keystone migration targets: {e}"))?;
    let schedule_json = serde_json::to_string(approved_schedule)
        .map_err(|e| format!("Encode Keystone migration schedule: {e}"))?;
    tx.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase, created_at_ms,
              updated_at_ms, target_values_json, timing_policy, schedule_json,
              preparation_timing_policy)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8, ?9, ?10)"
        ),
        params![
            run_id,
            account_uuid,
            network_name(network),
            db_path,
            PHASE_AWAITING_PREPARATION,
            now,
            target_values_json,
            timing_policy.as_str(),
            schedule_json,
            preparation_timing_policy.as_str(),
        ],
    )
    .map_err(|e| format!("Create private migration draft: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit private migration draft creation: {e}"))?;
    Ok(run_id)
}

fn is_private_migration_draft_phase(phase: &str) -> bool {
    matches!(
        phase,
        PHASE_AWAITING_PREPARATION | PHASE_AWAITING_DENOMINATION_SIGNATURE
    )
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn finalize_private_migration_draft(
    db_path: &str,
    run_id: &str,
    account_uuid: &str,
    network: WalletNetwork,
    plan: &DenominationPlan,
    prepared_notes: &[PreparedOrchardNoteRef],
    signed_children: Vec<SignedMigrationPcztInsert>,
    denomination_stages: Vec<DenominationStageInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    if denomination_stages.is_empty() && prepared_notes.is_empty() {
        return Err("Migration run has no prepared funding notes".to_string());
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let run = active_run(&conn, account_uuid, network)?
        .ok_or("Saved private migration draft was not found")?;
    if run.run_id != run_id || !is_private_migration_draft_phase(&run.phase) {
        return Err("Saved private migration draft is no longer awaiting preparation".to_string());
    }
    if run.target_values_zatoshi != plan.migration_outputs {
        return Err("Prepared transactions do not match the saved migration plan".to_string());
    }
    let initial_phase = if denomination_stages.is_empty() {
        PHASE_READY_TO_MIGRATE
    } else {
        PHASE_WAITING_DENOM_CONFIRMATIONS
    };
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin private migration draft finalization: {e}"))?;
    insert_prepared_notes_with_tx(&tx, run_id, prepared_notes, true)?;
    insert_denomination_stages_with_tx(&tx, run_id, denomination_stages, password, salt_base64)?;
    insert_signed_child_pczts_with_tx(
        &tx,
        run_id,
        signed_children,
        password,
        salt_base64,
        SignedChildInsertMode::Initial,
    )?;
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = NULL
             WHERE run_id = ?3 AND phase IN (?4, ?5)"
        ),
        params![
            initial_phase,
            now_ms()?,
            run_id,
            PHASE_AWAITING_PREPARATION,
            PHASE_AWAITING_DENOMINATION_SIGNATURE,
        ],
    )
    .map_err(|e| format!("Activate private migration draft: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit private migration draft: {e}"))?;
    drop(conn);
    reconcile_wallet_locks_for_run(db_path, network, run_id)
}

fn cleanup_failed_created_run(
    reconciliation_error: String,
    unlock: impl FnOnce() -> Result<(), String>,
    delete_run: impl FnOnce() -> Result<(), String>,
) -> String {
    if let Err(unlock_error) = unlock() {
        // The run is the durable source of both the deterministic LockOwner
        // and its candidate outputs. Preserve it whenever unlock cannot be
        // confirmed so startup reconciliation can safely retry.
        return format!(
            "{reconciliation_error}; additionally failed to release migration wallet locks; \
             the durable run was preserved for recovery: {unlock_error}"
        );
    }

    match delete_run() {
        Ok(()) => reconciliation_error,
        Err(delete_error) => format!(
            "{reconciliation_error}; wallet locks were released but the migration run could not \
             be removed and was preserved for reconciliation: {delete_error}"
        ),
    }
}

pub(crate) fn mark_run_phase(
    db_path: &str,
    run_id: &str,
    phase: &str,
    message: Option<&str>,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let now = now_ms()?;
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = ?3
             WHERE run_id = ?4"
        ),
        params![phase, now, message, run_id],
    )
    .map_err(|e| format!("Update migration run phase: {e}"))?;
    Ok(())
}

pub(crate) fn run_phase(db_path: &str, run_id: &str) -> Result<String, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
        params![run_id],
        |row| row.get(0),
    )
    .map_err(|e| format!("Read migration run phase: {e}"))
}

pub(crate) fn prepared_notes_for_run(
    db_path: &str,
    run_id: &str,
) -> Result<Vec<PreparedOrchardNoteRef>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, output_index, value_zatoshi, note_version, nullifier_hex
             FROM {PREPARED_NOTES_TABLE}
             WHERE run_id = ?1
             ORDER BY value_zatoshi DESC, txid_hex, output_index"
        ))
        .map_err(|e| format!("Prepare prepared-note query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok(PreparedOrchardNoteRef {
                txid_hex: row.get(0)?,
                output_index: row.get(1)?,
                value_zatoshi: row.get(2)?,
                note_version: row.get(3)?,
                nullifier_hex: row.get(4)?,
            })
        })
        .map_err(|e| format!("Query prepared notes: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read prepared notes: {e}"))
}

pub(crate) fn prepared_anchor_retention_candidates(
    db_path: &str,
    network: WalletNetwork,
) -> Result<Vec<PreparedAnchorRetentionCandidate>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT r.run_id, r.phase, r.account_uuid, r.timing_policy,
                    p.txid_hex, p.output_index, p.value_zatoshi,
                    p.note_version, p.nullifier_hex
             FROM {RUNS_TABLE} r
             INNER JOIN {PREPARED_NOTES_TABLE} p ON p.run_id = r.run_id
             WHERE r.network = ?1
               AND r.phase IN (?2, ?3, ?4, ?5, ?6, ?7)
               AND p.note_version = 2
             ORDER BY r.account_uuid, p.txid_hex, p.output_index"
        ))
        .map_err(|e| format!("Prepare migration anchor retention query: {e}"))?;
    let rows = stmt
        .query_map(
            params![
                network_name(network),
                PHASE_WAITING_DENOM_CONFIRMATIONS,
                PHASE_READY_TO_MIGRATE,
                PHASE_BROADCAST_SCHEDULED,
                // A broadcast pass persists this phase before its first send
                // and only leaves it once a send is recorded, so an interrupted
                // pass keeps the phase while the run still owns unpromoted
                // signed children. Omitting it released their anchors.
                PHASE_BROADCASTING,
                PHASE_FAILED_RECOVERABLE,
                PHASE_PAUSED,
            ],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                    PreparedOrchardNoteRef {
                        txid_hex: row.get(4)?,
                        output_index: row.get(5)?,
                        value_zatoshi: row.get(6)?,
                        note_version: row.get(7)?,
                        nullifier_hex: row.get(8)?,
                    },
                ))
            },
        )
        .map_err(|e| format!("Query migration anchor retention candidates: {e}"))?;
    let rows = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration anchor retention candidate: {e}"))?;
    drop(stmt);

    let mut remaining_by_run = BTreeMap::new();
    let mut candidates = Vec::new();
    for (run_id, phase, account_uuid, timing_policy, note) in rows {
        // Before materialization, retain every prepared note because Keystone
        // may not have supplied child signatures yet. Once any child has been
        // signed or promoted, retain only signed children that have not already
        // been promoted to pending transactions. This also covers paused runs
        // that have not reached the signing step yet.
        if matches!(
            phase.as_str(),
            PHASE_BROADCAST_SCHEDULED
                | PHASE_BROADCASTING
                | PHASE_FAILED_RECOVERABLE
                | PHASE_PAUSED
        ) {
            let remaining = match remaining_by_run.entry(run_id.clone()) {
                std::collections::btree_map::Entry::Vacant(entry) => {
                    let has_materialized_children =
                        migration_child_materialization_exists_with_conn(&conn, &run_id)?;
                    let remaining = has_materialized_children
                        .then(|| unpromoted_signed_child_note_outpoints_with_conn(&conn, &run_id));
                    entry.insert(remaining.transpose()?)
                }
                std::collections::btree_map::Entry::Occupied(entry) => entry.into_mut(),
            };
            if let Some(remaining) = remaining {
                if !remaining.contains(&(note.txid_hex.to_ascii_lowercase(), note.output_index)) {
                    continue;
                }
            }
        }
        candidates.push(PreparedAnchorRetentionCandidate {
            run_id,
            account_uuid,
            note,
            timing_policy: MigrationTimingPolicy::from_str(&timing_policy)?,
        });
    }
    Ok(candidates)
}

pub(crate) fn migration_anchor_retention_references_exist(
    db_path: &str,
    network: WalletNetwork,
) -> Result<bool, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!(
            "SELECT EXISTS(
                SELECT 1 FROM {RETAINED_ANCHORS_TABLE} WHERE network = ?1
             )"
        ),
        params![network_name(network)],
        |row| row.get::<_, bool>(0),
    )
    .map_err(|e| format!("Check migration anchor retention references: {e}"))
}

pub(crate) fn migration_anchor_retention_references(
    db_path: &str,
    network: WalletNetwork,
) -> Result<BTreeSet<(String, u32)>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT run_id, checkpoint_height
             FROM {RETAINED_ANCHORS_TABLE}
             WHERE network = ?1 AND run_id != ?2
             ORDER BY checkpoint_height, run_id"
        ))
        .map_err(|e| format!("Prepare migration anchor retention references: {e}"))?;
    let references = stmt
        .query_map(
            params![network_name(network), RETENTION_RELEASE_SENTINEL_RUN_ID],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?)),
        )
        .map_err(|e| format!("Query migration anchor retention references: {e}"))?
        .collect::<Result<BTreeSet<_>, _>>()
        .map_err(|e| format!("Read migration anchor retention reference: {e}"))?;
    Ok(references)
}

/// Whether librustzcash itself retains the checkpoint at `height` as a durable
/// anchor under the production ZIP 318 grid.
fn is_wallet_durable_anchor(height: u32, anchor_retention_floor: Option<BlockHeight>) -> bool {
    anchor_retention_floor.is_some_and(|floor| height >= u32::from(floor))
        && height.is_multiple_of(AnchorRetentionInterval::ZIP_318.block_count().get())
}

pub(crate) fn stage_migration_anchor_retention_references(
    db_path: &str,
    network: WalletNetwork,
    desired: &BTreeSet<(String, u32)>,
    retained_before_maintenance: &BTreeSet<u32>,
) -> Result<Vec<u32>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let network_name = network_name(network);
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT run_id, checkpoint_height, owns_retention
             FROM {RETAINED_ANCHORS_TABLE}
             WHERE network = ?1
             ORDER BY checkpoint_height, run_id"
        ))
        .map_err(|e| format!("Prepare migration anchor retention references: {e}"))?;
    let current = stmt
        .query_map(params![network_name], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, bool>(2)?,
            ))
        })
        .map_err(|e| format!("Query migration anchor retention references: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration anchor retention reference: {e}"))?;
    drop(stmt);

    let currently_owned = current
        .iter()
        .filter_map(|(_, height, owns)| owns.then_some(*height))
        .collect::<BTreeSet<_>>();
    let desired_heights = desired
        .iter()
        .map(|(_, height)| *height)
        .collect::<BTreeSet<_>>();
    // librustzcash independently retains interval-aligned checkpoints at or
    // after anchor-retention activation as durable anchors. Migration may have
    // retained the same checkpoint first, but must not later remove the
    // wallet's durable retention.
    let anchor_retention_floor = network.activation_height(NetworkUpgrade::Nu6_3);
    let release = currently_owned
        .difference(&desired_heights)
        .copied()
        .filter(|height| !is_wallet_durable_anchor(*height, anchor_retention_floor))
        .collect::<Vec<_>>();

    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration anchor retention update: {e}"))?;
    tx.execute(
        &format!("DELETE FROM {RETAINED_ANCHORS_TABLE} WHERE network = ?1"),
        params![network_name],
    )
    .map_err(|e| format!("Clear migration anchor retention references: {e}"))?;

    let mut owner_assigned = BTreeSet::new();
    for (run_id, checkpoint_height) in desired {
        let migration_owns = currently_owned.contains(checkpoint_height)
            || !retained_before_maintenance.contains(checkpoint_height)
            // Builds before the ownership table retained migration
            // checkpoints directly. Adopt those legacy non-durable pins so
            // they can be released when the run no longer needs them, while
            // leaving librustzcash's independently durable anchors alone.
            || !is_wallet_durable_anchor(*checkpoint_height, anchor_retention_floor);
        let owns_retention = migration_owns && owner_assigned.insert(*checkpoint_height);
        tx.execute(
            &format!(
                "INSERT INTO {RETAINED_ANCHORS_TABLE}
                 (network, run_id, checkpoint_height, owns_retention)
                 VALUES (?1, ?2, ?3, ?4)"
            ),
            params![network_name, run_id, checkpoint_height, owns_retention,],
        )
        .map_err(|e| format!("Record migration anchor retention reference: {e}"))?;
    }
    for checkpoint_height in &release {
        tx.execute(
            &format!(
                "INSERT INTO {RETAINED_ANCHORS_TABLE}
                 (network, run_id, checkpoint_height, owns_retention)
                 VALUES (?1, ?2, ?3, 1)"
            ),
            params![
                network_name,
                RETENTION_RELEASE_SENTINEL_RUN_ID,
                checkpoint_height,
            ],
        )
        .map_err(|e| format!("Stage migration anchor retention release: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit migration anchor retention update: {e}"))?;
    Ok(release)
}

pub(crate) fn finish_migration_anchor_retention_releases(
    db_path: &str,
    network: WalletNetwork,
    released: &[u32],
) -> Result<(), String> {
    if released.is_empty() {
        return Ok(());
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let network_name = network_name(network);
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration anchor retention release cleanup: {e}"))?;
    for checkpoint_height in released {
        tx.execute(
            &format!(
                "DELETE FROM {RETAINED_ANCHORS_TABLE}
                 WHERE network = ?1 AND run_id = ?2 AND checkpoint_height = ?3"
            ),
            params![
                network_name,
                RETENTION_RELEASE_SENTINEL_RUN_ID,
                checkpoint_height,
            ],
        )
        .map_err(|e| format!("Finish migration anchor retention release: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit migration anchor retention release cleanup: {e}"))
}

fn insert_prepared_notes_with_tx(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    notes: &[PreparedOrchardNoteRef],
    locked: bool,
) -> Result<(), String> {
    let lock_state = if locked { "locked" } else { "unlocked" };
    for note in notes {
        tx.execute(
            &format!(
                "INSERT OR REPLACE INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"
            ),
            params![
                run_id,
                note.txid_hex,
                note.output_index,
                note.value_zatoshi,
                note.note_version,
                note.nullifier_hex,
                lock_state,
            ],
        )
        .map_err(|e| format!("Insert prepared migration note: {e}"))?;
    }
    Ok(())
}

pub(crate) fn insert_pending_txs(
    db_path: &str,
    run_id: &str,
    pending_txs: Vec<PendingMigrationTxInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    if pending_txs.is_empty() {
        return Ok(());
    }

    with_wallet_db_write_lock("migration.insert_pending_txs", || {
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        ensure_schema(&conn)?;
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("Begin migration pending insert: {e}"))?;
        insert_pending_txs_with_tx(&tx, run_id, pending_txs, password, salt_base64)?;
        tx.commit()
            .map_err(|e| format!("Commit migration pending insert: {e}"))?;
        Ok(())
    })
}

pub(crate) fn promote_signed_child_pczts_to_pending_txs(
    db_path: &str,
    run_id: &str,
    pending_txs: Vec<PendingMigrationTxInsert>,
    remaining_child_retry_height: u32,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    if pending_txs.is_empty() {
        return Ok(());
    }

    with_wallet_db_write_lock(
        "migration.promote_signed_child_pczts_to_pending_txs",
        || {
            let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
            ensure_schema(&conn)?;
            let tx = conn
                .unchecked_transaction()
                .map_err(|e| format!("Begin signed migration PCZT promotion: {e}"))?;
            insert_pending_txs_with_tx(&tx, run_id, pending_txs, password, salt_base64)?;
            tx.execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
             SET proof_retry_height = CASE
                     WHEN EXISTS (
                         SELECT 1
                         FROM {SIGNED_CHILD_PCZTS_TABLE} c
                         WHERE c.run_id = ?2
                           AND NOT EXISTS (
                               SELECT 1
                               FROM {PENDING_TXS_TABLE} p
                               WHERE p.run_id = c.run_id
                                 AND p.part_index = c.child_index
                           )
                     )
                     THEN ?3
                     ELSE NULL
                 END,
                 updated_at_ms = ?1
             WHERE run_id = ?2"
                ),
                params![now_ms()?, run_id, remaining_child_retry_height],
            )
            .map_err(|e| format!("Update migration proof retry height after promotion: {e}"))?;
            // Retain the compact signatures and base PCZTs until the run completes.
            // If a trusted denomination transaction is later reorged, the affected
            // children can be re-anchored and proved again without another Keystone
            // scan. `signed_child_pczt_count` reports only children that do not
            // currently have a pending transaction, so retaining these rows does not
            // make an already-promoted batch look unfinished.
            tx.commit()
                .map_err(|e| format!("Commit signed migration PCZT promotion: {e}"))?;
            Ok(())
        },
    )
}

pub(crate) fn set_run_approved_schedule(
    db_path: &str,
    run_id: &str,
    network: WalletNetwork,
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let timing_policy = timing_policy_for_run_with_conn(&conn, run_id, network)?;
    validate_schedule_with_policy(schedule, target_values, network, timing_policy)?;
    let schedule_json = serde_json::to_string(schedule)
        .map_err(|e| format!("Encode approved migration schedule: {e}"))?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {RUNS_TABLE} SET schedule_json = ?1
                 WHERE run_id = ?2 AND network = ?3"
            ),
            params![schedule_json, run_id, network_name(network)],
        )
        .map_err(|e| format!("Save approved migration schedule: {e}"))?;
    if updated != 1 {
        return Err("Migration run disappeared before schedule approval".to_string());
    }
    Ok(())
}

pub(crate) fn approved_schedule_for_run(
    db_path: &str,
    run_id: &str,
) -> Result<Vec<MigrationScheduleEntry>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let schedule_json = conn
        .query_row(
            &format!("SELECT schedule_json FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read approved migration schedule: {e}"))?;
    serde_json::from_str(&schedule_json)
        .map_err(|e| format!("Decode approved migration schedule: {e}"))
}

pub(crate) fn target_values_for_run(db_path: &str, run_id: &str) -> Result<Vec<u64>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let target_values_json = conn
        .query_row(
            &format!("SELECT target_values_json FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration target values: {e}"))?;
    serde_json::from_str(&target_values_json)
        .map_err(|e| format!("Decode migration target values: {e}"))
}

pub(crate) fn signed_schedule_origin_for_run(
    db_path: &str,
    run_id: &str,
) -> Result<Option<u32>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!(
            "SELECT signed_schedule_origin_height
             FROM {RUNS_TABLE}
             WHERE run_id = ?1"
        ),
        params![run_id],
        |row| row.get(0),
    )
    .map_err(|e| format!("Read signed migration schedule origin: {e}"))
}

pub(crate) fn schedule_block_offset_for_part(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    part_index: u32,
    value_zatoshi: u64,
) -> Option<u32> {
    if schedule.iter().all(|entry| entry.part_index.is_some()) {
        return schedule
            .iter()
            .find(|entry| {
                entry.part_index == Some(part_index) && entry.value_zatoshi == value_zatoshi
            })
            .map(|entry| entry.block_offset);
    }

    let part_index = usize::try_from(part_index).ok()?;
    if target_values.get(part_index) != Some(&value_zatoshi) {
        return None;
    }
    let equal_value_rank = target_values
        .iter()
        .take(part_index)
        .filter(|value| **value == value_zatoshi)
        .count();
    schedule
        .iter()
        .filter(|entry| entry.value_zatoshi == value_zatoshi)
        .nth(equal_value_rank)
        .map(|entry| entry.block_offset)
}

fn insert_pending_txs_with_tx(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    pending_txs: Vec<PendingMigrationTxInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    let (network, timing_policy, target_values_json) = tx
        .query_row(
            &format!(
                "SELECT network, timing_policy, target_values_json
                 FROM {RUNS_TABLE} WHERE run_id = ?1"
            ),
            params![run_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                ))
            },
        )
        .map_err(|e| format!("Read migration run policy: {e}"))?;
    let network = WalletNetwork::from_str(&network)
        .ok_or_else(|| format!("Unsupported migration run network: {network}"))?;
    let timing_policy = MigrationTimingPolicy::from_str(&timing_policy)?;
    let target_values: Vec<u64> = serde_json::from_str(&target_values_json)
        .map_err(|e| format!("Decode migration run target values: {e}"))?;
    let schedule_json = tx
        .query_row(
            &format!("SELECT schedule_json FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read approved migration schedule: {e}"))?;
    let mut schedule: Vec<MigrationScheduleEntry> = serde_json::from_str(&schedule_json)
        .map_err(|e| format!("Decode approved migration schedule: {e}"))?;
    if schedule.is_empty() {
        schedule = planned_transfer_schedule_with_policy(
            target_values.iter().copied(),
            network,
            timing_policy,
            &mut OsRng,
        );
        let schedule_json = serde_json::to_string(&schedule)
            .map_err(|e| format!("Encode generated migration schedule: {e}"))?;
        tx.execute(
            &format!("UPDATE {RUNS_TABLE} SET schedule_json = ?1 WHERE run_id = ?2"),
            params![schedule_json, run_id],
        )
        .map_err(|e| format!("Save generated migration schedule: {e}"))?;
    }
    validate_schedule_with_policy(&schedule, &target_values, network, timing_policy)?;
    let persisted_signed_schedule_origin = tx
        .query_row(
            &format!(
                "SELECT signed_schedule_origin_height
                 FROM {RUNS_TABLE}
                 WHERE run_id = ?1"
            ),
            params![run_id],
            |row| row.get::<_, Option<u32>>(0),
        )
        .map_err(|e| format!("Read signed migration schedule origin: {e}"))?;
    let scheduled_start_ms = now_ms()?;
    let mut scheduled_pending = Vec::with_capacity(pending_txs.len());
    let mut pending_part_indexes = BTreeSet::new();
    let mut incoming_initial_schedule_origin = None;
    for mut pending in pending_txs {
        if !pending_part_indexes.insert(pending.part_index) {
            return Err("Migration pending part index is duplicated".to_string());
        }
        let entry = schedule_entry_for_pending(&schedule, &target_values, &pending)
            .ok_or("Approved migration schedule no longer matches prepared values")?;
        // Rows created before signed children persisted their absolute
        // schedule used target_height as the compatibility marker. Recover
        // the original shared schedule origin when doing so does not change
        // the already-signed canonical expiry bucket.
        if pending.scheduled_height == pending.target_height
            && pending.expiry_height
                == zip318_canonical_migration_expiry_height(pending.target_height)?
        {
            let legacy_scheduled_height = pending
                .target_height
                .saturating_sub(1)
                .checked_add(entry.block_offset)
                .ok_or("Legacy migration scheduled height overflow")?;
            if pending.expiry_height
                == zip318_canonical_migration_expiry_height(legacy_scheduled_height)?
            {
                pending.scheduled_height = legacy_scheduled_height;
            }
        }
        let schedule_origin = pending
            .scheduled_height
            .checked_sub(entry.block_offset)
            .ok_or("Migration signed schedule starts below zero")?;
        if let Some(persisted_origin) = persisted_signed_schedule_origin {
            if schedule_origin != persisted_origin {
                let matches_retained_replacement = tx
                    .query_row(
                        &format!(
                            "SELECT 1 FROM {SIGNED_CHILD_PCZTS_TABLE}
                             WHERE run_id = ?1 AND child_index = ?2
                               AND scheduled_height = ?3 AND expiry_height = ?4
                               AND value_zatoshi = ?5
                             LIMIT 1"
                        ),
                        params![
                            run_id,
                            pending.part_index,
                            pending.scheduled_height,
                            pending.expiry_height,
                            pending.value_zatoshi,
                        ],
                        |_| Ok(()),
                    )
                    .optional()
                    .map_err(|e| format!("Check retained replacement migration child: {e}"))?
                    .is_some();
                if !matches_retained_replacement {
                    return Err(
                        "Signed migration child no longer matches the immutable signed schedule origin"
                            .to_string(),
                    );
                }
            }
        } else if let Some(incoming_origin) = incoming_initial_schedule_origin {
            if schedule_origin != incoming_origin {
                return Err(
                    "Initial signed migration children do not share one absolute schedule origin"
                        .to_string(),
                );
            }
        } else {
            incoming_initial_schedule_origin = Some(schedule_origin);
        }
        let canonical_expiry = zip318_canonical_migration_expiry_height(pending.scheduled_height)?;
        if pending.expiry_height != canonical_expiry {
            return Err(format!(
                "Migration transaction {} expiry is not canonical for scheduled height {}",
                pending.txid_hex, pending.scheduled_height
            ));
        }
        scheduled_pending.push((pending, entry.block_offset, schedule_origin));
    }
    if persisted_signed_schedule_origin.is_none() {
        if let Some(origin) = incoming_initial_schedule_origin {
            tx.execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                     SET signed_schedule_origin_height = ?1
                     WHERE run_id = ?2 AND signed_schedule_origin_height IS NULL"
                ),
                params![origin, run_id],
            )
            .map_err(|e| format!("Save signed migration schedule origin: {e}"))?;
        }
    }
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;

    for (pending, block_offset, schedule_origin) in scheduled_pending {
        let encrypted_raw_tx = secret_payload::encrypt_payload(
            Zeroizing::new(pending.raw_tx),
            password,
            salt.as_slice(),
        )?;
        let metadata_json = serde_json::to_string(&pending.metadata)
            .map_err(|e| format!("Encode migration pending metadata: {e}"))?;
        let scheduled_at_ms = scheduled_start_ms
            .checked_add(i64::from(block_offset).saturating_mul(1000))
            .ok_or("Migration scheduled time overflow")?;
        let scheduled_height = pending.scheduled_height;

        let inserted = tx
            .execute(
                &format!(
                    "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, part_index, encrypted_raw_tx, target_height, expiry_height,
                  anchor_boundary_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  schedule_start_height, scheduled_height, original_scheduled_height,
                  status, metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,
                         ?13, ?14, ?15, ?15, 'scheduled', ?16)"
                ),
                params![
                    run_id,
                    pending.txid_hex,
                    pending.part_index,
                    encrypted_raw_tx,
                    pending.target_height,
                    pending.expiry_height,
                    pending.anchor_boundary_height,
                    pending.value_zatoshi,
                    pending.fee_zatoshi,
                    pending.selected_note.txid_hex,
                    pending.selected_note.output_index,
                    pending.selected_note.value_zatoshi,
                    scheduled_at_ms,
                    schedule_origin,
                    scheduled_height,
                    metadata_json,
                ],
            )
            .map_err(|e| format!("Insert pending migration tx: {e}"))?;
        if inserted != 1 {
            return Err("Insert pending migration tx affected no rows".to_string());
        }
    }

    let now = now_ms()?;
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = NULL
             WHERE run_id = ?3"
        ),
        params![PHASE_BROADCAST_SCHEDULED, now, run_id],
    )
    .map_err(|e| format!("Mark migration broadcast scheduled: {e}"))?;
    Ok(())
}

fn schedule_entry_for_pending<'a>(
    schedule: &'a [MigrationScheduleEntry],
    target_values: &[u64],
    pending: &PendingMigrationTxInsert,
) -> Option<&'a MigrationScheduleEntry> {
    if schedule.iter().all(|entry| entry.part_index.is_some()) {
        return schedule.iter().find(|entry| {
            entry.part_index == Some(pending.part_index)
                && entry.value_zatoshi == pending.value_zatoshi
        });
    }

    // Legacy schedules did not persist part indexes. Equal-value parts are
    // mapped by their stable rank in the original plan so incremental proof
    // persistence cannot reuse the same schedule entry.
    let part_index = usize::try_from(pending.part_index).ok()?;
    if target_values.get(part_index) != Some(&pending.value_zatoshi) {
        return None;
    }
    let equal_value_rank = target_values
        .iter()
        .take(part_index)
        .filter(|value| **value == pending.value_zatoshi)
        .count();
    schedule
        .iter()
        .filter(|entry| entry.value_zatoshi == pending.value_zatoshi)
        .nth(equal_value_rank)
}

#[derive(Clone, Copy)]
enum SignedChildInsertMode {
    Initial,
    Replacement,
}

fn insert_signed_child_pczts_with_tx(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    signed_children: Vec<SignedMigrationPcztInsert>,
    password: &[u8],
    salt_base64: &str,
    mode: SignedChildInsertMode,
) -> Result<(), String> {
    if signed_children.is_empty() {
        return Ok(());
    }

    let (schedule_json, target_values_json, persisted_signed_schedule_origin, recovery_origin) = tx
        .query_row(
            &format!(
                "SELECT schedule_json, target_values_json, signed_schedule_origin_height,
                        recovery_schedule_origin_height
                 FROM {RUNS_TABLE} WHERE run_id = ?1"
            ),
            params![run_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<u32>>(2)?,
                    row.get::<_, Option<u32>>(3)?,
                ))
            },
        )
        .map_err(|e| format!("Read signed migration schedule: {e}"))?;
    let schedule: Vec<MigrationScheduleEntry> = serde_json::from_str(&schedule_json)
        .map_err(|e| format!("Decode signed migration schedule: {e}"))?;
    let target_values: Vec<u64> = serde_json::from_str(&target_values_json)
        .map_err(|e| format!("Decode signed migration target values: {e}"))?;
    let mut signed_schedule_origin = match mode {
        SignedChildInsertMode::Initial => persisted_signed_schedule_origin,
        SignedChildInsertMode::Replacement => None,
    };
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration PCZT salt")?;
    for child in signed_children {
        let canonical_expiry = zip318_canonical_migration_expiry_height(child.scheduled_height)?;
        if child.expiry_height != canonical_expiry {
            return Err(format!(
                "Signed migration child {} expiry {} is not canonical for scheduled height {}",
                child.message_id, child.expiry_height, child.scheduled_height
            ));
        }
        if !schedule.is_empty() {
            let block_offset = schedule_block_offset_for_part(
                &schedule,
                &target_values,
                child.child_index,
                child.value_zatoshi,
            )
            .ok_or("Approved migration schedule is missing a signed child")?;
            match mode {
                SignedChildInsertMode::Initial => {
                    let child_schedule_origin = child
                        .scheduled_height
                        .checked_sub(block_offset)
                        .ok_or("Signed migration schedule starts below zero")?;
                    if let Some(origin) = signed_schedule_origin {
                        if origin != child_schedule_origin {
                            return Err(
                                "Signed migration children do not share one absolute schedule origin"
                                    .to_string(),
                            );
                        }
                    } else {
                        signed_schedule_origin = Some(child_schedule_origin);
                    }
                }
                // Rebuilt children carry fresh offsets anchored at the run's
                // recovery-schedule generation (see
                // `ensure_rebuild_schedule_generation`), so a shared origin
                // derived from original offsets no longer holds; require the
                // generation origin plus a non-negative rebuild offset.
                SignedChildInsertMode::Replacement => {
                    let child_origin = child.target_height.saturating_sub(1);
                    if let Some(origin) = recovery_origin {
                        if child_origin != origin {
                            return Err(
                                "Rebuilt migration children must share the recovery schedule origin"
                                    .to_string(),
                            );
                        }
                    }
                    child
                        .scheduled_height
                        .checked_sub(child_origin)
                        .ok_or("Signed migration schedule starts below zero")?;
                }
            }
        }
        let encrypted_base_pczt = secret_payload::encrypt_payload(
            Zeroizing::new(child.base_pczt),
            password,
            salt.as_slice(),
        )?;
        let encrypted_compact_sigs = secret_payload::encrypt_payload(
            Zeroizing::new(crate::wallet::keystone::encode_compact_action_sigs(
                &child.sigs,
            )?),
            password,
            salt.as_slice(),
        )?;
        let selected_note_json = serde_json::to_string(&child.selected_note)
            .map_err(|e| format!("Encode migration signed PCZT note: {e}"))?;
        let metadata_json = serde_json::to_string(&child.metadata)
            .map_err(|e| format!("Encode migration signed PCZT metadata: {e}"))?;

        tx.execute(
            &format!(
                "INSERT OR REPLACE INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_compact_sigs, target_height, expiry_height, scheduled_height,
                  anchor_boundary_height, value_zatoshi, fee_zatoshi, selected_note_json,
                  metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)"
            ),
            params![
                run_id,
                child.message_id,
                child.child_index,
                encrypted_base_pczt,
                encrypted_compact_sigs,
                child.target_height,
                child.expiry_height,
                child.scheduled_height,
                child.anchor_boundary_height,
                child.value_zatoshi,
                child.fee_zatoshi,
                selected_note_json,
                metadata_json,
            ],
        )
        .map_err(|e| format!("Insert signed migration PCZT: {e}"))?;
    }
    if matches!(mode, SignedChildInsertMode::Initial) && persisted_signed_schedule_origin.is_none()
    {
        if let Some(origin) = signed_schedule_origin {
            tx.execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                     SET signed_schedule_origin_height = ?1
                     WHERE run_id = ?2 AND signed_schedule_origin_height IS NULL"
                ),
                params![origin, run_id],
            )
            .map_err(|e| format!("Save signed migration schedule origin: {e}"))?;
        }
    }
    Ok(())
}

pub(crate) fn persist_signed_child_pczts_for_run(
    db_path: &str,
    run_id: &str,
    signed_children: Vec<SignedMigrationPcztInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    if signed_children.is_empty() {
        return Err("Keystone migration returned no signed children".to_string());
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin signed migration handoff: {e}"))?;
    insert_signed_child_pczts_with_tx(
        &tx,
        run_id,
        signed_children,
        password,
        salt_base64,
        SignedChildInsertMode::Initial,
    )?;
    let updated = tx
        .execute(
            &format!(
                "UPDATE {RUNS_TABLE}
             SET updated_at_ms = ?1, last_error = NULL
             WHERE run_id = ?2 AND phase = ?3"
            ),
            params![now_ms()?, run_id, PHASE_READY_TO_MIGRATE],
        )
        .map_err(|e| format!("Update presigned migration run: {e}"))?;
    if updated != 1 {
        return Err("Migration run is no longer ready for Keystone signatures".to_string());
    }
    tx.commit()
        .map_err(|e| format!("Commit signed migration handoff: {e}"))
}

pub(crate) fn signed_child_pczts_for_run(
    db_path: &str,
    run_id: &str,
    password: &[u8],
    salt_base64: &str,
) -> Result<Vec<SignedMigrationPczt>, String> {
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration PCZT salt")?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT c.message_id, c.child_index, c.encrypted_base_pczt,
                    encrypted_compact_sigs, target_height, expiry_height, scheduled_height,
                    anchor_boundary_height, value_zatoshi, fee_zatoshi,
                    selected_note_json, metadata_json
             FROM {SIGNED_CHILD_PCZTS_TABLE} c
             WHERE c.run_id = ?1
               AND NOT EXISTS (
                   SELECT 1 FROM {PENDING_TXS_TABLE} p
                   WHERE p.run_id = c.run_id AND p.part_index = c.child_index
               )
             ORDER BY c.child_index ASC, c.message_id ASC"
        ))
        .map_err(|e| format!("Prepare signed migration PCZT query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, u32>(5)?,
                row.get::<_, Option<u32>>(6)?,
                row.get::<_, Option<u32>>(7)?,
                row.get::<_, u64>(8)?,
                row.get::<_, u64>(9)?,
                row.get::<_, String>(10)?,
                row.get::<_, String>(11)?,
            ))
        })
        .map_err(|e| format!("Query signed migration PCZTs: {e}"))?;

    let mut signed = Vec::new();
    for row in rows {
        let (
            message_id,
            child_index,
            encrypted_base_pczt,
            encrypted_compact_sigs,
            target_height,
            expiry_height,
            scheduled_height,
            anchor_boundary_height,
            value_zatoshi,
            fee_zatoshi,
            selected_note_json,
            metadata_json,
        ) = row.map_err(|e| format!("Read signed migration PCZT: {e}"))?;
        let scheduled_height = scheduled_height.ok_or_else(|| {
            format!("Signed migration child {message_id} requires fresh signatures")
        })?;
        if expiry_height != zip318_canonical_migration_expiry_height(scheduled_height)? {
            return Err(format!(
                "Signed migration child {message_id} expiry is not canonical for scheduled height {scheduled_height}"
            ));
        }
        let base_pczt = secret_payload::decrypt_payload(
            encrypted_base_pczt.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        let sigs_blob = secret_payload::decrypt_payload(
            encrypted_compact_sigs.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        let sigs = crate::wallet::keystone::decode_compact_action_sigs(sigs_blob.as_slice())?;
        let selected_note = serde_json::from_str::<PreparedOrchardNoteRef>(&selected_note_json)
            .map_err(|e| format!("Decode signed migration PCZT note: {e}"))?;
        let metadata = serde_json::from_str::<PendingMigrationTxMetadata>(&metadata_json)
            .map_err(|e| format!("Decode signed migration PCZT metadata: {e}"))?;

        signed.push(SignedMigrationPczt {
            message_id,
            child_index,
            base_pczt: base_pczt.to_vec(),
            sigs,
            target_height,
            anchor_boundary_height,
            expiry_height,
            scheduled_height,
            value_zatoshi,
            fee_zatoshi,
            selected_note,
            metadata,
        });
    }

    Ok(signed)
}

pub(crate) fn signed_child_proof_candidates_for_run(
    db_path: &str,
    run_id: &str,
) -> Result<Vec<SignedChildProofCandidate>, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT c.selected_note_json, c.anchor_boundary_height
             FROM {SIGNED_CHILD_PCZTS_TABLE} c
             WHERE c.run_id = ?1
               AND NOT EXISTS (
                   SELECT 1 FROM {PENDING_TXS_TABLE} p
                   WHERE p.run_id = c.run_id AND p.part_index = c.child_index
               )
             ORDER BY c.child_index ASC, c.message_id ASC"
        ))
        .map_err(|e| format!("Prepare signed migration proof candidate query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, Option<u32>>(1)?))
        })
        .map_err(|e| format!("Query signed migration proof candidates: {e}"))?;

    let mut candidates = Vec::new();
    for row in rows {
        let (selected_note_json, anchor_boundary_height) =
            row.map_err(|e| format!("Read signed migration proof candidate: {e}"))?;
        let selected_note = serde_json::from_str::<PreparedOrchardNoteRef>(&selected_note_json)
            .map_err(|e| format!("Decode signed migration proof candidate note: {e}"))?;
        candidates.push(SignedChildProofCandidate {
            selected_note,
            anchor_boundary_height,
        });
    }
    Ok(candidates)
}

pub(crate) fn signed_child_message_ids_by_part(
    db_path: &str,
    run_id: &str,
) -> Result<BTreeMap<u32, String>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT child_index, message_id
             FROM {SIGNED_CHILD_PCZTS_TABLE}
             WHERE run_id = ?1
             ORDER BY child_index ASC, message_id ASC"
        ))
        .map_err(|e| format!("Prepare signed migration child identities: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, u32>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|e| format!("Query signed migration child identities: {e}"))?;
    let mut identities = BTreeMap::new();
    for row in rows {
        let (part_index, message_id) =
            row.map_err(|e| format!("Read signed migration child identity: {e}"))?;
        if identities.insert(part_index, message_id).is_some() {
            return Err(format!(
                "Migration part {part_index} has duplicate retained signature records"
            ));
        }
    }
    Ok(identities)
}

pub(crate) fn signed_child_pczt_count(db_path: &str, run_id: &str) -> Result<u32, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    unpromoted_signed_child_pczt_count_with_conn(&conn, run_id)
}

fn unpromoted_signed_child_pczt_count_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<u32, String> {
    u32::try_from(unpromoted_signed_child_note_outpoints_with_conn(conn, run_id)?.len())
        .map_err(|_| "Signed migration PCZT count overflow".to_string())
}

fn migration_child_materialization_exists_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<bool, String> {
    conn.query_row(
        &format!(
            "SELECT EXISTS(
                SELECT 1 FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1
                UNION ALL
                SELECT 1 FROM {PENDING_TXS_TABLE} WHERE run_id = ?1
             )"
        ),
        params![run_id],
        |row| row.get::<_, bool>(0),
    )
    .map_err(|e| format!("Check migration child materialization: {e}"))
}

fn unpromoted_signed_child_note_outpoints_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<Vec<(String, u32)>, String> {
    let pending = pending_migration_note_outpoints_with_conn(&conn, run_id)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT selected_note_json
             FROM {SIGNED_CHILD_PCZTS_TABLE}
             WHERE run_id = ?1"
        ))
        .map_err(|e| format!("Prepare unpromoted signed migration PCZT query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Query unpromoted signed migration PCZTs: {e}"))?;
    let mut unpromoted = Vec::new();
    for row in rows {
        let selected_note_json =
            row.map_err(|e| format!("Read unpromoted signed migration PCZT: {e}"))?;
        let note = serde_json::from_str::<PreparedOrchardNoteRef>(&selected_note_json)
            .map_err(|e| format!("Decode unpromoted signed migration PCZT note: {e}"))?;
        let outpoint = (note.txid_hex.to_ascii_lowercase(), note.output_index);
        if !pending.contains(&outpoint) {
            unpromoted.push(outpoint);
        }
    }
    Ok(unpromoted)
}

pub(crate) fn pending_migration_note_outpoints(
    db_path: &str,
    run_id: &str,
) -> Result<BTreeSet<(String, u32)>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    pending_migration_note_outpoints_with_conn(&conn, run_id)
}

fn pending_migration_note_outpoints_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<BTreeSet<(String, u32)>, String> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT lower(selected_note_txid), selected_note_output_index
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1"
        ))
        .map_err(|e| format!("Prepare pending migration note query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .map_err(|e| format!("Query pending migration notes: {e}"))?;
    rows.collect::<Result<BTreeSet<_>, _>>()
        .map_err(|e| format!("Read pending migration notes: {e}"))
}

/// Restores the child-migration side of a staged run after one or more
/// denomination transactions leave the active chain.
///
/// Compact signatures remain in `SIGNED_CHILD_PCZTS_TABLE`; only the child
/// transactions funded by affected outputs are removed so they can be proved
/// again once those same effecting-data transaction IDs are mined on the new
/// chain. Independent children retain their schedule and confirmation state.
pub(crate) fn reset_migration_children_for_reorged_denominations(
    db_path: &str,
    run_id: &str,
    denomination_txids: &BTreeSet<String>,
) -> Result<bool, String> {
    if denomination_txids.is_empty() {
        return Ok(false);
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin denomination reorg child reset: {e}"))?;
    if migration_phase_releases_wallet_locks(
        &tx.query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration phase before denomination reorg reset: {e}"))?,
    ) {
        return Ok(false);
    }
    let mut reset_any = false;
    for denomination_txid in denomination_txids {
        let denomination_txid = denomination_txid.to_ascii_lowercase();
        let mut child_stmt = tx
            .prepare_cached(&format!(
                "SELECT txid_hex, selected_note_output_index
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND lower(selected_note_txid) = ?2"
            ))
            .map_err(|e| format!("Prepare reorged migration child query: {e}"))?;
        let child_rows = child_stmt
            .query_map(params![run_id, denomination_txid], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?))
            })
            .map_err(|e| format!("Query reorged migration children: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read reorged migration children: {e}"))?;
        drop(child_stmt);

        let mut included_outputs = BTreeSet::new();
        for (child_txid, output_index) in child_rows {
            if local_denomination_chain_identity(&tx, &child_txid)?.is_some() {
                included_outputs.insert(output_index);
                continue;
            }
            tx.execute(
                &format!(
                    "DELETE FROM {PENDING_TXS_TABLE}
                     WHERE run_id = ?1 AND txid_hex = ?2"
                ),
                params![run_id, child_txid],
            )
            .map_err(|e| format!("Clear reorged pending migration child: {e}"))?;
            reset_any = true;
        }

        let mut note_stmt = tx
            .prepare_cached(&format!(
                "SELECT output_index
                 FROM {PREPARED_NOTES_TABLE}
                 WHERE run_id = ?1 AND lower(txid_hex) = ?2"
            ))
            .map_err(|e| format!("Prepare reorged migration note query: {e}"))?;
        let output_indices = note_stmt
            .query_map(params![run_id, denomination_txid], |row| {
                row.get::<_, u32>(0)
            })
            .map_err(|e| format!("Query reorged migration notes: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read reorged migration notes: {e}"))?;
        drop(note_stmt);
        for output_index in output_indices {
            if included_outputs.contains(&output_index) {
                continue;
            }
            tx.execute(
                &format!(
                    "UPDATE {PREPARED_NOTES_TABLE}
                     SET nullifier_hex = NULL, lock_state = 'locked'
                     WHERE run_id = ?1 AND lower(txid_hex) = ?2
                       AND output_index = ?3"
                ),
                params![run_id, denomination_txid, output_index],
            )
            .map_err(|e| format!("Reset reorged prepared migration note: {e}"))?;
            reset_any = true;
        }
    }
    if reset_any {
        let now = now_ms()?;
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL,
                     proof_retry_height = NULL
                 WHERE run_id = ?3
                   AND phase NOT IN (
                       '{PHASE_COMPLETE}',
                       '{PHASE_FAILED_TERMINAL}',
                       '{PHASE_ABANDONED}'
                   )"
            ),
            params![PHASE_WAITING_DENOM_CONFIRMATIONS, now, run_id],
        )
        .map_err(|e| format!("Reset migration run after denomination reorg: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit denomination reorg child reset: {e}"))?;
    Ok(reset_any)
}

/// Reconciles the plaintext denomination graph against the wallet's scanned
/// canonical chain. This needs no seed, PCZT, or encryption password, so the
/// normal status path can reconcile a reorg even after every child has been
/// broadcast.
/// A pending stage discovered on-chain and its remaining peers are updated in
/// one transaction. The submission timing was not persisted, so a spaced run
/// conservatively restarts its peer delays from the current chain tip.
pub(crate) fn reconcile_denomination_stage_chain_state(
    db_path: &str,
    run_id: &str,
) -> Result<(), String> {
    reconcile_denomination_stage_chain_state_with_rng(db_path, run_id, None, &mut OsRng)
}

fn reconcile_denomination_stage_chain_state_with_rng<R: RngCore + CryptoRng + ?Sized>(
    db_path: &str,
    run_id: &str,
    recovery_chain_tip_height: Option<u32>,
    rng: &mut R,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let records = denomination_stage_chain_records(&conn, run_id)?;
    if records.is_empty() {
        return Ok(());
    }

    let mut current = BTreeMap::new();
    for record in &records {
        current.insert(
            record.expected_txid_hex.to_ascii_lowercase(),
            local_denomination_chain_identity(&conn, &record.expected_txid_hex)?,
        );
    }

    let stored_matches = |record: &DenominationStageChainRecord,
                          identity: &LocalTransactionChainIdentity| {
        record.confirmed_mined_height == Some(identity.mined_height)
            && record.confirmed_block_hash.as_deref() == Some(identity.block_hash.as_slice())
    };
    let mut affected = BTreeSet::new();
    let mut invalid_stages = BTreeSet::new();
    let mut identities_to_record = BTreeMap::new();
    let mut recovered_pending_txids = BTreeSet::new();

    for record in &records {
        let txid = record.expected_txid_hex.to_ascii_lowercase();
        match (record.status, current.get(&txid).and_then(Option::as_ref)) {
            (DenominationStageStatus::AwaitingInputs, Some(identity)) => {
                identities_to_record.insert(txid, identity.clone());
            }
            (DenominationStageStatus::Pending, Some(identity)) => {
                recovered_pending_txids.insert(txid.clone());
                identities_to_record.insert(txid, identity.clone());
            }
            (DenominationStageStatus::Broadcasted, Some(identity)) => {
                identities_to_record.insert(txid, identity.clone());
            }
            (DenominationStageStatus::Confirmed, None) => {
                affected.insert(txid.clone());
                invalid_stages.insert(txid);
            }
            (DenominationStageStatus::Confirmed, Some(identity))
                if !stored_matches(record, identity) =>
            {
                affected.insert(txid.clone());
                identities_to_record.insert(txid, identity.clone());
            }
            _ => {}
        }
    }

    // Propagate through normalized inputs. A dependent transaction that is
    // itself on the canonical chain is valid and retained; an off-chain one
    // must be re-anchored and re-proved.
    loop {
        let before = affected.len();
        for record in &records {
            let txid = record.expected_txid_hex.to_ascii_lowercase();
            if record
                .parent_txids
                .iter()
                .any(|parent| affected.contains(parent))
            {
                affected.insert(txid.clone());
                if current.get(&txid).and_then(Option::as_ref).is_none() {
                    invalid_stages.insert(txid);
                }
            }
        }
        if affected.len() == before {
            break;
        }
    }
    let recovery_network = if recovered_pending_txids.is_empty()
        || preparation_timing_policy_for_run_with_conn(&conn, run_id)?
            == PreparationTimingPolicy::Immediate
    {
        None
    } else {
        let network = conn
            .query_row(
                &format!("SELECT network FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get::<_, String>(0),
            )
            .map_err(|e| format!("Read recovered denomination run network: {e}"))?;
        let network = WalletNetwork::from_str(&network)
            .ok_or_else(|| format!("Unsupported migration run network: {network}"))?;
        Some(network)
    };
    drop(conn);

    let recovery_context = if let Some(network) = recovery_network {
        let chain_tip_height = if let Some(height) = recovery_chain_tip_height {
            height
        } else {
            u32::try_from(super::get_sync_progress(db_path, network)?.chain_tip_height)
                .map_err(|_| "Migration chain tip exceeds u32".to_string())?
        };
        Some((network, chain_tip_height))
    } else {
        None
    };

    if !affected.is_empty() {
        // Child cleanup comes first. If the process stops before stage state is
        // updated, the unchanged identity causes this idempotent cleanup to run
        // again on the next status call.
        reset_migration_children_for_reorged_denominations(db_path, run_id, &affected)?;
    }

    if !invalid_stages.is_empty() || !identities_to_record.is_empty() {
        // This reconciliation records canonical-chain identities and commits
        // stage resets, so it must tolerate the foreground scanner finishing
        // a concurrent wallet write. The read timeout can expire first on
        // mobile and strand an otherwise completed preparation run.
        let conn = open_wallet_raw_conn_with_timeout(db_path, WALLET_DB_BUSY_TIMEOUT)?;
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("Begin denomination chain-state reconciliation: {e}"))?;
        if migration_phase_releases_wallet_locks(
            &tx.query_row(
                &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get::<_, String>(0),
            )
            .map_err(|e| format!("Read migration phase before chain-state reconciliation: {e}"))?,
        ) {
            return Ok(());
        }
        let mut recovered_pending_stage = false;
        for txid in &recovered_pending_txids {
            let still_pending = tx
                .query_row(
                    &format!(
                        "SELECT status = 'pending' FROM {STAGES_TABLE}
                         WHERE run_id = ?1 AND expected_txid_hex = ?2"
                    ),
                    params![run_id, txid],
                    |row| row.get::<_, bool>(0),
                )
                .map_err(|e| format!("Check recovered denomination stage state: {e}"))?;
            recovered_pending_stage |= still_pending;
        }
        for txid in &invalid_stages {
            reset_denomination_stage_exact(&tx, run_id, txid)?;
        }
        for (txid, identity) in identities_to_record {
            if invalid_stages.contains(&txid) {
                continue;
            }
            replace_denomination_stage_confirmation_identity(
                &tx,
                run_id,
                &txid,
                identity.mined_height,
                &identity.block_hash,
            )?;
        }
        if let (true, Some((network, chain_tip_height))) =
            (recovered_pending_stage, recovery_context)
        {
            let rerandomized = rerandomize_remaining_preparation_broadcast_heights(
                &tx,
                run_id,
                network,
                chain_tip_height,
                rng,
            )?;
            if rerandomized > 0 {
                log::info!(
                    "migration: re-randomized {rerandomized} preparation stage(s) after recovering an on-chain pending stage"
                );
            }
        }
        tx.commit()
            .map_err(|e| format!("Commit denomination chain-state reconciliation: {e}"))?;
    }

    if !affected.is_empty() {
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        let now = now_ms()?;
        let transitioned = conn
            .execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                     SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                     WHERE run_id = ?3
                       AND phase NOT IN (
                           '{PHASE_COMPLETE}',
                           '{PHASE_FAILED_TERMINAL}',
                           '{PHASE_ABANDONED}'
                       )"
                ),
                params![PHASE_WAITING_DENOM_CONFIRMATIONS, now, run_id],
            )
            .map_err(|e| format!("Mark denomination reorg waiting for confirmations: {e}"))?;
        if transitioned == 1 {
            log::warn!(
                "migration: reconciled {} denomination transaction(s) after a chain change",
                affected.len()
            );
        }
    }
    Ok(())
}

pub(crate) fn export_scheduled_migration_outbox(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    password: &[u8],
    salt_base64: &str,
) -> Result<Option<MigrationOutboxBatch>, String> {
    if let Ok(progress) = super::get_sync_progress(db_path, network) {
        if let Ok(chain_tip_height) = u32::try_from(progress.chain_tip_height) {
            if let Some(run) = active_migration_run(db_path, account_uuid, network)? {
                mark_due_parts_with_noncanonical_broadcast_height_for_resign(
                    db_path,
                    &run.run_id,
                    chain_tip_height,
                )?;
            }
        }
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let Some(run) = active_run(&conn, account_uuid, network)? else {
        return Ok(None);
    };
    let timing_policy = timing_policy_for_run_with_conn(&conn, &run.run_id, network)?;
    let (timing_mean_blocks, timing_max_blocks) =
        schedule_parameters_with_policy(network, timing_policy);
    let unmaterialized_count = unpromoted_signed_child_pczt_count_with_conn(&conn, &run.run_id)?;
    let next_proof_height = if unmaterialized_count == 0 {
        None
    } else {
        let persisted = conn
            .query_row(
                &format!("SELECT proof_retry_height FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run.run_id],
                |row| row.get::<_, Option<u32>>(0),
            )
            .map_err(|e| format!("Read migration outbox proof retry height: {e}"))?;
        prepared_notes_proof_ready_height(db_path, &run.run_id, network, timing_policy)?
            .map(|ready_height| persisted.unwrap_or(ready_height).max(ready_height))
    };
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT part_index, txid_hex, encrypted_raw_tx,
                    anchor_boundary_height, scheduled_height,
                    schedule_start_height, expiry_height
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'scheduled'
             ORDER BY scheduled_height ASC, part_index ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration outbox export: {e}"))?;
    let rows = stmt
        .query_map(params![run.run_id], |row| {
            Ok((
                row.get::<_, Option<u32>>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<u32>>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, Option<u32>>(5)?,
                row.get::<_, u32>(6)?,
            ))
        })
        .map_err(|e| format!("Query migration outbox export: {e}"))?;

    let mut items = Vec::new();
    for row in rows {
        let (
            part_index,
            txid_hex,
            encrypted_raw_tx,
            anchor_boundary_height,
            scheduled_height,
            schedule_start_height,
            expiry_height,
        ) = row.map_err(|e| format!("Read migration outbox export: {e}"))?;
        let part_index = part_index.ok_or_else(|| {
            format!("Migration outbox transaction {txid_hex} is missing its part index")
        })?;
        let anchor_boundary_height = anchor_boundary_height.ok_or_else(|| {
            format!("Migration outbox transaction {txid_hex} is missing its anchor boundary")
        })?;
        let schedule_start_height = schedule_start_height.ok_or_else(|| {
            format!("Migration outbox transaction {txid_hex} is missing its schedule origin")
        })?;
        if scheduled_height >= expiry_height {
            return Err(format!(
                "Migration outbox transaction {txid_hex} is scheduled at or after expiry"
            ));
        }
        let canonical_expiry = zip318_canonical_migration_expiry_height(scheduled_height)?;
        if expiry_height != canonical_expiry {
            return Err(format!(
                "Migration outbox transaction {txid_hex} expiry is not canonical for scheduled height {scheduled_height}"
            ));
        }
        let raw_tx = secret_payload::decrypt_payload(
            encrypted_raw_tx.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        let item_id = txid_hex.to_ascii_lowercase();
        items.push(MigrationOutboxItem {
            item_id,
            part_index,
            txid_hex,
            raw_tx: raw_tx.to_vec(),
            anchor_boundary_height,
            scheduled_height,
            schedule_start_height,
            expiry_height,
        });
    }
    if items.is_empty() && next_proof_height.is_none() {
        return Ok(None);
    }
    Ok(Some(MigrationOutboxBatch {
        run_id: run.run_id,
        timing_mean_blocks,
        timing_max_blocks,
        next_proof_height,
        items,
    }))
}

fn migration_outbox_run_phase_with_conn(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
    run_id: &str,
) -> Result<String, String> {
    conn.query_row(
        &format!(
            "SELECT phase FROM {RUNS_TABLE}
             WHERE run_id = ?1 AND account_uuid = ?2 AND network = ?3"
        ),
        params![run_id, account_uuid, network_name(network)],
        |row| row.get(0),
    )
    .optional()
    .map_err(|e| format!("Read migration outbox run scope: {e}"))?
    .ok_or_else(|| "Migration outbox receipt does not match this account and run".to_string())
}

pub(crate) fn migration_outbox_tx_state(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    run_id: &str,
    txid_hex: &str,
) -> Result<MigrationOutboxTxState, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let run_phase = migration_outbox_run_phase_with_conn(&conn, account_uuid, network, run_id)?;
    let (status, expiry_height) = conn
        .query_row(
            &format!(
                "SELECT status, expiry_height FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND lower(txid_hex) = lower(?2)"
            ),
            params![run_id, txid_hex],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(|e| format!("Read migration outbox receipt transaction: {e}"))?
        .ok_or_else(|| {
            "Migration outbox receipt transaction was not found in this run".to_string()
        })?;
    Ok(MigrationOutboxTxState {
        run_phase,
        status,
        expiry_height,
    })
}

pub(crate) fn unbroadcast_migration_recovery_candidates(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    expected_run_id: &str,
) -> Result<Vec<UnbroadcastMigrationRecoveryCandidate>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let run = active_run(&conn, account_uuid, network)?
        .ok_or("No active migration run is available for recovery")?;
    if run.run_id != expected_run_id {
        return Err(format!(
            "Migration recovery run changed: expected {expected_run_id}, got {}",
            run.run_id
        ));
    }

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, status, scheduled_height
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status IN ('scheduled', 'broadcasted')
             ORDER BY part_index ASC, scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration recovery candidates: {e}"))?;
    let rows = stmt
        .query_map(params![expected_run_id], |row| {
            Ok(UnbroadcastMigrationRecoveryCandidate {
                txid_hex: row.get(0)?,
                status: row.get(1)?,
                scheduled_height: row.get(2)?,
            })
        })
        .map_err(|e| format!("Query migration recovery candidates: {e}"))?;
    let candidates = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration recovery candidate: {e}"))?;
    if candidates.is_empty() {
        return Err("Migration recovery has no unconfirmed transactions".to_string());
    }
    Ok(candidates)
}

/// Promotes pending migration rows to `confirmed` when the wallet already has
/// local chain identity for their txids (and demotes orphaned `confirmed` rows
/// after a reorg). Call before due selection. Expiry and noncanonical
/// broadcast-height recovery call [`reconcile_run_confirmations`] inside their
/// own IMMEDIATE write transaction instead of this helper, so identity checks
/// and `needs_resign` updates stay atomic against concurrent sync writers.
pub(crate) fn reconcile_run_pending_confirmations(
    db_path: &str,
    run_id: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    reconcile_run_confirmations(&conn, run_id)
}

pub(crate) fn scheduled_migration_stop_candidates(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    expected_run_id: &str,
) -> Result<Vec<MigrationStopCandidate>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let (stored_account_uuid, stored_network, phase) = conn
        .query_row(
            &format!(
                "SELECT account_uuid, network, phase
                 FROM {RUNS_TABLE}
                 WHERE run_id = ?1"
            ),
            params![expected_run_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read migration run before stop reconciliation: {e}"))?
        .ok_or_else(|| format!("Migration run {expected_run_id} was not found"))?;
    if stored_account_uuid != account_uuid || stored_network != network_name(network) {
        return Err("Migration run does not belong to this wallet account".to_string());
    }
    if phase == PHASE_ABANDONED {
        return Ok(Vec::new());
    }
    if matches!(phase.as_str(), PHASE_COMPLETE | PHASE_FAILED_TERMINAL) {
        return Err(format!("Migration run is already terminal ({phase})"));
    }

    // Include `broadcasted` rows that still lack local `transactions.raw`:
    // accept-then-store-fail promotes out of `scheduled` so due selection
    // cannot HOL-block, but stop must still store them before unlocking notes.
    let mut pending_stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, scheduled_height, expiry_height,
                    broadcast_attempted, status
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status IN ('scheduled', 'broadcasted')
             ORDER BY part_index ASC, scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare scheduled migration stop candidates: {e}"))?;
    let pending_rows = pending_stmt
        .query_map(params![expected_run_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, u32>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, String>(4)?,
            ))
        })
        .map_err(|e| format!("Query scheduled migration stop candidates: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read scheduled migration stop candidate: {e}"))?;
    let mut candidates = Vec::new();
    for (txid_hex, broadcast_height, expiry_height, attempt_state, status) in pending_rows {
        let attempt_state = if status == "broadcasted" {
            // Network already accepted: always reconcile before abandon unlocks.
            if local_transaction_raw(&conn, &txid_hex)?.is_some() {
                continue;
            }
            MigrationBroadcastAttemptState::Attempted
        } else {
            MigrationBroadcastAttemptState::from_db(attempt_state)?
        };
        candidates.push(MigrationStopCandidate {
            kind: MigrationStopCandidateKind::MigrationTransaction,
            txid_hex,
            broadcast_height,
            expiry_height,
            attempt_state,
        });
    }
    drop(pending_stmt);

    let mut stage_stmt = conn
        .prepare_cached(&format!(
            "SELECT expected_txid_hex,
                    max(scheduled_height, coalesce(broadcast_not_before_height, 0)),
                    expiry_height, broadcast_attempted
             FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND status = 'pending'
             ORDER BY stage_index ASC"
        ))
        .map_err(|e| format!("Prepare denomination stop candidates: {e}"))?;
    let stage_rows = stage_stmt
        .query_map(params![expected_run_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, u32>(2)?,
                row.get::<_, i64>(3)?,
            ))
        })
        .map_err(|e| format!("Query denomination stop candidates: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read denomination stop candidate: {e}"))?;
    candidates.extend(
        stage_rows
            .into_iter()
            .map(
                |(txid_hex, broadcast_height, expiry_height, attempt_state)| {
                    Ok(MigrationStopCandidate {
                        kind: MigrationStopCandidateKind::DenominationStage,
                        txid_hex,
                        broadcast_height,
                        expiry_height,
                        attempt_state: MigrationBroadcastAttemptState::from_db(attempt_state)?,
                    })
                },
            )
            .collect::<Result<Vec<_>, String>>()?,
    );
    Ok(candidates)
}

pub(crate) fn mark_pending_broadcast_attempted(
    db_path: &str,
    run_id: &str,
    txid_hex: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {PENDING_TXS_TABLE}
                 SET broadcast_attempted = 1
                 WHERE run_id = ?1 AND txid_hex = ?2 AND status = 'scheduled'"
            ),
            params![run_id, txid_hex],
        )
        .map_err(|e| format!("Record migration broadcast attempt: {e}"))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(format!(
            "Migration transaction {txid_hex} is no longer scheduled"
        ))
    }
}

pub(crate) fn mark_denomination_broadcast_attempted(
    db_path: &str,
    run_id: &str,
    txid_hex: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET broadcast_attempted = 1
                 WHERE run_id = ?1 AND expected_txid_hex = ?2
                   AND status = 'pending'"
            ),
            params![run_id, txid_hex],
        )
        .map_err(|e| format!("Record denomination broadcast attempt: {e}"))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(format!(
            "Denomination transaction {txid_hex} is no longer pending"
        ))
    }
}

pub(crate) fn clear_denomination_broadcast_attempted(
    db_path: &str,
    run_id: &str,
    txid_hex: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.execute(
        &format!(
            "UPDATE {STAGES_TABLE}
             SET broadcast_attempted = 0
             WHERE run_id = ?1 AND expected_txid_hex = ?2
               AND status = 'pending'"
        ),
        params![run_id, txid_hex],
    )
    .map_err(|e| format!("Clear rejected denomination broadcast attempt: {e}"))?;
    Ok(())
}

pub(crate) fn due_pending_txs(
    db_path: &str,
    run_id: &str,
    chain_tip_height: u32,
    password: &[u8],
    salt_base64: &str,
) -> Result<Vec<DuePendingMigrationTx>, String> {
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;
    // Reconcile before selecting so locally mined parts are no longer
    // `scheduled` and cannot win the earliest-due LIMIT 1 forever.
    reconcile_run_pending_confirmations(db_path, run_id)?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, encrypted_raw_tx, scheduled_height, expiry_height
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'scheduled' AND scheduled_height <= ?2
             ORDER BY scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare due migration tx query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, chain_tip_height], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u32>(2)?,
                row.get::<_, u32>(3)?,
            ))
        })
        .map_err(|e| format!("Query due migration txs: {e}"))?;

    let mut due = Vec::new();
    for row in rows {
        let (txid_hex, encrypted_raw_tx, scheduled_height, expiry_height) =
            row.map_err(|e| format!("Read due migration tx: {e}"))?;
        // Defense in depth: never return a part that is already mined locally,
        // even if status reconciliation raced or was skipped by a caller.
        if local_denomination_chain_identity(&conn, &txid_hex)?.is_some() {
            continue;
        }
        if expiry_height != zip318_canonical_migration_expiry_height(scheduled_height)? {
            return Err(format!(
                "Due migration transaction {txid_hex} expiry is not canonical for scheduled height {scheduled_height}"
            ));
        }
        let raw_tx = secret_payload::decrypt_payload(
            encrypted_raw_tx.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        due.push(DuePendingMigrationTx {
            txid_hex,
            raw_tx: raw_tx.to_vec(),
        });
        break;
    }
    Ok(due)
}

pub(crate) fn mark_due_parts_with_noncanonical_broadcast_height_for_resign(
    db_path: &str,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<u32, String> {
    // Outbox export and broadcast advance call this before due selection.
    // Reconcile and the needs_resign flip share one IMMEDIATE transaction so a
    // mined-but-still-`scheduled` part whose tip crossed a ZIP 318 expiry
    // window is promoted to `confirmed` instead of `needs_resign`, and
    // foreground sync cannot commit that chain identity between the check and
    // the status update.
    let mut conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let canonical_expiry = zip318_canonical_migration_expiry_height(chain_tip_height)?;
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| format!("Begin migration broadcast-height validation: {e}"))?;
    reconcile_run_confirmations(&tx, run_id)?;
    let affected = tx
        .execute(
            &format!(
                "UPDATE {PENDING_TXS_TABLE}
                 SET status = 'needs_resign'
                 WHERE run_id = ?1 AND status = 'scheduled'
                   AND scheduled_height <= ?2 AND expiry_height != ?3"
            ),
            params![run_id, chain_tip_height, canonical_expiry],
        )
        .map_err(|e| format!("Mark migration broadcast-height mismatch for signing: {e}"))?;
    if affected > 0 {
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2,
                     last_error = 'Migration broadcast height crossed a ZIP 318 expiry boundary'
                 WHERE run_id = ?3"
            ),
            params![PHASE_READY_TO_MIGRATE, now_ms()?, run_id],
        )
        .map_err(|e| format!("Mark migration broadcast-height recovery: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit migration broadcast-height validation: {e}"))?;
    u32::try_from(affected).map_err(|_| "Migration recovery count exceeds u32".to_string())
}

pub(crate) fn next_scheduled_height(db_path: &str, run_id: &str) -> Result<Option<u32>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!(
            "SELECT MIN(scheduled_height)
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND status = 'scheduled'"
        ),
        params![run_id],
        |row| row.get::<_, Option<u32>>(0),
    )
    .map_err(|e| format!("Read next migration schedule: {e}"))
}

pub(crate) fn due_scheduled_pending_count(
    db_path: &str,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<u32, String> {
    // Match due selection: promote locally mined scheduled rows first so the
    // broadcast gate does not treat a stale head as still due.
    reconcile_run_pending_confirmations(db_path, run_id)?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!(
            "SELECT COUNT(*)
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'scheduled' AND scheduled_height <= ?2"
        ),
        params![run_id, chain_tip_height],
        |row| row.get(0),
    )
    .map_err(|e| format!("Count due migration transactions: {e}"))
}

pub(crate) fn proof_retry_height(db_path: &str, run_id: &str) -> Result<Option<u32>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!("SELECT proof_retry_height FROM {RUNS_TABLE} WHERE run_id = ?1"),
        params![run_id],
        |row| row.get(0),
    )
    .map_err(|e| format!("Read migration proof retry height: {e}"))
}

pub(crate) fn set_proof_retry_height(
    db_path: &str,
    run_id: &str,
    retry_height: u32,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET proof_retry_height = ?1, updated_at_ms = ?2
             WHERE run_id = ?3"
        ),
        params![retry_height, now_ms()?, run_id],
    )
    .map_err(|e| format!("Set migration proof retry height: {e}"))?;
    Ok(())
}

/// Whether a past-expiry pending row should flip to `needs_resign`.
///
/// `scheduled` always resigns. `broadcasted` only resigns once local storage
/// succeeded (`transactions.raw` present): not-yet-stored accepted txs must
/// stay `broadcasted` so store-retry can still run.
fn pending_row_is_expired_for_resign(
    conn: &rusqlite::Connection,
    status: &str,
    expiry_height: u32,
    chain_tip_height: u32,
    txid_hex: &str,
) -> Result<bool, String> {
    if expiry_height == 0 || expiry_height > chain_tip_height {
        return Ok(false);
    }
    match status {
        "scheduled" => Ok(true),
        "broadcasted" => Ok(local_transaction_raw(conn, txid_hex)?.is_some()),
        _ => Ok(false),
    }
}

fn expired_unconfirmed_pending_txids(
    conn: &rusqlite::Connection,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<Vec<String>, String> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, status, expiry_height
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
               AND status IN ('scheduled', 'broadcasted')
               AND expiry_height > 0
               AND expiry_height <= ?2"
        ))
        .map_err(|e| format!("Prepare expired migration query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, chain_tip_height], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u32>(2)?,
            ))
        })
        .map_err(|e| format!("Query expired migration transactions: {e}"))?;

    let mut expired = Vec::new();
    for row in rows {
        let (txid_hex, status, expiry_height) =
            row.map_err(|e| format!("Read expired migration transaction: {e}"))?;
        if pending_row_is_expired_for_resign(
            conn,
            &status,
            expiry_height,
            chain_tip_height,
            &txid_hex,
        )? {
            expired.push(txid_hex);
        }
    }
    Ok(expired)
}

pub(crate) fn expired_unconfirmed_pending_count(
    db_path: &str,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<u32, String> {
    // Resume/export paths check this before due selection. Promote locally mined
    // rows first so a past-expiry but already-confirmed part is not treated as
    // needing resign.
    reconcile_run_pending_confirmations(db_path, run_id)?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let expired = expired_unconfirmed_pending_txids(&conn, run_id, chain_tip_height)?;
    u32::try_from(expired.len()).map_err(|_| "Expired migration count exceeds u32".to_string())
}

pub(crate) fn mark_expired_pending_parts_for_resign(
    db_path: &str,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<u32, String> {
    // Resume (`migrate_orchard_to_ironwood`) and outbox export call this before
    // `due_pending_txs`. Reconcile and the needs_resign flip share one IMMEDIATE
    // transaction so a mined-but-still-`scheduled` part past its expiry height
    // is promoted to `confirmed` instead of `needs_resign`, and foreground sync
    // cannot commit that chain identity between the check and the status update.
    let mut conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| format!("Begin expired migration recovery: {e}"))?;
    reconcile_run_confirmations(&tx, run_id)?;
    let expired = expired_unconfirmed_pending_txids(&tx, run_id, chain_tip_height)?;
    let mut updated: usize = 0;
    for txid_hex in &expired {
        updated += tx
            .execute(
                &format!(
                    "UPDATE {PENDING_TXS_TABLE}
                     SET status = 'needs_resign'
                     WHERE run_id = ?1 AND txid_hex = ?2
                       AND status IN ('scheduled', 'broadcasted')"
                ),
                params![run_id, txid_hex],
            )
            .map_err(|e| format!("Mark expired migration parts for re-signing: {e}"))?;
    }
    if updated > 0 {
        let now = now_ms()?;
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = ?3
                 WHERE run_id = ?4"
            ),
            params![
                PHASE_READY_TO_MIGRATE,
                now,
                "Expired migration parts must be re-signed with fresh anchors and expiry heights.",
                run_id,
            ],
        )
        .map_err(|e| format!("Mark migration run ready for expiry recovery: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit expired migration recovery: {e}"))?;
    u32::try_from(updated).map_err(|_| "Expired migration part count exceeds u32".to_string())
}

pub(crate) fn pending_parts_needing_resign(
    db_path: &str,
    run_id: &str,
) -> Result<Vec<PendingMigrationPartRecovery>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT part_index, txid_hex, value_zatoshi, fee_zatoshi, metadata_json
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'needs_resign'
             ORDER BY scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration re-sign query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, u64>(3)?,
                row.get::<_, String>(4)?,
            ))
        })
        .map_err(|e| format!("Query migration parts needing re-sign: {e}"))?;
    let mut recoveries = Vec::new();
    for row in rows {
        let (part_index, old_txid_hex, value_zatoshi, fee_zatoshi, metadata_json) =
            row.map_err(|e| format!("Read migration part needing re-sign: {e}"))?;
        let metadata = serde_json::from_str::<PendingMigrationTxMetadata>(&metadata_json)
            .map_err(|e| format!("Decode migration recovery metadata: {e}"))?;
        recoveries.push(PendingMigrationPartRecovery {
            part_index,
            old_txid_hex,
            value_zatoshi,
            fee_zatoshi,
            selected_note: metadata.selected_note,
        });
    }
    Ok(recoveries)
}

pub(crate) fn replace_resigned_pending_parts(
    db_path: &str,
    run_id: &str,
    _network: WalletNetwork,
    mut replacements: Vec<PendingMigrationTxReplacement>,
    signed_children: Vec<SignedMigrationPcztInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    if replacements.is_empty() {
        return Ok(());
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let (schedule_json, recovery_origin) = conn
        .query_row(
            &format!(
                "SELECT schedule_json, recovery_schedule_origin_height
                 FROM {RUNS_TABLE} WHERE run_id = ?1"
            ),
            params![run_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, Option<u32>>(1)?)),
        )
        .map_err(|e| format!("Read replacement migration schedule: {e}"))?;
    let schedule: Vec<MigrationScheduleEntry> = serde_json::from_str(&schedule_json)
        .map_err(|e| format!("Decode replacement migration schedule: {e}"))?;
    let scheduled_start_ms = now_ms()?;
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration part replacement: {e}"))?;

    let mut scheduled_replacements = Vec::with_capacity(replacements.len());
    for schedule_entry in schedule {
        let replacement_index =
            replacements
                .iter()
                .position(|replacement| match schedule_entry.part_index {
                    Some(part_index) => {
                        replacement.replacement.part_index == part_index
                            && replacement.replacement.value_zatoshi == schedule_entry.value_zatoshi
                    }
                    None => replacement.replacement.value_zatoshi == schedule_entry.value_zatoshi,
                });
        let Some(replacement_index) = replacement_index else {
            continue;
        };
        scheduled_replacements.push((replacements.swap_remove(replacement_index), schedule_entry));
    }
    if !replacements.is_empty() {
        return Err("Replacement migration schedule does not match its denominations".to_string());
    }

    for (replacement, _schedule_entry) in scheduled_replacements {
        let original = tx
            .query_row(
                &format!(
                    "SELECT value_zatoshi, selected_note_txid,
                            selected_note_output_index, original_scheduled_height,
                            rebuild_block_offset
                     FROM {PENDING_TXS_TABLE}
                     WHERE run_id = ?1 AND txid_hex = ?2
                       AND status = 'needs_resign'"
                ),
                params![run_id, replacement.old_txid_hex],
                |row| {
                    Ok((
                        row.get::<_, u64>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, u32>(2)?,
                        row.get::<_, Option<u32>>(3)?,
                        row.get::<_, Option<u32>>(4)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| format!("Read expired migration part: {e}"))?
            .ok_or("Expired migration part disappeared before replacement")?;
        if original.0 != replacement.replacement.value_zatoshi {
            return Err("Expired migration denomination changed during recovery".to_string());
        }
        if !original
            .1
            .eq_ignore_ascii_case(&replacement.replacement.selected_note.txid_hex)
            || original.2 != replacement.replacement.selected_note.output_index
        {
            return Err("Expired migration funding note changed during recovery".to_string());
        }

        let pending = replacement.replacement;
        let canonical_expiry = zip318_canonical_migration_expiry_height(pending.scheduled_height)?;
        if pending.expiry_height != canonical_expiry {
            return Err(
                "Replacement migration expiry is not canonical for its scheduled height"
                    .to_string(),
            );
        }
        // Rebuilt rows use their recovery generation rather than the original
        // approved schedule.
        let schedule_start_height = pending.target_height.saturating_sub(1);
        let rebuild_block_offset = pending
            .scheduled_height
            .checked_sub(schedule_start_height)
            .ok_or("Replacement migration schedule starts below zero")?;
        match (recovery_origin, original.4) {
            (Some(origin), Some(persisted_offset)) => {
                let persisted_scheduled_height = origin
                    .checked_add(persisted_offset)
                    .ok_or("Persisted migration recovery schedule overflow")?;
                if schedule_start_height != origin
                    || pending.scheduled_height != persisted_scheduled_height
                {
                    return Err(
                        "Replacement migration schedule does not match its persisted recovery offset"
                            .to_string(),
                    );
                }
            }
            // Runs created before recovery generations have neither field.
            (None, None) => {}
            _ => return Err("Migration recovery schedule metadata is incomplete".to_string()),
        }
        let encrypted_raw_tx = secret_payload::encrypt_payload(
            Zeroizing::new(pending.raw_tx),
            password,
            salt.as_slice(),
        )?;
        let metadata_json = serde_json::to_string(&pending.metadata)
            .map_err(|e| format!("Encode replacement migration metadata: {e}"))?;
        let scheduled_at_ms = scheduled_start_ms
            .checked_add(i64::from(rebuild_block_offset).saturating_mul(1000))
            .ok_or("Replacement migration time overflow")?;
        let scheduled_height = pending.scheduled_height;
        let original_scheduled_height = original.3;

        tx.execute(
            &format!("DELETE FROM {PENDING_TXS_TABLE} WHERE run_id = ?1 AND txid_hex = ?2"),
            params![run_id, replacement.old_txid_hex],
        )
        .map_err(|e| format!("Delete expired migration part: {e}"))?;
        tx.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, part_index, encrypted_raw_tx, target_height, expiry_height,
                  anchor_boundary_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  schedule_start_height, scheduled_height, original_scheduled_height,
                  status, metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,
                         ?13, ?14, ?15, ?16, 'scheduled', ?17)"
            ),
            params![
                run_id,
                pending.txid_hex,
                pending.part_index,
                encrypted_raw_tx,
                pending.target_height,
                pending.expiry_height,
                pending.anchor_boundary_height,
                pending.value_zatoshi,
                pending.fee_zatoshi,
                pending.selected_note.txid_hex,
                pending.selected_note.output_index,
                pending.selected_note.value_zatoshi,
                scheduled_at_ms,
                schedule_start_height,
                scheduled_height,
                original_scheduled_height,
                metadata_json,
            ],
        )
        .map_err(|e| format!("Insert replacement migration part: {e}"))?;
    }

    insert_signed_child_pczts_with_tx(
        &tx,
        run_id,
        signed_children,
        password,
        salt_base64,
        SignedChildInsertMode::Replacement,
    )?;
    // A finished recovery set retires its schedule generation so a later
    // `needs_resign` wave anchors a fresh ladder at its own time.
    let remaining_resign: u32 = tx
        .query_row(
            &format!(
                "SELECT COUNT(*) FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND status = 'needs_resign'"
            ),
            params![run_id],
            |row| row.get(0),
        )
        .map_err(|e| format!("Count remaining migration re-sign parts: {e}"))?;
    if remaining_resign == 0 {
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET recovery_schedule_origin_height = NULL,
                     recovery_schedule_max_block_offset = NULL
                 WHERE run_id = ?1"
            ),
            params![run_id],
        )
        .map_err(|e| format!("Retire migration rebuild schedule generation: {e}"))?;
    }
    let now = now_ms()?;
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = NULL
             WHERE run_id = ?3"
        ),
        params![PHASE_BROADCAST_SCHEDULED, now, run_id],
    )
    .map_err(|e| format!("Mark recovered migration scheduled: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit migration part replacement: {e}"))
}

pub(crate) fn noncanonical_unconfirmed_fee_count(
    db_path: &str,
    run_id: &str,
    canonical_fee_zatoshi: u64,
) -> Result<u32, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!(
            "SELECT COUNT(*)
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
               AND status IN ('scheduled', 'broadcasted', 'needs_resign')
               AND fee_zatoshi != ?2"
        ),
        params![run_id, canonical_fee_zatoshi],
        |row| row.get::<_, u32>(0),
    )
    .map_err(|e| format!("Count migration transactions with stale fees: {e}"))
}

pub(crate) fn scheduled_inputs_spent_by_mined_transactions(
    db_path: &str,
    run_id: &str,
) -> Result<Vec<PreparedOrchardNoteRef>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    if !table_exists(&conn, "transactions")?
        || !table_exists(&conn, "orchard_received_notes")?
        || !table_exists(&conn, "orchard_received_note_spends")?
    {
        return Ok(Vec::new());
    }

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, selected_note_txid, selected_note_output_index,
                    selected_note_value, metadata_json
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
               AND status IN ('scheduled', 'broadcasted', 'needs_resign')"
        ))
        .map_err(|e| format!("Prepare scheduled migration input query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u32>(2)?,
                row.get::<_, u64>(3)?,
                row.get::<_, String>(4)?,
            ))
        })
        .map_err(|e| format!("Query scheduled migration inputs: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read scheduled migration inputs: {e}"))?;
    drop(stmt);

    let mut spent = Vec::new();
    for (expected_spend_txid, txid_hex, output_index, value_zatoshi, metadata_json) in rows {
        let metadata = serde_json::from_str::<PendingMigrationTxMetadata>(&metadata_json)
            .map_err(|e| format!("Decode scheduled migration input metadata: {e}"))?;
        let expected_spend_txids = txid_blob_variants(&expected_spend_txid)?;
        let mut mined_spend_exists = false;
        for txid_blob in txid_blob_variants(&txid_hex)? {
            let mut spend_stmt = conn
                .prepare_cached(
                    "SELECT spend_tx.txid
                     FROM orchard_received_notes note
                     INNER JOIN transactions source_tx
                         ON source_tx.id_tx = note.transaction_id
                     INNER JOIN orchard_received_note_spends spend
                         ON spend.orchard_received_note_id = note.id
                     INNER JOIN transactions spend_tx
                         ON spend_tx.id_tx = spend.transaction_id
                     WHERE source_tx.txid = ?1
                       AND note.action_index = ?2
                       AND note.value = ?3
                       AND spend_tx.mined_height IS NOT NULL",
                )
                .map_err(|e| format!("Prepare scheduled migration input spend query: {e}"))?;
            let mined_spend_txids = spend_stmt
                .query_map(params![txid_blob, output_index, value_zatoshi], |row| {
                    row.get::<_, Vec<u8>>(0)
                })
                .map_err(|e| format!("Check scheduled migration input spend: {e}"))?
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| format!("Read scheduled migration input spend: {e}"))?;
            mined_spend_exists = mined_spend_txids
                .iter()
                .any(|spend_txid| !expected_spend_txids.contains(spend_txid));
            if mined_spend_exists {
                break;
            }
        }
        if mined_spend_exists {
            spent.push(metadata.selected_note);
        }
    }
    Ok(spent)
}

pub(crate) fn retire_run_for_rebuild(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
    message: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let now = now_ms()?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration rebuild transition: {e}"))?;
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = ?3
             WHERE run_id = ?4"
        ),
        params![PHASE_FAILED_TERMINAL, now, message, run_id],
    )
    .map_err(|e| format!("Mark migration run for rebuild: {e}"))?;
    tx.execute(
        &format!(
            "UPDATE {PREPARED_NOTES_TABLE}
             SET lock_state = 'unlocked'
             WHERE run_id = ?1"
        ),
        params![run_id],
    )
    .map_err(|e| format!("Release expired migration note locks: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit migration rebuild transition: {e}"))?;
    drop(conn);
    reconcile_wallet_locks_for_run(db_path, network, run_id)
}

pub(crate) fn abandon_run(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    expected_run_id: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let run = conn
        .query_row(
            &format!(
                "SELECT account_uuid, network, phase
                 FROM {RUNS_TABLE}
                 WHERE run_id = ?1"
            ),
            params![expected_run_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read migration run before stopping: {e}"))?
        .ok_or_else(|| format!("Migration run {expected_run_id} was not found"))?;
    if run.0 != account_uuid || run.1 != network_name(network) {
        return Err("Migration run does not belong to this wallet account".to_string());
    }
    if run.2 == PHASE_ABANDONED {
        drop(conn);
        reconcile_wallet_locks_for_run(db_path, network, expected_run_id)?;
        return discard_unsubmitted_preparation_stages(db_path, expected_run_id);
    }
    if matches!(run.2.as_str(), PHASE_COMPLETE | PHASE_FAILED_TERMINAL) {
        return Err(format!("Migration run is already terminal ({})", run.2));
    }

    let now = now_ms()?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration stop transition: {e}"))?;
    let transitioned = tx
        .execute(
            &format!(
                "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = ?3
             WHERE run_id = ?4 AND phase = ?5"
            ),
            params![
                PHASE_ABANDONED,
                now,
                "Migration stopped by the user.",
                expected_run_id,
                run.2
            ],
        )
        .map_err(|e| format!("Mark migration stopped: {e}"))?;
    if transitioned != 1 {
        return Err("Migration phase changed while stopping; retry.".to_string());
    }

    // A prepared child PCZT has not reached the network. Once the run is
    // terminal it must never be promoted by a later foreground retry.
    tx.execute(
        &format!("DELETE FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1"),
        params![expected_run_id],
    )
    .map_err(|e| format!("Discard unsubmitted migration proofs: {e}"))?;
    tx.execute(
        &format!(
            "DELETE FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status IN ('scheduled', 'needs_resign')"
        ),
        params![expected_run_id],
    )
    .map_err(|e| format!("Discard unsubmitted migration transactions: {e}"))?;

    tx.execute(
        &format!(
            "UPDATE {PREPARED_NOTES_TABLE}
             SET lock_state = 'unlocked'
             WHERE run_id = ?1"
        ),
        params![expected_run_id],
    )
    .map_err(|e| format!("Release stopped migration note locks: {e}"))?;
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET recovery_schedule_origin_height = NULL,
                 recovery_schedule_max_block_offset = NULL
             WHERE run_id = ?1"
        ),
        params![expected_run_id],
    )
    .map_err(|e| format!("Retire stopped migration rebuild schedule: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit migration stop transition: {e}"))?;
    drop(conn);

    // Keep stage inputs until generic wallet locks have been released: those
    // rows can be the only durable outpoint list for later split rounds.
    reconcile_wallet_locks_for_run(db_path, network, expected_run_id)?;
    discard_unsubmitted_preparation_stages(db_path, expected_run_id)
}

fn discard_unsubmitted_preparation_stages(db_path: &str, run_id: &str) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin stopped preparation cleanup: {e}"))?;

    // Broadcasted/confirmed rows remain as durable audit state; the ordinary
    // wallet scanner continues to discover their resulting notes.
    tx.execute(
        &format!(
            "DELETE FROM {STAGE_INPUTS_TABLE}
             WHERE run_id = ?1 AND stage_index IN (
                 SELECT stage_index FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND status IN ('awaiting_inputs', 'pending')
             )"
        ),
        params![run_id],
    )
    .map_err(|e| format!("Discard stopped preparation inputs: {e}"))?;
    tx.execute(
        &format!(
            "DELETE FROM {STAGE_OUTPUTS_TABLE}
             WHERE run_id = ?1 AND stage_index IN (
                 SELECT stage_index FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND status IN ('awaiting_inputs', 'pending')
             )"
        ),
        params![run_id],
    )
    .map_err(|e| format!("Discard stopped preparation outputs: {e}"))?;
    tx.execute(
        &format!(
            "DELETE FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND status IN ('awaiting_inputs', 'pending')"
        ),
        params![run_id],
    )
    .map_err(|e| format!("Discard unsubmitted preparation transactions: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit stopped preparation cleanup: {e}"))
}

/// One persisted recovery-schedule generation: every rebuilt part shares
/// `origin_height` and carries its own cumulative offset, so all consumers
/// (the software rebuild and each Keystone signing batch) schedule against
/// the same ladder instead of anchoring per-batch ladders at their own tips.
#[derive(Clone, Debug)]
pub(crate) struct RebuildScheduleGeneration {
    pub origin_height: u32,
    pub offsets_by_txid: BTreeMap<String, u32>,
}

/// Draws and persists a rebuild offset for every `needs_resign` part that
/// lacks one, anchored at one shared recovery origin (created at
/// `origin_candidate_height` when absent). The generation persists its
/// historical maximum so parts marked `needs_resign` after earlier batches
/// were replaced still extend the same ladder. The generation is cleared
/// when the last `needs_resign` row is replaced (see
/// `replace_resigned_pending_parts`). Returns `None` when the run has no
/// parts waiting for re-sign.
pub(crate) fn ensure_rebuild_schedule_generation(
    db_path: &str,
    run_id: &str,
    network: WalletNetwork,
    origin_candidate_height: u32,
) -> Result<Option<RebuildScheduleGeneration>, String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(|e| format!("Begin migration rebuild schedule update: {e}"))?;
    let rows = {
        let mut stmt = tx
            .prepare_cached(&format!(
                "SELECT txid_hex, part_index, value_zatoshi, rebuild_block_offset
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND status = 'needs_resign'
                 ORDER BY scheduled_height ASC, txid_hex ASC"
            ))
            .map_err(|e| format!("Prepare migration rebuild schedule query: {e}"))?;
        let rows = stmt
            .query_map(params![run_id], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<u32>>(1)?,
                    row.get::<_, u64>(2)?,
                    row.get::<_, Option<u32>>(3)?,
                ))
            })
            .map_err(|e| format!("Query migration rebuild schedule rows: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read migration rebuild schedule row: {e}"))?
    };
    if rows.is_empty() {
        return Ok(None);
    }

    let timing_policy = timing_policy_for_run_with_conn(&tx, run_id, network)?;
    let (schedule_json, target_values_json, persisted_origin, persisted_max_offset) = tx
        .query_row(
            &format!(
                "SELECT schedule_json, target_values_json, recovery_schedule_origin_height,
                        recovery_schedule_max_block_offset
                 FROM {RUNS_TABLE} WHERE run_id = ?1"
            ),
            params![run_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<u32>>(2)?,
                    row.get::<_, Option<u32>>(3)?,
                ))
            },
        )
        .map_err(|e| format!("Read migration rebuild schedule origin: {e}"))?;
    let origin_height = persisted_origin.unwrap_or(origin_candidate_height);

    let mut offsets_by_txid = BTreeMap::new();
    let mut missing = Vec::new();
    for (txid_hex, part_index, value_zatoshi, offset) in rows {
        let part_index =
            part_index.ok_or("Migration part waiting for re-sign is missing its part index")?;
        match offset {
            Some(offset) => {
                offsets_by_txid.insert(txid_hex.to_ascii_lowercase(), offset);
            }
            None => missing.push((txid_hex, part_index, value_zatoshi)),
        }
    }
    let observed_max_offset = offsets_by_txid.values().copied().max().unwrap_or(0);
    if persisted_origin.is_none() && (persisted_max_offset.is_some() || !offsets_by_txid.is_empty())
    {
        return Err("Migration recovery schedule metadata is incomplete".to_string());
    }
    let base_offset = match persisted_max_offset {
        Some(max_offset) if max_offset >= observed_max_offset => max_offset,
        Some(_) => {
            return Err(
                "Migration recovery schedule maximum is below a persisted part offset".to_string(),
            )
        }
        None => observed_max_offset,
    };
    if missing.is_empty() && persisted_origin.is_some() && persisted_max_offset.is_some() {
        tx.commit()
            .map_err(|e| format!("Commit migration rebuild schedule update: {e}"))?;
        return Ok(Some(RebuildScheduleGeneration {
            origin_height,
            offsets_by_txid,
        }));
    }

    let mut generation_max_offset = base_offset;
    if !missing.is_empty() {
        let schedule: Vec<MigrationScheduleEntry> = serde_json::from_str(&schedule_json)
            .map_err(|e| format!("Decode migration rebuild schedule: {e}"))?;
        let target_values: Vec<u64> = serde_json::from_str(&target_values_json)
            .map_err(|e| format!("Decode migration rebuild target values: {e}"))?;
        let recovery_parts = missing
            .iter()
            .map(|(_, part_index, value_zatoshi)| (*part_index, *value_zatoshi))
            .collect::<Vec<_>>();
        let fresh_offsets = rebuild_schedule_block_offsets(
            &schedule,
            &target_values,
            &recovery_parts,
            network,
            timing_policy,
            &mut OsRng,
        )?;

        for ((txid_hex, _, _), fresh_offset) in missing.iter().zip(fresh_offsets) {
            let assigned = base_offset
                .checked_add(fresh_offset)
                .ok_or("Migration rebuild schedule offset overflow")?;
            let updated = tx
                .execute(
                    &format!(
                        "UPDATE {PENDING_TXS_TABLE}
                         SET rebuild_block_offset = ?1
                         WHERE run_id = ?2 AND txid_hex = ?3
                           AND status = 'needs_resign' AND rebuild_block_offset IS NULL"
                    ),
                    params![assigned, run_id, txid_hex],
                )
                .map_err(|e| format!("Persist migration rebuild schedule offset: {e}"))?;
            if updated != 1 {
                return Err("Migration recovery part changed while scheduling".to_string());
            }
            generation_max_offset = generation_max_offset.max(assigned);
            offsets_by_txid.insert(txid_hex.to_ascii_lowercase(), assigned);
        }
    }
    let updated = tx
        .execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET recovery_schedule_origin_height = ?1,
                     recovery_schedule_max_block_offset = ?2
                 WHERE run_id = ?3"
            ),
            params![origin_height, generation_max_offset, run_id],
        )
        .map_err(|e| format!("Persist migration rebuild schedule generation: {e}"))?;
    if updated != 1 {
        return Err("Migration run changed while scheduling recovery".to_string());
    }
    tx.commit()
        .map_err(|e| format!("Commit migration rebuild schedule update: {e}"))?;

    Ok(Some(RebuildScheduleGeneration {
        origin_height,
        offsets_by_txid,
    }))
}

pub(crate) fn reschedule_overdue_pending_txs(
    db_path: &str,
    run_id: &str,
    network: WalletNetwork,
    chain_tip_height: u32,
) -> Result<(), String> {
    reschedule_overdue_pending_txs_with_options(db_path, run_id, network, chain_tip_height, 0, None)
}

fn reschedule_overdue_pending_txs_with_options(
    db_path: &str,
    run_id: &str,
    network: WalletNetwork,
    chain_tip_height: u32,
    minimum_delay_blocks: u32,
    excluded_txid: Option<&str>,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, expiry_height FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'scheduled' AND scheduled_height <= ?2"
        ))
        .map_err(|e| format!("Prepare overdue migration query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, chain_tip_height], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?))
        })
        .map_err(|e| format!("Query overdue migration transactions: {e}"))?;
    let mut txids = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read overdue migration transaction: {e}"))?;
    drop(stmt);
    if let Some(excluded_txid) = excluded_txid {
        txids.retain(|(txid, _)| txid != excluded_txid);
    }
    if txids.is_empty() {
        return Ok(());
    }

    txids.shuffle(&mut OsRng);
    let timing_policy = timing_policy_for_run_with_conn(&conn, run_id, network)?;
    let (mean_delay_blocks, max_delay_blocks) =
        schedule_parameters_with_policy(network, timing_policy);
    let offsets = random_schedule_block_offsets_with_rng(
        txids.len(),
        mean_delay_blocks,
        max_delay_blocks,
        &mut OsRng,
    );
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin overdue migration reschedule: {e}"))?;
    let mut needs_resign = false;
    for ((txid, expiry_height), offset) in txids.into_iter().zip(offsets) {
        let scheduled_height = chain_tip_height
            .checked_add(offset.max(minimum_delay_blocks))
            .ok_or("Migration rescheduled height overflow")?;
        if zip318_canonical_migration_expiry_height(scheduled_height)? != expiry_height {
            tx.execute(
                &format!(
                    "UPDATE {PENDING_TXS_TABLE}
                     SET status = 'needs_resign'
                     WHERE run_id = ?1 AND txid_hex = ?2 AND status = 'scheduled'"
                ),
                params![run_id, txid],
            )
            .map_err(|e| format!("Mark noncanonical migration reschedule for signing: {e}"))?;
            needs_resign = true;
            continue;
        }
        tx.execute(
            &format!(
                "UPDATE {PENDING_TXS_TABLE}
                 SET scheduled_height = ?1, schedule_start_height = ?2
                 WHERE run_id = ?3 AND txid_hex = ?4 AND status = 'scheduled'"
            ),
            params![scheduled_height, chain_tip_height, run_id, txid],
        )
        .map_err(|e| format!("Reschedule overdue migration transaction: {e}"))?;
    }
    if needs_resign {
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2,
                     last_error = 'Migration schedule crossed a ZIP 318 expiry boundary'
                 WHERE run_id = ?3"
            ),
            params![PHASE_READY_TO_MIGRATE, now_ms()?, run_id],
        )
        .map_err(|e| format!("Mark migration reschedule for signing: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit overdue migration reschedule: {e}"))
}

/// Redraws every still-overdue scheduled transfer in this wallet after the
/// single ZIP 318 on-open fallback transfer has been submitted.
///
/// Runs are collected first and then rescheduled independently because each
/// run owns its timing policy and may cross a different canonical expiry
/// boundary. This function intentionally spans accounts: the on-open limit is
/// a wallet privacy invariant, not a per-account allowance.
pub(crate) fn reschedule_wallet_overdue_pending_txs(
    db_path: &str,
    network: WalletNetwork,
    chain_tip_height: u32,
) -> Result<(), String> {
    reschedule_wallet_overdue_pending_txs_with_exclusion(db_path, network, chain_tip_height, None)
}

/// Reschedules every other overdue transfer after lightwalletd accepted a
/// transaction whose local storage update failed. The accepted transaction is
/// left in place for storage recovery; it must not be redrawn into a new
/// expiry bucket or treated as needing a new signature.
pub(crate) fn reschedule_wallet_overdue_pending_txs_after_accepted(
    db_path: &str,
    network: WalletNetwork,
    chain_tip_height: u32,
    accepted_run_id: &str,
    accepted_txid: &str,
) -> Result<(), String> {
    reschedule_wallet_overdue_pending_txs_with_exclusion(
        db_path,
        network,
        chain_tip_height,
        Some((accepted_run_id, accepted_txid)),
    )
}

fn reschedule_wallet_overdue_pending_txs_with_exclusion(
    db_path: &str,
    network: WalletNetwork,
    chain_tip_height: u32,
    excluded: Option<(&str, &str)>,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let run_ids = {
        let mut stmt = conn
            .prepare_cached(&format!(
                "SELECT DISTINCT pending.run_id
                 FROM {PENDING_TXS_TABLE} AS pending
                 JOIN {RUNS_TABLE} AS runs ON runs.run_id = pending.run_id
                 WHERE pending.status = 'scheduled'
                   AND pending.scheduled_height <= ?1
                   AND runs.network = ?2
                 ORDER BY pending.run_id ASC"
            ))
            .map_err(|e| format!("Prepare wallet overdue migration query: {e}"))?;
        let rows = stmt
            .query_map(params![chain_tip_height, network_name(network)], |row| {
                row.get::<_, String>(0)
            })
            .map_err(|e| format!("Query wallet overdue migration runs: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read wallet overdue migration run: {e}"))?
    };
    drop(conn);

    for run_id in run_ids {
        let excluded_txid = excluded.and_then(|(excluded_run_id, excluded_txid)| {
            (run_id == excluded_run_id).then_some(excluded_txid)
        });
        // A zero-block redraw would still be due during the same wallet-open
        // pass and could allow a second fallback submission. ZIP 318's
        // one-transfer on-open rule therefore requires at least one new block.
        reschedule_overdue_pending_txs_with_options(
            db_path,
            &run_id,
            network,
            chain_tip_height,
            1,
            excluded_txid,
        )?;
    }
    Ok(())
}

pub(crate) fn mark_pending_broadcasted(
    db_path: &str,
    run_id: &str,
    txid_hex: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let now = now_ms()?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin pending migration broadcast update: {e}"))?;
    tx.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET status = 'broadcasted'
             WHERE run_id = ?1 AND txid_hex = ?2"
        ),
        params![run_id, txid_hex],
    )
    .map_err(|e| format!("Mark pending migration tx broadcasted: {e}"))?;
    update_run_after_pending_broadcast(&tx, run_id, now)?;
    tx.commit()
        .map_err(|e| format!("Commit pending migration broadcast update: {e}"))
}

/// Pending rows already accepted on the network (`broadcasted`) whose raw tx is
/// not yet present in the local wallet DB. Used to retry local storage without
/// re-selecting them as due broadcasts.
pub(crate) fn broadcasted_pending_txs_missing_local_identity(
    db_path: &str,
    run_id: &str,
    password: &[u8],
    salt_base64: &str,
) -> Result<Vec<DuePendingMigrationTx>, String> {
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, encrypted_raw_tx
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'broadcasted'
             ORDER BY scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare broadcasted migration store-retry query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|e| format!("Query broadcasted migration store-retry txs: {e}"))?;

    let mut missing = Vec::new();
    for row in rows {
        let (txid_hex, encrypted_raw_tx) =
            row.map_err(|e| format!("Read broadcasted migration store-retry tx: {e}"))?;
        // Skip once local wallet storage has the raw bytes. Mined identity is
        // not required — store-retry is about persist, not confirmation.
        if local_transaction_raw(&conn, &txid_hex)?.is_some() {
            continue;
        }
        let raw_tx = secret_payload::decrypt_payload(
            encrypted_raw_tx.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        missing.push(DuePendingMigrationTx {
            txid_hex,
            raw_tx: raw_tx.to_vec(),
        });
    }
    Ok(missing)
}

fn update_run_after_pending_broadcast(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    now: i64,
) -> Result<(), String> {
    let needs_resign_remaining = count_pending_with_status(&tx, run_id, "needs_resign")?;
    let scheduled_remaining = count_pending_with_status(&tx, run_id, "scheduled")?;
    let pending_count = count_for_run(&tx, PENDING_TXS_TABLE, run_id)?;
    let planned_count = planned_part_count_with_conn(&tx, run_id)?;
    let unpromoted_count = unpromoted_signed_child_pczt_count_with_conn(&tx, run_id)?;
    let fully_materialized =
        planned_count > 0 && pending_count == planned_count && unpromoted_count == 0;
    let next_phase = if needs_resign_remaining > 0 {
        PHASE_READY_TO_MIGRATE
    } else if scheduled_remaining > 0 || !fully_materialized {
        PHASE_BROADCAST_SCHEDULED
    } else {
        PHASE_WAITING_MIGRATION_CONFIRMATIONS
    };
    if needs_resign_remaining > 0 {
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2
                 WHERE run_id = ?3"
            ),
            params![next_phase, now, run_id],
        )
        .map_err(|e| format!("Keep migration ready for re-signing: {e}"))?;
    } else {
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                 WHERE run_id = ?3"
            ),
            params![next_phase, now, run_id],
        )
        .map_err(|e| format!("Mark migration waiting confirmations: {e}"))?;
    }
    Ok(())
}

pub(crate) fn apply_accepted_migration_outbox_receipt(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    run_id: &str,
    txid_hex: &str,
    remote_height: u32,
    schedule_updates: &[MigrationOutboxScheduleUpdate],
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration outbox receipt reconciliation: {e}"))?;
    migration_outbox_run_phase_with_conn(&tx, account_uuid, network, run_id)?;
    let accepted_status = tx
        .query_row(
            &format!(
                "SELECT status FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND lower(txid_hex) = lower(?2)"
            ),
            params![run_id, txid_hex],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| format!("Read accepted migration outbox transaction: {e}"))?
        .ok_or_else(|| {
            "Migration outbox receipt transaction was not found in this run".to_string()
        })?;
    if !matches!(
        accepted_status.as_str(),
        "scheduled" | "broadcasted" | "confirmed" | "needs_resign"
    ) {
        return Err(format!(
            "Migration outbox receipt cannot accept a transaction in status {accepted_status}"
        ));
    }

    let timing_policy = timing_policy_for_run_with_conn(&tx, run_id, network)?;
    let (_, timing_max_blocks) = schedule_parameters_with_policy(network, timing_policy);
    let accepted_txid = txid_hex.to_ascii_lowercase();
    let mut supplied = BTreeMap::new();
    let mut previous_scheduled_height = remote_height;
    for update in schedule_updates {
        let item_id = update.item_id.to_ascii_lowercase();
        if item_id == accepted_txid {
            return Err("Accepted migration outbox item cannot reschedule itself".to_string());
        }
        if supplied.insert(item_id.clone(), update).is_some() {
            return Err(format!(
                "Migration outbox schedule update {item_id} is duplicated"
            ));
        }
        if update.schedule_start_height != remote_height {
            return Err(format!(
                "Migration outbox schedule update {item_id} does not start at the receipt height"
            ));
        }
        let incremental_delay = update
            .scheduled_height
            .checked_sub(previous_scheduled_height)
            .ok_or_else(|| format!("Migration outbox schedule update {item_id} moves backward"))?;
        if incremental_delay == 0 || incremental_delay > timing_max_blocks {
            return Err(format!(
                "Migration outbox schedule update {item_id} is outside the timing window"
            ));
        }
        previous_scheduled_height = update.scheduled_height;
    }

    if accepted_status == "scheduled" {
        let mut expected_stmt = tx
            .prepare_cached(&format!(
                "SELECT lower(txid_hex) FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND status = 'scheduled'
                   AND scheduled_height <= ?2 AND expiry_height > ?2
                   AND lower(txid_hex) != lower(?3)"
            ))
            .map_err(|e| format!("Prepare overdue migration outbox peers: {e}"))?;
        let expected = expected_stmt
            .query_map(params![run_id, remote_height, txid_hex], |row| {
                row.get::<_, String>(0)
            })
            .map_err(|e| format!("Query overdue migration outbox peers: {e}"))?
            .collect::<Result<BTreeSet<_>, _>>()
            .map_err(|e| format!("Read overdue migration outbox peers: {e}"))?;
        let supplied_ids = supplied.keys().cloned().collect::<BTreeSet<_>>();
        if supplied_ids != expected {
            return Err(
                "Migration outbox receipt must reschedule exactly the remaining overdue items"
                    .to_string(),
            );
        }
    }

    let mut schedule_crossed_expiry_boundary = false;
    for (item_id, update) in supplied {
        let (status, current_scheduled_height, current_schedule_start_height, expiry_height) = tx
            .query_row(
                &format!(
                    "SELECT status, scheduled_height, schedule_start_height, expiry_height
                     FROM {PENDING_TXS_TABLE}
                     WHERE run_id = ?1 AND lower(txid_hex) = ?2"
                ),
                params![run_id, item_id],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, u32>(1)?,
                        row.get::<_, Option<u32>>(2)?,
                        row.get::<_, u32>(3)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| format!("Read migration outbox schedule target: {e}"))?
            .ok_or_else(|| format!("Migration outbox schedule item {item_id} was not found"))?;
        let canonical_expiry = zip318_canonical_migration_expiry_height(update.scheduled_height)?;
        if status == "scheduled" {
            if canonical_expiry != expiry_height {
                tx.execute(
                    &format!(
                        "UPDATE {PENDING_TXS_TABLE}
                         SET status = 'needs_resign'
                         WHERE run_id = ?1 AND lower(txid_hex) = ?2
                           AND status = 'scheduled'"
                    ),
                    params![run_id, item_id],
                )
                .map_err(|e| format!("Mark outbox schedule update for signing: {e}"))?;
                schedule_crossed_expiry_boundary = true;
                continue;
            }
            tx.execute(
                &format!(
                    "UPDATE {PENDING_TXS_TABLE}
                     SET scheduled_height = ?1, schedule_start_height = ?2
                     WHERE run_id = ?3 AND lower(txid_hex) = ?4 AND status = 'scheduled'"
                ),
                params![
                    update.scheduled_height,
                    update.schedule_start_height,
                    run_id,
                    item_id,
                ],
            )
            .map_err(|e| format!("Apply migration outbox schedule update: {e}"))?;
        } else if current_scheduled_height != update.scheduled_height
            || current_schedule_start_height != Some(update.schedule_start_height)
        {
            return Err(format!(
                "Migration outbox schedule item {item_id} is no longer scheduled"
            ));
        }
    }
    if schedule_crossed_expiry_boundary {
        tx.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2,
                     last_error = 'Migration schedule crossed a ZIP 318 expiry boundary'
                 WHERE run_id = ?3"
            ),
            params![PHASE_READY_TO_MIGRATE, now_ms()?, run_id],
        )
        .map_err(|e| format!("Mark outbox migration reschedule for signing: {e}"))?;
    }

    if matches!(accepted_status.as_str(), "scheduled" | "needs_resign") {
        tx.execute(
            &format!(
                "UPDATE {PENDING_TXS_TABLE} SET status = 'broadcasted'
                 WHERE run_id = ?1 AND lower(txid_hex) = lower(?2)
                   AND status IN ('scheduled', 'needs_resign')"
            ),
            params![run_id, txid_hex],
        )
        .map_err(|e| format!("Mark migration outbox transaction broadcasted: {e}"))?;
        update_run_after_pending_broadcast(&tx, run_id, now_ms()?)?;
    }
    tx.commit()
        .map_err(|e| format!("Commit migration outbox receipt reconciliation: {e}"))
}

pub(crate) fn scheduled_pending_count(db_path: &str, run_id: &str) -> Result<u32, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    count_pending_with_status(&conn, run_id, "scheduled")
}

pub(crate) fn prepared_note_spend_metadata_available(
    db_path: &str,
    run_id: &str,
) -> Result<bool, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    prepared_note_spend_metadata_available_for_run(&conn, run_id)
}

pub(crate) fn prepared_notes_proof_ready_height(
    db_path: &str,
    run_id: &str,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> Result<Option<u32>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    prepared_notes_proof_ready_height_with_conn(&conn, run_id, network, timing_policy)
}

fn prepared_notes_proof_ready_height_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> Result<Option<u32>, String> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT DISTINCT txid_hex
             FROM {PREPARED_NOTES_TABLE}
             WHERE run_id = ?1
             ORDER BY txid_hex"
        ))
        .map_err(|e| format!("Prepare migration proof readiness query: {e}"))?;
    let txids = stmt
        .query_map(params![run_id], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Query migration proof readiness notes: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration proof readiness notes: {e}"))?;
    if txids.is_empty() {
        return Ok(None);
    }

    let mut ready_height = 0u32;
    for txid in txids {
        let Some(identity) = local_denomination_chain_identity(&conn, &txid)? else {
            return Ok(None);
        };
        ready_height = ready_height.max(proof_ready_height_for_note_mined_height(
            network,
            timing_policy,
            identity.mined_height,
        )?);
    }
    Ok(Some(ready_height))
}

pub(crate) fn pending_totals_for_run(
    db_path: &str,
    run_id: &str,
) -> Result<PendingMigrationTotals, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, value_zatoshi, fee_zatoshi, status
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
             ORDER BY scheduled_at_ms ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration pending totals query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, u64>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .map_err(|e| format!("Query migration pending totals: {e}"))?;

    let mut txids = Vec::new();
    let mut value_zatoshi = 0u64;
    let mut fee_zatoshi = 0u64;
    let mut broadcasted_count = 0u32;
    for row in rows {
        let (txid, value, fee, status) =
            row.map_err(|e| format!("Read migration pending totals: {e}"))?;
        txids.push(txid);
        value_zatoshi = value_zatoshi
            .checked_add(value)
            .ok_or("Migration pending value overflow")?;
        fee_zatoshi = fee_zatoshi
            .checked_add(fee)
            .ok_or("Migration pending fee overflow")?;
        if status == "broadcasted" || status == "confirmed" {
            broadcasted_count = broadcasted_count
                .checked_add(1)
                .ok_or("Migration broadcast count overflow")?;
        }
    }

    Ok(PendingMigrationTotals {
        total_count: txids.len() as u32,
        txids,
        value_zatoshi,
        fee_zatoshi,
        broadcasted_count,
    })
}

fn scheduled_broadcasts_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<Vec<ScheduledMigrationBroadcast>, String> {
    if !table_exists(conn, PENDING_TXS_TABLE)? {
        return Ok(Vec::new());
    }
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, value_zatoshi, scheduled_at_ms,
                    schedule_start_height, scheduled_height, status
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
             ORDER BY scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration schedule query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok(ScheduledMigrationBroadcast {
                txid_hex: row.get(0)?,
                value_zatoshi: row.get(1)?,
                scheduled_at_ms: row.get(2)?,
                schedule_start_height: row.get(3)?,
                scheduled_height: row.get(4)?,
                status: row.get(5)?,
            })
        })
        .map_err(|e| format!("Query migration schedule: {e}"))?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration schedule: {e}"))
}

pub(crate) fn locked_migration_note_refs(
    db_path: &str,
    account_uuid: &str,
) -> Result<BTreeSet<(String, u32)>, String> {
    let conn = open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT))
        .map_err(|e| format!("Failed to check migration note locks: {e}"))?;
    if !table_exists(&conn, PREPARED_NOTES_TABLE)? {
        return Ok(BTreeSet::new());
    }

    let mut locks = {
        let mut stmt = conn
            .prepare_cached(&format!(
                "SELECT lower(pn.txid_hex), pn.output_index
                 FROM {PREPARED_NOTES_TABLE} pn
                 INNER JOIN {RUNS_TABLE} r ON r.run_id = pn.run_id
                 WHERE r.account_uuid = ?1
                   AND pn.lock_state = 'locked'
                   AND r.phase NOT IN ('{PHASE_COMPLETE}', '{PHASE_FAILED_TERMINAL}', '{PHASE_ABANDONED}')"
            ))
            .map_err(|e| format!("Prepare migration lock query: {e}"))?;
        let rows = stmt
            .query_map(params![account_uuid], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(|e| format!("Query migration locks: {e}"))?;
        rows.collect::<Result<BTreeSet<_>, _>>()
            .map_err(|e| format!("Read migration locks: {e}"))?
    };

    let active_run_ids = {
        let mut stmt = conn
            .prepare_cached(&format!(
                "SELECT run_id FROM {RUNS_TABLE}
                 WHERE account_uuid = ?1
                   AND phase NOT IN ('{PHASE_COMPLETE}', '{PHASE_FAILED_TERMINAL}', '{PHASE_ABANDONED}')"
            ))
            .map_err(|e| format!("Prepare staged migration lock query: {e}"))?;
        let rows = stmt
            .query_map(params![account_uuid], |row| row.get::<_, String>(0))
            .map_err(|e| format!("Query staged migration locks: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read staged migration run locks: {e}"))?
    };
    for run_id in active_run_ids {
        locks.extend(locked_denomination_stage_input_outpoints(&conn, &run_id)?);
    }
    Ok(locks)
}

fn migration_timing_projection_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
    total_count: u32,
    confirmation_target: u32,
) -> Result<MigrationTimingProjection, String> {
    let (schedule_json, proof_retry_height) = conn
        .query_row(
            &format!(
                "SELECT schedule_json, proof_retry_height
                 FROM {RUNS_TABLE} WHERE run_id = ?1"
            ),
            params![run_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, Option<u32>>(1)?)),
        )
        .map_err(|e| format!("Read migration timing projection: {e}"))?;
    let schedule = serde_json::from_str::<Vec<MigrationScheduleEntry>>(&schedule_json)
        .map_err(|e| format!("Decode migration timing schedule: {e}"))?;
    if schedule.is_empty() || total_count == 0 {
        return Ok(MigrationTimingProjection::default());
    }

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT part_index, txid_hex, target_height, schedule_start_height,
                    scheduled_height, status
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
             ORDER BY part_index ASC, scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration timing pending query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, Option<u32>>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u32>(2)?,
                row.get::<_, Option<u32>>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, String>(5)?,
            ))
        })
        .map_err(|e| format!("Query migration timing pending parts: {e}"))?;
    let mut pending = Vec::new();
    for row in rows {
        let (part_index, txid_hex, target_height, schedule_start_height, scheduled_height, status) =
            row.map_err(|e| format!("Read migration timing pending part: {e}"))?;
        let mined_height = local_denomination_chain_identity(conn, &txid_hex)?
            .map(|identity| identity.mined_height);
        pending.push(MigrationTimingPendingPart {
            part_index,
            target_height,
            schedule_start_height,
            scheduled_height,
            status,
            mined_height,
        });
    }
    drop(stmt);

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT c.child_index, c.target_height
             FROM {SIGNED_CHILD_PCZTS_TABLE} c
             WHERE c.run_id = ?1
               AND NOT EXISTS (
                   SELECT 1 FROM {PENDING_TXS_TABLE} p
                   WHERE p.run_id = c.run_id AND p.part_index = c.child_index
               )
             ORDER BY c.child_index ASC, c.message_id ASC"
        ))
        .map_err(|e| format!("Prepare migration timing signed-child query: {e}"))?;
    let signed_children = stmt
        .query_map(params![run_id], |row| {
            Ok(MigrationTimingSignedChild {
                part_index: row.get(0)?,
                target_height: row.get(1)?,
            })
        })
        .map_err(|e| format!("Query migration timing signed children: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration timing signed child: {e}"))?;

    calculate_migration_timing_projection(
        &schedule,
        &pending,
        &signed_children,
        proof_retry_height,
        total_count,
        confirmation_target,
    )
}

fn calculate_migration_timing_projection(
    schedule: &[MigrationScheduleEntry],
    pending: &[MigrationTimingPendingPart],
    signed_children: &[MigrationTimingSignedChild],
    proof_retry_height: Option<u32>,
    total_count: u32,
    confirmation_target: u32,
) -> Result<MigrationTimingProjection, String> {
    let mut schedule_order_by_part = BTreeMap::new();
    for (schedule_order, entry) in schedule.iter().enumerate() {
        if let Some(part_index) = entry.part_index {
            let schedule_order = u32::try_from(schedule_order)
                .map_err(|_| "Migration schedule order exceeds u32".to_string())?;
            schedule_order_by_part.insert(part_index, schedule_order);
        }
    }
    let scheduled_next = pending
        .iter()
        .filter(|part| part.status == "scheduled")
        .min_by_key(|part| part.scheduled_height)
        .map(|part| (part.scheduled_height, part.part_index));
    let proof_next = proof_retry_height
        .filter(|_| !signed_children.is_empty())
        .map(|height| {
            (
                height,
                signed_children.iter().map(|child| child.part_index).min(),
            )
        });
    let next_action = match (scheduled_next, proof_next) {
        (Some(scheduled), Some(proof)) => Some(if scheduled.0 <= proof.0 {
            scheduled
        } else {
            proof
        }),
        (Some(scheduled), None) => Some(scheduled),
        (None, Some(proof)) => Some(proof),
        (None, None) => None,
    };
    let mut next_proof_window_part_indices = signed_children
        .iter()
        .map(|child| child.part_index)
        .collect::<Vec<_>>();
    next_proof_window_part_indices.sort_by_key(|part_index| {
        (
            schedule_order_by_part
                .get(part_index)
                .copied()
                .unwrap_or(u32::MAX),
            *part_index,
        )
    });

    let projected_signed_parts = if signed_children.is_empty() {
        Vec::new()
    } else {
        // Promotion reuses the first persisted schedule origin. Before any
        // child is promoted it uses the latest signed construction height.
        let persisted_schedule_origin = pending.first().map(|part| {
            part.schedule_start_height
                .unwrap_or_else(|| part.target_height.saturating_sub(1))
        });
        let schedule_origin = persisted_schedule_origin
            .or_else(|| {
                signed_children
                    .iter()
                    .map(|child| child.target_height.saturating_sub(1))
                    .max()
                    .map(|height| height.max(proof_retry_height.unwrap_or(0)))
            })
            .ok_or("Migration timing projection has no schedule origin")?;
        let indexed_schedule = schedule.iter().all(|entry| entry.part_index.is_some());
        signed_children
            .iter()
            .map(|child| {
                let offset = if indexed_schedule {
                    schedule
                        .iter()
                        .find(|entry| entry.part_index == Some(child.part_index))
                        .map(|entry| entry.block_offset)
                } else {
                    schedule.iter().map(|entry| entry.block_offset).max()
                }
                .ok_or("Migration timing projection is missing a signed-child schedule")?;
                schedule_origin
                    .checked_add(offset)
                    .ok_or("Migration projected broadcast height overflow")
                    .map(|height| {
                        let scheduled_height = if persisted_schedule_origin.is_some() {
                            height.max(proof_retry_height.unwrap_or(0))
                        } else {
                            height
                        };
                        MigrationTimingProjectedSignedPart {
                            part_index: child.part_index,
                            schedule_start_height: schedule_origin,
                            scheduled_height,
                        }
                    })
            })
            .collect::<Result<Vec<_>, _>>()?
    };
    // The send loop broadcasts one overdue transaction, then gives every
    // other overdue transaction a fresh randomized height. Until those rows
    // are persisted, an exact completion height would be misleading.
    let catch_up_schedule_pending = proof_retry_height.is_some_and(|retry_height| {
        let pending_due = pending
            .iter()
            .filter(|part| part.status == "scheduled" && part.scheduled_height <= retry_height)
            .count();
        let signed_due = projected_signed_parts
            .iter()
            .filter(|part| part.scheduled_height <= retry_height)
            .count();
        pending_due.saturating_add(signed_due) > 1
    });

    let accounted_count = pending
        .len()
        .checked_add(signed_children.len())
        .ok_or("Migration timing part count overflow")?;
    let can_estimate_completion = accounted_count == total_count as usize
        && !pending.iter().any(|part| part.status == "needs_resign")
        && !catch_up_schedule_pending;
    let estimated_completion_height = if can_estimate_completion {
        let confirmation_lag = confirmation_target.saturating_sub(1);
        let mut last_height = None;
        for part in pending {
            let completion_lag = if part.mined_height.is_some() {
                confirmation_lag
            } else {
                confirmation_target
            };
            let completion_height = part
                .mined_height
                .unwrap_or(part.scheduled_height)
                .checked_add(completion_lag)
                .ok_or("Migration confirmation height overflow")?;
            last_height = Some(last_height.map_or(completion_height, |height: u32| {
                height.max(completion_height)
            }));
        }

        if let Some(projected_broadcast_height) = projected_signed_parts
            .iter()
            .map(|part| part.scheduled_height)
            .max()
        {
            let projected_completion_height = projected_broadcast_height
                .checked_add(confirmation_target)
                .ok_or("Migration projected completion height overflow")?;
            last_height = Some(
                last_height.map_or(projected_completion_height, |height: u32| {
                    height.max(projected_completion_height)
                }),
            );
        }
        last_height
    } else {
        None
    };

    Ok(MigrationTimingProjection {
        next_action_height: next_action.map(|value| value.0),
        next_proof_window_height: proof_next.map(|value| value.0),
        next_proof_window_part_indices,
        next_action_part_index: next_action.and_then(|value| value.1),
        estimated_completion_height,
        schedule_order_by_part,
        projected_signed_parts,
    })
}

fn migration_timing_projection_or_default(
    conn: &rusqlite::Connection,
    run_id: &str,
    total_count: u32,
    confirmation_target: u32,
) -> MigrationTimingProjection {
    match migration_timing_projection_for_run(conn, run_id, total_count, confirmation_target) {
        Ok(projection) => projection,
        Err(error) => {
            log::warn!("migration: timing projection unavailable for run {run_id}: {error}");
            MigrationTimingProjection::default()
        }
    }
}

fn backfill_ready_migration_proof_retry_height(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<(), String> {
    let (phase, network, proof_retry_height) = conn
        .query_row(
            &format!(
                "SELECT phase, network, proof_retry_height
                 FROM {RUNS_TABLE}
                 WHERE run_id = ?1"
            ),
            params![run_id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<u32>>(2)?,
                ))
            },
        )
        .map_err(|e| format!("Read ready migration proof retry state: {e}"))?;
    if phase != PHASE_READY_TO_MIGRATE
        || proof_retry_height.is_some()
        || unpromoted_signed_child_pczt_count_with_conn(conn, run_id)? == 0
    {
        return Ok(());
    }

    let network = WalletNetwork::from_str(&network)
        .ok_or_else(|| format!("Unsupported migration run network: {network}"))?;
    let timing_policy = timing_policy_for_run_with_conn(conn, run_id, network)?;
    let ready_height =
        prepared_notes_proof_ready_height_with_conn(conn, run_id, network, timing_policy)?
            .ok_or("Ready migration notes are missing their canonical mined height")?;
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET proof_retry_height = ?1, updated_at_ms = ?2
             WHERE run_id = ?3 AND proof_retry_height IS NULL"
        ),
        params![ready_height, now_ms()?, run_id],
    )
    .map_err(|e| format!("Backfill ready migration proof retry height: {e}"))?;
    Ok(())
}

fn status_for_run(
    conn: &rusqlite::Connection,
    run: ActiveRun,
    current_scanned_height: u32,
) -> Result<MigrationStatus, String> {
    let network = conn
        .query_row(
            &format!("SELECT network FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run.run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration status network: {e}"))?;
    let network = WalletNetwork::from_str(&network)
        .ok_or_else(|| format!("Unsupported migration run network: {network}"))?;
    let timing_policy = timing_policy_for_run_with_conn(conn, &run.run_id, network)?;
    let preparation_timing_policy = preparation_timing_policy_for_run_with_conn(conn, &run.run_id)?;
    let prepared_note_count = count_for_run(conn, PREPARED_NOTES_TABLE, &run.run_id)?;
    let pending_split_stage_count = pending_split_stage_count_for_run(conn, &run.run_id)?;
    let pending_tx_count = count_for_run(conn, PENDING_TXS_TABLE, &run.run_id)?;
    let broadcasted_tx_count = count_pending_with_status(conn, &run.run_id, "broadcasted")?;
    let confirmed_tx_count = count_pending_with_status(conn, &run.run_id, "confirmed")?;
    let scheduled_broadcasts = scheduled_broadcasts_for_run(conn, &run.run_id)?;
    let signed_child_pczt_count = unpromoted_signed_child_pczt_count_with_conn(conn, &run.run_id)?;
    let total_count = run.target_values_zatoshi.len() as u32;
    // Completion is a durable state transition that happens only after every
    // child transaction has reached trusted depth. Never infer it from the
    // per-transaction `confirmed` marker, which means only that the child is
    // currently mined and can still be reorged before the trust threshold.
    let phase = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run.run_id],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| format!("Read durable migration phase: {e}"))?
        .unwrap_or_else(|| run.phase.clone());
    let denomination_confirmation_target = denomination_confirmations_required();
    let preparation_transactions = migration_preparation_transactions_for_run(
        conn,
        &run.run_id,
        &run.target_values_zatoshi,
        denomination_confirmation_target,
        current_scanned_height,
    )?;
    // A private-migration draft is persisted before Keystone signs its
    // denomination PCZTs. It deliberately has no staged transactions yet;
    // stage progress is only meaningful after draft finalization.
    let denomination_split_progress = if matches!(
        phase.as_str(),
        PHASE_AWAITING_PREPARATION | PHASE_AWAITING_DENOMINATION_SIGNATURE
    ) {
        DenominationSplitProgress::default()
    } else {
        denomination_split_progress_for_run(conn, &run.run_id)?
    };
    let denomination_confirmation_count = if denomination_split_progress.total_count > 0 {
        if denomination_split_progress.completed_count == denomination_split_progress.total_count {
            denomination_confirmation_target
        } else if phase == PHASE_WAITING_DENOM_CONFIRMATIONS {
            denomination_split_progress.frontier_confirmation_count
        } else {
            0
        }
    } else {
        0
    };
    // Stop is available for every active phase. The caller first drains native
    // preparation/outbox work, while the Rust operation guard excludes
    // concurrent foreground proof or broadcast work.
    let can_abandon = true;
    let mut parts = migration_parts_for_run(
        conn,
        &run.run_id,
        &run.target_values_zatoshi,
        &phase,
        denomination_confirmation_target,
    )?;
    let timing_projection = migration_timing_projection_or_default(
        conn,
        &run.run_id,
        total_count,
        denomination_confirmation_target,
    );
    for part in &mut parts {
        part.schedule_order = timing_projection
            .schedule_order_by_part
            .get(&part.part_index)
            .copied();
    }
    for projected in &timing_projection.projected_signed_parts {
        if let Some(part) = parts
            .iter_mut()
            .find(|part| part.part_index == projected.part_index)
        {
            if part.state == MigrationPartState::Preparing {
                part.schedule_start_height = Some(projected.schedule_start_height);
                part.scheduled_height = Some(projected.scheduled_height);
            }
        }
    }
    let recovery_part_indices = parts
        .iter()
        .filter(|part| part.state == MigrationPartState::NeedsInput)
        .map(|part| part.part_index)
        .collect::<Vec<_>>();
    let current_signing_part_indices = select_migration_batch_signing_part_indices(
        prepared_note_count,
        pending_tx_count,
        signed_child_pczt_count,
        &recovery_part_indices,
    )
    .unwrap_or_default();

    Ok(MigrationStatus {
        phase,
        active_run_id: Some(run.run_id),
        target_values_zatoshi: run.target_values_zatoshi,
        prepared_note_count,
        denomination_confirmation_count,
        denomination_confirmation_target,
        denomination_split_completed_count: denomination_split_progress.completed_count,
        denomination_split_total_count: denomination_split_progress.total_count,
        pending_tx_count,
        broadcasted_tx_count,
        confirmed_tx_count,
        total_count,
        signed_child_pczt_count,
        pending_split_stage_count,
        message: run.last_error,
        can_abandon,
        signing_batch_limit: MIGRATION_KEYSTONE_BATCH_MAX_PARTS,
        schedule_mean_delay_blocks: schedule_parameters_with_policy(network, timing_policy).0,
        schedule_max_delay_blocks: schedule_parameters_with_policy(network, timing_policy).1,
        preparation_mean_delay_blocks: if preparation_timing_policy
            == PreparationTimingPolicy::Immediate
        {
            0
        } else {
            preparation_schedule_parameters(network, timing_policy).0
        },
        next_action_height: timing_projection.next_action_height,
        next_proof_window_height: timing_projection.next_proof_window_height,
        next_proof_window_part_indices: timing_projection.next_proof_window_part_indices,
        estimated_completion_height: timing_projection.estimated_completion_height,
        next_action_part_index: timing_projection.next_action_part_index,
        current_signing_part_indices,
        scheduled_broadcasts,
        preparation_transactions,
        parts,
    })
}

fn migration_preparation_transactions_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
    target_values_zatoshi: &[u64],
    confirmation_target: u32,
    current_scanned_height: u32,
) -> Result<Vec<MigrationPreparationTransactionStatus>, String> {
    if !table_exists(conn, STAGES_TABLE)? {
        return Ok(Vec::new());
    }

    let chain_records = denomination_stage_chain_records(conn, run_id)?;
    let stage_index_by_txid = chain_records
        .iter()
        .map(|record| {
            (
                record.expected_txid_hex.to_ascii_lowercase(),
                record.stage_index,
            )
        })
        .collect::<BTreeMap<_, _>>();
    let mut round_by_stage = BTreeMap::<u32, u32>::new();
    for record in &chain_records {
        let parent_round = record
            .parent_txids
            .iter()
            .filter_map(|txid| stage_index_by_txid.get(&txid.to_ascii_lowercase()))
            .filter_map(|stage_index| round_by_stage.get(stage_index))
            .copied()
            .max();
        round_by_stage.insert(
            record.stage_index,
            parent_round.map_or(1, |round| round.saturating_add(1)),
        );
    }

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT s.stage_index,
                    s.scheduled_height,
                    MAX(s.scheduled_height,
                        COALESCE(s.broadcast_not_before_height, 0)),
                    s.fee_zatoshi,
                    COALESCE(SUM(i.value_zatoshi), 0)
             FROM {STAGES_TABLE} s
             LEFT JOIN {STAGE_INPUTS_TABLE} i
               ON i.run_id = s.run_id AND i.stage_index = s.stage_index
             WHERE s.run_id = ?1
             GROUP BY s.stage_index, s.scheduled_height,
                      s.broadcast_not_before_height, s.fee_zatoshi
             ORDER BY s.stage_index ASC"
        ))
        .map_err(|e| format!("Prepare migration preparation schedule query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, u32>(2)?,
                row.get::<_, u64>(3)?,
                row.get::<_, u64>(4)?,
            ))
        })
        .map_err(|e| format!("Query migration preparation schedule: {e}"))?;

    let stage_rows = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration preparation schedule: {e}"))?;
    drop(stmt);

    let planned_max_by_round =
        stage_rows
            .iter()
            .fold(BTreeMap::<u32, u32>::new(), |mut result, row| {
                let round = round_by_stage.get(&row.0).copied().unwrap_or(1);
                result
                    .entry(round)
                    .and_modify(|height| *height = (*height).max(row.1))
                    .or_insert(row.1);
                result
            });
    let mut projected_completion_by_stage = BTreeMap::<u32, u32>::new();
    let mut assigned_target_parts = BTreeSet::<u32>::new();
    let mut transactions = Vec::new();
    for (stage_index, planned_height, effective_height, fee_zatoshi, approximate_value_zatoshi) in
        stage_rows
    {
        let chain = chain_records
            .iter()
            .find(|record| record.stage_index == stage_index)
            .ok_or_else(|| {
                format!("Migration preparation stage {stage_index} has no chain-state record")
            })?;
        let (part_state, confirmation_count) =
            denomination_stage_part_state(conn, chain, confirmation_target)?;
        let state = match chain.status {
            DenominationStageStatus::AwaitingInputs => {
                MigrationPreparationTransactionState::AwaitingInputs
            }
            DenominationStageStatus::Pending => MigrationPreparationTransactionState::Scheduled,
            DenominationStageStatus::Broadcasted if confirmation_count == 0 => {
                MigrationPreparationTransactionState::Broadcasted
            }
            DenominationStageStatus::Broadcasted | DenominationStageStatus::Confirmed => {
                match part_state {
                    MigrationPartState::Completed => {
                        MigrationPreparationTransactionState::Completed
                    }
                    _ => MigrationPreparationTransactionState::Confirming,
                }
            }
        };
        let mined_height = match chain.confirmed_mined_height {
            Some(height) => Some(height),
            None => local_denomination_chain_identity(conn, &chain.expected_txid_hex)?
                .map(|identity| identity.mined_height),
        };
        let round = round_by_stage.get(&stage_index).copied().unwrap_or(1);
        let parent_projected_completion = chain
            .parent_txids
            .iter()
            .filter_map(|txid| stage_index_by_txid.get(&txid.to_ascii_lowercase()))
            .filter_map(|parent_stage| projected_completion_by_stage.get(parent_stage))
            .copied()
            .max();
        let original_round_base = if round <= 1 {
            0
        } else {
            planned_max_by_round
                .get(&round.saturating_sub(1))
                .copied()
                .unwrap_or(0)
                .saturating_add(confirmation_target)
        };
        let planned_offset = planned_height.saturating_sub(original_round_base);
        let dependency_projection = parent_projected_completion
            .map(|height| height.saturating_add(planned_offset))
            .unwrap_or(planned_height);
        // A pending stage whose operational height has passed can broadcast at
        // the current scanned tip. Once broadcast, keep this height stable
        // because the UI uses it to preserve transaction order; only its
        // completion forecast should continue moving until it is mined.
        let projected_height = effective_height.max(dependency_projection).max(
            (state == MigrationPreparationTransactionState::Scheduled)
                .then_some(current_scanned_height)
                .unwrap_or(0),
        );
        let projected_completion_height = mined_height.map_or_else(
            || {
                let projected_from_schedule = projected_height.saturating_add(confirmation_target);
                if state == MigrationPreparationTransactionState::Broadcasted {
                    projected_from_schedule
                        .max(current_scanned_height.saturating_add(confirmation_target))
                } else {
                    projected_from_schedule
                }
            },
            |height| height.saturating_add(confirmation_target.saturating_sub(1)),
        );
        projected_completion_by_stage.insert(stage_index, projected_completion_height);
        let outputs = chain
            .outputs
            .iter()
            .map(|output| MigrationPreparationOutputStatus {
                value_zatoshi: output.value_zatoshi,
                target_value_zatoshi: migration_preparation_output_target_value(
                    output,
                    target_values_zatoshi,
                    &mut assigned_target_parts,
                ),
                kind: match output.kind {
                    DenominationStageOutputKind::Migration => {
                        MigrationPreparationOutputKind::Migration
                    }
                    DenominationStageOutputKind::Change => MigrationPreparationOutputKind::Change,
                    DenominationStageOutputKind::Continuation => {
                        MigrationPreparationOutputKind::Continuation
                    }
                },
                next_round: (output.kind == DenominationStageOutputKind::Continuation)
                    .then_some(round.saturating_add(1)),
            })
            .collect();
        transactions.push(MigrationPreparationTransactionStatus {
            stage_index,
            approximate_value_zatoshi,
            round,
            fee_zatoshi,
            planned_height,
            projected_height,
            projected_completion_height,
            outputs,
            state,
            scheduled_height: (state != MigrationPreparationTransactionState::AwaitingInputs
                && effective_height > 0)
                .then_some(effective_height),
            mined_height,
            confirmation_count,
            confirmation_target,
        });
    }
    Ok(transactions)
}

fn migration_preparation_output_target_value(
    output: &DenominationStageOutputRef,
    target_values_zatoshi: &[u64],
    assigned_target_parts: &mut BTreeSet<u32>,
) -> Option<u64> {
    if output.kind != DenominationStageOutputKind::Migration {
        return None;
    }

    let part_index = output
        .part_index
        .filter(|index| {
            (*index as usize) < target_values_zatoshi.len()
                && !assigned_target_parts.contains(index)
        })
        .or_else(|| {
            target_values_zatoshi
                .iter()
                .enumerate()
                .filter_map(|(index, value)| {
                    let index = u32::try_from(index).ok()?;
                    (!assigned_target_parts.contains(&index) && *value <= output.value_zatoshi)
                        .then_some((index, *value))
                })
                .max_by_key(|(_, value)| *value)
                .map(|(index, _)| index)
        })?;
    assigned_target_parts.insert(part_index);
    target_values_zatoshi.get(part_index as usize).copied()
}

pub(crate) fn select_migration_batch_signing_part_indices(
    prepared_note_count: u32,
    pending_tx_count: u32,
    signed_child_pczt_count: u32,
    recovery_part_indices: &[u32],
) -> Result<Vec<u32>, String> {
    if !recovery_part_indices.is_empty() {
        return Ok(recovery_part_indices
            .iter()
            .copied()
            .take(MIGRATION_KEYSTONE_BATCH_MAX_PARTS as usize)
            .collect());
    }
    if prepared_note_count == 0 {
        return Err("Migration run has no prepared denomination notes".to_string());
    }
    let assigned_count = pending_tx_count
        .checked_add(signed_child_pczt_count)
        .ok_or("Migration signed transaction count overflow")?;
    if assigned_count >= prepared_note_count {
        return Err("All migration transactions are already signed and scheduled".to_string());
    }
    Ok((assigned_count
        ..prepared_note_count.min(assigned_count + MIGRATION_KEYSTONE_BATCH_MAX_PARTS))
        .collect())
}

fn migration_parts_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
    target_values: &[u64],
    phase: &str,
    confirmation_target: u32,
) -> Result<Vec<MigrationPartStatus>, String> {
    if phase == PHASE_WAITING_DENOM_CONFIRMATIONS {
        let denomination_parts =
            denomination_migration_parts_for_run(conn, run_id, target_values, confirmation_target)?;
        if !denomination_parts.is_empty() {
            return Ok(denomination_parts);
        }
    }

    let initial_state = if phase == PHASE_COMPLETE {
        MigrationPartState::Completed
    } else {
        MigrationPartState::Preparing
    };
    let mut parts = target_values
        .iter()
        .enumerate()
        .map(|(part_index, value_zatoshi)| MigrationPartStatus {
            part_index: part_index as u32,
            schedule_order: None,
            value_zatoshi: *value_zatoshi,
            state: initial_state,
            txid_hex: None,
            schedule_start_height: None,
            scheduled_height: None,
            original_scheduled_height: None,
            effective_scheduled_height: None,
            mined_height: None,
            confirmation_count: 0,
            confirmation_target,
        })
        .collect::<Vec<_>>();

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT part_index, txid_hex, value_zatoshi, fee_zatoshi,
                    COALESCE(schedule_start_height, target_height - 1),
                    scheduled_height,
                    original_scheduled_height,
                    status
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
             ORDER BY scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration part status query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, Option<u32>>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, u64>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, u32>(5)?,
                row.get::<_, Option<u32>>(6)?,
                row.get::<_, String>(7)?,
            ))
        })
        .map_err(|e| format!("Query migration part statuses: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration part statuses: {e}"))?;

    let mut assigned = BTreeSet::new();
    for (
        stored_index,
        txid_hex,
        value_zatoshi,
        fee_zatoshi,
        schedule_start_height,
        scheduled_height,
        original_scheduled_height,
        raw_status,
    ) in rows
    {
        let denomination_value = value_zatoshi.saturating_add(fee_zatoshi);
        let part_index = stored_index
            .filter(|index| (*index as usize) < parts.len() && !assigned.contains(index))
            .or_else(|| {
                parts
                    .iter()
                    .find(|part| {
                        (part.value_zatoshi == denomination_value
                            || part.value_zatoshi == value_zatoshi)
                            && !assigned.contains(&part.part_index)
                    })
                    .map(|part| part.part_index)
            })
            .or_else(|| {
                parts
                    .iter()
                    .find(|part| !assigned.contains(&part.part_index))
                    .map(|part| part.part_index)
            })
            .unwrap_or(parts.len() as u32);
        assigned.insert(part_index);

        let chain_identity = local_denomination_chain_identity(conn, &txid_hex)?;
        let mined_height = chain_identity
            .as_ref()
            .map(|identity| identity.mined_height);
        let (state, confirmation_count) = match raw_status.as_str() {
            "scheduled" => (MigrationPartState::Scheduled, 0),
            "broadcasted" => (MigrationPartState::Migrating, 0),
            "confirmed" => {
                let confirmation_count = match mined_height {
                    Some(mined_height) => synced_orchard_confirmation_count(conn, mined_height)?,
                    None => 0,
                };
                let state = if phase == PHASE_COMPLETE || confirmation_count >= confirmation_target
                {
                    MigrationPartState::Completed
                } else {
                    MigrationPartState::Confirming
                };
                (state, confirmation_count)
            }
            "needs_resign" => (MigrationPartState::NeedsInput, 0),
            _ => (MigrationPartState::Preparing, 0),
        };
        let part = MigrationPartStatus {
            part_index,
            schedule_order: None,
            value_zatoshi: parts
                .get(part_index as usize)
                .map(|part| part.value_zatoshi)
                .unwrap_or(denomination_value),
            state,
            txid_hex: Some(txid_hex),
            schedule_start_height: Some(schedule_start_height),
            scheduled_height: Some(scheduled_height),
            original_scheduled_height,
            effective_scheduled_height: Some(scheduled_height),
            mined_height,
            confirmation_count,
            confirmation_target,
        };
        if let Some(slot) = parts.get_mut(part_index as usize) {
            *slot = part;
        } else {
            parts.push(part);
        }
    }
    parts.sort_by_key(|part| part.part_index);
    Ok(parts)
}

fn denomination_migration_parts_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
    target_values: &[u64],
    confirmation_target: u32,
) -> Result<Vec<MigrationPartStatus>, String> {
    let stages = denomination_stage_chain_records(conn, run_id)?;
    if stages.is_empty() {
        return Ok(Vec::new());
    }

    let mut parts = target_values
        .iter()
        .enumerate()
        .map(|(part_index, value_zatoshi)| MigrationPartStatus {
            part_index: part_index as u32,
            schedule_order: None,
            value_zatoshi: *value_zatoshi,
            state: MigrationPartState::Preparing,
            txid_hex: None,
            schedule_start_height: None,
            scheduled_height: None,
            original_scheduled_height: None,
            effective_scheduled_height: None,
            mined_height: None,
            confirmation_count: 0,
            confirmation_target,
        })
        .collect::<Vec<_>>();
    let mut assigned = BTreeSet::new();

    for stage in stages {
        let txid_hex = stage.expected_txid_hex.to_ascii_lowercase();
        let (state, confirmation_count) =
            denomination_stage_part_state(conn, &stage, confirmation_target)?;
        let mined_height = match stage.confirmed_mined_height {
            Some(mined_height) => Some(mined_height),
            None => local_denomination_chain_identity(conn, &txid_hex)?
                .map(|identity| identity.mined_height),
        };
        for output in stage
            .outputs
            .iter()
            .filter(|output| output.kind == DenominationStageOutputKind::Migration)
        {
            let part_index = output
                .part_index
                .filter(|index| (*index as usize) < parts.len() && !assigned.contains(index))
                .or_else(|| {
                    parts
                        .iter()
                        .find(|part| {
                            part.value_zatoshi == output.value_zatoshi
                                && !assigned.contains(&part.part_index)
                        })
                        .map(|part| part.part_index)
                })
                .or_else(|| {
                    parts
                        .iter()
                        .find(|part| !assigned.contains(&part.part_index))
                        .map(|part| part.part_index)
                })
                .unwrap_or(parts.len() as u32);
            assigned.insert(part_index);

            let part = MigrationPartStatus {
                part_index,
                schedule_order: None,
                value_zatoshi: parts
                    .get(part_index as usize)
                    .map(|part| part.value_zatoshi)
                    .unwrap_or(output.value_zatoshi),
                state,
                txid_hex: Some(txid_hex.clone()),
                schedule_start_height: None,
                scheduled_height: None,
                original_scheduled_height: None,
                effective_scheduled_height: None,
                mined_height,
                confirmation_count,
                confirmation_target,
            };
            if let Some(slot) = parts.get_mut(part_index as usize) {
                *slot = part;
            } else {
                parts.push(part);
            }
        }
    }

    parts.sort_by_key(|part| part.part_index);
    Ok(parts)
}

fn denomination_stage_part_state(
    conn: &rusqlite::Connection,
    stage: &DenominationStageChainRecord,
    confirmation_target: u32,
) -> Result<(MigrationPartState, u32), String> {
    match stage.status {
        DenominationStageStatus::AwaitingInputs | DenominationStageStatus::Pending => {
            Ok((MigrationPartState::Preparing, 0))
        }
        DenominationStageStatus::Broadcasted => {
            let confirmation_count =
                denomination_stage_confirmation_count(conn, &stage.expected_txid_hex)?;
            let state = if confirmation_count == 0 {
                MigrationPartState::Migrating
            } else if confirmation_count >= confirmation_target {
                MigrationPartState::Completed
            } else {
                MigrationPartState::Confirming
            };
            Ok((state, confirmation_count))
        }
        DenominationStageStatus::Confirmed => {
            let confirmation_count = match stage.confirmed_mined_height {
                Some(mined_height) => synced_orchard_confirmation_count(conn, mined_height)?,
                None => denomination_stage_confirmation_count(conn, &stage.expected_txid_hex)?,
            };
            let state = if confirmation_count >= confirmation_target {
                MigrationPartState::Completed
            } else {
                MigrationPartState::Confirming
            };
            Ok((state, confirmation_count))
        }
    }
}

fn denomination_stage_confirmation_count(
    conn: &rusqlite::Connection,
    txid_hex: &str,
) -> Result<u32, String> {
    match local_denomination_chain_identity(conn, txid_hex)? {
        Some(identity) => synced_orchard_confirmation_count(conn, identity.mined_height),
        None => Ok(0),
    }
}

fn active_run(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<Option<ActiveRun>, String> {
    if !table_exists(conn, RUNS_TABLE)? {
        return Ok(None);
    }

    conn.query_row(
        &format!(
            "SELECT run_id, phase, target_values_json, last_error
             FROM {RUNS_TABLE}
             WHERE account_uuid = ?1
               AND network = ?2
               AND phase NOT IN ('{PHASE_NO_ORCHARD_FUNDS}', '{PHASE_COMPLETE}',
                                 '{PHASE_FAILED_TERMINAL}', '{PHASE_ABANDONED}')
             ORDER BY created_at_ms DESC
             LIMIT 1"
        ),
        params![account_uuid, network_name(network)],
        |row| {
            let target_values_json: String = row.get(2)?;
            let target_values_zatoshi =
                serde_json::from_str::<Vec<u64>>(&target_values_json).unwrap_or_default();
            Ok(ActiveRun {
                run_id: row.get(0)?,
                phase: row.get(1)?,
                target_values_zatoshi,
                last_error: row.get(3)?,
            })
        },
    )
    .optional()
    .map_err(|e| format!("Read active migration run: {e}"))
}

fn recover_latest_idempotent_broadcast_failure(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<(), String> {
    let Some((run_id, last_error)) =
        latest_idempotent_broadcast_failure(conn, account_uuid, network)?
    else {
        return Ok(());
    };

    let now = now_ms()?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin idempotent migration broadcast recovery: {e}"))?;
    let recovered = tx
        .execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                 WHERE run_id = ?3 AND phase = ?4 AND last_error = ?5"
            ),
            params![
                PHASE_BROADCAST_SCHEDULED,
                now,
                run_id,
                PHASE_FAILED_TERMINAL,
                last_error,
            ],
        )
        .map_err(|e| format!("Restore migration after duplicate broadcast response: {e}"))?;
    if recovered == 0 {
        tx.rollback()
            .map_err(|e| format!("Roll back stale migration broadcast recovery: {e}"))?;
        return Ok(());
    }
    tx.execute(
        &format!(
            "UPDATE {PREPARED_NOTES_TABLE}
             SET lock_state = 'locked'
             WHERE run_id = ?1"
        ),
        params![run_id],
    )
    .map_err(|e| format!("Restore migration note locks after duplicate broadcast: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit idempotent migration broadcast recovery: {e}"))?;
    log::info!(
        "migration: restored run {run_id} after lightwalletd reported an already accepted transaction"
    );
    Ok(())
}

fn latest_idempotent_broadcast_failure(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<Option<(String, String)>, String> {
    if !table_exists(conn, PENDING_TXS_TABLE)? || !table_exists(conn, PREPARED_NOTES_TABLE)? {
        return Ok(None);
    }

    let latest = conn
        .query_row(
            &format!(
                "SELECT run_id, phase, last_error
                 FROM {RUNS_TABLE}
                 WHERE account_uuid = ?1 AND network = ?2
                 ORDER BY created_at_ms DESC
                 LIMIT 1"
            ),
            params![account_uuid, network_name(network)],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read latest migration run for broadcast recovery: {e}"))?;
    let Some((run_id, phase, Some(last_error))) = latest else {
        return Ok(None);
    };
    if phase != PHASE_FAILED_TERMINAL
        || !super::broadcast::send_rejection_is_already_accepted(&last_error)
    {
        return Ok(None);
    }

    let scheduled_count = count_pending_with_status(conn, &run_id, "scheduled")?;
    if scheduled_count == 0 {
        return Ok(None);
    }
    Ok(Some((run_id, last_error)))
}

fn latest_completed_run(
    conn: &rusqlite::Connection,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<Option<ActiveRun>, String> {
    if !table_exists(conn, RUNS_TABLE)? {
        return Ok(None);
    }

    conn.query_row(
        &format!(
            "SELECT run_id, phase, target_values_json, last_error
             FROM {RUNS_TABLE}
             WHERE account_uuid = ?1
               AND network = ?2
               AND phase = ?3
             ORDER BY updated_at_ms DESC, created_at_ms DESC
             LIMIT 1"
        ),
        params![account_uuid, network_name(network), PHASE_COMPLETE],
        |row| {
            let target_values_json: String = row.get(2)?;
            let target_values_zatoshi =
                serde_json::from_str::<Vec<u64>>(&target_values_json).unwrap_or_default();
            Ok(ActiveRun {
                run_id: row.get(0)?,
                phase: row.get(1)?,
                target_values_zatoshi,
                last_error: row.get(3)?,
            })
        },
    )
    .optional()
    .map_err(|e| format!("Read latest completed migration run: {e}"))
}

fn reconcile_run_confirmations(conn: &rusqlite::Connection, run_id: &str) -> Result<(), String> {
    if !table_exists(conn, "transactions")? || !table_exists(conn, PENDING_TXS_TABLE)? {
        return Ok(());
    }

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, status
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
               AND status IN ('scheduled', 'broadcasted', 'confirmed')"
        ))
        .map_err(|e| format!("Prepare migration confirmation query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|e| format!("Query migration confirmation txs: {e}"))?;
    let pending = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration confirmation txs: {e}"))?;

    let now = now_ms()?;
    let mut rescheduled = false;
    for (txid_hex, status) in pending {
        match local_denomination_chain_identity(conn, &txid_hex)? {
            Some(_) if status != "confirmed" => {
                conn.execute(
                    &format!(
                        "UPDATE {PENDING_TXS_TABLE}
                         SET status = 'confirmed'
                         WHERE run_id = ?1 AND txid_hex = ?2
                           AND EXISTS (
                               SELECT 1 FROM {RUNS_TABLE}
                               WHERE run_id = ?1
                                 AND phase NOT IN (
                                     '{PHASE_COMPLETE}',
                                     '{PHASE_FAILED_TERMINAL}',
                                     '{PHASE_ABANDONED}'
                                 )
                           )"
                    ),
                    params![run_id, txid_hex],
                )
                .map_err(|e| format!("Mark migration tx confirmed: {e}"))?;
            }
            None if status == "confirmed" => {
                // A child that was mined but disappeared before trusted depth
                // must become broadcastable again. Its signed raw transaction
                // remains valid unless denomination reconciliation separately
                // determines that its selected parent changed.
                conn.execute(
                    &format!(
                        "UPDATE {PENDING_TXS_TABLE}
                         SET status = 'scheduled', scheduled_at_ms = ?1,
                             schedule_start_height = target_height,
                             scheduled_height = target_height
                         WHERE run_id = ?2 AND txid_hex = ?3
                           AND EXISTS (
                               SELECT 1 FROM {RUNS_TABLE}
                               WHERE run_id = ?2
                                 AND phase NOT IN (
                                     '{PHASE_COMPLETE}',
                                     '{PHASE_FAILED_TERMINAL}',
                                     '{PHASE_ABANDONED}'
                                 )
                           )"
                    ),
                    params![now, run_id, txid_hex],
                )
                .map_err(|e| format!("Reschedule reorged migration tx: {e}"))?;
                rescheduled = true;
            }
            _ => {}
        }
    }

    if rescheduled {
        conn.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                 WHERE run_id = ?3
                   AND phase NOT IN (
                       '{PHASE_COMPLETE}',
                       '{PHASE_FAILED_TERMINAL}',
                       '{PHASE_ABANDONED}'
                   )"
            ),
            params![PHASE_BROADCAST_SCHEDULED, now, run_id],
        )
        .map_err(|e| format!("Mark reorged migration tx broadcast scheduled: {e}"))?;
    }

    let current_phase = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration phase during confirmation reconciliation: {e}"))?;
    let unpromoted_count = unpromoted_signed_child_pczt_count_with_conn(conn, run_id)?;
    if current_phase == PHASE_WAITING_MIGRATION_CONFIRMATIONS && unpromoted_count > 0 {
        conn.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                 WHERE run_id = ?3 AND phase = ?4"
            ),
            params![
                PHASE_BROADCAST_SCHEDULED,
                now,
                run_id,
                PHASE_WAITING_MIGRATION_CONFIRMATIONS
            ],
        )
        .map_err(|e| format!("Resume incomplete migration materialization: {e}"))?;
    }

    let total_count = count_for_run(conn, PENDING_TXS_TABLE, run_id)?;
    let confirmed_count = count_pending_with_status(conn, run_id, "confirmed")?;
    if total_count > 0 && confirmed_count >= total_count {
        let planned_count = planned_part_count_with_conn(conn, run_id)?;
        if planned_count == 0 || total_count != planned_count || unpromoted_count > 0 {
            if current_phase == PHASE_WAITING_MIGRATION_CONFIRMATIONS {
                conn.execute(
                    &format!(
                        "UPDATE {RUNS_TABLE}
                         SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                         WHERE run_id = ?3 AND phase = ?4"
                    ),
                    params![
                        PHASE_BROADCAST_SCHEDULED,
                        now,
                        run_id,
                        PHASE_WAITING_MIGRATION_CONFIRMATIONS
                    ],
                )
                .map_err(|e| format!("Keep incomplete migration run materializing: {e}"))?;
            }
            return Ok(());
        }
        let mut stmt = conn
            .prepare_cached(&format!(
                "SELECT txid_hex FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 ORDER BY txid_hex ASC"
            ))
            .map_err(|e| format!("Prepare completed migration trust query: {e}"))?;
        let txids = stmt
            .query_map(params![run_id], |row| row.get::<_, String>(0))
            .map_err(|e| format!("Query completed migration trust state: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read completed migration trust state: {e}"))?;
        for txid in txids {
            let Some(identity) = local_denomination_chain_identity(conn, &txid)? else {
                return Ok(());
            };
            if synced_orchard_confirmation_count(conn, identity.mined_height)?
                < denomination_confirmations_required()
            {
                return Ok(());
            }
        }
        let now = now_ms()?;
        let completed = conn
            .execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                 WHERE run_id = ?3
                   AND phase NOT IN (
                       '{PHASE_COMPLETE}',
                       '{PHASE_FAILED_TERMINAL}',
                       '{PHASE_ABANDONED}'
                   )"
                ),
                params![PHASE_COMPLETE, now, run_id],
            )
            .map_err(|e| format!("Mark migration run complete: {e}"))?;
        if completed != 1 {
            return Ok(());
        }
        conn.execute(
            &format!(
                "UPDATE {PREPARED_NOTES_TABLE}
                 SET lock_state = 'unlocked'
                 WHERE run_id = ?1"
            ),
            params![run_id],
        )
        .map_err(|e| format!("Release migration note locks: {e}"))?;
        conn.execute(
            &format!("DELETE FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1"),
            params![run_id],
        )
        .map_err(|e| format!("Delete completed migration child PCZTs: {e}"))?;
    }

    Ok(())
}

fn reconcile_denomination_confirmations(
    conn: &rusqlite::Connection,
    run: &ActiveRun,
) -> Result<(), String> {
    if run.phase != PHASE_WAITING_DENOM_CONFIRMATIONS {
        return Ok(());
    }
    let Some(confirmed) = confirmed_prepared_denomination_notes(conn, &run.run_id)? else {
        return Ok(());
    };
    if confirmed.is_empty() {
        return Ok(());
    }

    if let Some(max_mined_height) = confirmed.iter().map(|(_, _, _, height)| *height).max() {
        if synced_orchard_confirmation_count(conn, max_mined_height)?
            < denomination_confirmations_required()
        {
            return Ok(());
        }
    }

    // Prepared-note rows cover only terminal migration outputs. A smart
    // multi-root plan can also contain an independent change-only stage, so
    // never infer that every stage is confirmed from the terminal notes.
    // Require a trusted canonical inclusion for every planned transaction.
    let mut stage_identities = Vec::new();
    for txid_hex in denomination_stage_expected_txids(conn, &run.run_id)? {
        let Some(identity) = local_denomination_chain_identity(conn, &txid_hex)? else {
            return Ok(());
        };
        if synced_orchard_confirmation_count(conn, identity.mined_height)?
            < denomination_confirmations_required()
        {
            return Ok(());
        }
        stage_identities.push((txid_hex, identity));
    }

    let network = conn
        .query_row(
            &format!("SELECT network FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run.run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read denomination run network: {e}"))?;
    let network = WalletNetwork::from_str(&network)
        .ok_or_else(|| format!("Unsupported migration run network: {network}"))?;
    let timing_policy = timing_policy_for_run_with_conn(conn, &run.run_id, network)?;
    let proof_ready_height =
        confirmed
            .iter()
            .try_fold(0u32, |ready_height, (_, _, _, mined_height)| {
                proof_ready_height_for_note_mined_height(network, timing_policy, *mined_height)
                    .map(|height| ready_height.max(height))
            })?;

    let now = now_ms()?;
    for (txid_hex, output_index, nf_hex, _) in confirmed {
        conn.execute(
            &format!(
                "UPDATE {PREPARED_NOTES_TABLE}
                 SET nullifier_hex = ?1
                 WHERE run_id = ?2 AND txid_hex = ?3 AND output_index = ?4"
            ),
            params![nf_hex, run.run_id, txid_hex, output_index],
        )
        .map_err(|e| format!("Update prepared denomination note nullifier: {e}"))?;
    }
    for (txid_hex, identity) in stage_identities {
        if let Err(error) = mark_denomination_stage_confirmed_at(
            conn,
            &run.run_id,
            &txid_hex,
            identity.mined_height,
            &identity.block_hash,
        ) {
            // The broadcast tick owns the full reorg reset because it also
            // clears and rebuilds dependent child transactions. Keep status
            // reconciliation non-fatal and leave the run waiting so that tick
            // can perform that atomic recovery path.
            if error.contains("moved to a different chain inclusion") {
                return Ok(());
            }
            return Err(error);
        }
    }
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, proof_retry_height = ?2, updated_at_ms = ?3,
                 last_error = NULL
             WHERE run_id = ?4 AND phase = ?5"
        ),
        params![
            PHASE_READY_TO_MIGRATE,
            proof_ready_height,
            now,
            run.run_id,
            PHASE_WAITING_DENOM_CONFIRMATIONS
        ],
    )
    .map_err(|e| format!("Mark denomination notes ready: {e}"))?;

    Ok(())
}

pub(crate) fn denomination_confirmations_required() -> u32 {
    ConfirmationsPolicy::default().trusted().get()
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct DenominationSplitProgress {
    frontier_confirmation_count: u32,
    completed_count: u32,
    total_count: u32,
}

fn denomination_split_progress_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<DenominationSplitProgress, String> {
    let stages = denomination_stage_chain_records(conn, run_id)?;
    if stages.is_empty() {
        return Ok(DenominationSplitProgress::default());
    }

    let total_count = u32::try_from(stages.len())
        .map_err(|_| "Denomination split stage count exceeds u32".to_string())?;
    let planned_txids = stages
        .iter()
        .map(|stage| stage.expected_txid_hex.to_ascii_lowercase())
        .collect::<BTreeSet<_>>();
    let mut confirmations_by_txid = BTreeMap::new();
    let mut trusted_txids = BTreeSet::new();
    for stage in &stages {
        let txid = stage.expected_txid_hex.to_ascii_lowercase();
        let confirmation_count = match local_denomination_chain_identity(conn, &txid)? {
            Some(identity) => synced_orchard_confirmation_count(conn, identity.mined_height)?,
            None => 0,
        };
        confirmations_by_txid.insert(txid.clone(), confirmation_count);
        if confirmation_count >= denomination_confirmations_required() {
            trusted_txids.insert(txid);
        }
    }

    let completed_count = u32::try_from(trusted_txids.len())
        .map_err(|_| "Completed denomination split stage count exceeds u32".to_string())?;
    let frontier_confirmation_count = if completed_count == total_count {
        denomination_confirmations_required()
    } else {
        // A frontier contains only incomplete stages whose planned-stage
        // parents are already trusted. Future descendants therefore do not pin
        // the visible confirmation count to zero. Independent roots can share
        // a frontier; report the least-confirmed one because every root in that
        // round still has to reach trusted depth.
        stages
            .iter()
            .filter_map(|stage| {
                let txid = stage.expected_txid_hex.to_ascii_lowercase();
                if trusted_txids.contains(&txid) {
                    return None;
                }
                let parents_trusted = stage
                    .parent_txids
                    .iter()
                    .map(|parent| parent.to_ascii_lowercase())
                    .filter(|parent| planned_txids.contains(parent))
                    .all(|parent| trusted_txids.contains(&parent));
                parents_trusted.then(|| confirmations_by_txid[&txid])
            })
            .min()
            .unwrap_or(0)
    };

    Ok(DenominationSplitProgress {
        frontier_confirmation_count,
        completed_count,
        total_count,
    })
}

fn confirmed_prepared_denomination_notes(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<Option<Vec<(String, u32, String, u32)>>, String> {
    if !table_exists(conn, "transactions")?
        || !table_exists(conn, "orchard_received_notes")?
        || !table_exists(conn, PREPARED_NOTES_TABLE)?
    {
        return Ok(None);
    }

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, output_index, value_zatoshi, note_version
             FROM {PREPARED_NOTES_TABLE}
             WHERE run_id = ?1"
        ))
        .map_err(|e| format!("Prepare denomination confirmation query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, u8>(3)?,
            ))
        })
        .map_err(|e| format!("Query denomination confirmation notes: {e}"))?;
    let notes = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read denomination confirmation notes: {e}"))?;
    if notes.is_empty() {
        return Ok(Some(Vec::new()));
    }

    let mut confirmed = Vec::with_capacity(notes.len());
    for (txid_hex, output_index, value_zatoshi, note_version) in notes {
        let mut spendable_metadata = None;
        for txid_blob in txid_blob_variants(&txid_hex)? {
            spendable_metadata = conn
                .query_row(
                    "SELECT lower(hex(n.nf)), t.mined_height
                     FROM orchard_received_notes n
                     INNER JOIN transactions t ON t.id_tx = n.transaction_id
                     WHERE t.txid = ?1
                       AND t.mined_height IS NOT NULL
                       AND n.action_index = ?2
                       AND n.value = ?3
                       AND n.note_version = ?4
                       AND n.nf IS NOT NULL
                       AND n.commitment_tree_position IS NOT NULL",
                    params![txid_blob, output_index, value_zatoshi, note_version],
                    |row| Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?)),
                )
                .optional()
                .map_err(|e| format!("Read prepared denomination note confirmation: {e}"))?;
            if spendable_metadata.is_some() {
                break;
            }
        }

        let Some((nf_hex, mined_height)) = spendable_metadata else {
            return Ok(None);
        };
        confirmed.push((txid_hex, output_index, nf_hex, mined_height));
    }

    Ok(Some(confirmed))
}

fn prepared_note_spend_metadata_available_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<bool, String> {
    Ok(matches!(
        confirmed_prepared_denomination_notes(conn, run_id)?,
        Some(notes) if !notes.is_empty()
    ))
}

fn pending_split_stage_count_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<u32, String> {
    // Keep the UI retry signal active for the full staged split lifecycle. In
    // particular, a terminal stage that has been broadcast must still trigger
    // reconciliation while it is mined, confirmed, or reorged. Once
    // reconciliation advances the run, only actionable pending or awaiting
    // stages remain part of the signal.
    let staged = denomination_stage_status_counts(conn, run_id)?;
    let waiting_for_denominations = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| format!("Read migration phase for denomination retry count: {e}"))?
        .is_some_and(|phase| phase == PHASE_WAITING_DENOM_CONFIRMATIONS);
    let staged_retry_count = if waiting_for_denominations {
        staged.total
    } else {
        staged
            .pending
            .checked_add(staged.awaiting_inputs)
            .ok_or("Pending denomination stage count overflow")?
    };
    Ok(staged_retry_count)
}

fn synced_orchard_confirmation_count(
    conn: &rusqlite::Connection,
    height: u32,
) -> Result<u32, String> {
    // Confirmation depth is local to the transaction being checked. A wallet
    // may have a recent Scanned range around this transaction while an older
    // Historic gap still exists below it; requiring the wallet-wide scanned
    // prefix would stall migration progress even though the relevant blocks
    // have already been validated. Tree checkpoints are not a scan watermark
    // because blocks with no new Orchard commitments do not create one.
    let has_fully_scanned_schema = table_exists(conn, "accounts")?
        && table_exists(conn, "scan_queue")?
        && table_exists(conn, "blocks")?;
    if has_fully_scanned_schema {
        // `10` is the persisted code for `ScanPriority::Scanned` in the
        // pinned zcash_client_sqlite schema.
        let scanned_range = conn
            .query_row(
                "SELECT block_range_start, block_range_end
                 FROM scan_queue
                 WHERE priority = 10
                   AND block_range_start <= ?1
                   AND block_range_end > ?1
                 ORDER BY block_range_end DESC
                 LIMIT 1",
                params![height],
                |row| Ok((row.get::<_, u32>(0)?, row.get::<_, u32>(1)?)),
            )
            .optional()
            .map_err(|e| format!("Read transaction scan range for migration confirmations: {e}"))?;
        let Some((range_start, range_end)) = scanned_range else {
            return Ok(0);
        };
        if range_start > height || range_end <= height {
            return Ok(0);
        }
        let scanned_through_height = range_end - 1;

        // `block_fully_scanned` finally loads metadata for the derived height.
        // Fail closed when a scan range does not retain that terminal block.
        let terminal_block_exists = conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM blocks WHERE height = ?1)",
                params![scanned_through_height],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|e| format!("Read fully scanned block for migration confirmations: {e}"))?;
        if !terminal_block_exists {
            return Ok(0);
        }

        return Ok(scanned_through_height
            .checked_sub(height)
            .map(|depth| depth.saturating_add(1))
            .unwrap_or(0)
            .min(denomination_confirmations_required()));
    }

    // Unit fixtures in this module intentionally model only the confirmation
    // metadata needed by their subject. Production wallets must never trust a
    // sparse Orchard checkpoint as a substitute for the fully scanned height.
    #[cfg(test)]
    {
        if !table_exists(conn, "orchard_tree_checkpoints")? {
            return Ok(denomination_confirmations_required());
        }

        let latest_checkpoint = conn
            .query_row(
                "SELECT MAX(checkpoint_id) FROM orchard_tree_checkpoints",
                [],
                |row| row.get::<_, Option<u32>>(0),
            )
            .map_err(|e| format!("Read latest Orchard checkpoint: {e}"))?;

        return Ok(latest_checkpoint
            .map(|checkpoint| {
                if checkpoint < height {
                    0
                } else {
                    checkpoint - height + 1
                }
            })
            .unwrap_or(0)
            .min(denomination_confirmations_required()));
    }

    #[cfg(not(test))]
    Err(
        "Wallet schema is missing accounts, scan_queue, or blocks required for migration confirmations"
            .to_string(),
    )
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct LocalTransactionChainIdentity {
    pub mined_height: u32,
    pub block_hash: [u8; 32],
}

pub(crate) fn local_denomination_chain_identity(
    conn: &rusqlite::Connection,
    txid_hex: &str,
) -> Result<Option<LocalTransactionChainIdentity>, String> {
    if !table_exists(conn, "transactions")? {
        return Ok(None);
    }
    let has_scanned_block_identity =
        table_exists(conn, "blocks")? && table_column_exists(conn, "transactions", "block")?;
    if has_scanned_block_identity {
        for txid_blob in txid_blob_variants(txid_hex)? {
            let row = conn
                .query_row(
                    "SELECT t.block, b.hash
                     FROM transactions t
                     INNER JOIN blocks b ON b.height = t.block
                     WHERE t.txid = ?1 AND t.block IS NOT NULL",
                    params![txid_blob],
                    |row| Ok((row.get::<_, u32>(0)?, row.get::<_, Vec<u8>>(1)?)),
                )
                .optional()
                .map_err(|e| format!("Read migration tx chain inclusion: {e}"))?;
            if let Some((mined_height, block_hash)) = row {
                let block_hash: [u8; 32] = block_hash.try_into().map_err(|_| {
                    "Migration denomination block hash must be 32 bytes".to_string()
                })?;
                return Ok(Some(LocalTransactionChainIdentity {
                    mined_height,
                    block_hash,
                }));
            }
        }
        return Ok(None);
    }

    // Unit fixtures in this module intentionally model only the two columns
    // needed by their subject. Production wallets always have `transactions.block`
    // and `blocks.hash`; never weaken denomination recovery to mined-height-only
    // state outside tests.
    #[cfg(test)]
    for txid_blob in txid_blob_variants(txid_hex)? {
        let mined_height = conn
            .query_row(
                "SELECT mined_height
                 FROM transactions
                 WHERE txid = ?1 AND mined_height IS NOT NULL",
                params![txid_blob],
                |row| row.get::<_, u32>(0),
            )
            .optional()
            .map_err(|e| format!("Read test migration tx chain inclusion: {e}"))?;
        if let Some(mined_height) = mined_height {
            let mut block_hash = [0u8; 32];
            for chunk in block_hash.chunks_exact_mut(4) {
                chunk.copy_from_slice(&mined_height.to_le_bytes());
            }
            return Ok(Some(LocalTransactionChainIdentity {
                mined_height,
                block_hash,
            }));
        }
    }
    #[cfg(test)]
    return Ok(None);

    #[cfg(not(test))]
    Err("Wallet schema cannot provide canonical denomination block identities".to_string())
}

pub(crate) fn local_transaction_raw(
    conn: &rusqlite::Connection,
    txid_hex: &str,
) -> Result<Option<Vec<u8>>, String> {
    if !table_exists(conn, "transactions")? || !table_column_exists(conn, "transactions", "raw")? {
        return Ok(None);
    }
    for txid_blob in txid_blob_variants(txid_hex)? {
        let raw = conn
            .query_row(
                "SELECT raw FROM transactions WHERE txid = ?1 AND raw IS NOT NULL",
                params![txid_blob],
                |row| row.get::<_, Vec<u8>>(0),
            )
            .optional()
            .map_err(|e| format!("Read migration transaction bytes: {e}"))?;
        if raw.is_some() {
            return Ok(raw);
        }
    }
    Ok(None)
}

fn txid_blob_variants(txid_hex: &str) -> Result<Vec<Vec<u8>>, String> {
    let bytes = hex::decode(txid_hex).map_err(|e| format!("Bad migration txid hex: {e}"))?;
    if bytes.len() != 32 {
        return Err("Migration txid must be 32 bytes".to_string());
    }
    let mut variants = vec![bytes.clone()];
    let mut reversed = bytes;
    reversed.reverse();
    if reversed != variants[0] {
        variants.push(reversed);
    }
    Ok(variants)
}

fn count_for_run(conn: &rusqlite::Connection, table: &str, run_id: &str) -> Result<u32, String> {
    if !table_exists(conn, table)? {
        return Ok(0);
    }
    let count = conn
        .query_row(
            &format!("SELECT COUNT(*) FROM {table} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| format!("Count migration table {table}: {e}"))?;
    u32::try_from(count).map_err(|_| "Migration count overflow".to_string())
}

fn planned_part_count_with_conn(conn: &rusqlite::Connection, run_id: &str) -> Result<u32, String> {
    let target_values_json = conn
        .query_row(
            &format!("SELECT target_values_json FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration planned part count: {e}"))?;
    let target_values = serde_json::from_str::<Vec<u64>>(&target_values_json)
        .map_err(|e| format!("Decode migration planned part count: {e}"))?;
    u32::try_from(target_values.len()).map_err(|_| "Migration part count overflow".to_string())
}

fn count_pending_with_status(
    conn: &rusqlite::Connection,
    run_id: &str,
    status: &str,
) -> Result<u32, String> {
    if !table_exists(conn, PENDING_TXS_TABLE)? {
        return Ok(0);
    }
    let count = conn
        .query_row(
            &format!("SELECT COUNT(*) FROM {PENDING_TXS_TABLE} WHERE run_id = ?1 AND status = ?2"),
            params![run_id, status],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|e| format!("Count migration pending txs: {e}"))?;
    u32::try_from(count).map_err(|_| "Migration count overflow".to_string())
}

include!("migration/schedule.rs");

include!("migration/schema.rs");

fn now_ms() -> Result<i64, String> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System clock before Unix epoch: {e}"))?;
    i64::try_from(duration.as_millis()).map_err(|_| "Timestamp overflow".to_string())
}

fn new_run_id(account_uuid: &str) -> String {
    let nonce: u64 = OsRng.gen();
    format!(
        "{account_uuid}-{}-{nonce:016x}",
        now_ms().unwrap_or_default()
    )
}

fn network_name(network: WalletNetwork) -> &'static str {
    match network {
        WalletNetwork::Main => "main",
        WalletNetwork::Test => "test",
        WalletNetwork::Regtest => "regtest",
    }
}

#[cfg(test)]
mod tests;
