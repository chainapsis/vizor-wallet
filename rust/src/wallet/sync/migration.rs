use std::collections::{BTreeMap, BTreeSet};
use std::time::{SystemTime, UNIX_EPOCH};

use rand::{rngs::OsRng, Rng};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use zcash_client_backend::data_api::wallet::ConfirmationsPolicy;
use zeroize::Zeroizing;

use crate::wallet::db::{open_readonly_conn_with_timeout, open_wallet_raw_conn_with_timeout};
use crate::wallet::keystone::ZCASH_SIGN_BATCH_MAX_MESSAGES;
use crate::wallet::network::WalletNetwork;
use crate::wallet::secret_payload;

use super::READ_DB_BUSY_TIMEOUT;

mod split_plan;
mod stages;
pub(crate) use split_plan::{
    plan_padded_denominations, SplitTerminalKind, DENOMINATION_SPLIT_ACTIONS,
};
#[allow(unused_imports)]
pub(crate) use stages::{
    all_denomination_stages_confirmed, denomination_stage_chain_records,
    denomination_stage_expected_txids, denomination_stage_status, denomination_stage_status_counts,
    denomination_stages_for_run, insert_denomination_stages_with_tx,
    locked_denomination_stage_input_outpoints, mark_denomination_stage_broadcasted,
    mark_denomination_stage_confirmed_at, pending_raw_denomination_stages,
    promote_awaiting_denomination_stage, replace_denomination_stage_confirmation_identity,
    reset_denomination_stage_exact, reset_denomination_stage_for_reorg, DenominationStage,
    DenominationStageChainRecord, DenominationStageInputRef, DenominationStageInsert,
    DenominationStageOutputKind, DenominationStageOutputRef, DenominationStageStatus,
    DenominationStageStatusCounts, PendingRawDenominationStage,
};

pub(crate) const ZATOSHIS_PER_ZEC: u64 = 100_000_000;
pub(crate) const ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI: u64 = ZATOSHIS_PER_ZEC / 100;
pub(crate) const ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI: u64 = 10_000 * ZATOSHIS_PER_ZEC;
pub(crate) const ZIP318_ANCHOR_BUCKET_MODULUS: u32 = 144;
pub(crate) const ZIP318_ANCHOR_AGE_CAP: u32 = 16;
pub(crate) const ZIP318_EXPIRY_MODULUS: u32 = 34_560;
pub(crate) const MIGRATION_BROADCAST_WINDOW_SECS: u64 = 180;
pub(crate) const MIGRATION_MAX_PREPARED_NOTES_PER_RUN: usize = 64;
pub(crate) const MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI: u64 = 1;
// Mirrors the per-child ZIP-317 migration fee estimate used by send planning:
// 3 logical actions (a 2-action padded Orchard bundle and a 1-action
// unpadded Ironwood bundle).
const MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 15_000;

const RUNS_TABLE: &str = "vizor_migration_runs";
const PREPARED_NOTES_TABLE: &str = "vizor_migration_prepared_notes";
const PENDING_TXS_TABLE: &str = "vizor_migration_pending_txs";
const SIGNED_CHILD_PCZTS_TABLE: &str = "vizor_migration_signed_child_pczts";

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
pub(crate) const PHASE_PAUSED: &str = "paused";
pub(crate) const PHASE_FAILED_RECOVERABLE: &str = "failed_recoverable";
pub(crate) const PHASE_FAILED_TERMINAL: &str = "failed_terminal";
pub(crate) const PHASE_ABANDONED: &str = "abandoned";

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DenominationPlan {
    /// Canonical ZIP 318 denominations to be emitted as Ironwood outputs.
    /// The note-preparation outputs that fund these are `denomination + fee`.
    pub migration_outputs: Vec<u64>,
    pub orchard_change: Option<u64>,
    pub split_fee_zatoshi: u64,
    pub migration_fee_zatoshi: u64,
    pub total_input_zatoshi: u64,
    pub total_migratable_zatoshi: u64,
}

