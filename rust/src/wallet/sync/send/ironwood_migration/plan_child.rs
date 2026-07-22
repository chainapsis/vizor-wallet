pub(crate) fn get_orchard_migration_private_plan(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<OrchardMigrationPrivatePlan>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let fee_rule = ConservativeZip317FeeRule;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let ufvk = account.ufvk().ok_or("Account cannot create PCZTs")?;
    let orchard_fvk = ufvk.orchard().ok_or("Orchard viewing key not available")?;

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before estimating migration plan")?;
    let mut orchard_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    orchard_notes.sort_by_key(|note| (format!("{}", note.txid()), note.output_index()));
    if orchard_notes.is_empty() {
        return Ok(None);
    }

    let input_values = orchard_notes
        .iter()
        .map(|note| note.note_value().map(u64::from).map_err(|e| format!("{e}")))
        .collect::<Result<Vec<_>, String>>()?;
    // Touch the FVK-derived nullifiers in the read-only estimate path so the
    // note-version/value assumptions match the mutating PCZT builder path.
    for received in &orchard_notes {
        let _ = received.note().nullifier(orchard_fvk);
    }

    let migration_fee_estimate = fee_rule
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
        .map_err(|e| format!("Failed to estimate migration fee: {e}"))?;
    let split_fee = fee_rule
        .fee_required(
            &network,
            BlockHeight::from(target_height),
            std::iter::empty::<TransparentInputSize>(),
            std::iter::empty::<usize>(),
            0,
            0,
            super::migration::DENOMINATION_SPLIT_ACTIONS,
            0,
        )
        .map_err(|e| format!("Failed to estimate padded denomination fee: {e}"))?;
    let padded_plan = super::migration::plan_padded_denominations(
        &input_values,
        u64::from(split_fee),
        u64::from(migration_fee_estimate),
        MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI,
        super::migration::MIGRATION_MAX_PREPARED_NOTES_PER_RUN,
    )?;
    let Some(padded_plan) = padded_plan else {
        return Ok(None);
    };

    let planned_batch_count = u32::try_from(padded_plan.denominations.migration_outputs.len())
        .map_err(|_| "Migration batch count exceeds u32".to_string())?;
    let denomination_split_stage_count = u32::try_from(padded_plan.stages.len())
        .map_err(|_| "Denomination split stage count exceeds u32".to_string())?;
    let migration_fee_zatoshi = u64::from(migration_fee_estimate)
        .checked_mul(u64::from(planned_batch_count))
        .ok_or("Migration fee estimate overflow")?;
    let estimated_total_fee_zatoshi = padded_plan
        .denominations
        .split_fee_zatoshi
        .checked_add(migration_fee_zatoshi)
        .ok_or("Migration total fee estimate overflow")?;
    let scheduled_transfers = super::migration::planned_transfer_schedule(
        padded_plan.denominations.migration_outputs.iter().copied(),
        network,
        &mut OsRng,
    );

    Ok(Some(OrchardMigrationPrivatePlan {
        target_values_zatoshi: padded_plan.denominations.migration_outputs,
        total_input_zatoshi: padded_plan.denominations.total_input_zatoshi,
        total_migratable_zatoshi: padded_plan.denominations.total_migratable_zatoshi,
        orchard_change_zatoshi: padded_plan.denominations.orchard_change,
        denomination_split_fee_zatoshi: padded_plan.denominations.split_fee_zatoshi,
        migration_fee_zatoshi,
        estimated_total_fee_zatoshi,
        planned_batch_count,
        denomination_split_stage_count,
        signing_batch_limit: ZCASH_SIGN_BATCH_MAX_MESSAGES as u32,
        schedule_mean_delay_blocks: super::migration::schedule_parameters(network).0,
        schedule_max_delay_blocks: super::migration::schedule_parameters(network).1,
        max_prepared_notes_per_run: super::migration::MIGRATION_MAX_PREPARED_NOTES_PER_RUN as u32,
        scheduled_transfers,
    }))
}

fn select_all_orchard_v2_notes(
    db: &WalletDatabase,
    account_id: AccountUuid,
    anchor_height: BlockHeight,
) -> Result<Vec<ReceivedNote<ReceivedNoteId, orchard::Note>>, String> {
    db.get_unspent_orchard_notes_at_historical_height(account_id, anchor_height)
        .map(|notes| {
            notes
                .into_iter()
                .filter(|note| note.note().version() == orchard::note::NoteVersion::V2)
                .collect()
        })
        .map_err(|e| format!("Failed to select Orchard notes: {e}"))
}

