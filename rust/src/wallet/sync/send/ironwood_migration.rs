pub(crate) fn prepare_orchard_migration_denominations_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err("Migration already has an active run. Start migration next.".to_string());
    }
    {
        let mut request_store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        ensure_no_live_single_qr_migration_request(&mut request_store, account_uuid, network)?;
    }
    {
        let mut request_store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        ensure_no_live_denomination_request(&mut request_store, account_uuid, network)?;
    }

    let split = with_wallet_db_write_lock("send.migration.prepare_denominations_pczt", || {
        create_padded_orchard_denomination_pczts(db_path, network, account_uuid)
    })?;
    let Some(split) = split else {
        return Err(
            "Create migration denominations failed: insufficient spendable Orchard funds"
                .to_string(),
        );
    };

    let request_id = new_keystone_migration_request_id("denominations");
    let messages = split
        .stages
        .iter()
        .map(|stage| KeystoneMigrationMessage {
            id: stage.id.clone(),
            redacted_pczt: stage.redacted_pczt.clone(),
        })
        .collect::<Vec<_>>();
    validate_keystone_migration_messages(&messages)?;
    let root_proofs = split
        .stages
        .iter()
        .filter(|stage| !stage.deferred)
        .map(|stage| (stage.id.clone(), stage.base_pczt.clone()))
        .collect::<Vec<_>>();
    if root_proofs.is_empty() {
        return Err("Padded denomination plan has no immediately provable root".to_string());
    }
    let mut request_store = keystone_denomination_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredDenominationPczt {
            account_uuid: account_uuid.to_string(),
            network,
            state: KeystoneMigrationRequestState::Proofing,
            proof_error: None,
            split_stages: split.stages,
            total_migratable_zatoshi: split.total_migratable_zatoshi,
            plan: split.plan,
        },
    );
    drop(request_store);
    spawn_denomination_proof_worker(request_id.clone(), root_proofs);

    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
    })
}

pub(crate) async fn complete_orchard_migration_denominations_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    pending_password: &[u8],
    pending_salt_base64: &str,
    approved_schedule: Vec<super::migration::MigrationScheduleEntry>,
    preparation_timing_policy: super::migration::PreparationTimingPolicy,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let signed_by_id = signed_migration_messages_by_id(request_id, signed_messages)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err(
            "Migration already has an active run. Reject this Keystone request.".to_string(),
        );
    }

    let stored = {
        let mut store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        let stored = store.get_mut(request_id).ok_or_else(|| {
            format!("Keystone denomination request {request_id} was not found or was already used")
        })?;
        if stored.account_uuid != account_uuid || stored.network != network {
            return Err(
                "Signed denomination request does not match the active account".to_string(),
            );
        }
        if signed_by_id.len() != stored.split_stages.len() {
            return Err(format!(
                "Keystone returned {} signed messages for {} requested denomination splits",
                signed_by_id.len(),
                stored.split_stages.len()
            ));
        }
        match stored.state {
            KeystoneMigrationRequestState::Proofing => {
                return Err(
                    "Vizor is still finishing migration proofs. Try again shortly.".to_string(),
                );
            }
            KeystoneMigrationRequestState::ProofFailed => {
                return Err(stored.proof_error.clone().unwrap_or_else(|| {
                    "Vizor proof generation failed. Reject and prepare a new request.".to_string()
                }));
            }
            KeystoneMigrationRequestState::Completing => {
                return Err("Keystone denomination request is already completing".to_string());
            }
            KeystoneMigrationRequestState::ProofReady => {}
        }
        if stored
            .split_stages
            .iter()
            .any(|stage| !stage.deferred && stage.pczt_with_proofs.is_none())
        {
            return Err("Keystone denomination root proofs are not ready".to_string());
        }
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredDenominationCompletion {
            split_stages: stored.split_stages.clone(),
            total_migratable_zatoshi: stored.total_migratable_zatoshi,
            plan: stored.plan.clone(),
        }
    };

    for stage in &stored.split_stages {
        if !signed_by_id.contains_key(&stage.id) {
            reset_denomination_request_after_failed_completion(request_id);
            return Err(format!("Keystone result missing {}", stage.id));
        }
    }
    let prepared_refs = prepared_refs_from_denomination_stages(&stored.split_stages);
    let finalize_result = (|| -> Result<String, String> {
        let denomination_stages =
            signed_denomination_stage_inserts(&stored.split_stages, &signed_by_id)?;
        super::migration::create_run_with_staged_denominations_and_signed_children(
            db_path,
            account_uuid,
            network,
            &stored.plan,
            &prepared_refs,
            Vec::new(),
            denomination_stages,
            Some(&approved_schedule),
            preparation_timing_policy,
            pending_password,
            pending_salt_base64,
        )
    })();
    let run_id = match finalize_result {
        Ok(run_id) => run_id,
        Err(e) => {
            reset_denomination_request_after_failed_completion(request_id);
            return Err(e);
        }
    };
    if let Ok(mut store) = keystone_denomination_requests().lock() {
        store.remove(request_id);
    }

    let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run_id,
        pending_password,
        pending_salt_base64,
        MigrationBroadcastPolicy::FOREGROUND,
    )
    .await?
    else {
        return Err(
            "Migration denomination split has no broadcastable root transaction".to_string(),
        );
    };

    Ok(migration_result_from_split_broadcast(
        broadcast,
        prepared_refs.len() as u32,
        stored.split_stages.iter().try_fold(0u64, |total, stage| {
            total
                .checked_add(stage.fee_zatoshi)
                .ok_or("Denomination stage fee total overflow")
        })?,
        stored.total_migratable_zatoshi,
    ))
}

