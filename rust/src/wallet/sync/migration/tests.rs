use super::*;
use rand::{rngs::StdRng, SeedableRng};
use std::cell::Cell;

const TEST_PASSWORD: &[u8] = b"correct horse battery staple";
const TEST_SALT_BASE64: &str = "AQIDBAUGBwgJCgsMDQ4PEA==";

#[test]
fn wallet_lock_reconciliation_retries_when_terminal_disposition_changes() {
    assert!(migration_phase_releases_wallet_locks(PHASE_COMPLETE));
    assert!(migration_phase_releases_wallet_locks(PHASE_FAILED_TERMINAL));
    assert!(migration_phase_releases_wallet_locks(PHASE_ABANDONED));
    assert!(!migration_phase_releases_wallet_locks(
        PHASE_READY_TO_MIGRATE
    ));

    assert!(!wallet_lock_reconciliation_is_stable(false, true));
    assert!(!wallet_lock_reconciliation_is_stable(true, false));
    assert!(wallet_lock_reconciliation_is_stable(false, false));
    assert!(wallet_lock_reconciliation_is_stable(true, true));
}

#[test]
fn wallet_lock_reconciliation_propagates_storage_failure() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("missing-parent")
        .join("wallet.db")
        .to_string_lossy()
        .into_owned();
    let network = WalletNetwork::Test;

    assert!(reconcile_wallet_locks_for_run(&db_path, network, "run-1").is_err());
}

#[test]
fn failed_run_creation_preserves_durable_run_when_unlock_fails() {
    let delete_called = Cell::new(false);
    let error = cleanup_failed_created_run(
        "reconciliation failed".to_string(),
        || Err("wallet database busy".to_string()),
        || {
            delete_called.set(true);
            Ok(())
        },
    );

    assert!(!delete_called.get());
    assert!(error.contains("durable run was preserved for recovery"));
    assert!(error.contains("wallet database busy"));
}

#[test]
fn failed_run_creation_deletes_run_only_after_unlock_succeeds() {
    let unlock_completed = Cell::new(false);
    let delete_saw_unlock = Cell::new(false);
    let error = cleanup_failed_created_run(
        "reconciliation failed".to_string(),
        || {
            unlock_completed.set(true);
            Ok(())
        },
        || {
            delete_saw_unlock.set(unlock_completed.get());
            Ok(())
        },
    );

    assert!(delete_saw_unlock.get());
    assert_eq!(error, "reconciliation failed");
}

fn create_outbox_test_run(
    db_path: &str,
    run_id: &str,
    values: &[u64],
    anchors: &[Option<u32>],
) -> Vec<String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    ensure_schema(&conn).unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json)
             VALUES (?1, 'account-1', 'regtest', ?2, ?3, 1, 1, ?4)"
        ),
        params![
            run_id,
            db_path,
            PHASE_READY_TO_MIGRATE,
            serde_json::to_string(values).unwrap(),
        ],
    )
    .unwrap();
    drop(conn);

    let schedule = values
        .iter()
        .enumerate()
        .map(|(index, value_zatoshi)| MigrationScheduleEntry {
            part_index: Some(index as u32),
            value_zatoshi: *value_zatoshi,
            block_offset: index as u32 + 1,
        })
        .collect::<Vec<_>>();
    set_run_approved_schedule(db_path, run_id, WalletNetwork::Regtest, &schedule, values).unwrap();
    let txids = values
        .iter()
        .enumerate()
        .map(|(index, _)| format!("{:064x}", index + 1))
        .collect::<Vec<_>>();
    let pending = values
        .iter()
        .enumerate()
        .map(|(index, value_zatoshi)| {
            let selected_note = PreparedOrchardNoteRef {
                txid_hex: format!("{:064x}", index + 100),
                output_index: 0,
                value_zatoshi: value_zatoshi + 10,
                note_version: 2,
                nullifier_hex: Some(format!("{:064x}", index + 200)),
            };
            PendingMigrationTxInsert {
                part_index: index as u32,
                txid_hex: txids[index].clone(),
                raw_tx: vec![index as u8, 0xaa, 0x55],
                target_height: 101,
                anchor_boundary_height: anchors[index],
                expiry_height: 69_120,
                scheduled_height: 100 + schedule[index].block_offset,
                value_zatoshi: *value_zatoshi,
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
    insert_pending_txs(db_path, run_id, pending, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();
    txids
}

fn pending_test_stage(expected_txid_hex: &str, raw_tx: Vec<u8>) -> DenominationStageInsert {
    DenominationStageInsert {
        stage_index: 0,
        base_pczt: vec![0xa0],
        sigs: Vec::new(),
        raw_tx: Some(raw_tx),
        expected_txid_hex: expected_txid_hex.to_string(),
        target_height: 3_000_000,
        scheduled_height: 0,
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

#[test]
fn schema_backfills_only_recoverable_original_schedule_heights() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    let schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100,
        block_offset: 5,
    }];
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, schedule_json,
              signed_schedule_origin_height)
             VALUES ('run-original', 'account-1', 'regtest', 'db', ?1, 1, 1,
                     '[100]', ?2, 100)"
        ),
        params![
            PHASE_BROADCAST_SCHEDULED,
            serde_json::to_string(&schedule).unwrap()
        ],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PENDING_TXS_TABLE}
             (run_id, txid_hex, part_index, encrypted_raw_tx, target_height,
              expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
              selected_note_output_index, selected_note_value, scheduled_at_ms,
              schedule_start_height, scheduled_height, status, metadata_json)
             VALUES ('run-original', ?1, 0, 'raw', 101, 69120, 100, 0, ?2,
                     0, 100, 1, 109, 110, 'scheduled', '{{}}')"
        ),
        params!["11".repeat(32), "22".repeat(32)],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, schedule_json)
             VALUES ('run-unknown-original', 'account-1', 'regtest', 'db', ?1,
                     1, 1, '[100]', '[]')"
        ),
        params![PHASE_BROADCAST_SCHEDULED],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PENDING_TXS_TABLE}
             (run_id, txid_hex, part_index, encrypted_raw_tx, target_height,
              expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
              selected_note_output_index, selected_note_value, scheduled_at_ms,
              schedule_start_height, scheduled_height, status, metadata_json)
             VALUES ('run-unknown-original', ?1, 0, 'raw', 101, 69120, 100, 0,
                     ?2, 0, 100, 1, 109, 110, 'scheduled', '{{}}')"
        ),
        params!["33".repeat(32), "44".repeat(32)],
    )
    .unwrap();

    ensure_schema(&conn).unwrap();

    let heights = conn
        .query_row(
            &format!(
                "SELECT original_scheduled_height, scheduled_height
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = 'run-original'"
            ),
            [],
            |row| Ok((row.get::<_, u32>(0)?, row.get::<_, u32>(1)?)),
        )
        .unwrap();
    assert_eq!(heights, (105, 110));
    let unknown_original = conn
        .query_row(
            &format!(
                "SELECT original_scheduled_height
                 FROM {PENDING_TXS_TABLE}
                 WHERE run_id = 'run-unknown-original'"
            ),
            [],
            |row| row.get::<_, Option<u32>>(0),
        )
        .unwrap();
    assert_eq!(unknown_original, None);
    let unknown_parts = migration_parts_for_run(
        &conn,
        "run-unknown-original",
        &[100],
        PHASE_BROADCAST_SCHEDULED,
        3,
    )
    .unwrap();
    assert_eq!(unknown_parts[0].original_scheduled_height, None);
    assert_eq!(unknown_parts[0].effective_scheduled_height, Some(110));
}

#[test]
fn legacy_signed_schedule_backfill_uses_approved_offsets_and_discards_wrong_bucket() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    let selected_note = serde_json::to_string(&PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 110,
        note_version: 2,
        nullifier_hex: Some("22".repeat(32)),
    })
    .unwrap();
    for (run_id, offset) in [("legacy-valid", 1u32), ("legacy-invalid", 2u32)] {
        let schedule = serde_json::to_string(&[MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 100,
            block_offset: offset,
        }])
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json, schedule_json)
                 VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1, '[100]', ?3)"
            ),
            params![run_id, PHASE_BROADCAST_SCHEDULED, schedule],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_compact_sigs, target_height, expiry_height,
                  scheduled_height, value_zatoshi, fee_zatoshi,
                  selected_note_json, metadata_json)
                 VALUES (?1, ?2, 0, 'base', 'sigs', 34559, 69120,
                         NULL, 100, 10, ?3, '{{}}')"
            ),
            params![run_id, format!("{run_id}-child"), selected_note],
        )
        .unwrap();
    }

    ensure_schema(&conn).unwrap();

    let (scheduled_height, origin): (u32, u32) = conn
        .query_row(
            &format!(
                "SELECT c.scheduled_height, r.signed_schedule_origin_height
                 FROM {SIGNED_CHILD_PCZTS_TABLE} c
                 JOIN {RUNS_TABLE} r ON r.run_id = c.run_id
                 WHERE c.run_id = 'legacy-valid'"
            ),
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(scheduled_height, 34_559);
    assert_eq!(origin, 34_558);

    let invalid_count: u32 = conn
        .query_row(
            &format!(
                "SELECT COUNT(*) FROM {SIGNED_CHILD_PCZTS_TABLE}
                 WHERE run_id = 'legacy-invalid'"
            ),
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(invalid_count, 0);
    let (phase, last_error): (String, Option<String>) = conn
        .query_row(
            &format!(
                "SELECT phase, last_error FROM {RUNS_TABLE}
                 WHERE run_id = 'legacy-invalid'"
            ),
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(phase, PHASE_READY_TO_MIGRATE);
    assert!(last_error.unwrap().contains("must be recreated"));
}

#[test]
fn legacy_signed_schedule_backfill_preserves_identity_for_pending_recovery() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    let run_id = "legacy-pending-recovery";
    let schedule = serde_json::to_string(&[MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100,
        block_offset: 2,
    }])
    .unwrap();
    let selected_note = PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 110,
        note_version: 2,
        nullifier_hex: Some("22".repeat(32)),
    };
    let selected_note_json = serde_json::to_string(&selected_note).unwrap();
    let metadata_json = serde_json::to_string(&PendingMigrationTxMetadata {
        tx_kind: "migration".to_string(),
        funding_account_uuid: "account-1".to_string(),
        selected_note: selected_note.clone(),
    })
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, schedule_json)
             VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1, '[100]', ?3)"
        ),
        params![run_id, PHASE_BROADCAST_SCHEDULED, schedule],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
             (run_id, message_id, child_index, encrypted_base_pczt,
              encrypted_compact_sigs, target_height, expiry_height,
              scheduled_height, value_zatoshi, fee_zatoshi,
              selected_note_json, metadata_json)
             VALUES (?1, 'retained-child', 0, 'base', 'sigs', 34559, 69120,
                     NULL, 100, 10, ?2, ?3)"
        ),
        params![run_id, selected_note_json, metadata_json],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PENDING_TXS_TABLE}
             (run_id, txid_hex, part_index, encrypted_raw_tx, target_height,
              expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
              selected_note_output_index, selected_note_value, scheduled_at_ms,
              schedule_start_height, scheduled_height, status, metadata_json)
             VALUES (?1, ?2, 0, 'raw', 34559, 69120, 100, 10, ?3, 0, 110,
                     1, 34558, 34559, 'scheduled', ?4)"
        ),
        params![
            run_id,
            "33".repeat(32),
            selected_note.txid_hex,
            metadata_json
        ],
    )
    .unwrap();

    ensure_schema(&conn).unwrap();

    let (message_id, status): (String, String) = conn
        .query_row(
            &format!(
                "SELECT c.message_id, p.status
                 FROM {SIGNED_CHILD_PCZTS_TABLE} c
                 JOIN {PENDING_TXS_TABLE} p
                   ON p.run_id = c.run_id AND p.part_index = c.child_index
                 WHERE c.run_id = ?1"
            ),
            params![run_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(message_id, "retained-child");
    assert_eq!(status, "needs_resign");
}

fn insert_duplicate_broadcast_terminal_failure(conn: &rusqlite::Connection) {
    ensure_schema(&conn).unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, last_error)
             VALUES ('duplicate-run', 'account-1', 'test', 'wallet.db', ?1,
                     1, 1, '[100000]', ?2)"
        ),
        params![
            PHASE_FAILED_TERMINAL,
            "Migration transaction abc was rejected by the network. Error: Broadcast rejected: failed to validate tx: WtxId(\"private\"), error: transaction is already in state (code -25)",
        ],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PREPARED_NOTES_TABLE}
             (run_id, txid_hex, output_index, value_zatoshi, note_version, lock_state)
             VALUES ('duplicate-run', ?1, 0, 115000, 2, 'unlocked')"
        ),
        params!["11".repeat(32)],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PENDING_TXS_TABLE}
             (run_id, txid_hex, part_index, encrypted_raw_tx, target_height,
              expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
              selected_note_output_index, selected_note_value, scheduled_at_ms,
              scheduled_height, status, metadata_json)
             VALUES ('duplicate-run', ?1, 0, 'encrypted', 10, 100, 100000,
                     15000, ?2, 0, 115000, 1, 20, 'scheduled', '{{}}')"
        ),
        params!["22".repeat(32), "11".repeat(32)],
    )
    .unwrap();
}

#[test]
fn active_run_does_not_recover_latest_duplicate_broadcast_terminal_failure() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    insert_duplicate_broadcast_terminal_failure(&conn);

    assert!(active_run(&conn, "account-1", WalletNetwork::Test)
        .unwrap()
        .is_none());
    let (phase, lock_state): (String, String) = conn
        .query_row(
            &format!(
                "SELECT r.phase, n.lock_state
                 FROM {RUNS_TABLE} r
                 JOIN {PREPARED_NOTES_TABLE} n ON n.run_id = r.run_id
                 WHERE r.run_id = 'duplicate-run'"
            ),
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(phase, PHASE_FAILED_TERMINAL);
    assert_eq!(lock_state, "unlocked");
}

#[test]
fn reservation_snapshot_keeps_false_terminal_visible_during_recovery() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().into_owned();
    let setup_conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    insert_duplicate_broadcast_terminal_failure(&setup_conn);
    drop(setup_conn);

    let reader = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let snapshot = reader.unchecked_transaction().unwrap();
    assert!(active_run(&snapshot, "account-1", WalletNetwork::Test)
        .unwrap()
        .is_none());

    let writer = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    recover_latest_idempotent_broadcast_failure(&writer, "account-1", WalletNetwork::Test).unwrap();
    assert_eq!(
        active_run(&writer, "account-1", WalletNetwork::Test)
            .unwrap()
            .unwrap()
            .phase,
        PHASE_BROADCAST_SCHEDULED
    );

    assert!(migration_reserves_orchard_inputs_in_snapshot(
        &snapshot,
        "account-1",
        WalletNetwork::Test,
    )
    .unwrap());
    snapshot.commit().unwrap();
}

#[test]
fn migration_status_does_not_recover_latest_duplicate_broadcast_terminal_failure() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().into_owned();
    let conn = rusqlite::Connection::open(&db_path).unwrap();
    insert_duplicate_broadcast_terminal_failure(&conn);
    drop(conn);

    assert!(
        migration_reserves_orchard_inputs(&db_path, "account-1", WalletNetwork::Test,).unwrap()
    );
    migration_status(&db_path, WalletNetwork::Test, "account-1", 0, 0, 0, 0).unwrap();
    assert!(
        migration_reserves_orchard_inputs(&db_path, "account-1", WalletNetwork::Test,).unwrap()
    );
    assert_eq!(
        create_or_resume_private_migration_draft(
            &db_path,
            "account-1",
            WalletNetwork::Test,
            &[100_000],
            &[],
            PreparationTimingPolicy::Immediate,
        )
        .unwrap_err(),
        "Migration recovery must complete before creating another run"
    );

    let conn = rusqlite::Connection::open(&db_path).unwrap();
    let (phase, lock_state): (String, String) = conn
        .query_row(
            &format!(
                "SELECT r.phase, n.lock_state
                 FROM {RUNS_TABLE} r
                 JOIN {PREPARED_NOTES_TABLE} n ON n.run_id = r.run_id
                 WHERE r.run_id = 'duplicate-run'"
            ),
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(phase, PHASE_FAILED_TERMINAL);
    assert_eq!(lock_state, "unlocked");
}

