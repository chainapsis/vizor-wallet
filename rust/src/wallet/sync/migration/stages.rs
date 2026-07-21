use std::collections::BTreeSet;

use pczt::roles::signer::SpendAuthSignature;
use rusqlite::{params, Connection, OptionalExtension, Transaction};
use zeroize::Zeroizing;

use crate::wallet::{keystone, secret_payload};

const STAGES_TABLE: &str = "vizor_migration_denomination_stages";
const STAGE_INPUTS_TABLE: &str = "vizor_migration_denomination_stage_inputs";
const STAGE_OUTPUTS_TABLE: &str = "vizor_migration_denomination_stage_outputs";
const INSERT_SAVEPOINT: &str = "vizor_insert_denomination_stages";

/// Persistence state for one signed denomination-split transaction.
///
/// An awaiting stage has signed effecting data but cannot be proved and
/// extracted until all of its inputs are confirmed. Promotion stores the raw
/// transaction without removing the base PCZT or compact signatures, so a
/// reorg can rebuild the transaction with a new anchor and witness.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DenominationStageStatus {
    AwaitingInputs,
    Pending,
    Broadcasted,
    Confirmed,
}

impl DenominationStageStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::AwaitingInputs => "awaiting_inputs",
            Self::Pending => "pending",
            Self::Broadcasted => "broadcasted",
            Self::Confirmed => "confirmed",
        }
    }

    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "awaiting_inputs" => Ok(Self::AwaitingInputs),
            "pending" => Ok(Self::Pending),
            "broadcasted" => Ok(Self::Broadcasted),
            "confirmed" => Ok(Self::Confirmed),
            other => Err(format!(
                "Unknown migration denomination stage status: {other}"
            )),
        }
    }
}

/// The purpose of one real output created by a denomination stage.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DenominationStageOutputKind {
    Migration,
    Change,
    Continuation,
}

impl DenominationStageOutputKind {
    fn as_str(self) -> &'static str {
        match self {
            Self::Migration => "migration",
            Self::Change => "change",
            Self::Continuation => "continuation",
        }
    }

    fn parse(value: &str) -> Result<Self, String> {
        match value {
            "migration" => Ok(Self::Migration),
            "change" => Ok(Self::Change),
            "continuation" => Ok(Self::Continuation),
            other => Err(format!(
                "Unknown migration denomination stage output kind: {other}"
            )),
        }
    }
}

/// One ordered Orchard input consumed by a denomination stage.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DenominationStageInputRef {
    pub txid_hex: String,
    pub output_index: u32,
    pub value_zatoshi: u64,
    pub note_version: u8,
    pub nullifier_hex: Option<String>,
}

/// One ordered real output created by a denomination stage.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DenominationStageOutputRef {
    pub output_index: u32,
    pub value_zatoshi: u64,
    pub note_version: u8,
    pub kind: DenominationStageOutputKind,
    pub part_index: Option<u32>,
}

/// A signed denomination stage ready to be inserted in an existing SQL
/// transaction.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DenominationStageInsert {
    pub stage_index: u32,
    pub base_pczt: Vec<u8>,
    pub sigs: Vec<SpendAuthSignature>,
    pub raw_tx: Option<Vec<u8>>,
    pub expected_txid_hex: String,
    pub target_height: u32,
    pub expiry_height: u32,
    pub fee_zatoshi: u64,
    pub status: DenominationStageStatus,
    pub inputs: Vec<DenominationStageInputRef>,
    pub outputs: Vec<DenominationStageOutputRef>,
}

/// A decrypted denomination stage, including the material retained for reorg
/// recovery and its normalized input and output references.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DenominationStage {
    pub stage_index: u32,
    pub base_pczt: Vec<u8>,
    pub sigs: Vec<SpendAuthSignature>,
    pub raw_tx: Option<Vec<u8>>,
    pub expected_txid_hex: String,
    pub target_height: u32,
    pub expiry_height: u32,
    pub fee_zatoshi: u64,
    pub status: DenominationStageStatus,
    /// The chain inclusion that descendants were proved against. Confirmed
    /// stages always store both fields; earlier stages store neither.
    pub confirmed_mined_height: Option<u32>,
    pub confirmed_block_hash: Option<Vec<u8>>,
    pub inputs: Vec<DenominationStageInputRef>,
    pub outputs: Vec<DenominationStageOutputRef>,
}

/// The raw transaction for a stage that is ready to broadcast.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct PendingRawDenominationStage {
    pub stage_index: u32,
    pub expected_txid_hex: String,
    pub raw_tx: Vec<u8>,
    pub target_height: u32,
    pub expiry_height: u32,
    pub fee_zatoshi: u64,
}

/// Per-state counts for all denomination stages belonging to one run.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub(crate) struct DenominationStageStatusCounts {
    pub awaiting_inputs: u32,
    pub pending: u32,
    pub broadcasted: u32,
    pub confirmed: u32,
    pub total: u32,
}

/// Unencrypted graph and chain state needed for confirmation and reorg
/// reconciliation from the normal wallet status path.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DenominationStageChainRecord {
    pub expected_txid_hex: String,
    pub status: DenominationStageStatus,
    pub confirmed_mined_height: Option<u32>,
    pub confirmed_block_hash: Option<Vec<u8>>,
    pub parent_txids: Vec<String>,
    pub outputs: Vec<DenominationStageOutputRef>,
}

