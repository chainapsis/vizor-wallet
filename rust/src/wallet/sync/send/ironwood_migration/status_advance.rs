fn is_orchard_witness_not_ready_error(error: &str) -> bool {
    let lower = error.to_ascii_lowercase();
    lower.contains("wallet must sync before finalizing migration")
        || lower.contains("prepared migration note witness missing")
        || (lower.contains("read orchard witnesses")
            && (lower.contains("anchornotfound")
                || lower.contains("notcontained")
                || lower.contains("checkpoint")
                || lower.contains("commitmenttree")))
}

fn mark_prepared_notes_waiting(db_path: &str, run_id: &str) -> Result<(), String> {
    super::migration::mark_run_phase(
        db_path,
        run_id,
        super::migration::PHASE_READY_TO_MIGRATE,
        Some("Waiting for the anchor block needed to migrate prepared notes."),
    )
}

fn current_migration_scanned_height(db_path: &str, network: WalletNetwork) -> Result<u32, String> {
    u32::try_from(super::get_sync_progress(db_path, network)?.scanned_height)
        .map_err(|_| "Migration scanned height exceeds u32".to_string())
}

fn defer_presigned_proof_until(
    db_path: &str,
    run_id: &str,
    retry_height: u32,
) -> Result<(), String> {
    super::migration::set_proof_retry_height(db_path, run_id, retry_height)?;
    mark_prepared_notes_waiting(db_path, run_id)
}

fn prepared_note_spend_metadata_is_available(db_path: &str, run_id: &str) -> Result<bool, String> {
    if super::migration::prepared_note_spend_metadata_available(db_path, run_id)? {
        return Ok(true);
    }
    mark_prepared_notes_waiting(db_path, run_id)?;
    Ok(false)
}

fn prepared_notes_not_spendable_result(
    total_count: u32,
    migrated_zatoshi: u64,
) -> IronwoodMigrationResult {
    IronwoodMigrationResult {
        txids: String::new(),
        status: super::migration::PHASE_READY_TO_MIGRATE.to_string(),
        broadcasted_count: 0,
        total_count,
        message: Some(
            "Waiting for the anchor block needed to migrate prepared notes.".to_string(),
        ),
        fee_zatoshi: 0,
        migrated_zatoshi,
    }
}

fn cancelled_migration_result(run: &super::migration::ActiveRun) -> IronwoodMigrationResult {
    IronwoodMigrationResult {
        txids: String::new(),
        status: run.phase.clone(),
        broadcasted_count: 0,
        total_count: run.target_values_zatoshi.len() as u32,
        message: Some("Background migration stopped before the next broadcast.".to_string()),
        fee_zatoshi: 0,
        migrated_zatoshi: run.target_values_zatoshi.iter().sum(),
    }
}

enum StagedDenominationAdvance {
    Waiting(IronwoodMigrationResult),
    Ready,
}

fn restore_observed_separate_submission_transactions<F>(
    conn: &rusqlite::Connection,
    stages: &[super::migration::DenominationStage],
    mut store: F,
) -> Result<u32, String>
where
    F: FnMut(&[u8], u32) -> Result<(), String>,
{
    let mut restored = 0u32;
    for stage in stages {
        let Some(raw_tx) = stage.raw_tx.as_deref() else {
            continue;
        };
        let Some(identity) =
            super::migration::local_denomination_chain_identity(conn, &stage.expected_txid_hex)?
        else {
            continue;
        };
        if super::migration::local_transaction_raw(conn, &stage.expected_txid_hex)?.is_some() {
            continue;
        }
        store(raw_tx, identity.mined_height).map_err(|error| {
            format!(
                "Restore observed separate-route denomination transaction {}: {error}",
                stage.expected_txid_hex
            )
        })?;
        restored = restored
            .checked_add(1)
            .ok_or("Restored denomination transaction count overflow")?;
    }
    Ok(restored)
}

