use super::*;

const MIN_IRONWOOD_OUTPUT_ZATOSHI: u64 = 1;
const MIN_ORCHARD_ACTION_COUNT: usize = 2;

struct BuiltPczt {
    bytes: Vec<u8>,
    orchard_spend_action_indices: Vec<usize>,
}

fn plan_for_values(
    network: WalletNetwork,
    target_height: BlockHeight,
    input_values: impl IntoIterator<Item = u64>,
) -> Result<Option<OrchardMigrationImmediatePlan>, String> {
    let positive_values = input_values
        .into_iter()
        .filter(|value| *value > 0)
        .collect::<Vec<_>>();
    if positive_values.is_empty() {
        return Ok(None);
    }
    let total_input_zatoshi = positive_values.iter().try_fold(0u64, |total, value| {
        total
            .checked_add(*value)
            .ok_or_else(|| "Immediate migration input overflow".to_string())
    })?;
    let fee_zatoshi = u64::from(
        ConservativeZip317FeeRule
            .fee_required(
                &network,
                target_height,
                std::iter::empty::<TransparentInputSize>(),
                std::iter::empty::<usize>(),
                0,
                0,
                positive_values.len().max(MIN_ORCHARD_ACTION_COUNT),
                1,
            )
            .map_err(|e| format!("Estimate Immediate migration fee failed: {e}"))?,
    );
    let Some(migrated_zatoshi) = total_input_zatoshi.checked_sub(fee_zatoshi) else {
        return Ok(None);
    };
    if migrated_zatoshi < MIN_IRONWOOD_OUTPUT_ZATOSHI {
        return Ok(None);
    }
    Ok(Some(OrchardMigrationImmediatePlan {
        total_input_zatoshi,
        fee_zatoshi,
        migrated_zatoshi,
        input_note_count: u32::try_from(positive_values.len())
            .map_err(|_| "Immediate migration note count exceeds u32".to_string())?,
    }))
}

pub(crate) fn get_plan(
    db_path: &str,
    network: WalletNetwork,
    account_uuid: &str,
) -> Result<Option<OrchardMigrationImmediatePlan>, String> {
    let db = open_wallet_db_for_read(db_path, network)?;
    let account_id = parse_account_uuid(account_uuid)?;
    let (target_height, anchor_height) = db
        .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
        .map_err(|e| format!("Failed to read anchor height: {e}"))?
        .ok_or("Wallet must sync before estimating Immediate migration")?;
    let orchard_notes =
        select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
    let input_values = orchard_notes
        .iter()
        .map(|note| note.note_value().map(u64::from).map_err(|e| format!("{e}")))
        .collect::<Result<Vec<_>, String>>()?;
    plan_for_values(network, target_height.into(), input_values)
}