/// Creates the normalized staged-denomination tables.
pub(super) fn ensure_schema(conn: &Connection) -> Result<(), String> {
    conn.execute_batch(&format!(
        "
        CREATE TABLE IF NOT EXISTS {STAGES_TABLE} (
            run_id TEXT NOT NULL,
            stage_index INTEGER NOT NULL,
            encrypted_base_pczt TEXT NOT NULL,
            encrypted_compact_sigs TEXT NOT NULL,
            encrypted_raw_tx TEXT,
            expected_txid_hex TEXT NOT NULL,
            target_height INTEGER NOT NULL,
            expiry_height INTEGER NOT NULL,
            fee_zatoshi INTEGER NOT NULL,
            confirmed_mined_height INTEGER,
            confirmed_block_hash BLOB,
            status TEXT NOT NULL CHECK (
                status IN ('awaiting_inputs', 'pending', 'broadcasted', 'confirmed')
            ),
            PRIMARY KEY (run_id, stage_index),
            UNIQUE (run_id, expected_txid_hex),
            CHECK (
                (status = 'awaiting_inputs' AND encrypted_raw_tx IS NULL)
                OR
                (status IN ('pending', 'broadcasted')
                 AND encrypted_raw_tx IS NOT NULL)
                OR
                status = 'confirmed'
            ),
            CHECK (
                (status != 'confirmed'
                 AND confirmed_mined_height IS NULL
                 AND confirmed_block_hash IS NULL)
                OR
                (status = 'confirmed'
                 AND confirmed_mined_height IS NOT NULL
                 AND confirmed_block_hash IS NOT NULL
                 AND length(confirmed_block_hash) = 32)
            )
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_migration_denomination_stages_status
            ON {STAGES_TABLE}(run_id, status, stage_index);

        CREATE TABLE IF NOT EXISTS {STAGE_INPUTS_TABLE} (
            run_id TEXT NOT NULL,
            stage_index INTEGER NOT NULL,
            input_order INTEGER NOT NULL,
            txid_hex TEXT NOT NULL,
            output_index INTEGER NOT NULL,
            value_zatoshi INTEGER NOT NULL,
            note_version INTEGER NOT NULL,
            nullifier_hex TEXT,
            PRIMARY KEY (run_id, stage_index, input_order),
            UNIQUE (run_id, txid_hex, output_index),
            FOREIGN KEY (run_id, stage_index)
                REFERENCES {STAGES_TABLE}(run_id, stage_index) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_migration_denomination_inputs_stage
            ON {STAGE_INPUTS_TABLE}(run_id, stage_index, input_order);

        CREATE TABLE IF NOT EXISTS {STAGE_OUTPUTS_TABLE} (
            run_id TEXT NOT NULL,
            stage_index INTEGER NOT NULL,
            output_order INTEGER NOT NULL,
            output_index INTEGER NOT NULL,
            value_zatoshi INTEGER NOT NULL,
            note_version INTEGER NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('migration', 'change', 'continuation')),
            part_index INTEGER,
            PRIMARY KEY (run_id, stage_index, output_order),
            UNIQUE (run_id, stage_index, output_index),
            FOREIGN KEY (run_id, stage_index)
                REFERENCES {STAGES_TABLE}(run_id, stage_index) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_vizor_migration_denomination_outputs_stage
            ON {STAGE_OUTPUTS_TABLE}(run_id, stage_index, output_order);
        "
    ))
    .map_err(|e| format!("Initialize migration denomination stage schema: {e}"))?;

    migrate_confirmed_stage_without_raw_constraint(conn)?;
    add_column_if_missing(conn, STAGE_OUTPUTS_TABLE, "part_index", "INTEGER")?;

    Ok(())
}

fn add_column_if_missing(
    conn: &Connection,
    table: &str,
    column: &str,
    definition: &str,
) -> Result<(), String> {
    let exists = conn
        .query_row(
            "SELECT 1 FROM pragma_table_info(?1) WHERE name = ?2",
            params![table, column],
            |_| Ok(()),
        )
        .optional()
        .map(|row| row.is_some())
        .map_err(|e| format!("Check migration denomination column {table}.{column}: {e}"))?;
    if !exists {
        conn.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {definition}"),
            [],
        )
        .map_err(|e| format!("Add migration denomination column {table}.{column}: {e}"))?;
    }
    Ok(())
}

fn migrate_confirmed_stage_without_raw_constraint(conn: &Connection) -> Result<(), String> {
    let table_sql = conn
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?1",
            params![STAGES_TABLE],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration denomination stage schema: {e}"))?;
    if !table_sql.contains("status != 'awaiting_inputs' AND encrypted_raw_tx IS NOT NULL") {
        return Ok(());
    }
    if !conn.is_autocommit() {
        return Err(
            "Cannot upgrade migration denomination stage schema inside a transaction".to_string(),
        );
    }

    let foreign_keys_enabled = conn
        .query_row("PRAGMA foreign_keys", [], |row| row.get::<_, bool>(0))
        .map_err(|e| format!("Read SQLite foreign key state: {e}"))?;
    conn.execute_batch("PRAGMA foreign_keys = OFF;")
        .map_err(|e| format!("Disable foreign keys for denomination stage upgrade: {e}"))?;
    let upgrade = conn.execute_batch(&format!(
        "BEGIN IMMEDIATE;
         CREATE TABLE {STAGES_TABLE}_v2 (
             run_id TEXT NOT NULL,
             stage_index INTEGER NOT NULL,
             encrypted_base_pczt TEXT NOT NULL,
             encrypted_compact_sigs TEXT NOT NULL,
             encrypted_raw_tx TEXT,
             expected_txid_hex TEXT NOT NULL,
             target_height INTEGER NOT NULL,
             expiry_height INTEGER NOT NULL,
             fee_zatoshi INTEGER NOT NULL,
             confirmed_mined_height INTEGER,
             confirmed_block_hash BLOB,
             status TEXT NOT NULL CHECK (
                 status IN ('awaiting_inputs', 'pending', 'broadcasted', 'confirmed')
             ),
             PRIMARY KEY (run_id, stage_index),
             UNIQUE (run_id, expected_txid_hex),
             CHECK (
                 (status = 'awaiting_inputs' AND encrypted_raw_tx IS NULL)
                 OR
                 (status IN ('pending', 'broadcasted')
                  AND encrypted_raw_tx IS NOT NULL)
                 OR
                 status = 'confirmed'
             ),
             CHECK (
                 (status != 'confirmed'
                  AND confirmed_mined_height IS NULL
                  AND confirmed_block_hash IS NULL)
                 OR
                 (status = 'confirmed'
                  AND confirmed_mined_height IS NOT NULL
                  AND confirmed_block_hash IS NOT NULL
                  AND length(confirmed_block_hash) = 32)
             )
         );
         INSERT INTO {STAGES_TABLE}_v2
         SELECT * FROM {STAGES_TABLE};
         DROP TABLE {STAGES_TABLE};
         ALTER TABLE {STAGES_TABLE}_v2 RENAME TO {STAGES_TABLE};
         CREATE INDEX idx_vizor_migration_denomination_stages_status
             ON {STAGES_TABLE}(run_id, status, stage_index);
         COMMIT;"
    ));
    if let Err(error) = upgrade {
        let _ = conn.execute_batch("ROLLBACK;");
        if foreign_keys_enabled {
            let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
        }
        return Err(format!(
            "Upgrade migration denomination stage schema: {error}"
        ));
    }
    if foreign_keys_enabled {
        conn.execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(|e| format!("Restore foreign keys after denomination stage upgrade: {e}"))?;
    }
    let foreign_key_error = conn
        .query_row("PRAGMA foreign_key_check", [], |row| {
            row.get::<_, String>(0)
        })
        .optional()
        .map_err(|e| format!("Check denomination stage foreign keys: {e}"))?;
    if let Some(table) = foreign_key_error {
        return Err(format!(
            "Denomination stage schema upgrade left an invalid foreign key in {table}"
        ));
    }
    Ok(())
}

/// Inserts every stage under a savepoint in the caller's transaction.
///
/// A failure rolls back only this batch, allowing the caller to handle the
/// error without accidentally committing a partial stage graph.
pub(crate) fn insert_denomination_stages_with_tx(
    tx: &Transaction<'_>,
    run_id: &str,
    stages: Vec<DenominationStageInsert>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    validate_stage_batch(run_id, &stages)?;
    let salt =
        secret_payload::decode_base64(salt_base64.as_bytes(), "migration denomination stage salt")?;

    tx.execute_batch(&format!("SAVEPOINT {INSERT_SAVEPOINT}"))
        .map_err(|e| format!("Begin migration denomination stage savepoint: {e}"))?;

    let insert_result = (|| {
        for stage in stages {
            insert_stage(tx, run_id, stage, password, salt.as_slice())?;
        }
        Ok(())
    })();

    match insert_result {
        Ok(()) => tx
            .execute_batch(&format!("RELEASE SAVEPOINT {INSERT_SAVEPOINT}"))
            .map_err(|e| format!("Release migration denomination stage savepoint: {e}")),
        Err(error) => {
            let rollback_result = tx.execute_batch(&format!(
                "ROLLBACK TO SAVEPOINT {INSERT_SAVEPOINT};\n\
                 RELEASE SAVEPOINT {INSERT_SAVEPOINT};"
            ));
            match rollback_result {
                Ok(()) => Err(error),
                Err(rollback_error) => Err(format!(
                    "{error}; rollback migration denomination stage batch: {rollback_error}"
                )),
            }
        }
    }
}

fn insert_stage(
    tx: &Transaction<'_>,
    run_id: &str,
    stage: DenominationStageInsert,
    password: &[u8],
    salt: &[u8],
) -> Result<(), String> {
    let encrypted_base_pczt =
        secret_payload::encrypt_payload(Zeroizing::new(stage.base_pczt), password, salt)?;
    let sigs_blob = keystone::encode_compact_action_sigs(&stage.sigs)?;
    let encrypted_compact_sigs =
        secret_payload::encrypt_payload(Zeroizing::new(sigs_blob), password, salt)?;
    let encrypted_raw_tx = stage
        .raw_tx
        .map(|raw_tx| secret_payload::encrypt_payload(Zeroizing::new(raw_tx), password, salt))
        .transpose()?;

    tx.execute(
        &format!(
            "INSERT INTO {STAGES_TABLE}
             (run_id, stage_index, encrypted_base_pczt, encrypted_compact_sigs,
              encrypted_raw_tx, expected_txid_hex, target_height, expiry_height,
              fee_zatoshi, status)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)"
        ),
        params![
            run_id,
            stage.stage_index,
            encrypted_base_pczt,
            encrypted_compact_sigs,
            encrypted_raw_tx,
            stage.expected_txid_hex.to_ascii_lowercase(),
            stage.target_height,
            stage.expiry_height,
            stage.fee_zatoshi,
            stage.status.as_str(),
        ],
    )
    .map_err(|e| format!("Insert migration denomination stage: {e}"))?;

    for (input_order, input) in stage.inputs.into_iter().enumerate() {
        tx.execute(
            &format!(
                "INSERT INTO {STAGE_INPUTS_TABLE}
                 (run_id, stage_index, input_order, txid_hex, output_index,
                  value_zatoshi, note_version, nullifier_hex)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"
            ),
            params![
                run_id,
                stage.stage_index,
                u32::try_from(input_order)
                    .map_err(|_| "Migration denomination input order exceeds u32".to_string())?,
                input.txid_hex.to_ascii_lowercase(),
                input.output_index,
                input.value_zatoshi,
                input.note_version,
                input.nullifier_hex.map(|value| value.to_ascii_lowercase()),
            ],
        )
        .map_err(|e| format!("Insert migration denomination stage input: {e}"))?;
    }

    for (output_order, output) in stage.outputs.into_iter().enumerate() {
        tx.execute(
            &format!(
                "INSERT INTO {STAGE_OUTPUTS_TABLE}
                 (run_id, stage_index, output_order, output_index, value_zatoshi,
                  note_version, kind, part_index)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"
            ),
            params![
                run_id,
                stage.stage_index,
                u32::try_from(output_order)
                    .map_err(|_| "Migration denomination output order exceeds u32".to_string())?,
                output.output_index,
                output.value_zatoshi,
                output.note_version,
                output.kind.as_str(),
                output.part_index,
            ],
        )
        .map_err(|e| format!("Insert migration denomination stage output: {e}"))?;
    }

    Ok(())
}

