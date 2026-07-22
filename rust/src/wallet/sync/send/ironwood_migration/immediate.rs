const IMMEDIATE_KEYSTONE_BATCH_LIMIT: usize = 8;

fn immediate_plan_and_notes(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<(OrchardMigrationImmediatePlan, Vec<super::migration::PreparedOrchardNoteRef>)>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let orchard_fvk = account
        .ufvk()
        .and_then(|ufvk| ufvk.orchard())
        .ok_or("Orchard viewing key not available")?;
    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before estimating immediate migration")?;
    let mut notes = select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    notes.sort_by_key(|note| (format!("{}", note.txid()), note.output_index()));
    let fee = u64::from(
        ConservativeZip317FeeRule
            .fee_required(
                &network,
                BlockHeight::from(target_height),
                std::iter::empty::<TransparentInputSize>(),
                std::iter::empty::<usize>(),
                0,
                0,
                MIGRATION_ORCHARD_ACTION_COUNT,
                MIGRATION_IRONWOOD_ACTION_COUNT,
            )
            .map_err(|e| format!("Failed to estimate immediate migration fee: {e}"))?,
    );

    let mut prepared = Vec::new();
    let mut targets = Vec::new();
    let mut total_input = 0u64;
    for received in notes {
        let value = received
            .note_value()
            .map(u64::from)
            .map_err(|e| format!("Invalid Orchard note value: {e}"))?;
        if value <= fee || value - fee < MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI {
            continue;
        }
        total_input = total_input
            .checked_add(value)
            .ok_or("Immediate migration input total overflow")?;
        targets.push(value - fee);
        prepared.push(super::migration::PreparedOrchardNoteRef {
            txid_hex: format!("{}", received.txid()),
            output_index: received.output_index() as u32,
            value_zatoshi: value,
            note_version: 2,
            nullifier_hex: Some(hex::encode(received.note().nullifier(orchard_fvk).to_bytes())),
        });
    }
    if prepared.is_empty() {
        return Ok(None);
    }
    let transaction_count = u32::try_from(prepared.len())
        .map_err(|_| "Immediate migration transaction count exceeds u32".to_string())?;
    let total_fee = fee
        .checked_mul(u64::from(transaction_count))
        .ok_or("Immediate migration fee total overflow")?;
    let total_migratable_zatoshi = targets.iter().try_fold(0u64, |total, value| {
        total
            .checked_add(*value)
            .ok_or("Immediate migration value total overflow")
    })?;
    let keystone_signing_round_count = u32::try_from(
        prepared.len().div_ceil(IMMEDIATE_KEYSTONE_BATCH_LIMIT),
    )
    .map_err(|_| "Immediate Keystone signing round count exceeds u32".to_string())?;
    Ok(Some((
        OrchardMigrationImmediatePlan {
            target_values_zatoshi: targets,
            total_input_zatoshi: total_input,
            total_migratable_zatoshi,
            estimated_total_fee_zatoshi: total_fee,
            planned_transaction_count: transaction_count,
            keystone_signing_round_count,
            signing_batch_limit: IMMEDIATE_KEYSTONE_BATCH_LIMIT as u32,
        },
        prepared,
    )))
}

