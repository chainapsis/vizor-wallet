use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use rand::{rngs::OsRng, seq::SliceRandom, Rng};
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
use stages::{STAGES_TABLE, STAGE_INPUTS_TABLE, STAGE_OUTPUTS_TABLE};

pub(crate) const ZATOSHIS_PER_ZEC: u64 = 100_000_000;
pub(crate) const ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI: u64 = ZATOSHIS_PER_ZEC / 100;
pub(crate) const ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI: u64 = 10_000 * ZATOSHIS_PER_ZEC;
pub(crate) const ZIP318_ANCHOR_BUCKET_MODULUS: u32 = 144;
pub(crate) const REGTEST_ANCHOR_BUCKET_MODULUS: u32 = 1;
pub(crate) const ZIP318_ANCHOR_AGE_CAP: u32 = 16;
/// Provisional per-wallet contribution limit for a single anchor cohort.
/// ZIP 318 leaves this value open; eight lets the current 64-part run fit
/// across eight or more candidate boundaries while retaining a cohort cap.
pub(crate) const ZIP318_MAX_PARTS_PER_ANCHOR_COHORT: u32 = 8;
pub(crate) const ZIP318_EXPIRY_MODULUS: u32 = 34_560;
pub(crate) const ZIP318_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 144;
pub(crate) const ZIP318_TRANSFER_MAX_DELAY_BLOCKS: u32 = 576;
pub(crate) const REGTEST_TRANSFER_MEAN_DELAY_BLOCKS: u32 = 1;
pub(crate) const REGTEST_TRANSFER_MAX_DELAY_BLOCKS: u32 = 4;
pub(crate) const MIGRATION_MAX_PREPARED_NOTES_PER_RUN: usize = 64;
pub(crate) const MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI: u64 = 1;
// Mirrors the per-child ZIP-317 migration fee estimate used by send planning:
// 3 logical actions (a 2-action padded Orchard bundle and a 1-action
// unpadded Ironwood bundle).
const MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 15_000;
// Every migration needs at least one 16-action padded Orchard transaction
// before its first Ironwood output can be created.
const DENOMINATION_SPLIT_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 80_000;

static FAST_TESTNET_MIGRATION_ENABLED: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MigrationTimingPolicy {
    Standard,
    FastTestnet,
}

impl MigrationTimingPolicy {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Standard => "standard",
            Self::FastTestnet => "fast_testnet",
        }
    }

    fn from_str(value: &str) -> Result<Self, String> {
        match value {
            "standard" => Ok(Self::Standard),
            "fast_testnet" => Ok(Self::FastTestnet),
            _ => Err(format!("Unsupported migration timing policy: {value}")),
        }
    }
}

pub(crate) fn configure_fast_testnet_migration(enabled: bool) {
    FAST_TESTNET_MIGRATION_ENABLED.store(enabled, Ordering::Relaxed);
}

fn configured_timing_policy(network: WalletNetwork) -> MigrationTimingPolicy {
    if network == WalletNetwork::Test && FAST_TESTNET_MIGRATION_ENABLED.load(Ordering::Relaxed) {
        MigrationTimingPolicy::FastTestnet
    } else {
        MigrationTimingPolicy::Standard
    }
}

pub(crate) fn schedule_parameters(network: WalletNetwork) -> (u32, u32) {
    schedule_parameters_with_policy(network, configured_timing_policy(network))
}

