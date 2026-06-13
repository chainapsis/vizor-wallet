use std::collections::BTreeSet;
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

pub(crate) const ZATOSHIS_PER_ZEC: u64 = 100_000_000;
pub(crate) const MIGRATION_BROADCAST_WINDOW_SECS: u64 = 180;
pub(crate) const MIGRATION_MAX_PREPARED_NOTES_PER_RUN: usize = 64;
pub(crate) const MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI: u64 = 1;
// Mirrors the one-action ZIP-317 migration fee estimate used by send planning.
const MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI: u64 = 10_000;

const RUNS_TABLE: &str = "vizor_migration_runs";
const PREPARED_NOTES_TABLE: &str = "vizor_migration_prepared_notes";
const PREP_TXS_TABLE: &str = "vizor_migration_prep_txs";
const PENDING_TXS_TABLE: &str = "vizor_migration_pending_txs";
const SIGNED_CHILD_PCZTS_TABLE: &str = "vizor_migration_signed_child_pczts";

pub(crate) const PHASE_NO_ORCHARD_FUNDS: &str = "no_orchard_funds";
pub(crate) const PHASE_WAITING_FOR_SPENDABLE_ORCHARD: &str = "waiting_for_spendable_orchard";
pub(crate) const PHASE_READY_TO_PREPARE: &str = "ready_to_prepare";
pub(crate) const PHASE_PREPARING_DENOMINATIONS: &str = "preparing_denominations";
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
    pub migration_outputs: Vec<u64>,
    pub orchard_change: Option<u64>,
    pub prep_fee_zatoshi: u64,
    pub migration_fee_zatoshi: u64,
    pub total_input_zatoshi: u64,
    pub total_migratable_zatoshi: u64,
}

pub(crate) fn plan_denominations(
    total_input_zatoshi: u64,
    prep_fee_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<DenominationPlan, String> {
    if total_input_zatoshi <= prep_fee_zatoshi {
        return Ok(DenominationPlan {
            migration_outputs: Vec::new(),
            orchard_change: None,
            prep_fee_zatoshi: total_input_zatoshi,
            migration_fee_zatoshi,
            total_input_zatoshi,
            total_migratable_zatoshi: 0,
        });
    }

    let available = total_input_zatoshi
        .checked_sub(prep_fee_zatoshi)
        .ok_or("Denomination prep fee underflow")?;
    let whole_zec = available / ZATOSHIS_PER_ZEC;
    let mut remainder = available % ZATOSHIS_PER_ZEC;
    let mut outputs = Vec::new();

    let mut denom = 1u64;
    while denom <= whole_zec / 10 {
        denom = denom.checked_mul(10).ok_or("Denomination overflow")?;
    }

    let mut remaining_whole = whole_zec;
    while denom > 0 {
        while remaining_whole >= denom {
            outputs.push(
                denom
                    .checked_mul(ZATOSHIS_PER_ZEC)
                    .ok_or("Denomination zatoshi overflow")?,
            );
            remaining_whole -= denom;
        }
        denom /= 10;
    }

    let migratable_residual_threshold = migration_fee_zatoshi
        .checked_add(minimum_output_zatoshi)
        .ok_or("Residual fee threshold overflow")?;
    let orchard_change = if remainder > migratable_residual_threshold {
        outputs.push(remainder);
        None
    } else if remainder >= minimum_output_zatoshi {
        Some(remainder)
    } else {
        remainder = 0;
        None
    };

    if outputs.len() > MIGRATION_MAX_PREPARED_NOTES_PER_RUN {
        return Err(format!(
            "Migration plan would create {} prepared notes, above the {} note limit",
            outputs.len(),
            MIGRATION_MAX_PREPARED_NOTES_PER_RUN
        ));
    }

    let total_migratable_zatoshi = outputs.iter().try_fold(0u64, |acc, value| {
        acc.checked_add(*value)
            .ok_or("Migratable total overflow".to_string())
    })?;

    // When `remainder` is below minimum output it intentionally becomes extra
    // transaction fee. Keep the variable assignment explicit so tests can lock
    // the policy.
    let _dust_remainder_added_to_fee = remainder < minimum_output_zatoshi;

    Ok(DenominationPlan {
        migration_outputs: outputs,
        orchard_change,
        prep_fee_zatoshi,
        migration_fee_zatoshi,
        total_input_zatoshi,
        total_migratable_zatoshi,
    })
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
    pub signed_pczt: Vec<u8>,
    pub target_height: u32,
    pub expiry_height: u32,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
}

pub(crate) struct SignedMigrationPczt {
    pub base_pczt: Vec<u8>,
    pub signed_pczt: Vec<u8>,
    pub target_height: u32,
    pub expiry_height: u32,
    pub value_zatoshi: u64,
    pub fee_zatoshi: u64,
    pub selected_note: PreparedOrchardNoteRef,
    pub metadata: PendingMigrationTxMetadata,
}

pub(crate) struct MigrationPrepTx {
    pub txid_hex: String,
    pub raw_tx: Vec<u8>,
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
    pub pending_tx_count: u32,
    pub broadcasted_tx_count: u32,
    pub confirmed_tx_count: u32,
    pub total_count: u32,
    pub signed_child_pczt_count: u32,
    pub pending_prep_tx_count: u32,
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
) -> Result<MigrationStatus, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;

    if let Some(run) = active_run(&conn, account_uuid, network)? {
        let original_run = run.clone();
        reconcile_denomination_confirmations(&conn, &run)?;
        reconcile_run_confirmations(&conn, &run.run_id)?;
        let run = active_run(&conn, account_uuid, network)?.unwrap_or(original_run);
        return status_for_run(&conn, run);
    }

    let orchard_migratable = orchard_balance_can_create_migration_output(orchard_spendable)?;
    let phase = if orchard_migratable {
        PHASE_READY_TO_PREPARE
    } else if orchard_pending > 0 {
        PHASE_WAITING_FOR_SPENDABLE_ORCHARD
    } else if ironwood_spendable > 0 {
        PHASE_COMPLETE
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
        pending_tx_count: 0,
        broadcasted_tx_count: 0,
        confirmed_tx_count: 0,
        total_count: 0,
        signed_child_pczt_count: 0,
        pending_prep_tx_count: 0,
        message: None,
        can_abandon: false,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        broadcast_window_seconds: MIGRATION_BROADCAST_WINDOW_SECS,
        max_prepared_notes_per_run: MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        scheduled_broadcasts: Vec::new(),
    })
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