/// Reads and decrypts every denomination stage for a run in stage order.
pub(crate) fn denomination_stages_for_run(
    conn: &Connection,
    run_id: &str,
    password: &[u8],
    salt_base64: &str,
) -> Result<Vec<DenominationStage>, String> {
    ensure_schema(conn)?;
    let salt =
        secret_payload::decode_base64(salt_base64.as_bytes(), "migration denomination stage salt")?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT stage_index, encrypted_base_pczt, encrypted_compact_sigs,
                    encrypted_raw_tx, expected_txid_hex, target_height,
                    expiry_height, fee_zatoshi, status,
                    confirmed_mined_height, confirmed_block_hash
             FROM {STAGES_TABLE}
             WHERE run_id = ?1
             ORDER BY stage_index ASC"
        ))
        .map_err(|e| format!("Prepare migration denomination stages query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, u32>(5)?,
                row.get::<_, u32>(6)?,
                row.get::<_, u64>(7)?,
                row.get::<_, String>(8)?,
                row.get::<_, Option<u32>>(9)?,
                row.get::<_, Option<Vec<u8>>>(10)?,
            ))
        })
        .map_err(|e| format!("Query migration denomination stages: {e}"))?;

    let mut stages = Vec::new();
    for row in rows {
        let (
            stage_index,
            encrypted_base_pczt,
            encrypted_compact_sigs,
            encrypted_raw_tx,
            expected_txid_hex,
            target_height,
            expiry_height,
            fee_zatoshi,
            status,
            confirmed_mined_height,
            confirmed_block_hash,
        ) = row.map_err(|e| format!("Read migration denomination stage: {e}"))?;
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
        let raw_tx = encrypted_raw_tx
            .map(|encrypted| {
                secret_payload::decrypt_payload(encrypted.as_bytes(), password, salt.as_slice())
                    .map(|raw| raw.to_vec())
            })
            .transpose()?;

        stages.push(DenominationStage {
            stage_index,
            base_pczt: base_pczt.to_vec(),
            sigs: keystone::decode_compact_action_sigs(sigs_blob.as_slice())?,
            raw_tx,
            expected_txid_hex,
            target_height,
            expiry_height,
            fee_zatoshi,
            status: DenominationStageStatus::parse(&status)?,
            confirmed_mined_height,
            confirmed_block_hash,
            inputs: stage_inputs(conn, run_id, stage_index)?,
            outputs: stage_outputs(conn, run_id, stage_index)?,
        });
    }
    Ok(stages)
}

fn stage_inputs(
    conn: &Connection,
    run_id: &str,
    stage_index: u32,
) -> Result<Vec<DenominationStageInputRef>, String> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT txid_hex, output_index, value_zatoshi, note_version, nullifier_hex
             FROM {STAGE_INPUTS_TABLE}
             WHERE run_id = ?1 AND stage_index = ?2
             ORDER BY input_order ASC"
        ))
        .map_err(|e| format!("Prepare migration denomination stage inputs query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, stage_index], |row| {
            Ok(DenominationStageInputRef {
                txid_hex: row.get(0)?,
                output_index: row.get(1)?,
                value_zatoshi: row.get(2)?,
                note_version: row.get(3)?,
                nullifier_hex: row.get(4)?,
            })
        })
        .map_err(|e| format!("Query migration denomination stage inputs: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration denomination stage inputs: {e}"))
}

fn stage_outputs(
    conn: &Connection,
    run_id: &str,
    stage_index: u32,
) -> Result<Vec<DenominationStageOutputRef>, String> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT output_index, value_zatoshi, note_version, kind, part_index
             FROM {STAGE_OUTPUTS_TABLE}
             WHERE run_id = ?1 AND stage_index = ?2
             ORDER BY output_order ASC"
        ))
        .map_err(|e| format!("Prepare migration denomination stage outputs query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id, stage_index], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, u64>(1)?,
                row.get::<_, u8>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, Option<u32>>(4)?,
            ))
        })
        .map_err(|e| format!("Query migration denomination stage outputs: {e}"))?;
    let mut outputs = Vec::new();
    for row in rows {
        let (output_index, value_zatoshi, note_version, kind, part_index) =
            row.map_err(|e| format!("Read migration denomination stage output: {e}"))?;
        outputs.push(DenominationStageOutputRef {
            output_index,
            value_zatoshi,
            note_version,
            kind: DenominationStageOutputKind::parse(&kind)?,
            part_index,
        });
    }
    Ok(outputs)
}

/// Lists decrypted raw transactions that are ready to broadcast, in stage
/// order.
pub(crate) fn pending_raw_denomination_stages(
    conn: &Connection,
    run_id: &str,
    password: &[u8],
    salt_base64: &str,
) -> Result<Vec<PendingRawDenominationStage>, String> {
    ensure_schema(conn)?;
    let salt =
        secret_payload::decode_base64(salt_base64.as_bytes(), "migration denomination stage salt")?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT stage_index, expected_txid_hex, encrypted_raw_tx,
                    target_height, expiry_height, fee_zatoshi
             FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND status = 'pending' AND encrypted_raw_tx IS NOT NULL
             ORDER BY stage_index ASC"
        ))
        .map_err(|e| format!("Prepare pending migration denomination stages query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, u32>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, u64>(5)?,
            ))
        })
        .map_err(|e| format!("Query pending migration denomination stages: {e}"))?;
    let mut pending = Vec::new();
    for row in rows {
        let (
            stage_index,
            expected_txid_hex,
            encrypted_raw_tx,
            target_height,
            expiry_height,
            fee_zatoshi,
        ) = row.map_err(|e| format!("Read pending migration denomination stage: {e}"))?;
        let raw_tx = secret_payload::decrypt_payload(
            encrypted_raw_tx.as_bytes(),
            password,
            salt.as_slice(),
        )?;
        pending.push(PendingRawDenominationStage {
            stage_index,
            expected_txid_hex,
            raw_tx: raw_tx.to_vec(),
            target_height,
            expiry_height,
            fee_zatoshi,
        });
    }
    Ok(pending)
}

