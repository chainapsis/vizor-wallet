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
    pub scheduled_broadcasts: Vec<ScheduledMigrationBroadcast>,
    pub parts: Vec<MigrationPartStatus>,
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
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin staged migration run: {e}"))?;
    tx.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase, created_at_ms,
              updated_at_ms, target_values_json, timing_policy)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8)"
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
    let (network, timing_policy) = tx
        .query_row(
            &format!("SELECT network, timing_policy FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .map_err(|e| format!("Read migration run policy: {e}"))?;
    let network = WalletNetwork::from_str(&network)
        .ok_or_else(|| format!("Unsupported migration run network: {network}"))?;
    let timing_policy = if network == WalletNetwork::Test {
        MigrationTimingPolicy::from_str(&timing_policy)?
    } else {
        MigrationTimingPolicy::Standard
    };
    let mut pending_txs = pending_txs;
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
            pending_txs.iter().map(|pending| pending.value_zatoshi),
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
    validate_schedule_with_policy(
        &schedule,
        &pending_txs
            .iter()
            .map(|pending| pending.value_zatoshi)
            .collect::<Vec<_>>(),
        network,
        timing_policy,
    )?;
    let construction_height = pending_txs
        .iter()
        .map(|pending| pending.target_height.saturating_sub(1))
        .max()
        .ok_or("Migration schedule has no transactions")?;
    let mut scheduled_pending = Vec::with_capacity(pending_txs.len());
    for entry in &schedule {
        let position = pending_txs
            .iter()
            .position(|pending| match entry.part_index {
                Some(part_index) => {
                    pending.part_index == part_index && pending.value_zatoshi == entry.value_zatoshi
                }
                None => pending.value_zatoshi == entry.value_zatoshi,
            })
            .ok_or("Approved migration schedule no longer matches prepared values")?;
        scheduled_pending.push((pending_txs.swap_remove(position), entry.block_offset));
    }
    let scheduled_start_ms = now_ms()?;
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
mod tests {
    use super::*;
    use rand::{rngs::StdRng, SeedableRng};

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
                part_index: Some(0),
            }],
        }
    }

    fn pending_test_stage_for_part(
        stage_index: u32,
        expected_txid_hex: &str,
        value_zatoshi: u64,
        part_index: Option<u32>,
    ) -> DenominationStageInsert {
        let mut stage = pending_test_stage(expected_txid_hex, vec![1, 2, 3, 4]);
        stage.stage_index = stage_index;
        stage.inputs[0].txid_hex = format!("{:02x}", 0xa0 + stage_index as u8).repeat(32);
        stage.inputs[0].output_index = stage_index;
        stage.inputs[0].value_zatoshi = value_zatoshi.saturating_add(stage.fee_zatoshi);
        stage.outputs[0].value_zatoshi = value_zatoshi;
        stage.outputs[0].part_index = part_index;
        stage
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
        assert_eq!(
            zip318_anchor_boundary_at_or_before(WalletNetwork::Test, 143),
            None
        );
        assert_eq!(
            zip318_anchor_boundary_at_or_before(WalletNetwork::Test, 144),
            Some(144)
        );
        assert_eq!(
            zip318_anchor_boundary_at_or_before(WalletNetwork::Test, 5700),
            Some(5616)
        );

        assert_eq!(
            zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5700, 5000, 5000),
            vec![5472, 5328, 5184, 5040]
        );
        assert_eq!(
            zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5700, 5600, 5000),
            Vec::<u32>::new()
        );
        assert_eq!(
            zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5900, 5600, 5000),
            vec![5616]
        );

        assert!(zip318_anchor_boundary_is_candidate(
            WalletNetwork::Test,
            5472,
            5700,
            5000,
            5000
        ));
        assert!(!zip318_anchor_boundary_is_candidate(
            WalletNetwork::Test,
            5616,
            5700,
            5000,
            5000
        ));
        assert!(!zip318_anchor_boundary_is_candidate(
            WalletNetwork::Test,
            4896,
            5700,
            1,
            5000
        ));
        assert!(!zip318_anchor_boundary_is_candidate(
            WalletNetwork::Test,
            5500,
            5700,
            1,
            5000
        ));
    }

    #[test]
    fn anchor_bucket_draw_stays_within_candidate_set() {
        let candidates = zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5700, 5000, 5000);
        assert!(!candidates.is_empty());

        for _ in 0..32 {
            let boundary =
                zip318_draw_anchor_boundary_for_note(WalletNetwork::Test, 5700, 5000, 5000)
                    .unwrap();
            assert!(candidates.contains(&boundary));
        }
        assert_eq!(
            zip318_draw_anchor_boundary_for_note(WalletNetwork::Test, 5700, 5600, 5000),
            None
        );
        assert_eq!(
            zip318_anchor_candidate_boundaries(WalletNetwork::Regtest, 503, 501, 500)[0],
            503
        );
        assert_eq!(
            zip318_anchor_candidate_boundaries(WalletNetwork::Regtest, 501, 501, 500),
            vec![501]
        );
    }

    #[test]
    fn anchor_bucket_draw_skips_full_wallet_cohorts() {
        assert_eq!(ZIP318_MAX_PARTS_PER_ANCHOR_COHORT, 8);
        let candidates = zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5700, 5000, 5000);
        let available = *candidates.last().unwrap();
        let mut cohort_counts = candidates
            .iter()
            .map(|boundary| (*boundary, ZIP318_MAX_PARTS_PER_ANCHOR_COHORT))
            .collect::<BTreeMap<_, _>>();
        cohort_counts.insert(available, ZIP318_MAX_PARTS_PER_ANCHOR_COHORT - 1);

        for _ in 0..16 {
            assert_eq!(
                zip318_draw_anchor_boundary_for_note_with_cohorts(
                    WalletNetwork::Test,
                    5700,
                    5000,
                    5000,
                    &cohort_counts,
                ),
                Some(available)
            );
        }

        cohort_counts.insert(available, ZIP318_MAX_PARTS_PER_ANCHOR_COHORT);
        assert_eq!(
            zip318_draw_anchor_boundary_for_note_with_cohorts(
                WalletNetwork::Test,
                5700,
                5000,
                5000,
                &cohort_counts,
            ),
            None
        );
    }

    #[test]
    fn planner_chunks_more_than_max_prepared_outputs_into_follow_up_run() {
        let input = 1_999_999_950_000_000;
        let migration_fee = 10_000;
        let plan = plan_denominations(input, 0, migration_fee, 1).unwrap();

        assert_eq!(
            plan.migration_outputs.len(),
            MIGRATION_MAX_PREPARED_NOTES_PER_RUN
        );
        assert!(plan
            .migration_outputs
            .iter()
            .all(|value| is_zip318_canonical_denomination(*value)));
        let orchard_change = plan.orchard_change.unwrap();
        assert!(orchard_balance_can_create_migration_output(orchard_change).unwrap());
        assert_eq!(
            plan.total_migratable_zatoshi
                + migration_fee * MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u64
                + orchard_change,
            input
        );
    }

    #[test]
    fn schedule_offsets_delay_every_transfer_and_cap_each_gap() {
        let mut rng = StdRng::seed_from_u64(0x318);
        let offsets = random_schedule_block_offsets_with_rng(
            32,
            ZIP318_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
            &mut rng,
        );

        assert_eq!(offsets.len(), 32);
        assert!(offsets[0] >= 1);
        assert!(offsets.windows(2).all(|w| {
            let gap = w[1] - w[0];
            (1..=ZIP318_TRANSFER_MAX_DELAY_BLOCKS).contains(&gap)
        }));
    }

    #[test]
    fn regtest_schedule_is_short_but_still_requires_blocks() {
        assert_eq!(
            schedule_parameters(WalletNetwork::Regtest),
            (1, REGTEST_TRANSFER_MAX_DELAY_BLOCKS)
        );
        assert_eq!(
            schedule_parameters(WalletNetwork::Test),
            (
                ZIP318_TRANSFER_MEAN_DELAY_BLOCKS,
                ZIP318_TRANSFER_MAX_DELAY_BLOCKS
            )
        );
    }

    #[test]
    fn fast_testnet_uses_regtest_schedule_and_anchor_timing() {
        assert_eq!(
            schedule_parameters_with_policy(
                WalletNetwork::Test,
                MigrationTimingPolicy::FastTestnet,
            ),
            (1, REGTEST_TRANSFER_MAX_DELAY_BLOCKS)
        );
        assert_eq!(
            zip318_anchor_candidate_boundaries_with_policy(
                WalletNetwork::Test,
                MigrationTimingPolicy::FastTestnet,
                503,
                501,
                500,
            )[0],
            503
        );
        assert_eq!(
            schedule_parameters_with_policy(
                WalletNetwork::Main,
                MigrationTimingPolicy::FastTestnet,
            ),
            (
                ZIP318_TRANSFER_MEAN_DELAY_BLOCKS,
                ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
            )
        );
    }

    #[test]
    fn fast_testnet_adopts_unstarted_run_and_replaces_schedule() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json, schedule_json)
                 VALUES ('run-1', 'account-1', 'test', ?1, ?2, 1, 1,
                         '[100,200,300]', ?3)"
            ),
            params![
                db_path,
                PHASE_READY_TO_MIGRATE,
                r#"[{"value_zatoshi":100,"block_offset":144},{"value_zatoshi":200,"block_offset":288},{"value_zatoshi":300,"block_offset":432}]"#,
            ],
        )
        .unwrap();

        adopt_timing_policy_for_active_run(
            &conn,
            "account-1",
            WalletNetwork::Test,
            MigrationTimingPolicy::FastTestnet,
        )
        .unwrap();

        let (policy, schedule_json): (String, String) = conn
            .query_row(
                &format!(
                    "SELECT timing_policy, schedule_json FROM {RUNS_TABLE} WHERE run_id = 'run-1'"
                ),
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(policy, "fast_testnet");
        let schedule: Vec<MigrationScheduleEntry> = serde_json::from_str(&schedule_json).unwrap();
        validate_schedule_with_policy(
            &schedule,
            &[100, 200, 300],
            WalletNetwork::Test,
            MigrationTimingPolicy::FastTestnet,
        )
        .unwrap();
    }

    #[test]
    fn fast_testnet_does_not_retime_run_after_child_creation() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json, schedule_json)
                 VALUES ('run-1', 'account-1', 'test', ?1, ?2, 1, 1, '[100]', ?3)"
            ),
            params![
                db_path,
                PHASE_BROADCAST_SCHEDULED,
                r#"[{"value_zatoshi":100,"block_offset":144}]"#,
            ],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  scheduled_height, status, metadata_json)
                 VALUES ('run-1', 'aa', 'ciphertext', 10, 100, 100, 1, 'bb',
                         0, 101, 1, 20, 'scheduled', '{{}}')"
            ),
            [],
        )
        .unwrap();

        adopt_timing_policy_for_active_run(
            &conn,
            "account-1",
            WalletNetwork::Test,
            MigrationTimingPolicy::FastTestnet,
        )
        .unwrap();

        let (policy, schedule_json): (String, String) = conn
            .query_row(
                &format!(
                    "SELECT timing_policy, schedule_json FROM {RUNS_TABLE} WHERE run_id = 'run-1'"
                ),
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(policy, "standard");
        assert!(schedule_json.contains("144"));
    }

    #[test]
    fn approved_schedule_controls_storage_and_overdue_catch_up() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES ('run-1', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100,200,300]')"
            ),
            params![db_path, PHASE_READY_TO_MIGRATE],
        )
        .unwrap();
        drop(conn);

        let schedule = vec![
            MigrationScheduleEntry {
                part_index: Some(1),
                value_zatoshi: 200,
                block_offset: 1,
            },
            MigrationScheduleEntry {
                part_index: Some(0),
                value_zatoshi: 100,
                block_offset: 2,
            },
            MigrationScheduleEntry {
                part_index: Some(2),
                value_zatoshi: 300,
                block_offset: 3,
            },
        ];
        set_run_approved_schedule(
            &db_path,
            "run-1",
            WalletNetwork::Regtest,
            &schedule,
            &[100, 200, 300],
        )
        .unwrap();

        let pending = [100u64, 200, 300]
            .into_iter()
            .enumerate()
            .map(|(index, value_zatoshi)| {
                let txid_hex = format!("{index:064x}");
                let selected_note = PreparedOrchardNoteRef {
                    txid_hex: format!("{:064x}", index + 10),
                    output_index: 0,
                    value_zatoshi,
                    note_version: 2,
                    nullifier_hex: None,
                };
                PendingMigrationTxInsert {
                    part_index: index as u32,
                    txid_hex,
                    raw_tx: vec![index as u8],
                    target_height: 501,
                    anchor_boundary_height: None,
                    expiry_height: 1_000,
                    value_zatoshi,
                    fee_zatoshi: 10,
                    selected_note: selected_note.clone(),
                    metadata: PendingMigrationTxMetadata {
                        tx_kind: "migration".to_string(),
                        funding_account_uuid: "account-1".to_string(),
                        selected_note,
                    },
                }
            })
            .collect();
        insert_pending_txs(&db_path, "run-1", pending, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();

        let stored = {
            let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
            let mut stmt = conn
                .prepare(
                    "SELECT value_zatoshi, scheduled_height
                     FROM vizor_migration_pending_txs
                     ORDER BY scheduled_height",
                )
                .unwrap();
            stmt.query_map([], |row| Ok((row.get::<_, u64>(0)?, row.get::<_, u32>(1)?)))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap()
        };
        assert_eq!(stored, vec![(200, 501), (100, 502), (300, 503)]);

        let due = due_pending_txs(&db_path, "run-1", 503, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();
        assert_eq!(due.len(), 1);
        mark_pending_broadcasted(&db_path, "run-1", &due[0].txid_hex).unwrap();
        reschedule_overdue_pending_txs(&db_path, "run-1", WalletNetwork::Regtest, 503).unwrap();

        let remaining = scheduled_broadcasts_for_run(
            &open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap(),
            "run-1",
        )
        .unwrap()
        .into_iter()
        .filter(|entry| entry.status == "scheduled")
        .collect::<Vec<_>>();
        assert_eq!(remaining.len(), 2);
        assert!(remaining.iter().all(|entry| entry.scheduled_height > 503));
    }

    #[test]
    fn approved_schedule_part_index_disambiguates_equal_values() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES ('run-1', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100,100]')"
            ),
            params![db_path, PHASE_READY_TO_MIGRATE],
        )
        .unwrap();
        drop(conn);

        let schedule = vec![
            MigrationScheduleEntry {
                part_index: Some(1),
                value_zatoshi: 100,
                block_offset: 1,
            },
            MigrationScheduleEntry {
                part_index: Some(0),
                value_zatoshi: 100,
                block_offset: 2,
            },
        ];
        set_run_approved_schedule(
            &db_path,
            "run-1",
            WalletNetwork::Regtest,
            &schedule,
            &[100, 100],
        )
        .unwrap();

        let pending = [0u32, 1]
            .into_iter()
            .map(|part_index| {
                let selected_note = PreparedOrchardNoteRef {
                    txid_hex: format!("{:064x}", part_index + 10),
                    output_index: 0,
                    value_zatoshi: 110,
                    note_version: 2,
                    nullifier_hex: None,
                };
                PendingMigrationTxInsert {
                    part_index,
                    txid_hex: format!("{part_index:064x}"),
                    raw_tx: vec![part_index as u8],
                    target_height: 501,
                    anchor_boundary_height: None,
                    expiry_height: 1_000,
                    value_zatoshi: 100,
                    fee_zatoshi: 10,
                    selected_note: selected_note.clone(),
                    metadata: PendingMigrationTxMetadata {
                        tx_kind: "migration".to_string(),
                        funding_account_uuid: "account-1".to_string(),
                        selected_note,
                    },
                }
            })
            .collect();
        insert_pending_txs(&db_path, "run-1", pending, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();

        let stored = {
            let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
            let mut stmt = conn
                .prepare(
                    "SELECT part_index, scheduled_height
                     FROM vizor_migration_pending_txs
                     ORDER BY scheduled_height",
                )
                .unwrap();
            stmt.query_map([], |row| Ok((row.get::<_, u32>(0)?, row.get::<_, u32>(1)?)))
                .unwrap()
                .collect::<Result<Vec<_>, _>>()
                .unwrap()
        };
        assert_eq!(stored, vec![(1, 501), (0, 502)]);
    }

    #[test]
    fn expired_pending_transaction_is_resigned_without_changing_its_denomination() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
        ensure_schema(&conn).unwrap();
        let selected_note = PreparedOrchardNoteRef {
            txid_hex: "11".repeat(32),
            output_index: 0,
            value_zatoshi: 110,
            note_version: 2,
            nullifier_hex: None,
        };
        let metadata = PendingMigrationTxMetadata {
            tx_kind: "migration".to_string(),
            funding_account_uuid: "account-1".to_string(),
            selected_note: selected_note.clone(),
        };
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES ('expired-run', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100]')"
            ),
            params![db_path, PHASE_BROADCAST_SCHEDULED],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES ('expired-run', ?1, 0, 110, 2, NULL, 'locked')"
            ),
            params![selected_note.txid_hex],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  scheduled_height, status, metadata_json)
                 VALUES ('expired-run', ?1, 'encrypted', 90, 100, 100, 10, ?2,
                         0, 110, 1, 95, 'scheduled', ?3)"
            ),
            params![
                "22".repeat(32),
                selected_note.txid_hex,
                serde_json::to_string(&metadata).unwrap()
            ],
        )
        .unwrap();
        drop(conn);

        assert_eq!(
            expired_unconfirmed_pending_count(&db_path, "expired-run", 99).unwrap(),
            0
        );
        assert_eq!(
            expired_unconfirmed_pending_count(&db_path, "expired-run", 100).unwrap(),
            1
        );

        assert_eq!(
            mark_expired_pending_parts_for_resign(&db_path, "expired-run", 100).unwrap(),
            1
        );
        let recovery = pending_parts_needing_resign(&db_path, "expired-run").unwrap();
        assert_eq!(recovery.len(), 1);
        assert_eq!(recovery[0].part_index, 0);
        assert_eq!(recovery[0].value_zatoshi, 100);
        assert_eq!(recovery[0].fee_zatoshi, 10);
        assert_eq!(recovery[0].selected_note, selected_note);
        assert!(
            active_migration_run(&db_path, "account-1", WalletNetwork::Regtest)
                .unwrap()
                .is_some()
        );
        assert_eq!(
            locked_migration_note_refs(&db_path, "account-1")
                .unwrap()
                .len(),
            1
        );

        replace_resigned_pending_parts(
            &db_path,
            "expired-run",
            WalletNetwork::Regtest,
            vec![PendingMigrationTxReplacement {
                old_txid_hex: "22".repeat(32),
                replacement: PendingMigrationTxInsert {
                    part_index: 0,
                    txid_hex: "33".repeat(32),
                    raw_tx: vec![1, 2, 3],
                    target_height: 101,
                    anchor_boundary_height: Some(90),
                    expiry_height: 200,
                    value_zatoshi: 100,
                    fee_zatoshi: 10,
                    selected_note: selected_note.clone(),
                    metadata,
                },
            }],
            Vec::new(),
            TEST_PASSWORD,
            TEST_SALT_BASE64,
        )
        .unwrap();

        assert!(pending_parts_needing_resign(&db_path, "expired-run")
            .unwrap()
            .is_empty());
        let totals = pending_totals_for_run(&db_path, "expired-run").unwrap();
        assert_eq!(totals.txids, vec!["33".repeat(32)]);
        assert_eq!(totals.value_zatoshi, 100);
        assert_eq!(totals.fee_zatoshi, 10);
        let replacement_part_index: u32 =
            open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT)
                .unwrap()
                .query_row(
                    &format!(
                        "SELECT part_index FROM {PENDING_TXS_TABLE} WHERE run_id = 'expired-run'"
                    ),
                    [],
                    |row| row.get(0),
                )
                .unwrap();
        assert_eq!(replacement_part_index, 0);
        assert_eq!(
            due_pending_txs(
                &db_path,
                "expired-run",
                200,
                TEST_PASSWORD,
                TEST_SALT_BASE64,
            )
            .unwrap()
            .len(),
            1
        );
        assert_eq!(
            active_migration_run(&db_path, "account-1", WalletNetwork::Regtest)
                .unwrap()
                .unwrap()
                .phase,
            PHASE_BROADCAST_SCHEDULED
        );
        assert_eq!(
            locked_migration_note_refs(&db_path, "account-1")
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn pending_policy_checks_detect_fee_drift_and_only_mined_input_spends() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute_batch(
            "CREATE TABLE transactions (
                 id_tx INTEGER PRIMARY KEY,
                 txid BLOB NOT NULL,
                 mined_height INTEGER
             );
             CREATE TABLE orchard_received_notes (
                 id INTEGER PRIMARY KEY,
                 transaction_id INTEGER NOT NULL,
                 action_index INTEGER NOT NULL,
                 value INTEGER NOT NULL
             );
             CREATE TABLE orchard_received_note_spends (
                 orchard_received_note_id INTEGER NOT NULL,
                 transaction_id INTEGER NOT NULL
             );",
        )
        .unwrap();

        let selected_txid = "31".repeat(32);
        let selected_note = PreparedOrchardNoteRef {
            txid_hex: selected_txid.clone(),
            output_index: 2,
            value_zatoshi: 115_000,
            note_version: 2,
            nullifier_hex: Some("41".repeat(32)),
        };
        let metadata = serde_json::to_string(&PendingMigrationTxMetadata {
            tx_kind: "migration".to_string(),
            funding_account_uuid: "account-1".to_string(),
            selected_note: selected_note.clone(),
        })
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  scheduled_height, status, metadata_json)
                 VALUES ('run-1', ?1, 'encrypted', 90, 200, 100000, 15000, ?2,
                         2, 115000, 1, 100, 'scheduled', ?3)"
            ),
            params!["51".repeat(32), selected_txid, metadata],
        )
        .unwrap();

        assert_eq!(
            noncanonical_unconfirmed_fee_count(&db_path, "run-1", 15_000).unwrap(),
            0
        );
        assert_eq!(
            noncanonical_unconfirmed_fee_count(&db_path, "run-1", 20_000).unwrap(),
            1
        );
        assert!(
            scheduled_inputs_spent_by_mined_transactions(&db_path, "run-1")
                .unwrap()
                .is_empty()
        );

        let source_txid = txid_blob_variants(&selected_note.txid_hex)
            .unwrap()
            .remove(0);
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (1, ?1, 80)",
            params![source_txid],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_notes
             (id, transaction_id, action_index, value) VALUES (1, 1, 2, 115000)",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO transactions (id_tx, txid, mined_height) VALUES (2, ?1, NULL)",
            params![vec![0x61u8; 32]],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO orchard_received_note_spends
             (orchard_received_note_id, transaction_id) VALUES (1, 2)",
            [],
        )
        .unwrap();
        assert!(
            scheduled_inputs_spent_by_mined_transactions(&db_path, "run-1")
                .unwrap()
                .is_empty()
        );

        conn.execute(
            "UPDATE transactions SET mined_height = 99 WHERE id_tx = 2",
            [],
        )
        .unwrap();
        conn.execute(
            "UPDATE transactions SET txid = ?1 WHERE id_tx = 2",
            params![txid_blob_variants(&"51".repeat(32)).unwrap().remove(0)],
        )
        .unwrap();
        assert!(
            scheduled_inputs_spent_by_mined_transactions(&db_path, "run-1")
                .unwrap()
                .is_empty()
        );

        conn.execute(
            "UPDATE transactions SET txid = ?1 WHERE id_tx = 2",
            params![vec![0x61u8; 32]],
        )
        .unwrap();
        assert_eq!(
            scheduled_inputs_spent_by_mined_transactions(&db_path, "run-1").unwrap(),
            vec![selected_note]
        );
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
        assert_eq!(status.parts.len(), 1);
        assert_eq!(status.parts[0].part_index, 0);
        assert_eq!(status.parts[0].state, MigrationPartState::Confirming);
        assert_eq!(status.parts[0].confirmation_count, 1);
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
        assert_eq!(status.parts.len(), 1);
        assert_eq!(status.parts[0].part_index, 0);
        assert_eq!(status.parts[0].state, MigrationPartState::Scheduled);
        assert_eq!(status.parts[0].confirmation_count, 0);
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
    fn migration_parts_report_exact_mixed_states_and_trusted_depth() {
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
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (20)",
            [],
        )
        .unwrap();

        let txids = [
            "10".repeat(32),
            "20".repeat(32),
            "30".repeat(32),
            "40".repeat(32),
        ];
        for (part_index, (txid, status)) in txids
            .iter()
            .zip(["scheduled", "broadcasted", "confirmed", "confirmed"])
            .enumerate()
        {
            conn.execute(
                &format!(
                    "INSERT INTO {PENDING_TXS_TABLE}
                     (run_id, txid_hex, part_index, encrypted_raw_tx, target_height,
                      expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                      selected_note_output_index, selected_note_value, scheduled_at_ms,
                      scheduled_height, status, metadata_json)
                     VALUES ('run-parts', ?1, ?2, 'raw', 1, 100, 100, 1, ?3,
                             0, 101, 1, ?4, ?5, '{{}}')"
                ),
                params![
                    txid,
                    part_index as u32,
                    "aa".repeat(32),
                    part_index + 1,
                    status
                ],
            )
            .unwrap();
        }
        for (txid, mined_height) in [(&txids[2], 20u32), (&txids[3], 18u32)] {
            let mut txid_blob = hex::decode(txid).unwrap();
            txid_blob.reverse();
            conn.execute(
                "INSERT INTO transactions (txid, mined_height) VALUES (?1, ?2)",
                params![txid_blob, mined_height],
            )
            .unwrap();
        }

        let parts = migration_parts_for_run(
            &conn,
            "run-parts",
            &[100, 100, 100, 100],
            PHASE_WAITING_MIGRATION_CONFIRMATIONS,
            3,
        )
        .unwrap();

        assert_eq!(parts.len(), 4);
        assert_eq!(parts[0].state, MigrationPartState::Scheduled);
        assert_eq!(parts[1].state, MigrationPartState::Migrating);
        assert_eq!(parts[2].state, MigrationPartState::Confirming);
        assert_eq!(parts[2].confirmation_count, 1);
        assert_eq!(parts[3].state, MigrationPartState::Completed);
        assert_eq!(parts[3].confirmation_count, 3);
        assert_eq!(
            parts.iter().map(|part| part.part_index).collect::<Vec<_>>(),
            vec![0, 1, 2, 3]
        );
    }

    #[test]
    fn denomination_parts_report_independent_split_stage_states() {
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
        conn.execute(
            "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (20)",
            [],
        )
        .unwrap();

        let run_id = "run-denomination-parts";
        let confirming_txid = "11".repeat(32);
        let preparing_txid = "22".repeat(32);
        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(
            &tx,
            run_id,
            vec![
                pending_test_stage_for_part(0, &confirming_txid, 20_000_000, Some(1)),
                pending_test_stage_for_part(1, &preparing_txid, 10_000_000, Some(0)),
            ],
            TEST_PASSWORD,
            TEST_SALT_BASE64,
        )
        .unwrap();
        tx.commit().unwrap();
        mark_denomination_stage_broadcasted(&conn, run_id, &confirming_txid).unwrap();

        let mut confirming_blob = hex::decode(&confirming_txid).unwrap();
        confirming_blob.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height) VALUES (?1, 19)",
            params![confirming_blob],
        )
        .unwrap();

        let parts = migration_parts_for_run(
            &conn,
            run_id,
            &[10_000_000, 20_000_000],
            PHASE_WAITING_DENOM_CONFIRMATIONS,
            3,
        )
        .unwrap();

        assert_eq!(parts.len(), 2);
        assert_eq!(parts[0].part_index, 0);
        assert_eq!(parts[0].value_zatoshi, 10_000_000);
        assert_eq!(parts[0].state, MigrationPartState::Preparing);
        assert_eq!(parts[0].confirmation_count, 0);
        assert_eq!(parts[1].part_index, 1);
        assert_eq!(parts[1].value_zatoshi, 20_000_000);
        assert_eq!(parts[1].state, MigrationPartState::Confirming);
        assert_eq!(parts[1].confirmation_count, 2);
    }

    #[test]
    fn ready_to_migrate_does_not_report_denomination_parts_as_completed_transfers() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();

        let run_id = "run-ready-denomination-parts";
        let txid = "11".repeat(32);
        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(
            &tx,
            run_id,
            vec![pending_test_stage_for_part(0, &txid, 100_000_000, Some(0))],
            TEST_PASSWORD,
            TEST_SALT_BASE64,
        )
        .unwrap();
        tx.commit().unwrap();
        mark_denomination_stage_confirmed_at(&conn, run_id, &txid, 20, &[0xabu8; 32]).unwrap();

        let parts =
            migration_parts_for_run(&conn, run_id, &[100_000_000], PHASE_READY_TO_MIGRATE, 3)
                .unwrap();

        assert!(parts.is_empty());
    }

    #[test]
    fn legacy_pending_parts_backfill_from_signed_child_identity() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json)
                 VALUES ('legacy-run', 'account-1', 'test', 'db', ?1, 1, 1,
                         '[100,100]')"
            ),
            params![PHASE_BROADCAST_SCHEDULED],
        )
        .unwrap();

        for (part_index, note_txid) in [(0u32, "11".repeat(32)), (1u32, "22".repeat(32))] {
            let selected_note = PreparedOrchardNoteRef {
                txid_hex: note_txid.clone(),
                output_index: 0,
                value_zatoshi: 101,
                note_version: 2,
                nullifier_hex: None,
            };
            conn.execute(
                &format!(
                    "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                     (run_id, message_id, child_index, encrypted_base_pczt,
                      encrypted_compact_sigs, target_height, expiry_height,
                      value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
                     VALUES ('legacy-run', ?1, ?2, 'base', 'sigs', 1, 100,
                             100, 1, ?3, '{{}}')"
                ),
                params![
                    format!("message-{part_index}"),
                    part_index,
                    serde_json::to_string(&selected_note).unwrap()
                ],
            )
            .unwrap();
            conn.execute(
                &format!(
                    "INSERT INTO {PENDING_TXS_TABLE}
                     (run_id, txid_hex, encrypted_raw_tx, target_height, expiry_height,
                      value_zatoshi, fee_zatoshi, selected_note_txid,
                      selected_note_output_index, selected_note_value, scheduled_at_ms,
                      scheduled_height, status, metadata_json)
                     VALUES ('legacy-run', ?1, 'raw', 1, 100, 100, 1, ?2,
                             0, 101, 1, ?3, 'scheduled', '{{}}')"
                ),
                params![
                    format!("{:064x}", part_index + 50),
                    note_txid,
                    20 - part_index
                ],
            )
            .unwrap();
        }

        backfill_pending_part_indices(&conn).unwrap();
        let mut stmt = conn
            .prepare(&format!(
                "SELECT lower(selected_note_txid), part_index
                 FROM {PENDING_TXS_TABLE} WHERE run_id = 'legacy-run'"
            ))
            .unwrap();
        let assigned = stmt
            .query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?))
            })
            .unwrap()
            .collect::<Result<BTreeMap<_, _>, _>>()
            .unwrap();
        assert_eq!(assigned[&"11".repeat(32)], 0);
        assert_eq!(assigned[&"22".repeat(32)], 1);
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