pub(crate) fn create_run_with_prepared_notes_and_signed_children(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    plan: &DenominationPlan,
    prepared_notes: &[PreparedOrchardNoteRef],
    locked: bool,
    signed_children: Vec<SignedMigrationPcztInsert>,
    password: &[u8],
    salt_base64: &str,
    prep_txid: Option<&str>,
    prep_raw_tx: Option<Vec<u8>>,
) -> Result<String, String> {
    if prep_raw_tx.is_some() && prep_txid.is_none() {
        return Err("Migration prep raw transaction requires a txid".to_string());
    }

    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    if let Some(run) = active_run(&conn, account_uuid, network)? {
        return Err(format!("Migration already active: {}", run.run_id));
    }

    let run_id = new_run_id(account_uuid);
    let now = now_ms()?;
    let phase = if prep_txid.is_some() {
        PHASE_WAITING_DENOM_CONFIRMATIONS
    } else {
        PHASE_PREPARING_DENOMINATIONS
    };
    let target_values_json = serde_json::to_string(&plan.migration_outputs)
        .map_err(|e| format!("Encode migration targets: {e}"))?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration run staging: {e}"))?;
    tx.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase, created_at_ms,
              updated_at_ms, prep_txid, target_values_json)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8)"
        ),
        params![
            run_id,
            account_uuid,
            network_name(network),
            db_path,
            phase,
            now,
            prep_txid,
            target_values_json,
        ],
    )
    .map_err(|e| format!("Create migration run: {e}"))?;
    insert_prepared_notes_with_tx(&tx, &run_id, prepared_notes, locked)?;
    if let Some(raw_tx) = prep_raw_tx {
        let prep_txid = prep_txid.ok_or("Migration prep raw transaction requires a txid")?;
        insert_prep_tx_with_tx(&tx, &run_id, prep_txid, raw_tx, password, salt_base64)?;
    }
    insert_signed_child_pczts_with_tx(&tx, &run_id, signed_children, password, salt_base64)?;
    tx.commit()
        .map_err(|e| format!("Commit migration run staging: {e}"))?;
    Ok(run_id)
}