#[test]
fn post_sync_recovery_restores_latest_duplicate_broadcast_terminal_failure() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().into_owned();
    let conn = rusqlite::Connection::open(&db_path).unwrap();
    insert_duplicate_broadcast_terminal_failure(&conn);
    drop(conn);

    reconcile_wallet_locks_after_sync(&db_path, WalletNetwork::Test).unwrap();

    let conn = rusqlite::Connection::open(&db_path).unwrap();
    let run = active_run(&conn, "account-1", WalletNetwork::Test)
        .unwrap()
        .unwrap();
    assert_eq!(run.run_id, "duplicate-run");
    assert_eq!(run.phase, PHASE_BROADCAST_SCHEDULED);
    assert_eq!(run.last_error, None);
    let lock_state: String = conn
        .query_row(
            &format!(
                "SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = 'duplicate-run'"
            ),
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(lock_state, "locked");
}

#[test]
fn active_run_does_not_recover_other_terminal_broadcast_failures() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, last_error)
             VALUES ('rejected-run', 'account-1', 'test', 'wallet.db', ?1,
                     1, 1, '[100000]', ?2)"
        ),
        params![
            PHASE_FAILED_TERMINAL,
            "Broadcast rejected: bad-txns-inputs-spent (code 18)",
        ],
    )
    .unwrap();

    assert!(active_run(&conn, "account-1", WalletNetwork::Test)
        .unwrap()
        .is_none());
    assert!(
        latest_idempotent_broadcast_failure(&conn, "account-1", WalletNetwork::Test)
            .unwrap()
            .is_none()
    );
    let phase: String = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = 'rejected-run'"),
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(phase, PHASE_FAILED_TERMINAL);
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

fn insert_preparation_policy_test_run(
    conn: &rusqlite::Connection,
    run_id: &str,
    policy: PreparationTimingPolicy,
    stage_count: u32,
    target_height: u32,
) {
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json,
              preparation_timing_policy)
             VALUES (?1, 'account-1', 'test', 'db', ?2, 1, 1, '[]', ?3)"
        ),
        params![run_id, PHASE_READY_TO_PREPARE, policy.as_str()],
    )
    .unwrap();
    for stage_index in 0..stage_count {
        conn.execute(
            &format!(
                "INSERT INTO {STAGES_TABLE}
                 (run_id, stage_index, encrypted_base_pczt,
                  encrypted_compact_sigs, encrypted_raw_tx, expected_txid_hex,
                  target_height, expiry_height, fee_zatoshi, status)
                 VALUES (?1, ?2, 'base', 'sigs', 'raw', ?3, ?4, 0, 1, 'pending')"
            ),
            params![
                run_id,
                stage_index,
                format!("{:064x}", u64::from(stage_index) + 1),
                target_height,
            ],
        )
        .unwrap();
    }
}

fn preparation_catch_up_test_rows(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Vec<(u32, u32, Option<u32>, u32)> {
    let mut stmt = conn
        .prepare(&format!(
            "SELECT stage_index, scheduled_height,
                    broadcast_not_before_height, expiry_height
             FROM {STAGES_TABLE}
             WHERE run_id = ?1
             ORDER BY stage_index ASC"
        ))
        .unwrap();
    stmt.query_map(params![run_id], |row| {
        Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
    })
    .unwrap()
    .collect::<Result<Vec<_>, _>>()
    .unwrap()
}

fn insert_recovered_pending_preparation_test_run(
    conn: &rusqlite::Connection,
    run_id: &str,
    scheduled_heights: [u32; 3],
    mined_height: u32,
) {
    conn.execute_batch(
        "CREATE TABLE blocks (height INTEGER PRIMARY KEY, hash BLOB NOT NULL);
         CREATE TABLE transactions (
             txid BLOB PRIMARY KEY,
             block INTEGER,
             mined_height INTEGER
         );",
    )
    .unwrap();
    insert_preparation_policy_test_run(conn, run_id, PreparationTimingPolicy::Zip318Spaced, 3, 101);
    for (stage_index, scheduled_height) in scheduled_heights.into_iter().enumerate() {
        conn.execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET scheduled_height = ?1, expiry_height = 3490560
                 WHERE run_id = ?2 AND stage_index = ?3"
            ),
            params![scheduled_height, run_id, stage_index],
        )
        .unwrap();
    }

    let block_hash = [0xabu8; 32];
    conn.execute(
        "INSERT INTO blocks (height, hash) VALUES (?1, ?2)",
        params![mined_height, block_hash.as_slice()],
    )
    .unwrap();
    let mut stored_txid = hex::decode(format!("{:064x}", 1)).unwrap();
    stored_txid.reverse();
    conn.execute(
        "INSERT INTO transactions (txid, block, mined_height)
         VALUES (?1, ?2, ?2)",
        params![stored_txid, mined_height],
    )
    .unwrap();
}

fn seed_account_migration_rows(
    conn: &rusqlite::Connection,
    run_id: &str,
    account_uuid: &str,
    suffix: &str,
) {
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json)
             VALUES (?1, ?2, 'regtest', 'wallet.db', ?3, 1, 1, '[100]')"
        ),
        params![run_id, account_uuid, PHASE_BROADCAST_SCHEDULED],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PREPARED_NOTES_TABLE}
             (run_id, txid_hex, output_index, value_zatoshi, note_version)
             VALUES (?1, ?2, 0, 115000, 2)"
        ),
        params![run_id, format!("prepared-{suffix}")],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PENDING_TXS_TABLE}
             (run_id, txid_hex, encrypted_raw_tx, target_height, expiry_height,
              value_zatoshi, fee_zatoshi, selected_note_txid,
              selected_note_output_index, selected_note_value, scheduled_at_ms,
              scheduled_height, status, metadata_json)
             VALUES (?1, ?2, 'ciphertext', 10, 100, 100000, 15000, ?3,
                     0, 115000, 1, 20, 'scheduled', '{{}}')"
        ),
        params![
            run_id,
            format!("pending-{suffix}"),
            format!("selected-{suffix}"),
        ],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
             (run_id, message_id, child_index, encrypted_base_pczt,
              encrypted_compact_sigs, target_height, expiry_height,
              value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
             VALUES (?1, ?2, 0, 'base', 'sigs', 10, 100,
                     100000, 15000, '{{}}', '{{}}')"
        ),
        params![run_id, format!("message-{suffix}")],
    )
    .unwrap();
    let stage_txid = format!("{:02x}", suffix.as_bytes()[0]).repeat(32);
    insert_test_stage(
        conn,
        run_id,
        &stage_txid,
        DenominationStageStatus::Pending,
        None,
    );
}

fn account_migration_tables() -> [&'static str; 7] {
    [
        RUNS_TABLE,
        PREPARED_NOTES_TABLE,
        PENDING_TXS_TABLE,
        SIGNED_CHILD_PCZTS_TABLE,
        STAGES_TABLE,
        STAGE_INPUTS_TABLE,
        STAGE_OUTPUTS_TABLE,
    ]
}

#[test]
fn delete_account_migration_rows_removes_only_owned_runs_and_children() {
    let mut conn = rusqlite::Connection::open_in_memory().unwrap();
    conn.execute("PRAGMA foreign_keys = ON", []).unwrap();
    ensure_schema(&conn).unwrap();
    seed_account_migration_rows(&conn, "deleted-run", "deleted-account", "deleted");
    seed_account_migration_rows(&conn, "kept-run", "kept-account", "kept");

    let tx = conn.transaction().unwrap();
    delete_account_migration_rows_with_tx(&tx, "deleted-account").unwrap();
    tx.commit().unwrap();

    for table in account_migration_tables() {
        assert_eq!(count_for_run(&conn, table, "deleted-run").unwrap(), 0);
        assert_eq!(count_for_run(&conn, table, "kept-run").unwrap(), 1);
    }
}

#[test]
fn delete_account_migration_rows_rolls_back_with_account_transaction() {
    let mut conn = rusqlite::Connection::open_in_memory().unwrap();
    conn.execute("PRAGMA foreign_keys = ON", []).unwrap();
    ensure_schema(&conn).unwrap();
    seed_account_migration_rows(&conn, "deleted-run", "deleted-account", "deleted");
    seed_account_migration_rows(&conn, "kept-run", "kept-account", "kept");

    let tx = conn.transaction().unwrap();
    delete_account_migration_rows_with_tx(&tx, "deleted-account").unwrap();
    tx.rollback().unwrap();

    for table in account_migration_tables() {
        assert_eq!(count_for_run(&conn, table, "deleted-run").unwrap(), 1);
        assert_eq!(count_for_run(&conn, table, "kept-run").unwrap(), 1);
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
    let plan = plan_denominations(540 * ZATOSHIS_PER_ZEC, 0, 0, MINIMUM_OUTPUT_FOR_TEST).unwrap();

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
fn pending_insert_rejects_expiry_from_a_different_schedule_bucket() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    ensure_schema(&conn).unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json)
             VALUES ('run-1', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100]')"
        ),
        params![db_path, PHASE_READY_TO_MIGRATE],
    )
    .unwrap();
    drop(conn);
    let schedule = [MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100,
        block_offset: 1,
    }];
    set_run_approved_schedule(&db_path, "run-1", WalletNetwork::Regtest, &schedule, &[100])
        .unwrap();
    let selected_note = PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 110,
        note_version: 2,
        nullifier_hex: None,
    };
    let error = insert_pending_txs(
        &db_path,
        "run-1",
        vec![PendingMigrationTxInsert {
            part_index: 0,
            txid_hex: "22".repeat(32),
            raw_tx: vec![1],
            target_height: 34_560,
            anchor_boundary_height: Some(30_000),
            expiry_height: 69_120,
            scheduled_height: 34_560,
            value_zatoshi: 100,
            fee_zatoshi: 10,
            selected_note: selected_note.clone(),
            metadata: PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: "account-1".to_string(),
                selected_note,
            },
        }],
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap_err();
    assert!(error.contains("not canonical for scheduled height"));
}

#[test]
fn overdue_reschedule_crossing_expiry_bucket_requires_resigning() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(&db_path, "run-1", &[100], &[Some(90)]);
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET schedule_start_height = 34558, scheduled_height = 34559,
                 expiry_height = 69120
             WHERE run_id = 'run-1'"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    reschedule_overdue_pending_txs(&db_path, "run-1", WalletNetwork::Regtest, 34_560).unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let status = conn
        .query_row(
            &format!(
                "SELECT status FROM {PENDING_TXS_TABLE}
                 WHERE txid_hex = ?1"
            ),
            params![txids[0]],
            |row| row.get::<_, String>(0),
        )
        .unwrap();
    assert_eq!(status, "needs_resign");
    assert_eq!(
        run_phase(&db_path, "run-1").unwrap(),
        PHASE_READY_TO_MIGRATE
    );
}

#[test]
fn on_open_reschedule_redraws_overdue_transfers_across_wallet_runs() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    create_outbox_test_run(&db_path, "run-1", &[100, 200], &[Some(90), Some(90)]);
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET txid_hex = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
             WHERE run_id = 'run-1' AND part_index = 0"
        ),
        [],
    )
    .unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET txid_hex = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
             WHERE run_id = 'run-1' AND part_index = 1"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    create_outbox_test_run(&db_path, "run-2", &[300], &[Some(90)]);
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!("UPDATE {RUNS_TABLE} SET account_uuid = 'account-2' WHERE run_id = 'run-2'"),
        [],
    )
    .unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET scheduled_height = 503, schedule_start_height = 502
             WHERE status = 'scheduled'"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    mark_pending_broadcasted(
        &db_path,
        "run-1",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
    .unwrap();
    reschedule_wallet_overdue_pending_txs(&db_path, WalletNetwork::Regtest, 503).unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let remaining = conn
        .prepare(
            "SELECT run_id, scheduled_height
             FROM vizor_migration_pending_txs
             WHERE status = 'scheduled'
             ORDER BY run_id, part_index",
        )
        .unwrap()
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, u32>(1)?))
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(remaining.len(), 2);
    assert_eq!(
        remaining
            .iter()
            .map(|entry| entry.0.as_str())
            .collect::<Vec<_>>(),
        vec!["run-1", "run-2"]
    );
    assert!(remaining.iter().all(|entry| entry.1 > 503));
}

#[test]
fn on_open_storage_recovery_keeps_accepted_tx_and_redraws_every_other_run() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    create_outbox_test_run(&db_path, "run-1", &[100, 200], &[Some(90), Some(90)]);
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET txid_hex = CASE part_index
                 WHEN 0 THEN 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                 ELSE 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
             END
             WHERE run_id = 'run-1'"
        ),
        [],
    )
    .unwrap();
    drop(conn);
    let accepted_txid = "a".repeat(64);
    create_outbox_test_run(&db_path, "run-2", &[300], &[Some(90)]);
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!("UPDATE {RUNS_TABLE} SET account_uuid = 'account-2' WHERE run_id = 'run-2'"),
        [],
    )
    .unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET scheduled_height = 503, schedule_start_height = 502
             WHERE status = 'scheduled'"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    reschedule_wallet_overdue_pending_txs_after_accepted(
        &db_path,
        WalletNetwork::Regtest,
        503,
        "run-1",
        &accepted_txid,
    )
    .unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let schedules = conn
        .prepare(
            "SELECT run_id, txid_hex, scheduled_height
             FROM vizor_migration_pending_txs
             WHERE status = 'scheduled'
             ORDER BY run_id, part_index",
        )
        .unwrap()
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u32>(2)?,
            ))
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(schedules.len(), 3);
    assert_eq!(
        schedules
            .iter()
            .find(|(_, txid, _)| txid == &accepted_txid)
            .unwrap()
            .2,
        503
    );
    assert!(schedules
        .iter()
        .filter(|(_, txid, _)| txid != &accepted_txid)
        .all(|(_, _, height)| *height > 503));
}

#[test]
fn overdue_broadcast_crossing_expiry_bucket_requires_resigning_before_send() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    create_outbox_test_run(&db_path, "run-1", &[100], &[Some(90)]);
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET schedule_start_height = 34558, scheduled_height = 34559,
                 expiry_height = 69120
             WHERE run_id = 'run-1'"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    assert_eq!(
        mark_due_parts_with_noncanonical_broadcast_height_for_resign(&db_path, "run-1", 34_560,)
            .unwrap(),
        1
    );
    assert!(
        due_pending_txs(&db_path, "run-1", 34_560, TEST_PASSWORD, TEST_SALT_BASE64,)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn incremental_child_promotion_uses_immutable_signed_schedule_origin() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "incremental-origin",
        &[100, 200],
        &[Some(90), Some(90)],
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!("DELETE FROM {PENDING_TXS_TABLE} WHERE txid_hex = ?1"),
        params![txids[1]],
    )
    .unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET schedule_start_height = 500, scheduled_height = 501
             WHERE txid_hex = ?1"
        ),
        params![txids[0]],
    )
    .unwrap();
    drop(conn);

    let selected_note = PreparedOrchardNoteRef {
        txid_hex: format!("{:064x}", 101),
        output_index: 0,
        value_zatoshi: 210,
        note_version: 2,
        nullifier_hex: Some(format!("{:064x}", 201)),
    };
    insert_pending_txs(
        &db_path,
        "incremental-origin",
        vec![PendingMigrationTxInsert {
            part_index: 1,
            txid_hex: txids[1].clone(),
            raw_tx: vec![1, 0xaa, 0x55],
            target_height: 101,
            anchor_boundary_height: Some(90),
            expiry_height: 69_120,
            scheduled_height: 102,
            value_zatoshi: 200,
            fee_zatoshi: 10,
            selected_note: selected_note.clone(),
            metadata: PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: "account-1".to_string(),
                selected_note,
            },
        }],
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let origin: u32 = conn
        .query_row(
            &format!(
                "SELECT signed_schedule_origin_height FROM {RUNS_TABLE}
                 WHERE run_id = 'incremental-origin'"
            ),
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(origin, 100);
}