pub(crate) fn plan_denominations(
    total_input_zatoshi: u64,
    split_fee_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<DenominationPlan, String> {
    if total_input_zatoshi <= split_fee_zatoshi {
        return Ok(DenominationPlan {
            migration_outputs: Vec::new(),
            orchard_change: None,
            split_fee_zatoshi: total_input_zatoshi,
            migration_fee_zatoshi,
            total_input_zatoshi,
            total_migratable_zatoshi: 0,
        });
    }

    let mut remaining = total_input_zatoshi
        .checked_sub(split_fee_zatoshi)
        .ok_or("Denomination split fee underflow")?;
    let mut outputs = Vec::new();

    while let Some(spendable_after_fee) = remaining.checked_sub(migration_fee_zatoshi) {
        let Some(denomination) = largest_zip318_denomination_at_or_below(spendable_after_fee)
        else {
            break;
        };
        outputs.push(denomination);
        if outputs.len() > MIGRATION_MAX_PREPARED_NOTES_PER_RUN {
            return Err(format!(
                "Migration plan would create {} prepared notes, above the {} note limit",
                outputs.len(),
                MIGRATION_MAX_PREPARED_NOTES_PER_RUN
            ));
        }
        remaining = remaining
            .checked_sub(denomination)
            .and_then(|value| value.checked_sub(migration_fee_zatoshi))
            .ok_or("Canonical denomination fee underflow")?;
    }

    let orchard_change = (remaining >= minimum_output_zatoshi).then_some(remaining);

    let total_migratable_zatoshi = outputs.iter().try_fold(0u64, |acc, value| {
        acc.checked_add(*value)
            .ok_or("Migratable total overflow".to_string())
    })?;

    Ok(DenominationPlan {
        migration_outputs: outputs,
        orchard_change,
        split_fee_zatoshi,
        migration_fee_zatoshi,
        total_input_zatoshi,
        total_migratable_zatoshi,
    })
}

pub(crate) fn is_zip318_canonical_denomination(value_zatoshi: u64) -> bool {
    largest_zip318_denomination_at_or_below(value_zatoshi) == Some(value_zatoshi)
}

pub(crate) fn zip318_canonical_migration_expiry_height(
    construction_height: u32,
) -> Result<u32, String> {
    let boundary = construction_height - (construction_height % ZIP318_EXPIRY_MODULUS);
    let window = ZIP318_EXPIRY_MODULUS
        .checked_mul(2)
        .ok_or_else(|| "ZIP 318 expiry window overflow".to_string())?;

    boundary
        .checked_add(window)
        .ok_or_else(|| "ZIP 318 canonical expiry height overflow".to_string())
}

fn largest_zip318_denomination_at_or_below(value_zatoshi: u64) -> Option<u64> {
    if value_zatoshi < ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI {
        return None;
    }

    let mut magnitude = ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI;
    let mut best = None;
    loop {
        for multiplier in [1u64, 2, 5] {
            let Some(denomination) = magnitude.checked_mul(multiplier) else {
                continue;
            };
            if denomination <= value_zatoshi
                && denomination <= ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI
            {
                best = Some(denomination);
            }
        }
        if magnitude >= ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI {
            break;
        }
        magnitude = magnitude.checked_mul(10)?;
    }
    best
}

pub(crate) fn zip318_anchor_boundary_at_or_before(height: u32) -> Option<u32> {
    let boundary = height - (height % ZIP318_ANCHOR_BUCKET_MODULUS);
    (boundary > 0).then_some(boundary)
}

fn zip318_anchor_boundary_age(latest_boundary: u32, anchor_boundary: u32) -> Option<u32> {
    if anchor_boundary >= latest_boundary {
        return None;
    }
    let delta = latest_boundary.checked_sub(anchor_boundary)?;
    if delta % ZIP318_ANCHOR_BUCKET_MODULUS != 0 {
        return None;
    }
    let age = delta / ZIP318_ANCHOR_BUCKET_MODULUS;
    (1..=ZIP318_ANCHOR_AGE_CAP).contains(&age).then_some(age)
}

pub(crate) fn zip318_anchor_candidate_boundaries(
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Vec<u32> {
    let Some(latest_boundary) = zip318_anchor_boundary_at_or_before(observed_anchor_height) else {
        return Vec::new();
    };
    let lower_bound = note_mined_height.max(nu6_3_activation_height.saturating_add(1));
    let mut candidates = Vec::new();
    for age in 1..=ZIP318_ANCHOR_AGE_CAP {
        let Some(distance) = age.checked_mul(ZIP318_ANCHOR_BUCKET_MODULUS) else {
            break;
        };
        let Some(boundary) = latest_boundary.checked_sub(distance) else {
            break;
        };
        if boundary < lower_bound {
            break;
        }
        candidates.push(boundary);
    }
    candidates
}

pub(crate) fn zip318_anchor_boundary_is_candidate(
    anchor_boundary: u32,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> bool {
    if anchor_boundary == 0 || anchor_boundary % ZIP318_ANCHOR_BUCKET_MODULUS != 0 {
        return false;
    }
    if anchor_boundary < note_mined_height || anchor_boundary <= nu6_3_activation_height {
        return false;
    }
    let Some(latest_boundary) = zip318_anchor_boundary_at_or_before(observed_anchor_height) else {
        return false;
    };
    zip318_anchor_boundary_age(latest_boundary, anchor_boundary).is_some()
}

pub(crate) fn zip318_draw_anchor_boundary_for_note(
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Option<u32> {
    let latest_boundary = zip318_anchor_boundary_at_or_before(observed_anchor_height)?;
    let candidates = zip318_anchor_candidate_boundaries(
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
    );
    if candidates.is_empty() {
        return None;
    }

    let mut weighted = Vec::with_capacity(candidates.len());
    let mut total_weight = 0u32;
    for boundary in candidates {
        let age = zip318_anchor_boundary_age(latest_boundary, boundary)?;
        let weight = 1u32 << (ZIP318_ANCHOR_AGE_CAP - age);
        total_weight = total_weight.checked_add(weight)?;
        weighted.push((boundary, weight));
    }

    let mut draw = OsRng.gen_range(0..total_weight);
    for (boundary, weight) in weighted {
        if draw < weight {
            return Some(boundary);
        }
        draw -= weight;
    }
    None
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub(crate) struct PreparedOrchardNoteRef {
    pub txid_hex: String,
    pub output_index: u32,
    pub value_zatoshi: u64,
    pub note_version: u8,
    pub nullifier_hex: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub(crate) struct PendingMigrationTxMetadata {
    pub tx_kind: String,
    pub funding_account_uuid: String,
    pub selected_note: PreparedOrchardNoteRef,
}

pub(crate) struct PendingMigrationTxInsert {
    pub txid_hex: String,
    pub raw_tx: Vec<u8>,
    pub target_height: u32,
    pub anchor_boundary_height: Option<u32>,
    pub expiry_height: u32,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
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
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
}

pub(crate) struct SignedMigrationPczt {
    pub base_pczt: Vec<u8>,
    /// Decoded compact spend-authorization signatures for this child (see
    /// [`SignedMigrationPcztInsert::sigs`]).
    pub sigs: Vec<pczt::roles::signer::SpendAuthSignature>,
    pub target_height: u32,
    pub anchor_boundary_height: Option<u32>,
    pub expiry_height: u32,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
}

pub(crate) struct DuePendingMigrationTx {
    pub txid_hex: String,
    pub raw_tx: Vec<u8>,
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
    pub scheduled_at_ms: i64,
    pub status: String,
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
    pub broadcast_window_seconds: u64,
    pub max_prepared_notes_per_run: u32,
    pub scheduled_broadcasts: Vec<ScheduledMigrationBroadcast>,
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
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;

    if let Some(original_run) = active_run(&conn, account_uuid, network)? {
        drop(conn);
        reconcile_denomination_stage_chain_state(db_path, &original_run.run_id)?;
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        ensure_schema(&conn)?;
        let run = active_run(&conn, account_uuid, network)?.unwrap_or(original_run);
        reconcile_denomination_confirmations(&conn, &run)?;
        reconcile_run_confirmations(&conn, &run.run_id)?;
        let run = active_run(&conn, account_uuid, network)?.unwrap_or(run);
        return status_for_run(&conn, run);
    }

    let orchard_migratable = orchard_balance_can_create_migration_output(orchard_spendable)?;
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
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        broadcast_window_seconds: MIGRATION_BROADCAST_WINDOW_SECS,
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        scheduled_broadcasts: Vec::new(),
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
    Ok(progress.total_count > 0 && progress.completed_count == progress.total_count)
}

fn orchard_balance_can_create_migration_output(orchard_spendable: u64) -> Result<bool, String> {
    if orchard_spendable == 0 {
        return Ok(false);
    }
    let plan = plan_denominations(
        orchard_spendable,
        0,
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

pub(crate) fn active_migration_run(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
) -> Result<Option<ActiveRun>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    active_run(&conn, account_uuid, network)
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
    password: &[u8],
    salt_base64: &str,
) -> Result<String, String> {
    if denomination_stages.is_empty() {
        return Err("Staged migration has no denomination transactions".to_string());
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    if let Some(run) = active_run(&conn, account_uuid, network)? {
        return Err(format!("Migration already active: {}", run.run_id));
    }

    let run_id = new_run_id(account_uuid);
    let now = now_ms()?;
    let target_values_json = serde_json::to_string(&plan.migration_outputs)
        .map_err(|e| format!("Encode migration targets: {e}"))?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin staged migration run: {e}"))?;
    tx.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase, created_at_ms,
              updated_at_ms, target_values_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7)"
        ),
        params![
            run_id,
            account_uuid,
            network_name(network),
            db_path,
            PHASE_WAITING_DENOM_CONFIRMATIONS,
            now,
            target_values_json,
        ],
    )
    .map_err(|e| format!("Create staged migration run: {e}"))?;
    insert_prepared_notes_with_tx(&tx, &run_id, prepared_notes, true)?;
    insert_denomination_stages_with_tx(&tx, &run_id, denomination_stages, password, salt_base64)?;
    insert_signed_child_pczts_with_tx(&tx, &run_id, signed_children, password, salt_base64)?;
    tx.commit()
        .map_err(|e| format!("Commit staged migration run: {e}"))?;
    Ok(run_id)
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

    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration pending insert: {e}"))?;
    insert_pending_txs_with_tx(&tx, run_id, pending_txs, password, salt_base64)?;
    tx.commit()
        .map_err(|e| format!("Commit migration pending insert: {e}"))?;
    Ok(())
}

pub(crate) fn promote_signed_child_pczts_to_pending_txs(
    db_path: &str,
    run_id: &str,
    pending_txs: Vec<PendingMigrationTxInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    if pending_txs.is_empty() {
        return Ok(());
    }

    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin signed migration PCZT promotion: {e}"))?;
    insert_pending_txs_with_tx(&tx, run_id, pending_txs, password, salt_base64)?;
    // Retain the compact signatures and base PCZTs until the run completes.
    // If a trusted denomination transaction is later reorged, the affected
    // children can be re-anchored and proved again without another Keystone
    // scan. `signed_child_pczt_count` reports only children that do not
    // currently have a pending transaction, so retaining these rows does not
    // make an already-promoted batch look unfinished.
    tx.commit()
        .map_err(|e| format!("Commit signed migration PCZT promotion: {e}"))?;
    Ok(())
}

fn insert_pending_txs_with_tx(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    pending_txs: Vec<PendingMigrationTxInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    let offsets = random_schedule_offsets(pending_txs.len());
    let scheduled_start_ms = now_ms()?;
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;

    for (pending, offset_seconds) in pending_txs.into_iter().zip(offsets.into_iter()) {
        let encrypted_raw_tx = secret_payload::encrypt_payload(
            Zeroizing::new(pending.raw_tx),
            password,
            salt.as_slice(),
        )?;
        let metadata_json = serde_json::to_string(&pending.metadata)
            .map_err(|e| format!("Encode migration pending metadata: {e}"))?;
        let scheduled_at_ms = scheduled_start_ms
            .checked_add(
                i64::try_from(offset_seconds)
                    .map_err(|_| "Migration schedule offset overflow".to_string())?
                    .saturating_mul(1000),
            )
            .ok_or("Migration scheduled time overflow")?;

        let inserted = tx
            .execute(
                &format!(
                    "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height, expiry_height,
                  anchor_boundary_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  status, metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, 'scheduled', ?13)"
                ),
                params![
                    run_id,
                    pending.txid_hex,
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

fn insert_signed_child_pczts_with_tx(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    signed_children: Vec<SignedMigrationPcztInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    if signed_children.is_empty() {
        return Ok(());
    }

    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration PCZT salt")?;
    for child in signed_children {
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
                  encrypted_compact_sigs, target_height, expiry_height,
                  anchor_boundary_height, value_zatoshi, fee_zatoshi, selected_note_json,
                  metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)"
            ),
            params![
                run_id,
                child.message_id,
                child.child_index,
                encrypted_base_pczt,
                encrypted_compact_sigs,
                child.target_height,
                child.expiry_height,
                child.anchor_boundary_height,
                child.value_zatoshi,
                child.fee_zatoshi,
                selected_note_json,
                metadata_json,
            ],
        )
        .map_err(|e| format!("Insert signed migration PCZT: {e}"))?;
    }
    Ok(())
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
            "SELECT encrypted_base_pczt, encrypted_compact_sigs,
                    target_height, expiry_height, anchor_boundary_height,
                    value_zatoshi, fee_zatoshi,
                    selected_note_json, metadata_json
             FROM {SIGNED_CHILD_PCZTS_TABLE}
             WHERE run_id = ?1
             ORDER BY child_index ASC, message_id ASC"
        ))
        .map_err(|e| format!("Prepare signed migration PCZT query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u32>(2)?,
                row.get::<_, u32>(3)?,
                row.get::<_, Option<u32>>(4)?,
                row.get::<_, u64>(5)?,
                row.get::<_, u64>(6)?,
                row.get::<_, String>(7)?,
                row.get::<_, String>(8)?,
            ))
        })
        .map_err(|e| format!("Query signed migration PCZTs: {e}"))?;

    let mut signed = Vec::new();
    for row in rows {
        let (
            encrypted_base_pczt,
            encrypted_compact_sigs,
            target_height,
            expiry_height,
            anchor_boundary_height,
            value_zatoshi,
            fee_zatoshi,
            selected_note_json,
            metadata_json,
        ) = row.map_err(|e| format!("Read signed migration PCZT: {e}"))?;
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
            base_pczt: base_pczt.to_vec(),
            sigs,
            target_height,
            anchor_boundary_height,
            expiry_height,
            value_zatoshi,
            fee_zatoshi,
            selected_note,
            metadata,
        });
    }

    Ok(signed)
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
    let pending = pending_migration_note_outpoints_with_conn(&conn, run_id)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT selected_note_json
             FROM {SIGNED_CHILD_PCZTS_TABLE}
             WHERE run_id = ?1"
        ))
        .map_err(|e| format!("Prepare signed migration PCZT count: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Query signed migration PCZT count: {e}"))?;
    let mut count = 0u32;
    for row in rows {
        let selected_note_json =
            row.map_err(|e| format!("Read signed migration PCZT count: {e}"))?;
        let note = serde_json::from_str::<PreparedOrchardNoteRef>(&selected_note_json)
            .map_err(|e| format!("Decode signed migration PCZT count note: {e}"))?;
        if !pending.contains(&(note.txid_hex.to_ascii_lowercase(), note.output_index)) {
            count = count
                .checked_add(1)
                .ok_or("Signed migration PCZT count overflow")?;
        }
    }
    Ok(count)
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
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                 WHERE run_id = ?3"
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
pub(crate) fn reconcile_denomination_stage_chain_state(
    db_path: &str,
    run_id: &str,
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

    for record in &records {
        let txid = record.expected_txid_hex.to_ascii_lowercase();
        match (record.status, current.get(&txid).and_then(Option::as_ref)) {
            (DenominationStageStatus::AwaitingInputs, Some(identity)) => {
                identities_to_record.insert(txid, identity.clone());
            }
            (
                DenominationStageStatus::Pending | DenominationStageStatus::Broadcasted,
                Some(identity),
            ) => {
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
    drop(conn);

    if !affected.is_empty() {
        // Child cleanup comes first. If the process stops before stage state is
        // updated, the unchanged identity causes this idempotent cleanup to run
        // again on the next status call.
        reset_migration_children_for_reorged_denominations(db_path, run_id, &affected)?;
    }

    if !invalid_stages.is_empty() || !identities_to_record.is_empty() {
        let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
        for txid in &invalid_stages {
            reset_denomination_stage_exact(&conn, run_id, txid)?;
        }
        for (txid, identity) in identities_to_record {
            if invalid_stages.contains(&txid) {
                continue;
            }
            replace_denomination_stage_confirmation_identity(
                &conn,
                run_id,
                &txid,
                identity.mined_height,
                &identity.block_hash,
            )?;
        }
    }

    if !affected.is_empty() {
        mark_run_phase(db_path, run_id, PHASE_WAITING_DENOM_CONFIRMATIONS, None)?;
        log::warn!(
            "migration: reconciled {} denomination transaction(s) after a chain change",
            affected.len()
        );
    }
    Ok(())
}

pub(crate) fn due_pending_txs(
    db_path: &str,
    run_id: &str,
    password: &[u8],
    salt_base64: &str,
) -> Result<Vec<DuePendingMigrationTx>, String> {
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let now = now_ms()?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, encrypted_raw_tx
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'scheduled' AND scheduled_at_ms <= ?2
             ORDER BY scheduled_at_ms ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare due migration tx query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, now], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(|e| format!("Query due migration txs: {e}"))?;

    let mut due = Vec::new();
    for row in rows {
        let (txid_hex, encrypted_raw_tx) =
            row.map_err(|e| format!("Read due migration tx: {e}"))?;
        let raw_tx = secret_payload::decrypt_payload(
            encrypted_raw_tx.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        due.push(DuePendingMigrationTx {
            txid_hex,
            raw_tx: raw_tx.to_vec(),
        });
    }
    Ok(due)
}

pub(crate) fn next_scheduled_delay_ms(db_path: &str, run_id: &str) -> Result<Option<u64>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let next_scheduled_at_ms = conn
        .query_row(
            &format!(
                "SELECT MIN(scheduled_at_ms)
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND status = 'scheduled'"
            ),
            params![run_id],
            |row| row.get::<_, Option<i64>>(0),
        )
        .map_err(|e| format!("Read next migration schedule: {e}"))?;

    let Some(next_scheduled_at_ms) = next_scheduled_at_ms else {
        return Ok(None);
    };
    let now = now_ms()?;
    if next_scheduled_at_ms <= now {
        Ok(Some(0))
    } else {
        u64::try_from(next_scheduled_at_ms - now)
            .map(Some)
            .map_err(|_| "Migration schedule delay overflow".to_string())
    }
}

pub(crate) fn mark_pending_broadcasted(
    db_path: &str,
    run_id: &str,
    txid_hex: &str,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let now = now_ms()?;
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET status = 'broadcasted'
             WHERE run_id = ?1 AND txid_hex = ?2"
        ),
        params![run_id, txid_hex],
    )
    .map_err(|e| format!("Mark pending migration tx broadcasted: {e}"))?;
    let scheduled_remaining = count_pending_with_status(&conn, run_id, "scheduled")?;
    let next_phase = if scheduled_remaining > 0 {
        PHASE_BROADCAST_SCHEDULED
    } else {
        PHASE_WAITING_MIGRATION_CONFIRMATIONS
    };
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = NULL
             WHERE run_id = ?3"
        ),
        params![next_phase, now, run_id],
    )
    .map_err(|e| format!("Mark migration waiting confirmations: {e}"))?;
    Ok(())
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
            "SELECT txid_hex, scheduled_at_ms, status
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
             ORDER BY scheduled_at_ms ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration schedule query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok(ScheduledMigrationBroadcast {
                txid_hex: row.get(0)?,
                scheduled_at_ms: row.get(1)?,
                status: row.get(2)?,
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

fn status_for_run(conn: &rusqlite::Connection, run: ActiveRun) -> Result<MigrationStatus, String> {
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
    let mut phase = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run.run_id],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| format!("Read durable migration phase: {e}"))?
        .unwrap_or_else(|| run.phase.clone());
    if phase == PHASE_READY_TO_MIGRATE
        && pending_tx_count == 0
        && prepared_note_count > 0
        && !prepared_note_spend_metadata_available_for_run(conn, &run.run_id)?
    {
        phase = PHASE_WAITING_DENOM_CONFIRMATIONS.to_string();
    }
    let denomination_confirmation_target = denomination_confirmations_required();
    let denomination_split_progress = denomination_split_progress_for_run(conn, &run.run_id)?;
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
    let can_abandon = matches!(
        phase.as_str(),
        PHASE_WAITING_DENOM_CONFIRMATIONS
            | PHASE_READY_TO_MIGRATE
            | PHASE_FAILED_RECOVERABLE
            | PHASE_PAUSED
    ) && pending_tx_count == 0;

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
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        broadcast_window_seconds: MIGRATION_BROADCAST_WINDOW_SECS,
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        scheduled_broadcasts,
    })
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
                         WHERE run_id = ?1 AND txid_hex = ?2"
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
                         SET status = 'scheduled', scheduled_at_ms = ?1
                         WHERE run_id = ?2 AND txid_hex = ?3"
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
                 WHERE run_id = ?3"
            ),
            params![PHASE_BROADCAST_SCHEDULED, now, run_id],
        )
        .map_err(|e| format!("Mark reorged migration tx broadcast scheduled: {e}"))?;
    }

    let total_count = count_for_run(conn, PENDING_TXS_TABLE, run_id)?;
    let confirmed_count = count_pending_with_status(conn, run_id, "confirmed")?;
    if total_count > 0 && confirmed_count >= total_count {
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
        conn.execute(
            &format!(
                "UPDATE {RUNS_TABLE}
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL
                 WHERE run_id = ?3"
            ),
            params![PHASE_COMPLETE, now, run_id],
        )
        .map_err(|e| format!("Mark migration run complete: {e}"))?;
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
             SET phase = ?1, updated_at_ms = ?2, last_error = NULL
             WHERE run_id = ?3"
        ),
        params![PHASE_READY_TO_MIGRATE, now, run.run_id],
    )
    .map_err(|e| format!("Mark denomination notes ready: {e}"))?;

    Ok(())
}

