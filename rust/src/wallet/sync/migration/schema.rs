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

fn backfill_legacy_signed_schedule_metadata(
    conn: &rusqlite::Connection,
) -> Result<(), String> {
    let mut run_stmt = conn
        .prepare_cached(&format!(
            "SELECT run_id, target_values_json, schedule_json,
                    signed_schedule_origin_height
             FROM {RUNS_TABLE}"
        ))
        .map_err(|e| format!("Prepare legacy signed schedule runs: {e}"))?;
    let runs = run_stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<u32>>(3)?,
            ))
        })
        .map_err(|e| format!("Query legacy signed schedule runs: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read legacy signed schedule runs: {e}"))?;
    drop(run_stmt);

    for (run_id, target_values_json, schedule_json, persisted_origin) in runs {
        let Ok(target_values) = serde_json::from_str::<Vec<u64>>(&target_values_json) else {
            continue;
        };
        let Ok(schedule) =
            serde_json::from_str::<Vec<MigrationScheduleEntry>>(&schedule_json)
        else {
            continue;
        };
        if schedule.is_empty() {
            continue;
        }

        let mut child_stmt = conn
            .prepare_cached(&format!(
                "SELECT message_id, child_index, target_height, expiry_height,
                        scheduled_height, value_zatoshi
                 FROM {SIGNED_CHILD_PCZTS_TABLE}
                 WHERE run_id = ?1
                   AND (scheduled_height IS NULL OR scheduled_height = 0
                        OR scheduled_height = target_height)
                 ORDER BY child_index ASC, message_id ASC"
            ))
            .map_err(|e| format!("Prepare legacy signed children: {e}"))?;
        let children = child_stmt
            .query_map(params![run_id], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, u32>(1)?,
                    row.get::<_, u32>(2)?,
                    row.get::<_, u32>(3)?,
                    row.get::<_, Option<u32>>(4)?,
                    row.get::<_, u64>(5)?,
                ))
            })
            .map_err(|e| format!("Query legacy signed children: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read legacy signed children: {e}"))?;
        drop(child_stmt);

        let mut recovered_origin = persisted_origin;
        let mut invalid_children = Vec::new();
        for (
            message_id,
            child_index,
            target_height,
            expiry_height,
            stored_scheduled_height,
            value_zatoshi,
        ) in children
        {
            if persisted_origin.is_some()
                && stored_scheduled_height.is_some_and(|height| height != 0)
            {
                continue;
            }
            let Some(block_offset) = schedule_block_offset_for_part(
                &schedule,
                &target_values,
                child_index,
                value_zatoshi,
            ) else {
                invalid_children.push((message_id, child_index));
                continue;
            };
            let origin = target_height.saturating_sub(1);
            let Some(scheduled_height) = origin.checked_add(block_offset) else {
                invalid_children.push((message_id, child_index));
                continue;
            };
            if recovered_origin.is_some_and(|existing| existing != origin)
                || zip318_canonical_migration_expiry_height(scheduled_height)? != expiry_height
            {
                invalid_children.push((message_id, child_index));
                continue;
            }
            recovered_origin = Some(origin);
            conn.execute(
                &format!(
                    "UPDATE {SIGNED_CHILD_PCZTS_TABLE}
                     SET scheduled_height = ?1
                     WHERE run_id = ?2 AND message_id = ?3
                       AND (scheduled_height IS NULL OR scheduled_height = 0
                            OR scheduled_height = target_height)"
                ),
                params![scheduled_height, run_id, message_id],
            )
            .map_err(|e| format!("Backfill signed migration scheduled height: {e}"))?;
        }

        if let Some(origin) = recovered_origin {
            conn.execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                     SET signed_schedule_origin_height = COALESCE(
                         signed_schedule_origin_height, ?1
                     )
                     WHERE run_id = ?2"
                ),
                params![origin, run_id],
            )
            .map_err(|e| format!("Backfill signed migration schedule origin: {e}"))?;
        }
        if !invalid_children.is_empty() {
            for (message_id, child_index) in invalid_children {
                let has_pending_recovery = conn
                    .query_row(
                        &format!(
                            "SELECT 1 FROM {PENDING_TXS_TABLE}
                             WHERE run_id = ?1 AND part_index = ?2
                             LIMIT 1"
                        ),
                        params![run_id, child_index],
                        |_| Ok(()),
                    )
                    .optional()
                    .map_err(|e| format!("Check legacy signed child recovery row: {e}"))?
                    .is_some();
                if has_pending_recovery {
                    // The software recovery path needs the original message
                    // identity in order to replace this retained signature
                    // record after rebuilding the pending transaction.
                    continue;
                }
                conn.execute(
                    &format!(
                        "DELETE FROM {SIGNED_CHILD_PCZTS_TABLE}
                         WHERE run_id = ?1 AND message_id = ?2"
                    ),
                    params![run_id, message_id],
                )
                .map_err(|e| format!("Discard noncanonical legacy signed child: {e}"))?;
            }
            conn.execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                     SET phase = ?1,
                         last_error = 'Legacy migration signatures crossed a ZIP 318 expiry boundary and must be recreated'
                     WHERE run_id = ?2"
                ),
                params![PHASE_READY_TO_MIGRATE, run_id],
            )
            .map_err(|e| format!("Mark legacy signed children for recreation: {e}"))?;
        }
    }
    Ok(())
}