#[test]
fn accepted_receipt_keeps_re_sign_phase_when_peer_crosses_expiry_bucket() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "outbox-boundary",
        &[100, 200],
        &[Some(90), Some(90)],
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET schedule_start_height = 34558, scheduled_height = 34559,
                 expiry_height = 69120
             WHERE run_id = 'outbox-boundary'"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    apply_accepted_migration_outbox_receipt(
        &db_path,
        "account-1",
        WalletNetwork::Regtest,
        "outbox-boundary",
        &txids[0],
        34_559,
        &[MigrationOutboxScheduleUpdate {
            item_id: txids[1].clone(),
            scheduled_height: 34_560,
            schedule_start_height: 34_559,
        }],
    )
    .unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let (phase, last_error, peer_status): (String, Option<String>, String) = conn
        .query_row(
            &format!(
                "SELECT r.phase, r.last_error, p.status
                 FROM {RUNS_TABLE} r
                 JOIN {PENDING_TXS_TABLE} p ON p.run_id = r.run_id
                 WHERE r.run_id = 'outbox-boundary' AND p.txid_hex = ?1"
            ),
            params![txids[1]],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(phase, PHASE_READY_TO_MIGRATE);
    assert_eq!(peer_status, "needs_resign");
    assert!(last_error.unwrap().contains("ZIP 318 expiry boundary"));
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
fn anchor_bucket_candidates_include_latest_but_exclude_pre_activation_boundaries() {
    assert_eq!(ZIP318_ANCHOR_AGE_CAP, 4);

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
        vec![5616, 5472, 5328, 5184, 5040]
    );
    assert_eq!(
        zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5700, 5600, 5000),
        vec![5616]
    );
    assert_eq!(
        zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5900, 5600, 5000),
        vec![5760, 5616]
    );

    assert!(zip318_anchor_boundary_is_candidate(
        WalletNetwork::Test,
        5472,
        5700,
        5000,
        5000
    ));
    assert!(zip318_anchor_boundary_is_candidate(
        WalletNetwork::Test,
        5616,
        5700,
        5000,
        5000
    ));
    assert_eq!(
        zip318_anchor_candidate_boundaries_with_policy(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            5700,
            5000,
            5000,
        ),
        vec![5472, 5328, 5184, 5040]
    );
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

    let latest_boundary = ZIP318_ANCHOR_BUCKET_MODULUS * (ZIP318_ANCHOR_AGE_CAP.saturating_add(2));
    let capped_candidates =
        zip318_anchor_candidate_boundaries(WalletNetwork::Test, latest_boundary, 1, 0);
    assert_eq!(capped_candidates.len(), ZIP318_ANCHOR_AGE_CAP as usize + 1);
    assert_eq!(capped_candidates.first(), Some(&latest_boundary));
    assert_eq!(
        capped_candidates.last(),
        Some(&(latest_boundary - ZIP318_ANCHOR_BUCKET_MODULUS * ZIP318_ANCHOR_AGE_CAP))
    );
    assert!(!zip318_anchor_boundary_is_candidate(
        WalletNetwork::Test,
        latest_boundary - ZIP318_ANCHOR_BUCKET_MODULUS * (ZIP318_ANCHOR_AGE_CAP + 1),
        latest_boundary,
        1,
        0,
    ));
}

#[test]
fn proof_retry_waits_until_the_next_boundary_is_trusted() {
    assert_eq!(
        next_anchor_retry_height_after(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            5_700,
        )
        .unwrap(),
        5_762
    );
    assert_eq!(
        next_anchor_retry_height_after(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            5_760,
        )
        .unwrap(),
        5_762
    );
    assert_eq!(
        next_anchor_retry_height_after(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            5_761,
        )
        .unwrap(),
        5_762
    );
    assert_eq!(
        next_anchor_retry_height_after(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            5_762,
        )
        .unwrap(),
        5_906
    );
    assert_eq!(
        next_anchor_retry_height_after(
            WalletNetwork::Regtest,
            MigrationTimingPolicy::Standard,
            10,
        )
        .unwrap(),
        13
    );
}

#[test]
fn proof_readiness_ages_the_boundary_containing_the_prepared_note() {
    assert_eq!(
        estimated_proof_ready_height(WalletNetwork::Main, 142).unwrap(),
        146
    );
    assert_eq!(
        proof_readiness_delay_blocks(WalletNetwork::Main, 142).unwrap(),
        2
    );
    assert_eq!(
        proof_readiness_delay_blocks(WalletNetwork::Regtest, 10).unwrap(),
        0
    );
    assert_eq!(
        proof_ready_height_for_note_mined_height(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            4_194_451,
        )
        .unwrap(),
        4_194_722
    );
    assert_eq!(
        proof_ready_height_for_note_mined_height(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            4_194_576,
        )
        .unwrap(),
        4_194_722
    );
    assert_eq!(
        proof_ready_height_for_note_mined_height(
            WalletNetwork::Regtest,
            MigrationTimingPolicy::Standard,
            10,
        )
        .unwrap(),
        12
    );
}

#[test]
fn anchor_bucket_draw_stays_within_candidate_set() {
    let candidates = zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5700, 5000, 5000);
    assert!(!candidates.is_empty());

    for _ in 0..32 {
        let boundary =
            zip318_draw_anchor_boundary_for_note(WalletNetwork::Test, 5700, 5000, 5000).unwrap();
        assert!(candidates.contains(&boundary));
    }
    assert_eq!(
        zip318_draw_anchor_boundary_for_note(WalletNetwork::Test, 5700, 5600, 5000),
        Some(5616)
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
fn anchor_bucket_draw_renormalizes_over_available_checkpoint_boundaries() {
    let candidates = zip318_anchor_candidate_boundaries(WalletNetwork::Test, 5700, 5000, 5000);
    let available = vec![candidates[1], candidates[3]];

    for _ in 0..32 {
        let boundary = zip318_draw_anchor_boundary_from_available_with_policy(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            5700,
            &available,
        )
        .unwrap();
        assert!(available.contains(&boundary));
    }

    assert_eq!(
        zip318_draw_anchor_boundary_from_available_with_policy(
            WalletNetwork::Test,
            MigrationTimingPolicy::Standard,
            5700,
            &[],
        ),
        None
    );
}

#[test]
fn planner_drains_balance_beyond_the_old_run_cap() {
    let input = 1_999_999_950_000_000;
    let migration_fee = 10_000;
    let plan = plan_denominations(input, 0, migration_fee, 1).unwrap();

    assert!(plan.migration_outputs.len() > 64);
    assert!(plan
        .migration_outputs
        .iter()
        .all(|value| is_zip318_canonical_denomination(*value)));
    let orchard_change = plan.orchard_change.unwrap_or(0);
    assert!(!orchard_balance_can_create_migration_output(orchard_change).unwrap());
    assert_eq!(
        plan.total_migratable_zatoshi
            + migration_fee * plan.migration_outputs.len() as u64
            + orchard_change,
        input
    );
}

#[test]
fn timing_projection_starts_approved_offsets_after_initial_proof_readiness() {
    let schedule = vec![
        MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 100,
            block_offset: 0,
        },
        MigrationScheduleEntry {
            part_index: Some(1),
            value_zatoshi: 200,
            block_offset: 48,
        },
        MigrationScheduleEntry {
            part_index: Some(2),
            value_zatoshi: 300,
            block_offset: 96,
        },
    ];
    let signed_children = vec![
        MigrationTimingSignedChild {
            part_index: 0,
            target_height: 101,
        },
        MigrationTimingSignedChild {
            part_index: 1,
            target_height: 101,
        },
        MigrationTimingSignedChild {
            part_index: 2,
            target_height: 101,
        },
    ];

    let projection =
        calculate_migration_timing_projection(&schedule, &[], &signed_children, Some(200), 3, 3)
            .unwrap();

    assert_eq!(projection.next_action_height, Some(200));
    assert_eq!(projection.next_action_part_index, Some(0));
    assert_eq!(projection.next_proof_window_height, Some(200));
    assert_eq!(projection.next_proof_window_part_indices, vec![0, 1, 2]);
    assert_eq!(projection.estimated_completion_height, Some(299));
    assert_eq!(
        projection.schedule_order_by_part,
        BTreeMap::from([(0, 0), (1, 1), (2, 2)])
    );
    assert_eq!(
        projection.projected_signed_parts,
        vec![
            MigrationTimingProjectedSignedPart {
                part_index: 0,
                schedule_start_height: 200,
                scheduled_height: 200,
            },
            MigrationTimingProjectedSignedPart {
                part_index: 1,
                schedule_start_height: 200,
                scheduled_height: 248,
            },
            MigrationTimingProjectedSignedPart {
                part_index: 2,
                schedule_start_height: 200,
                scheduled_height: 296,
            },
        ]
    );
}

#[test]
fn persisting_presigned_children_keeps_ready_phase_and_proof_height() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    ensure_schema(&conn).unwrap();
    let schedule = serde_json::to_string(&[MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100_000,
        block_offset: 10,
    }])
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, schedule_json,
              proof_retry_height)
             VALUES ('run-presigned-handoff', 'account-1', 'test', ?1, ?2,
                     1, 1, '[100000]', ?3, 200)"
        ),
        params![db_path, PHASE_READY_TO_MIGRATE, schedule],
    )
    .unwrap();
    drop(conn);

    let selected_note = PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 110_000,
        note_version: 2,
        nullifier_hex: Some("22".repeat(32)),
    };
    persist_signed_child_pczts_for_run(
        &db_path,
        "run-presigned-handoff",
        vec![SignedMigrationPcztInsert {
            message_id: "migration-1".to_string(),
            child_index: 0,
            base_pczt: vec![1, 2, 3],
            sigs: Vec::new(),
            target_height: 100,
            anchor_boundary_height: None,
            expiry_height: 69_120,
            scheduled_height: 110,
            value_zatoshi: 100_000,
            fee_zatoshi: 10_000,
            selected_note: selected_note.clone(),
            metadata: PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: "account-1".to_string(),
                selected_note,
            },
        }],
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let (phase, proof_retry_height, signed_count): (String, Option<u32>, u32) = conn
        .query_row(
            &format!(
                "SELECT phase, proof_retry_height,
                        (SELECT COUNT(*) FROM {SIGNED_CHILD_PCZTS_TABLE}
                         WHERE run_id = r.run_id)
                 FROM {RUNS_TABLE} r
                 WHERE run_id = 'run-presigned-handoff'"
            ),
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(phase, PHASE_READY_TO_MIGRATE);
    assert_eq!(proof_retry_height, Some(200));
    assert_eq!(signed_count, 1);
}

#[test]
fn timing_projection_keeps_unpromoted_parts_after_a_reschedule() {
    let schedule = vec![
        MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 100,
            block_offset: 144,
        },
        MigrationScheduleEntry {
            part_index: Some(1),
            value_zatoshi: 200,
            block_offset: 288,
        },
    ];
    let pending = vec![MigrationTimingPendingPart {
        part_index: Some(0),
        target_height: 101,
        schedule_start_height: Some(500),
        scheduled_height: 600,
        status: "scheduled".to_string(),
        mined_height: None,
    }];
    let signed_children = vec![MigrationTimingSignedChild {
        part_index: 1,
        target_height: 101,
    }];

    let projection = calculate_migration_timing_projection(
        &schedule,
        &pending,
        &signed_children,
        Some(550),
        2,
        3,
    )
    .unwrap();

    assert_eq!(projection.next_action_height, Some(550));
    assert_eq!(projection.next_action_part_index, Some(1));
    assert_eq!(projection.next_proof_window_height, Some(550));
    assert_eq!(projection.next_proof_window_part_indices, vec![1]);
    assert_eq!(projection.estimated_completion_height, Some(791));
    assert_eq!(
        projection.projected_signed_parts,
        vec![MigrationTimingProjectedSignedPart {
            part_index: 1,
            schedule_start_height: 500,
            scheduled_height: 788,
        }]
    );
}

#[test]
fn timing_projection_ignores_retained_signed_children_after_promotion() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    let schedule_json = serde_json::to_string(&vec![
        MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 100,
            block_offset: 144,
        },
        MigrationScheduleEntry {
            part_index: Some(1),
            value_zatoshi: 200,
            block_offset: 288,
        },
    ])
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json,
              schedule_json, proof_retry_height)
             VALUES ('run-timing', 'account-1', 'test', 'db', ?1, 1, 1,
                     '[100,200]', ?2, 550)"
        ),
        params![PHASE_BROADCAST_SCHEDULED, schedule_json],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PENDING_TXS_TABLE}
             (run_id, txid_hex, part_index, encrypted_raw_tx, target_height,
              expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
              selected_note_output_index, selected_note_value, scheduled_at_ms,
              schedule_start_height, scheduled_height, status, metadata_json)
             VALUES ('run-timing', ?1, 0, 'raw', 101, 900, 99, 1, ?2,
                     0, 100, 1, 500, 600, 'scheduled', '{{}}')"
        ),
        params!["11".repeat(32), "aa".repeat(32)],
    )
    .unwrap();
    for child_index in [0u32, 1] {
        conn.execute(
            &format!(
                "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_compact_sigs, target_height, expiry_height,
                  value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
                 VALUES ('run-timing', ?1, ?2, 'base', 'sigs', 101, 900,
                         99, 1, '{{}}', '{{}}')"
            ),
            params![format!("message-{child_index}"), child_index],
        )
        .unwrap();
    }

    let projection = migration_timing_projection_for_run(&conn, "run-timing", 2, 3).unwrap();

    assert_eq!(projection.next_action_height, Some(550));
    assert_eq!(projection.next_action_part_index, Some(1));
    assert_eq!(projection.estimated_completion_height, Some(791));
}

#[test]
fn timing_projection_counts_the_mined_block_as_confirmation_one() {
    let schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100,
        block_offset: 144,
    }];
    let pending = vec![MigrationTimingPendingPart {
        part_index: Some(0),
        target_height: 90,
        schedule_start_height: Some(90),
        scheduled_height: 100,
        status: "confirmed".to_string(),
        mined_height: Some(105),
    }];

    let projection =
        calculate_migration_timing_projection(&schedule, &pending, &[], None, 1, 3).unwrap();

    assert_eq!(projection.estimated_completion_height, Some(107));
}

#[test]
fn timing_projection_waits_for_multi_part_catch_up_reschedule() {
    let schedule = vec![
        MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 100,
            block_offset: 50,
        },
        MigrationScheduleEntry {
            part_index: Some(1),
            value_zatoshi: 200,
            block_offset: 80,
        },
    ];
    let signed_children = vec![MigrationTimingSignedChild {
        part_index: 1,
        target_height: 101,
    }];
    let pending = vec![MigrationTimingPendingPart {
        part_index: Some(0),
        target_height: 101,
        schedule_start_height: Some(100),
        scheduled_height: 150,
        status: "scheduled".to_string(),
        mined_height: None,
    }];

    let projection = calculate_migration_timing_projection(
        &schedule,
        &pending,
        &signed_children,
        Some(200),
        2,
        3,
    )
    .unwrap();

    assert_eq!(projection.next_action_height, Some(150));
    assert_eq!(projection.estimated_completion_height, None);
}