pub(crate) fn get_orchard_migration_immediate_plan(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<OrchardMigrationImmediatePlan>, String> {
    Ok(immediate_plan_and_notes(db_path, network, account_uuid)?.map(|(plan, _)| plan))
}

fn build_immediate_children(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    indexed_notes: &[(u32, super::migration::PreparedOrchardNoteRef)],
) -> Result<Vec<CreatedMigrationPczt>, String> {
    let mut anchor_cohort_counts = BTreeMap::new();
    indexed_notes
        .iter()
        .map(|(part_index, note)| {
            create_orchard_to_ironwood_pczt_from_note(
                db_path,
                network,
                account_uuid,
                note,
                part_index.saturating_add(1),
                super::migration::MigrationTimingPolicy::Immediate,
                &mut anchor_cohort_counts,
                false,
            )?
            .ok_or_else(|| {
                format!(
                    "Immediate migration note {}:{} is no longer spendable",
                    note.txid_hex, note.output_index
                )
            })
        })
        .collect()
}

fn signed_immediate_child_insert(
    account_uuid: &str,
    child: &CreatedMigrationPczt,
    sigs: Vec<pczt::roles::signer::SpendAuthSignature>,
) -> super::migration::SignedMigrationPcztInsert {
    super::migration::SignedMigrationPcztInsert {
        message_id: child.id.clone(),
        child_index: child.part_index,
        base_pczt: child.base_pczt.clone(),
        sigs,
        target_height: child.target_height,
        anchor_boundary_height: child.anchor_boundary_height,
        expiry_height: child.expiry_height,
        value_zatoshi: child.migrated_zatoshi,
        fee_zatoshi: child.fee_zatoshi,
        selected_note: child.selected_note.clone(),
        metadata: super::migration::PendingMigrationTxMetadata {
            tx_kind: "immediate_migration".to_string(),
            funding_account_uuid: account_uuid.to_string(),
            selected_note: child.selected_note.clone(),
        },
    }
}

pub(crate) async fn migrate_orchard_to_ironwood_immediate(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
    pending_password: zeroize::Zeroizing<Vec<u8>>,
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    if super::migration::active_migration_run(db_path, account_uuid, network)?.is_some() {
        return Err("Migration already has an active run".to_string());
    }
    let (plan, prepared) = immediate_plan_and_notes(db_path, network, account_uuid)?
        .ok_or("No Orchard notes can be migrated immediately")?;
    let indexed = prepared
        .iter()
        .cloned()
        .enumerate()
        .map(|(index, note)| {
            u32::try_from(index)
                .map(|index| (index, note))
                .map_err(|_| "Immediate migration part index exceeds u32".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let children = with_wallet_db_write_lock("send.migration.immediate.build", || {
        build_immediate_children(db_path, network, account_uuid, &indexed)
    })?;
    let usk = derive_migration_usk(db_path, network, account_uuid, seed)?;
    let signed_children = children
        .iter()
        .map(|child| {
            let signed = sign_orchard_migration_pczt_with_usk(
                &child.base_pczt,
                &child.orchard_spend_action_indices,
                &usk,
            )?;
            let sigs = super::pczt::extract_required_compact_sigs_from_signed_pczt(
                &child.base_pczt,
                &signed,
            )?;
            super::pczt::preflight_orchard_spend_auth_signatures(&child.base_pczt, &sigs)?;
            Ok(signed_immediate_child_insert(account_uuid, child, sigs))
        })
        .collect::<Result<Vec<_>, String>>()?;
    drop(usk);

    let run_id = super::migration::create_immediate_run(
        db_path,
        account_uuid,
        network,
        &prepared,
        &plan.target_values_zatoshi,
        signed_children,
        pending_password.as_slice(),
        pending_salt_base64,
    )?;
    finalize_presigned_migration_children(
        db_path,
        network,
        account_uuid,
        &run_id,
        pending_password.as_slice(),
        pending_salt_base64,
        MigrationBroadcastPolicy::FOREGROUND,
    )?;
    broadcast_due_scheduled_migration_txs(
        db_path,
        lightwalletd_url,
        network,
        &run_id,
        pending_password.as_slice(),
        pending_salt_base64,
        plan.planned_transaction_count,
        plan.total_migratable_zatoshi,
        MigrationBroadcastPolicy::FOREGROUND,
    )
    .await
}

pub(crate) fn prepare_orchard_migration_immediate_pczt(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<KeystoneMigrationSigningRequest, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    let run_id = match super::migration::active_migration_run(db_path, account_uuid, network)? {
        Some(run) => {
            if !super::migration::run_is_immediate(db_path, &run.run_id)? {
                return Err("Another migration is already active".to_string());
            }
            run.run_id
        }
        None => {
            let (plan, prepared) = immediate_plan_and_notes(db_path, network, account_uuid)?
                .ok_or("No Orchard notes can be migrated immediately")?;
            super::migration::create_immediate_run(
                db_path,
                account_uuid,
                network,
                &prepared,
                &plan.target_values_zatoshi,
                Vec::new(),
                pending_password,
                pending_salt_base64,
            )?
        }
    };
    {
        let mut store = keystone_migration_requests()
            .lock()
            .map_err(|e| format!("Lock Keystone immediate request store: {e}"))?;
        ensure_no_live_migration_request(&mut store, account_uuid, network, &run_id)?;
    }
    let unsigned = super::migration::unsigned_immediate_prepared_notes(db_path, &run_id)?;
    if unsigned.is_empty() {
        return Err("All immediate migration transactions are already signed".to_string());
    }
    let batch = unsigned
        .into_iter()
        .take(IMMEDIATE_KEYSTONE_BATCH_LIMIT)
        .collect::<Vec<_>>();
    let created = with_wallet_db_write_lock("send.migration.immediate.prepare_pczt", || {
        build_immediate_children(db_path, network, account_uuid, &batch)
    })?;
    let request_id = new_keystone_migration_request_id("immediate");
    let messages = created
        .iter()
        .map(|message| KeystoneMigrationMessage {
            id: message.id.clone(),
            redacted_pczt: message.redacted_pczt.clone(),
        })
        .collect::<Vec<_>>();
    validate_keystone_migration_messages(&messages)?;
    let proof_messages = created
        .iter()
        .map(|message| (message.id.clone(), message.base_pczt.clone()))
        .collect::<Vec<_>>();
    let run = super::migration::active_migration_run(db_path, account_uuid, network)?
        .ok_or("Immediate migration run disappeared")?;
    let mut store = keystone_migration_requests()
        .lock()
        .map_err(|e| format!("Lock Keystone immediate request store: {e}"))?;
    store.insert(
        request_id.clone(),
        StoredMigrationPcztBatch {
            account_uuid: account_uuid.to_string(),
            network,
            run_id,
            fallback_total_count: run.target_values_zatoshi.len() as u32,
            fallback_migrated_zatoshi: run.target_values_zatoshi.iter().sum(),
            recovery_old_txids: Vec::new(),
            state: KeystoneMigrationRequestState::Proofing,
            proof_error: None,
            messages: created,
        },
    );
    drop(store);
    spawn_migration_proof_worker(request_id.clone(), proof_messages);
    Ok(KeystoneMigrationSigningRequest {
        request_id,
        messages,
        signing_batch_limit: IMMEDIATE_KEYSTONE_BATCH_LIMIT as u32,
    })
}

pub(crate) async fn complete_orchard_migration_immediate_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    request_id: &str,
    signed_messages: Vec<KeystoneSignedMigrationMessage>,
    pending_password: &[u8],
    pending_salt_base64: &str,
) -> Result<IronwoodMigrationResult, String> {
    let result = complete_orchard_migration_batch_pczt(
        db_path,
        network,
        account_uuid,
        request_id,
        signed_messages,
        pending_password,
        pending_salt_base64,
    )?;
    let run = super::migration::active_migration_run(db_path, account_uuid, network)?
        .ok_or("Immediate migration run disappeared after signing")?;
    if !super::migration::unsigned_immediate_prepared_notes(db_path, &run.run_id)?.is_empty() {
        return Ok(result);
    }
    broadcast_due_orchard_migration_transactions(
        db_path,
        lightwalletd_url,
        network,
        account_uuid,
        zeroize::Zeroizing::new(pending_password.to_vec()),
        pending_salt_base64,
    )
    .await
}