pub(crate) async fn migrate(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    account_uuid: &str,
    seed: SecretVec<u8>,
    approved_plan: OrchardMigrationImmediatePlan,
) -> Result<IronwoodMigrationResult, String> {
    let _migration_guard = ActiveIronwoodMigration::acquire(db_path, account_uuid)?;
    if orchard_migration_active(db_path, network, account_uuid)? {
        return Err("An Ironwood migration is already in progress for this account".to_string());
    }

    let (base_pczt, orchard_spend_action_indices, fee_zatoshi, migrated_zatoshi) =
        with_wallet_db_write_lock("send.immediate_migration.build", || {
            let mut db = open_wallet_db(db_path, network)?;
            let account_id = parse_account_uuid(account_uuid)?;
            let account = db
                .get_account(account_id)
                .map_err(|e| format!("{e}"))?
                .ok_or("Account not found")?;
            let ufvk = account
                .ufvk()
                .ok_or("Account cannot create an Immediate migration")?;
            let account_derivation = account.source().key_derivation();
            let orchard_fvk = ufvk
                .orchard()
                .cloned()
                .ok_or("Orchard viewing key not available")?;
            let recipient = orchard_fvk.address_at(0u32, orchard::keys::Scope::Internal);
            let internal_ovk = Some(orchard_fvk.to_ovk(orchard::keys::Scope::Internal));
            let (target_height, anchor_height) = db
                .get_target_and_anchor_heights(ConfirmationsPolicy::default().trusted())
                .map_err(|e| format!("Failed to read anchor height: {e}"))?
                .ok_or("Wallet must sync before migrating")?;
            let orchard_notes =
                select_all_orchard_v2_notes(&db, account_id, BlockHeight::from(anchor_height))?;
            let valued_notes = orchard_notes
                .into_iter()
                .map(|note| {
                    let value = note
                        .note_value()
                        .map(u64::from)
                        .map_err(|e| format!("{e}"))?;
                    Ok((note, value))
                })
                .collect::<Result<Vec<_>, String>>()?;
            let plan = plan_for_values(
                network,
                target_height.into(),
                valued_notes.iter().map(|(_, value)| *value),
            )?
            .ok_or("No spendable Orchard notes are available for Immediate migration")?;
            if plan != approved_plan {
                return Err(
                    "Immediate migration plan changed. Review the updated amount and fee."
                        .to_string(),
                );
            }
            let orchard_notes = valued_notes
                .into_iter()
                .filter_map(|(note, value)| (value > 0).then_some(note))
                .collect::<Vec<_>>();
            let (orchard_anchor, orchard_inputs) = immediate_orchard_witnesses(
                &mut db,
                network,
                BlockHeight::from(anchor_height),
                &orchard_notes,
            )?;
            let fee_rule = ConservativeZip317FeeRule;
            let make_builder = |amount: Zatoshis| {
                let mut builder = immediate_builder(
                    network,
                    BlockHeight::from(target_height),
                    orchard_anchor.clone(),
                );
                for (note, merkle_path) in &orchard_inputs {
                    builder
                        .add_orchard_spend::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                            orchard_fvk.clone(),
                            *note,
                            merkle_path.clone(),
                        )
                        .map_err(|e| format!("Add Immediate Orchard spend failed: {e}"))?;
                }
                builder
                    .add_ironwood_output::<<ConservativeZip317FeeRule as FeeRule>::Error>(
                        internal_ovk.clone(),
                        recipient,
                        amount,
                        MemoBytes::empty(),
                    )
                    .map_err(|e| format!("Add Immediate Ironwood output failed: {e}"))?;
                Ok::<_, String>(builder)
            };
            let minimum = Zatoshis::from_u64(MIN_IRONWOOD_OUTPUT_ZATOSHI)
                .map_err(|_| "Bad Immediate migration minimum output")?;
            let fee = make_builder(minimum)?
                .get_fee(&fee_rule)
                .map_err(|e| format!("Estimate Immediate migration fee failed: {e}"))?;
            if u64::from(fee) != plan.fee_zatoshi {
                return Err("Immediate migration fee changed while building".to_string());
            }
            let amount = Zatoshis::from_u64(plan.migrated_zatoshi)
                .map_err(|_| "Bad Immediate migration output amount")?;
            let built = pczt_from_build_result(
                make_builder(amount)?
                    .build_for_pczt(rand_core::OsRng, &fee_rule)
                    .map_err(|e| format!("Build Immediate migration PCZT failed: {e}"))?,
                network,
                account_derivation,
                orchard_inputs.len(),
            )?;
            Ok::<_, String>((
                built.bytes,
                built.orchard_spend_action_indices,
                plan.fee_zatoshi,
                plan.migrated_zatoshi,
            ))
        })?;
    let usk = derive_usk(db_path, network, account_uuid, seed)?;
    let signed = sign_pczt(&base_pczt, &orchard_spend_action_indices, &usk)?;
    let sigs =
        super::super::pczt::extract_required_compact_sigs_from_signed_pczt(&base_pczt, &signed)?;
    super::super::pczt::preflight_orchard_spend_auth_signatures(&base_pczt, &sigs)?;
    let proofed = super::super::pczt::add_proofs_to_pczt(&base_pczt, None, None)?;
    let extracted = super::super::pczt::apply_sigs_and_extract(&proofed, &sigs, None, None)?;
    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| format!("Connect to lightwalletd for Immediate migration failed: {e}"))?;
    let response = match crate::wallet::sync_engine::send_transaction_with_status(
        &mut client,
        &extracted.raw_tx,
    )
    .await
    {
        Ok(response) => response,
        Err(status) if status.code() == Code::DeadlineExceeded => {
            let storage_message = match store_transaction(db_path, network, &extracted.raw_tx) {
                Ok(()) => {
                    "The transaction was stored locally and will retry automatically during sync."
                        .to_string()
                }
                Err(error) => format!("Local tracking also failed: {error}"),
            };
            return Ok(IronwoodMigrationResult {
                txids: extracted.txid.to_string(),
                status: CreatedBroadcastResult::PENDING_BROADCAST.to_string(),
                broadcasted_count: 0,
                total_count: 1,
                message: Some(format!(
                    "The Immediate migration broadcast timed out and may already be on the network. {storage_message}"
                )),
                fee_zatoshi,
                migrated_zatoshi,
            });
        }
        Err(status) => {
            return Err(format!(
                "Immediate migration broadcast failed before acceptance: {status}"
            ));
        }
    };
    if let Some(error) = super::super::broadcast::send_response_rejection_error(&response) {
        return Err(error);
    }
    let storage_error = store_transaction(db_path, network, &extracted.raw_tx).err();

    Ok(IronwoodMigrationResult {
        txids: extracted.txid.to_string(),
        status: super::super::migration::PHASE_BROADCASTING.to_string(),
        broadcasted_count: 1,
        total_count: 1,
        message: storage_error.map(|error| {
            format!(
                "The Immediate migration was accepted, but local tracking failed: {error}. Sync will recover the transaction."
            )
        }),
        fee_zatoshi,
        migrated_zatoshi,
    })
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