#[test]
fn timing_projection_failure_does_not_block_migration_status() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap().to_string();
    let conn = rusqlite::Connection::open(&db_path).unwrap();
    ensure_schema(&conn).unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json,
              schedule_json, proof_retry_height)
             VALUES ('run-timing-gap', 'account-1', 'test', 'db', ?1, 1, 1,
                     '[100]', '{{', NULL)"
        ),
        params![PHASE_BROADCAST_SCHEDULED],
    )
    .unwrap();
    insert_test_stage(
        &conn,
        "run-timing-gap",
        &"33".repeat(32),
        DenominationStageStatus::Confirmed,
        Some(100),
    );
    conn.execute(
        &format!(
            "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
             (run_id, message_id, child_index, encrypted_base_pczt,
              encrypted_compact_sigs, target_height, expiry_height,
              value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
             VALUES ('run-timing-gap', 'message-0', 0, 'base', 'sigs', 101,
                     900, 99, 1, ?1, '{{}}')"
        ),
        params![serde_json::to_string(&PreparedOrchardNoteRef {
            txid_hex: "11".repeat(32),
            output_index: 0,
            value_zatoshi: 100,
            note_version: 2,
            nullifier_hex: Some("22".repeat(32)),
        })
        .unwrap()],
    )
    .unwrap();

    let run = active_run(&conn, "account-1", WalletNetwork::Test)
        .unwrap()
        .unwrap();
    let status = status_for_run(&conn, run, 0).unwrap();

    assert_eq!(status.phase, PHASE_BROADCAST_SCHEDULED);
    assert_eq!(status.next_action_height, None);
    assert_eq!(status.estimated_completion_height, None);
    drop(conn);

    let export = export_scheduled_migration_outbox(
        &db_path,
        "account-1",
        WalletNetwork::Test,
        b"password",
        TEST_SALT_BASE64,
    )
    .unwrap();
    assert!(export.is_none());
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
    assert!(offsets[0] <= ZIP318_TRANSFER_MAX_DELAY_BLOCKS);
    assert!(offsets.windows(2).all(|w| {
        let gap = w[1] - w[0];
        gap <= ZIP318_TRANSFER_MAX_DELAY_BLOCKS
    }));
}

#[test]
fn preparation_schedule_is_planned_across_dependency_layers() {
    assert_eq!(ZIP318_PREPARATION_MEAN_DELAY_BLOCKS, 16);
    assert_eq!(ZIP318_PREPARATION_MAX_DELAY_BLOCKS, 96);

    let mut rng = StdRng::seed_from_u64(0x318);
    let heights = planned_preparation_scheduled_heights(
        WalletNetwork::Main,
        PreparationTimingPolicy::Zip318Spaced,
        MigrationTimingPolicy::Standard,
        3_455_990,
        &[0, 0, 1, 1],
        &mut rng,
    )
    .unwrap();

    assert_eq!(heights.len(), 4);
    let root_end = heights[..2].iter().copied().max().unwrap();
    let descendant_start = heights[2..].iter().copied().min().unwrap();
    assert!(root_end >= 3_455_989);
    assert!(descendant_start >= root_end + denomination_confirmations_required());
    assert!(heights.iter().all(|height| {
        zip318_canonical_migration_expiry_height(*height)
            .is_ok_and(|expiry_height| expiry_height > *height)
    }));
}

#[test]
fn immediate_preparation_schedule_still_serializes_dependency_layers() {
    let mut rng = StdRng::seed_from_u64(0x318);
    let heights = planned_preparation_scheduled_heights(
        WalletNetwork::Main,
        PreparationTimingPolicy::Immediate,
        MigrationTimingPolicy::Standard,
        101,
        &[0, 0, 1],
        &mut rng,
    )
    .unwrap();

    assert_eq!(heights, vec![100, 100, 103]);
}

#[test]
fn fast_testnet_uses_accelerated_preparation_delays() {
    assert_eq!(
        preparation_schedule_parameters(WalletNetwork::Regtest, MigrationTimingPolicy::FastTestnet,),
        (
            FAST_TESTNET_PREPARATION_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_PREPARATION_MAX_DELAY_BLOCKS,
        ),
    );

    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    insert_preparation_policy_test_run(
        &conn,
        "fast-testnet-preparation",
        PreparationTimingPolicy::Zip318Spaced,
        1,
        101,
    );
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE} SET timing_policy = 'fast_testnet'
             WHERE run_id = 'fast-testnet-preparation'"
        ),
        [],
    )
    .unwrap();
    assert_eq!(
        timing_policy_for_run_with_conn(&conn, "fast-testnet-preparation", WalletNetwork::Regtest,)
            .unwrap(),
        MigrationTimingPolicy::FastTestnet,
    );
    let mut rng = StdRng::seed_from_u64(0x318);
    for _ in 0..32 {
        let scheduled_height = planned_preparation_scheduled_heights(
            WalletNetwork::Test,
            PreparationTimingPolicy::Zip318Spaced,
            MigrationTimingPolicy::FastTestnet,
            201,
            &[0],
            &mut rng,
        )
        .unwrap()[0];
        assert!((200..=200 + FAST_TESTNET_PREPARATION_MAX_DELAY_BLOCKS).contains(&scheduled_height));
    }
}

#[test]
fn preparation_delay_rounds_to_nearest_block() {
    let mut rng = StdRng::seed_from_u64(0x318);
    let delays = (0..256)
        .map(|_| {
            preparation_delay_with_rng(
                WalletNetwork::Main,
                MigrationTimingPolicy::Standard,
                &mut rng,
            )
        })
        .collect::<Vec<_>>();

    assert!(delays.contains(&0));
    assert!(delays
        .iter()
        .all(|delay| *delay <= ZIP318_PREPARATION_MAX_DELAY_BLOCKS));
}

#[test]
fn late_preparation_broadcast_rerandomizes_remaining_effective_heights() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    insert_preparation_policy_test_run(
        &conn,
        "preparation-catch-up",
        PreparationTimingPolicy::Zip318Spaced,
        4,
        101,
    );
    conn.execute(
        &format!(
            "UPDATE {STAGES_TABLE}
             SET scheduled_height = CASE stage_index
                     WHEN 0 THEN 100
                     WHEN 1 THEN 150
                     WHEN 2 THEN 250
                     ELSE 1000
                 END,
                 broadcast_not_before_height = CASE stage_index
                     WHEN 2 THEN 275
                     ELSE NULL
                 END,
                 expiry_height = 3490560
             WHERE run_id = 'preparation-catch-up'"
        ),
        [],
    )
    .unwrap();
    let before = preparation_catch_up_test_rows(&conn, "preparation-catch-up");
    let tx = conn.unchecked_transaction().unwrap();
    mark_denomination_stage_broadcasted(&tx, "preparation-catch-up", &format!("{:064x}", 1))
        .unwrap();
    let mut rng = StdRng::seed_from_u64(0x318);
    assert_eq!(
        rerandomize_remaining_preparation_broadcast_heights(
            &tx,
            "preparation-catch-up",
            WalletNetwork::Test,
            200,
            &mut rng,
        )
        .unwrap(),
        3,
    );
    tx.commit().unwrap();
    let after = preparation_catch_up_test_rows(&conn, "preparation-catch-up");

    assert_eq!(
        before
            .iter()
            .map(|row| (row.0, row.1, row.3))
            .collect::<Vec<_>>(),
        after
            .iter()
            .map(|row| (row.0, row.1, row.3))
            .collect::<Vec<_>>(),
        "the expiry-derived schedule must stay immutable",
    );
    assert!(after[0].2.is_none(), "the broadcasted stage is unchanged");
    assert!(after[1..].iter().all(|row| row.2.is_some()));

    let effective_heights = after[1..]
        .iter()
        .map(|row| row.1.max(row.2.unwrap_or(0)))
        .collect::<Vec<_>>();
    assert!(effective_heights[0] >= 200);
    assert!(effective_heights[0] <= 200 + ZIP318_PREPARATION_MAX_DELAY_BLOCKS);
    assert!(effective_heights[1] - effective_heights[0] <= ZIP318_PREPARATION_MAX_DELAY_BLOCKS);
    assert_eq!(effective_heights[2], 1000);
    assert!(effective_heights.windows(2).all(|pair| pair[0] <= pair[1]));
    for (before, after) in before[1..].iter().zip(&after[1..]) {
        let old_effective = before.1.max(before.2.unwrap_or(0));
        let new_effective = after.1.max(after.2.unwrap_or(0));
        assert!(new_effective >= old_effective);
    }
    let displayed_heights = migration_preparation_transactions_for_run(
        &conn,
        "preparation-catch-up",
        &[],
        denomination_confirmations_required(),
        0,
    )
    .unwrap()
    .into_iter()
    .skip(1)
    .map(|stage| stage.scheduled_height.unwrap())
    .collect::<Vec<_>>();
    assert_eq!(displayed_heights, effective_heights);
}

#[test]
fn recovered_pending_preparation_stage_uses_chain_tip_and_rerandomizes_once() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let conn = rusqlite::Connection::open(db_path).unwrap();
    ensure_schema(&conn).unwrap();
    let run_id = "recovered-preparation-catch-up";
    let scanned_inclusion_height = 200;
    let chain_tip_height = 500;
    insert_recovered_pending_preparation_test_run(
        &conn,
        run_id,
        [100, 150, 175],
        scanned_inclusion_height,
    );
    let before = preparation_catch_up_test_rows(&conn, run_id);
    drop(conn);

    let mut rng = StdRng::seed_from_u64(0x318);
    reconcile_denomination_stage_chain_state_with_rng(
        db_path,
        run_id,
        Some(chain_tip_height),
        &mut rng,
    )
    .unwrap();

    let conn = rusqlite::Connection::open(db_path).unwrap();
    let statuses = conn
        .prepare(&format!(
            "SELECT status FROM {STAGES_TABLE}
             WHERE run_id = ?1 ORDER BY stage_index"
        ))
        .unwrap()
        .query_map(params![run_id], |row| row.get::<_, String>(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(statuses, vec!["confirmed", "pending", "pending"]);
    let after = preparation_catch_up_test_rows(&conn, run_id);
    assert_eq!(
        before
            .iter()
            .map(|row| (row.0, row.1, row.3))
            .collect::<Vec<_>>(),
        after
            .iter()
            .map(|row| (row.0, row.1, row.3))
            .collect::<Vec<_>>(),
        "recovery must preserve every signed schedule and expiry",
    );
    assert!(after[0].2.is_none());
    let recovered_heights = after[1..]
        .iter()
        .map(|row| row.1.max(row.2.unwrap_or(0)))
        .collect::<Vec<_>>();
    assert!(scanned_inclusion_height < chain_tip_height);
    assert!(recovered_heights[0] >= chain_tip_height);
    assert!(recovered_heights.windows(2).all(|pair| pair[0] <= pair[1]));
    drop(conn);

    let first_recovery = after.iter().map(|row| row.2).collect::<Vec<Option<u32>>>();
    let mut second_rng = StdRng::seed_from_u64(0x123);
    reconcile_denomination_stage_chain_state_with_rng(db_path, run_id, Some(600), &mut second_rng)
        .unwrap();
    let conn = rusqlite::Connection::open(db_path).unwrap();
    assert_eq!(
        preparation_catch_up_test_rows(&conn, run_id)
            .iter()
            .map(|row| row.2)
            .collect::<Vec<Option<u32>>>(),
        first_recovery,
        "a confirmed recovery must not re-randomize peers again",
    );
}

#[test]
fn recovered_pending_preparation_stage_conservatively_delays_near_future_peers() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let conn = rusqlite::Connection::open(db_path).unwrap();
    ensure_schema(&conn).unwrap();
    let run_id = "recovered-preparation-on-time";
    insert_recovered_pending_preparation_test_run(&conn, run_id, [100, 251, 252], 200);
    drop(conn);

    let mut rng = StdRng::seed_from_u64(0x318);
    reconcile_denomination_stage_chain_state_with_rng(db_path, run_id, Some(250), &mut rng)
        .unwrap();

    let conn = rusqlite::Connection::open(db_path).unwrap();
    let rows = preparation_catch_up_test_rows(&conn, run_id);
    assert!(rows[0].2.is_none());
    assert!(rows[1..].iter().all(|row| row.2.is_some()));
    assert!(rows[1].1.max(rows[1].2.unwrap_or(0)) > rows[1].1);
    for row in &rows[1..] {
        assert!(row.1.max(row.2.unwrap_or(0)) >= row.1);
    }
    let status: String = conn
        .query_row(
            &format!(
                "SELECT status FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND stage_index = 0"
            ),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(status, "confirmed");
}

#[test]
fn recovered_pending_preparation_stage_rolls_back_if_rescheduling_fails() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let conn = rusqlite::Connection::open(db_path).unwrap();
    ensure_schema(&conn).unwrap();
    let run_id = "recovered-preparation-rollback";
    insert_recovered_pending_preparation_test_run(&conn, run_id, [100, 150, 175], 200);
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE} SET timing_policy = 'invalid'
             WHERE run_id = ?1"
        ),
        params![run_id],
    )
    .unwrap();
    drop(conn);

    let mut rng = StdRng::seed_from_u64(0x318);
    let error =
        reconcile_denomination_stage_chain_state_with_rng(db_path, run_id, Some(250), &mut rng)
            .unwrap_err();
    assert!(error.contains("Unsupported migration timing policy"));

    let conn = rusqlite::Connection::open(db_path).unwrap();
    let rows = preparation_catch_up_test_rows(&conn, run_id);
    assert!(rows.iter().all(|row| row.2.is_none()));
    let status: String = conn
        .query_row(
            &format!(
                "SELECT status FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND stage_index = 0"
            ),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(status, "pending");
}

#[test]
fn recovered_pending_immediate_stage_does_not_require_catch_up_context() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_str().unwrap();
    let conn = rusqlite::Connection::open(db_path).unwrap();
    ensure_schema(&conn).unwrap();
    let run_id = "recovered-immediate-preparation";
    insert_recovered_pending_preparation_test_run(&conn, run_id, [100, 150, 175], 200);
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE} SET preparation_timing_policy = 'immediate'
             WHERE run_id = ?1"
        ),
        params![run_id],
    )
    .unwrap();
    drop(conn);

    reconcile_denomination_stage_chain_state(db_path, run_id).unwrap();

    let conn = rusqlite::Connection::open(db_path).unwrap();
    let rows = preparation_catch_up_test_rows(&conn, run_id);
    assert!(rows.iter().all(|row| row.2.is_none()));
    let status: String = conn
        .query_row(
            &format!(
                "SELECT status FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND stage_index = 0"
            ),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(status, "confirmed");
}

#[test]
fn immediate_preparation_does_not_create_catch_up_schedule() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    insert_preparation_policy_test_run(
        &conn,
        "immediate-preparation-catch-up",
        PreparationTimingPolicy::Immediate,
        2,
        101,
    );
    let tx = conn.unchecked_transaction().unwrap();
    let mut rng = StdRng::seed_from_u64(0x318);
    assert_eq!(
        rerandomize_remaining_preparation_broadcast_heights(
            &tx,
            "immediate-preparation-catch-up",
            WalletNetwork::Test,
            200,
            &mut rng,
        )
        .unwrap(),
        0,
    );
    tx.commit().unwrap();
    assert!(
        preparation_catch_up_test_rows(&conn, "immediate-preparation-catch-up")
            .iter()
            .all(|row| row.2.is_none())
    );
}

#[test]
fn legacy_preparation_policy_remains_immediate() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    conn.execute_batch(&format!(
        "CREATE TABLE {RUNS_TABLE} (
            run_id TEXT PRIMARY KEY,
            account_uuid TEXT NOT NULL,
            network TEXT NOT NULL,
            db_fingerprint TEXT NOT NULL,
            phase TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            target_values_json TEXT NOT NULL DEFAULT '[]'
        );
        INSERT INTO {RUNS_TABLE}
            (run_id, account_uuid, network, db_fingerprint, phase,
             created_at_ms, updated_at_ms)
        VALUES ('legacy', 'account-1', 'test', 'db', 'preparing', 1, 1);"
    ))
    .unwrap();
    ensure_schema(&conn).unwrap();

    assert_eq!(
        preparation_timing_policy_for_run_with_conn(&conn, "legacy").unwrap(),
        PreparationTimingPolicy::Immediate
    );
}

