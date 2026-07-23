fn prepared_refs_from_denomination_split(
    direct_refs: &[super::migration::PreparedOrchardNoteRef],
    stages: &[CreatedDenominationStagePczt],
) -> Vec<super::migration::PreparedOrchardNoteRef> {
    let mut prepared_refs = direct_refs.to_vec();
    prepared_refs.extend(stages
        .iter()
        .flat_map(|stage| {
            stage
                .outputs
                .iter()
                .filter(|output| {
                    output.kind == super::migration::DenominationStageOutputKind::Migration
                })
                .map(|output| super::migration::PreparedOrchardNoteRef {
                    txid_hex: stage.expected_txid_hex.clone(),
                    output_index: output.output_index,
                    value_zatoshi: output.value_zatoshi,
                    note_version: output.note_version,
                    nullifier_hex: None,
                })
        })
    );
    prepared_refs.sort_by(|left, right| {
        right
            .value_zatoshi
            .cmp(&left.value_zatoshi)
            .then_with(|| left.txid_hex.cmp(&right.txid_hex))
            .then_with(|| left.output_index.cmp(&right.output_index))
    });
    prepared_refs
}

fn signed_denomination_stage_inserts(
    stages: &[CreatedDenominationStagePczt],
    signed_by_id: &HashMap<String, Vec<pczt::roles::signer::SpendAuthSignature>>,
) -> Result<Vec<super::migration::DenominationStageInsert>, String> {
    stages
        .iter()
        .enumerate()
        .map(|(stage_index, stage)| {
            let sigs = signed_by_id
                .get(&stage.id)
                .ok_or_else(|| format!("Keystone result missing {}", stage.id))?
                .clone();
            super::pczt::preflight_orchard_spend_auth_signatures(&stage.base_pczt, &sigs)?;
            let raw_tx = if stage.deferred {
                None
            } else {
                let proofed = stage
                    .pczt_with_proofs
                    .as_ref()
                    .ok_or("Keystone denomination root proofs are not ready")?;
                let extracted = super::pczt::apply_sigs_and_extract(proofed, &sigs, None, None)?;
                if extracted.txid.to_string() != stage.expected_txid_hex {
                    return Err(format!(
                        "Denomination root {} extracted an unexpected txid",
                        stage.id
                    ));
                }
                Some(extracted.raw_tx)
            };
            Ok(super::migration::DenominationStageInsert {
                stage_index: u32::try_from(stage_index)
                    .map_err(|_| "Denomination stage index overflow".to_string())?,
                base_pczt: stage.base_pczt.clone(),
                sigs,
                raw_tx,
                expected_txid_hex: stage.expected_txid_hex.clone(),
                target_height: stage.target_height,
                expiry_height: stage.expiry_height,
                fee_zatoshi: stage.fee_zatoshi,
                status: if stage.deferred {
                    super::migration::DenominationStageStatus::AwaitingInputs
                } else {
                    super::migration::DenominationStageStatus::Pending
                },
                inputs: stage.inputs.clone(),
                outputs: stage.outputs.clone(),
            })
        })
        .collect()
}