fn denomination_confirmations_required() -> u32 {
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
        return Err(format!(
            "Migration run {run_id} has no staged denomination transactions"
        ));
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
    // Match `zcash_client_sqlite::WalletRead::block_fully_scanned`: the
    // earliest Scanned range that begins at or before the wallet birthday is
    // contiguous through its end-exclusive upper bound. Tree checkpoints are
    // not a scan watermark because blocks with no new Orchard commitments do
    // not need to create one.
    let has_fully_scanned_schema = table_exists(conn, "accounts")?
        && table_exists(conn, "scan_queue")?
        && table_exists(conn, "blocks")?;
    if has_fully_scanned_schema {
        let wallet_birthday = conn
            .query_row("SELECT MIN(birthday_height) FROM accounts", [], |row| {
                row.get::<_, Option<u32>>(0)
            })
            .map_err(|e| format!("Read wallet birthday for migration confirmations: {e}"))?;
        let Some(wallet_birthday) = wallet_birthday else {
            return Ok(0);
        };

        // `10` is the persisted code for `ScanPriority::Scanned` in the
        // pinned zcash_client_sqlite schema.
        let scanned_range = conn
            .query_row(
                "SELECT block_range_start, block_range_end
                 FROM scan_queue
                 WHERE priority = 10
                 ORDER BY block_range_start ASC
                 LIMIT 1",
                [],
                |row| Ok((row.get::<_, u32>(0)?, row.get::<_, u32>(1)?)),
            )
            .optional()
            .map_err(|e| format!("Read fully scanned range for migration confirmations: {e}"))?;
        let Some((range_start, range_end)) = scanned_range else {
            return Ok(0);
        };
        if range_start > wallet_birthday || range_end <= range_start {
            return Ok(0);
        }
        let fully_scanned_height = range_end - 1;

        // `block_fully_scanned` finally loads metadata for the derived height.
        // Fail closed when a scan range does not retain that terminal block.
        let terminal_block_exists = conn
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM blocks WHERE height = ?1)",
                params![fully_scanned_height],
                |row| row.get::<_, bool>(0),
            )
            .map_err(|e| format!("Read fully scanned block for migration confirmations: {e}"))?;
        if !terminal_block_exists {
            return Ok(0);
        }

        return Ok(fully_scanned_height
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

pub(crate) fn random_schedule_offsets(count: usize) -> Vec<u64> {
    if count == 0 {
        return Vec::new();
    }

    let mut offsets = Vec::with_capacity(count);
    offsets.push(0);
    if count == 1 {
        return offsets;
    }

    let mean_gap_seconds = MIGRATION_BROADCAST_WINDOW_SECS as f64 / (count - 1) as f64;
    let mut elapsed_seconds = 0.0;
    for _ in 1..count {
        let sample = OsRng.gen_range(f64::EPSILON..1.0);
        elapsed_seconds += -sample.ln() * mean_gap_seconds;
        offsets.push(
            elapsed_seconds
                .round()
                .clamp(0.0, MIGRATION_BROADCAST_WINDOW_SECS as f64) as u64,
        );
    }
    offsets.sort_unstable();
    offsets
}

fn ensure_schema(conn: &rusqlite::Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "
        CREATE TABLE IF NOT EXISTS {RUNS_TABLE} (
            run_id TEXT PRIMARY KEY,
            account_uuid TEXT NOT NULL,
            network TEXT NOT NULL,
            db_fingerprint TEXT NOT NULL,
            phase TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            target_values_json TEXT NOT NULL DEFAULT '[]',
            last_error TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_migration_runs_active
            ON {RUNS_TABLE}(account_uuid, network, phase, created_at_ms);

        CREATE TABLE IF NOT EXISTS {PREPARED_NOTES_TABLE} (
            run_id TEXT NOT NULL,
            txid_hex TEXT NOT NULL,
            output_index INTEGER NOT NULL,
            value_zatoshi INTEGER NOT NULL,
            note_version INTEGER NOT NULL,
            nullifier_hex TEXT,
            lock_state TEXT NOT NULL DEFAULT 'locked',
            PRIMARY KEY (run_id, txid_hex, output_index)
        );

        CREATE TABLE IF NOT EXISTS {PENDING_TXS_TABLE} (
            run_id TEXT NOT NULL,
            txid_hex TEXT PRIMARY KEY,
            encrypted_raw_tx TEXT NOT NULL,
            target_height INTEGER NOT NULL,
            anchor_boundary_height INTEGER,
            expiry_height INTEGER NOT NULL,
            value_zatoshi INTEGER NOT NULL,
            fee_zatoshi INTEGER NOT NULL,
            selected_note_txid TEXT NOT NULL,
            selected_note_output_index INTEGER NOT NULL,
            selected_note_value INTEGER NOT NULL,
            scheduled_at_ms INTEGER NOT NULL,
            status TEXT NOT NULL,
            metadata_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_migration_pending_due
            ON {PENDING_TXS_TABLE}(status, scheduled_at_ms);

        CREATE TABLE IF NOT EXISTS {SIGNED_CHILD_PCZTS_TABLE} (
            run_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            child_index INTEGER NOT NULL,
            encrypted_base_pczt TEXT NOT NULL,
            encrypted_compact_sigs TEXT NOT NULL,
            target_height INTEGER NOT NULL,
            anchor_boundary_height INTEGER,
            expiry_height INTEGER NOT NULL,
            value_zatoshi INTEGER NOT NULL,
            fee_zatoshi INTEGER NOT NULL,
            selected_note_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            PRIMARY KEY (run_id, message_id)
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_migration_signed_child_run
            ON {SIGNED_CHILD_PCZTS_TABLE}(run_id, child_index);

        "
    ))
    .map_err(|e| format!("Initialize migration schema: {e}"))?;
    add_column_if_missing(conn, PENDING_TXS_TABLE, "anchor_boundary_height", "INTEGER")?;
    add_column_if_missing(
        conn,
        SIGNED_CHILD_PCZTS_TABLE,
        "anchor_boundary_height",
        "INTEGER",
    )?;
    stages::ensure_schema(conn)
}

fn add_column_if_missing(
    conn: &rusqlite::Connection,
    table: &str,
    column: &str,
    definition: &str,
) -> Result<(), String> {
    if !table_column_exists(conn, table, column)? {
        conn.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {definition}"),
            [],
        )
        .map_err(|e| format!("Add migration column {table}.{column}: {e}"))?;
    }
    Ok(())
}

fn table_exists(conn: &rusqlite::Connection, table: &str) -> Result<bool, String> {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
        params![table],
        |_| Ok(()),
    )
    .optional()
    .map(|row| row.is_some())
    .map_err(|e| format!("Check migration table {table}: {e}"))
}

fn table_column_exists(
    conn: &rusqlite::Connection,
    table: &str,
    column: &str,
) -> Result<bool, String> {
    conn.query_row(
        "SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2",
        params![table, column],
        |_| Ok(()),
    )
    .optional()
    .map(|row| row.is_some())
    .map_err(|e| format!("Check migration column {table}.{column}: {e}"))
}

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
mod tests {
    use super::*;

    const TEST_PASSWORD: &[u8] = b"correct horse battery staple";
    const TEST_SALT_BASE64: &str = "AQIDBAUGBwgJCgsMDQ4PEA==";

    fn pending_test_stage(expected_txid_hex: &str, raw_tx: Vec<u8>) -> DenominationStageInsert {
        DenominationStageInsert {
            stage_index: 0,
            base_pczt: vec![0xa0],
            sigs: Vec::new(),
            raw_tx: Some(raw_tx),
            expected_txid_hex: expected_txid_hex.to_string(),
            target_height: 3_000_000,
            expiry_height: 0,
            fee_zatoshi: 80_000,
            status: DenominationStageStatus::Pending,
            inputs: vec![DenominationStageInputRef {
                txid_hex: "aa".repeat(32),
                output_index: 0,
                value_zatoshi: 100_080_000,
                note_version: 2,
                nullifier_hex: Some("bb".repeat(32)),
            }],
            outputs: vec![DenominationStageOutputRef {
                output_index: 0,
                value_zatoshi: 100_000_000,
                note_version: 2,
                kind: DenominationStageOutputKind::Migration,
            }],
        }
    }

    fn insert_test_stage(
        conn: &rusqlite::Connection,
        run_id: &str,
        expected_txid_hex: &str,
        status: DenominationStageStatus,
        confirmed_mined_height: Option<u32>,
    ) {
        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(
            &tx,
            run_id,
            vec![pending_test_stage(expected_txid_hex, vec![1, 2, 3, 4])],
            TEST_PASSWORD,
            TEST_SALT_BASE64,
        )
        .unwrap();
        tx.commit().unwrap();

        match status {
            DenominationStageStatus::Pending => {
                assert!(confirmed_mined_height.is_none());
            }
            DenominationStageStatus::Broadcasted => {
                assert!(confirmed_mined_height.is_none());
                mark_denomination_stage_broadcasted(conn, run_id, expected_txid_hex).unwrap();
            }
            DenominationStageStatus::Confirmed => {
                let mined_height = confirmed_mined_height.unwrap();
                let block_hash = mined_height.to_le_bytes().repeat(8);
                mark_denomination_stage_confirmed_at(
                    conn,
                    run_id,
                    expected_txid_hex,
                    mined_height,
                    block_hash.as_slice().try_into().unwrap(),
                )
                .unwrap();
            }
            DenominationStageStatus::AwaitingInputs => {
                panic!("pending test stages cannot move backward to awaiting inputs");
            }
        }
    }