#[test]
fn planned_schedule_delays_every_transfer() {
    let values = (1..=32).collect::<Vec<_>>();
    let mut rng = StdRng::seed_from_u64(0x318);
    let schedule = planned_transfer_schedule(values.iter().copied(), WalletNetwork::Test, &mut rng);

    assert_eq!(schedule.len(), values.len());
    assert_ne!(schedule[0].block_offset, 0);
    assert!(schedule[0].block_offset <= ZIP318_TRANSFER_MAX_DELAY_BLOCKS);
    assert!(schedule.windows(2).all(|entries| {
        let gap = entries[1].block_offset - entries[0].block_offset;
        gap <= ZIP318_TRANSFER_MAX_DELAY_BLOCKS
    }));
    validate_schedule(&schedule, &values, WalletNetwork::Test).unwrap();
}

#[test]
fn schedule_validation_accepts_zero_delay_gaps() {
    let schedule = vec![
        MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 100,
            block_offset: 0,
        },
        MigrationScheduleEntry {
            part_index: Some(1),
            value_zatoshi: 200,
            block_offset: 0,
        },
    ];

    validate_schedule(&schedule, &[100, 200], WalletNetwork::Test).unwrap();
}

#[test]
fn schedule_validation_keeps_legacy_positive_first_offsets_compatible() {
    let schedule = vec![
        MigrationScheduleEntry {
            part_index: Some(0),
            value_zatoshi: 100,
            block_offset: 144,
        },
        MigrationScheduleEntry {
            part_index: Some(1),
            value_zatoshi: 200,
            block_offset: 288,
        },
    ];

    validate_schedule(&schedule, &[100, 200], WalletNetwork::Test).unwrap();
}

#[test]
fn configured_schedule_uses_shortened_mean_without_changing_regtest() {
    assert_eq!(NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS, 66);
    assert_eq!(
        schedule_parameters(WalletNetwork::Regtest),
        (1, REGTEST_TRANSFER_MAX_DELAY_BLOCKS)
    );
    assert_eq!(
        schedule_parameters(WalletNetwork::Test),
        (
            NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS
        )
    );
    assert_eq!(
        schedule_parameters(WalletNetwork::Main),
        (
            NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS
        )
    );
}

#[test]
fn legacy_and_ninety_minute_policies_keep_distinct_parameters() {
    assert_eq!(
        schedule_parameters_with_policy(WalletNetwork::Main, MigrationTimingPolicy::Standard),
        (
            ZIP318_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS
        )
    );
    assert_eq!(
        schedule_parameters_with_policy(
            WalletNetwork::Main,
            MigrationTimingPolicy::Standard90Minutes,
        ),
        (
            NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS
        )
    );
    assert_eq!(
        schedule_parameters_with_policy(
            WalletNetwork::Main,
            MigrationTimingPolicy::Standard90MinutesLatestAnchor,
        ),
        (
            NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
            ZIP318_TRANSFER_MAX_DELAY_BLOCKS
        )
    );
}

#[test]
fn mainnet_run_reads_its_persisted_timing_policy() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    for (run_id, timing_policy) in [("legacy", "standard"), ("shorter", "standard_90m")] {
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json, timing_policy)
                 VALUES (?1, ?1, 'main', 'wallet.db', ?2, 1, 1, '[100]', ?3)"
            ),
            params![run_id, PHASE_READY_TO_MIGRATE, timing_policy],
        )
        .unwrap();
    }

    assert_eq!(
        timing_policy_for_run_with_conn(&conn, "legacy", WalletNetwork::Main).unwrap(),
        MigrationTimingPolicy::Standard,
    );
    assert_eq!(
        timing_policy_for_run_with_conn(&conn, "shorter", WalletNetwork::Main).unwrap(),
        MigrationTimingPolicy::Standard90Minutes,
    );
}

#[test]
fn new_mainnet_draft_persists_ninety_minute_latest_anchor_policy() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let schedule = [MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100,
        block_offset: NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
    }];

    let run_id = create_or_resume_private_migration_draft(
        &db_path,
        "account-1",
        WalletNetwork::Main,
        &[100],
        &schedule,
        PreparationTimingPolicy::Zip318Spaced,
    )
    .unwrap();

    assert_eq!(
        timing_policy_for_run(&db_path, &run_id, WalletNetwork::Main).unwrap(),
        MigrationTimingPolicy::Standard90MinutesLatestAnchor,
    );
}

#[test]
fn shortened_schedule_samples_the_truncated_distribution() {
    let count = 20_000;
    let mut rng = StdRng::seed_from_u64(0x90);
    let offsets = random_schedule_block_offsets_with_rng(
        count,
        NINETY_MINUTE_TRANSFER_MEAN_DELAY_BLOCKS,
        ZIP318_TRANSFER_MAX_DELAY_BLOCKS,
        &mut rng,
    );
    let total_delay = u64::from(*offsets.last().unwrap());

    // Redrawing samples above the 12-hour cap makes the realized mean
    // slightly lower than the untruncated 66-block parameter.
    assert!(total_delay > count as u64 * 64);
    assert!(total_delay < count as u64 * 68);
}

#[test]
fn fast_testnet_uses_accelerated_schedule_and_anchor_timing() {
    assert_eq!(
        schedule_parameters_with_policy(WalletNetwork::Regtest, MigrationTimingPolicy::FastTestnet,),
        (
            FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS,
        ),
    );
    assert_eq!(
        schedule_parameters_with_policy(WalletNetwork::Test, MigrationTimingPolicy::FastTestnet,),
        (
            FAST_TESTNET_TRANSFER_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS,
        )
    );
    assert_eq!(
        zip318_anchor_candidate_boundaries_with_policy(
            WalletNetwork::Test,
            MigrationTimingPolicy::FastTestnet,
            540,
            501,
            500,
        )[0],
        528
    );
    assert_eq!(
        proof_ready_height_for_note_mined_height(
            WalletNetwork::Test,
            MigrationTimingPolicy::FastTestnet,
            501,
        )
        .unwrap(),
        518
    );
    assert_eq!(
        schedule_parameters_with_policy(WalletNetwork::Main, MigrationTimingPolicy::FastTestnet,),
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
fn fast_testnet_adoption_preserves_signed_preparation_schedule() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    insert_preparation_policy_test_run(
        &conn,
        "run-fast-preparation",
        PreparationTimingPolicy::Zip318Spaced,
        3,
        101,
    );
    conn.execute(
        &format!(
            "UPDATE {STAGES_TABLE}
             SET scheduled_height = CASE stage_index
                 WHEN 0 THEN 100 WHEN 1 THEN 150 ELSE 200 END,
                 expiry_height = 69120,
                 status = CASE stage_index
                     WHEN 0 THEN 'broadcasted' ELSE 'pending' END
             WHERE run_id = 'run-fast-preparation'"
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

    let policy: String = conn
        .query_row(
            &format!(
                "SELECT timing_policy FROM {RUNS_TABLE}
                 WHERE run_id = 'run-fast-preparation'"
            ),
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(policy, "fast_testnet");
    let mut stmt = conn
        .prepare(&format!(
            "SELECT scheduled_height FROM {STAGES_TABLE}
             WHERE run_id = 'run-fast-preparation' AND status = 'pending'
             ORDER BY scheduled_height ASC, stage_index ASC"
        ))
        .unwrap();
    let heights = stmt
        .query_map([], |row| row.get::<_, u32>(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(heights.len(), 2);
    assert_eq!(heights, vec![150, 200]);
}

#[test]
fn configured_latest_anchor_policy_does_not_retime_existing_runs() {
    let conn = rusqlite::Connection::open_in_memory().unwrap();
    ensure_schema(&conn).unwrap();
    for (account_uuid, run_id, timing_policy, retry_height) in [
        ("account-standard", "run-standard", "standard", 290),
        (
            "account-standard-90m",
            "run-standard-90m",
            "standard_90m",
            434,
        ),
    ] {
        conn.execute(
            &format!(
                "INSERT INTO {RUNS_TABLE}
                 (run_id, account_uuid, network, db_fingerprint, phase,
                  created_at_ms, updated_at_ms, target_values_json,
                  timing_policy, proof_retry_height)
                 VALUES (?1, ?2, 'main', 'wallet.db', ?3, 1, 1, '[100]', ?4, ?5)"
            ),
            params![
                run_id,
                account_uuid,
                PHASE_READY_TO_MIGRATE,
                timing_policy,
                retry_height,
            ],
        )
        .unwrap();

        adopt_configured_timing_policy_for_active_run(&conn, account_uuid, WalletNetwork::Main)
            .unwrap();

        let persisted: (String, u32) = conn
            .query_row(
                &format!(
                    "SELECT timing_policy, proof_retry_height
                     FROM {RUNS_TABLE}
                     WHERE run_id = ?1"
                ),
                params![run_id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(persisted, (timing_policy.to_string(), retry_height));
    }
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
                expiry_height: 69_120,
                scheduled_height: 500
                    + schedule
                        .iter()
                        .find(|entry| entry.part_index == Some(index as u32))
                        .unwrap()
                        .block_offset,
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
    assert!(remaining.iter().all(|entry| entry.scheduled_height >= 503));
}

#[test]
fn regtest_fast_policy_survives_pending_transaction_materialization() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    ensure_schema(&conn).unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, timing_policy)
             VALUES ('run-fast', 'account-1', 'regtest', ?1, ?2, 1, 1,
                     '[100]', 'fast_testnet')"
        ),
        params![db_path, PHASE_READY_TO_MIGRATE],
    )
    .unwrap();
    drop(conn);

    let schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100,
        block_offset: 12,
    }];
    set_run_approved_schedule(
        &db_path,
        "run-fast",
        WalletNetwork::Regtest,
        &schedule,
        &[100],
    )
    .unwrap();
    let selected_note = PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 110,
        note_version: 2,
        nullifier_hex: None,
    };
    insert_pending_txs(
        &db_path,
        "run-fast",
        vec![PendingMigrationTxInsert {
            part_index: 0,
            txid_hex: "22".repeat(32),
            raw_tx: vec![0xaa],
            target_height: 501,
            anchor_boundary_height: None,
            expiry_height: 69_120,
            scheduled_height: 512,
            value_zatoshi: 100,
            fee_zatoshi: 10,
            selected_note: selected_note.clone(),
            metadata: PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: "account-1".to_string(),
                selected_note,
            },
        }],
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();
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
                expiry_height: 69_120,
                scheduled_height: 500
                    + schedule
                        .iter()
                        .find(|entry| entry.part_index == Some(part_index))
                        .unwrap()
                        .block_offset,
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
fn last_broadcast_keeps_run_materializing_while_signed_child_remains() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    ensure_schema(&conn).unwrap();
    let run_id = "run-partially-materialized";
    let pending_note_txid = "11".repeat(32);
    let remaining_note = PreparedOrchardNoteRef {
        txid_hex: "22".repeat(32),
        output_index: 1,
        value_zatoshi: 200,
        note_version: 2,
        nullifier_hex: Some("33".repeat(32)),
    };
    let remaining_note_json = serde_json::to_string(&remaining_note).unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json)
             VALUES (?1, 'account-1', 'test', ?2, ?3, 1, 1, '[100,200]')"
        ),
        params![run_id, db_path, PHASE_BROADCAST_SCHEDULED],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {PENDING_TXS_TABLE}
             (run_id, txid_hex, encrypted_raw_tx, target_height,
              expiry_height, value_zatoshi, fee_zatoshi, selected_note_txid,
              selected_note_output_index, selected_note_value,
              scheduled_at_ms, scheduled_height, status, metadata_json)
             VALUES (?1, ?2, 'raw', 10, 20, 100, 10, ?3, 0, 110,
                     1, 10, 'scheduled', '{{}}')"
        ),
        params![run_id, "44".repeat(32), pending_note_txid],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
             (run_id, message_id, child_index, encrypted_base_pczt,
              encrypted_compact_sigs, target_height, expiry_height,
              value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
             VALUES (?1, 'remaining-child', 1, 'base', 'sigs', 20, 30,
                     200, 10, ?2, '{{}}')"
        ),
        params![run_id, remaining_note_json],
    )
    .unwrap();
    drop(conn);

    assert_eq!(due_scheduled_pending_count(&db_path, run_id, 9).unwrap(), 0);
    assert_eq!(
        due_scheduled_pending_count(&db_path, run_id, 10).unwrap(),
        1
    );
    mark_pending_broadcasted(&db_path, run_id, &"44".repeat(32)).unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
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
fn durable_anchor_check_matches_the_pinned_librustzcash_interval() {
    // librustzcash retains interval-aligned checkpoints at or after anchor
    // retention activation. Releasing one of those would drop a witness anchor
    // the wallet still depends on, so migration must recognise every one of
    // them, not only the ones that happen to be multiples of a wider interval.
    let floor = Some(BlockHeight::from_u32(1_000));

    assert!(is_wallet_durable_anchor(1_008, floor));
    assert!(is_wallet_durable_anchor(1_152, floor));
    assert!(!is_wallet_durable_anchor(1_100, floor));

    // Below activation librustzcash retains nothing, so migration owns the
    // checkpoint outright and may release it.
    assert!(!is_wallet_durable_anchor(864, floor));
    assert!(!is_wallet_durable_anchor(144, None));
}