pub(crate) fn prepare_orchard_migration_single_qr_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err("Migration already has an active run.".to_string());
    }
    {
        let mut store = keystone_denomination_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone denomination request store: {e}"))?;
        ensure_no_live_denomination_request(&mut store, account_uuid, network)?;
    }
    {
        let mut store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        ensure_no_live_single_qr_migration_request(&mut store, account_uuid, network)?;
    }

    let split = with_wallet_db_write_lock("send.migration.prepare_single_qr_pczt", || {
        create_padded_orchard_denomination_pczts(db_path, network, account_uuid)
    })?;
    let Some(split) = split else {
        return Err(
            "Create migration denominations failed: insufficient spendable Orchard funds"
                .to_string(),
        );
    };

    let total_messages = split
        .predicted_notes
        .len()
        .checked_add(split.stages.len())
        .ok_or("Keystone migration message count overflow")?;
    if total_messages > ZCASH_SIGN_BATCH_MAX_MESSAGES {
        return Err(format!(
            "Single Keystone migration signing supports at most {ZCASH_SIGN_BATCH_MAX_MESSAGES} PCZTs, but this plan needs {} split transactions plus {} migration transactions. Reduce the migration amount or use the staged flow.",
            split.stages.len(),
            split.predicted_notes.len(),
        ));
    }

    let approved_schedule = super::migration::planned_transfer_schedule(
        split.plan.migration_outputs.iter().copied(),
        network,
        &mut OsRng,
    );
    let mut child_messages = Vec::with_capacity(split.predicted_notes.len());
    for (index, predicted) in split.predicted_notes.iter().enumerate() {
        let part_index = index as u32;
        let block_offset = super::migration::schedule_block_offset_for_part(
            &approved_schedule,
            &split.plan.migration_outputs,
            part_index,
            split.plan.migration_outputs[part_index as usize],
        )
        .ok_or("Generated migration schedule is missing a child")?;
        let pczt = create_orchard_to_ironwood_pczt_from_predicted_note(
            db_path,
            network,
            account_uuid,
            predicted,
            (index + 1) as u32,
            block_offset,
        )?
        .ok_or("Predicted migration note is below the migration fee threshold")?;
        child_messages.push(pczt);
    }

    let request_id = new_keystone_migration_request_id("single");
    let mut messages = Vec::with_capacity(total_messages);
    messages.extend(split.stages.iter().map(|stage| KeystoneMigrationMessage {
        id: stage.id.clone(),
        redacted_pczt: stage.redacted_pczt.clone(),
    }));
    messages.extend(
        child_messages
            .iter()
            .map(|message| KeystoneMigrationMessage {
                id: message.id.clone(),
                redacted_pczt: message.redacted_pczt.clone(),
            }),
    );
    validate_keystone_migration_messages(&messages)?;

    let root_proofs = split
        .stages
        .iter()
        .filter(|stage| !stage.deferred)
        .map(|stage| (stage.id.clone(), stage.base_pczt.clone()))
        .collect::<Vec<_>>();
    if root_proofs.is_empty() {
        return Err("Padded denomination plan has no immediately provable root".to_string());
    }
    let mut request_store = keystone_single_qr_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredSingleQrMigrationPczt {
            account_uuid: account_uuid.to_string(),
            network,
            state: KeystoneMigrationRequestState::Proofing,
            proof_error: None,
            split_stages: split.stages,
            total_migratable_zatoshi: split.total_migratable_zatoshi,
            plan: split.plan,
            child_messages,
            approved_schedule,
        },
    );
    drop(request_store);
    spawn_single_qr_split_proof_worker(request_id.clone(), root_proofs);

    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
    })
}