    #[test]
    fn planner_noops_when_split_fee_consumes_balance() {
        let plan = plan_denominations(5_000, 10_000, 10_000, 1).unwrap();

        assert!(plan.migration_outputs.is_empty());
        assert_eq!(plan.total_migratable_zatoshi, 0);
        assert_eq!(plan.split_fee_zatoshi, 5_000);
    }

    #[test]
    fn planner_creates_zip318_one_two_five_denominations() {
        let plan = plan_denominations(12_345_000_000, 0, 0, MINIMUM_OUTPUT_FOR_TEST).unwrap();

        assert_eq!(
            plan.migration_outputs,
            vec![
                100 * ZATOSHIS_PER_ZEC,
                20 * ZATOSHIS_PER_ZEC,
                2 * ZATOSHIS_PER_ZEC,
                ZATOSHIS_PER_ZEC,
                ZATOSHIS_PER_ZEC / 5,
                ZATOSHIS_PER_ZEC / 5,
                ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI * 5,
            ]
        );
        assert_eq!(plan.orchard_change, None);
        assert_eq!(plan.total_migratable_zatoshi, 12_345_000_000);
    }

    #[test]
    fn planner_splits_above_cap_into_multiple_cap_and_power_outputs() {
        let plan =
            plan_denominations(25_000 * ZATOSHIS_PER_ZEC, 0, 0, MINIMUM_OUTPUT_FOR_TEST).unwrap();

        assert_eq!(
            plan.migration_outputs,
            vec![
                10_000 * ZATOSHIS_PER_ZEC,
                10_000 * ZATOSHIS_PER_ZEC,
                5_000 * ZATOSHIS_PER_ZEC,
            ]
        );
    }

    #[test]
    fn planner_uses_one_two_five_digit_expansion_below_cap() {
        let plan =
            plan_denominations(540 * ZATOSHIS_PER_ZEC, 0, 0, MINIMUM_OUTPUT_FOR_TEST).unwrap();

        assert_eq!(
            plan.migration_outputs,
            vec![
                500 * ZATOSHIS_PER_ZEC,
                20 * ZATOSHIS_PER_ZEC,
                20 * ZATOSHIS_PER_ZEC,
            ]
        );
    }

    #[test]
    fn canonical_migration_expiry_uses_zip318_window_boundaries() {
        assert_eq!(ZIP318_EXPIRY_MODULUS, 34_560);
        assert_eq!(
            zip318_canonical_migration_expiry_height(3_428_143).unwrap(),
            3_490_560
        );
        assert_eq!(
            zip318_canonical_migration_expiry_height(3_455_999).unwrap(),
            3_490_560
        );
        assert_eq!(
            zip318_canonical_migration_expiry_height(3_456_000).unwrap(),
            3_525_120
        );
        assert_eq!(zip318_canonical_migration_expiry_height(0).unwrap(), 69_120);
    }

    #[test]
    fn planner_keeps_sub_max_residual_value_as_orchard_change() {
        let plan = plan_denominations(100_020_000, 0, 10_000, MINIMUM_OUTPUT_FOR_TEST).unwrap();

        assert_eq!(plan.migration_outputs, vec![100_000_000]);
        assert_eq!(plan.orchard_change, Some(10_000));
    }

    #[test]
    fn planner_reserves_split_fee_before_decomposition() {
        let plan = plan_denominations(1_000_000_000, 10_000, 10_000, 1).unwrap();

        assert!(plan
            .migration_outputs
            .iter()
            .all(|value| is_zip318_canonical_denomination(*value)));
        let prepared_total = plan
            .migration_outputs
            .iter()
            .try_fold(0u64, |sum, output| {
                sum.checked_add(*output + plan.migration_fee_zatoshi)
            })
            .unwrap()
            + plan.orchard_change.unwrap_or_default()
            + plan.split_fee_zatoshi;
        assert_eq!(prepared_total, plan.total_input_zatoshi);
    }

    #[test]
    fn planner_accepts_only_zip318_one_two_five_denominations() {
        assert!(is_zip318_canonical_denomination(
            ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI
        ));
        assert!(is_zip318_canonical_denomination(
            2 * ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI
        ));
        assert!(is_zip318_canonical_denomination(
            5 * ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI
        ));
        assert!(is_zip318_canonical_denomination(ZATOSHIS_PER_ZEC / 10));
        assert!(is_zip318_canonical_denomination(ZATOSHIS_PER_ZEC / 2));
        assert!(is_zip318_canonical_denomination(ZATOSHIS_PER_ZEC));
        assert!(is_zip318_canonical_denomination(2 * ZATOSHIS_PER_ZEC));
        assert!(is_zip318_canonical_denomination(5 * ZATOSHIS_PER_ZEC));
        assert!(is_zip318_canonical_denomination(10 * ZATOSHIS_PER_ZEC));
        assert!(is_zip318_canonical_denomination(50 * ZATOSHIS_PER_ZEC));
        assert!(is_zip318_canonical_denomination(
            ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI
        ));
        assert!(!is_zip318_canonical_denomination(
            ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI - 1
        ));
        assert!(!is_zip318_canonical_denomination(3 * ZATOSHIS_PER_ZEC));
        assert!(!is_zip318_canonical_denomination(4 * ZATOSHIS_PER_ZEC));
        assert!(!is_zip318_canonical_denomination(6 * ZATOSHIS_PER_ZEC));
        assert!(!is_zip318_canonical_denomination(
            ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI + ZATOSHIS_PER_ZEC
        ));
    }

    #[test]
    fn anchor_bucket_candidates_exclude_latest_and_pre_activation_boundaries() {
        assert_eq!(zip318_anchor_boundary_at_or_before(143), None);
        assert_eq!(zip318_anchor_boundary_at_or_before(144), Some(144));
        assert_eq!(zip318_anchor_boundary_at_or_before(5700), Some(5616));

        assert_eq!(
            zip318_anchor_candidate_boundaries(5700, 5000, 5000),
            vec![5472, 5328, 5184, 5040]
        );
        assert_eq!(
            zip318_anchor_candidate_boundaries(5700, 5600, 5000),
            Vec::<u32>::new()
        );
        assert_eq!(
            zip318_anchor_candidate_boundaries(5900, 5600, 5000),
            vec![5616]
        );

        assert!(zip318_anchor_boundary_is_candidate(5472, 5700, 5000, 5000));
        assert!(!zip318_anchor_boundary_is_candidate(5616, 5700, 5000, 5000));
        assert!(!zip318_anchor_boundary_is_candidate(4896, 5700, 1, 5000));
        assert!(!zip318_anchor_boundary_is_candidate(5500, 5700, 1, 5000));
    }

    #[test]
    fn anchor_bucket_draw_stays_within_candidate_set() {
        let candidates = zip318_anchor_candidate_boundaries(5700, 5000, 5000);
        assert!(!candidates.is_empty());

        for _ in 0..32 {
            let boundary = zip318_draw_anchor_boundary_for_note(5700, 5000, 5000).unwrap();
            assert!(candidates.contains(&boundary));
        }
        assert_eq!(zip318_draw_anchor_boundary_for_note(5700, 5600, 5000), None);
    }

    #[test]
    fn planner_rejects_more_than_max_prepared_outputs() {
        let err = plan_denominations(1_999_999_950_000_000, 0, 10_000, 1).unwrap_err();

        assert!(err.contains("above the 64 note limit"));
    }

    #[test]
    fn schedule_offsets_are_sorted_and_within_window() {
        let offsets = random_schedule_offsets(32);

        assert_eq!(offsets.len(), 32);
        assert_eq!(offsets[0], 0);
        assert!(offsets.windows(2).all(|w| w[0] <= w[1]));
        assert!(offsets
            .iter()
            .all(|offset| *offset <= MIGRATION_BROADCAST_WINDOW_SECS));
    }