/// Adds the proved raw transaction to an awaiting stage and makes it pending.
/// The signed base PCZT and compact signatures remain unchanged.
pub(crate) fn promote_awaiting_denomination_stage(
    conn: &Connection,
    run_id: &str,
    stage_index: u32,
    expected_txid_hex: &str,
    raw_tx: Vec<u8>,
    password: &[u8],
    salt_base64: &str,
) -> Result<(), String> {
    ensure_schema(conn)?;
    validate_txid_hex(expected_txid_hex, "expected transaction ID")?;
    if raw_tx.is_empty() {
        return Err("Migration denomination stage raw transaction is empty".to_string());
    }
    let salt =
        secret_payload::decode_base64(salt_base64.as_bytes(), "migration denomination stage salt")?;
    let encrypted_raw_tx =
        secret_payload::encrypt_payload(Zeroizing::new(raw_tx), password, salt.as_slice())?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET encrypted_raw_tx = ?1, status = 'pending'
                 WHERE run_id = ?2 AND stage_index = ?3
                   AND expected_txid_hex = ?4 AND status = 'awaiting_inputs'
                   AND encrypted_raw_tx IS NULL"
            ),
            params![
                encrypted_raw_tx,
                run_id,
                stage_index,
                expected_txid_hex.to_ascii_lowercase(),
            ],
        )
        .map_err(|e| format!("Promote awaiting migration denomination stage: {e}"))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(format!(
            "Migration denomination stage {stage_index} is missing, has a different txid, or is not awaiting inputs"
        ))
    }
}

/// Marks a pending stage as broadcasted. Repeating the update after a crash is
/// safe when the stage has already reached this state or confirmation.
pub(crate) fn mark_denomination_stage_broadcasted(
    conn: &Connection,
    run_id: &str,
    expected_txid_hex: &str,
) -> Result<(), String> {
    transition_stage(
        conn,
        run_id,
        expected_txid_hex,
        DenominationStageStatus::Broadcasted,
    )
}

/// Marks a pending or broadcasted stage as confirmed at a specific canonical
/// chain inclusion. This accepts a direct pending-to-confirmed transition for
/// crash recovery after a successful send.
pub(crate) fn mark_denomination_stage_confirmed_at(
    conn: &Connection,
    run_id: &str,
    expected_txid_hex: &str,
    mined_height: u32,
    block_hash: &[u8; 32],
) -> Result<(), String> {
    ensure_schema(conn)?;
    validate_txid_hex(expected_txid_hex, "expected transaction ID")?;
    let expected_txid_hex = expected_txid_hex.to_ascii_lowercase();
    let updated = conn
        .execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET status = 'confirmed', confirmed_mined_height = ?1,
                     confirmed_block_hash = ?2
                 WHERE run_id = ?3 AND expected_txid_hex = ?4
                   AND status IN ('pending', 'broadcasted')"
            ),
            params![
                mined_height,
                block_hash.as_slice(),
                run_id,
                expected_txid_hex
            ],
        )
        .map_err(|e| format!("Confirm migration denomination stage: {e}"))?;
    if updated == 1 {
        return Ok(());
    }

    let current = conn
        .query_row(
            &format!(
                "SELECT status, confirmed_mined_height, confirmed_block_hash
                 FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND expected_txid_hex = ?2"
            ),
            params![run_id, expected_txid_hex],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, Option<u32>>(1)?,
                    row.get::<_, Option<Vec<u8>>>(2)?,
                ))
            },
        )
        .optional()
        .map_err(|e| format!("Read migration denomination stage confirmation: {e}"))?
        .ok_or_else(|| format!("Migration denomination stage {expected_txid_hex} was not found"))?;
    let status = DenominationStageStatus::parse(&current.0)?;
    if status != DenominationStageStatus::Confirmed {
        return Err(format!(
            "Cannot move migration denomination stage from {} to confirmed",
            status.as_str()
        ));
    }

    match (current.1, current.2.as_deref()) {
        (Some(stored_height), Some(stored_hash))
            if stored_height == mined_height && stored_hash == block_hash.as_slice() =>
        {
            Ok(())
        }
        _ => Err(format!(
            "Migration denomination stage {expected_txid_hex} moved to a different chain inclusion"
        )),
    }
}

fn transition_stage(
    conn: &Connection,
    run_id: &str,
    expected_txid_hex: &str,
    target: DenominationStageStatus,
) -> Result<(), String> {
    ensure_schema(conn)?;
    validate_txid_hex(expected_txid_hex, "expected transaction ID")?;
    let expected_txid_hex = expected_txid_hex.to_ascii_lowercase();
    let allowed_source_sql = match target {
        DenominationStageStatus::Broadcasted => "status = 'pending'",
        DenominationStageStatus::Confirmed
        | DenominationStageStatus::AwaitingInputs
        | DenominationStageStatus::Pending => {
            return Err(format!(
                "Unsupported migration denomination stage transition target {}",
                target.as_str()
            ));
        }
    };
    let updated = conn
        .execute(
            &format!(
                "UPDATE {STAGES_TABLE} SET status = ?1
                 WHERE run_id = ?2 AND expected_txid_hex = ?3
                   AND {allowed_source_sql}"
            ),
            params![target.as_str(), run_id, expected_txid_hex],
        )
        .map_err(|e| format!("Update migration denomination stage status: {e}"))?;
    if updated == 1 {
        return Ok(());
    }

    // The guarded UPDATE above makes forward transitions monotonic even when
    // a broadcast callback races a confirmation or a reorg reset. Resolve a
    // zero-row update only for idempotent or already-later states.
    let current = conn
        .query_row(
            &format!(
                "SELECT status FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND expected_txid_hex = ?2"
            ),
            params![run_id, expected_txid_hex],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|e| format!("Read migration denomination stage status: {e}"))?
        .ok_or_else(|| format!("Migration denomination stage {expected_txid_hex} was not found"))?;
    let current = DenominationStageStatus::parse(&current)?;
    let already_reached = current == target
        || (target == DenominationStageStatus::Broadcasted
            && current == DenominationStageStatus::Confirmed);
    if already_reached {
        Ok(())
    } else {
        Err(format!(
            "Cannot move migration denomination stage from {} to {}",
            current.as_str(),
            target.as_str()
        ))
    }
}

/// Clears the extracted transaction for a reorged stage and every stage that
/// spends one of its outputs, while retaining each base PCZT and compact
/// signature list.
///
/// Descendants are found from their normalized input outpoints instead of by
/// stage index, so independent branches remain untouched. Each affected stage
/// returns to `AwaitingInputs` and can be re-anchored, proved, and promoted
/// again with the same effecting-data transaction ID.
pub(crate) fn reset_denomination_stage_for_reorg(
    conn: &Connection,
    run_id: &str,
    expected_txid_hex: &str,
) -> Result<(), String> {
    ensure_schema(conn)?;
    validate_txid_hex(expected_txid_hex, "expected transaction ID")?;
    let expected_txid_hex = expected_txid_hex.to_ascii_lowercase();
    let updated = conn
        .execute(
            &format!(
                "WITH RECURSIVE affected(stage_index, expected_txid_hex) AS (
                    SELECT stage_index, expected_txid_hex
                    FROM {STAGES_TABLE}
                    WHERE run_id = ?1 AND expected_txid_hex = ?2
                    UNION
                    SELECT child.stage_index, child.expected_txid_hex
                    FROM {STAGES_TABLE} child
                    INNER JOIN {STAGE_INPUTS_TABLE} child_input
                      ON child_input.run_id = child.run_id
                     AND child_input.stage_index = child.stage_index
                    INNER JOIN affected parent
                      ON child_input.txid_hex = parent.expected_txid_hex
                    WHERE child.run_id = ?1
                )
                UPDATE {STAGES_TABLE}
                SET encrypted_raw_tx = NULL, status = 'awaiting_inputs',
                    confirmed_mined_height = NULL,
                    confirmed_block_hash = NULL
                WHERE run_id = ?1
                  AND stage_index IN (SELECT stage_index FROM affected)"
            ),
            params![run_id, expected_txid_hex],
        )
        .map_err(|e| format!("Reset migration denomination stage after reorg: {e}"))?;
    if updated > 0 {
        Ok(())
    } else {
        Err(format!(
            "Migration denomination stage {expected_txid_hex} was not found"
        ))
    }
}

