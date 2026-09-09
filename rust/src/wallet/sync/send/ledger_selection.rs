//! Ledger-aware input budgets shared by fee quotes, Max, and stored proposals.
//! Selection is read-only; `propose_send` owns the eventual input locks.

use super::*;
use crate::wallet::ledger::serializer::{
    MAX_SHIELDED_ACTIONS, MAX_TRANSPARENT_INPUTS, MAX_TRANSPARENT_OUTPUTS,
};

pub(super) const CAPACITY_ERROR: &str = "VIZOR_LEDGER_CAPACITY";

pub(super) fn is_ledger(db: &WalletDatabase, account: AccountUuid) -> Result<bool, String> {
    let account = db
        .get_account(account)
        .map_err(|e| format!("Read signing account: {e}"))?
        .ok_or("Signing account not found")?;
    Ok(crate::wallet::keys::hardware_signer_kind(account.source())
        == Some(crate::wallet::keys::HardwareSignerKind::Ledger))
}

#[derive(Clone, Debug)]
pub(super) struct Input {
    pub id: ReceivedNoteId,
    pub value: u64,
}

pub(super) struct Selection {
    pub orchard: Vec<Input>,
    pub ironwood: Vec<Input>,
    pub excluded: BTreeSet<ReceivedNoteId>,
    pub was_capped: bool,
}

/// Eligible notes are selected by the SDK before ranking: confirmation, witness,
/// DB-lock, migration-lock, and caller-reservation rules remain authoritative.
pub(super) fn select(
    source: &ReservedInputSource<'_, WalletDatabase>,
    account: AccountUuid,
    pools: &[ShieldedPool],
    target: TargetHeight,
    network: WalletNetwork,
) -> Result<Selection, String> {
    let pools = pools
        .iter()
        .copied()
        .filter(|pool| *pool != ShieldedPool::Sapling)
        .collect::<Vec<_>>();
    let notes = source
        .select_spendable_notes(
            account,
            TargetValue::AllFunds(MaxSpendMode::MaxSpendable),
            &pools,
            target,
            confirmations_policy(),
            &[],
            LockFilter::Policy(&LockedInputPolicy::Exclude),
        )
        .map_err(|e| format!("Select Ledger inputs: {e}"))?;
    let rank = |notes: &[ReceivedNote<ReceivedNoteId, orchard::note::Note>]| {
        let mut inputs = notes
            .iter()
            .map(|note| Input {
                id: *note.internal_note_id(),
                value: note.note().value().inner(),
            })
            .collect::<Vec<_>>();
        // Stable tie-breaking makes quote and proposal selection deterministic.
        inputs.sort_by(|a, b| b.value.cmp(&a.value).then(a.id.cmp(&b.id)));
        inputs
    };
    let mut orchard = rank(notes.orchard());
    let mut ironwood = rank(notes.ironwood());
    // At NU6.3 legacy Orchard actions add spends and outputs. The shared
    // single-change strategy reserves one output even for an exact-balance send.
    let orchard_budget = if network.is_nu_active(consensus::NetworkUpgrade::Nu6_3, target.into()) {
        MAX_SHIELDED_ACTIONS - 1
    } else {
        MAX_SHIELDED_ACTIONS
    };
    let excluded = orchard
        .iter()
        .skip(orchard_budget)
        .chain(ironwood.iter().skip(MAX_SHIELDED_ACTIONS))
        .map(|input| input.id)
        .collect::<BTreeSet<_>>();
    let was_capped = !excluded.is_empty();
    orchard.truncate(orchard_budget);
    ironwood.truncate(MAX_SHIELDED_ACTIONS);
    Ok(Selection {
        orchard,
        ironwood,
        excluded,
        was_capped,
    })
}

pub(super) fn capacity_error(detail: impl std::fmt::Display) -> String {
    format!("{CAPACITY_ERROR}: {detail}")
}