pub(crate) fn create_run_with_prepared_notes_and_prep_tx(
    db_path: &str,
    account_uuid: &str,
    network: WalletNetwork,
    plan: &DenominationPlan,
    prepared_notes: &[PreparedOrchardNoteRef],
    locked: bool,
    prep_txid: &str,
    prep_raw_tx: Vec<u8>,
    password: &[u8],
    salt_base64: &str,
) -> Result<String, String> {
    create_run_with_prepared_notes_and_signed_children(
        db_path,
        account_uuid,
        network,
        plan,
        prepared_notes,
        locked,
        Vec::new(),
        password,
        salt_base64,
        Some(prep_txid),
        Some(prep_raw_tx),
    )
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

fn insert_prep_tx_with_tx(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    txid_hex: &str,
    raw_tx: Vec<u8>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration prep tx salt")?;
    let encrypted_raw_tx =
        secret_payload::encrypt_payload(Zeroizing::new(raw_tx), password, salt.as_slice())?;
    tx.execute(
        &format!(
            "INSERT OR REPLACE INTO {PREP_TXS_TABLE}
             (run_id, txid_hex, encrypted_raw_tx, status)
             VALUES (?1, ?2, ?3, 'pending')"
        ),
        params![run_id, txid_hex, encrypted_raw_tx],
    )
    .map_err(|e| format!("Insert migration prep tx: {e}"))?;
    Ok(())
}

pub(crate) fn pending_prep_tx_for_run(
    db_path: &str,
    run_id: &str,
    password: &[u8],
    salt_base64: &str,
) -> Result<Option<MigrationPrepTx>, String> {
    let salt = secret_payload::decode_base64(salt_base64.as_bytes(), "migration prep tx salt")?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let row = conn
        .query_row(
            &format!(
                "SELECT txid_hex, encrypted_raw_tx
                 FROM {PREP_TXS_TABLE}
                 WHERE run_id = ?1 AND status = 'pending'"
            ),
            params![run_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()
        .map_err(|e| format!("Read migration prep tx: {e}"))?;
    let Some((txid_hex, encrypted_raw_tx)) = row else {
        return Ok(None);
    };
    let raw_tx =
        secret_payload::decrypt_payload(encrypted_raw_tx.as_bytes(), password, salt.as_slice())?;
    Ok(Some(MigrationPrepTx {
        txid_hex,
        raw_tx: raw_tx.to_vec(),
    }))
}

pub(crate) fn mark_prep_tx_broadcasted(db_path: &str, run_id: &str) -> Result<String, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    let now = now_ms()?;
    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration prep broadcast update: {e}"))?;
    tx.execute(
        &format!(
            "UPDATE {PREP_TXS_TABLE}
             SET status = 'broadcasted'
             WHERE run_id = ?1"
        ),
        params![run_id],
    )
    .map_err(|e| format!("Mark migration prep tx broadcasted: {e}"))?;
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET updated_at_ms = ?1, last_error = NULL
             WHERE run_id = ?2"
        ),
        params![now, run_id],
    )
    .map_err(|e| format!("Clear migration prep broadcast message: {e}"))?;
    let phase = tx
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration prep broadcast phase: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit migration prep broadcast update: {e}"))?;
    Ok(phase)
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
        &format!("DELETE FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1"),
        params![run_id],
    )
    .map_err(|e| format!("Delete promoted signed migration PCZTs: {e}"))?;
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
                  value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value, scheduled_at_ms,
                  status, metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 'scheduled', ?12)"
                ),
                params![
                    run_id,
                    pending.txid_hex,
                    encrypted_raw_tx,
                    pending.target_height,
                    pending.expiry_height,
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
        let encrypted_signed_pczt = secret_payload::encrypt_payload(
            Zeroizing::new(child.signed_pczt),
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
                  encrypted_signed_pczt, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_json,
                  metadata_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"
            ),
            params![
                run_id,
                child.message_id,
                child.child_index,
                encrypted_base_pczt,
                encrypted_signed_pczt,
                child.target_height,
                child.expiry_height,
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
            "SELECT encrypted_base_pczt, encrypted_signed_pczt,
                    target_height, expiry_height, value_zatoshi, fee_zatoshi,
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
                row.get::<_, u64>(4)?,
                row.get::<_, u64>(5)?,
                row.get::<_, String>(6)?,
                row.get::<_, String>(7)?,
            ))
        })
        .map_err(|e| format!("Query signed migration PCZTs: {e}"))?;

    let mut signed = Vec::new();
    for row in rows {
        let (
            encrypted_base_pczt,
            encrypted_signed_pczt,
            target_height,
            expiry_height,
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
        let signed_pczt = secret_payload::decrypt_payload(
            encrypted_signed_pczt.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        let selected_note = serde_json::from_str::<PreparedOrchardNoteRef>(&selected_note_json)
            .map_err(|e| format!("Decode signed migration PCZT note: {e}"))?;
        let metadata = serde_json::from_str::<PendingMigrationTxMetadata>(&metadata_json)
            .map_err(|e| format!("Decode signed migration PCZT metadata: {e}"))?;

        signed.push(SignedMigrationPczt {
            base_pczt: base_pczt.to_vec(),
            signed_pczt: signed_pczt.to_vec(),
            target_height,
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
    count_for_run(&conn, SIGNED_CHILD_PCZTS_TABLE, run_id)
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

pub(crate) fn clear_retriable_pending_txs(db_path: &str, run: &ActiveRun) -> Result<bool, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    clear_retriable_pending_txs_with_conn(&conn, run)
}

fn clear_retriable_pending_txs_with_conn(
    conn: &rusqlite::Connection,
    run: &ActiveRun,
) -> Result<bool, String> {
    if run.phase != PHASE_FAILED_RECOVERABLE
        || !failure_can_rebuild_pending_txs(run.last_error.as_deref())
    {
        return Ok(false);
    }
    if !table_exists(conn, PENDING_TXS_TABLE)? {
        return Ok(false);
    }

    let scheduled_count = count_pending_with_status(conn, &run.run_id, "scheduled")?;
    if scheduled_count == 0 {
        return Ok(false);
    }
    let non_scheduled_count: u32 = conn
        .query_row(
            &format!(
                "SELECT COUNT(*)
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = ?1 AND status != 'scheduled'"
            ),
            params![run.run_id],
            |row| row.get::<_, u32>(0),
        )
        .map_err(|e| format!("Count non-retriable migration pending txs: {e}"))?;
    if non_scheduled_count > 0 {
        return Ok(false);
    }

    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin migration retry reset: {e}"))?;
    tx.execute(
        &format!("DELETE FROM {PENDING_TXS_TABLE} WHERE run_id = ?1 AND status = 'scheduled'"),
        params![run.run_id],
    )
    .map_err(|e| format!("Clear expired migration pending txs: {e}"))?;
    let now = now_ms()?;
    tx.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET phase = ?1, updated_at_ms = ?2, last_error = NULL
             WHERE run_id = ?3"
        ),
        params![PHASE_READY_TO_MIGRATE, now, run.run_id],
    )
    .map_err(|e| format!("Reset migration run for retry: {e}"))?;
    tx.commit()
        .map_err(|e| format!("Commit migration retry reset: {e}"))?;
    Ok(true)
}

fn failure_can_rebuild_pending_txs(message: Option<&str>) -> bool {
    let Some(message) = message else {
        return false;
    };
    let lower = message.to_ascii_lowercase();
    lower.contains("expiry") || lower.contains("expired")
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
    let conn = match open_readonly_conn_with_timeout(db_path, Some(READ_DB_BUSY_TIMEOUT)) {
        Ok(conn) => conn,
        Err(e) => {
            log::warn!("migration locks: failed to open readonly DB: {e}");
            return Ok(BTreeSet::new());
        }
    };
    if !table_exists(&conn, PREPARED_NOTES_TABLE)? {
        return Ok(BTreeSet::new());
    }

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
        .map_err(|e| format!("Read migration locks: {e}"))
}

fn status_for_run(conn: &rusqlite::Connection, run: ActiveRun) -> Result<MigrationStatus, String> {
    let prepared_note_count = count_for_run(conn, PREPARED_NOTES_TABLE, &run.run_id)?;
    let pending_prep_tx_count = pending_prep_tx_count_for_run(conn, &run.run_id)?;
    let pending_tx_count = count_for_run(conn, PENDING_TXS_TABLE, &run.run_id)?;
    let broadcasted_tx_count = count_pending_with_status(conn, &run.run_id, "broadcasted")?;
    let confirmed_tx_count = count_pending_with_status(conn, &run.run_id, "confirmed")?;
    let scheduled_broadcasts = scheduled_broadcasts_for_run(conn, &run.run_id)?;
    let signed_child_pczt_count = count_for_run(conn, SIGNED_CHILD_PCZTS_TABLE, &run.run_id)?;
    let total_count = run.target_values_zatoshi.len() as u32;
    let mut phase = if total_count > 0 && confirmed_tx_count >= total_count {
        PHASE_COMPLETE.to_string()
    } else {
        run.phase
    };
    if phase == PHASE_READY_TO_MIGRATE
        && pending_tx_count == 0
        && prepared_note_count > 0
        && !prepared_note_spend_metadata_available_for_run(conn, &run.run_id)?
    {
        phase = PHASE_WAITING_DENOM_CONFIRMATIONS.to_string();
    }
    let denomination_confirmation_target = denomination_confirmations_required();
    let denomination_confirmation_count = if phase == PHASE_WAITING_DENOM_CONFIRMATIONS {
        denomination_confirmation_count_for_run(conn, &run.run_id)?
    } else if prepared_note_count > 0
        && phase != PHASE_PREPARING_DENOMINATIONS
        && phase != PHASE_FAILED_TERMINAL
        && phase != PHASE_ABANDONED
    {
        denomination_confirmation_target
    } else {
        0
    };
    let can_abandon = matches!(
        phase.as_str(),
        PHASE_PREPARING_DENOMINATIONS
            | PHASE_WAITING_DENOM_CONFIRMATIONS
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
        pending_tx_count,
        broadcasted_tx_count,
        confirmed_tx_count,
        total_count,
        signed_child_pczt_count,
        pending_prep_tx_count,
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
            "SELECT txid_hex
             FROM {PENDING_TXS_TABLE}
             WHERE run_id = ?1 AND status IN ('scheduled', 'broadcasted')"
        ))
        .map_err(|e| format!("Prepare migration confirmation query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Query migration confirmation txs: {e}"))?;
    let txids = rows
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration confirmation txs: {e}"))?;

    for txid_hex in txids {
        if local_transaction_is_confirmed(conn, &txid_hex)? {
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
    }

    let total_count = count_for_run(conn, PENDING_TXS_TABLE, run_id)?;
    let confirmed_count = count_pending_with_status(conn, run_id, "confirmed")?;
    if total_count > 0 && confirmed_count >= total_count {
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

fn denomination_confirmation_count_for_run(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<u32, String> {
    let Some(confirmed) = confirmed_prepared_denomination_notes(conn, run_id)? else {
        return Ok(0);
    };
    if confirmed.is_empty() {
        return Ok(0);
    }
    let max_mined_height = confirmed
        .iter()
        .map(|(_, _, _, height)| *height)
        .max()
        .unwrap_or(0);
    synced_orchard_confirmation_count(conn, max_mined_height)
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

fn pending_prep_tx_count_for_run(conn: &rusqlite::Connection, run_id: &str) -> Result<u32, String> {
    if !table_exists(conn, PREP_TXS_TABLE)? {
        return Ok(0);
    }
    conn.query_row(
        &format!(
            "SELECT COUNT(*)
             FROM {PREP_TXS_TABLE}
             WHERE run_id = ?1 AND status = 'pending'"
        ),
        params![run_id],
        |row| row.get::<_, u32>(0),
    )
    .map_err(|e| format!("Count pending migration prep txs: {e}"))
}

fn synced_orchard_confirmation_count(
    conn: &rusqlite::Connection,
    height: u32,
) -> Result<u32, String> {
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

    Ok(latest_checkpoint
        .map(|checkpoint| {
            if checkpoint < height {
                0
            } else {
                checkpoint - height + 1
            }
        })
        .unwrap_or(0)
        .min(denomination_confirmations_required()))
}

fn local_transaction_is_confirmed(
    conn: &rusqlite::Connection,
    txid_hex: &str,
) -> Result<bool, String> {
    for txid_blob in txid_blob_variants(txid_hex)? {
        let mined = conn
            .query_row(
                "SELECT mined_height IS NOT NULL FROM transactions WHERE txid = ?1",
                params![txid_blob],
                |row| row.get::<_, bool>(0),
            )
            .optional()
            .map_err(|e| format!("Read migration tx confirmation state: {e}"))?;
        if mined.unwrap_or(false) {
            return Ok(true);
        }
    }
    Ok(false)
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
            prep_txid TEXT,
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

        CREATE TABLE IF NOT EXISTS {PREP_TXS_TABLE} (
            run_id TEXT PRIMARY KEY,
            txid_hex TEXT NOT NULL,
            encrypted_raw_tx TEXT NOT NULL,
            status TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS {PENDING_TXS_TABLE} (
            run_id TEXT NOT NULL,
            txid_hex TEXT PRIMARY KEY,
            encrypted_raw_tx TEXT NOT NULL,
            target_height INTEGER NOT NULL,
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
            encrypted_signed_pczt TEXT NOT NULL,
            target_height INTEGER NOT NULL,
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
    .map_err(|e| format!("Initialize migration schema: {e}"))
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
        WalletNetwork::LocalIronwoodTestnet => "local_ironwood_testnet",
        WalletNetwork::Regtest => "regtest",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn planner_noops_when_prep_fee_consumes_balance() {
        let plan = plan_denominations(5_000, 10_000, 10_000, 1).unwrap();

        assert!(plan.migration_outputs.is_empty());
        assert_eq!(plan.total_migratable_zatoshi, 0);
        assert_eq!(plan.prep_fee_zatoshi, 5_000);
    }

    #[test]
    fn planner_creates_decimal_denominations_and_fee_positive_residual() {
        let plan = plan_denominations(1_234_500_000, 0, 10_000, MINIMUM_OUTPUT_FOR_TEST).unwrap();

        assert_eq!(
            plan.migration_outputs,
            vec![1_000_000_000, 100_000_000, 100_000_000, 34_500_000]
        );
        assert_eq!(plan.orchard_change, None);
        assert_eq!(plan.total_migratable_zatoshi, 1_234_500_000);
    }

    #[test]
    fn planner_keeps_non_fee_positive_residual_as_orchard_change() {
        let plan = plan_denominations(100_010_000, 0, 10_000, MINIMUM_OUTPUT_FOR_TEST).unwrap();

        assert_eq!(plan.migration_outputs, vec![100_000_000]);
        assert_eq!(plan.orchard_change, Some(10_000));
    }

    #[test]
    fn planner_reserves_prep_fee_before_decomposition() {
        let plan = plan_denominations(1_000_000_000, 10_000, 10_000, 1).unwrap();

        assert_eq!(
            plan.migration_outputs,
            vec![
                100_000_000,
                100_000_000,
                100_000_000,
                100_000_000,
                100_000_000,
                100_000_000,
                100_000_000,
                100_000_000,
                100_000_000,
                99_990_000,
            ]
        );
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
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_COMPLETE);
    }

    #[test]
    fn migration_status_treats_threshold_residual_as_complete() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();

        let status = migration_status(
            &db_path,
            WalletNetwork::Test,
            "account-1",
            MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI + MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI,
            0,
            ZATOSHIS_PER_ZEC,
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
            prep_fee_zatoshi: 10_000,
            migration_fee_zatoshi: MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI,
            total_input_zatoshi: ZATOSHIS_PER_ZEC + 20_000,
            total_migratable_zatoshi: ZATOSHIS_PER_ZEC,
        };
        let run_id = create_run_with_prepared_notes_and_signed_children(
            &db_path,
            "account-1",
            WalletNetwork::Test,
            &plan,
            &[],
            false,
            Vec::new(),
            b"correct horse battery staple",
            "AQIDBAUGBwgJCgsMDQ4PEA==",
            None,
            None,
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
            MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI + MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI + 1,
            0,
            ZATOSHIS_PER_ZEC,
        )
        .unwrap();

        assert_eq!(status.phase, PHASE_READY_TO_PREPARE);
    }

    #[test]
    fn create_run_with_prep_tx_stages_pending_broadcast_state() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let txid_hex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
        let plan = DenominationPlan {
            migration_outputs: vec![100_000_000],
            orchard_change: None,
            prep_fee_zatoshi: 10_000,
            migration_fee_zatoshi: 10_000,
            total_input_zatoshi: 100_010_000,
            total_migratable_zatoshi: 100_000_000,
        };
        let prepared_notes = vec![PreparedOrchardNoteRef {
            txid_hex: txid_hex.to_string(),
            output_index: 0,
            value_zatoshi: 100_000_000,
            note_version: 2,
            nullifier_hex: None,
        }];
        let raw_tx = vec![1, 2, 3, 4];

        let run_id = create_run_with_prepared_notes_and_prep_tx(
            &db_path,
            "account-1",
            WalletNetwork::Test,
            &plan,
            &prepared_notes,
            true,
            txid_hex,
            raw_tx.clone(),
            b"correct horse battery staple",
            "AQIDBAUGBwgJCgsMDQ4PEA==",
        )
        .unwrap();

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let (phase, prep_txid): (String, Option<String>) = conn
            .query_row(
                &format!("SELECT phase, prep_txid FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert_eq!(prep_txid.as_deref(), Some(txid_hex));

        let lock_state: String = conn
            .query_row(
                &format!("SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(lock_state, "locked");

        let prep_tx = pending_prep_tx_for_run(
            &db_path,
            &run_id,
            b"correct horse battery staple",
            "AQIDBAUGBwgJCgsMDQ4PEA==",
        )
        .unwrap()
        .unwrap();
        assert_eq!(prep_tx.txid_hex, txid_hex);
        assert_eq!(prep_tx.raw_tx, raw_tx);
    }

    #[test]
    fn create_run_with_prep_tx_rolls_back_on_encrypt_failure() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let db_path = db_path.to_string_lossy().to_string();
        let txid_hex = "101112131415161718191a1b1c1d1e1f000102030405060708090a0b0c0d0e0f";
        let plan = DenominationPlan {
            migration_outputs: vec![100_000_000],
            orchard_change: None,
            prep_fee_zatoshi: 10_000,
            migration_fee_zatoshi: 10_000,
            total_input_zatoshi: 100_010_000,
            total_migratable_zatoshi: 100_000_000,
        };
        let prepared_notes = vec![PreparedOrchardNoteRef {
            txid_hex: txid_hex.to_string(),
            output_index: 0,
            value_zatoshi: 100_000_000,
            note_version: 2,
            nullifier_hex: None,
        }];

        let err = create_run_with_prepared_notes_and_prep_tx(
            &db_path,
            "account-1",
            WalletNetwork::Test,
            &plan,
            &prepared_notes,
            true,
            txid_hex,
            vec![1, 2, 3, 4],
            b"correct horse battery staple",
            "not base64",
        )
        .unwrap_err();
        assert!(err.contains("Failed to decode migration prep tx salt"));

        let conn = rusqlite::Connection::open(&db_path).unwrap();
        let run_count: i64 = conn
            .query_row(&format!("SELECT COUNT(*) FROM {RUNS_TABLE}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        let note_count: i64 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {PREPARED_NOTES_TABLE}"),
                [],
                |row| row.get(0),
            )
            .unwrap();
        let prep_count: i64 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {PREP_TXS_TABLE}"),
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(run_count, 0);
        assert_eq!(note_count, 0);
        assert_eq!(prep_count, 0);
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
                PHASE_WAITING_MIGRATION_CONFIRMATIONS,
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
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height,
                  expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value,
                  scheduled_at_ms, status, metadata_json)
                 VALUES (?1, ?2, 'encrypted', 10, 30, 99990000, 10000,
                         ?2, 0, 100000000, 1, 'broadcasted', '{{}}')"
            ),
            params![run_id, txid_hex],
        )
        .unwrap();

        let mut txid_blob = hex::decode(txid_hex).unwrap();
        txid_blob.reverse();
        conn.execute(
            "INSERT INTO transactions (txid, mined_height) VALUES (?1, 20)",
            params![txid_blob],
        )
        .unwrap();

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
        assert_eq!(phase, PHASE_READY_TO_MIGRATE);
        let nullifier_hex: String = conn
            .query_row(
                &format!("SELECT nullifier_hex FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(nullifier_hex, "ab".repeat(32));
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
            &format!(
                "INSERT INTO {PREP_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, status)
                 VALUES (?1, ?2, 'raw', 'pending')"
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
        assert_eq!(status.pending_prep_tx_count, 1);

        conn.execute(
            &format!(
                "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_signed_pczt, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
                 VALUES (?1, 'migration-1', 0, 'base', 'signed', 10, 20,
                         99980000, 20000, '{{}}', '{{}}')"
            ),
            params![run_id],
        )
        .unwrap();

        let status = status_for_run(&conn, run.clone()).unwrap();
        assert_eq!(status.phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
        assert_eq!(status.signed_child_pczt_count, 1);
        assert_eq!(status.pending_prep_tx_count, 1);

        conn.execute(
            "UPDATE orchard_received_notes SET commitment_tree_position = 0",
            [],
        )
        .unwrap();
        conn.execute(
            &format!("UPDATE {PREP_TXS_TABLE} SET status = 'broadcasted' WHERE run_id = ?1"),
            params![run_id],
        )
        .unwrap();

        let status = status_for_run(&conn, run).unwrap();
        assert_eq!(status.phase, PHASE_READY_TO_MIGRATE);
        assert_eq!(status.pending_prep_tx_count, 0);
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
    fn retry_reset_clears_unbroadcasted_expired_pending_txs() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        let run = insert_failed_run(
            &conn,
            "run-retry",
            Some(
                "Migration broadcast failed. Error: transaction must not be mined greater than its expiry Height(616)",
            ),
        );
        insert_prepared_note(&conn, &run.run_id);
        insert_pending_tx(
            &conn,
            &run.run_id,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "scheduled",
        );
        insert_pending_tx(
            &conn,
            &run.run_id,
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "scheduled",
        );

        assert!(clear_retriable_pending_txs_with_conn(&conn, &run).unwrap());

        let pending_count: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {PENDING_TXS_TABLE} WHERE run_id = ?1"),
                params![run.run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(pending_count, 0);
        let (phase, last_error): (String, Option<String>) = conn
            .query_row(
                &format!("SELECT phase, last_error FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run.run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(phase, PHASE_READY_TO_MIGRATE);
        assert!(last_error.is_none());
        let lock_state: String = conn
            .query_row(
                &format!("SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
                params![run.run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(lock_state, "locked");
    }

    #[test]
    fn retry_reset_refuses_partially_broadcast_expired_run() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        let run = insert_failed_run(&conn, "run-partial", Some("transaction expired"));
        insert_pending_tx(
            &conn,
            &run.run_id,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "scheduled",
        );
        insert_pending_tx(
            &conn,
            &run.run_id,
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "broadcasted",
        );

        assert!(!clear_retriable_pending_txs_with_conn(&conn, &run).unwrap());

        let pending_count: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {PENDING_TXS_TABLE} WHERE run_id = ?1"),
                params![run.run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(pending_count, 2);
        let phase: String = conn
            .query_row(
                &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
                params![run.run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(phase, PHASE_FAILED_RECOVERABLE);
    }

    #[test]
    fn retry_reset_refuses_non_expiry_failures() {
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        ensure_schema(&conn).unwrap();
        let run = insert_failed_run(&conn, "run-network", Some("lightwalletd unavailable"));
        insert_pending_tx(
            &conn,
            &run.run_id,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "scheduled",
        );

        assert!(!clear_retriable_pending_txs_with_conn(&conn, &run).unwrap());

        let pending_count: u32 = conn
            .query_row(
                &format!("SELECT COUNT(*) FROM {PENDING_TXS_TABLE} WHERE run_id = ?1"),
                params![run.run_id],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(pending_count, 1);
    }

    fn insert_failed_run(
        conn: &rusqlite::Connection,
        run_id: &str,
        last_error: Option<&str>,
    ) -> ActiveRun {
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json, last_error)
                 VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1,
                         '[100000000]', ?3)"
            ),
            params![run_id, PHASE_FAILED_RECOVERABLE, last_error],
        )
        .unwrap();
        ActiveRun {
            run_id: run_id.to_string(),
            phase: PHASE_FAILED_RECOVERABLE.to_string(),
            target_values_zatoshi: vec![100_000_000],
            last_error: last_error.map(ToString::to_string),
        }
    }

    fn insert_prepared_note(conn: &rusqlite::Connection, run_id: &str) {
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES (?1,
                         'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                         0, 100000000, 2, NULL, 'locked')"
            ),
            params![run_id],
        )
        .unwrap();
    }

    fn insert_pending_tx(conn: &rusqlite::Connection, run_id: &str, txid_hex: &str, status: &str) {
        conn.execute(
            &format!(
                "INSERT INTO {PENDING_TXS_TABLE}
                 (run_id, txid_hex, encrypted_raw_tx, target_height,
                  expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
                  selected_note_output_index, selected_note_value,
                  scheduled_at_ms, status, metadata_json)
                 VALUES (?1, ?2, 'encrypted', 10, 30, 99990000, 10000,
                         ?2, 0, 100000000, 1, ?3, '{{}}')"
            ),
            params![run_id, txid_hex, status],
        )
        .unwrap();
    }

    const MINIMUM_OUTPUT_FOR_TEST: u64 = 1;
}