/// Reads the state of one stage by its stable order within the run.
pub(crate) fn denomination_stage_status(
    conn: &Connection,
    run_id: &str,
    stage_index: u32,
) -> Result<Option<DenominationStageStatus>, String> {
    ensure_schema(conn)?;
    conn.query_row(
        &format!(
            "SELECT status FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND stage_index = ?2"
        ),
        params![run_id, stage_index],
        |row| row.get::<_, String>(0),
    )
    .optional()
    .map_err(|e| format!("Read migration denomination stage status: {e}"))?
    .map(|status| DenominationStageStatus::parse(&status))
    .transpose()
}

/// Lists every planned denomination transaction ID in stable stage order.
/// This intentionally reads no encrypted material so confirmation checks can
/// run from the normal wallet status path.
pub(crate) fn denomination_stage_expected_txids(
    conn: &Connection,
    run_id: &str,
) -> Result<Vec<String>, String> {
    ensure_schema(conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT expected_txid_hex
             FROM {STAGES_TABLE}
             WHERE run_id = ?1
             ORDER BY stage_index ASC"
        ))
        .map_err(|e| format!("Prepare migration denomination txid query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Query migration denomination txids: {e}"))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read migration denomination txids: {e}"))
}

pub(crate) fn denomination_stage_chain_records(
    conn: &Connection,
    run_id: &str,
) -> Result<Vec<DenominationStageChainRecord>, String> {
    ensure_schema(conn)?;
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT stage_index, expected_txid_hex, status,
                    confirmed_mined_height, confirmed_block_hash
             FROM {STAGES_TABLE}
             WHERE run_id = ?1
             ORDER BY stage_index ASC"
        ))
        .map_err(|e| format!("Prepare migration denomination chain-state query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<u32>>(3)?,
                row.get::<_, Option<Vec<u8>>>(4)?,
            ))
        })
        .map_err(|e| format!("Query migration denomination chain state: {e}"))?;

    let mut records = Vec::new();
    for row in rows {
        let (stage_index, expected_txid_hex, status, confirmed_mined_height, confirmed_block_hash) =
            row.map_err(|e| format!("Read migration denomination chain state: {e}"))?;
        match (&confirmed_mined_height, &confirmed_block_hash) {
            (None, None) => {}
            (Some(_), Some(hash)) if hash.len() == 32 => {}
            _ => {
                return Err(format!(
                    "Migration denomination stage {expected_txid_hex} has a malformed chain inclusion"
                ));
            }
        }
        let mut parent_stmt = conn
            .prepare_cached(&format!(
                "SELECT lower(txid_hex)
                 FROM {STAGE_INPUTS_TABLE}
                 WHERE run_id = ?1 AND stage_index = ?2
                 ORDER BY input_order ASC"
            ))
            .map_err(|e| format!("Prepare migration denomination parent query: {e}"))?;
        let parents = parent_stmt
            .query_map(params![run_id, stage_index], |row| row.get::<_, String>(0))
            .map_err(|e| format!("Query migration denomination parents: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read migration denomination parents: {e}"))?;
        records.push(DenominationStageChainRecord {
            expected_txid_hex,
            status: DenominationStageStatus::parse(&status)?,
            confirmed_mined_height,
            confirmed_block_hash,
            parent_txids: parents,
            outputs: stage_outputs(conn, run_id, stage_index)?,
        });
    }
    Ok(records)
}

/// Records the inclusion for a stage known to be present on the canonical
/// chain. A retained raw transaction remains available; an `awaiting_inputs`
/// stage may have no raw bytes after a prior reorg reset, but canonical
/// inclusion means it no longer needs to be rebuilt.
pub(crate) fn replace_denomination_stage_confirmation_identity(
    conn: &Connection,
    run_id: &str,
    expected_txid_hex: &str,
    mined_height: u32,
    block_hash: &[u8; 32],
) -> Result<(), String> {
    ensure_schema(conn)?;
    validate_txid_hex(expected_txid_hex, "expected transaction ID")?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET status = 'confirmed', confirmed_mined_height = ?1,
                     confirmed_block_hash = ?2
                 WHERE run_id = ?3 AND expected_txid_hex = ?4
                   AND status IN ('awaiting_inputs', 'pending', 'broadcasted',
                                  'confirmed')"
            ),
            params![
                mined_height,
                block_hash.as_slice(),
                run_id,
                expected_txid_hex.to_ascii_lowercase()
            ],
        )
        .map_err(|e| format!("Replace migration denomination chain inclusion: {e}"))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(format!(
            "Migration denomination stage {expected_txid_hex} cannot record a mined inclusion"
        ))
    }
}

/// Clears only the named stage. Callers derive the precise off-chain
/// descendant set from normalized graph records so a descendant already
/// re-included on the canonical chain is preserved.
pub(crate) fn reset_denomination_stage_exact(
    conn: &Connection,
    run_id: &str,
    expected_txid_hex: &str,
) -> Result<(), String> {
    ensure_schema(conn)?;
    validate_txid_hex(expected_txid_hex, "expected transaction ID")?;
    let updated = conn
        .execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET encrypted_raw_tx = NULL, status = 'awaiting_inputs',
                     confirmed_mined_height = NULL,
                     confirmed_block_hash = NULL
                 WHERE run_id = ?1 AND expected_txid_hex = ?2"
            ),
            params![run_id, expected_txid_hex.to_ascii_lowercase()],
        )
        .map_err(|e| format!("Reset migration denomination stage after reorg: {e}"))?;
    if updated == 1 {
        Ok(())
    } else {
        Err(format!(
            "Migration denomination stage {expected_txid_hex} was not found"
        ))
    }
}

/// Counts the stages in each persistence state for one run.
pub(crate) fn denomination_stage_status_counts(
    conn: &Connection,
    run_id: &str,
) -> Result<DenominationStageStatusCounts, String> {
    ensure_schema(conn)?;
    let counts = conn
        .query_row(
            &format!(
                "SELECT
                    COALESCE(SUM(status = 'awaiting_inputs'), 0),
                    COALESCE(SUM(status = 'pending'), 0),
                    COALESCE(SUM(status = 'broadcasted'), 0),
                    COALESCE(SUM(status = 'confirmed'), 0),
                    COUNT(*)
                 FROM {STAGES_TABLE}
                 WHERE run_id = ?1"
            ),
            params![run_id],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                ))
            },
        )
        .map_err(|e| format!("Count migration denomination stage statuses: {e}"))?;
    Ok(DenominationStageStatusCounts {
        awaiting_inputs: count_to_u32(counts.0)?,
        pending: count_to_u32(counts.1)?,
        broadcasted: count_to_u32(counts.2)?,
        confirmed: count_to_u32(counts.3)?,
        total: count_to_u32(counts.4)?,
    })
}

/// Returns true only when the run has at least one stage and every stage is
/// confirmed.
pub(crate) fn all_denomination_stages_confirmed(
    conn: &Connection,
    run_id: &str,
) -> Result<bool, String> {
    ensure_schema(conn)?;
    let (total, confirmed_with_identity) = conn
        .query_row(
            &format!(
                "SELECT COUNT(*),
                        COALESCE(SUM(
                            status = 'confirmed'
                            AND confirmed_mined_height IS NOT NULL
                            AND confirmed_block_hash IS NOT NULL
                            AND length(confirmed_block_hash) = 32
                        ), 0)
                 FROM {STAGES_TABLE}
                 WHERE run_id = ?1"
            ),
            params![run_id],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
        )
        .map_err(|e| format!("Check migration denomination confirmations: {e}"))?;
    Ok(total > 0 && confirmed_with_identity == total)
}