fn action_count(
    network: WalletNetwork,
    target: BlockHeight,
    pool: orchard::ValuePool,
    inputs: usize,
    outputs: usize,
) -> Result<usize, String> {
    if inputs == 0 && outputs == 0 {
        return Ok(0);
    }
    let version = zcash_primitives::transaction::components::orchard::bundle_version_for_branch(
        consensus::BranchId::for_height(&network, target),
        pool,
    )
    .ok_or("Shielded pool is not active at the transaction height")?;
    orchard::builder::BundleType::DEFAULT
        .num_actions(version.default_flags(), inputs, outputs)
        .map_err(str::to_string)
}

/// Validate each transaction and each pool separately, including padding and
/// change. A TEX pair is not one combined input/action budget.
pub(super) fn validate<NoteRef>(
    proposal: &Proposal<WalletFeeRule, NoteRef>,
    network: WalletNetwork,
) -> Result<(), String> {
    for step in proposal.steps().iter() {
        if step.involves(PoolType::SAPLING) {
            return Err("Ledger does not support Sapling inputs or outputs".into());
        }
        let mut spends = [0usize; 2];
        if let Some(inputs) = step.shielded_inputs() {
            for note in inputs.notes().iter() {
                match note.note() {
                    Note::Orchard { pool, .. } => match pool {
                        orchard::ValuePool::Orchard => spends[0] += 1,
                        orchard::ValuePool::Ironwood => spends[1] += 1,
                    },
                    Note::Sapling(_) => return Err("Ledger does not support Sapling inputs".into()),
                }
            }
        }
        let mut outputs = [0usize; 2];
        let mut transparent_outputs = 0;
        for pool in step.payment_pools().values().copied().chain(
            step.balance()
                .proposed_change()
                .iter()
                .map(|change| change.output_pool()),
        ) {
            match pool {
                PoolType::ORCHARD => outputs[0] += 1,
                PoolType::IRONWOOD => outputs[1] += 1,
                PoolType::TRANSPARENT => transparent_outputs += 1,
                _ => return Err("Ledger does not support Sapling outputs".into()),
            }
        }
        // Prior-step ephemeral outputs are inputs of this step, not stored UTXOs.
        let transparent_inputs = step.transparent_inputs().len() + step.prior_step_inputs().len();
        if transparent_inputs > MAX_TRANSPARENT_INPUTS
            || transparent_outputs > MAX_TRANSPARENT_OUTPUTS
        {
            return Err(capacity_error("transparent input/output limit exceeded"));
        }
        for (index, pool) in [orchard::ValuePool::Orchard, orchard::ValuePool::Ironwood]
            .into_iter()
            .enumerate()
        {
            if action_count(
                network,
                BlockHeight::from(proposal.min_target_height()),
                pool,
                spends[index],
                outputs[index],
            )? > MAX_SHIELDED_ACTIONS
            {
                return Err(capacity_error("shielded action limit exceeded"));
            }
        }
    }
    Ok(())
}