fn reconcile_mined_denomination_stages(
    db_path: &str,
    network: WalletNetwork,
    run_id: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<Vec<super::migration::DenominationStage>, String> {
    let uses_separate_submission = !matches!(
        super::migration::migration_submission_policy(db_path, run_id)?,
        super::migration::MigrationSubmissionPolicy::Lightwalletd
    );
    super::migration::reconcile_denomination_stage_chain_state(db_path, run_id)?;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    let stages = super::migration::denomination_stages_for_run(
        &conn,
        run_id,
        pending_password,
        pending_salt_base64,
    )?;
    if uses_separate_submission {
        let restored = restore_observed_separate_submission_transactions(
            &conn,
            &stages,
            |raw_tx, mined_height| {
                super::transactions::decrypt_and_store_transaction(
                    db_path,
                    network,
                    raw_tx,
                    Some(u64::from(mined_height)),
                )
            },
        )?;
        if restored > 0 {
            log::info!(
                "migration: restored {restored} observed separate-route denomination transaction(s) from retained local bytes"
            );
        }
    }
    let mut recovered_included_stage = false;
    for stage in stages
        .iter()
        .filter(|stage| stage.status == super::migration::DenominationStageStatus::AwaitingInputs)
    {
        let Some(identity) =
            super::migration::local_denomination_chain_identity(&conn, &stage.expected_txid_hex)?
        else {
            continue;
        };
        let raw_tx = super::migration::local_transaction_raw(&conn, &stage.expected_txid_hex)?
            .ok_or_else(|| {
                format!(
                    "Mined denomination stage {} is missing wallet transaction bytes",
                    stage.expected_txid_hex
                )
            })?;
        super::migration::promote_awaiting_denomination_stage(
            &conn,
            run_id,
            stage.stage_index,
            &stage.expected_txid_hex,
            raw_tx,
            pending_password,
            pending_salt_base64,
        )?;
        super::migration::replace_denomination_stage_confirmation_identity(
            &conn,
            run_id,
            &stage.expected_txid_hex,
            identity.mined_height,
            &identity.block_hash,
        )?;
        recovered_included_stage = true;
    }
    if recovered_included_stage {
        super::migration::denomination_stages_for_run(
            &conn,
            run_id,
            pending_password,
            pending_salt_base64,
        )
    } else {
        Ok(stages)
    }
}

async fn advance_staged_denomination_run(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    run: &super::migration::ActiveRun,
    pending_password: &[u8],
    pending_salt_base64: &str,
    policy: MigrationBroadcastPolicy<'_>,
) -> Result<StagedDenominationAdvance, String> {
    let stages = reconcile_mined_denomination_stages(
        db_path,
        network,
        &run.run_id,
        pending_password,
        pending_salt_base64,
    )?;
    if stages.is_empty() {
        return Ok(StagedDenominationAdvance::Ready);
    }

    let fallback_total_count = u32::try_from(run.target_values_zatoshi.len())
        .map_err(|_| "Migration output count exceeds u32".to_string())?;
    let fallback_migrated_zatoshi = run.target_values_zatoshi.iter().sum();
    let split_fee_zatoshi = stages.iter().try_fold(0u64, |total, stage| {
        total
            .checked_add(stage.fee_zatoshi)
            .ok_or("Denomination stage fee total overflow")
    })?;

    if let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run.run_id,
        pending_password,
        pending_salt_base64,
        policy,
    )
    .await?
    {
        return Ok(StagedDenominationAdvance::Waiting(
            migration_result_from_split_broadcast(
                broadcast,
                fallback_total_count,
                split_fee_zatoshi,
                fallback_migrated_zatoshi,
            ),
        ));
    }

    if stages
        .iter()
        .any(|stage| stage.status == super::migration::DenominationStageStatus::AwaitingInputs)
    {
        if policy.is_cancelled() {
            return Ok(StagedDenominationAdvance::Waiting(
                cancelled_migration_result(run),
            ));
        }
        let finalized = finalize_ready_denomination_stages(
            db_path,
            network,
            account_uuid,
            &run.run_id,
            pending_password,
            pending_salt_base64,
            policy,
        )?;
        if finalized > 0 {
            if policy.should_defer_broadcast(finalized) {
                return Ok(StagedDenominationAdvance::Waiting(
                    prepared_notes_not_spendable_result(
                        fallback_total_count,
                        fallback_migrated_zatoshi,
                    ),
                ));
            }
            let broadcast = broadcast_pending_denomination_stages(
                db_path,
                lightwalletd_url,
                network,
                &run.run_id,
                pending_password,
                pending_salt_base64,
                policy,
            )
            .await?;
            let Some(broadcast) = broadcast else {
                return Ok(StagedDenominationAdvance::Waiting(
                    prepared_notes_not_spendable_result(
                        fallback_total_count,
                        fallback_migrated_zatoshi,
                    ),
                ));
            };
            return Ok(StagedDenominationAdvance::Waiting(
                migration_result_from_split_broadcast(
                    broadcast,
                    fallback_total_count,
                    split_fee_zatoshi,
                    fallback_migrated_zatoshi,
                ),
            ));
        }
        return Ok(StagedDenominationAdvance::Waiting(
            prepared_notes_not_spendable_result(fallback_total_count, fallback_migrated_zatoshi),
        ));
    }

    let denomination_ready =
        super::migration::reconcile_denomination_run(db_path, &run.run_id)?;
    // Denomination outputs become lockable only after sync has discovered
    // them. Reconcile here, at that state transition, instead of making every
    // ordinary-send migration predicate perform a full lock write pass.
    super::migration::reconcile_wallet_locks_for_run(db_path, network, &run.run_id)?;
    if denomination_ready {
        return Ok(StagedDenominationAdvance::Ready);
    }
    Ok(StagedDenominationAdvance::Waiting(
        prepared_notes_not_spendable_result(fallback_total_count, fallback_migrated_zatoshi),
    ))
}

fn run_may_finalize_presigned_migration_children(run: &super::migration::ActiveRun) -> bool {
    matches!(
        run.phase.as_str(),
        super::migration::PHASE_WAITING_DENOM_CONFIRMATIONS
            | super::migration::PHASE_READY_TO_MIGRATE
            | super::migration::PHASE_BROADCAST_SCHEDULED
    )
}