/// Lists every input outpoint that must remain unavailable to normal coin
/// selection while an unconfirmed denomination stage owns it.
pub(crate) fn locked_denomination_stage_input_outpoints(
    conn: &Connection,
    run_id: &str,
) -> Result<BTreeSet<(String, u32)>, String> {
    // Coin selection also calls this through read-only wallet connections, so
    // don't try to initialize schema here. A wallet with no stage tables has
    // no staged inputs to lock.
    if !table_exists(conn, STAGE_INPUTS_TABLE)? || !table_exists(conn, STAGES_TABLE)? {
        return Ok(BTreeSet::new());
    }
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT lower(i.txid_hex), i.output_index
             FROM {STAGE_INPUTS_TABLE} i
             INNER JOIN {STAGES_TABLE} s
               ON s.run_id = i.run_id AND s.stage_index = i.stage_index
             WHERE i.run_id = ?1 AND s.status != 'confirmed'
             ORDER BY i.txid_hex, i.output_index"
        ))
        .map_err(|e| format!("Prepare migration denomination input lock query: {e}"))?;
    let rows = stmt
        .query_map(params![run_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .map_err(|e| format!("Query migration denomination input locks: {e}"))?;
    rows.collect::<Result<BTreeSet<_>, _>>()
        .map_err(|e| format!("Read migration denomination input locks: {e}"))
}

fn validate_stage_batch(run_id: &str, stages: &[DenominationStageInsert]) -> Result<(), String> {
    if run_id.is_empty() {
        return Err("Migration denomination stage run ID is empty".to_string());
    }
    let mut stage_indices = BTreeSet::new();
    let mut expected_txids = BTreeSet::new();
    let mut input_outpoints = BTreeSet::new();
    for stage in stages {
        if !stage_indices.insert(stage.stage_index) {
            return Err(format!(
                "Duplicate migration denomination stage index {}",
                stage.stage_index
            ));
        }
        validate_txid_hex(&stage.expected_txid_hex, "expected transaction ID")?;
        if !expected_txids.insert(stage.expected_txid_hex.to_ascii_lowercase()) {
            return Err(format!(
                "Duplicate migration denomination expected txid {}",
                stage.expected_txid_hex
            ));
        }
        if stage.base_pczt.is_empty() {
            return Err(format!(
                "Migration denomination stage {} has an empty base PCZT",
                stage.stage_index
            ));
        }
        if stage.inputs.is_empty() {
            return Err(format!(
                "Migration denomination stage {} has no real inputs",
                stage.stage_index
            ));
        }
        if stage.outputs.is_empty() {
            return Err(format!(
                "Migration denomination stage {} has no real outputs",
                stage.stage_index
            ));
        }
        match (stage.status, stage.raw_tx.as_ref()) {
            (DenominationStageStatus::AwaitingInputs, None) => {}
            (DenominationStageStatus::AwaitingInputs, Some(_)) => {
                return Err(format!(
                    "Awaiting migration denomination stage {} already has a raw transaction",
                    stage.stage_index
                ));
            }
            (DenominationStageStatus::Pending, Some(raw_tx)) if !raw_tx.is_empty() => {}
            (DenominationStageStatus::Pending, Some(_)) => {
                return Err(format!(
                    "Migration denomination stage {} has an empty raw transaction",
                    stage.stage_index
                ));
            }
            (DenominationStageStatus::Pending, None) => {
                return Err(format!(
                    "Migration denomination stage {} is {} without a raw transaction",
                    stage.stage_index,
                    stage.status.as_str()
                ));
            }
            (DenominationStageStatus::Broadcasted | DenominationStageStatus::Confirmed, _) => {
                return Err(format!(
                    "Migration denomination stage {} cannot be inserted as {}",
                    stage.stage_index,
                    stage.status.as_str()
                ));
            }
        }

        for input in &stage.inputs {
            validate_txid_hex(&input.txid_hex, "input transaction ID")?;
            if let Some(nullifier_hex) = &input.nullifier_hex {
                validate_hex_32(nullifier_hex, "input nullifier")?;
            }
            let outpoint = (input.txid_hex.to_ascii_lowercase(), input.output_index);
            if !input_outpoints.insert(outpoint) {
                return Err(format!(
                    "Migration denomination input {}:{} is assigned more than once",
                    input.txid_hex, input.output_index
                ));
            }
        }

        let mut output_indices = BTreeSet::new();
        for output in &stage.outputs {
            if output.kind != DenominationStageOutputKind::Migration && output.part_index.is_some()
            {
                return Err(format!(
                    "Migration denomination stage {} assigns a part index to a {} output",
                    stage.stage_index,
                    output.kind.as_str()
                ));
            }
            if !output_indices.insert(output.output_index) {
                return Err(format!(
                    "Migration denomination stage {} repeats output index {}",
                    stage.stage_index, output.output_index
                ));
            }
        }
    }
    Ok(())
}

fn validate_txid_hex(value: &str, label: &str) -> Result<(), String> {
    validate_hex_32(value, label)
}

fn validate_hex_32(value: &str, label: &str) -> Result<(), String> {
    if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(format!("Invalid {label}: expected 32-byte hex"));
    }
    Ok(())
}

fn count_to_u32(count: i64) -> Result<u32, String> {
    u32::try_from(count).map_err(|_| "Migration denomination stage count overflow".to_string())
}