pub(crate) async fn complete_orchard_migration_single_qr_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    pending_password: &[u8],
    pending_salt_base64: &str,
    preparation_timing_policy: super::migration::PreparationTimingPolicy,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let signed_by_id = signed_migration_messages_by_id(request_id, signed_messages)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err(
            "Migration already has an active run. Reject this Keystone request.".to_string(),
        );
    }

    let stored = {
        let mut store = keystone_single_qr_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone single QR request store: {e}"))?;
        let stored = store.get_mut(request_id).ok_or_else(|| {
            format!("Keystone migration request {request_id} was not found or was already used")
        })?;
        if stored.account_uuid != account_uuid || stored.network != network {
            return Err("Signed migration request does not match the active account".to_string());
        }
        let expected_count = stored
            .child_messages
            .len()
            .checked_add(stored.split_stages.len())
            .ok_or("Keystone migration message count overflow")?;
        if signed_by_id.len() != expected_count {
            return Err(format!(
                "Keystone returned {} signed messages for {} requested messages",
                signed_by_id.len(),
                expected_count
            ));
        }
        match stored.state {
            KeystoneMigrationRequestState::Proofing => {
                return Err(
                    "Vizor is still finishing migration proofs. Try again shortly.".to_string(),
                );
            }
            KeystoneMigrationRequestState::ProofFailed => {
                return Err(stored.proof_error.clone().unwrap_or_else(|| {
                    "Vizor proof generation failed. Reject and prepare a new request.".to_string()
                }));
            }
            KeystoneMigrationRequestState::Completing => {
                return Err("Keystone migration request is already completing".to_string());
            }
            KeystoneMigrationRequestState::ProofReady => {}
        }
        if stored
            .split_stages
            .iter()
            .any(|stage| !stage.deferred && stage.pczt_with_proofs.is_none())
        {
            return Err("Keystone denomination root proofs are not ready".to_string());
        }
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredSingleQrMigrationCompletion {
            split_stages: stored.split_stages.clone(),
            total_migratable_zatoshi: stored.total_migratable_zatoshi,
            plan: stored.plan.clone(),
            child_messages: stored.child_messages.clone(),
            approved_schedule: stored.approved_schedule.clone(),
        }
    };

    for id in stored
        .split_stages
        .iter()
        .map(|stage| stage.id.as_str())
        .chain(stored.child_messages.iter().map(|child| child.id.as_str()))
    {
        if !signed_by_id.contains_key(id) {
            reset_single_qr_request_after_failed_completion(request_id);
            return Err(format!("Keystone result missing {id}"));
        }
    }

    let prepared_refs = prepared_refs_from_denomination_stages(&stored.split_stages);

    let finalize_result = (|| -> Result<String, String> {
        let denomination_stages =
            signed_denomination_stage_inserts(&stored.split_stages, &signed_by_id)?;
        let signed_children = stored
            .child_messages
            .iter()
            .map(|child| {
                let mut selected_note = child.selected_note.clone();
                selected_note.nullifier_hex = None;
                let sigs = signed_by_id
                    .get(&child.id)
                    .ok_or_else(|| format!("Keystone result missing {}", child.id))?
                    .clone();
                super::pczt::preflight_orchard_spend_auth_signatures(&child.base_pczt, &sigs)?;
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
        super::migration::create_run_with_staged_denominations_and_signed_children(
            db_path,
            account_uuid,
            network,
            &stored.plan,
            &prepared_refs,
            signed_children,
            denomination_stages,
            Some(&stored.approved_schedule),
            preparation_timing_policy,
            pending_password,
            pending_salt_base64,
        )
    })();
    let run_id = match finalize_result {
        Ok(run_id) => run_id,
        Err(e) => {
            reset_single_qr_request_after_failed_completion(request_id);
            return Err(e);
        }
    };
    if let Ok(mut store) = keystone_single_qr_migration_requests().lock() {
        store.remove(request_id);
    }

    let Some(broadcast) = broadcast_pending_denomination_stages(
        db_path,
        lightwalletd_url,
        network,
        &run_id,
        pending_password,
        pending_salt_base64,
        MigrationBroadcastPolicy::FOREGROUND,
    )
    .await?
    else {
        return Err(
            "Migration denomination split has no broadcastable root transaction".to_string(),
        );
    };

    Ok(migration_result_from_split_broadcast(
        broadcast,
        prepared_refs.len() as u32,
        stored
            .split_stages
            .iter()
            .map(|stage| stage.fee_zatoshi)
            .sum(),
        stored.total_migratable_zatoshi,
    ))
}

pub(crate) fn prepare_orchard_migration_batch_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let run = super::migration::active_migration_run(db_path, account_uuid, network)?
        .ok_or("No active migration run")?;
    let chain_tip_height =
        u32::try_from(super::get_sync_progress(db_path, network)?.chain_tip_height)
            .map_err(|_| "Migration chain tip exceeds u32".to_string())?;
    if let Some(message) =
        pending_migration_policy_rebuild_message(db_path, network, &run.run_id, chain_tip_height)?
    {
        super::migration::retire_run_for_rebuild(db_path, &run.run_id, &message)?;
        return Err(message);
    }
    super::migration::mark_expired_pending_parts_for_resign(
        db_path,
        &run.run_id,
        chain_tip_height,
    )?;
    let recoveries = super::migration::pending_parts_needing_resign(db_path, &run.run_id)?;
    let initial_signing = recoveries.is_empty();
    let all_prepared_notes = super::migration::prepared_notes_for_run(db_path, &run.run_id)?;
    let prepared_notes = if initial_signing {
        all_prepared_notes
    } else {
        recoveries
            .iter()
            .map(|recovery| recovery.selected_note.clone())
            .collect()
    };
    if prepared_notes.is_empty() {
        return Err("Migration run has no prepared denomination notes".to_string());
    }
    let pending_totals = super::migration::pending_totals_for_run(db_path, &run.run_id)?;
    if initial_signing
        && (pending_totals.total_count > 0
            || super::migration::signed_child_pczt_count(db_path, &run.run_id)? > 0)
    {
        return Err("Migration transactions are already signed and scheduled".to_string());
    }
    if !initial_signing && !prepared_note_spend_metadata_is_available(db_path, &run.run_id)? {
        return Err(
            "Prepared denomination notes are not spendable yet. Sync and try again.".to_string(),
        );
    }
    {
        let mut request_store = keystone_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
        ensure_no_live_migration_request(&mut request_store, account_uuid, network, &run.run_id)?;
    }

    let mut created = Vec::with_capacity(prepared_notes.len());
    let timing_policy = super::migration::timing_policy_for_run(db_path, &run.run_id, network)?;
    let approved_schedule =
        super::migration::approved_schedule_for_run(db_path, &run.run_id)?;
    for (index, note_ref) in prepared_notes.iter().enumerate() {
        let part_index = recoveries
            .get(index)
            .map(|recovery| recovery.part_index)
            .unwrap_or(index as u32);
        let schedule_block_offset = super::migration::schedule_block_offset_for_part(
            &approved_schedule,
            &run.target_values_zatoshi,
            part_index,
            *run.target_values_zatoshi
                .get(part_index as usize)
                .ok_or("Migration part is outside the approved target list")?,
        )
        .ok_or("Approved migration schedule is missing a child")?;
        let migration_index = recoveries
            .get(index)
            .map(|recovery| recovery.part_index + 1)
            .unwrap_or((index + 1) as u32);
        let pczt_result = if initial_signing {
            create_deferred_orchard_to_ironwood_pczt_from_prepared_note(
                db_path,
                network,
                account_uuid,
                note_ref,
                migration_index,
                schedule_block_offset,
            )
        } else {
            with_wallet_db_write_lock("send.migration.prepare_exact_note_pczt", || {
                create_orchard_to_ironwood_pczt_from_note(
                    db_path,
                    network,
                    account_uuid,
                    note_ref,
                    migration_index,
                    schedule_block_offset,
                    timing_policy,
                    true,
                )
            })
        };
        let pczt = match pczt_result {
            Ok(pczt) => pczt,
            Err(e) if is_orchard_witness_not_ready_error(&e) => {
                mark_prepared_notes_waiting(db_path, &run.run_id)?;
                return Err(
                    "Prepared denomination notes are not spendable yet. Sync and try again."
                        .to_string(),
                );
            }
            Err(e) => return Err(e),
        };
        let Some(pczt) = pczt else {
            if initial_signing {
                return Err(
                    "Prepared denomination note is not available for Keystone signing. Sync and try again."
                        .to_string(),
                );
            } else {
                mark_prepared_notes_waiting(db_path, &run.run_id)?;
                return Err(
                    "Prepared denomination notes are not spendable yet. Sync and try again."
                        .to_string(),
                );
            }
        };
        if let Some(recovery) = recoveries.get(index) {
            if pczt.migrated_zatoshi != recovery.value_zatoshi {
                return Err("Expired migration denomination changed during rebuild".to_string());
            }
            if pczt.fee_zatoshi != recovery.fee_zatoshi {
                return Err(
                    "Canonical migration fee changed while rebuilding an expired part".to_string(),
                );
            }
        }
        created.push(pczt);
    }

    let request_id = new_keystone_migration_request_id("batch");
    let messages = created
        .iter()
        .map(|message| KeystoneMigrationMessage {
            id: message.id.clone(),
            redacted_pczt: message.redacted_pczt.clone(),
        })
        .collect::<Vec<_>>();
    validate_keystone_migration_messages(&messages)?;
    let proof_worker_messages = created
        .iter()
        .map(|message| (message.id.clone(), message.base_pczt.clone()))
        .collect::<Vec<_>>();
    let mut request_store = keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
    request_store.insert(
        request_id.clone(),
        StoredMigrationPcztBatch {
            account_uuid: account_uuid.to_string(),
            network,
            run_id: run.run_id,
            fallback_total_count: run.target_values_zatoshi.len() as u32,
            fallback_migrated_zatoshi: run.target_values_zatoshi.iter().sum(),
            recovery_old_txids: recoveries
                .iter()
                .map(|recovery| recovery.old_txid_hex.clone())
                .collect(),
            state: if initial_signing {
                KeystoneMigrationRequestState::ProofReady
            } else {
                KeystoneMigrationRequestState::Proofing
            },
            proof_error: None,
            messages: created,
        },
    );
    drop(request_store);
    if !initial_signing {
        spawn_migration_proof_worker(request_id.clone(), proof_worker_messages);
    }

    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
    })
}