fn derive_migration_usk(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
) -> Result<UnifiedSpendingKey, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let zip32_index = account
        .source()
        .key_derivation()
        .ok_or("No key derivation")?
        .account_index();
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
        .map_err(|e| format!("USK derivation failed: {e:?}"))?;
    let derived_account_id = db
        .get_account_for_ufvk(&usk.to_unified_full_viewing_key())
        .map_err(|e| format!("{e}"))?
        .ok_or("Spending key not recognized")?
        .id();
    if derived_account_id != account_id {
        return Err("Spending key does not match migration account".to_string());
    }
    drop(seed);

    Ok(usk)
}

// Keep software migration signing in synchronous preparation scopes. These
// helpers return only signed PCZT or raw transaction artifacts, so callers can
// perform network broadcast after seed and USK values have been dropped.
fn prepare_software_migration_run(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
    approved_schedule: &[super::migration::MigrationScheduleEntry],
    preparation_timing_policy: super::migration::PreparationTimingPolicy,
    migration_timing_policy: super::migration::MigrationTimingPolicy,
) -> Result<Option<PreparedSoftwareMigrationRun>, String> {
    let usk = derive_migration_usk(db_path, network, account_uuid, seed)?;
    let Some(mut split) = create_padded_orchard_denomination_pczts(
        db_path,
        network,
        account_uuid,
        preparation_timing_policy,
        migration_timing_policy,
    )?
    else {
        return Ok(None);
    };

    let mut split_sigs = HashMap::with_capacity(split.stages.len());
    for stage in &mut split.stages {
        let signed_pczt = sign_orchard_migration_pczt_with_usk(
            &stage.base_pczt,
            &stage.orchard_spend_action_indices,
            &usk,
        )?;
        let sigs = super::pczt::extract_required_compact_sigs_from_signed_pczt(
            &stage.base_pczt,
            &signed_pczt,
        )?;
        super::pczt::preflight_orchard_spend_auth_signatures(&stage.base_pczt, &sigs)?;
        if !stage.deferred {
            stage.pczt_with_proofs = Some(super::pczt::add_proofs_to_pczt(
                &stage.base_pczt,
                None,
                None,
            )?);
        }
        split_sigs.insert(stage.id.clone(), sigs);
    }
    let prepared_refs = prepared_refs_from_denomination_split(
        &split.direct_prepared_refs,
        &split.stages,
    );
    let denomination_stages = signed_denomination_stage_inserts(&split.stages, &split_sigs)?;

    let child_messages = split
        .predicted_notes
        .iter()
        .enumerate()
        .map(|(index, predicted)| {
            let part_index = index as u32;
            let block_offset = super::migration::schedule_block_offset_for_part(
                approved_schedule,
                &split.plan.migration_outputs,
                part_index,
                predicted.value_zatoshi.saturating_sub(split.plan.migration_fee_zatoshi),
            )
            .ok_or("Approved migration schedule is missing a child")?;
            create_orchard_to_ironwood_pczt_from_predicted_note(
                db_path,
                network,
                account_uuid,
                predicted,
                (index + 1) as u32,
                block_offset,
                None,
            )?
            .ok_or("Predicted migration note is below the migration fee threshold".to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;
    let signed_children = child_messages
        .iter()
        .map(|child| {
            let signed_pczt = sign_orchard_migration_pczt_with_usk(
                &child.base_pczt,
                &child.orchard_spend_action_indices,
                &usk,
            )?;
            // Persist only the produced signatures, matching the hardware
            // "signatures-only" path's compact storage form rather than the
            // full signed PCZT.
            let sigs = super::pczt::extract_required_compact_sigs_from_signed_pczt(
                &child.base_pczt,
                &signed_pczt,
            )?;
            super::pczt::preflight_orchard_spend_auth_signatures(&child.base_pczt, &sigs)?;
            let mut selected_note = child.selected_note.clone();
            selected_note.nullifier_hex = None;
            Ok(super::migration::SignedMigrationPcztInsert {
                message_id: child.id.clone(),
                child_index: child.part_index,
                base_pczt: child.base_pczt.clone(),
                sigs,
                target_height: child.target_height,
                anchor_boundary_height: child.anchor_boundary_height,
                expiry_height: child.expiry_height,
                scheduled_height: child.scheduled_height,
                value_zatoshi: child.migrated_zatoshi,
                fee_zatoshi: child.fee_zatoshi,
                selected_note: selected_note.clone(),
                metadata: super::migration::PendingMigrationTxMetadata {
                    tx_kind: "migration".to_string(),
                    funding_account_uuid: account_uuid.to_string(),
                    selected_note,
                },
            })
        })
        .collect::<Result<Vec<_>, String>>()?;

    Ok(Some(PreparedSoftwareMigrationRun {
        plan: split.plan,
        prepared_refs,
        denomination_stages,
        signed_children,
        fee_zatoshi: split.stages.iter().try_fold(0u64, |total, stage| {
            total
                .checked_add(stage.fee_zatoshi)
                .ok_or("Denomination stage fee total overflow")
        })?,
        total_migratable_zatoshi: split.total_migratable_zatoshi,
    }))
}