fn immediate_builder(
    network: WalletNetwork,
    target_height: BlockHeight,
    orchard_anchor: orchard::Anchor,
) -> Builder<WalletNetwork, ()> {
    Builder::new(
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
    .with_expiry_height(zcash_pool_migration_backend::scheduling::expiry_height(
        target_height,
    ))
}

fn orchard_witnesses(
    db: &mut WalletDatabase,
    anchor_height: BlockHeight,
    orchard_notes: &[ReceivedNote<ReceivedNoteId, orchard::Note>],
) -> Result<
    (
        orchard::Anchor,
        Vec<(orchard::Note, orchard::tree::MerklePath)>,
    ),
    String,
> {
    type WitnessError = WalletError<
        (),
        commitment_tree::Error,
        (),
        <ConservativeZip317FeeRule as FeeRule>::Error,
        (),
        ReceivedNoteId,
    >;

    let result: Result<_, WitnessError> = db.with_orchard_tree_mut(|orchard_tree| {
        let anchor = orchard_tree
            .root_at_checkpoint_id(&anchor_height)?
            .ok_or(ProposalError::AnchorNotFound(anchor_height))?
            .into();
        let inputs = orchard_notes
            .iter()
            .map(|selected| {
                orchard_tree
                    .witness_at_checkpoint_id_caching(
                        selected.note_commitment_tree_position(),
                        &anchor_height,
                    )
                    .and_then(|witness| {
                        witness.ok_or(ShardTreeError::Query(QueryError::CheckpointPruned))
                    })
                    .map(|merkle_path| (*selected.note(), merkle_path.into()))
                    .map_err(WalletError::from)
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok((anchor, inputs))
    });
    result.map_err(|e| format!("Read Orchard witnesses: {e:?}"))
}

fn immediate_orchard_witnesses(
    db: &mut WalletDatabase,
    network: WalletNetwork,
    anchor_height: BlockHeight,
    orchard_notes: &[ReceivedNote<ReceivedNoteId, orchard::Note>],
) -> Result<
    (
        orchard::Anchor,
        Vec<(orchard::Note, orchard::tree::MerklePath)>,
    ),
    String,
> {
    if network != WalletNetwork::Regtest {
        return orchard_witnesses(db, anchor_height, orchard_notes);
    }

    let newest_note_height = orchard_notes
        .iter()
        .filter_map(|note| note.mined_height())
        .map(u32::from)
        .max()
        .ok_or("Immediate migration note mined height unavailable")?;
    let anchor_height = u32::from(anchor_height);
    let oldest_candidate = anchor_height
        .saturating_sub(zcash_pool_migration_backend::scheduling::ANCHOR_AGE_CAP)
        .max(newest_note_height);
    let mut last_error = None;
    for checkpoint in (oldest_candidate..=anchor_height).rev() {
        match orchard_witnesses(db, BlockHeight::from(checkpoint), orchard_notes) {
            Ok(result) => return Ok(result),
            Err(error) if witness_not_ready(&error) => last_error = Some(error),
            Err(error) => return Err(error),
        }
    }
    Err(last_error.unwrap_or_else(|| {
        "Read Orchard witnesses: no regtest checkpoint at or before the anchor height".to_string()
    }))
}

fn witness_not_ready(error: &str) -> bool {
    let lower = error.to_ascii_lowercase();
    lower.contains("anchornotfound")
        || lower.contains("notcontained")
        || lower.contains("checkpoint")
        || lower.contains("commitmenttree")
}

fn pczt_from_build_result(
    build_result: zcash_primitives::transaction::builder::PcztResult<WalletNetwork>,
    network: WalletNetwork,
    account_derivation: Option<&zcash_client_backend::data_api::Zip32Derivation>,
    orchard_spend_count: usize,
) -> Result<BuiltPczt, String> {
    use pczt::roles::{creator::Creator, io_finalizer::IoFinalizer, updater::Updater};

    let orchard_spend_action_indices = (0..orchard_spend_count)
        .map(|index| {
            build_result
                .orchard_meta
                .spend_action_index(index)
                .ok_or_else(|| "Orchard spend action index missing".to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;
    let created = Creator::build_from_parts(build_result.pczt_parts).ok_or("Build PCZT failed")?;
    let io_finalized = IoFinalizer::new(created)
        .finalize_io()
        .map_err(|e| format!("Finalize PCZT IO: {e:?}"))?;
    let pczt = Updater::new(io_finalized)
        .update_orchard_with(|mut updater| {
            if let Some(derivation) = account_derivation {
                for index in &orchard_spend_action_indices {
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
    Ok(BuiltPczt {
        bytes: pczt
            .serialize()
            .map_err(|e| format!("Serialize built PCZT: {e:?}"))?,
        orchard_spend_action_indices,
    })
}

fn derive_usk(
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
    let account_index = account
        .source()
        .key_derivation()
        .ok_or("No key derivation")?
        .account_index();
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), account_index)
        .map_err(|e| format!("USK derivation failed: {e:?}"))?;
    let derived_account_id = db
        .get_account_for_ufvk(&usk.to_unified_full_viewing_key())
        .map_err(|e| format!("{e}"))?
        .ok_or("Spending key not recognized")?
        .id();
    if derived_account_id != account_id {
        return Err("Spending key does not match migration account".to_string());
    }
    Ok(usk)
}

fn sign_pczt(
    pczt_bytes: &[u8],
    orchard_spend_action_indices: &[usize],
    usk: &UnifiedSpendingKey,
) -> Result<Vec<u8>, String> {
    use pczt::roles::signer::Signer;

    if orchard_spend_action_indices.is_empty() {
        return Err("Immediate migration PCZT has no Orchard spend actions".to_string());
    }
    let pczt = pczt::Pczt::parse(pczt_bytes)
        .map_err(|e| format!("Parse Immediate migration PCZT: {e:?}"))?;
    let orchard_ask = orchard::keys::SpendAuthorizingKey::from(usk.orchard());
    let mut signer =
        Signer::new(pczt).map_err(|e| format!("Create Immediate migration signer: {e:?}"))?;
    for index in orchard_spend_action_indices {
        signer
            .sign_orchard(*index, &orchard_ask)
            .map_err(|e| format!("Sign Immediate migration action {index}: {e:?}"))?;
    }
    signer
        .finish()
        .serialize()
        .map_err(|e| format!("Serialize signed Immediate migration PCZT: {e:?}"))
}

fn store_transaction(db_path: &str, network: WalletNetwork, raw_tx: &[u8]) -> Result<(), String> {
    super::super::transactions::decrypt_and_store_transaction(db_path, network, raw_tx, None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plan_ignores_zero_value_notes() {
        let target_height = BlockHeight::from_u32(2_000_000);
        let with_zero =
            plan_for_values(WalletNetwork::Test, target_height, [0, 2_000_000, 0]).unwrap();
        let without_zero =
            plan_for_values(WalletNetwork::Test, target_height, [2_000_000]).unwrap();
        assert_eq!(with_zero, without_zero);
    }
}