#[test]
fn approved_schedule_keeps_unpromoted_anchor_retention_candidates() {
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
             VALUES ('run-1', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100,200]')"
        ),
        params![db_path, PHASE_READY_TO_MIGRATE],
    )
    .unwrap();
    for (part_index, target_height) in [(0, 501), (1, 999)] {
        let selected_note = PreparedOrchardNoteRef {
            txid_hex: format!("{:064x}", part_index + 10),
            output_index: 0,
            value_zatoshi: if part_index == 0 { 110 } else { 210 },
            note_version: 2,
            nullifier_hex: None,
        };
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version,
                  nullifier_hex, lock_state)
                 VALUES ('run-1', ?1, 0, ?2, 2, NULL, 'locked')"
            ),
            params![selected_note.txid_hex, selected_note.value_zatoshi],
        )
        .unwrap();
        conn.execute(
            &format!(
                "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
                 (run_id, message_id, child_index, encrypted_base_pczt,
                  encrypted_compact_sigs, target_height, expiry_height,
                  scheduled_height, value_zatoshi, fee_zatoshi,
                  selected_note_json, metadata_json)
                 VALUES ('run-1', ?1, ?2, 'base', 'sigs', ?3, ?4,
                         ?5, ?6, 10, ?7, '{{}}')"
            ),
            params![
                format!("child-{part_index}"),
                part_index,
                target_height,
                zip318_canonical_migration_expiry_height(if part_index == 0 { 502 } else { 501 })
                    .unwrap(),
                if part_index == 0 { 502 } else { 501 },
                if part_index == 0 { 100 } else { 200 },
                serde_json::to_string(&selected_note).unwrap(),
            ],
        )
        .unwrap();
    }
    drop(conn);

    set_run_approved_schedule(
        &db_path,
        "run-1",
        WalletNetwork::Regtest,
        &[
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
        ],
        &[100, 200],
    )
    .unwrap();

    let pending = |part_index: u32, value_zatoshi: u64, target_height: u32| {
        let selected_note = PreparedOrchardNoteRef {
            txid_hex: format!("{:064x}", part_index + 10),
            output_index: 0,
            value_zatoshi: value_zatoshi + 10,
            note_version: 2,
            nullifier_hex: None,
        };
        PendingMigrationTxInsert {
            part_index,
            txid_hex: format!("{part_index:064x}"),
            raw_tx: vec![part_index as u8],
            target_height,
            anchor_boundary_height: None,
            expiry_height: 69_120,
            scheduled_height: 500 + if part_index == 0 { 2 } else { 1 },
            value_zatoshi,
            fee_zatoshi: 10,
            selected_note: selected_note.clone(),
            metadata: PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: "account-1".to_string(),
                selected_note,
            },
        }
    };

    set_proof_retry_height(&db_path, "run-1", 1_200).unwrap();
    assert_eq!(proof_retry_height(&db_path, "run-1").unwrap(), Some(1_200));
    assert_eq!(
        prepared_anchor_retention_candidates(&db_path, WalletNetwork::Regtest)
            .unwrap()
            .len(),
        2
    );
    let candidates = signed_child_proof_candidates_for_run(&db_path, "run-1").unwrap();
    assert_eq!(candidates.len(), 2);
    promote_signed_child_pczts_to_pending_txs(
        &db_path,
        "run-1",
        vec![pending(0, 100, 501)],
        1_200,
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();
    assert_eq!(proof_retry_height(&db_path, "run-1").unwrap(), Some(1_200));
    let retention_candidates =
        prepared_anchor_retention_candidates(&db_path, WalletNetwork::Regtest).unwrap();
    assert_eq!(
        retention_candidates
            .iter()
            .map(|candidate| candidate.note.txid_hex.as_str())
            .collect::<Vec<_>>(),
        vec![format!("{:064x}", 11)]
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    // PHASE_BROADCASTING is persisted before the first send of a broadcast
    // pass, so an interrupted pass leaves a run there while it still owns
    // unpromoted signed children. Dropping it from retention released their
    // anchors and let the next full-size scan batch prune the checkpoint.
    for recoverable_phase in [PHASE_FAILED_RECOVERABLE, PHASE_PAUSED, PHASE_BROADCASTING] {
        conn.execute(
            &format!("UPDATE {RUNS_TABLE} SET phase = ?1 WHERE run_id = 'run-1'"),
            params![recoverable_phase],
        )
        .unwrap();
        let candidates =
            prepared_anchor_retention_candidates(&db_path, WalletNetwork::Regtest).unwrap();
        assert_eq!(
            candidates
                .iter()
                .map(|candidate| candidate.note.txid_hex.as_str())
                .collect::<Vec<_>>(),
            vec![format!("{:064x}", 11)]
        );
    }
    conn.execute(
        &format!("UPDATE {RUNS_TABLE} SET phase = ?1 WHERE run_id = 'run-1'"),
        params![PHASE_BROADCAST_SCHEDULED],
    )
    .unwrap();
    drop(conn);
    let candidates = signed_child_proof_candidates_for_run(&db_path, "run-1").unwrap();
    assert_eq!(
        candidates,
        vec![SignedChildProofCandidate {
            selected_note: PreparedOrchardNoteRef {
                txid_hex: format!("{:064x}", 11),
                output_index: 0,
                value_zatoshi: 210,
                note_version: 2,
                nullifier_hex: None,
            },
            anchor_boundary_height: None,
        }]
    );
    promote_signed_child_pczts_to_pending_txs(
        &db_path,
        "run-1",
        vec![pending(1, 200, 999)],
        1_400,
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();
    assert_eq!(proof_retry_height(&db_path, "run-1").unwrap(), None);
    assert!(
        prepared_anchor_retention_candidates(&db_path, WalletNetwork::Regtest)
            .unwrap()
            .is_empty()
    );
    assert!(signed_child_proof_candidates_for_run(&db_path, "run-1")
        .unwrap()
        .is_empty());

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let mut stmt = conn
        .prepare(
            "SELECT part_index, schedule_start_height, scheduled_height
             FROM vizor_migration_pending_txs
             ORDER BY scheduled_height",
        )
        .unwrap();
    let stored = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, u32>(0)?,
                row.get::<_, u32>(1)?,
                row.get::<_, u32>(2)?,
            ))
        })
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(stored, vec![(1, 500, 501), (0, 500, 502)]);
}

#[test]
fn paused_unmaterialized_run_retains_all_prepared_notes() {
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
             VALUES ('run-1', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100,200]')"
        ),
        params![db_path, PHASE_PAUSED],
    )
    .unwrap();
    for index in 0..2 {
        conn.execute(
            &format!(
                "INSERT INTO {PREPARED_NOTES_TABLE}
                 (run_id, txid_hex, output_index, value_zatoshi, note_version, lock_state)
                 VALUES ('run-1', ?1, 0, ?2, 2, 'locked')"
            ),
            params![format!("{:064x}", index + 1), 100 + index],
        )
        .unwrap();
    }
    drop(conn);

    assert_eq!(
        prepared_anchor_retention_candidates(&db_path, WalletNetwork::Regtest)
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn migration_anchor_retention_ownership_transfers_and_releases() {
    crate::wallet::network::configure_regtest_nu6_3_activation_height(2).unwrap();
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    ensure_schema(&conn).unwrap();
    drop(conn);

    let durable_height = 144;
    let desired = BTreeSet::from([
        ("run-1".to_string(), 100),
        ("run-1".to_string(), 101),
        ("run-1".to_string(), durable_height),
    ]);
    assert!(stage_migration_anchor_retention_references(
        &db_path,
        WalletNetwork::Regtest,
        &desired,
        &BTreeSet::from([100, durable_height]),
    )
    .unwrap()
    .is_empty());

    let desired = BTreeSet::from([
        ("run-2".to_string(), 101),
        ("run-2".to_string(), durable_height),
    ]);
    let released = stage_migration_anchor_retention_references(
        &db_path,
        WalletNetwork::Regtest,
        &desired,
        &BTreeSet::from([100, 101, durable_height]),
    )
    .unwrap();
    assert_eq!(released, vec![100]);
    finish_migration_anchor_retention_releases(&db_path, WalletNetwork::Regtest, &released)
        .unwrap();

    let released = stage_migration_anchor_retention_references(
        &db_path,
        WalletNetwork::Regtest,
        &BTreeSet::new(),
        &BTreeSet::from([101, durable_height]),
    )
    .unwrap();
    assert_eq!(released, vec![101]);
    assert!(migration_anchor_retention_references_exist(&db_path, WalletNetwork::Regtest).unwrap());

    finish_migration_anchor_retention_releases(&db_path, WalletNetwork::Regtest, &released)
        .unwrap();
    assert!(
        !migration_anchor_retention_references_exist(&db_path, WalletNetwork::Regtest).unwrap()
    );
}

#[test]
fn legacy_equal_value_schedule_maps_incremental_parts_by_rank() {
    let schedule = [
        MigrationScheduleEntry {
            part_index: None,
            value_zatoshi: 100,
            block_offset: 1,
        },
        MigrationScheduleEntry {
            part_index: None,
            value_zatoshi: 100,
            block_offset: 2,
        },
    ];
    let pending = |part_index| PendingMigrationTxInsert {
        part_index,
        txid_hex: String::new(),
        raw_tx: vec![],
        target_height: 1,
        anchor_boundary_height: None,
        expiry_height: 69_120,
        scheduled_height: part_index + 1,
        value_zatoshi: 100,
        fee_zatoshi: 0,
        selected_note: PreparedOrchardNoteRef {
            txid_hex: String::new(),
            output_index: 0,
            value_zatoshi: 100,
            note_version: 2,
            nullifier_hex: None,
        },
        metadata: PendingMigrationTxMetadata {
            tx_kind: "migration".to_string(),
            funding_account_uuid: String::new(),
            selected_note: PreparedOrchardNoteRef {
                txid_hex: String::new(),
                output_index: 0,
                value_zatoshi: 100,
                note_version: 2,
                nullifier_hex: None,
            },
        },
    };

    assert_eq!(
        schedule_entry_for_pending(&schedule, &[100, 100], &pending(0))
            .unwrap()
            .block_offset,
        1
    );
    assert_eq!(
        schedule_entry_for_pending(&schedule, &[100, 100], &pending(1))
            .unwrap()
            .block_offset,
        2
    );
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
              created_at_ms, updated_at_ms, target_values_json, schedule_json,
              signed_schedule_origin_height)
             VALUES ('expired-run', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100]',
                     '[{{\"part_index\":0,\"value_zatoshi\":100,\"block_offset\":1}}]',
                     90)"
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
                expiry_height: 69_120,
                scheduled_height: 101,
                value_zatoshi: 100,
                fee_zatoshi: 10,
                selected_note: selected_note.clone(),
                metadata,
            },
        }],
        vec![SignedMigrationPcztInsert {
            message_id: "replacement-child".to_string(),
            child_index: 0,
            base_pczt: vec![4, 5, 6],
            sigs: Vec::new(),
            target_height: 101,
            anchor_boundary_height: Some(90),
            expiry_height: 69_120,
            scheduled_height: 101,
            value_zatoshi: 100,
            fee_zatoshi: 10,
            selected_note: selected_note.clone(),
            metadata: PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: "account-1".to_string(),
                selected_note: selected_note.clone(),
            },
        }],
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
    let (replacement_part_index, replacement_original_scheduled_height): (u32, Option<u32>) =
        open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT)
            .unwrap()
            .query_row(
                &format!(
                    "SELECT part_index, original_scheduled_height
                     FROM {PENDING_TXS_TABLE}
                     WHERE run_id = 'expired-run'"
                ),
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
    assert_eq!(replacement_part_index, 0);
    assert_eq!(replacement_original_scheduled_height, Some(91));
    let (signed_origin, replacement_scheduled_height): (u32, u32) =
        open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT)
            .unwrap()
            .query_row(
                &format!(
                    "SELECT r.signed_schedule_origin_height, c.scheduled_height
                     FROM {RUNS_TABLE} r
                     JOIN {SIGNED_CHILD_PCZTS_TABLE} c ON c.run_id = r.run_id
                     WHERE r.run_id = 'expired-run'"
                ),
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
    assert_eq!(signed_origin, 90);
    assert_eq!(replacement_scheduled_height, 101);

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET status = 'needs_resign',
                 original_scheduled_height = NULL,
                 expiry_height = 1
             WHERE run_id = 'expired-run'"
        ),
        [],
    )
    .unwrap();
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET signed_schedule_origin_height = NULL,
                 target_values_json = 'unrecoverable legacy metadata'
             WHERE run_id = 'expired-run'"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    replace_resigned_pending_parts(
        &db_path,
        "expired-run",
        WalletNetwork::Regtest,
        vec![PendingMigrationTxReplacement {
            old_txid_hex: "33".repeat(32),
            replacement: PendingMigrationTxInsert {
                part_index: 0,
                txid_hex: "55".repeat(32),
                raw_tx: vec![7, 8, 9],
                target_height: 102,
                anchor_boundary_height: Some(90),
                expiry_height: zip318_canonical_migration_expiry_height(102).unwrap(),
                scheduled_height: 102,
                value_zatoshi: 100,
                fee_zatoshi: 10,
                selected_note: selected_note.clone(),
                metadata: PendingMigrationTxMetadata {
                    tx_kind: "migration".to_string(),
                    funding_account_uuid: "account-1".to_string(),
                    selected_note: selected_note.clone(),
                },
            },
        }],
        Vec::new(),
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();

    let unknown_original_after_replacement =
        open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT)
            .unwrap()
            .query_row(
                &format!(
                    "SELECT original_scheduled_height
                     FROM {PENDING_TXS_TABLE}
                     WHERE run_id = 'expired-run'"
                ),
                [],
                |row| row.get::<_, Option<u32>>(0),
            )
            .unwrap();
    assert_eq!(unknown_original_after_replacement, None);

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET signed_schedule_origin_height = 90,
                 target_values_json = '[100]'
             WHERE run_id = 'expired-run'"
        ),
        [],
    )
    .unwrap();
    conn.execute(
        &format!("DELETE FROM {PENDING_TXS_TABLE} WHERE run_id = 'expired-run'"),
        [],
    )
    .unwrap();
    drop(conn);
    insert_pending_txs(
        &db_path,
        "expired-run",
        vec![PendingMigrationTxInsert {
            part_index: 0,
            txid_hex: "44".repeat(32),
            raw_tx: vec![7, 8, 9],
            target_height: 101,
            anchor_boundary_height: Some(90),
            expiry_height: 69_120,
            scheduled_height: 101,
            value_zatoshi: 100,
            fee_zatoshi: 10,
            selected_note: selected_note.clone(),
            metadata: PendingMigrationTxMetadata {
                tx_kind: "migration".to_string(),
                funding_account_uuid: "account-1".to_string(),
                selected_note: selected_note.clone(),
            },
        }],
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();
    assert_eq!(
        pending_totals_for_run(&db_path, "expired-run")
            .unwrap()
            .txids,
        vec!["44".repeat(32)]
    );
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
fn projection_height_lookup_does_not_treat_wallet_db_errors_as_genesis() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    rusqlite::Connection::open(&db_path).unwrap();

    assert!(migration_projection_scanned_height(
        db_path.to_string_lossy().as_ref(),
        WalletNetwork::Test,
    )
    .is_err(),);
}

#[test]
fn migration_status_treats_sub_minimum_plan_value_as_complete() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();

    let status = migration_status(
        &db_path,
        WalletNetwork::Test,
        "account-1",
        DENOMINATION_SPLIT_STATUS_FEE_ESTIMATE_ZATOSHI
            + MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI
            + ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI
            - 1,
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
        None,
        PreparationTimingPolicy::Immediate,
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();
    mark_run_phase(&db_path, &run_id, PHASE_COMPLETE, None).unwrap();

    let status = migration_status_with_projection_height(
        &db_path,
        WalletNetwork::Test,
        "account-1",
        MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI,
        0,
        ZATOSHIS_PER_ZEC,
        0,
        Some(0),
    )
    .unwrap();

    assert_eq!(status.phase, PHASE_COMPLETE);
    assert_eq!(status.active_run_id, None);
    assert_eq!(status.target_values_zatoshi, vec![ZATOSHIS_PER_ZEC]);
    assert_eq!(status.total_count, 1);
    assert_eq!(status.parts.len(), 1);
    assert_eq!(status.parts[0].value_zatoshi, ZATOSHIS_PER_ZEC);
    assert_eq!(status.parts[0].state, MigrationPartState::Completed);
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
        DENOMINATION_SPLIT_STATUS_FEE_ESTIMATE_ZATOSHI
            + MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI
            + ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI,
        0,
        ZATOSHIS_PER_ZEC,
        0,
    )
    .unwrap();

    assert_eq!(status.phase, PHASE_READY_TO_PREPARE);
}