fn pczt_from_build_result(
    build_result: zcash_primitives::transaction::builder::PcztResult<WalletNetwork>,
    network: WalletNetwork,
    account_derivation: Option<&zcash_client_backend::data_api::Zip32Derivation>,
    orchard_spend_count: usize,
    orchard_change_output_count: usize,
) -> Result<BuiltPczt, String> {
    use pczt::roles::{creator::Creator, io_finalizer::IoFinalizer, updater::Updater};

    let orchard_spend_action_indices = (0..orchard_spend_count)
        .map(|i| {
            build_result
                .orchard_meta
                .spend_action_index(i)
                .ok_or_else(|| "Orchard spend action index missing".to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;
    let mut orchard_derivation_action_indices =
        Vec::with_capacity(orchard_spend_count + orchard_change_output_count);
    orchard_derivation_action_indices.extend(orchard_spend_action_indices.iter().copied());
    for i in 0..orchard_change_output_count {
        let index = build_result
            .orchard_meta
            .output_action_index(i)
            .ok_or_else(|| "Orchard change output action index missing".to_string())?;
        if !orchard_derivation_action_indices.contains(&index) {
            orchard_derivation_action_indices.push(index);
        }
    }
    let orchard_derivation_actions = orchard_derivation_action_indices
        .iter()
        .copied()
        .collect::<HashSet<_>>();
    let created = Creator::build_from_parts(build_result.pczt_parts).ok_or("Build PCZT failed")?;
    let io_finalized = IoFinalizer::new(created)
        .finalize_io()
        .map_err(|e| format!("Finalize PCZT IO: {e:?}"))?;

    let pczt = Updater::new(io_finalized)
        .update_orchard_with(|mut updater| {
            if let Some(derivation) = account_derivation {
                for index in &orchard_derivation_actions {
                    updater.update_action_with(*index, |mut action_updater| {
                        action_updater.set_spend_zip32_derivation(
                            orchard::pczt::Zip32Derivation::parse(
                                derivation.seed_fingerprint().to_bytes(),
                                vec![
                                    zip32::ChildIndex::hardened(32).index(),
                                    zip32::ChildIndex::hardened(network.network_type().coin_type())
                                        .index(),
                                    zip32::ChildIndex::hardened(u32::from(
                                        derivation.account_index(),
                                    ))
                                    .index(),
                                ],
                            )
                            .expect("valid ZIP32 derivation"),
                        );
                        Ok(())
                    })?;
                }
            }
            Ok(())
        })
        .map_err(|e| format!("Update Orchard PCZT derivations: {e:?}"))?
        .finish();

    let bytes = pczt
        .serialize()
        .map_err(|e| format!("Serialize built PCZT: {e:?}"))?;
    let redacted_bytes = super::pczt::redact_pczt_for_batch_signer(&bytes)?;

    Ok(BuiltPczt {
        bytes,
        redacted_bytes,
        // Post-NU6.3 Orchard change outputs are paired with wallet-controlled
        // zero-valued spends. They are not IO-finalizer dummies, so software
        // signing must authorize their actions along with the requested input
        // spends. This union is also the set that receives derivation metadata
        // for hardware signing above.
        orchard_spend_action_indices: orchard_derivation_action_indices,
    })
}

fn predicted_note_from_split_action(
    action: &orchard::pczt::Action,
    value_zatoshi: u64,
) -> Result<orchard::Note, String> {
    let recipient = action
        .output()
        .recipient()
        .as_ref()
        .copied()
        .ok_or("Denomination split output recipient missing")?;
    let rseed = action
        .output()
        .rseed()
        .as_ref()
        .copied()
        .ok_or("Denomination split output rseed missing")?;
    let rho = orchard::note::Rho::from_bytes(&action.spend().nullifier().to_bytes())
        .into_option()
        .ok_or("Denomination split output rho is invalid")?;
    orchard::Note::from_parts(
        recipient,
        orchard::value::NoteValue::from_raw(value_zatoshi),
        rho,
        rseed,
        orchard::note::NoteVersion::V2,
    )
    .into_option()
    .ok_or("Denomination split output note is invalid".to_string())
}

fn synthetic_orchard_anchor_and_witnesses(
    notes: &[orchard::Note],
) -> Result<(orchard::Anchor, Vec<orchard::tree::MerklePath>), String> {
    use incrementalmerkletree::{frontier::CommitmentTree, witness::IncrementalWitness};

    if notes.is_empty() {
        return Err("Synthetic Orchard witness set is empty".to_string());
    }
    let mut tree = CommitmentTree::<orchard::tree::MerkleHashOrchard, 32>::empty();
    let mut witnesses = Vec::<IncrementalWitness<orchard::tree::MerkleHashOrchard, 32>>::new();
    for note in notes {
        let cmx: orchard::note::ExtractedNoteCommitment = note.commitment().into();
        let leaf = orchard::tree::MerkleHashOrchard::from_cmx(&cmx);
        for witness in &mut witnesses {
            witness
                .append(leaf)
                .map_err(|_| "Extend synthetic Orchard witness failed".to_string())?;
        }
        tree.append(leaf)
            .map_err(|_| "Append synthetic Orchard commitment failed".to_string())?;
        witnesses.push(
            IncrementalWitness::from_tree(tree.clone())
                .ok_or("Create synthetic Orchard witness failed")?,
        );
    }
    let anchor = witnesses
        .first()
        .ok_or("Synthetic Orchard witness set is empty")?
        .root()
        .into();
    let paths = witnesses
        .into_iter()
        .map(|witness| {
            witness
                .path()
                .map(Into::into)
                .ok_or_else(|| "Complete synthetic Orchard witness failed".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok((anchor, paths))
}

fn create_padded_orchard_denomination_pczts(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<CreatedPaddedDenominationPczts>, String> {
    let mut db = open_wallet_db(db_path, network)?;
    let fee_rule = ConservativeZip317FeeRule;
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
    let recipient_scope = orchard::keys::Scope::Internal;
    let recipient = orchard_fvk.address_at(0u32, recipient_scope);
    let internal_ovk = Some(orchard_fvk.to_ovk(recipient_scope));
    let memo = MemoBytes::empty();

    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before preparing denominations")?;
    let mut orchard_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    orchard_notes.sort_by_key(|note| (format!("{}", note.txid()), note.output_index()));
    if orchard_notes.is_empty() {
        return Ok(None);
    }
    let (orchard_anchor, orchard_inputs) =
        orchard_witnesses(&mut db, anchor_height, &orchard_notes)?;
    let input_values = orchard_notes
        .iter()
        .map(|note| note.note_value().map(u64::from).map_err(|e| format!("{e}")))
        .collect::<Result<Vec<_>, String>>()?;
    let input_refs = orchard_notes
        .iter()
        .map(|received| super::migration::DenominationStageInputRef {
            txid_hex: format!("{}", received.txid()),
            output_index: received.output_index() as u32,
            value_zatoshi: u64::from(
                received
                    .note_value()
                    .expect("Orchard V2 input value was validated above"),
            ),
            note_version: 2,
            nullifier_hex: Some(hex::encode(
                received.note().nullifier(&orchard_fvk).to_bytes(),
            )),
        })
        .collect::<Vec<_>>();

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
    )?
    .ok_or("Insufficient spendable Orchard funds for denomination split")?;

    let padded_bundle_type = orchard::builder::BundleType::Transactional {
        bundle_required: false,
        pad_to_minimum: Some(
            u8::try_from(super::migration::DENOMINATION_SPLIT_ACTIONS)
                .map_err(|_| "Padded denomination action count exceeds u8".to_string())?,
        ),
    };
    let mut stages = Vec::with_capacity(padded_plan.stages.len());
    let mut predicted_migration_notes =
        Vec::with_capacity(padded_plan.denominations.migration_outputs.len());
    let mut direct_prepared_refs =
        Vec::with_capacity(padded_plan.direct_migration_inputs.len());
    let mut predicted_stage_outputs = BTreeMap::<(usize, usize), PredictedMigrationNote>::new();

    for direct in &padded_plan.direct_migration_inputs {
        let received = orchard_notes
            .get(direct.input_index)
            .ok_or("Direct migration input index is out of range")?;
        let value_zatoshi = received
            .note_value()
            .map(u64::from)
            .map_err(|e| format!("Direct migration input value is invalid: {e}"))?;
        if value_zatoshi != direct.value_zatoshi {
            return Err("Direct migration input value changed after planning".to_string());
        }
        let prepared_ref = input_refs
            .get(direct.input_index)
            .ok_or("Direct migration input reference is out of range")?
            .clone();
        direct_prepared_refs.push(super::migration::PreparedOrchardNoteRef {
            txid_hex: prepared_ref.txid_hex.clone(),
            output_index: prepared_ref.output_index,
            value_zatoshi: prepared_ref.value_zatoshi,
            note_version: prepared_ref.note_version,
            nullifier_hex: prepared_ref.nullifier_hex.clone(),
        });
        predicted_migration_notes.push((
            direct.part_index,
            PredictedMigrationNote {
                txid_hex: prepared_ref.txid_hex,
                output_index: prepared_ref.output_index,
                value_zatoshi,
                note: *received.note(),
            },
        ));
    }

    for (stage_index, stage_plan) in padded_plan.stages.iter().enumerate() {
        let mut stage_notes = Vec::new();
        let mut stage_input_refs = Vec::new();
        let mut root_inputs = Vec::new();
        let mut deferred = false;
        for input in &stage_plan.inputs {
            match input {
                super::migration::SplitStageInput::Original {
                    input_index,
                    value_zatoshi,
                } => {
                    let (note, witness) = orchard_inputs
                        .get(*input_index)
                        .ok_or("Denomination stage input index is out of range")?;
                    let input_ref = input_refs
                        .get(*input_index)
                        .ok_or("Denomination stage input reference is out of range")?;
                    if input_ref.value_zatoshi != *value_zatoshi {
                        return Err(
                            "Denomination stage input value changed after planning".to_string()
                        );
                    }
                    stage_notes.push(*note);
                    root_inputs.push((*note, witness.clone()));
                    stage_input_refs.push(input_ref.clone());
                }
                super::migration::SplitStageInput::Prior {
                    stage_index: prior_stage_index,
                    output_index,
                    value_zatoshi,
                } => {
                    deferred = true;
                    let prior = predicted_stage_outputs
                        .get(&(*prior_stage_index, *output_index))
                        .ok_or("Denomination stage references an unknown prior output")?;
                    if prior.value_zatoshi != *value_zatoshi {
                        return Err(
                            "Denomination prior output value changed after planning".to_string()
                        );
                    }
                    stage_notes.push(prior.note);
                    stage_input_refs.push(super::migration::DenominationStageInputRef {
                        txid_hex: prior.txid_hex.clone(),
                        output_index: prior.output_index,
                        value_zatoshi: prior.value_zatoshi,
                        note_version: 2,
                        nullifier_hex: Some(hex::encode(
                            prior.note.nullifier(&orchard_fvk).to_bytes(),
                        )),
                    });
                }
            }
        }
        if stage_notes.is_empty() {
            return Err("Denomination stage has no Orchard inputs".to_string());
        }

        let (stage_anchor, stage_inputs) = if deferred {
            let (anchor, witnesses) = synthetic_orchard_anchor_and_witnesses(&stage_notes)?;
            (
                anchor,
                stage_notes
                    .iter()
                    .copied()
                    .zip(witnesses.into_iter())
                    .collect::<Vec<_>>(),
            )
        } else {
            (orchard_anchor, root_inputs)
        };

        let output_values = stage_plan
            .outputs
            .iter()
            .map(|output| output.value_zatoshi)
            .collect::<Vec<_>>();
        let builder = make_orchard_split_builder_with_type(
            network,
            target_height.into(),
            stage_anchor,
            &stage_inputs,
            &orchard_fvk,
            internal_ovk.clone(),
            recipient,
            &output_values,
            &memo,
            padded_bundle_type,
        )?;
        let exact_fee = builder
            .get_fee(&fee_rule)
            .map_err(|e| format!("Failed to verify padded denomination fee: {e}"))?;
        if exact_fee != split_fee || u64::from(exact_fee) != stage_plan.fee_zatoshi {
            return Err("Padded denomination stage fee changed after planning".to_string());
        }
        let build_result = builder
            .build_for_pczt(rand_core::OsRng, &fee_rule)
            .map_err(|e| format!("Build padded denomination PCZT failed: {e}"))?;
        let expiry_height = u32::from(build_result.pczt_parts.expiry_height);
        let orchard_bundle = build_result
            .pczt_parts
            .orchard
            .as_ref()
            .ok_or("Padded denomination PCZT missing Orchard bundle")?;
        if orchard_bundle.actions().len() != super::migration::DENOMINATION_SPLIT_ACTIONS {
            return Err(format!(
                "Padded denomination stage built {} actions instead of {}",
                orchard_bundle.actions().len(),
                super::migration::DENOMINATION_SPLIT_ACTIONS
            ));
        }

        let mut predicted_outputs = Vec::with_capacity(output_values.len());
        for (logical_output, value_zatoshi) in output_values.iter().enumerate() {
            let action_index = build_result
                .orchard_meta
                .output_action_index(logical_output)
                .ok_or("Padded denomination output action index missing")?;
            let action = orchard_bundle
                .actions()
                .get(action_index)
                .ok_or("Padded denomination output action missing")?;
            predicted_outputs.push((
                action_index as u32,
                *value_zatoshi,
                predicted_note_from_split_action(action, *value_zatoshi)?,
            ));
        }

        let built_pczt = pczt_from_build_result(
            build_result,
            network,
            account_derivation,
            stage_inputs.len(),
            output_values.len(),
        )?;
        let expected_txid = super::pczt::txid_from_io_finalized_pczt(&built_pczt.bytes)?;
        let expected_txid_hex = expected_txid.to_string();
        let mut stage_output_refs = Vec::with_capacity(predicted_outputs.len());
        for (logical_output_index, (terminal, (output_index, value_zatoshi, note))) in stage_plan
            .outputs
            .iter()
            .zip(predicted_outputs.iter())
            .enumerate()
        {
            let kind = match terminal.kind {
                super::migration::SplitTerminalKind::Migration => {
                    super::migration::DenominationStageOutputKind::Migration
                }
                super::migration::SplitTerminalKind::OrchardChange => {
                    super::migration::DenominationStageOutputKind::Change
                }
                super::migration::SplitTerminalKind::Continuation => {
                    super::migration::DenominationStageOutputKind::Continuation
                }
            };
            let part_index = terminal
                .part_index
                .map(|part_index| {
                    u32::try_from(part_index)
                        .map_err(|_| "Migration denomination part index exceeds u32".to_string())
                })
                .transpose()?;
            stage_output_refs.push(super::migration::DenominationStageOutputRef {
                output_index: *output_index,
                value_zatoshi: *value_zatoshi,
                note_version: 2,
                kind,
                part_index,
            });
            let predicted = PredictedMigrationNote {
                txid_hex: expected_txid_hex.clone(),
                output_index: *output_index,
                value_zatoshi: *value_zatoshi,
                note: *note,
            };
            predicted_stage_outputs.insert(
                (stage_index, logical_output_index),
                predicted.clone(),
            );
            if let Some(part_index) = terminal.part_index {
                if terminal.kind != super::migration::SplitTerminalKind::Migration {
                    return Err(
                        "Only migration outputs may carry a migration part index".to_string()
                    );
                }
                predicted_migration_notes.push((
                    part_index,
                    predicted,
                ));
            }
        }

        stages.push(CreatedDenominationStagePczt {
            id: if stage_index == 0 {
                "denominations".to_string()
            } else {
                format!("denominations-{}", stage_index + 1)
            },
            base_pczt: built_pczt.bytes,
            orchard_spend_action_indices: built_pczt.orchard_spend_action_indices,
            redacted_pczt: built_pczt.redacted_bytes,
            pczt_with_proofs: None,
            expected_txid_hex,
            target_height: target_height.into(),
            expiry_height,
            fee_zatoshi: u64::from(split_fee),
            deferred,
            inputs: stage_input_refs,
            outputs: stage_output_refs,
        });
    }
    predicted_migration_notes.sort_by_key(|(logical_index, _)| *logical_index);
    let predicted_notes = predicted_migration_notes
        .into_iter()
        .map(|(_, note)| note)
        .collect::<Vec<_>>();
    if predicted_notes.len() != padded_plan.denominations.migration_outputs.len() {
        return Err("Padded denomination plan did not build every migration output".to_string());
    }

    Ok(Some(CreatedPaddedDenominationPczts {
        stages,
        predicted_notes,
        direct_prepared_refs,
        total_migratable_zatoshi: padded_plan.denominations.total_migratable_zatoshi,
        plan: padded_plan.denominations,
    }))
}