pub(crate) fn complete_orchard_migration_batch_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let signed_by_id = signed_migration_messages_by_id(request_id, signed_messages)?;
    let stored = {
        let mut store = keystone_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone migration request store: {e}"))?;
        let stored = store.get_mut(request_id).ok_or_else(|| {
            format!("Keystone migration request {request_id} was not found or was already used")
        })?;
        if stored.account_uuid != account_uuid || stored.network != network {
            return Err("Signed migration request does not match the active account".to_string());
        }
        if signed_by_id.len() != stored.messages.len() {
            return Err(format!(
                "Keystone returned {} signed messages for {} requested messages",
                signed_by_id.len(),
                stored.messages.len()
            ));
        }
        match stored.state {
            KeystoneMigrationRequestState::Proofing => {
                return Err(
                    "Vizor is still finishing migration proofs. Try again shortly.".to_string(),
                );
            }
            KeystoneMigrationRequestState::ProofFailed => {
                return Err(stored.proof_error.clone().unwrap_or_else(|| {
                    "Vizor proof generation failed. Reject and prepare a new request.".to_string()
                }));
            }
            KeystoneMigrationRequestState::Completing => {
                return Err("Keystone migration request is already completing".to_string());
            }
            KeystoneMigrationRequestState::ProofReady => {}
        }
        if !stored.recovery_old_txids.is_empty()
            && stored
                .messages
                .iter()
                .any(|message| message.pczt_with_proofs.is_none())
        {
            return Err("Keystone migration proofs are not ready".to_string());
        }
        stored.state = KeystoneMigrationRequestState::Completing;
        StoredMigrationBatchCompletion {
            run_id: stored.run_id.clone(),
            fallback_total_count: stored.fallback_total_count,
            fallback_migrated_zatoshi: stored.fallback_migrated_zatoshi,
            recovery_old_txids: stored.recovery_old_txids.clone(),
            messages: stored.messages.clone(),
        }
    };

    let run = super::migration::active_migration_run(db_path, account_uuid, network)?
        .ok_or("No active migration run")?;
    if run.run_id != stored.run_id {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Signed migration request is for an old migration run".to_string());
    }
    let current_prepared = super::migration::prepared_notes_for_run(db_path, &run.run_id)?;
    let request_prepared = stored
        .messages
        .iter()
        .map(|message| message.selected_note.clone())
        .collect::<Vec<_>>();
    let prepared_notes_unchanged = if stored.recovery_old_txids.is_empty() {
        current_prepared == request_prepared
    } else {
        request_prepared.iter().all(|requested| {
            current_prepared
                .iter()
                .any(|current| same_prepared_note_without_nullifier(current, requested))
        })
    };
    if !prepared_notes_unchanged {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Prepared migration notes changed before completion".to_string());
    }
    if stored.recovery_old_txids.is_empty()
        && super::migration::pending_totals_for_run(db_path, &run.run_id)?.total_count > 0
    {
        reset_migration_request_after_failed_completion(request_id);
        return Err("Migration transactions are already signed and scheduled".to_string());
    }

    if stored.recovery_old_txids.is_empty() {
        let completion_result = (|| -> Result<u64, String> {
            if stored
                .messages
                .iter()
                .any(|message| message.pczt_with_proofs.is_some())
            {
                return Err(
                    "Initial Keystone migration request unexpectedly contains proofs".to_string(),
                );
            }
            let mut total_fee_zatoshi = 0u64;
            let signed_children = stored
                .messages
                .clone()
                .into_iter()
                .map(|message| {
                    let sigs = signed_by_id
                        .get(&message.id)
                        .ok_or_else(|| format!("Keystone result missing {}", message.id))?
                        .clone();
                    super::pczt::preflight_orchard_spend_auth_signatures(
                        &message.base_pczt,
                        &sigs,
                    )?;
                    total_fee_zatoshi = total_fee_zatoshi
                        .checked_add(message.fee_zatoshi)
                        .ok_or("Migration fee total overflow")?;
                    Ok(super::migration::SignedMigrationPcztInsert {
                        message_id: message.id,
                        child_index: message.part_index,
                        base_pczt: message.base_pczt,
                        sigs,
                        target_height: message.target_height,
                        anchor_boundary_height: None,
                        expiry_height: message.expiry_height,
                        scheduled_height: message.scheduled_height,
                        value_zatoshi: message.migrated_zatoshi,
                        fee_zatoshi: message.fee_zatoshi,
                        selected_note: message.selected_note.clone(),
                        metadata: super::migration::PendingMigrationTxMetadata {
                            tx_kind: "migration".to_string(),
                            funding_account_uuid: account_uuid.to_string(),
                            selected_note: message.selected_note,
                        },
                    })
                })
                .collect::<Result<Vec<_>, String>>()?;
            super::migration::persist_signed_child_pczts_for_run(
                db_path,
                &stored.run_id,
                signed_children,
                pending_password,
                pending_salt_base64,
            )?;
            Ok(total_fee_zatoshi)
        })();
        if completion_result.is_err() {
            reset_migration_request_after_failed_completion(request_id);
        }
        let total_fee_zatoshi = completion_result?;
        if let Ok(mut store) = keystone_migration_requests().lock() {
            store.remove(request_id);
        }
        return Ok(IronwoodMigrationResult {
            txids: String::new(),
            status: super::migration::PHASE_READY_TO_MIGRATE.to_string(),
            broadcasted_count: 0,
            total_count: stored.fallback_total_count,
            message: Some(
                "Migration transactions were signed and will continue when the safe anchor is ready."
                    .to_string(),
            ),
            fee_zatoshi: total_fee_zatoshi,
            migrated_zatoshi: stored.fallback_migrated_zatoshi,
        });
    }

    let completion_result = (|| -> Result<super::migration::PendingMigrationTotals, String> {
        let mut pending_inserts = Vec::with_capacity(stored.messages.len());
        for message in stored.messages.clone() {
            let sigs = signed_by_id
                .get(&message.id)
                .ok_or_else(|| format!("Keystone result missing {}", message.id))?;
            let extracted = super::pczt::apply_sigs_and_extract(
                message
                    .pczt_with_proofs
                    .as_ref()
                    .ok_or("Keystone migration proof missing")?,
                sigs,
                None,
                None,
            )?;
            pending_inserts.push(super::migration::PendingMigrationTxInsert {
                part_index: message.part_index,
                txid_hex: extracted.txid.to_string(),
                raw_tx: extracted.raw_tx,
                target_height: message.target_height,
                anchor_boundary_height: message.anchor_boundary_height,
                expiry_height: message.expiry_height,
                scheduled_height: message.scheduled_height,
                value_zatoshi: message.migrated_zatoshi,
                fee_zatoshi: message.fee_zatoshi,
                selected_note: message.selected_note.clone(),
                metadata: super::migration::PendingMigrationTxMetadata {
                    tx_kind: "migration".to_string(),
                    funding_account_uuid: account_uuid.to_string(),
                    selected_note: message.selected_note,
                },
            });
        }

        if stored.recovery_old_txids.is_empty() {
            super::migration::insert_pending_txs(
                db_path,
                &stored.run_id,
                pending_inserts,
                pending_password,
                pending_salt_base64,
            )?;
        } else {
            if stored.recovery_old_txids.len() != pending_inserts.len() {
                return Err("Expired migration recovery batch changed size".to_string());
            }
            let replacements = stored
                .recovery_old_txids
                .iter()
                .cloned()
                .zip(pending_inserts)
                .map(|(old_txid_hex, replacement)| {
                    super::migration::PendingMigrationTxReplacement {
                        old_txid_hex,
                        replacement,
                    }
                })
                .collect();
            super::migration::replace_resigned_pending_parts(
                db_path,
                &stored.run_id,
                network,
                replacements,
                Vec::new(),
                pending_password,
                pending_salt_base64,
            )?;
        }
        super::migration::pending_totals_for_run(db_path, &stored.run_id)
    })();
    if completion_result.is_err() {
        reset_migration_request_after_failed_completion(request_id);
    }
    let totals = completion_result?;
    if let Ok(mut store) = keystone_migration_requests().lock() {
        store.remove(request_id);
    }
    Ok(migration_result_from_pending_totals(
        totals,
        super::migration::PHASE_BROADCAST_SCHEDULED,
        Some("Migration transactions were signed and scheduled for delayed broadcast.".to_string()),
        stored.fallback_total_count,
        stored.fallback_migrated_zatoshi,
    ))
}

include!("ironwood_migration/status_advance.rs");

include!("ironwood_migration/keystone_requests.rs");

include!("ironwood_migration/denomination_split.rs");

include!("ironwood_migration/plan_child.rs");