#[test]
fn migration_status_requires_the_first_split_and_migration_fees() {
    let minimum_input = DENOMINATION_SPLIT_STATUS_FEE_ESTIMATE_ZATOSHI
        + MIGRATION_STATUS_FEE_ESTIMATE_ZATOSHI
        + ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI;

    for orchard_spendable in [0, minimum_input - 1] {
        assert!(!orchard_balance_can_create_migration_output(orchard_spendable).unwrap());
    }
    assert!(orchard_balance_can_create_migration_output(minimum_input).unwrap());
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
fn private_migration_draft_persists_plan_and_finalizes_in_place() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let target_values = vec![100_000_000];
    let approved_schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: target_values[0],
        block_offset: 1,
    }];

    let run_id = create_or_resume_private_migration_draft(
        &db_path,
        "account-1",
        WalletNetwork::Test,
        &target_values,
        &approved_schedule,
        PreparationTimingPolicy::Immediate,
    )
    .unwrap();
    let resumed_run_id = create_or_resume_private_migration_draft(
        &db_path,
        "account-1",
        WalletNetwork::Test,
        &target_values,
        &approved_schedule,
        PreparationTimingPolicy::Immediate,
    )
    .unwrap();
    assert_eq!(resumed_run_id, run_id);

    let conn = rusqlite::Connection::open(&db_path).unwrap();
    let (phase, schedule_json): (String, String) = conn
        .query_row(
            &format!("SELECT phase, schedule_json FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(phase, PHASE_AWAITING_PREPARATION);
    assert_eq!(
        serde_json::from_str::<Vec<MigrationScheduleEntry>>(&schedule_json).unwrap(),
        approved_schedule
    );
    drop(conn);

    let draft_status = migration_status_with_projection_height(
        &db_path,
        WalletNetwork::Test,
        "account-1",
        0,
        0,
        0,
        0,
        Some(0),
    )
    .unwrap();
    assert_eq!(draft_status.phase, PHASE_AWAITING_PREPARATION);
    assert_eq!(draft_status.denomination_split_total_count, 0);
    assert_eq!(draft_status.denomination_split_completed_count, 0);

    let expected_txid = "11".repeat(32);
    let plan = DenominationPlan {
        migration_outputs: target_values,
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
    finalize_private_migration_draft(
        &db_path,
        &run_id,
        "account-1",
        WalletNetwork::Test,
        &plan,
        &prepared_notes,
        Vec::new(),
        vec![pending_test_stage(&expected_txid, vec![1, 2, 3])],
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
    assert_eq!(
        denomination_stages_for_run(&conn, &run_id, TEST_PASSWORD, TEST_SALT_BASE64)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn private_migration_draft_with_direct_notes_skips_denomination_waiting() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let target_values = vec![100_000_000];
    let approved_schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: target_values[0],
        block_offset: 1,
    }];
    let run_id = create_or_resume_private_migration_draft(
        &db_path,
        "account-1",
        WalletNetwork::Test,
        &target_values,
        &approved_schedule,
        PreparationTimingPolicy::Immediate,
    )
    .unwrap();
    let plan = DenominationPlan {
        migration_outputs: target_values,
        orchard_change: None,
        split_fee_zatoshi: 0,
        migration_fee_zatoshi: 10_000,
        total_input_zatoshi: 100_010_000,
        total_migratable_zatoshi: 100_000_000,
    };
    let prepared_notes = vec![PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 100_000_000,
        note_version: 2,
        nullifier_hex: None,
    }];

    finalize_private_migration_draft(
        &db_path,
        &run_id,
        "account-1",
        WalletNetwork::Test,
        &plan,
        &prepared_notes,
        Vec::new(),
        Vec::new(),
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
    assert_eq!(phase, PHASE_READY_TO_MIGRATE);
    assert!(
        denomination_stages_for_run(&conn, &run_id, TEST_PASSWORD, TEST_SALT_BASE64)
            .unwrap()
            .is_empty()
    );
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
    let approved_schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100_000_000,
        block_offset: 1,
    }];

    let run_id = create_run_with_staged_denominations_and_signed_children(
        &db_path,
        "account-1",
        WalletNetwork::Test,
        &plan,
        &prepared_notes,
        Vec::new(),
        vec![pending_test_stage(&expected_txid, raw_tx.clone())],
        Some(&approved_schedule),
        PreparationTimingPolicy::Immediate,
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
    let schedule_json: String = conn
        .query_row(
            &format!("SELECT schedule_json FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Vec<MigrationScheduleEntry>>(&schedule_json).unwrap(),
        approved_schedule
    );
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
fn create_run_with_direct_funding_notes_starts_ready_without_split_stages() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir.path().join("wallet.db");
    let db_path = db_path.to_string_lossy().to_string();
    let plan = DenominationPlan {
        migration_outputs: vec![100_000_000],
        orchard_change: None,
        split_fee_zatoshi: 0,
        migration_fee_zatoshi: 15_000,
        total_input_zatoshi: 100_015_000,
        total_migratable_zatoshi: 100_000_000,
    };
    let prepared_notes = vec![PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 100_015_000,
        note_version: 2,
        nullifier_hex: Some("22".repeat(32)),
    }];
    let approved_schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100_000_000,
        block_offset: 1,
    }];

    let run_id = create_run_with_staged_denominations_and_signed_children(
        &db_path,
        "account-1",
        WalletNetwork::Test,
        &plan,
        &prepared_notes,
        Vec::new(),
        Vec::new(),
        Some(&approved_schedule),
        PreparationTimingPolicy::Zip318Spaced,
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();

    let conn = rusqlite::Connection::open(&db_path).unwrap();
    assert_eq!(
        run_phase(&db_path, &run_id).unwrap(),
        PHASE_READY_TO_MIGRATE
    );
    assert!(
        denomination_stages_for_run(&conn, &run_id, TEST_PASSWORD, TEST_SALT_BASE64,)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        denomination_split_progress_for_run(&conn, &run_id).unwrap(),
        DenominationSplitProgress::default()
    );
    assert_eq!(
        prepared_notes_for_run(&db_path, &run_id).unwrap(),
        prepared_notes
    );
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
    let approved_schedule = vec![MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100_000_000,
        block_offset: 1,
    }];

    let err = create_run_with_staged_denominations_and_signed_children(
        &db_path,
        "account-1",
        WalletNetwork::Test,
        &plan,
        &prepared_notes,
        Vec::new(),
        vec![pending_test_stage(&expected_txid, vec![1, 2, 3, 4])],
        Some(&approved_schedule),
        PreparationTimingPolicy::Immediate,
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
fn confirmation_count_uses_recent_scanned_range_across_historic_gap() {
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
             VALUES
               (20, 500, 10),
               (500, 1000000, 20),
               (1000000, 1000004, 10);
         INSERT INTO blocks (height) VALUES (1000003);
         INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (100);",
    )
    .unwrap();

    // The historical gap does not invalidate the already-scanned transaction
    // block and its two successors.
    assert_eq!(
        synced_orchard_confirmation_count(&conn, 1_000_001).unwrap(),
        3
    );
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
            "[100000000,200000000]",
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

    let remaining_note = PreparedOrchardNoteRef {
        txid_hex: "22".repeat(32),
        output_index: 1,
        value_zatoshi: 200_000_000,
        note_version: 2,
        nullifier_hex: Some("33".repeat(32)),
    };
    conn.execute(
        &format!(
            "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
             (run_id, message_id, child_index, encrypted_base_pczt,
              encrypted_compact_sigs, target_height, expiry_height,
              value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
             VALUES (?1, 'remaining-child', 1, 'base', 'sigs', 30, 40,
                     199990000, 10000, ?2, '{{}}')"
        ),
        params![run_id, serde_json::to_string(&remaining_note).unwrap()],
    )
    .unwrap();

    reconcile_run_confirmations(&conn, run_id).unwrap();
    let incomplete_phase: String = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    let incomplete_lock_state: String = conn
        .query_row(
            &format!("SELECT lock_state FROM {PREPARED_NOTES_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    let retained_signed_children: u32 = conn
        .query_row(
            &format!("SELECT COUNT(*) FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(incomplete_phase, PHASE_BROADCAST_SCHEDULED);
    assert_eq!(incomplete_lock_state, "locked");
    assert_eq!(retained_signed_children, 1);

    conn.execute(
        &format!("UPDATE {RUNS_TABLE} SET phase = ?1 WHERE run_id = ?2"),
        params![PHASE_PAUSED, run_id],
    )
    .unwrap();
    reconcile_run_confirmations(&conn, run_id).unwrap();
    let paused_phase: String = conn
        .query_row(
            &format!("SELECT phase FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(paused_phase, PHASE_PAUSED);

    conn.execute(
        &format!("DELETE FROM {SIGNED_CHILD_PCZTS_TABLE} WHERE run_id = ?1"),
        params![run_id],
    )
    .unwrap();
    conn.execute(
        &format!(
            "UPDATE {RUNS_TABLE}
             SET target_values_json = '[100000000]', phase = ?1
             WHERE run_id = ?2"
        ),
        params![PHASE_WAITING_MIGRATION_CONFIRMATIONS, run_id],
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
        0,
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
    let status = status_for_run(&conn, stale_run.clone(), 0).unwrap();
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

    let status = status_for_run(&conn, stale_run, 0).unwrap();
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
                  scheduled_height, original_scheduled_height, status, metadata_json)
                 VALUES ('run-parts', ?1, ?2, 'raw', 1, 100, 100, 1, ?3,
                         0, 101, 1, ?4, ?4, ?5, '{{}}')"
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
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET scheduled_height = 9
             WHERE run_id = 'run-parts' AND part_index = 0"
        ),
        [],
    )
    .unwrap();
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
    assert_eq!(parts[0].original_scheduled_height, Some(1));
    assert_eq!(parts[0].effective_scheduled_height, Some(9));
    assert_eq!(parts[0].mined_height, None);
    assert_eq!(parts[1].state, MigrationPartState::Migrating);
    assert_eq!(parts[1].original_scheduled_height, Some(2));
    assert_eq!(parts[1].effective_scheduled_height, Some(2));
    assert_eq!(parts[1].mined_height, None);
    assert_eq!(parts[2].state, MigrationPartState::Confirming);
    assert_eq!(parts[2].confirmation_count, 1);
    assert_eq!(parts[2].mined_height, Some(20));
    assert_eq!(parts[3].state, MigrationPartState::Completed);
    assert_eq!(parts[3].confirmation_count, 3);
    assert_eq!(parts[3].mined_height, Some(18));
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
        migration_parts_for_run(&conn, run_id, &[100_000_000], PHASE_READY_TO_MIGRATE, 3).unwrap();

    assert_eq!(parts.len(), 1);
    assert_eq!(parts[0].part_index, 0);
    assert_eq!(parts[0].value_zatoshi, 100_000_000);
    assert_eq!(parts[0].state, MigrationPartState::Preparing);
    assert_eq!(parts[0].txid_hex, None);
}

#[test]
fn migration_batch_signing_selector_reports_initial_and_resign_requests_exactly() {
    assert_eq!(
        select_migration_batch_signing_part_indices(3, 0, 0, &[]).unwrap(),
        vec![0, 1, 2]
    );
    assert_eq!(
        select_migration_batch_signing_part_indices(2, 2, 2, &[1, 10]).unwrap(),
        vec![1, 10]
    );
    assert_eq!(
        select_migration_batch_signing_part_indices(
            12,
            12,
            0,
            &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        )
        .unwrap(),
        vec![0, 1, 2, 3, 4, 5, 6, 7]
    );
    assert_eq!(
        select_migration_batch_signing_part_indices(12, 0, 0, &[]).unwrap(),
        vec![0, 1, 2, 3, 4, 5, 6, 7]
    );
    assert_eq!(
        select_migration_batch_signing_part_indices(12, 8, 0, &[]).unwrap(),
        vec![8, 9, 10, 11]
    );
    assert_eq!(
        select_migration_batch_signing_part_indices(0, 0, 0, &[]).unwrap_err(),
        "Migration run has no prepared denomination notes"
    );
    assert_eq!(
        select_migration_batch_signing_part_indices(3, 3, 0, &[]).unwrap_err(),
        "All migration transactions are already signed and scheduled"
    );
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
    let selected_note_json = serde_json::to_string(&PreparedOrchardNoteRef {
        txid_hex: txid_hex.to_string(),
        output_index: 0,
        value_zatoshi: 100_000_000,
        note_version: 2,
        nullifier_hex: None,
    })
    .unwrap();
    let schedule_json = serde_json::to_string(&[MigrationScheduleEntry {
        part_index: Some(0),
        value_zatoshi: 100_000_000,
        block_offset: 0,
    }])
    .unwrap();
    conn.execute(
        &format!("UPDATE {RUNS_TABLE} SET schedule_json = ?1 WHERE run_id = ?2"),
        params![schedule_json, run_id],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
             (run_id, message_id, child_index, encrypted_base_pczt,
              encrypted_compact_sigs, target_height, expiry_height,
              value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
             VALUES (?1, 'message-0', 0, 'base', 'sigs', 20, 1000,
                     99980000, 20000, ?2, '{{}}')"
        ),
        params![run_id, selected_note_json],
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
    let retry_height: Option<u32> = conn
        .query_row(
            &format!("SELECT proof_retry_height FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(retry_height, Some(290));

    let status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(status.phase, PHASE_READY_TO_MIGRATE);
    assert_eq!(status.signed_child_pczt_count, 1);
    assert_eq!(status.next_action_height, Some(290));
    assert_eq!(status.estimated_completion_height, Some(293));
    assert_eq!(status.parts.len(), 1);
    assert_eq!(status.parts[0].state, MigrationPartState::Preparing);
    assert_eq!(status.parts[0].scheduled_height, Some(290));

    // Post-sync upgrade recovery: older builds could persist ready_to_migrate
    // before persisting the proof height, which made iOS classify the run as
    // state 2. Status projection itself must not repair the row.
    conn.execute(
        &format!("UPDATE {RUNS_TABLE} SET proof_retry_height = NULL WHERE run_id = ?1"),
        params![run_id],
    )
    .unwrap();
    let stale_status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(stale_status.next_action_height, None);
    backfill_ready_migration_proof_retry_height(&conn, run_id).unwrap();
    let recovered_status = status_for_run(&conn, run, 0).unwrap();
    assert_eq!(recovered_status.next_action_height, Some(290));
    let recovered_retry_height: Option<u32> = conn
        .query_row(
            &format!("SELECT proof_retry_height FROM {RUNS_TABLE} WHERE run_id = ?1"),
            params![run_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(recovered_retry_height, Some(290));
}

#[test]
fn status_keeps_migration_stage_while_waiting_for_spend_metadata() {
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
    let status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(status.phase, PHASE_READY_TO_MIGRATE);
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

    let status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(status.phase, PHASE_READY_TO_MIGRATE);
    assert_eq!(status.signed_child_pczt_count, 1);
    assert_eq!(status.pending_split_stage_count, 0);

    conn.execute(
        "UPDATE orchard_received_notes SET commitment_tree_position = 0",
        [],
    )
    .unwrap();

    let status = status_for_run(&conn, run, 0).unwrap();
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
              created_at_ms, updated_at_ms, target_values_json,
              proof_retry_height)
             VALUES (?1, 'account-1', 'test', ?2, ?3, 1, 1,
                     '[100000000]', 999)"
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
    let (phase, proof_retry_height, nullifier, lock_state): (
        String,
        Option<u32>,
        Option<String>,
        String,
    ) = conn
        .query_row(
            &format!(
                "SELECT r.phase, r.proof_retry_height, n.nullifier_hex, n.lock_state
                 FROM {RUNS_TABLE} r
                 JOIN {PREPARED_NOTES_TABLE} n ON n.run_id = r.run_id
                 WHERE r.run_id = ?1"
            ),
            params![run_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    assert_eq!(retained_signed, 1);
    assert_eq!(pending, 0);
    assert_eq!(phase, PHASE_WAITING_DENOM_CONFIRMATIONS);
    assert!(proof_retry_height.is_none());
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

    reconcile_wallet_locks_after_sync(db_path, WalletNetwork::Test).unwrap();
    let status = migration_status_with_projection_height(
        db_path,
        WalletNetwork::Test,
        "account-1",
        0,
        0,
        0,
        0,
        Some(0),
    )
    .unwrap();
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

    let status = status_for_run(&conn, run, 0).unwrap();
    assert_eq!(status.denomination_confirmation_count, 2);
    assert_eq!(status.denomination_confirmation_target, 3);
}

#[test]
fn staged_split_progress_tracks_the_active_frontier_and_projects_future_rounds() {
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
        let is_migration_output = stage_index + 1 == stage_txids.len();
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
        conn.execute(
            "INSERT INTO vizor_migration_denomination_stage_outputs
             (run_id, stage_index, output_order, output_index,
              value_zatoshi, note_version, kind, part_index)
             VALUES (?1, ?2, 0, 0, 99920000, 2, ?3, ?4)",
            params![
                run_id,
                stage_index as u32,
                if is_migration_output {
                    "migration"
                } else {
                    "continuation"
                },
                is_migration_output.then_some(0u32),
            ],
        )
        .unwrap();
    }
    conn.execute(
        "UPDATE vizor_migration_denomination_stages
         SET scheduled_height = 19
         WHERE run_id = ?1 AND stage_index = 2",
        params![run_id],
    )
    .unwrap();

    let run = ActiveRun {
        run_id: run_id.to_string(),
        phase: PHASE_WAITING_DENOM_CONFIRMATIONS.to_string(),
        target_values_zatoshi: vec![100_000_000],
        last_error: None,
    };
    let status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(status.denomination_confirmation_count, 0);
    assert_eq!(status.denomination_split_completed_count, 0);
    assert_eq!(status.denomination_split_total_count, 3);
    assert_eq!(status.preparation_transactions[2].scheduled_height, None);
    assert_eq!(
        status
            .preparation_transactions
            .iter()
            .map(|transaction| transaction.round)
            .collect::<Vec<_>>(),
        vec![1, 2, 3],
    );
    assert_eq!(status.preparation_transactions[2].planned_height, 19);
    assert_eq!(status.preparation_transactions[2].projected_height, 22);
    assert_eq!(
        status.preparation_transactions[2].projected_completion_height,
        25,
    );
    assert_eq!(
        status.preparation_transactions[0].outputs[0],
        MigrationPreparationOutputStatus {
            value_zatoshi: 99_920_000,
            target_value_zatoshi: None,
            kind: MigrationPreparationOutputKind::Continuation,
            next_round: Some(2),
        },
    );
    assert_eq!(
        status.preparation_transactions[2].outputs[0].kind,
        MigrationPreparationOutputKind::Migration,
    );
    assert_eq!(
        status.preparation_transactions[2].outputs[0].target_value_zatoshi,
        Some(100_000_000),
    );

    let delayed_status = status_for_run(&conn, run.clone(), 30).unwrap();
    assert_eq!(
        delayed_status.preparation_transactions[0].state,
        MigrationPreparationTransactionState::Broadcasted,
    );
    assert_eq!(
        delayed_status.preparation_transactions[0].projected_height,
        status.preparation_transactions[0].projected_height,
    );
    assert_eq!(
        delayed_status.preparation_transactions[0].projected_completion_height,
        33,
    );
    assert_eq!(
        delayed_status.preparation_transactions[1].projected_height,
        33,
    );
    assert_eq!(
        delayed_status.preparation_transactions[2].projected_height,
        52,
    );
    assert_eq!(
        delayed_status.preparation_transactions[2].projected_completion_height,
        55,
    );

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
    let status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(status.denomination_confirmation_count, 1);
    assert_eq!(status.denomination_split_completed_count, 0);
    assert_eq!(
        status.preparation_transactions[0].state,
        MigrationPreparationTransactionState::Confirming,
    );
    assert_eq!(status.preparation_transactions[0].mined_height, Some(20));

    conn.execute(
        "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (21)",
        [],
    )
    .unwrap();
    let status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(status.denomination_confirmation_count, 2);
    assert_eq!(status.denomination_split_completed_count, 0);

    conn.execute(
        "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (22)",
        [],
    )
    .unwrap();
    let status = status_for_run(&conn, run.clone(), 0).unwrap();
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
    let status = status_for_run(&conn, run.clone(), 0).unwrap();
    assert_eq!(status.denomination_confirmation_count, 1);
    assert_eq!(status.denomination_split_completed_count, 1);
    assert_eq!(status.preparation_transactions[1].mined_height, Some(23));

    conn.execute_batch(
        "INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (24);
         INSERT INTO orchard_tree_checkpoints (checkpoint_id) VALUES (25);",
    )
    .unwrap();
    let status = status_for_run(&conn, run, 0).unwrap();
    assert_eq!(status.denomination_confirmation_count, 0);
    assert_eq!(status.denomination_split_completed_count, 2);
    assert_eq!(status.denomination_split_total_count, 3);
}

#[test]
fn preparation_output_targets_exclude_reserved_migration_fees() {
    let targets = [50_000_000, 20_000_000];
    let mut assigned = BTreeSet::new();
    let output = |value_zatoshi, kind, part_index| DenominationStageOutputRef {
        output_index: 0,
        value_zatoshi,
        note_version: 2,
        kind,
        part_index,
    };

    assert_eq!(
        migration_preparation_output_target_value(
            &output(50_015_000, DenominationStageOutputKind::Migration, Some(0),),
            &targets,
            &mut assigned,
        ),
        Some(50_000_000),
    );
    assert_eq!(
        migration_preparation_output_target_value(
            &output(20_010_000, DenominationStageOutputKind::Migration, None),
            &targets,
            &mut assigned,
        ),
        Some(20_000_000),
    );
    assert_eq!(
        migration_preparation_output_target_value(
            &output(10_000, DenominationStageOutputKind::Change, None),
            &targets,
            &mut assigned,
        ),
        None,
    );
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

#[test]
fn migration_outbox_export_decrypts_only_scheduled_children() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "outbox-export",
        &[100, 200, 300],
        &[Some(90), Some(91), Some(92)],
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!("UPDATE {PENDING_TXS_TABLE} SET status = 'broadcasted' WHERE txid_hex = ?1"),
        params![txids[1]],
    )
    .unwrap();
    drop(conn);

    let batch = export_scheduled_migration_outbox(
        &db_path,
        "account-1",
        WalletNetwork::Regtest,
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap()
    .unwrap();

    assert_eq!(batch.run_id, "outbox-export");
    assert!(batch.timing_mean_blocks > 0);
    assert!(batch.timing_max_blocks >= batch.timing_mean_blocks);
    assert_eq!(batch.next_proof_height, None);
    assert_eq!(batch.items.len(), 2);
    assert_eq!(batch.items[0].item_id, txids[0]);
    assert_eq!(batch.items[0].raw_tx, vec![0, 0xaa, 0x55]);
    assert_eq!(batch.items[0].anchor_boundary_height, 90);
    assert_eq!(batch.items[1].item_id, txids[2]);
    assert_eq!(batch.items[1].raw_tx, vec![2, 0xaa, 0x55]);
}

#[test]
fn migration_outbox_export_fails_closed_without_anchor() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    create_outbox_test_run(&db_path, "outbox-no-anchor", &[100], &[None]);

    let error = export_scheduled_migration_outbox(
        &db_path,
        "account-1",
        WalletNetwork::Regtest,
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap_err();

    assert!(error.contains("missing its anchor boundary"));
}

#[test]
fn migration_outbox_export_omits_unverified_next_proof_height() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    ensure_schema(&conn).unwrap();
    let selected_note = PreparedOrchardNoteRef {
        txid_hex: "11".repeat(32),
        output_index: 0,
        value_zatoshi: 110,
        note_version: 2,
        nullifier_hex: None,
    };
    conn.execute(
        &format!(
            "INSERT INTO {RUNS_TABLE}
             (run_id, account_uuid, network, db_fingerprint, phase,
              created_at_ms, updated_at_ms, target_values_json, proof_retry_height)
             VALUES ('proof-wait', 'account-1', 'regtest', ?1, ?2, 1, 1, '[100]', 321)"
        ),
        params![db_path, PHASE_WAITING_DENOM_CONFIRMATIONS],
    )
    .unwrap();
    conn.execute(
        &format!(
            "INSERT INTO {SIGNED_CHILD_PCZTS_TABLE}
             (run_id, message_id, child_index, encrypted_base_pczt,
              encrypted_compact_sigs, target_height, expiry_height,
              value_zatoshi, fee_zatoshi, selected_note_json, metadata_json)
             VALUES ('proof-wait', 'child-0', 0, 'base', 'sigs', 300, 400,
                     100, 10, ?1, '{{}}')"
        ),
        params![serde_json::to_string(&selected_note).unwrap()],
    )
    .unwrap();
    drop(conn);

    let batch = export_scheduled_migration_outbox(
        &db_path,
        "account-1",
        WalletNetwork::Regtest,
        TEST_PASSWORD,
        TEST_SALT_BASE64,
    )
    .unwrap();

    assert!(batch.is_none());
}

#[test]
fn accepted_outbox_receipt_atomically_reschedules_overdue_peers() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "outbox-accepted",
        &[100, 200, 300],
        &[Some(90), Some(90), Some(90)],
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    for txid in &txids {
        conn.execute(
            &format!(
                "UPDATE {PENDING_TXS_TABLE}
                 SET schedule_start_height = 90, scheduled_height = ?1
                 WHERE txid_hex = ?2"
            ),
            params![100, txid],
        )
        .unwrap();
    }
    drop(conn);
    let updates = vec![
        MigrationOutboxScheduleUpdate {
            item_id: txids[1].clone(),
            scheduled_height: 104,
            schedule_start_height: 100,
        },
        MigrationOutboxScheduleUpdate {
            item_id: txids[2].clone(),
            scheduled_height: 108,
            schedule_start_height: 100,
        },
    ];

    apply_accepted_migration_outbox_receipt(
        &db_path,
        "account-1",
        WalletNetwork::Regtest,
        "outbox-accepted",
        &txids[0],
        100,
        &updates,
    )
    .unwrap();
    apply_accepted_migration_outbox_receipt(
        &db_path,
        "account-1",
        WalletNetwork::Regtest,
        "outbox-accepted",
        &txids[0],
        100,
        &updates,
    )
    .unwrap();

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let rows = txids
        .iter()
        .map(|txid| {
            conn.query_row(
                &format!(
                    "SELECT status, scheduled_height, schedule_start_height
                     FROM {PENDING_TXS_TABLE} WHERE txid_hex = ?1"
                ),
                params![txid],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, u32>(1)?,
                        row.get::<_, u32>(2)?,
                    ))
                },
            )
            .unwrap()
        })
        .collect::<Vec<_>>();
    assert_eq!(rows[0].0, "broadcasted");
    assert_eq!(rows[1], ("scheduled".to_string(), 104, 100));
    assert_eq!(rows[2], ("scheduled".to_string(), 108, 100));
}

#[test]
fn invalid_outbox_schedule_rolls_back_accepted_transition() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "outbox-invalid",
        &[100, 200],
        &[Some(90), Some(90)],
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET schedule_start_height = 90, scheduled_height = 100"
        ),
        [],
    )
    .unwrap();
    drop(conn);

    let error = apply_accepted_migration_outbox_receipt(
        &db_path,
        "account-1",
        WalletNetwork::Regtest,
        "outbox-invalid",
        &txids[0],
        100,
        &[],
    )
    .unwrap_err();
    assert!(error.contains("exactly the remaining overdue items"));

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    let status: String = conn
        .query_row(
            &format!("SELECT status FROM {PENDING_TXS_TABLE} WHERE txid_hex = ?1"),
            params![txids[0]],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(status, "scheduled");
}

fn insert_test_mined_txid(conn: &rusqlite::Connection, txid_hex: &str, mined_height: u32) {
    conn.execute(
        "CREATE TABLE IF NOT EXISTS transactions (
             txid BLOB PRIMARY KEY,
             mined_height INTEGER
         )",
        [],
    )
    .unwrap();
    let mut txid_blob = hex::decode(txid_hex).unwrap();
    txid_blob.reverse();
    conn.execute(
        "INSERT OR REPLACE INTO transactions (txid, mined_height) VALUES (?1, ?2)",
        params![txid_blob, mined_height],
    )
    .unwrap();
}

fn pending_status(conn: &rusqlite::Connection, txid_hex: &str) -> String {
    conn.query_row(
        &format!("SELECT status FROM {PENDING_TXS_TABLE} WHERE txid_hex = ?1"),
        params![txid_hex],
        |row| row.get(0),
    )
    .unwrap()
}

#[test]
fn expiry_recovery_promotes_locally_mined_scheduled_part_instead_of_resign() {
    // Resume/export call mark_expired_pending_parts_for_resign before due
    // selection. A mined-but-still-`scheduled` part past expiry must become
    // `confirmed`, not `needs_resign`.
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "expiry-mined",
        &[100, 200],
        &[Some(90), Some(90)],
    );
    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    // Force past-expiry bookkeeping while leaving status as `scheduled`.
    conn.execute(
        &format!(
            "UPDATE {PENDING_TXS_TABLE}
             SET expiry_height = 100
             WHERE run_id = 'expiry-mined' AND txid_hex = ?1"
        ),
        params![txids[0]],
    )
    .unwrap();
    insert_test_mined_txid(&conn, &txids[0], 101);
    assert_eq!(pending_status(&conn, &txids[0]), "scheduled");
    drop(conn);

    let tip = 100u32;
    assert_eq!(
        expired_unconfirmed_pending_count(&db_path, "expiry-mined", tip).unwrap(),
        0,
        "count must reconcile mined rows before treating them as expired"
    );
    assert_eq!(
        mark_expired_pending_parts_for_resign(&db_path, "expiry-mined", tip).unwrap(),
        0,
        "expiry recovery must not flip a locally mined part to needs_resign"
    );
    assert!(pending_parts_needing_resign(&db_path, "expiry-mined")
        .unwrap()
        .is_empty());

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    assert_eq!(pending_status(&conn, &txids[0]), "confirmed");
    assert_eq!(pending_status(&conn, &txids[1]), "scheduled");
}

#[test]
fn due_pending_skips_locally_mined_scheduled_part() {
    // A part that is already mined locally must not remain the due candidate.
    // Selection reconciles pending confirmations first so later due parts can
    // advance instead of head-of-line blocking on a stale `scheduled` row.
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "race-b",
        &[100, 200, 300],
        &[Some(90), Some(90), Some(90)],
    );
    // create_outbox_test_run schedules at 101, 102, 103.
    let tip = 103u32;

    let before = due_pending_txs(&db_path, "race-b", tip, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();
    assert_eq!(before.len(), 1);
    assert_eq!(before[0].txid_hex, txids[0]);

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    insert_test_mined_txid(&conn, &txids[0], 101);
    assert_eq!(pending_status(&conn, &txids[0]), "scheduled");
    assert!(local_denomination_chain_identity(&conn, &txids[0])
        .unwrap()
        .is_some());
    drop(conn);

    let next = due_pending_txs(&db_path, "race-b", tip, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();
    assert_eq!(next.len(), 1);
    assert_eq!(
        next[0].txid_hex, txids[1],
        "locally mined part 0 must be skipped so part 1 becomes due"
    );

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    assert_eq!(
        pending_status(&conn, &txids[0]),
        "confirmed",
        "due selection must promote the mined head so bookkeeping matches chain state"
    );
    assert_eq!(pending_status(&conn, &txids[1]), "scheduled");
}

#[test]
fn reconcile_promotes_pending_when_local_txid_is_mined() {
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "race-c",
        &[100, 200, 300],
        &[Some(90), Some(90), Some(90)],
    );
    let tip = 103u32;

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    insert_test_mined_txid(&conn, &txids[0], 101);
    assert_eq!(pending_status(&conn, &txids[0]), "scheduled");

    reconcile_run_confirmations(&conn, "race-c").unwrap();
    assert_eq!(pending_status(&conn, &txids[0]), "confirmed");
    assert_eq!(pending_status(&conn, &txids[1]), "scheduled");
    drop(conn);

    let next = due_pending_txs(&db_path, "race-c", tip, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();
    assert_eq!(next.len(), 1);
    assert_eq!(
        next[0].txid_hex, txids[1],
        "after reconcile, part 1 must become the due candidate"
    );
}

#[test]
fn due_pending_unblocks_later_parts_after_stale_head_is_mined() {
    // Combined HOL symptom: mined-but-unreconciled part 0 must not block part 1
    // once due selection runs.
    let temp_dir = tempfile::tempdir().unwrap();
    let db_path = temp_dir
        .path()
        .join("wallet.db")
        .to_string_lossy()
        .to_string();
    let txids = create_outbox_test_run(
        &db_path,
        "race-hol",
        &[100, 200, 300],
        &[Some(90), Some(90), Some(90)],
    );
    let tip = 103u32;

    let conn = open_wallet_raw_conn_with_timeout(&db_path, READ_DB_BUSY_TIMEOUT).unwrap();
    insert_test_mined_txid(&conn, &txids[0], 101);
    drop(conn);

    let unblocked =
        due_pending_txs(&db_path, "race-hol", tip, TEST_PASSWORD, TEST_SALT_BASE64).unwrap();
    assert_eq!(unblocked[0].txid_hex, txids[1]);

    assert_eq!(
        due_scheduled_pending_count(&db_path, "race-hol", tip).unwrap(),
        2,
        "after promoting part 0, two later scheduled parts remain due at tip"
    );
}
