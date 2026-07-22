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