fn dummy_orchard_merkle_path() -> Result<orchard::tree::MerklePath, String> {
    let zero = Option::<orchard::tree::MerkleHashOrchard>::from(
        orchard::tree::MerkleHashOrchard::from_bytes(&[0; 32]),
    )
    .ok_or("Zero Orchard Merkle hash is invalid")?;
    Ok(orchard::tree::MerklePath::from_parts(0, [zero; 32]))
}

/// Builds a migration child with 2 Orchard actions and 1 Ironwood action.
pub(super) fn migration_child_builder<P: consensus::Parameters>(
    network: P,
    target_height: BlockHeight,
    orchard_anchor: orchard::Anchor,
) -> Result<Builder<P, ()>, String> {
    let target_height_u32: u32 = target_height.into();
    let expiry_height =
        super::migration::zip318_canonical_migration_expiry_height(target_height_u32)?;

    Ok(Builder::new(
        network,
        target_height,
        BuildConfig::Standard {
            sapling_anchor: None,
            orchard_anchor: Some(orchard_anchor),
            ironwood_anchor: Some(orchard::Anchor::empty_tree()),
            orchard_bundle_type: orchard::builder::BundleType::DEFAULT,
            ironwood_bundle_type: orchard::builder::BundleType::UNPADDED,
        },
    )
    .with_expiry_height(BlockHeight::from(expiry_height)))
}

fn create_orchard_to_ironwood_pczt_from_predicted_note(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    predicted: &PredictedMigrationNote,
    migration_index: u32,
) -> Result<Option<CreatedMigrationPczt>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let ufvk = account.ufvk().ok_or("Account cannot create PCZTs")?;
    let account_derivation = account.source().key_derivation();
    let orchard_fvk = ufvk
        .orchard()
        .cloned()
        .ok_or("Orchard viewing key not available")?;
    let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);
    let internal_ovk = Some(orchard_fvk.to_ovk(orchard::keys::Scope::Internal));
    let memo = MemoBytes::empty();
    let (target_height, _) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read target height: {e}"))?
        .ok_or("Wallet must sync before preparing migration")?;
    let selected_value: Zatoshis = predicted
        .value_zatoshi
        .try_into()
        .map_err(|e| format!("Predicted migration note value invalid: {e}"))?;
    // Migration children are built from predicted denomination notes before the
    // split tx is mined. This dummy anchor is v6-only scaffolding. Orchard
    // spend signatures do not commit to it, and finalization replaces it with
    // the real anchor/witness before creating proofs.
    let dummy_witness = dummy_orchard_merkle_path()?;
    let dummy_anchor = {
        let cmx: orchard::note::ExtractedNoteCommitment = predicted.note.commitment().into();
        dummy_witness.root(cmx)
    };
    let fee_rule = ConservativeZip317FeeRule;
    let make_builder = |ironwood_amount: Zatoshis| {
        let mut builder =
            migration_child_builder(network, BlockHeight::from(target_height), dummy_anchor)?;

        builder
            .add_orchard_spend::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                orchard_fvk.clone(),
                predicted.note,
                dummy_witness.clone(),
            )
            .map_err(|e| format!("Add predicted Orchard migration spend failed: {e}"))?;
        builder
            .add_ironwood_output::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                internal_ovk.clone(),
                recipient,
                ironwood_amount,
                memo.clone(),
            )
            .map_err(|e| format!("Add predicted Ironwood migration output failed: {e}"))?;
        Ok::<_, String>(builder)
    };

    let builder_with_minimum_amount = make_builder(
        Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?,
    )?;
    let fee_amount = builder_with_minimum_amount
        .get_fee(&fee_rule)
        .map_err(|e| format!("Failed to estimate predicted migration fee: {e}"))?;
    if selected_value <= fee_amount {
        return Ok(None);
    }
    let migrated_amount: Zatoshis = (selected_value - fee_amount)
        .ok_or_else(|| "Predicted migration amount underflow".to_string())?;
    if !super::migration::is_zip318_canonical_denomination(u64::from(migrated_amount)) {
        return Err(
            "Predicted migration amount is not a ZIP 318 canonical denomination".to_string(),
        );
    }
    let builder = if migrated_amount
        == Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?
    {
        builder_with_minimum_amount
    } else {
        make_builder(migrated_amount)?
    };

    let build_result = builder
        .build_for_pczt(rand_core::OsRng, &fee_rule)
        .map_err(|e| format!("Build predicted migration PCZT failed: {e}"))?;
    let expiry_height = u32::from(build_result.pczt_parts.expiry_height);
    let built_pczt = pczt_from_build_result(build_result, network, account_derivation, 1, 0)?;
    let target_height_u32: u32 = target_height.into();

    Ok(Some(CreatedMigrationPczt {
        part_index: migration_index.saturating_sub(1),
        id: format!("migration-{migration_index}"),
        base_pczt: built_pczt.bytes,
        orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
        pczt_with_proofs: None,
        redacted_pczt: built_pczt.redacted_bytes,
        target_height: target_height_u32,
        anchor_boundary_height: None,
        expiry_height,
        fee_zatoshi: u64::from(fee_amount),
        migrated_zatoshi: u64::from(migrated_amount),
        selected_note: super::migration::PreparedOrchardNoteRef {
            txid_hex: predicted.txid_hex.clone(),
            output_index: predicted.output_index,
            value_zatoshi: predicted.value_zatoshi,
            note_version: 2,
            nullifier_hex: None,
        },
    }))
}