fn schedule_parameters_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> (u32, u32) {
    match network {
        WalletNetwork::Regtest => (
            REGTEST_TRANSFER_MEAN_DELAY_BLOCKS,
            REGTEST_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => (
            REGTEST_TRANSFER_MEAN_DELAY_BLOCKS,
            REGTEST_TRANSFER_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Main | WalletNetwork::Test => (
            ZIP318_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
        ),
    }
}

const RUNS_TABLE: &str = "vizor_migration_runs";
const PREPARED_NOTES_TABLE: &str = "vizor_migration_prepared_notes";
const PENDING_TXS_TABLE: &str = "vizor_migration_pending_txs";
const SIGNED_CHILD_PCZTS_TABLE: &str = "vizor_migration_signed_child_pczts";

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

    while outputs.len() < MIGRATION_MAX_PREPARED_NOTES_PER_RUN {
        let Some(spendable_after_fee) = remaining.checked_sub(migration_fee_zatoshi) else {
            break;
        };
        let Some(denomination) = largest_zip318_denomination_at_or_below(spendable_after_fee)
        else {
            break;
        };
        outputs.push(denomination);
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

fn anchor_bucket_modulus(network: WalletNetwork, timing_policy: MigrationTimingPolicy) -> u32 {
    match network {
        WalletNetwork::Regtest => REGTEST_ANCHOR_BUCKET_MODULUS,
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => {
            REGTEST_ANCHOR_BUCKET_MODULUS
        }
        WalletNetwork::Main | WalletNetwork::Test => ZIP318_ANCHOR_BUCKET_MODULUS,
    }
}

fn anchor_bucket_min_age(network: WalletNetwork, timing_policy: MigrationTimingPolicy) -> u32 {
    match network {
        // Empty regtest blocks do not add commitment-tree checkpoints. Allow
        // the checkpoint containing the denomination note so E2E can advance.
        WalletNetwork::Regtest => 0,
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => 0,
        WalletNetwork::Main | WalletNetwork::Test => 1,
    }
}

pub(crate) fn next_anchor_retry_height_after(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    fully_scanned_height: u32,
) -> Result<u32, String> {
    let modulus = anchor_bucket_modulus(network, timing_policy);
    let confirmation_lag = ConfirmationsPolicy::default()
        .trusted()
        .get()
        .saturating_sub(1);
    // Standard ZIP 318 selection excludes the newest boundary. Base the next
    // retry on the trusted anchor height so a boundary that is about to age
    // into the candidate set is not skipped for a full bucket.
    let boundary_reference = if anchor_bucket_min_age(network, timing_policy) > 0 {
        fully_scanned_height.saturating_sub(confirmation_lag)
    } else {
        fully_scanned_height
    };
    let distance = modulus - (boundary_reference % modulus);
    boundary_reference
        .checked_add(distance)
        .and_then(|boundary| boundary.checked_add(confirmation_lag))
        .ok_or_else(|| "Migration proof retry height overflow".to_string())
}

pub(crate) fn zip318_anchor_boundary_at_or_before(
    network: WalletNetwork,
    height: u32,
) -> Option<u32> {
    zip318_anchor_boundary_at_or_before_with_policy(
        network,
        configured_timing_policy(network),
        height,
    )
}

fn zip318_anchor_boundary_at_or_before_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    height: u32,
) -> Option<u32> {
    let modulus = anchor_bucket_modulus(network, timing_policy);
    let boundary = height - (height % modulus);
    (boundary > 0).then_some(boundary)
}

fn zip318_anchor_boundary_age(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    latest_boundary: u32,
    anchor_boundary: u32,
) -> Option<u32> {
    if anchor_boundary > latest_boundary {
        return None;
    }
    let delta = latest_boundary.checked_sub(anchor_boundary)?;
    let modulus = anchor_bucket_modulus(network, timing_policy);
    if delta % modulus != 0 {
        return None;
    }
    let age = delta / modulus;
    (anchor_bucket_min_age(network, timing_policy)..=ZIP318_ANCHOR_AGE_CAP)
        .contains(&age)
        .then_some(age)
}

pub(crate) fn zip318_anchor_candidate_boundaries(
    network: WalletNetwork,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Vec<u32> {
    zip318_anchor_candidate_boundaries_with_policy(
        network,
        configured_timing_policy(network),
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
    )
}

fn zip318_anchor_candidate_boundaries_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Vec<u32> {
    let Some(latest_boundary) = zip318_anchor_boundary_at_or_before_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
    ) else {
        return Vec::new();
    };
    let lower_bound = note_mined_height.max(nu6_3_activation_height.saturating_add(1));
    let mut candidates = Vec::new();
    for age in anchor_bucket_min_age(network, timing_policy)..=ZIP318_ANCHOR_AGE_CAP {
        let Some(distance) = age.checked_mul(anchor_bucket_modulus(network, timing_policy)) else {
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
    network: WalletNetwork,
    anchor_boundary: u32,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> bool {
    zip318_anchor_boundary_is_candidate_with_policy(
        network,
        configured_timing_policy(network),
        anchor_boundary,
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
    )
}

pub(crate) fn zip318_anchor_boundary_is_candidate_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    anchor_boundary: u32,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> bool {
    if anchor_boundary == 0 || anchor_boundary % anchor_bucket_modulus(network, timing_policy) != 0
    {
        return false;
    }
    if anchor_boundary < note_mined_height || anchor_boundary <= nu6_3_activation_height {
        return false;
    }
    let Some(latest_boundary) = zip318_anchor_boundary_at_or_before_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
    ) else {
        return false;
    };
    zip318_anchor_boundary_age(network, timing_policy, latest_boundary, anchor_boundary).is_some()
}

pub(crate) fn zip318_draw_anchor_boundary_for_note(
    network: WalletNetwork,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Option<u32> {
    zip318_draw_anchor_boundary_for_note_with_cohorts(
        network,
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
        &BTreeMap::new(),
    )
}

pub(crate) fn zip318_draw_anchor_boundary_for_note_with_cohorts(
    network: WalletNetwork,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
    cohort_counts: &BTreeMap<u32, u32>,
) -> Option<u32> {
    zip318_draw_anchor_boundary_for_note_with_cohorts_and_policy(
        network,
        configured_timing_policy(network),
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
        cohort_counts,
    )
}

pub(crate) fn zip318_draw_anchor_boundary_for_note_with_cohorts_and_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
    cohort_counts: &BTreeMap<u32, u32>,
) -> Option<u32> {
    let latest_boundary = zip318_anchor_boundary_at_or_before_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
    )?;
    let candidates = zip318_anchor_candidate_boundaries_with_policy(
        network,
        timing_policy,
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
        if cohort_counts.get(&boundary).copied().unwrap_or_default()
            >= ZIP318_MAX_PARTS_PER_ANCHOR_COHORT
        {
            continue;
        }
        let age = zip318_anchor_boundary_age(network, timing_policy, latest_boundary, boundary)?;
        let weight = 1u32 << (ZIP318_ANCHOR_AGE_CAP - age);
        total_weight = total_weight.checked_add(weight)?;
        weighted.push((boundary, weight));
    }

    if total_weight == 0 {
        return None;
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
    pub max_prepared_notes_per_run: u32,
    /// Earliest block height at which the wallet can make more progress.
    pub next_action_height: Option<u32>,
    /// Projected height at which every migration part reaches trusted depth.
    pub estimated_completion_height: Option<u32>,
    /// Part associated with `next_action_height`, when it can be identified.
    pub next_action_part_index: Option<u32>,
    pub scheduled_broadcasts: Vec<ScheduledMigrationBroadcast>,
    pub parts: Vec<MigrationPartStatus>,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct MigrationTimingProjection {
    next_action_height: Option<u32>,
    estimated_completion_height: Option<u32>,
    next_action_part_index: Option<u32>,
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
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    adopt_configured_timing_policy_for_active_run(&conn, account_uuid, network)?;

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
    if orchard_pending == 0 && !orchard_migratable {
        if let Some(run) = latest_completed_run(&conn, account_uuid, network)? {
            let mut status = status_for_run(&conn, run)?;
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
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
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
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        next_action_height: None,
        estimated_completion_height: None,
        next_action_part_index: None,
        scheduled_broadcasts: Vec::new(),
        parts: Vec::new(),
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
    network: WalletNetwork,
) -> Result<MigrationTimingPolicy, String> {
    if network != WalletNetwork::Test {
        return Ok(MigrationTimingPolicy::Standard);
    }
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
    if network != WalletNetwork::Test || desired_policy != MigrationTimingPolicy::FastTestnet {
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
    // transaction is constructed, preserve the prepared notes and signatures
    // while replacing the long standard schedule with the fast policy.
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
             WHERE run_id = ?4 AND timing_policy = 'standard'"
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
    ensure_schema(&conn)?;
    adopt_configured_timing_policy_for_active_run(&conn, account_uuid, network)?;
    active_run(&conn, account_uuid, network)
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
    let timing_policy = configured_timing_policy(network);
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
              updated_at_ms, target_values_json, timing_policy, schedule_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8, ?9)"
        ),
        params![
            run_id,
            account_uuid,
            network_name(network),
            db_path,
            PHASE_WAITING_DENOM_CONFIRMATIONS,
            now,
            target_values_json,
            timing_policy.as_str(),
            schedule_json,
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
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET proof_retry_height = NULL, updated_at_ms = ?1
             WHERE run_id = ?2"
        ),
        params![now_ms()?, run_id],
    )
    .map_err(|e| format!("Clear migration proof retry height: {e}"))?;
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
    let timing_policy = if network == WalletNetwork::Test {
        MigrationTimingPolicy::from_str(&timing_policy)?
    } else {
        MigrationTimingPolicy::Standard
    };
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
    let existing_schedule_origin = tx
        .query_row(
            &format!(
                "SELECT scheduled_at_ms,
                        COALESCE(schedule_start_height, target_height - 1),
                        scheduled_height
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1
                 ORDER BY part_index ASC
                 LIMIT 1"
            ),
            params![run_id],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, u32>(1)?,
                    row.get::<_, u32>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read migration schedule origin: {e}"))?;
    let (construction_height, scheduled_start_ms) =
        if let Some((scheduled_at_ms, schedule_start_height, scheduled_height)) =
            existing_schedule_origin
        {
            let existing_offset = scheduled_height.saturating_sub(schedule_start_height);
            let scheduled_start_ms = scheduled_at_ms
                .checked_sub(i64::from(existing_offset).saturating_mul(1000))
                .ok_or("Migration scheduled time underflow")?;
            (schedule_start_height, scheduled_start_ms)
        } else {
            let signed_child_construction_height = tx
                .query_row(
                    &format!(
                        "SELECT MAX(target_height - 1)
                         FROM {SIGNED_CHILD_PCZTS_TABLE}
                         WHERE run_id = ?1"
                    ),
                    params![run_id],
                    |row| row.get::<_, Option<u32>>(0),
                )
                .map_err(|e| format!("Read signed migration construction height: {e}"))?;
            let construction_height = pending_txs
                .iter()
                .map(|pending| pending.target_height.saturating_sub(1))
                .chain(signed_child_construction_height)
                .max()
                .ok_or("Migration schedule has no transactions")?;
            (construction_height, now_ms()?)
        };
    let mut scheduled_pending = Vec::with_capacity(pending_txs.len());
    let mut pending_part_indexes = BTreeSet::new();
    for pending in pending_txs {
        if !pending_part_indexes.insert(pending.part_index) {
            return Err("Migration pending part index is duplicated".to_string());
        }
        let entry = schedule_entry_for_pending(&schedule, &target_values, &pending)
            .ok_or("Approved migration schedule no longer matches prepared values")?;
        scheduled_pending.push((pending, entry.block_offset));
    }
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;

    for (pending, block_offset) in scheduled_pending {
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
        let scheduled_height = construction_height
            .checked_add(block_offset)
            .ok_or("Migration scheduled height overflow")?;

        let inserted = tx
            .execute(
                &format!(
                    "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, part_index, encrypted_raw_tx, target_height, expiry_height,
                  anchor_boundary_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  schedule_start_height, scheduled_height, status, metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, 'scheduled', ?16)"
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
                    construction_height,
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
            "SELECT message_id, child_index, encrypted_base_pczt,
                    encrypted_compact_sigs, target_height, expiry_height,
                    anchor_boundary_height, value_zatoshi, fee_zatoshi,
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
                row.get::<_, u32>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, u32>(5)?,
                row.get::<_, Option<u32>>(6)?,
                row.get::<_, u64>(7)?,
                row.get::<_, u64>(8)?,
                row.get::<_, String>(9)?,
                row.get::<_, String>(10)?,
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
            message_id,
            child_index,
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

pub(crate) fn pending_anchor_cohort_counts(
    db_path: &str,
    run_id: &str,
) -> Result<BTreeMap<u32, u32>, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT anchor_boundary_height, COUNT(*)
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND anchor_boundary_height IS NOT NULL
               AND status != 'needs_resign'
             GROUP BY anchor_boundary_height"
        ))
        .map_err(|e| format!("Prepare migration anchor cohort query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, u32>(0)?, row.get::<_, u32>(1)?))
        })
        .map_err(|e| format!("Query migration anchor cohorts: {e}"))?;
    rows.collect::<Result<BTreeMap<_, _>, _>>()
        .map_err(|e| format!("Read migration anchor cohorts: {e}"))
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
                 SET phase = ?1, updated_at_ms = ?2, last_error = NULL,
                     proof_retry_height = NULL
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
    chain_tip_height: u32,
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
             WHERE run_id = ?1 AND status = 'scheduled' AND scheduled_height <= ?2
             ORDER BY scheduled_height ASC, txid_hex ASC
             LIMIT 1"
        ))
        .map_err(|e| format!("Prepare due migration tx query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, chain_tip_height], |row| {
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

pub(crate) fn expired_unconfirmed_pending_count(
    db_path: &str,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<u32, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    conn.query_row(
        &format!(
            "SELECT COUNT(*)
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1
               AND status IN ('scheduled', 'broadcasted')
               AND expiry_height > 0
               AND expiry_height <= ?2"
        ),
        params![run_id, chain_tip_height],
        |row| row.get::<_, u32>(0),
    )
    .map_err(|e| format!("Count expired migration transactions: {e}"))
}

pub(crate) fn mark_expired_pending_parts_for_resign(
    db_path: &str,
    run_id: &str,
    chain_tip_height: u32,
) -> Result<u32, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin expired migration recovery: {e}"))?;
    let updated = tx
        .execute(
            &format!(
                "UPDATE {PENDING_TXS_TABLE}
                 SET status = 'needs_resign'
                 WHERE run_id = ?1
                   AND status IN ('scheduled', 'broadcasted')
                   AND expiry_height > 0
                   AND expiry_height <= ?2"
            ),
            params![run_id, chain_tip_height],
        )
        .map_err(|e| format!("Mark expired migration parts for re-signing: {e}"))?;
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
    network: WalletNetwork,
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
    let timing_policy = timing_policy_for_run_with_conn(&conn, run_id, network)?;
    let schedule = planned_transfer_schedule_for_parts_with_policy(
        replacements.iter().map(|replacement| {
            (
                replacement.replacement.part_index,
                replacement.replacement.value_zatoshi,
            )
        }),
        network,
        timing_policy,
        &mut OsRng,
    );
    let construction_height = replacements
        .iter()
        .map(|replacement| replacement.replacement.target_height.saturating_sub(1))
        .max()
        .ok_or("Migration recovery has no transactions")?;
    let scheduled_start_ms = now_ms()?;
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration pending salt")?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration part replacement: {e}"))?;

    let mut scheduled_replacements = Vec::with_capacity(replacements.len());
    for schedule_entry in schedule {
        let replacement_index = replacements
            .iter()
            .position(|replacement| match schedule_entry.part_index {
                Some(part_index) => {
                    replacement.replacement.part_index == part_index
                        && replacement.replacement.value_zatoshi == schedule_entry.value_zatoshi
                }
                None => replacement.replacement.value_zatoshi == schedule_entry.value_zatoshi,
            })
            .ok_or("Replacement migration schedule does not match its denominations")?;
        scheduled_replacements.push((replacements.swap_remove(replacement_index), schedule_entry));
    }

    for (replacement, schedule_entry) in scheduled_replacements {
        let original = tx
            .query_row(
                &format!(
                    "SELECT value_zatoshi, selected_note_txid,
                            selected_note_output_index
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
        let encrypted_raw_tx = secret_payload::encrypt_payload(
            Zeroizing::new(pending.raw_tx),
            password,
            salt.as_slice(),
        )?;
        let metadata_json = serde_json::to_string(&pending.metadata)
            .map_err(|e| format!("Encode replacement migration metadata: {e}"))?;
        let scheduled_at_ms = scheduled_start_ms
            .checked_add(i64::from(schedule_entry.block_offset).saturating_mul(1000))
            .ok_or("Replacement migration time overflow")?;
        let scheduled_height = construction_height
            .checked_add(schedule_entry.block_offset)
            .ok_or("Replacement migration height overflow")?;

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
                  schedule_start_height, scheduled_height, status, metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12,
                         ?13, ?14, ?15, 'scheduled', ?16)"
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
                construction_height,
                scheduled_height,
                metadata_json,
            ],
        )
        .map_err(|e| format!("Insert replacement migration part: {e}"))?;
    }

    insert_signed_child_pczts_with_tx(&tx, run_id, signed_children, password, salt_base64)?;
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
        .map_err(|e| format!("Commit migration rebuild transition: {e}"))
}

pub(crate) fn reschedule_overdue_pending_txs(
    db_path: &str,
    run_id: &str,
    network: WalletNetwork,
    chain_tip_height: u32,
) -> Result<(), String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'scheduled' AND scheduled_height <= ?2"
        ))
        .map_err(|e| format!("Prepare overdue migration query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, chain_tip_height], |row| {
            row.get::<_, String>(0)
        })
        .map_err(|e| format!("Query overdue migration transactions: {e}"))?;
    let mut txids = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read overdue migration transaction: {e}"))?;
    drop(stmt);
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
    for (txid, offset) in txids.into_iter().zip(offsets) {
        let scheduled_height = chain_tip_height
            .checked_add(offset)
            .ok_or("Migration rescheduled height overflow")?;
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
    tx.commit()
        .map_err(|e| format!("Commit overdue migration reschedule: {e}"))
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
    let scheduled_remaining = count_pending_with_status(&tx, run_id, "scheduled")?;
    let pending_count = count_for_run(&tx, PENDING_TXS_TABLE, run_id)?;
    let planned_count = planned_part_count_with_conn(&tx, run_id)?;
    let unpromoted_count = unpromoted_signed_child_pczt_count_with_conn(&tx, run_id)?;
    let fully_materialized =
        planned_count > 0 && pending_count == planned_count && unpromoted_count == 0;
    let next_phase = if scheduled_remaining > 0 || !fully_materialized {
        PHASE_BROADCAST_SCHEDULED
    } else {
        PHASE_WAITING_MIGRATION_CONFIRMATIONS
    };
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = NULL
             WHERE run_id = ?3"
        ),
        params![next_phase, now, run_id],
    )
    .map_err(|e| format!("Mark migration waiting confirmations: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit pending migration broadcast update: {e}"))
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

    let projected_signed_broadcast_heights = if signed_children.is_empty() {
        Vec::new()
    } else {
        // Promotion reuses the first persisted schedule origin. Before any
        // child is promoted it uses the latest signed construction height.
        let schedule_origin = pending
            .first()
            .map(|part| {
                part.schedule_start_height
                    .unwrap_or_else(|| part.target_height.saturating_sub(1))
            })
            .or_else(|| {
                signed_children
                    .iter()
                    .map(|child| child.target_height.saturating_sub(1))
                    .max()
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
                    .map(|height| height.max(proof_retry_height.unwrap_or(0)))
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
        let signed_due = projected_signed_broadcast_heights
            .iter()
            .filter(|height| **height <= retry_height)
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

        if let Some(projected_broadcast_height) =
            projected_signed_broadcast_heights.iter().copied().max()
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
        next_action_part_index: next_action.and_then(|value| value.1),
        estimated_completion_height,
    })
}