fn backfill_legacy_pending_schedule_metadata(
    conn: &rusqlite::Connection,
) -> Result<(), String> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT p.run_id, p.txid_hex, p.part_index, p.target_height,
                    p.expiry_height, p.scheduled_height, p.value_zatoshi,
                    r.target_values_json, r.schedule_json
             FROM {PENDING_TXS_TABLE} p
             JOIN {RUNS_TABLE} r ON r.run_id = p.run_id
             WHERE p.scheduled_height IS NULL OR p.scheduled_height = 0
                OR (p.scheduled_height = p.target_height
                    AND r.signed_schedule_origin_height IS NULL
                    AND p.status != 'needs_resign')
             ORDER BY p.run_id ASC, p.part_index ASC, p.txid_hex ASC"
        ))
        .map_err(|e| format!("Prepare legacy pending schedules: {e}"))?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, Option<u32>>(2)?,
                row.get::<_, u32>(3)?,
                row.get::<_, u32>(4)?,
                row.get::<_, Option<u32>>(5)?,
                row.get::<_, u64>(6)?,
                row.get::<_, String>(7)?,
                row.get::<_, String>(8)?,
            ))
        })
        .map_err(|e| format!("Query legacy pending schedules: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read legacy pending schedules: {e}"))?;
    drop(stmt);

    for (
        run_id,
        txid_hex,
        part_index,
        target_height,
        expiry_height,
        _,
        value_zatoshi,
        target_values_json,
        schedule_json,
    ) in rows
    {
        let (Ok(target_values), Ok(schedule)) = (
            serde_json::from_str::<Vec<u64>>(&target_values_json),
            serde_json::from_str::<Vec<MigrationScheduleEntry>>(&schedule_json),
        ) else {
            continue;
        };
        if schedule.is_empty() {
            continue;
        }
        let recovered = part_index
            .and_then(|part_index| {
                schedule_block_offset_for_part(
                    &schedule,
                    &target_values,
                    part_index,
                    value_zatoshi,
                )
            })
            .and_then(|offset| target_height.saturating_sub(1).checked_add(offset));
        let origin = target_height.saturating_sub(1);
        let persisted_origin = conn
            .query_row(
                &format!(
                    "SELECT signed_schedule_origin_height FROM {RUNS_TABLE}
                     WHERE run_id = ?1"
                ),
                params![run_id],
                |row| row.get::<_, Option<u32>>(0),
            )
            .map_err(|e| format!("Read pending migration schedule origin: {e}"))?;
        let canonical = persisted_origin.is_none_or(|existing| existing == origin)
            && recovered
                .map(zip318_canonical_migration_expiry_height)
                .transpose()?
                == Some(expiry_height);
        if canonical {
            let scheduled_height = recovered.expect("canonical recovery has a height");
            conn.execute(
                &format!(
                    "UPDATE {PENDING_TXS_TABLE}
                     SET scheduled_height = ?1,
                         schedule_start_height = COALESCE(schedule_start_height, ?2)
                     WHERE run_id = ?3 AND txid_hex = ?4"
                ),
                params![
                    scheduled_height,
                    target_height.saturating_sub(1),
                    run_id,
                    txid_hex
                ],
            )
            .map_err(|e| format!("Backfill pending migration schedule: {e}"))?;
            conn.execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                     SET signed_schedule_origin_height = COALESCE(
                         signed_schedule_origin_height, ?1
                     )
                     WHERE run_id = ?2"
                ),
                params![origin, run_id],
            )
            .map_err(|e| format!("Backfill pending migration schedule origin: {e}"))?;
        } else {
            conn.execute(
                &format!(
                    "UPDATE {PENDING_TXS_TABLE}
                     SET scheduled_height = target_height, status = 'needs_resign'
                     WHERE run_id = ?1 AND txid_hex = ?2"
                ),
                params![run_id, txid_hex],
            )
            .map_err(|e| format!("Mark legacy pending migration for re-signing: {e}"))?;
            conn.execute(
                &format!(
                    "UPDATE {RUNS_TABLE}
                     SET phase = ?1,
                         last_error = 'Legacy migration schedule crossed a ZIP 318 expiry boundary and must be recreated'
                     WHERE run_id = ?2"
                ),
                params![PHASE_READY_TO_MIGRATE, run_id],
            )
            .map_err(|e| format!("Mark legacy pending run for re-signing: {e}"))?;
        }
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
            preparation_timing_policy TEXT NOT NULL DEFAULT 'immediate',
            proof_retry_height INTEGER,
            signed_schedule_origin_height INTEGER,
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
            scheduled_height INTEGER,
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
    add_column_if_missing(
        conn,
        RUNS_TABLE,
        "preparation_timing_policy",
        "TEXT NOT NULL DEFAULT 'immediate'",
    )?;
    add_column_if_missing(conn, RUNS_TABLE, "proof_retry_height", "INTEGER")?;
    add_column_if_missing(
        conn,
        RUNS_TABLE,
        "signed_schedule_origin_height",
        "INTEGER",
    )?;
    add_column_if_missing(conn, PENDING_TXS_TABLE, "scheduled_height", "INTEGER")?;
    add_column_if_missing(conn, PENDING_TXS_TABLE, "schedule_start_height", "INTEGER")?;
    add_column_if_missing(
        conn,
        SIGNED_CHILD_PCZTS_TABLE,
        "scheduled_height",
        "INTEGER",
    )?;
    backfill_pending_part_indices(conn)?;
    backfill_legacy_signed_schedule_metadata(conn)?;
    backfill_legacy_pending_schedule_metadata(conn)?;
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