fn sign_orchard_migration_pczt_with_usk(
    pczt_bytes: &[u8],
    orchard_spend_action_indices: &[usize],
    usk: &UnifiedSpendingKey,
) -> Result<Vec<u8>, String> {
    use pczt::roles::signer::Signer;

    if orchard_spend_action_indices.is_empty() {
        return Err("Migration PCZT has no Orchard spend actions".to_string());
    }
    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse migration PCZT: {e:?}"))?;
    let orchard_ask = orchard::keys::SpendAuthorizingKey::from(usk.orchard());
    let mut signer =
        Signer::new(pczt).map_err(|e| format!("Create migration PCZT signer: {e:?}"))?;
    for index in orchard_spend_action_indices {
        signer
            .sign_orchard(*index, &orchard_ask)
            .map_err(|e| format!("Sign migration PCZT action {index}: {e:?}"))?;
    }
    signer
        .finish()
        .serialize()
        .map_err(|e| format!("Serialize signed migration PCZT: {e:?}"))
}

fn create_orchard_to_ironwood_pczt_from_note(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
    note_ref: &super::migration::PreparedOrchardNoteRef,
    migration_index: u32,
    timing_policy: super::migration::MigrationTimingPolicy,
    anchor_cohort_counts: &mut BTreeMap<u32, u32>,
    allow_replacing_local_spend: bool,
) -> Result<Option<CreatedMigrationPczt>, String> {
    if note_ref.note_version != 2 {
        return Err("Prepared migration note is not an Orchard V2 note".to_string());
    }

    let mut db = open_wallet_db(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let account = db
        .get_account(account_id)
        .map_err(|e| format!("{e}"))?
        .ok_or("Account not found")?;
    let ufvk = account.ufvk().ok_or("Account cannot create PCZTs")?;
    let account_derivation = account.source().key_derivation();
    let orchard_fvk = ufvk
        .orchard()
        .cloned()
        .ok_or("Orchard viewing key not available")?;
    let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);
    let internal_ovk = Some(orchard_fvk.to_ovk(orchard::keys::Scope::Internal));
    let memo = MemoBytes::empty();

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before migrating denominations")?;

    let orchard_selected = if allow_replacing_local_spend {
        let available_notes =
            select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
        let Some(selected) = available_notes.iter().find(|selected| {
            format!("{}", selected.txid()).eq_ignore_ascii_case(&note_ref.txid_hex)
                && selected.output_index() as u32 == note_ref.output_index
        }) else {
            return Ok(None);
        };
        ReceivedNote::from_parts(
            *selected.internal_note_id(),
            *selected.txid(),
            selected.output_index(),
            *selected.note(),
            selected.spending_key_scope(),
            selected.note_commitment_tree_position(),
            selected.mined_height(),
            selected.max_shielding_input_height(),
        )
    } else {
        let txid = parse_txid_hex(&note_ref.txid_hex)?;
        let selected = db
            .get_spendable_note(
                &txid,
                ShieldedProtocol::Orchard,
                note_ref.output_index,
                target_height,
            )
            .map_err(|e| format!("Failed to revalidate prepared note: {e}"))?;
        let Some(selected) = selected else {
            return Ok(None);
        };
        let orchard_note = match selected.note() {
            Note::Orchard { note, .. } => *note,
            Note::Sapling(_) => return Err("Prepared note revalidated as Sapling".to_string()),
        };
        ReceivedNote::from_parts(
            *selected.internal_note_id(),
            *selected.txid(),
            selected.output_index(),
            orchard_note,
            selected.spending_key_scope(),
            selected.note_commitment_tree_position(),
            selected.mined_height(),
            selected.max_shielding_input_height(),
        )
    };
    let orchard_note = *orchard_selected.note();
    if orchard_note.version() != orchard::note::NoteVersion::V2 {
        return Err("Prepared note revalidated as non-V2 Orchard".to_string());
    }
    let selected_value: Zatoshis = orchard_note
        .value()
        .inner()
        .try_into()
        .map_err(|e| format!("Prepared note value invalid: {e}"))?;
    if u64::from(selected_value) != note_ref.value_zatoshi {
        return Err("Prepared note value changed during revalidation".to_string());
    }
    let target_height_u32: u32 = target_height.into();
    let anchor_height_u32 = u32::from(anchor_height);
    let anchor_boundary_height = if timing_policy
        == super::migration::MigrationTimingPolicy::Immediate
    {
        anchor_height_u32
    } else {
        let nu6_3_activation_height = nu6_3_activation_height_u32(network)?;
        let mined_height = orchard_selected
            .mined_height()
            .ok_or("Prepared migration note mined height unavailable")?;
        let Some(anchor_boundary_height) =
            super::migration::zip318_draw_anchor_boundary_for_note_with_cohorts_and_policy(
                network,
                timing_policy,
                anchor_height_u32,
                u32::from(mined_height),
                nu6_3_activation_height,
                anchor_cohort_counts,
            )
        else {
            return Ok(None);
        };
        anchor_boundary_height
    };
    *anchor_cohort_counts
        .entry(anchor_boundary_height)
        .or_default() += 1;

    let (orchard_anchor, orchard_inputs) = migration_orchard_witnesses(
        &mut db,
        network,
        BlockHeight::from(anchor_boundary_height),
        std::slice::from_ref(&orchard_selected),
    )?;
    let fee_rule = ConservativeZip317FeeRule;
    let make_builder = |ironwood_amount: Zatoshis| {
        let mut builder =
            migration_child_builder(network, BlockHeight::from(target_height), orchard_anchor)?;

        for (note, merkle_path) in orchard_inputs.iter() {
            builder
                .add_orchard_spend::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                    orchard_fvk.clone(),
                    *note,
                    merkle_path.clone(),
                )
                .map_err(|e| format!("Add migration Orchard spend failed: {e}"))?;
        }
        builder
            .add_ironwood_output::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                internal_ovk.clone(),
                recipient,
                ironwood_amount,
                memo.clone(),
            )
            .map_err(|e| format!("Add migration Ironwood output failed: {e}"))?;
        Ok::<_, String>(builder)
    };

    let builder_with_minimum_amount = make_builder(
        Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?,
    )?;
    let fee_amount = builder_with_minimum_amount
        .get_fee(&fee_rule)
        .map_err(|e| format!("Failed to estimate exact-note migration fee: {e}"))?;
    if selected_value <= fee_amount {
        return Ok(None);
    }
    let migrated_amount: Zatoshis = (selected_value - fee_amount)
        .ok_or_else(|| "Exact-note migration amount underflow".to_string())?;
    if timing_policy != super::migration::MigrationTimingPolicy::Immediate
        && !super::migration::is_zip318_canonical_denomination(u64::from(migrated_amount))
    {
        return Err(
            "Exact-note migration amount is not a ZIP 318 canonical denomination".to_string(),
        );
    }
    let builder = if migrated_amount
        == Zatoshis::from_u64(MIN_IRONWOOD_MIGRATION_OUTPUT_ZATOSHI)
            .map_err(|_| "Bad migration minimum output")?
    {
        builder_with_minimum_amount
    } else {
        make_builder(migrated_amount)?
    };

    let build_result = builder
        .build_for_pczt(rand_core::OsRng, &fee_rule)
        .map_err(|e| format!("Build exact-note migration PCZT failed: {e}"))?;
    let expiry_height = u32::from(build_result.pczt_parts.expiry_height);
    let built_pczt = pczt_from_build_result(
        build_result,
        network,
        account_derivation,
        orchard_inputs.len(),
        0,
    )?;
    Ok(Some(CreatedMigrationPczt {
        part_index: migration_index.saturating_sub(1),
        id: format!("migration-{migration_index}"),
        base_pczt: built_pczt.bytes,
        orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
        pczt_with_proofs: None,
        redacted_pczt: built_pczt.redacted_bytes,
        target_height: target_height_u32,
        anchor_boundary_height: Some(anchor_boundary_height),
        expiry_height,
        fee_zatoshi: u64::from(fee_amount),
        migrated_zatoshi: u64::from(migrated_amount),
        selected_note: note_ref.clone(),
    }))
}