fn status_for_run(conn: &rusqlite::Connection, run: ActiveRun) -> Result<MigrationStatus, String> {
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
    let parts = migration_parts_for_run(
        conn,
        &run.run_id,
        &run.target_values_zatoshi,
        &phase,
        denomination_confirmation_target,
    )?;
    let timing_projection = migration_timing_projection_for_run(
        conn,
        &run.run_id,
        total_count,
        denomination_confirmation_target,
    )?;

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
        schedule_mean_delay_blocks: schedule_parameters_with_policy(network, timing_policy).0,
        schedule_max_delay_blocks: schedule_parameters_with_policy(network, timing_policy).1,
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        next_action_height: timing_projection.next_action_height,
        estimated_completion_height: timing_projection.estimated_completion_height,
        next_action_part_index: timing_projection.next_action_part_index,
        scheduled_broadcasts,
        parts,
    })
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
            value_zatoshi: *value_zatoshi,
            state: initial_state,
            txid_hex: None,
            schedule_start_height: None,
            scheduled_height: None,
            confirmation_count: 0,
            confirmation_target,
        })
        .collect::<Vec<_>>();

    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT part_index, txid_hex, value_zatoshi, fee_zatoshi,
                    COALESCE(schedule_start_height, target_height - 1),
                    scheduled_height, status
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
                row.get::<_, String>(6)?,
            ))
        })
        .map_err(|e| format!("Query migration part statuses: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration part statuses: {e}"))?;

    if phase == PHASE_READY_TO_MIGRATE && rows.is_empty() {
        return Ok(Vec::new());
    }

    let mut assigned = BTreeSet::new();
    for (
        stored_index,
        txid_hex,
        value_zatoshi,
        fee_zatoshi,
        schedule_start_height,
        scheduled_height,
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

        let (state, confirmation_count) = match raw_status.as_str() {
            "scheduled" => (MigrationPartState::Scheduled, 0),
            "broadcasted" => (MigrationPartState::Migrating, 0),
            "confirmed" => {
                let confirmation_count = match local_denomination_chain_identity(conn, &txid_hex)? {
                    Some(identity) => {
                        synced_orchard_confirmation_count(conn, identity.mined_height)?
                    }
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
            value_zatoshi: parts
                .get(part_index as usize)
                .map(|part| part.value_zatoshi)
                .unwrap_or(denomination_value),
            state,
            txid_hex: Some(txid_hex),
            schedule_start_height: Some(schedule_start_height),
            scheduled_height: Some(scheduled_height),
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
            value_zatoshi: *value_zatoshi,
            state: MigrationPartState::Preparing,
            txid_hex: None,
            schedule_start_height: None,
            scheduled_height: None,
            confirmation_count: 0,
            confirmation_target,
        })
        .collect::<Vec<_>>();
    let mut assigned = BTreeSet::new();

    for stage in stages {
        let txid_hex = stage.expected_txid_hex.to_ascii_lowercase();
        let (state, confirmation_count) =
            denomination_stage_part_state(conn, &stage, confirmation_target)?;
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
                value_zatoshi: parts
                    .get(part_index as usize)
                    .map(|part| part.value_zatoshi)
                    .unwrap_or(output.value_zatoshi),
                state,
                txid_hex: Some(txid_hex.clone()),
                schedule_start_height: None,
                scheduled_height: None,
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
                         SET status = 'scheduled', scheduled_at_ms = ?1,
                             schedule_start_height = target_height,
                             scheduled_height = target_height
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
                 WHERE run_id = ?3"
            ),
            params![PHASE_BROADCAST_SCHEDULED, now, run_id],
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
                         WHERE run_id = ?3"
                    ),
                    params![PHASE_BROADCAST_SCHEDULED, now, run_id],
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

fn random_schedule_block_offsets_with_rng<R: Rng + ?Sized>(
    count: usize,
    mean_delay_blocks: u32,
    max_delay_blocks: u32,
    rng: &mut R,
) -> Vec<u32> {
    assert!(mean_delay_blocks > 0);
    assert!(max_delay_blocks > 0);

    let mut offsets = Vec::with_capacity(count);
    let mut elapsed_blocks = 0u32;
    for _ in 0..count {
        let delay = loop {
            let uniform = rng.gen_range(f64::MIN_POSITIVE..1.0);
            let sampled = (-uniform.ln() * f64::from(mean_delay_blocks)).ceil() as u32;
            let sampled = sampled.max(1);
            if sampled <= max_delay_blocks {
                break sampled;
            }
        };
        elapsed_blocks = elapsed_blocks.saturating_add(delay);
        offsets.push(elapsed_blocks);
    }
    offsets
}

pub(crate) fn planned_transfer_schedule<R, I>(
    values: I,
    network: WalletNetwork,
    rng: &mut R,
) -> Vec<MigrationScheduleEntry>
where
    R: Rng + ?Sized,
    I: IntoIterator<Item = u64>,
{
    planned_transfer_schedule_for_parts_with_policy(
        values
            .into_iter()
            .enumerate()
            .map(|(part_index, value_zatoshi)| (part_index as u32, value_zatoshi)),
        network,
        configured_timing_policy(network),
        rng,
    )
}

fn planned_transfer_schedule_with_policy<R, I>(
    values: I,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    rng: &mut R,
) -> Vec<MigrationScheduleEntry>
where
    R: Rng + ?Sized,
    I: IntoIterator<Item = u64>,
{
    planned_transfer_schedule_for_parts_with_policy(
        values
            .into_iter()
            .enumerate()
            .map(|(part_index, value_zatoshi)| (part_index as u32, value_zatoshi)),
        network,
        timing_policy,
        rng,
    )
}

fn planned_transfer_schedule_for_parts_with_policy<R, I>(
    parts: I,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    rng: &mut R,
) -> Vec<MigrationScheduleEntry>
where
    R: Rng + ?Sized,
    I: IntoIterator<Item = (u32, u64)>,
{
    let mut parts = parts.into_iter().collect::<Vec<_>>();
    parts.shuffle(rng);
    let (mean_delay_blocks, max_delay_blocks) =
        schedule_parameters_with_policy(network, timing_policy);
    let offsets = random_schedule_block_offsets_with_rng(
        parts.len(),
        mean_delay_blocks,
        max_delay_blocks,
        rng,
    );
    parts
        .into_iter()
        .zip(offsets)
        .map(
            |((part_index, value_zatoshi), block_offset)| MigrationScheduleEntry {
                part_index: Some(part_index),
                value_zatoshi,
                block_offset,
            },
        )
        .collect()
}

pub(crate) fn validate_schedule(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    network: WalletNetwork,
) -> Result<(), String> {
    validate_schedule_with_policy(
        schedule,
        target_values,
        network,
        configured_timing_policy(network),
    )
}

fn validate_schedule_with_policy(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> Result<(), String> {
    if schedule.len() != target_values.len() {
        return Err("Approved migration schedule count changed".to_string());
    }
    let target_values_by_part = target_values.to_vec();
    let mut scheduled_values = schedule
        .iter()
        .map(|entry| entry.value_zatoshi)
        .collect::<Vec<_>>();
    let mut target_values = target_values_by_part.clone();
    scheduled_values.sort_unstable();
    target_values.sort_unstable();
    if scheduled_values != target_values {
        return Err("Approved migration schedule values changed".to_string());
    }
    validate_schedule_part_indexes(schedule, &target_values_by_part)?;

    let (_, max_delay_blocks) = schedule_parameters_with_policy(network, timing_policy);
    let mut previous_offset = 0;
    for entry in schedule {
        let gap = entry
            .block_offset
            .checked_sub(previous_offset)
            .ok_or("Approved migration schedule is not ordered")?;
        if !(1..=max_delay_blocks).contains(&gap) {
            return Err("Approved migration schedule delay is outside policy".to_string());
        }
        previous_offset = entry.block_offset;
    }
    Ok(())
}

fn validate_schedule_part_indexes(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
) -> Result<(), String> {
    if schedule.iter().all(|entry| entry.part_index.is_none()) {
        return Ok(());
    }
    if schedule.iter().any(|entry| entry.part_index.is_none()) {
        return Err("Approved migration schedule part indexes are incomplete".to_string());
    }

    let mut seen = BTreeSet::new();
    for entry in schedule {
        let part_index = entry
            .part_index
            .ok_or("Approved migration schedule part indexes are incomplete")?;
        let value = target_values
            .get(part_index as usize)
            .ok_or("Approved migration schedule part index is outside the plan")?;
        if !seen.insert(part_index) {
            return Err("Approved migration schedule part index is duplicated".to_string());
        }
        if *value != entry.value_zatoshi {
            return Err("Approved migration schedule part value changed".to_string());
        }
    }
    Ok(())
}

fn backfill_pending_part_indices(conn: &rusqlite::Connection) -> Result<(), String> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT run_id, txid_hex, value_zatoshi, fee_zatoshi,
                    lower(selected_note_txid), selected_note_output_index
             FROM {PENDING_TXS_TABLE}
             WHERE part_index IS NULL
             ORDER BY run_id ASC, scheduled_height ASC, txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare migration part index backfill: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, u64>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, u32>(5)?,
            ))
        })
        .map_err(|e| format!("Query migration part index backfill: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration part index backfill: {e}"))?;
    drop(stmt);

    for (run_id, txid_hex, value_zatoshi, fee_zatoshi, selected_txid, selected_output_index) in rows
    {
        let used = {
            let mut used_stmt = conn
                .prepare_cached(&format!(
                    "SELECT part_index FROM {PENDING_TXS_TABLE}
                     WHERE run_id = ?1 AND part_index IS NOT NULL"
                ))
                .map_err(|e| format!("Prepare used migration part indices: {e}"))?;
            let used = used_stmt
                .query_map(params![run_id], |row| row.get::<_, u32>(0))
                .map_err(|e| format!("Query used migration part indices: {e}"))?
                .collect::<Result<BTreeSet<_>, _>>()
                .map_err(|e| format!("Read used migration part indices: {e}"))?;
            used
        };

        let mut part_index = None;
        let mut child_stmt = conn
            .prepare_cached(&format!(
                "SELECT child_index, selected_note_json
                 FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1
                 ORDER BY child_index ASC"
            ))
            .map_err(|e| format!("Prepare signed migration part backfill: {e}"))?;
        let children = child_stmt
            .query_map(params![run_id], |row| {
                Ok((row.get::<_, u32>(0)?, row.get::<_, String>(1)?))
            })
            .map_err(|e| format!("Query signed migration part backfill: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read signed migration part backfill: {e}"))?;
        for (child_index, selected_note_json) in children {
            let note = serde_json::from_str::<PreparedOrchardNoteRef>(&selected_note_json)
                .map_err(|e| format!("Decode signed migration part backfill note: {e}"))?;
            if note.txid_hex.eq_ignore_ascii_case(&selected_txid)
                && note.output_index == selected_output_index
                && !used.contains(&child_index)
            {
                part_index = Some(child_index);
                break;
            }
        }

        if part_index.is_none() {
            let target_values_json = conn
                .query_row(
                    &format!("SELECT target_values_json FROM {RUNS_TABLE} WHERE run_id = ?1"),
                    params![run_id],
                    |row| row.get::<_, String>(0),
                )
                .optional()
                .map_err(|e| format!("Read migration targets for part backfill: {e}"))?;
            if let Some(target_values_json) = target_values_json {
                let target_values = serde_json::from_str::<Vec<u64>>(&target_values_json)
                    .map_err(|e| format!("Decode migration targets for part backfill: {e}"))?;
                part_index = target_values
                    .iter()
                    .enumerate()
                    .find(|(index, value)| {
                        (**value == value_zatoshi.saturating_add(fee_zatoshi)
                            || **value == value_zatoshi)
                            && !used.contains(&(*index as u32))
                    })
                    .map(|(index, _)| index as u32);
            }
        }

        let part_index = part_index.unwrap_or_else(|| {
            (0u32..)
                .find(|candidate| !used.contains(candidate))
                .expect("u32 migration part index space is exhausted")
        });
        conn.execute(
            &format!(
                "UPDATE {PENDING_TXS_TABLE} SET part_index = ?1
                 WHERE run_id = ?2 AND txid_hex = ?3 AND part_index IS NULL"
            ),
            params![part_index, run_id, txid_hex],
        )
        .map_err(|e| format!("Backfill migration part index: {e}"))?;
    }
    Ok(())
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
            schedule_json TEXT NOT NULL DEFAULT '[]',
            timing_policy TEXT NOT NULL DEFAULT 'standard',
            proof_retry_height INTEGER,
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
            part_index INTEGER,
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
            schedule_start_height INTEGER,
            scheduled_height INTEGER NOT NULL DEFAULT 0,
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
    add_column_if_missing(conn, PENDING_TXS_TABLE, "part_index", "INTEGER")?;
    add_column_if_missing(conn, PENDING_TXS_TABLE, "anchor_boundary_height", "INTEGER")?;
    add_column_if_missing(
        conn,
        RUNS_TABLE,
        "schedule_json",
        "TEXT NOT NULL DEFAULT '[]'",
    )?;
    add_column_if_missing(
        conn,
        RUNS_TABLE,
        "timing_policy",
        "TEXT NOT NULL DEFAULT 'standard'",
    )?;
    add_column_if_missing(conn, RUNS_TABLE, "proof_retry_height", "INTEGER")?;
    add_column_if_missing(conn, PENDING_TXS_TABLE, "scheduled_height", "INTEGER")?;
    add_column_if_missing(conn, PENDING_TXS_TABLE, "schedule_start_height", "INTEGER")?;
    backfill_pending_part_indices(conn)?;
    conn.execute(
        &format!(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_vizor_migration_pending_part
             ON {PENDING_TXS_TABLE}(run_id, part_index)
             WHERE part_index IS NOT NULL"
        ),
        [],
    )
    .map_err(|e| format!("Create migration pending part index: {e}"))?;
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET scheduled_height = target_height
             WHERE scheduled_height IS NULL"
        ),
        [],
    )
    .map_err(|e| format!("Backfill migration scheduled heights: {e}"))?;
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET schedule_start_height = CASE
                 WHEN target_height > 0 THEN target_height - 1
                 ELSE 0
             END
             WHERE schedule_start_height IS NULL"
        ),
        [],
    )
    .map_err(|e| format!("Backfill migration schedule start heights: {e}"))?;
    conn.execute(
        &format!(
            "CREATE INDEX IF NOT EXISTS idx_vizor_migration_pending_height_due
             ON {PENDING_TXS_TABLE}(status, scheduled_height)"
        ),
        [],
    )
    .map_err(|e| format!("Create migration scheduled-height index: {e}"))?;
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
mod tests;