fn table_exists(conn: &Connection, table: &str) -> Result<bool, String> {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
        params![table],
        |_| Ok(()),
    )
    .optional()
    .map(|row| row.is_some())
    .map_err(|e| format!("Check migration denomination stage table {table}: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const PASSWORD: &[u8] = b"correct horse battery staple";
    const SALT_BASE64: &str = "AQIDBAUGBwgJCgsMDQ4PEA==";

    fn txid(byte: u8) -> String {
        format!("{byte:02x}").repeat(32)
    }

    fn sig(byte: u8, action_index: usize) -> SpendAuthSignature {
        SpendAuthSignature::from_parts(orchard::ValuePool::Orchard, action_index, [byte; 64])
    }

    fn input(byte: u8, output_index: u32, value_zatoshi: u64) -> DenominationStageInputRef {
        DenominationStageInputRef {
            txid_hex: txid(byte),
            output_index,
            value_zatoshi,
            note_version: 2,
            nullifier_hex: Some(txid(byte.wrapping_add(1))),
        }
    }

    fn output(
        output_index: u32,
        value_zatoshi: u64,
        kind: DenominationStageOutputKind,
    ) -> DenominationStageOutputRef {
        DenominationStageOutputRef {
            output_index,
            value_zatoshi,
            note_version: 2,
            kind,
            part_index: None,
        }
    }

    fn awaiting_stage(stage_index: u32, txid_byte: u8) -> DenominationStageInsert {
        DenominationStageInsert {
            stage_index,
            base_pczt: vec![0xa0, txid_byte],
            sigs: vec![sig(txid_byte, usize::try_from(stage_index).unwrap())],
            raw_tx: None,
            expected_txid_hex: txid(txid_byte),
            target_height: 3_000_000 + stage_index,
            expiry_height: 0,
            fee_zatoshi: 80_000,
            status: DenominationStageStatus::AwaitingInputs,
            inputs: vec![input(txid_byte.wrapping_add(20), stage_index, 500_000)],
            outputs: vec![output(0, 420_000, DenominationStageOutputKind::Migration)],
        }
    }

    fn setup() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
        ensure_schema(&conn).unwrap();
        conn
    }

    #[test]
    fn schema_upgrade_allows_confirmed_stage_without_raw_transaction() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(&format!(
            "PRAGMA foreign_keys = ON;
             CREATE TABLE {STAGES_TABLE} (
                 run_id TEXT NOT NULL,
                 stage_index INTEGER NOT NULL,
                 encrypted_base_pczt TEXT NOT NULL,
                 encrypted_compact_sigs TEXT NOT NULL,
                 encrypted_raw_tx TEXT,
                 expected_txid_hex TEXT NOT NULL,
                 target_height INTEGER NOT NULL,
                 expiry_height INTEGER NOT NULL,
                 fee_zatoshi INTEGER NOT NULL,
                 confirmed_mined_height INTEGER,
                 confirmed_block_hash BLOB,
                 status TEXT NOT NULL CHECK (
                     status IN ('awaiting_inputs', 'pending', 'broadcasted', 'confirmed')
                 ),
                 PRIMARY KEY (run_id, stage_index),
                 UNIQUE (run_id, expected_txid_hex),
                 CHECK (
                     (status = 'awaiting_inputs' AND encrypted_raw_tx IS NULL)
                     OR
                     (status != 'awaiting_inputs' AND encrypted_raw_tx IS NOT NULL)
                 ),
                 CHECK (
                     (status != 'confirmed'
                      AND confirmed_mined_height IS NULL
                      AND confirmed_block_hash IS NULL)
                     OR
                     (status = 'confirmed'
                      AND confirmed_mined_height IS NOT NULL
                      AND confirmed_block_hash IS NOT NULL
                      AND length(confirmed_block_hash) = 32)
                 )
             );
             INSERT INTO {STAGES_TABLE}
             (run_id, stage_index, encrypted_base_pczt, encrypted_compact_sigs,
              encrypted_raw_tx, expected_txid_hex, target_height, expiry_height,
              fee_zatoshi, confirmed_mined_height, confirmed_block_hash, status)
             VALUES ('run-1', 0, 'base', 'sigs', 'raw', '{txid}', 10, 0,
                     80000, 20, X'{block_hash}', 'confirmed');",
            txid = txid(0x11),
            block_hash = hex::encode([0xabu8; 32]),
        ))
        .unwrap();

        ensure_schema(&conn).unwrap();
        conn.execute(
            &format!(
                "UPDATE {STAGES_TABLE} SET encrypted_raw_tx = NULL
                 WHERE run_id = 'run-1'"
            ),
            [],
        )
        .unwrap();

        let retained: (String, Option<String>) = conn
            .query_row(
                &format!(
                    "SELECT status, encrypted_raw_tx FROM {STAGES_TABLE}
                     WHERE run_id = 'run-1'"
                ),
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(retained, ("confirmed".to_string(), None));
        assert!(conn
            .query_row("PRAGMA foreign_keys", [], |row| row.get::<_, bool>(0))
            .unwrap());
        assert!(conn
            .query_row("PRAGMA foreign_key_check", [], |_| Ok(()))
            .optional()
            .unwrap()
            .is_none());
    }

    #[test]
    fn encrypted_stages_and_normalized_refs_round_trip_in_order() {
        let conn = setup();
        let mut stage_one = awaiting_stage(1, 0x11);
        stage_one.inputs = vec![input(0x31, 3, 200_000), input(0x32, 1, 300_000)];
        stage_one.outputs = vec![
            output(4, 100_000, DenominationStageOutputKind::Migration),
            output(2, 320_000, DenominationStageOutputKind::Continuation),
        ];
        let mut stage_zero = awaiting_stage(0, 0x10);
        stage_zero.raw_tx = Some(vec![0xde, 0xad, 0xbe, 0xef]);
        stage_zero.status = DenominationStageStatus::Pending;
        stage_zero.outputs = vec![output(7, 420_000, DenominationStageOutputKind::Change)];

        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(
            &tx,
            "run-1",
            vec![stage_one.clone(), stage_zero.clone()],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap();
        tx.commit().unwrap();

        let encrypted: (String, String, String) = conn
            .query_row(
                &format!(
                    "SELECT encrypted_base_pczt, encrypted_compact_sigs, encrypted_raw_tx
                     FROM {STAGES_TABLE} WHERE run_id = 'run-1' AND stage_index = 0"
                ),
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert!(!encrypted.0.contains("deadbeef"));
        assert!(!encrypted.1.contains("deadbeef"));
        assert!(!encrypted.2.contains("deadbeef"));

        let stages = denomination_stages_for_run(&conn, "run-1", PASSWORD, SALT_BASE64).unwrap();
        assert_eq!(stages.len(), 2);
        assert_eq!(stages[0].stage_index, 0);
        assert_eq!(stages[0].base_pczt, stage_zero.base_pczt);
        assert_eq!(stages[0].sigs, stage_zero.sigs);
        assert_eq!(stages[0].raw_tx, stage_zero.raw_tx);
        assert_eq!(stages[0].outputs, stage_zero.outputs);
        assert_eq!(stages[1].stage_index, 1);
        assert_eq!(stages[1].inputs, stage_one.inputs);
        assert_eq!(stages[1].outputs, stage_one.outputs);

        let error = denomination_stages_for_run(&conn, "run-1", b"wrong password", SALT_BASE64)
            .unwrap_err();
        assert!(error.contains("Failed to decrypt"));
    }

    #[test]
    fn insertion_is_atomic_and_input_outpoints_are_unique_per_run() {
        let conn = setup();
        let stage_zero = awaiting_stage(0, 0x10);
        let mut stage_one = awaiting_stage(1, 0x11);
        stage_one.inputs = stage_zero.inputs.clone();

        let tx = conn.unchecked_transaction().unwrap();
        let error = insert_denomination_stages_with_tx(
            &tx,
            "run-1",
            vec![stage_zero.clone(), stage_one],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap_err();
        assert!(error.contains("assigned more than once"));
        let count: i64 = tx
            .query_row(&format!("SELECT COUNT(*) FROM {STAGES_TABLE}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(count, 0);
        tx.commit().unwrap();

        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(
            &tx,
            "run-1",
            vec![stage_zero.clone()],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap();
        tx.commit().unwrap();

        let mut duplicate_input = awaiting_stage(1, 0x12);
        duplicate_input.inputs = stage_zero.inputs;
        let tx = conn.unchecked_transaction().unwrap();
        let error = insert_denomination_stages_with_tx(
            &tx,
            "run-1",
            vec![awaiting_stage(2, 0x13), duplicate_input],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap_err();
        assert!(error.contains("UNIQUE constraint failed"));
        let count: i64 = tx
            .query_row(&format!("SELECT COUNT(*) FROM {STAGES_TABLE}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(count, 1, "savepoint must roll back the first new stage");
        tx.commit().unwrap();
    }

    #[test]
    fn insertion_rejects_post_creation_states() {
        let conn = setup();
        for (stage_index, status) in [
            (0, DenominationStageStatus::Broadcasted),
            (1, DenominationStageStatus::Confirmed),
        ] {
            let mut stage = awaiting_stage(stage_index, 0x10 + stage_index as u8);
            stage.raw_tx = Some(vec![stage_index as u8]);
            stage.status = status;
            let tx = conn.unchecked_transaction().unwrap();
            let error = insert_denomination_stages_with_tx(
                &tx,
                "run-1",
                vec![stage],
                PASSWORD,
                SALT_BASE64,
            )
            .unwrap_err();
            assert!(error.contains("cannot be inserted"));
            tx.commit().unwrap();
        }
    }

    #[test]
    fn promotion_and_state_updates_keep_recovery_material_and_locks() {
        let conn = setup();
        let stage = awaiting_stage(0, 0x10);
        let expected_txid = stage.expected_txid_hex.clone();
        let expected_input = (
            stage.inputs[0].txid_hex.clone(),
            stage.inputs[0].output_index,
        );
        let expected_base = stage.base_pczt.clone();
        let expected_sigs = stage.sigs.clone();
        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(&tx, "run-1", vec![stage], PASSWORD, SALT_BASE64)
            .unwrap();
        tx.commit().unwrap();

        assert_eq!(
            locked_denomination_stage_input_outpoints(&conn, "run-1").unwrap(),
            BTreeSet::from([expected_input])
        );
        assert!(
            pending_raw_denomination_stages(&conn, "run-1", PASSWORD, SALT_BASE64)
                .unwrap()
                .is_empty()
        );

        promote_awaiting_denomination_stage(
            &conn,
            "run-1",
            0,
            &expected_txid,
            vec![1, 2, 3, 4],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap();
        let pending =
            pending_raw_denomination_stages(&conn, "run-1", PASSWORD, SALT_BASE64).unwrap();
        assert_eq!(pending.len(), 1);
        assert_eq!(pending[0].raw_tx, vec![1, 2, 3, 4]);

        mark_denomination_stage_broadcasted(&conn, "run-1", &expected_txid).unwrap();
        assert_eq!(
            denomination_stage_status(&conn, "run-1", 0).unwrap(),
            Some(DenominationStageStatus::Broadcasted)
        );
        mark_denomination_stage_confirmed_at(&conn, "run-1", &expected_txid, 100, &[0xabu8; 32])
            .unwrap();
        mark_denomination_stage_confirmed_at(&conn, "run-1", &expected_txid, 100, &[0xabu8; 32])
            .unwrap();
        let moved = mark_denomination_stage_confirmed_at(
            &conn,
            "run-1",
            &expected_txid,
            101,
            &[0xcdu8; 32],
        )
        .unwrap_err();
        assert!(moved.contains("different chain inclusion"));
        // A delayed broadcast callback must not regress a confirmed stage.
        mark_denomination_stage_broadcasted(&conn, "run-1", &expected_txid).unwrap();

        let counts = denomination_stage_status_counts(&conn, "run-1").unwrap();
        assert_eq!(
            counts,
            DenominationStageStatusCounts {
                confirmed: 1,
                total: 1,
                ..DenominationStageStatusCounts::default()
            }
        );
        assert!(all_denomination_stages_confirmed(&conn, "run-1").unwrap());
        assert!(locked_denomination_stage_input_outpoints(&conn, "run-1")
            .unwrap()
            .is_empty());

        let stored = denomination_stages_for_run(&conn, "run-1", PASSWORD, SALT_BASE64).unwrap();
        assert_eq!(stored[0].base_pczt, expected_base);
        assert_eq!(stored[0].sigs, expected_sigs);
        assert_eq!(stored[0].raw_tx, Some(vec![1, 2, 3, 4]));
        assert_eq!(stored[0].confirmed_mined_height, Some(100));
        assert_eq!(stored[0].confirmed_block_hash, Some(vec![0xabu8; 32]));

        let error = promote_awaiting_denomination_stage(
            &conn,
            "run-1",
            0,
            &expected_txid,
            vec![5, 6, 7, 8],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap_err();
        assert!(error.contains("not awaiting inputs"));
    }

    #[test]
    fn reorg_reset_clears_raw_transactions_for_only_the_dependent_branch() {
        let conn = setup();
        let mut root = awaiting_stage(0, 0x10);
        root.raw_tx = Some(vec![0x10]);
        root.status = DenominationStageStatus::Pending;
        let root_txid = root.expected_txid_hex.clone();
        let root_input = (root.inputs[0].txid_hex.clone(), root.inputs[0].output_index);
        let root_base = root.base_pczt.clone();
        let root_sigs = root.sigs.clone();

        let mut child = awaiting_stage(1, 0x11);
        child.raw_tx = Some(vec![0x11]);
        child.status = DenominationStageStatus::Pending;
        child.inputs = vec![DenominationStageInputRef {
            txid_hex: root_txid.clone(),
            output_index: 0,
            value_zatoshi: 420_000,
            note_version: 2,
            nullifier_hex: None,
        }];
        let child_input = (root_txid.clone(), 0);
        let child_txid = child.expected_txid_hex.clone();
        let child_base = child.base_pczt.clone();
        let child_sigs = child.sigs.clone();

        let mut independent = awaiting_stage(2, 0x12);
        independent.raw_tx = Some(vec![0x12]);
        independent.status = DenominationStageStatus::Pending;
        let independent_txid = independent.expected_txid_hex.clone();

        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(
            &tx,
            "run-1",
            vec![root, child, independent],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap();
        tx.commit().unwrap();
        for (txid, height, hash) in [
            (&root_txid, 100, [0x10; 32]),
            (&child_txid, 101, [0x11; 32]),
            (&independent_txid, 102, [0x12; 32]),
        ] {
            mark_denomination_stage_confirmed_at(&conn, "run-1", txid, height, &hash).unwrap();
        }
        assert!(locked_denomination_stage_input_outpoints(&conn, "run-1")
            .unwrap()
            .is_empty());

        reset_denomination_stage_for_reorg(&conn, "run-1", &root_txid).unwrap();
        // Repeating reconciliation is safe and keeps the same branch awaiting.
        reset_denomination_stage_for_reorg(&conn, "run-1", &root_txid).unwrap();

        let stages = denomination_stages_for_run(&conn, "run-1", PASSWORD, SALT_BASE64).unwrap();
        assert_eq!(stages[0].status, DenominationStageStatus::AwaitingInputs);
        assert_eq!(stages[0].raw_tx, None);
        assert_eq!(stages[0].base_pczt, root_base);
        assert_eq!(stages[0].sigs, root_sigs);
        assert_eq!(stages[1].status, DenominationStageStatus::AwaitingInputs);
        assert_eq!(stages[1].raw_tx, None);
        assert_eq!(stages[1].base_pczt, child_base);
        assert_eq!(stages[1].sigs, child_sigs);
        assert_eq!(stages[2].status, DenominationStageStatus::Confirmed);
        assert_eq!(stages[2].raw_tx, Some(vec![0x12]));
        assert_eq!(stages[2].expected_txid_hex, independent_txid);

        assert_eq!(
            locked_denomination_stage_input_outpoints(&conn, "run-1").unwrap(),
            BTreeSet::from([root_input, child_input])
        );
        let stale_broadcast =
            mark_denomination_stage_broadcasted(&conn, "run-1", &root_txid).unwrap_err();
        assert!(stale_broadcast.contains("awaiting_inputs to broadcasted"));
    }

    #[test]
    fn per_stage_confirmation_is_idempotent_and_releases_stage_input_locks() {
        let conn = setup();
        let mut pending = awaiting_stage(0, 0x10);
        pending.raw_tx = Some(vec![0x10]);
        pending.status = DenominationStageStatus::Pending;
        let pending_txid = pending.expected_txid_hex.clone();
        let mut to_broadcast = awaiting_stage(1, 0x11);
        to_broadcast.raw_tx = Some(vec![0x11]);
        to_broadcast.status = DenominationStageStatus::Pending;
        let broadcasted_txid = to_broadcast.expected_txid_hex.clone();
        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(
            &tx,
            "run-1",
            vec![pending, to_broadcast],
            PASSWORD,
            SALT_BASE64,
        )
        .unwrap();
        tx.commit().unwrap();
        mark_denomination_stage_broadcasted(&conn, "run-1", &broadcasted_txid).unwrap();
        assert_eq!(
            locked_denomination_stage_input_outpoints(&conn, "run-1")
                .unwrap()
                .len(),
            2
        );

        for txid in [&pending_txid, &broadcasted_txid] {
            mark_denomination_stage_confirmed_at(&conn, "run-1", txid, 100, &[0xcdu8; 32]).unwrap();
        }
        assert!(all_denomination_stages_confirmed(&conn, "run-1").unwrap());
        assert!(locked_denomination_stage_input_outpoints(&conn, "run-1")
            .unwrap()
            .is_empty());
    }

    #[test]
    fn locked_input_query_works_on_a_read_only_wallet_connection() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("wallet.db");
        let conn = Connection::open(&db_path).unwrap();
        ensure_schema(&conn).unwrap();
        let stage = awaiting_stage(0, 0x10);
        let expected_input = (
            stage.inputs[0].txid_hex.clone(),
            stage.inputs[0].output_index,
        );
        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(&tx, "run-1", vec![stage], PASSWORD, SALT_BASE64)
            .unwrap();
        tx.commit().unwrap();
        drop(conn);

        let read_only =
            Connection::open_with_flags(&db_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
                .unwrap();
        assert_eq!(
            locked_denomination_stage_input_outpoints(&read_only, "run-1").unwrap(),
            BTreeSet::from([expected_input])
        );
    }

    #[test]
    fn confirmation_can_recover_directly_from_pending() {
        let conn = setup();
        let mut stage = awaiting_stage(0, 0x10);
        stage.raw_tx = Some(vec![1, 2, 3]);
        stage.status = DenominationStageStatus::Pending;
        let expected_txid = stage.expected_txid_hex.clone();
        let tx = conn.unchecked_transaction().unwrap();
        insert_denomination_stages_with_tx(&tx, "run-1", vec![stage], PASSWORD, SALT_BASE64)
            .unwrap();
        tx.commit().unwrap();

        mark_denomination_stage_confirmed_at(&conn, "run-1", &expected_txid, 100, &[0xefu8; 32])
            .unwrap();
        assert_eq!(
            denomination_stage_status(&conn, "run-1", 0).unwrap(),
            Some(DenominationStageStatus::Confirmed)
        );
    }
}