/// Apply the device-app release guard after the normal V5/V6 re-proposal rule.
pub(super) fn validate_release_support<NoteRef>(
    proposal: &Proposal<WalletFeeRule, NoteRef>,
) -> Result<(), String> {
    for step in proposal.steps().iter() {
        let orchard_spend = step.shielded_inputs().is_some_and(|inputs| {
            inputs.notes().iter().any(|input| {
                matches!(
                    input.note(),
                    Note::Orchard {
                        pool: orchard::ValuePool::Orchard,
                        ..
                    }
                )
            })
        });
        let ironwood_output = step
            .payment_pools()
            .values()
            .any(|pool| *pool == PoolType::IRONWOOD)
            || step.balance().proposed_change().iter().any(|change| {
                change.output_pool() == PoolType::IRONWOOD && change.value() > Zatoshis::ZERO
            });
        crate::wallet::ledger::require_legacy_orchard_recovery_support(
            orchard_spend,
            ironwood_output,
        )?;
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Candidate {
    orchard: usize,
    ironwood: usize,
    amount: u64,
}

/// Count combinations, not note subsets: the largest k values are optimal for
/// each fixed per-pool count. Evaluating prefixes also excludes uneconomic dust.
fn best_prefix(
    orchard: &[u64],
    ironwood: &[u64],
    mut fee: impl FnMut(usize, usize) -> Result<Option<u64>, String>,
) -> Result<Option<Candidate>, String> {
    let sums = |values: &[u64]| -> Result<Vec<u64>, String> {
        let mut prefix = vec![0u64];
        for value in values.iter().take(MAX_SHIELDED_ACTIONS) {
            prefix.push(
                prefix
                    .last()
                    .unwrap()
                    .checked_add(*value)
                    .ok_or("Ledger input value overflow")?,
            );
        }
        Ok(prefix)
    };
    let orchard = sums(orchard)?;
    let ironwood = sums(ironwood)?;
    let mut best: Option<Candidate> = None;
    for (o, ov) in orchard.iter().enumerate() {
        for (i, iv) in ironwood.iter().enumerate() {
            if o + i == 0 {
                continue;
            }
            let Some(fee) = fee(o, i)? else {
                continue;
            };
            let Some(amount) = ov.checked_add(*iv).and_then(|total| total.checked_sub(fee)) else {
                continue;
            };
            if amount == 0 {
                continue;
            }
            if best.is_none_or(|b| {
                amount > b.amount || (amount == b.amount && o + i < b.orchard + b.ironwood)
            }) {
                best = Some(Candidate {
                    orchard: o,
                    ironwood: i,
                    amount,
                });
            }
        }
    }
    Ok(best)
}

pub(super) fn maximum(
    db_path: &str,
    db: &WalletDatabase,
    network: WalletNetwork,
    account: AccountUuid,
    account_uuid: &str,
    address: &str,
    memo: Option<&str>,
) -> Result<SendMaxEstimateResult, String> {
    let (target, _) = db
        .get_target_and_anchor_heights(confirmations_policy().trusted())
        .map_err(|e| format!("Read Ledger target height: {e}"))?
        .ok_or("Wallet must sync before estimating a Ledger transfer")?;
    let migration_locks =
        super::super::migration::locked_migration_note_refs(db_path, account_uuid)?;
    let pools = ordinary_send_spend_pools(
        super::super::migration::migration_reserves_orchard_inputs(db_path, account_uuid, network)?,
    );
    let reserved = BTreeSet::new();
    let source = ReservedInputSource {
        inner: db,
        reserved: &reserved,
        migration_locks: &migration_locks,
    };
    let selection = select(&source, account, &pools, target, network)?;
    let recipient: zcash_address::ZcashAddress =
        address.parse().map_err(|e| format!("Bad address: {e}"))?;
    let recipient: Address = recipient
        .convert_if_network(network.network_type())
        .map_err(|e| format!("Bad address: {e}"))?;
    let height = BlockHeight::from(target);
    let ironwood_active = network.is_nu_active(consensus::NetworkUpgrade::Nu6_3, height);
    let shielded = match &recipient {
        Address::Unified(ua) if ua.has_orchard() => true,
        Address::Transparent(_) | Address::Tex(_) => false,
        Address::Unified(ua) if ua.has_transparent() && !ua.has_sapling() => false,
        _ => return Err("Ledger does not support Sapling recipients".into()),
    };
    let tex = matches!(recipient, Address::Tex(_));
    let candidate = best_prefix(
        &selection
            .orchard
            .iter()
            .map(|input| input.value)
            .collect::<Vec<_>>(),
        &selection
            .ironwood
            .iter()
            .map(|input| input.value)
            .collect::<Vec<_>>(),
        |o, i| {
            // Preserve the existing release guard; do not recommend a transfer
            // whose Orchard inputs would pay an Ironwood output.
            if shielded && ironwood_active && o > 0 {
                return Ok(None);
            }
            let oa = action_count(
                network,
                height,
                orchard::ValuePool::Orchard,
                o,
                usize::from(shielded && !ironwood_active) + usize::from(o > 0),
            )?;
            let ia = action_count(
                network,
                height,
                orchard::ValuePool::Ironwood,
                i,
                usize::from(shielded && ironwood_active) + usize::from(o == 0 && i > 0),
            )?;
            if oa > MAX_SHIELDED_ACTIONS || ia > MAX_SHIELDED_ACTIONS {
                return Ok(None);
            }
            let fee = ConservativeZip317FeeRule
                .fee_required(
                    &network,
                    height,
                    std::iter::empty::<TransparentInputSize>(),
                    if shielded {
                        vec![]
                    } else {
                        vec![P2PKH_STANDARD_OUTPUT_SIZE]
                    },
                    0,
                    0,
                    oa,
                    ia,
                )
                .map_err(|e| format!("Ledger fee calculation: {e}"))?;
            let second_fee = if tex {
                ConservativeZip317FeeRule
                    .fee_required(
                        &network,
                        height,
                        [TransparentInputSize::Known(P2PKH_STANDARD_INPUT_SIZE)],
                        [P2PKH_STANDARD_OUTPUT_SIZE],
                        0,
                        0,
                        0,
                        0,
                    )
                    .map_err(|e| format!("Ledger TEX fee calculation: {e}"))?
            } else {
                Zatoshis::ZERO
            };
            Ok(Some(u64::from(
                (fee + second_fee).ok_or("Ledger fee overflow")?,
            )))
        },
    )?
    .ok_or("Insufficient Ledger-supported balance to cover the fee")?;
    let mut excluded = selection.excluded;
    excluded.extend(
        selection
            .orchard
            .iter()
            .skip(candidate.orchard)
            .map(|input| input.id),
    );
    excluded.extend(
        selection
            .ironwood
            .iter()
            .skip(candidate.ironwood)
            .map(|input| input.id),
    );
    let policy =
        SpendPolicy::shielded_pools(pools.into_iter().filter(|p| *p != ShieldedPool::Sapling));
    let version = proposed_tx_version_for_wallet_db(db, network, "estimating Ledger max")?;
    let build = |version| {
        propose_send_with_reserved_notes(
            db,
            network,
            account,
            build_send_request(address, candidate.amount, memo)?,
            &excluded,
            &migration_locks,
            &policy,
            version,
        )
    };
    let (proposal, _) = propose_with_note_version_downgrade(build(version)?, version, build);
    validate(&proposal, network)?;
    validate_release_support(&proposal)?;
    // Review does not carry this estimator's excluded-prefix set. Verify again
    // with its ordinary selection surface so extra eligible notes cannot make
    // the recommendation unusable (for example, by changing SDK dust handling).
    let rebuild = |version| {
        propose_send_with_reserved_notes(
            db,
            network,
            account,
            build_send_request(address, candidate.amount, memo)?,
            &reserved,
            &migration_locks,
            &policy,
            version,
        )
    };
    let (proposal, _) = propose_with_note_version_downgrade(rebuild(version)?, version, rebuild);
    validate_release_support(&proposal)?;
    // The displayed amount is backed by an actual proposal using the same
    // policy as Review, not just a sum-minus-guessed-fee calculation.
    Ok(SendMaxEstimateResult {
        amount_zatoshi: candidate.amount,
        fee_zatoshi: proposal_fee_zatoshi(&proposal),
        needs_sapling_params: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::data_api::{anchor_retention::PoolMigrationParams, PoolMeta};
    use zcash_protocol::consensus::NetworkUpgrade;

    struct TestInputs {
        orchard: Vec<ReceivedNote<u32, orchard::Note>>,
        ironwood: Vec<ReceivedNote<u32, orchard::Note>>,
    }

    impl InputSource for TestInputs {
        type Error = String;
        type AccountId = u32;
        type NoteRef = u32;
        fn anchor_computable(&self, _: ShieldedPool, _: BlockHeight) -> Result<bool, String> {
            Ok(true)
        }
        fn get_spendable_note(
            &self,
            _: &TxId,
            _: ShieldedPool,
            _: u32,
            _: TargetHeight,
            _: LockFilter<'_>,
        ) -> Result<Option<ReceivedNote<u32, Note>>, String> {
            Ok(None)
        }
        fn select_spendable_notes(
            &self,
            _: u32,
            _: TargetValue,
            pools: &[ShieldedPool],
            _: TargetHeight,
            _: ConfirmationsPolicy,
            exclude: &[u32],
            _: LockFilter<'_>,
        ) -> Result<ReceivedNotes<u32>, String> {
            let selected = |pool, notes: &[ReceivedNote<u32, orchard::Note>]| {
                notes
                    .iter()
                    .filter(|note| {
                        pools.contains(&pool) && !exclude.contains(note.internal_note_id())
                            // Match SQLite's eligible-note query, which excludes
                            // values at or below the ZIP-317 marginal fee.
                            && note.note().value().inner() > u64::from(ConservativeZip317FeeRule.marginal_fee())
                    })
                    .cloned()
                    .collect()
            };
            Ok(ReceivedNotes::new(
                vec![],
                selected(ShieldedPool::Orchard, &self.orchard),
                selected(ShieldedPool::Ironwood, &self.ironwood),
            ))
        }
        fn select_unspent_notes(
            &self,
            _: u32,
            _: &[ShieldedPool],
            _: TargetHeight,
            _: &[u32],
            _: LockFilter<'_>,
        ) -> Result<ReceivedNotes<u32>, String> {
            unreachable!()
        }
        fn get_account_metadata(
            &self,
            _: u32,
            _: &NoteFilter,
            _: TargetHeight,
            _: &[u32],
            _: LockFilter<'_>,
        ) -> Result<AccountMeta, String> {
            Ok(AccountMeta::new(
                Some(PoolMeta::new(0, Zatoshis::ZERO)),
                Some(PoolMeta::new(0, Zatoshis::ZERO)),
                Some(PoolMeta::new(0, Zatoshis::ZERO)),
            ))
        }
    }

    fn note(id: u32, version: orchard::note::NoteVersion) -> ReceivedNote<u32, orchard::Note> {
        note_with_value(id, version, 100_000)
    }

    fn note_with_value(
        id: u32,
        version: orchard::note::NoteVersion,
        value: u64,
    ) -> ReceivedNote<u32, orchard::Note> {
        let key = orchard::keys::SpendingKey::from_bytes([19; 32]).unwrap();
        let fvk = orchard::keys::FullViewingKey::from(&key);
        let mut rho_bytes = [0; 32];
        rho_bytes[..4].copy_from_slice(&id.to_le_bytes());
        let rho = orchard::note::Rho::from_bytes(&rho_bytes).unwrap();
        let seed = (0u8..=255)
            .find_map(|byte| orchard::note::RandomSeed::from_bytes([byte; 32], &rho).into_option())
            .unwrap();
        let note = orchard::Note::from_parts(
            fvk.address_at(id, orchard::keys::Scope::External),
            orchard::value::NoteValue::from_raw(value),
            rho,
            seed,
            version,
        )
        .unwrap();
        ReceivedNote::from_parts(
            id,
            TxId::from_bytes([id as u8; 32]),
            0,
            note,
            zip32::Scope::External,
            incrementalmerkletree::Position::from(id as u64),
            Some(BlockHeight::from_u32(10)),
            None,
        )
    }

    #[test]
    fn sdk_max_proposals_obey_separate_pool_budgets_and_exact_fees() {
        let network = WalletNetwork::Regtest;
        crate::wallet::network::configure_regtest_nu6_3_activation_height(500).unwrap();
        let height = BlockHeight::from_u32(1_000);
        let target = TargetHeight::from(height);
        let key = orchard::keys::SpendingKey::from_bytes([21; 32]).unwrap();
        let fvk = orchard::keys::FullViewingKey::from(&key);
        let unified = zcash_keys::address::UnifiedAddress::from_receivers(
            Some(fvk.address_at(0u32, orchard::keys::Scope::External)),
            None,
            None,
        )
        .unwrap();
        let transparent = Address::Transparent(TransparentAddress::PublicKeyHash([8; 20]));
        for (o, i, recipient) in [
            (1, 0, transparent.clone()),
            (0, 1, transparent.clone()),
            (1, 1, transparent.clone()),
            (31, 0, transparent.clone()),
            (32, 0, transparent.clone()),
            (0, 32, transparent.clone()),
            (31, 32, transparent),
            (0, 32, Address::Unified(unified)),
            (0, 32, Address::Tex([9; 20])),
        ] {
            let source = TestInputs {
                orchard: (1..=o)
                    .map(|id| note(id, orchard::note::NoteVersion::V2))
                    .collect(),
                ironwood: (101..101 + i)
                    .map(|id| note(id, orchard::note::NoteVersion::V3))
                    .collect(),
            };
            let shielded = matches!(recipient, Address::Unified(_));
            let tex = matches!(recipient, Address::Tex(_));
            let fee = u64::from(
                ConservativeZip317FeeRule
                    .fee_required(
                        &network,
                        height,
                        std::iter::empty::<TransparentInputSize>(),
                        if shielded {
                            vec![]
                        } else {
                            vec![P2PKH_STANDARD_OUTPUT_SIZE]
                        },
                        0,
                        0,
                        action_count(
                            network,
                            height,
                            orchard::ValuePool::Orchard,
                            o as usize,
                            usize::from(o > 0),
                        )
                        .unwrap(),
                        action_count(
                            network,
                            height,
                            orchard::ValuePool::Ironwood,
                            i as usize,
                            usize::from(shielded) + usize::from(o == 0),
                        )
                        .unwrap(),
                    )
                    .unwrap(),
            ) + if tex { 10_000 } else { 0 };
            let amount = (o + i) as u64 * 100_000 - fee;
            let address = recipient.to_zcash_address(&network).to_string();
            let request = build_send_request(&address, amount, None).unwrap();
            let change = ledger_change_strategy::<TestInputs>();
            let selector = GreedyInputSelector::<TestInputs>::new();
            let params = PoolMigrationParams::new(
                zcash_client_backend::data_api::anchor_retention::AnchorRetentionInterval::ZIP_318,
            );
            let proposal = selector
                .propose_transaction(
                    &network,
                    &source,
                    target,
                    height,
                    &params,
                    confirmations_policy(),
                    1,
                    request,
                    &change,
                    &SpendPolicy::shielded_pools([ShieldedPool::Orchard, ShieldedPool::Ironwood]),
                    Some(TxVersion::V6),
                )
                .unwrap_or_else(|error| {
                    panic!("{o} Orchard + {i} Ironwood to {address}: {error:?}")
                });
            if o == 32 {
                assert!(validate(&proposal, network)
                    .unwrap_err()
                    .contains(CAPACITY_ERROR));
                continue;
            }
            validate(&proposal, network).unwrap();
            validate_release_support(&proposal).unwrap();
            assert_eq!(proposal_fee_zatoshi(&proposal), fee);
            assert_eq!(proposal_input_refs_generic(&proposal), (o + i) as usize);
            assert_eq!(proposal.steps().len(), if tex { 2 } else { 1 });
        }
        assert!(network.is_nu_active(NetworkUpgrade::Nu6_3, height));
    }

    fn proposal_input_refs_generic(proposal: &Proposal<WalletFeeRule, u32>) -> usize {
        proposal
            .steps()
            .iter()
            .map(|step| {
                step.shielded_inputs()
                    .map_or(0, |inputs| inputs.notes().len())
            })
            .sum()
    }

    #[test]
    fn sdk_max_uses_only_database_eligible_notes() {
        let network = WalletNetwork::Regtest;
        crate::wallet::network::configure_regtest_nu6_3_activation_height(500).unwrap();
        let height = BlockHeight::from_u32(1_000);
        let source = TestInputs {
            orchard: vec![],
            ironwood: [100_000, 100, 1]
                .into_iter()
                .enumerate()
                .map(|(index, value)| {
                    note_with_value(index as u32 + 1, orchard::note::NoteVersion::V3, value)
                })
                .collect(),
        };
        let eligible = source
            .select_spendable_notes(
                1,
                TargetValue::AllFunds(MaxSpendMode::MaxSpendable),
                &[ShieldedPool::Ironwood],
                height.into(),
                confirmations_policy(),
                &[],
                LockFilter::Policy(&LockedInputPolicy::Exclude),
            )
            .unwrap();
        let values = eligible
            .ironwood()
            .iter()
            .map(|note| note.note().value().inner())
            .collect::<Vec<_>>();
        let candidate = best_prefix(&[], &values, |_, i| Ok(Some((i.max(2) as u64 + 1) * 5_000)))
            .unwrap()
            .unwrap();
        assert_eq!(candidate.ironwood, 1);
        let address = Address::Transparent(TransparentAddress::PublicKeyHash([8; 20]))
            .to_zcash_address(&network)
            .to_string();
        let proposal = GreedyInputSelector::<TestInputs>::new().propose_transaction(
            &network, &source, height.into(), height,
            &PoolMigrationParams::new(zcash_client_backend::data_api::anchor_retention::AnchorRetentionInterval::ZIP_318),
            confirmations_policy(), 1,
            build_send_request(&address, candidate.amount, None).unwrap(),
            &ledger_change_strategy::<TestInputs>(),
            &SpendPolicy::shielded_pools([ShieldedPool::Ironwood]), Some(TxVersion::V6),
        ).unwrap();
        validate(&proposal, network).unwrap();
        assert_eq!(proposal_input_refs_generic(&proposal), 1);
        assert_eq!(proposal_fee_zatoshi(&proposal), 15_000);
    }

    #[test]
    fn action_budget_counts_padding_and_outputs() {
        let network = WalletNetwork::Regtest;
        crate::wallet::network::configure_regtest_nu6_3_activation_height(500).unwrap();
        let height = BlockHeight::from_u32(1_000);
        assert_eq!(
            action_count(network, height, orchard::ValuePool::Orchard, 31, 1).unwrap(),
            32
        );
        assert_eq!(
            action_count(network, height, orchard::ValuePool::Orchard, 32, 1).unwrap(),
            33
        );
        assert_eq!(
            action_count(network, height, orchard::ValuePool::Ironwood, 1, 0).unwrap(),
            2
        );
        assert_eq!(
            action_count(network, height, orchard::ValuePool::Ironwood, 32, 1).unwrap(),
            32
        );
        assert_eq!(
            action_count(network, height, orchard::ValuePool::Ironwood, 1, 33).unwrap(),
            33
        );
    }

    #[test]
    fn eligible_inputs_preserve_reservations_and_migration_locks() {
        let source = TestInputs {
            orchard: (1..=3)
                .map(|id| note(id, orchard::note::NoteVersion::V2))
                .collect(),
            ironwood: vec![],
        };
        let reserved = BTreeSet::from([1]);
        let migration_locks = BTreeSet::from([(TxId::from_bytes([2; 32]).to_string(), 0)]);
        let bounded = ReservedInputSource {
            inner: &source,
            reserved: &reserved,
            migration_locks: &migration_locks,
        };
        let notes = bounded
            .select_spendable_notes(
                1,
                TargetValue::AllFunds(MaxSpendMode::MaxSpendable),
                &[ShieldedPool::Orchard],
                BlockHeight::from_u32(1000).into(),
                confirmations_policy(),
                &[],
                LockFilter::Policy(&LockedInputPolicy::Exclude),
            )
            .unwrap();
        assert_eq!(
            notes
                .orchard()
                .iter()
                .map(|note| *note.internal_note_id())
                .collect::<Vec<_>>(),
            vec![3]
        );
    }

    #[test]
    fn budgets_are_per_pool_not_one_combined_limit() {
        let candidate = best_prefix(&[100_000; 40], &[200_000; 40], |o, i| {
            Ok(Some((o + i) as u64 * 5_000))
        })
        .unwrap()
        .unwrap();
        assert_eq!((candidate.orchard, candidate.ironwood), (32, 32));
        assert_eq!(candidate.amount, 9_280_000);
    }

    #[test]
    fn maximum_omits_inputs_that_cost_more_than_they_add() {
        let candidate = best_prefix(&[100_000, 100, 1], &[], |o, _| {
            Ok(Some(o.max(2) as u64 * 5_000))
        })
        .unwrap()
        .unwrap();
        assert_eq!(candidate.orchard, 2);
        assert_eq!(candidate.amount, 90_100);
    }

    #[test]
    fn incompatible_pool_combinations_are_not_recommended() {
        let candidate = best_prefix(&[9_000_000], &[100_000], |o, _| {
            Ok((o == 0).then_some(10_000))
        })
        .unwrap()
        .unwrap();
        assert_eq!(
            (candidate.orchard, candidate.ironwood, candidate.amount),
            (0, 1, 90_000)
        );
    }

    #[test]
    fn no_positive_net_amount_has_no_suggestion() {
        assert_eq!(
            best_prefix(&[1, 2], &[], |_, _| Ok(Some(10_000))).unwrap(),
            None
        );
    }
}