    #[test]
    fn denomination_chain_identity_requires_a_scanned_block_hash() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE blocks (height INTEGER PRIMARY KEY, hash BLOB NOT NULL);
             CREATE TABLE transactions (
                 txid BLOB PRIMARY KEY,
                 block INTEGER,
                 mined_height INTEGER
             );",
        )
        .unwrap();
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        let mut stored_txid = hex::decode(txid_hex).unwrap();
        stored_txid.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, block, mined_height)
             VALUES (?1, NULL, 20)",
            params![stored_txid],
        )
        .unwrap();

        assert!(local_denomination_chain_identity(&conn, txid_hex)
            .unwrap()
            .is_none());

        let block_hash = [0xabu8; 32];
        conn.execute(
            "INSERT INTO blocks (height, hash) VALUES (20, ?1)",
            params![block_hash.as_slice()],
        )
        .unwrap();
        conn.execute("UPDATE transactions SET block = 20", [])
            .unwrap();
        assert_eq!(
            local_denomination_chain_identity(&conn, txid_hex).unwrap(),
            Some(LocalTransactionChainIdentity {
                mined_height: 20,
                block_hash,
            })
        );

        conn.execute(
            "UPDATE blocks SET hash = ?1 WHERE height = 20",
            params![vec![0xcdu8; 31]],
        )
        .unwrap();
        assert!(local_denomination_chain_identity(&conn, txid_hex)
            .unwrap_err()
            .contains("32 bytes"));
    }

    #[test]
    fn migration_status_treats_non_migratable_residual_as_complete() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();

        let status = migration_status(
            &db_path,
            WalletNetwork::Test,
            "account-1",
            MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI,
            0,
            ZATOSHIS_PER_ZEC,
            0,
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_COMPLETE);
    }

    #[test]
    fn migration_status_treats_sub_max_residual_plus_fee_as_complete() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();

        let status = migration_status(
            &db_path,
            WalletNetwork::Test,
            "account-1",
            MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI + ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI - 1,
            0,
            ZATOSHIS_PER_ZEC,
            0,
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_COMPLETE);
    }

    #[test]
    fn migration_status_keeps_completed_run_complete_with_residual_orchard() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let plan = DenominationPlan {
            migration_outputs: vec![ZATOSHIS_PER_ZEC],
            orchard_change: Some(MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI),
            split_fee_zatoshi: 10_000,
            migration_fee_zatoshi: MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI,
            total_input_zatoshi: ZATOSHIS_PER_ZEC + 20_000,
            total_migratable_zatoshi: ZATOSHIS_PER_ZEC,
        };
        let run_id = create_run_with_staged_denominations_and_signed_children(
            &db_path,
            "account-1",
            WalletNetwork::Test,
            &plan,
            &[],
            Vec::new(),
            vec![pending_test_stage(&"11".repeat(32), vec![1, 2, 3, 4])],
            TEST_PASSWORD,
            TEST_SALT_BASE64,
        )
        .unwrap();
        mark_run_phase(&db_path, &run_id, PHASE_COMPLETE, None).unwrap();

        let status = migration_status(
            &db_path,
            WalletNetwork::Test,
            "account-1",
            MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI,
            0,
            ZATOSHIS_PER_ZEC,
            0,
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_COMPLETE);
    }

    #[test]
    fn migration_status_keeps_migratable_orchard_ready_after_ironwood_exists() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();

        let status = migration_status(
            &db_path,
            WalletNetwork::Test,
            "account-1",
            MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI + ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI,
            0,
            ZATOSHIS_PER_ZEC,
            0,
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_READY_TO_PREPARE);
    }

    #[test]
    fn migration_status_waits_for_pending_orchard_before_partial_migration() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();

        let status = migration_status(
            &db_path,
            WalletNetwork::Test,
            "account-1",
            ZATOSHIS_PER_ZEC,
            ZATOSHIS_PER_ZEC,
            0,
            0,
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_WAITING_FOR_SPENDABLE_ORCHARD);
    }

    #[test]
    fn migration_status_waits_for_pending_ironwood_after_external_migration() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();

        let status = migration_status(
            &db_path,
            WalletNetwork::Test,
            "account-1",
            0,
            0,
            0,
            ZATOSHIS_PER_ZEC,
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_WAITING_FOR_IRONWOOD_SPENDABILITY);
    }

    #[test]
    fn locked_migration_note_refs_missing_wallet_db_fails_closed() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("missing-wallet.db");
        let db_path = db_path.to_string_lossy().to_string();

        let err = locked_migration_note_refs(&db_path, "account-1").unwrap_err();

        assert!(err.contains("Failed to check migration note locks"));
    }

    #[test]
    fn locked_migration_note_refs_without_migration_tables_is_empty() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        drop(rusqlite::Connection::open(&db_path).unwrap());

        let locks = locked_migration_note_refs(&db_path, "account-1").unwrap();

        assert!(locks.is_empty());
    }

    #[test]
    fn create_staged_run_persists_pending_split_atomically() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let expected_txid = "11".repeat(32);
        let raw_tx = vec![1, 2, 3, 4];
        let plan = DenominationPlan {
            migration_outputs: vec![100_000_000],
            orchard_change: None,
            split_fee_zatoshi: 80_000,
            migration_fee_zatoshi: 10_000,
            total_input_zatoshi: 100_080_000,
            total_migratable_zatoshi: 100_000_000,
        };
        let prepared_notes = vec![PreparedOrchardNoteRef {
            txid_hex: expected_txid.clone(),
            output_index: 0,
            value_zatoshi: 100_000_000,
            note_version: 2,
            nullifier_hex: None,
        }];

        let run_id = create_run_with_staged_denominations_and_signed_children(
            &db_path,
            "account-1",
            WalletNetwork::Test,
            &plan,
            &prepared_notes,
            Vec::new(),
            vec![pending_test_stage(&expected_txid, raw_tx.clone())],
            TEST_PASSWORD,
            TEST_SALT_BASE64,
        )
        .unwrap();

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let phase: String = conn
            .query_row(
                &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        let lock_state: String = conn
            .query_row(
                &format!("SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(lock_state, "locked");
        let stages =
            denomination_stages_for_run(&conn, &run_id, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();
        assert_eq!(stages.len(), 1);
        assert_eq!(stages[0].expected_txid_hex, expected_txid);
        assert_eq!(stages[0].raw_tx.as_deref(), Some(raw_tx.as_slice()));
        assert_eq!(stages[0].status, DenominationStageStatus::Pending);
    }

    #[test]
    fn create_staged_run_rolls_back_on_encrypt_failure() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let expected_txid = "11".repeat(32);
        let plan = DenominationPlan {
            migration_outputs: vec![100_000_000],
            orchard_change: None,
            split_fee_zatoshi: 80_000,
            migration_fee_zatoshi: 10_000,
            total_input_zatoshi: 100_080_000,
            total_migratable_zatoshi: 100_000_000,
        };
        let prepared_notes = vec![PreparedOrchardNoteRef {
            txid_hex: expected_txid.clone(),
            output_index: 0,
            value_zatoshi: 100_000_000,
            note_version: 2,
            nullifier_hex: None,
        }];

        let err = create_run_with_staged_denominations_and_signed_children(
            &db_path,
            "account-1",
            WalletNetwork::Test,
            &plan,
            &prepared_notes,
            Vec::new(),
            vec![pending_test_stage(&expected_txid, vec![1, 2, 3, 4])],
            TEST_PASSWORD,
            "not base64",
        )
        .unwrap_err();
        assert!(err.contains("Failed to decode migration denomination stage salt"));

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        for table in [
            RUNS_TABLE,
            PREPARED_NOTES_TABLE,
            "vizor_migration_denomination_stages",
        ] {
            let count: i64 = conn
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                    row.get(0)
                })
                .unwrap();
            assert_eq!(count, 0, "{table} should be empty after rollback");
        }
    }

    #[test]
    fn confirmation_count_uses_scanned_empty_orchard_blocks() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE accounts (birthday_height INTEGER NOT NULL);
             CREATE TABLE scan_queue (
                 block_range_start INTEGER NOT NULL,
                 block_range_end INTEGER NOT NULL,
                 priority INTEGER NOT NULL
             );
             CREATE TABLE blocks (height INTEGER PRIMARY KEY);
             CREATE TABLE orchard_tree_checkpoints (
                 checkpoint_id INTEGER PRIMARY KEY
             );
             INSERT INTO accounts (birthday_height) VALUES (20), (25);
             INSERT INTO scan_queue
                 (block_range_start, block_range_end, priority)
                 VALUES (20, 23, 10);
             INSERT INTO blocks (height) VALUES (22);
             INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (21);",
        )
        .unwrap();

        // Height 22 is fully scanned even though the last Orchard checkpoint
        // is 21 because the final block added no Orchard commitments.
        assert_eq!(synced_orchard_confirmation_count(&conn, 20).unwrap(), 3);
        assert_eq!(synced_orchard_confirmation_count(&conn, 21).unwrap(), 2);
        assert_eq!(synced_orchard_confirmation_count(&conn, 22).unwrap(), 1);
        assert_eq!(synced_orchard_confirmation_count(&conn, 23).unwrap(), 0);
    }

    #[test]
    fn confirmation_count_requires_scanned_range_to_cover_wallet_birthday() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE accounts (birthday_height INTEGER NOT NULL);
             CREATE TABLE scan_queue (
                 block_range_start INTEGER NOT NULL,
                 block_range_end INTEGER NOT NULL,
                 priority INTEGER NOT NULL
             );
             CREATE TABLE blocks (height INTEGER PRIMARY KEY);
             CREATE TABLE orchard_tree_checkpoints (
                 checkpoint_id INTEGER PRIMARY KEY
             );
             INSERT INTO accounts (birthday_height) VALUES (20), (25);
             INSERT INTO scan_queue
                 (block_range_start, block_range_end, priority)
                 VALUES (21, 24, 10), (24, 30, 10);
             INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (100);",
        )
        .unwrap();

        // A gap after the earliest account birthday means there is no fully
        // scanned height, regardless of later ranges or tree checkpoints.
        assert_eq!(synced_orchard_confirmation_count(&conn, 21).unwrap(), 0);
    }

    #[test]
    fn confirmation_count_requires_fully_scanned_terminal_block() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE accounts (birthday_height INTEGER NOT NULL);
             CREATE TABLE scan_queue (
                 block_range_start INTEGER NOT NULL,
                 block_range_end INTEGER NOT NULL,
                 priority INTEGER NOT NULL
             );
             CREATE TABLE blocks (height INTEGER PRIMARY KEY);
             CREATE TABLE orchard_tree_checkpoints (
                 checkpoint_id INTEGER PRIMARY KEY
             );
             INSERT INTO accounts (birthday_height) VALUES (20);
             INSERT INTO scan_queue
                 (block_range_start, block_range_end, priority)
                 VALUES (20, 23, 10);
             INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (100);",
        )
        .unwrap();

        assert_eq!(synced_orchard_confirmation_count(&conn, 20).unwrap(), 0);
    }

    #[test]
    fn confirmation_count_retains_checkpoint_fallback_for_minimal_schema() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        conn.execute(
            "CREATE TABLE orchard_tree_checkpoints (checkpoint_id INTEGER PRIMARY KEY)",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (21)",
            [],
        )
        .unwrap();

        assert_eq!(synced_orchard_confirmation_count(&conn, 20).unwrap(), 2);
    }

    #[test]
    fn confirmation_reconciliation_completes_run_and_releases_locks() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            "CREATE TABLE transactions (txid BLOB PRIMARY KEY, mined_height INTEGER)",
            [],
        )
        .unwrap();

        let run_id = "run-1";
        let denomination_txid_hex = "11".repeat(32);
        let child_txid_hex =
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f".to_string();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1, 1, ?6)"
            ),
            params![
                run_id,
                "account-1",
                "test",
                "db",
                PHASE_WAITING_MIGRATION_CONFIRMATIONS,
                "[100000000]",
            ],
        )
        .unwrap();
        insert_test_stage(
            &conn,
            run_id,
            &denomination_txid_hex,
            DenominationStageStatus::Confirmed,
            Some(17),
        );
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 0, 100000000, 2, NULL, 'locked')"
            ),
            params![run_id, denomination_txid_hex],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height,
                  expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value,
                  scheduled_at_ms, status, metadata_json)
                 VALUES (?1, ?2, 'encrypted', 10, 30, 99990000, 10000,
                         ?3, 0, 100000000, 1, 'broadcasted', '{{}}')"
            ),
            params![run_id, child_txid_hex, denomination_txid_hex],
        )
        .unwrap();

        for (txid_hex, mined_height) in [(&denomination_txid_hex, 17), (&child_txid_hex, 20)] {
            let mut txid_blob = hex::decode(txid_hex).unwrap();
            txid_blob.reverse();
            conn.execute(
                "INSERT INTO transactions (txid, mined_height) VALUES (?1, ?2)",
                params![txid_blob, mined_height],
            )
            .unwrap();
        }

        reconcile_run_confirmations(&conn, run_id).unwrap();
        let status = status_for_run(
            &conn,
            ActiveRun {
                run_id: run_id.to_string(),
                phase: PHASE_WAITING_MIGRATION_CONFIRMATIONS.to_string(),
                target_values_zatoshi: vec![100_000_000],
                last_error: None,
            },
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_COMPLETE);
        assert_eq!(status.confirmed_tx_count, 1);
        let lock_state: String = conn
            .query_row(
                &format!("SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(lock_state, "unlocked");
    }

    #[test]
    fn confirmation_reconciliation_requeues_child_reorged_before_trusted_depth() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            "CREATE TABLE transactions (txid BLOB PRIMARY KEY, mined_height INTEGER)",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_tree_checkpoints (checkpoint_id INTEGER PRIMARY KEY)",
            [],
        )
        .unwrap();

        let run_id = "run-pre-trust-reorg";
        let denomination_txid_hex = "11".repeat(32);
        let child_txid_hex =
            "101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f".to_string();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, PHASE_WAITING_MIGRATION_CONFIRMATIONS],
        )
        .unwrap();
        insert_test_stage(
            &conn,
            run_id,
            &denomination_txid_hex,
            DenominationStageStatus::Confirmed,
            Some(17),
        );
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 0, 100000000, 2, NULL, 'locked')"
            ),
            params![run_id, denomination_txid_hex],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height,
                  expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value,
                  scheduled_at_ms, status, metadata_json)
                 VALUES (?1, ?2, 'encrypted', 10, 30, 99990000, 10000,
                         ?3, 0, 100000000, 1, 'broadcasted', '{{}}')"
            ),
            params![run_id, child_txid_hex, denomination_txid_hex],
        )
        .unwrap();

        let mut denomination_txid_blob = hex::decode(&denomination_txid_hex).unwrap();
        denomination_txid_blob.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height) VALUES (?1, 17)",
            params![denomination_txid_blob],
        )
        .unwrap();
        let mut child_txid_blob = hex::decode(&child_txid_hex).unwrap();
        child_txid_blob.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height) VALUES (?1, 20)",
            params![child_txid_blob],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (20)",
            [],
        )
        .unwrap();

        let stale_run = ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_WAITING_MIGRATION_CONFIRMATIONS.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: None,
        };

        reconcile_run_confirmations(&conn, run_id).unwrap();
        let status = status_for_run(&conn, stale_run.clone()).unwrap();
        assert_eq!(status.phase, PHASE_WAITING_MIGRATION_CONFIRMATIONS);
        assert_eq!(status.confirmed_tx_count, 1);
        let lock_state: String = conn
            .query_row(
                &format!("SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(lock_state, "locked");

        conn.execute(
            "UPDATE transactions SET mined_height = NULL WHERE txid = ?1",
            params![child_txid_blob],
        )
        .unwrap();
        reconcile_run_confirmations(&conn, run_id).unwrap();

        let (pending_status, scheduled_at_ms): (String, i64) = conn
            .query_row(
                &format!(
                    "SELECT status, scheduled_at_ms
                     FROM {PENDING_TXS_TABLE} WHERE run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(pending_status, "scheduled");
        assert!(scheduled_at_ms > 1);

        let status = status_for_run(&conn, stale_run).unwrap();
        assert_eq!(status.phase, PHASE_BROADCAST_SCHEDULED);
        assert_eq!(status.confirmed_tx_count, 0);
        let lock_state: String = conn
            .query_row(
                &format!("SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(lock_state, "locked");
    }

    #[test]
    fn denomination_reconciliation_marks_confirmed_notes_ready_to_migrate() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            "CREATE TABLE transactions (
                id_tx INTEGER PRIMARY KEY,
                txid BLOB NOT NULL,
                mined_height INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_received_notes (
                transaction_id INTEGER NOT NULL,
                action_index INTEGER NOT NULL,
                value INTEGER NOT NULL,
                note_version INTEGER NOT NULL,
                nf BLOB,
                commitment_tree_position INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_tree_checkpoints (
                checkpoint_id INTEGER PRIMARY KEY,
                position INTEGER
             )",
            [],
        )
        .unwrap();

        let run_id = "run-1";
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1, 1, ?6)"
            ),
            params![
                run_id,
                "account-1",
                "test",
                "db",
                PHASE_WAITING_DENOM_CONFIRMATIONS,
                "[100000000]",
            ],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 0, 100000000, 2, NULL, 'locked')"
            ),
            params![run_id, txid_hex],
        )
        .unwrap();

        let mut txid_blob = hex::decode(txid_hex).unwrap();
        txid_blob.reverse();
        let nf = vec![0xabu8; 32];
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (1, ?1, 20)",
            params![txid_blob],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes
             (transaction_id, action_index, value, note_version, nf, commitment_tree_position)
             VALUES (1, 0, 100000000, 2, ?1, 0)",
            params![nf],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id, position) VALUES (22, 0)",
            [],
        )
        .unwrap();
        let independent_txid_hex = "11".repeat(32);
        for (stage_index, expected_txid_hex) in
            [(0, txid_hex.to_string()), (1, independent_txid_hex.clone())]
        {
            conn.execute(
                "INSERT INTO vizor_migration_denomination_stages
                 (run_id, stage_index, encrypted_base_pczt,
                  encrypted_compact_sigs, encrypted_raw_tx,
                  expected_txid_hex, target_height, expiry_height,
                  fee_zatoshi, status)
                 VALUES (?1, ?2, 'base', 'sigs', 'raw', ?3, 10, 0,
                         80000, 'broadcasted')",
                params![run_id, stage_index, expected_txid_hex],
            )
            .unwrap();
        }

        let run = ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_WAITING_DENOM_CONFIRMATIONS.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: None,
        };
        reconcile_denomination_confirmations(&conn, &run).unwrap();

        let phase: String = conn
            .query_row(
                &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);

        let mut independent_txid_blob = hex::decode(&independent_txid_hex).unwrap();
        independent_txid_blob.reverse();
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (2, ?1, 20)",
            params![independent_txid_blob],
        )
        .unwrap();
        reconcile_denomination_confirmations(&conn, &run).unwrap();

        let phase: String = conn
            .query_row(
                &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(phase, PHASE_READY_TO_MIGRATE);
        let nullifier_hex: String = conn
            .query_row(
                &format!("SELECT nullifier_hex FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(nullifier_hex, "ab".repeat(32));
        assert!(all_denomination_stages_confirmed(&conn, run_id).unwrap());
    }

    #[test]
    fn status_waits_for_spend_metadata_before_presigned_child_finalization() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            "CREATE TABLE transactions (
                id_tx INTEGER PRIMARY KEY,
                txid BLOB NOT NULL,
                mined_height INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_received_notes (
                transaction_id INTEGER NOT NULL,
                action_index INTEGER NOT NULL,
                value INTEGER NOT NULL,
                note_version INTEGER NOT NULL,
                nf BLOB,
                commitment_tree_position INTEGER
             )",
            [],
        )
        .unwrap();

        let run_id = "run-presigned";
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1, 1, ?6)"
            ),
            params![
                run_id,
                "account-1",
                "test",
                "db",
                PHASE_READY_TO_MIGRATE,
                "[100000000]",
            ],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 0, 100000000, 2, ?3, 'locked')"
            ),
            params![run_id, txid_hex, "ab".repeat(32)],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stages
             (run_id, stage_index, encrypted_base_pczt, encrypted_compact_sigs,
              encrypted_raw_tx, expected_txid_hex, target_height, expiry_height,
              fee_zatoshi, confirmed_mined_height, confirmed_block_hash, status)
             VALUES (?1, 0, 'base', 'sigs', 'raw', ?2, 10, 0, 80000,
                     20, ?3, 'confirmed')",
            params![run_id, txid_hex, 20u32.to_le_bytes().repeat(8)],
        )
        .unwrap();

        let mut txid_blob = hex::decode(txid_hex).unwrap();
        txid_blob.reverse();
        let nf = vec![0xabu8; 32];
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (1, ?1, 20)",
            params![txid_blob],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes
             (transaction_id, action_index, value, note_version, nf,
              commitment_tree_position)
             VALUES (1, 0, 100000000, 2, ?1, NULL)",
            params![nf],
        )
        .unwrap();

        let run = ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_READY_TO_MIGRATE.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: None,
        };
        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert_eq!(status.signed_child_pczt_count, 0);
        assert_eq!(status.pending_split_stage_count, 0);

        let selected_note_json = serde_json::to_string(&PreparedOrchardNoteRef {
            txid_hex: txid_hex.to_string(),
            output_index: 0,
            value_zatoshi: 100_000_000,
            note_version: 2,
            nullifier_hex: Some("ab".repeat(32)),
        })
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_compact_sigs, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
                 VALUES (?1, 'migration-1', 0, 'base', 'signed', 10, 20,
                         99980000, 20000, ?2, '{{}}')"
            ),
            params![run_id, selected_note_json],
        )
        .unwrap();

        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert_eq!(status.signed_child_pczt_count, 1);
        assert_eq!(status.pending_split_stage_count, 0);

        conn.execute(
            "UPDATE orchard_received_notes SET commitment_tree_position = 0",
            [],
        )
        .unwrap();

        let status = status_for_run(&conn, run).unwrap();
        assert_eq!(status.phase, PHASE_READY_TO_MIGRATE);
        assert_eq!(status.pending_split_stage_count, 0);
    }

    #[test]
    fn terminal_denomination_stage_keeps_retry_signal_until_run_is_ready() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        let run_id = "run-terminal-stage";
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, PHASE_WAITING_DENOM_CONFIRMATIONS],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stages
             (run_id, stage_index, encrypted_base_pczt, encrypted_compact_sigs,
              encrypted_raw_tx, expected_txid_hex, target_height, expiry_height,
              fee_zatoshi, status)
             VALUES (?1, 0, 'base', 'sigs', 'raw', ?2, 10, 0, 80000,
                     'broadcasted')",
            params![run_id, "11".repeat(32)],
        )
        .unwrap();

        assert_eq!(pending_split_stage_count_for_run(&conn, run_id).unwrap(), 1);
        mark_denomination_stage_confirmed_at(&conn, run_id, &"11".repeat(32), 20, &[0xabu8; 32])
            .unwrap();
        assert_eq!(pending_split_stage_count_for_run(&conn, run_id).unwrap(), 1);

        conn.execute(
            &format!("UPDATE {RUNS_TABLE} SET phase = ?1 WHERE run_id = ?2"),
            params![PHASE_READY_TO_MIGRATE, run_id],
        )
        .unwrap();
        assert_eq!(pending_split_stage_count_for_run(&conn, run_id).unwrap(), 0);
    }

    #[test]
    fn broadcast_scheduled_staged_run_requires_trusted_depth_and_preserves_phase() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE blocks (height INTEGER PRIMARY KEY, hash BLOB NOT NULL);
             CREATE TABLE transactions (
                 txid BLOB PRIMARY KEY,
                 block INTEGER,
                 mined_height INTEGER
             );
             CREATE TABLE orchard_tree_checkpoints (
                 checkpoint_id INTEGER PRIMARY KEY
             );",
        )
        .unwrap();

        let run_id = "run-broadcast-scheduled";
        let denomination_txid = "11".repeat(32);
        let mined_height = 20;
        let block_hash = [0xabu8; 32];
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', ?2, ?3, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, db_path, PHASE_BROADCAST_SCHEDULED],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO blocks (height, hash) VALUES (?1, ?2)",
            params![mined_height, block_hash.as_slice()],
        )
        .unwrap();
        let mut stored_txid = hex::decode(&denomination_txid).unwrap();
        stored_txid.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, block, mined_height)
             VALUES (?1, ?2, ?2)",
            params![stored_txid, mined_height],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stages
             (run_id, stage_index, encrypted_base_pczt, encrypted_compact_sigs,
              encrypted_raw_tx, expected_txid_hex, target_height, expiry_height,
              fee_zatoshi, status)
             VALUES (?1, 0, 'base', 'sigs', 'raw', ?2, 10, 0, 80000,
                     'broadcasted')",
            params![run_id, denomination_txid],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (?1)",
            params![mined_height + 1],
        )
        .unwrap();
        drop(conn);

        // A canonical identity changes the durable stage status to confirmed,
        // but two confirmations are still below trusted depth.
        assert!(!reconcile_denomination_run(db_path, run_id).unwrap());

        let conn = rusqlite::Connection::open(db_path).unwrap();
        assert!(all_denomination_stages_confirmed(&conn, run_id).unwrap());
        let phase: String = conn
            .query_row(
                &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(phase, PHASE_BROADCAST_SCHEDULED);

        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (?1)",
            params![mined_height + 2],
        )
        .unwrap();
        drop(conn);

        // `advance_staged_denomination_run` treats this readiness result as the
        // gate to `broadcast_due_scheduled_migration_txs`.
        assert!(reconcile_denomination_run(db_path, run_id).unwrap());

        let conn = rusqlite::Connection::open(db_path).unwrap();
        let phase: String = conn
            .query_row(
                &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(phase, PHASE_BROADCAST_SCHEDULED);
    }

    #[test]
    fn denomination_reorg_restores_affected_presigned_child() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        ensure_schema(&conn).unwrap();
        let run_id = "run-reorg-child";
        let denomination_txid = "11".repeat(32);
        let child_txid = "22".repeat(32);
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', ?2, ?3, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, db_path, PHASE_BROADCAST_SCHEDULED],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 7, 100000000, 2, ?3, 'unlocked')"
            ),
            params![run_id, denomination_txid, "ab".repeat(32)],
        )
        .unwrap();
        let selected_note_json = serde_json::to_string(&PreparedOrchardNoteRef {
            txid_hex: denomination_txid.clone(),
            output_index: 7,
            value_zatoshi: 100_000_000,
            note_version: 2,
            nullifier_hex: Some("ab".repeat(32)),
        })
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_compact_sigs, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
                 VALUES (?1, 'migration-1', 0, 'base', 'sigs', 10, 20,
                         99980000, 20000, ?2, '{{}}')"
            ),
            params![run_id, selected_note_json],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height,
                  expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value,
                  scheduled_at_ms, status, metadata_json)
                 VALUES (?1, ?2, 'raw', 10, 20, 99980000, 20000, ?3,
                         7, 100000000, 1, 'scheduled', '{{}}')"
            ),
            params![run_id, child_txid, denomination_txid],
        )
        .unwrap();
        drop(conn);

        assert_eq!(signed_child_pczt_count(db_path, run_id).unwrap(), 0);
        reset_migration_children_for_reorged_denominations(
            db_path,
            run_id,
            &BTreeSet::from([denomination_txid.clone()]),
        )
        .unwrap();
        assert_eq!(signed_child_pczt_count(db_path, run_id).unwrap(), 1);

        let conn = rusqlite::Connection::open(db_path).unwrap();
        let retained_signed: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        let pending: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {PENDING_TXS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        let (phase, nullifier, lock_state): (String, Option<String>, String) = conn
            .query_row(
                &format!(
                    "SELECT r.phase, n.nullifier_hex, n.lock_state
                     FROM {RUNS_TABLE} r
                     JOIN {PREPARED_NOTES_TABLE} n ON n.run_id = r.run_id
                     WHERE r.run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(retained_signed, 1);
        assert_eq!(pending, 0);
        assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert!(nullifier.is_none());
        assert_eq!(lock_state, "locked");
    }

    #[test]
    fn reorged_awaiting_stage_accepts_canonical_reinclusion() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE blocks (height INTEGER PRIMARY KEY, hash BLOB NOT NULL);
             CREATE TABLE transactions (
                 txid BLOB PRIMARY KEY,
                 block INTEGER,
                 mined_height INTEGER
             );",
        )
        .unwrap();

        let run_id = "run-reincluded-awaiting";
        let denomination_txid = "11".repeat(32);
        let block_hash = [0xabu8; 32];
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', ?2, ?3, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, db_path, PHASE_WAITING_DENOM_CONFIRMATIONS],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO blocks (height, hash) VALUES (20, ?1)",
            params![block_hash.as_slice()],
        )
        .unwrap();
        let mut stored_txid = hex::decode(&denomination_txid).unwrap();
        stored_txid.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, block, mined_height)
             VALUES (?1, 20, 20)",
            params![stored_txid],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stages
             (run_id, stage_index, encrypted_base_pczt, encrypted_compact_sigs,
              encrypted_raw_tx, expected_txid_hex, target_height, expiry_height,
              fee_zatoshi, status)
             VALUES (?1, 0, 'base', 'sigs', NULL, ?2, 10, 0, 80000,
                     'awaiting_inputs')",
            params![run_id, denomination_txid],
        )
        .unwrap();
        drop(conn);

        reconcile_denomination_stage_chain_state(db_path, run_id).unwrap();

        let conn = rusqlite::Connection::open(db_path).unwrap();
        let (status, mined_height, stored_hash, raw_tx): (
            String,
            Option<u32>,
            Option<Vec<u8>>,
            Option<String>,
        ) = conn
            .query_row(
                "SELECT status, confirmed_mined_height, confirmed_block_hash,
                        encrypted_raw_tx
                 FROM vizor_migration_denomination_stages
                 WHERE run_id = ?1",
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!(status, "confirmed");
        assert_eq!(mined_height, Some(20));
        assert_eq!(stored_hash.as_deref(), Some(block_hash.as_slice()));
        assert!(raw_tx.is_none());
    }

    #[test]
    fn status_reconciliation_preserves_reincluded_parent_and_resets_offchain_dependents() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE blocks (height INTEGER PRIMARY KEY, hash BLOB NOT NULL);
             CREATE TABLE transactions (
                 txid BLOB PRIMARY KEY,
                 block INTEGER,
                 mined_height INTEGER
             );",
        )
        .unwrap();

        let run_id = "run-status-reorg";
        let root_txid = "11".repeat(32);
        let descendant_txid = "22".repeat(32);
        let independent_txid = "33".repeat(32);
        let migration_child_txid = "44".repeat(32);
        let old_root_hash = [0xa1u8; 32];
        let new_root_hash = [0xb2u8; 32];
        let independent_hash = [0xc3u8; 32];
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', ?2, ?3, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, db_path, PHASE_BROADCAST_SCHEDULED],
        )
        .unwrap();
        for (height, hash) in [(20, new_root_hash), (21, independent_hash)] {
            conn.execute(
                "INSERT INTO blocks (height, hash) VALUES (?1, ?2)",
                params![height, hash.as_slice()],
            )
            .unwrap();
        }
        for (txid, height) in [(&root_txid, 20), (&independent_txid, 21)] {
            let mut blob = hex::decode(txid).unwrap();
            blob.reverse();
            conn.execute(
                "INSERT INTO transactions (txid, block, mined_height)
                 VALUES (?1, ?2, ?2)",
                params![blob, height],
            )
            .unwrap();
        }

        for (stage_index, txid, height, hash) in [
            (0, &root_txid, 20, old_root_hash),
            (1, &descendant_txid, 19, [0xd4u8; 32]),
            (2, &independent_txid, 21, independent_hash),
        ] {
            conn.execute(
                "INSERT INTO vizor_migration_denomination_stages
                 (run_id, stage_index, encrypted_base_pczt,
                  encrypted_compact_sigs, encrypted_raw_tx,
                  expected_txid_hex, target_height, expiry_height,
                  fee_zatoshi, confirmed_mined_height,
                  confirmed_block_hash, status)
                 VALUES (?1, ?2, 'base', 'sigs', 'raw', ?3, 10, 0,
                         80000, ?4, ?5, 'confirmed')",
                params![run_id, stage_index, txid, height, hash.as_slice()],
            )
            .unwrap();
        }
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stage_inputs
             (run_id, stage_index, input_order, txid_hex, output_index,
              value_zatoshi, note_version, nullifier_hex)
             VALUES (?1, 1, 0, ?2, 0, 100080000, 2, NULL)",
            params![run_id, root_txid],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 7, 100000000, 2, ?3, 'unlocked')"
            ),
            params![run_id, root_txid, "ab".repeat(32)],
        )
        .unwrap();
        let selected_note_json = serde_json::to_string(&PreparedOrchardNoteRef {
            txid_hex: root_txid.clone(),
            output_index: 7,
            value_zatoshi: 100_000_000,
            note_version: 2,
            nullifier_hex: Some("ab".repeat(32)),
        })
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_compact_sigs, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
                 VALUES (?1, 'migration-1', 0, 'base', 'sigs', 10, 20,
                         99980000, 20000, ?2, '{{}}')"
            ),
            params![run_id, selected_note_json],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height,
                  expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value,
                  scheduled_at_ms, status, metadata_json)
                 VALUES (?1, ?2, 'raw', 10, 20, 99980000, 20000, ?3,
                         7, 100000000, 1, 'broadcasted', '{{}}')"
            ),
            params![run_id, migration_child_txid, root_txid],
        )
        .unwrap();
        drop(conn);

        let status =
            migration_status(db_path, WalletNetwork::Test, "account-1", 0, 0, 0, 0).unwrap();
        assert_eq!(status.phase, PHASE_WAITING_DENOM_CONFIRMATIONS);

        let conn = rusqlite::Connection::open(db_path).unwrap();
        let stage_rows = conn
            .prepare(
                "SELECT expected_txid_hex, status, encrypted_raw_tx,
                        confirmed_block_hash
                 FROM vizor_migration_denomination_stages
                 WHERE run_id = ?1 ORDER BY stage_index",
            )
            .unwrap()
            .query_map(params![run_id], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, Option<Vec<u8>>>(3)?,
                ))
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(stage_rows[0].0, root_txid);
        assert_eq!(stage_rows[0].1, "confirmed");
        assert_eq!(stage_rows[0].2.as_deref(), Some("raw"));
        assert_eq!(stage_rows[0].3, Some(new_root_hash.to_vec()));
        assert_eq!(stage_rows[1].0, descendant_txid);
        assert_eq!(stage_rows[1].1, "awaiting_inputs");
        assert!(stage_rows[1].2.is_none());
        assert_eq!(stage_rows[2].0, independent_txid);
        assert_eq!(stage_rows[2].1, "confirmed");
        assert_eq!(stage_rows[2].2.as_deref(), Some("raw"));

        assert_eq!(count_for_run(&conn, PENDING_TXS_TABLE, run_id).unwrap(), 0);
        assert_eq!(
            count_for_run(&conn, SIGNED_CHILD_PCZTS_TABLE, run_id).unwrap(),
            1
        );
        let (nullifier, lock_state): (Option<String>, String) = conn
            .query_row(
                &format!(
                    "SELECT nullifier_hex, lock_state
                     FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert!(nullifier.is_none());
        assert_eq!(lock_state, "locked");

        let mut root_blob = hex::decode(&root_txid).unwrap();
        root_blob.reverse();
        conn.execute(
            "DELETE FROM transactions WHERE txid = ?1",
            params![root_blob],
        )
        .unwrap();
        drop(conn);
        reconcile_denomination_stage_chain_state(db_path, run_id).unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        let statuses = conn
            .prepare(
                "SELECT status FROM vizor_migration_denomination_stages
                 WHERE run_id = ?1 ORDER BY stage_index",
            )
            .unwrap()
            .query_map(params![run_id], |row| row.get::<_, String>(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(
            statuses,
            vec!["awaiting_inputs", "awaiting_inputs", "confirmed"]
        );
    }

    #[test]
    fn reorg_cleanup_preserves_a_migration_child_already_on_chain() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_str().unwrap();
        let conn = rusqlite::Connection::open(db_path).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE blocks (height INTEGER PRIMARY KEY, hash BLOB NOT NULL);
             CREATE TABLE transactions (
                 txid BLOB PRIMARY KEY,
                 block INTEGER,
                 mined_height INTEGER
             );",
        )
        .unwrap();
        let run_id = "run-preserve-child";
        let denomination_txid = "11".repeat(32);
        let child_txid = "22".repeat(32);
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', ?2, ?3, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, db_path, PHASE_WAITING_MIGRATION_CONFIRMATIONS],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 7, 100000000, 2, ?3, 'unlocked')"
            ),
            params![run_id, denomination_txid, "ab".repeat(32)],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height,
                  expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value,
                  scheduled_at_ms, status, metadata_json)
                 VALUES (?1, ?2, 'raw', 10, 20, 99980000, 20000, ?3,
                         7, 100000000, 1, 'broadcasted', '{{}}')"
            ),
            params![run_id, child_txid, denomination_txid],
        )
        .unwrap();
        let block_hash = [0xabu8; 32];
        conn.execute(
            "INSERT INTO blocks (height, hash) VALUES (20, ?1)",
            params![block_hash.as_slice()],
        )
        .unwrap();
        let mut child_blob = hex::decode(&child_txid).unwrap();
        child_blob.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, block, mined_height)
             VALUES (?1, 20, 20)",
            params![child_blob],
        )
        .unwrap();
        drop(conn);

        assert!(!reset_migration_children_for_reorged_denominations(
            db_path,
            run_id,
            &BTreeSet::from([denomination_txid]),
        )
        .unwrap());

        let conn = rusqlite::Connection::open(db_path).unwrap();
        assert_eq!(count_for_run(&conn, PENDING_TXS_TABLE, run_id).unwrap(), 1);
        let (nullifier, lock_state): (Option<String>, String) = conn
            .query_row(
                &format!(
                    "SELECT nullifier_hex, lock_state
                     FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(nullifier, Some("ab".repeat(32)));
        assert_eq!(lock_state, "unlocked");
    }

    #[test]
    fn denomination_reconciliation_waits_for_trusted_confirmations() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            "CREATE TABLE transactions (
                id_tx INTEGER PRIMARY KEY,
                txid BLOB NOT NULL,
                mined_height INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_received_notes (
                transaction_id INTEGER NOT NULL,
                action_index INTEGER NOT NULL,
                value INTEGER NOT NULL,
                note_version INTEGER NOT NULL,
                nf BLOB,
                commitment_tree_position INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_tree_checkpoints (
                checkpoint_id INTEGER PRIMARY KEY,
                position INTEGER
             )",
            [],
        )
        .unwrap();

        let run_id = "run-1";
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1, 1, ?6)"
            ),
            params![
                run_id,
                "account-1",
                "test",
                "db",
                PHASE_WAITING_DENOM_CONFIRMATIONS,
                "[100000000]",
            ],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 0, 100000000, 2, NULL, 'locked')"
            ),
            params![run_id, txid_hex],
        )
        .unwrap();

        let mut txid_blob = hex::decode(txid_hex).unwrap();
        txid_blob.reverse();
        let nf = vec![0xabu8; 32];
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (1, ?1, 20)",
            params![txid_blob],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes
             (transaction_id, action_index, value, note_version, nf, commitment_tree_position)
             VALUES (1, 0, 100000000, 2, ?1, 0)",
            params![nf],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id, position) VALUES (21, 0)",
            [],
        )
        .unwrap();
        insert_test_stage(
            &conn,
            run_id,
            txid_hex,
            DenominationStageStatus::Broadcasted,
            None,
        );

        let run = ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_WAITING_DENOM_CONFIRMATIONS.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: None,
        };
        reconcile_denomination_confirmations(&conn, &run).unwrap();

        let (phase, nullifier_hex): (String, Option<String>) = conn
            .query_row(
                &format!(
                    "SELECT r.phase, pn.nullifier_hex
                     FROM {RUNS_TABLE} r
                     JOIN {PREPARED_NOTES_TABLE} pn ON pn.run_id = r.run_id
                     WHERE r.run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert!(nullifier_hex.is_none());

        let status = status_for_run(&conn, run).unwrap();
        assert_eq!(status.denomination_confirmation_count, 2);
        assert_eq!(status.denomination_confirmation_target, 3);
    }

    #[test]
    fn staged_split_progress_tracks_the_active_frontier_without_future_outputs() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                txid BLOB PRIMARY KEY,
                mined_height INTEGER
             );
             CREATE TABLE orchard_tree_checkpoints (
                checkpoint_id INTEGER PRIMARY KEY
             );",
        )
        .unwrap();

        let run_id = "run-three-stage-progress";
        let stage_txids = ["11".repeat(32), "22".repeat(32), "33".repeat(32)];
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, PHASE_WAITING_DENOM_CONFIRMATIONS],
        )
        .unwrap();
        for (stage_index, txid) in stage_txids.iter().enumerate() {
            let (raw_tx, status) = if stage_index == 0 {
                (Some("raw"), "broadcasted")
            } else {
                (None, "awaiting_inputs")
            };
            conn.execute(
                "INSERT INTO vizor_migration_denomination_stages
                 (run_id, stage_index, encrypted_base_pczt,
                  encrypted_compact_sigs, encrypted_raw_tx,
                  expected_txid_hex, target_height, expiry_height,
                  fee_zatoshi, status)
                 VALUES (?1, ?2, 'base', 'sigs', ?3, ?4, 10, 20, 80000, ?5)",
                params![run_id, stage_index as u32, raw_tx, txid, status],
            )
            .unwrap();
            if stage_index > 0 {
                conn.execute(
                    "INSERT INTO vizor_migration_denomination_stage_inputs
                     (run_id, stage_index, input_order, txid_hex, output_index,
                      value_zatoshi, note_version, nullifier_hex)
                     VALUES (?1, ?2, 0, ?3, 0, 100000000, 2, NULL)",
                    params![run_id, stage_index as u32, stage_txids[stage_index - 1]],
                )
                .unwrap();
            }
        }

        let run = ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_WAITING_DENOM_CONFIRMATIONS.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: None,
        };
        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.denomination_confirmation_count, 0);
        assert_eq!(status.denomination_split_completed_count, 0);
        assert_eq!(status.denomination_split_total_count, 3);

        let mut stage_0_txid = hex::decode(&stage_txids[0]).unwrap();
        stage_0_txid.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height) VALUES (?1, 20)",
            params![stage_0_txid],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (20)",
            [],
        )
        .unwrap();
        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.denomination_confirmation_count, 1);
        assert_eq!(status.denomination_split_completed_count, 0);

        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (21)",
            [],
        )
        .unwrap();
        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.denomination_confirmation_count, 2);
        assert_eq!(status.denomination_split_completed_count, 0);

        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (22)",
            [],
        )
        .unwrap();
        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.denomination_confirmation_count, 0);
        assert_eq!(status.denomination_split_completed_count, 1);
        assert_eq!(status.denomination_split_total_count, 3);

        conn.execute(
            "UPDATE vizor_migration_denomination_stages
             SET encrypted_raw_tx = 'raw', status = 'broadcasted'
             WHERE run_id = ?1 AND stage_index = 1",
            params![run_id],
        )
        .unwrap();
        let mut stage_1_txid = hex::decode(&stage_txids[1]).unwrap();
        stage_1_txid.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height) VALUES (?1, 23)",
            params![stage_1_txid],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (23)",
            [],
        )
        .unwrap();
        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.denomination_confirmation_count, 1);
        assert_eq!(status.denomination_split_completed_count, 1);

        conn.execute_batch(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (24);
             INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (25);",
        )
        .unwrap();
        let status = status_for_run(&conn, run).unwrap();
        assert_eq!(status.denomination_confirmation_count, 0);
        assert_eq!(status.denomination_split_completed_count, 2);
        assert_eq!(status.denomination_split_total_count, 3);
    }

    #[test]
    fn staged_split_progress_uses_the_slowest_parallel_root_not_future_descendants() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                txid BLOB PRIMARY KEY,
                mined_height INTEGER
             );
             CREATE TABLE orchard_tree_checkpoints (
                checkpoint_id INTEGER PRIMARY KEY
             );",
        )
        .unwrap();

        let run_id = "run-parallel-root-progress";
        let root_0 = "44".repeat(32);
        let root_1 = "55".repeat(32);
        let child = "66".repeat(32);
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1,
                         '[100000000]')"
            ),
            params![run_id, PHASE_WAITING_DENOM_CONFIRMATIONS],
        )
        .unwrap();
        for (stage_index, txid, raw_tx, status) in [
            (0u32, &root_0, Some("raw"), "broadcasted"),
            (1u32, &root_1, Some("raw"), "broadcasted"),
            (2u32, &child, None, "awaiting_inputs"),
        ] {
            conn.execute(
                "INSERT INTO vizor_migration_denomination_stages
                 (run_id, stage_index, encrypted_base_pczt,
                  encrypted_compact_sigs, encrypted_raw_tx,
                  expected_txid_hex, target_height, expiry_height,
                  fee_zatoshi, status)
                 VALUES (?1, ?2, 'base', 'sigs', ?3, ?4, 10, 20, 80000, ?5)",
                params![run_id, stage_index, raw_tx, txid, status],
            )
            .unwrap();
        }
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stage_inputs
             (run_id, stage_index, input_order, txid_hex, output_index,
              value_zatoshi, note_version, nullifier_hex)
             VALUES (?1, 2, 0, ?2, 0, 100000000, 2, NULL)",
            params![run_id, root_0],
        )
        .unwrap();

        for (txid, mined_height) in [(&root_0, 20u32), (&root_1, 21u32)] {
            let mut txid_blob = hex::decode(txid).unwrap();
            txid_blob.reverse();
            conn.execute(
                "INSERT INTO transactions (txid, mined_height) VALUES (?1, ?2)",
                params![txid_blob, mined_height],
            )
            .unwrap();
        }
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (21)",
            [],
        )
        .unwrap();

        let progress = denomination_split_progress_for_run(&conn, run_id).unwrap();
        assert_eq!(progress.frontier_confirmation_count, 1);
        assert_eq!(progress.completed_count, 0);
        assert_eq!(progress.total_count, 3);
    }

    #[test]
    fn denomination_reconciliation_waits_for_post_mining_checkpoint() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            "CREATE TABLE transactions (
                id_tx INTEGER PRIMARY KEY,
                txid BLOB NOT NULL,
                mined_height INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_received_notes (
                transaction_id INTEGER NOT NULL,
                action_index INTEGER NOT NULL,
                value INTEGER NOT NULL,
                note_version INTEGER NOT NULL,
                nf BLOB,
                commitment_tree_position INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_tree_checkpoints (
                checkpoint_id INTEGER PRIMARY KEY,
                position INTEGER
             )",
            [],
        )
        .unwrap();

        let run_id = "run-1";
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1, 1, ?6)"
            ),
            params![
                run_id,
                "account-1",
                "test",
                "db",
                PHASE_WAITING_DENOM_CONFIRMATIONS,
                "[100000000]",
            ],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 0, 100000000, 2, NULL, 'locked')"
            ),
            params![run_id, txid_hex],
        )
        .unwrap();

        let mut txid_blob = hex::decode(txid_hex).unwrap();
        txid_blob.reverse();
        let nf = vec![0xabu8; 32];
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (1, ?1, 20)",
            params![txid_blob],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes
             (transaction_id, action_index, value, note_version, nf, commitment_tree_position)
             VALUES (1, 0, 100000000, 2, ?1, 0)",
            params![nf],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id, position) VALUES (20, 0)",
            [],
        )
        .unwrap();
        insert_test_stage(
            &conn,
            run_id,
            txid_hex,
            DenominationStageStatus::Broadcasted,
            None,
        );

        let run = ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_WAITING_DENOM_CONFIRMATIONS.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: None,
        };
        reconcile_denomination_confirmations(&conn, &run).unwrap();

        let (phase, nullifier_hex): (String, Option<String>) = conn
            .query_row(
                &format!(
                    "SELECT r.phase, pn.nullifier_hex
                     FROM {RUNS_TABLE} r
                     JOIN {PREPARED_NOTES_TABLE} pn ON pn.run_id = r.run_id
                     WHERE r.run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert!(nullifier_hex.is_none());
    }

    #[test]
    fn denomination_reconciliation_waits_for_spendable_note_metadata() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            "CREATE TABLE transactions (
                id_tx INTEGER PRIMARY KEY,
                txid BLOB NOT NULL,
                mined_height INTEGER
             )",
            [],
        )
        .unwrap();
        conn.execute(
            "CREATE TABLE orchard_received_notes (
                transaction_id INTEGER NOT NULL,
                action_index INTEGER NOT NULL,
                value INTEGER NOT NULL,
                note_version INTEGER NOT NULL,
                nf BLOB,
                commitment_tree_position INTEGER
             )",
            [],
        )
        .unwrap();

        let run_id = "run-1";
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, 1, 1, ?6)"
            ),
            params![
                run_id,
                "account-1",
                "test",
                "db",
                PHASE_WAITING_DENOM_CONFIRMATIONS,
                "[100000000]",
            ],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1, ?2, 0, 100000000, 2, NULL, 'locked')"
            ),
            params![run_id, txid_hex],
        )
        .unwrap();

        let mut txid_blob = hex::decode(txid_hex).unwrap();
        txid_blob.reverse();
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (1, ?1, 20)",
            params![txid_blob],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes
             (transaction_id, action_index, value, note_version, nf, commitment_tree_position)
             VALUES (1, 0, 100000000, 2, NULL, NULL)",
            [],
        )
        .unwrap();
        insert_test_stage(
            &conn,
            run_id,
            txid_hex,
            DenominationStageStatus::Broadcasted,
            None,
        );

        let run = ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_WAITING_DENOM_CONFIRMATIONS.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: None,
        };
        reconcile_denomination_confirmations(&conn, &run).unwrap();

        let (phase, nullifier_hex): (String, Option<String>) = conn
            .query_row(
                &format!(
                    "SELECT r.phase, pn.nullifier_hex
                     FROM {RUNS_TABLE} r
                     JOIN {PREPARED_NOTES_TABLE} pn ON pn.run_id = r.run_id
                     WHERE r.run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert!(nullifier_hex.is_none());
    }

    const MINIMUM_OUTPUT_FOR_TEST: u64 = 1;
}
