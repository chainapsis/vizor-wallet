use std::collections::BTreeMap;

use zcash_protocol::value::Zatoshis;

use super::{
    preparation_plan::{
        plan_preparation, PrepError, PrepInput, PrepOutput, PreparationPlan, PREP_TX_ACTIONS,
    },
    DenominationPlan,
};

pub(crate) const DENOMINATION_SPLIT_ACTIONS: usize = PREP_TX_ACTIONS;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SplitStageInput {
    Original {
        input_index: usize,
        value_zatoshi: u64,
    },
    Prior {
        stage_index: usize,
        output_index: usize,
        value_zatoshi: u64,
    },
}

impl SplitStageInput {
    fn value_zatoshi(self) -> u64 {
        match self {
            Self::Original { value_zatoshi, .. } | Self::Prior { value_zatoshi, .. } => {
                value_zatoshi
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SplitTerminalKind {
    Migration,
    OrchardChange,
    Continuation,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SplitStageOutput {
    pub value_zatoshi: u64,
    pub kind: SplitTerminalKind,
    pub part_index: Option<usize>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SplitStagePlan {
    pub inputs: Vec<SplitStageInput>,
    pub outputs: Vec<SplitStageOutput>,
    pub fee_zatoshi: u64,
    pub requested_actions: usize,
}

impl SplitStagePlan {
    pub(crate) fn padding_actions(&self) -> usize {
        DENOMINATION_SPLIT_ACTIONS
            .checked_sub(self.requested_actions)
            .expect("split stage exceeds the padded action limit")
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct DirectMigrationInput {
    pub input_index: usize,
    pub part_index: usize,
    pub value_zatoshi: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct PaddedDenominationPlan {
    pub denominations: DenominationPlan,
    pub stages: Vec<SplitStagePlan>,
    pub layer_count: usize,
    pub direct_migration_inputs: Vec<DirectMigrationInput>,
}

/// Plans the canonical ZIP 318 denominations and the native preparation graph.
///
/// This mirrors the upstream backend's coupling between denomination selection
/// and preparation layout. The preparation planner is consulted after every
/// candidate note, so exact-note reuse, consolidation, fanout, and their real
/// padded transaction fees all affect which denominations fit. Planning stops
/// only when the remaining balance cannot fund another canonical migration
/// note and its preparation cost.
pub(crate) fn plan_padded_denominations(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<Option<PaddedDenominationPlan>, String> {
    let positive_input_indices = input_values
        .iter()
        .enumerate()
        .filter_map(|(index, value)| (*value > 0).then_some(index))
        .collect::<Vec<_>>();
    if positive_input_indices.is_empty() {
        return Ok(None);
    }
    if fee_per_stage_zatoshi == 0 {
        return Err("Padded denomination stage fee must be positive".to_string());
    }
    if minimum_output_zatoshi != 1 {
        return Err(
            "Padded denomination stages require a 1-zatoshi minimum output to preserve the exact ZIP 317 fee"
                .to_string(),
        );
    }

    let positive_input_values = positive_input_indices
        .iter()
        .map(|index| input_values[*index])
        .collect::<Vec<_>>();
    let total_input_zatoshi = positive_input_values
        .iter()
        .try_fold(0u64, |total, value| {
            total
                .checked_add(*value)
                .ok_or_else(|| "Selected Orchard value overflow".to_string())
        })?;
    let available = positive_input_values
        .iter()
        .map(|value| {
            Zatoshis::from_u64(*value)
                .map_err(|_| "Selected Orchard note exceeds the maximum money supply".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let prep_fee = Zatoshis::from_u64(fee_per_stage_zatoshi)
        .map_err(|_| "Padded denomination fee is invalid".to_string())?;

    let minimum_denomination = super::ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI;
    let minimum_funding_note = minimum_denomination
        .checked_add(migration_fee_zatoshi)
        .ok_or("Minimum migration funding note overflow")?;
    let mut crossing_values = Vec::new();
    let mut funding_values = Vec::new();
    let mut preparation = PreparationPlan::from_parts(Vec::new(), Vec::new());

    loop {
        let funding_total = checked_sum(&funding_values, "Migration funding total overflow")?;
        let prep_fees = fee_per_stage_zatoshi
            .checked_mul(
                u64::try_from(preparation.transaction_count())
                    .map_err(|_| "Preparation transaction count overflow".to_string())?,
            )
            .ok_or("Preparation fee total overflow")?;
        let committed = funding_total
            .checked_add(prep_fees)
            .ok_or("Migration committed value overflow")?;
        let budget = total_input_zatoshi.saturating_sub(committed);
        if budget < minimum_funding_note {
            break;
        }

        let mut affordable = budget
            .checked_sub(migration_fee_zatoshi)
            .expect("minimum funding note check guarantees the subtraction")
            .min(super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI);
        let mut accepted = None;
        while affordable >= minimum_denomination {
            let Some(crossing) = super::largest_zip318_denomination_at_or_below(affordable) else {
                break;
            };
            let funding = crossing
                .checked_add(migration_fee_zatoshi)
                .ok_or("Prepared migration note value overflow")?;
            funding_values.push(funding);
            let typed_funding = funding_values
                .iter()
                .map(|value| {
                    Zatoshis::from_u64(*value)
                        .map_err(|_| "Prepared migration note value is invalid".to_string())
                })
                .collect::<Result<Vec<_>, _>>()?;

            match plan_preparation(&available, &typed_funding, prep_fee) {
                Ok(candidate) => {
                    let candidate_fees =
                        fee_per_stage_zatoshi
                            .checked_mul(u64::try_from(candidate.transaction_count()).map_err(
                                |_| "Preparation transaction count overflow".to_string(),
                            )?)
                            .ok_or("Preparation fee total overflow")?;
                    let candidate_total =
                        checked_sum(&funding_values, "Migration funding total overflow")?
                            .checked_add(candidate_fees)
                            .ok_or("Migration candidate value overflow")?;
                    if candidate_total <= total_input_zatoshi {
                        accepted = Some((crossing, candidate));
                    }
                }
                Err(PrepError::InsufficientFunds) => {}
                Err(PrepError::BalanceInvalid) => {
                    return Err("Migration preparation balance is invalid".to_string());
                }
            }

            if accepted.is_some() {
                break;
            }
            funding_values.pop();
            if crossing == minimum_denomination {
                break;
            }
            affordable = crossing - 1;
        }

        let Some((crossing, candidate)) = accepted else {
            break;
        };
        crossing_values.push(crossing);
        preparation = candidate;
    }

    if crossing_values.is_empty() {
        return Ok(None);
    }

    let split_fee_zatoshi = fee_per_stage_zatoshi
        .checked_mul(
            u64::try_from(preparation.transaction_count())
                .map_err(|_| "Preparation transaction count overflow".to_string())?,
        )
        .ok_or("Preparation fee total overflow")?;
    let funding_total = checked_sum(&funding_values, "Migration funding total overflow")?;
    let remaining = total_input_zatoshi
        .checked_sub(funding_total)
        .and_then(|value| value.checked_sub(split_fee_zatoshi))
        .ok_or("Migration preparation plan exceeds selected Orchard value")?;
    let total_migratable_zatoshi =
        checked_sum(&crossing_values, "Migratable denomination total overflow")?;
    let denominations = DenominationPlan {
        migration_outputs: crossing_values,
        orchard_change: (remaining >= minimum_output_zatoshi).then_some(remaining),
        split_fee_zatoshi,
        migration_fee_zatoshi,
        total_input_zatoshi,
        total_migratable_zatoshi,
    };

    translate_preparation_plan(
        preparation,
        denominations,
        &positive_input_indices,
        &funding_values,
        fee_per_stage_zatoshi,
    )
    .map(Some)
}

fn translate_preparation_plan(
    preparation: PreparationPlan,
    denominations: DenominationPlan,
    positive_input_indices: &[usize],
    funding_values: &[u64],
    fee_per_stage_zatoshi: u64,
) -> Result<PaddedDenominationPlan, String> {
    let layer_count = preparation.layer_count();
    let mut available_parts = BTreeMap::<u64, Vec<usize>>::new();
    for (part_index, value) in funding_values.iter().copied().enumerate().rev() {
        available_parts.entry(value).or_default().push(part_index);
    }

    let mut direct_migration_inputs = preparation
        .direct_funding_notes()
        .iter()
        .map(|(input_index, value)| {
            let value_zatoshi = u64::from(*value);
            Ok(DirectMigrationInput {
                input_index: *positive_input_indices
                    .get(*input_index)
                    .ok_or("Direct funding input index is out of range")?,
                part_index: take_part_index(&mut available_parts, value_zatoshi)?,
                value_zatoshi,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    direct_migration_inputs.sort_by_key(|input| input.part_index);

    let mut coordinates = BTreeMap::<(usize, usize), usize>::new();
    let mut stages = Vec::with_capacity(preparation.transaction_count());
    for (layer_index, layer) in preparation.layers().iter().enumerate() {
        for (transaction_index, transaction) in layer.iter().enumerate() {
            let inputs = transaction
                .inputs()
                .iter()
                .map(|input| match input {
                    PrepInput::Wallet { index, value } => Ok(SplitStageInput::Original {
                        input_index: *positive_input_indices
                            .get(*index)
                            .ok_or("Preparation wallet input index is out of range")?,
                        value_zatoshi: u64::from(*value),
                    }),
                    PrepInput::Prior {
                        layer,
                        transaction,
                        output,
                        value,
                    } => Ok(SplitStageInput::Prior {
                        stage_index: *coordinates
                            .get(&(*layer, *transaction))
                            .ok_or("Preparation input references an unknown prior transaction")?,
                        output_index: *output,
                        value_zatoshi: u64::from(*value),
                    }),
                })
                .collect::<Result<Vec<_>, String>>()?;
            let outputs = transaction
                .outputs()
                .iter()
                .map(|output| match output {
                    PrepOutput::Funding(value) => {
                        let value_zatoshi = u64::from(*value);
                        Ok(SplitStageOutput {
                            value_zatoshi,
                            kind: SplitTerminalKind::Migration,
                            part_index: Some(take_part_index(&mut available_parts, value_zatoshi)?),
                        })
                    }
                    PrepOutput::Intermediate(value) => Ok(SplitStageOutput {
                        value_zatoshi: u64::from(*value),
                        kind: SplitTerminalKind::Continuation,
                        part_index: None,
                    }),
                    PrepOutput::Change(value) => Ok(SplitStageOutput {
                        value_zatoshi: u64::from(*value),
                        kind: SplitTerminalKind::OrchardChange,
                        part_index: None,
                    }),
                })
                .collect::<Result<Vec<_>, String>>()?;
            let requested_actions = inputs
                .len()
                .checked_add(outputs.len())
                .ok_or("Preparation action count overflow")?;
            if requested_actions > DENOMINATION_SPLIT_ACTIONS {
                return Err(format!(
                    "Preparation transaction requests {requested_actions} actions instead of at most {DENOMINATION_SPLIT_ACTIONS}"
                ));
            }

            let input_total = inputs.iter().try_fold(0u64, |total, input| {
                total
                    .checked_add(input.value_zatoshi())
                    .ok_or("Preparation input total overflow")
            })?;
            let output_total = outputs.iter().try_fold(0u64, |total, output| {
                total
                    .checked_add(output.value_zatoshi)
                    .ok_or("Preparation output total overflow")
            })?;
            if input_total
                != output_total
                    .checked_add(fee_per_stage_zatoshi)
                    .ok_or("Preparation transaction value overflow")?
            {
                return Err("Preparation transaction does not conserve value".to_string());
            }

            let stage_index = stages.len();
            coordinates.insert((layer_index, transaction_index), stage_index);
            stages.push(SplitStagePlan {
                inputs,
                outputs,
                fee_zatoshi: fee_per_stage_zatoshi,
                requested_actions,
            });
        }
    }

    if available_parts.values().any(|parts| !parts.is_empty()) {
        return Err("Preparation plan did not assign every migration part".to_string());
    }

    Ok(PaddedDenominationPlan {
        denominations,
        stages,
        layer_count,
        direct_migration_inputs,
    })
}

fn take_part_index(
    available_parts: &mut BTreeMap<u64, Vec<usize>>,
    value_zatoshi: u64,
) -> Result<usize, String> {
    available_parts
        .get_mut(&value_zatoshi)
        .and_then(Vec::pop)
        .ok_or_else(|| {
            format!("Preparation plan produced unexpected funding value {value_zatoshi}")
        })
}

fn checked_sum(values: &[u64], context: &str) -> Result<u64, String> {
    values.iter().try_fold(0u64, |total, value| {
        total.checked_add(*value).ok_or_else(|| context.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const ZEC: u64 = 100_000_000;
    const PREP_FEE: u64 = 80_000;
    const MIGRATION_FEE: u64 = 15_000;

    fn funding(crossing: u64) -> u64 {
        crossing + MIGRATION_FEE
    }

    #[test]
    fn reuses_an_exact_funding_note_without_a_preparation_transaction() {
        let plan = plan_padded_denominations(&[funding(100 * ZEC)], PREP_FEE, MIGRATION_FEE, 1)
            .unwrap()
            .unwrap();

        assert_eq!(plan.denominations.migration_outputs, vec![100 * ZEC]);
        assert_eq!(plan.denominations.split_fee_zatoshi, 0);
        assert!(plan.stages.is_empty());
        assert_eq!(plan.layer_count, 0);
        assert_eq!(
            plan.direct_migration_inputs,
            vec![DirectMigrationInput {
                input_index: 0,
                part_index: 0,
                value_zatoshi: funding(100 * ZEC),
            }]
        );
    }

    #[test]
    fn reuses_all_exact_funding_notes_beyond_the_old_run_cap() {
        let inputs = vec![funding(10_000 * ZEC); 65];
        let plan = plan_padded_denominations(&inputs, PREP_FEE, MIGRATION_FEE, 1)
            .unwrap()
            .unwrap();

        assert_eq!(plan.denominations.migration_outputs.len(), inputs.len());
        assert_eq!(plan.direct_migration_inputs.len(), inputs.len());
        assert!(plan.stages.is_empty());
        assert_eq!(plan.denominations.orchard_change, None);
    }

    #[test]
    fn combines_direct_funding_with_a_minted_funding_note() {
        let plan = plan_padded_denominations(
            &[funding(100 * ZEC), funding(20 * ZEC) + PREP_FEE],
            PREP_FEE,
            MIGRATION_FEE,
            1,
        )
        .unwrap()
        .unwrap();

        assert_eq!(
            plan.denominations.migration_outputs,
            vec![100 * ZEC, 20 * ZEC]
        );
        assert_eq!(plan.denominations.split_fee_zatoshi, PREP_FEE);
        assert_eq!(plan.direct_migration_inputs.len(), 1);
        assert_eq!(plan.direct_migration_inputs[0].part_index, 0);
        assert_eq!(plan.stages.len(), 1);
        assert_eq!(plan.layer_count, 1);
        assert_eq!(plan.stages[0].outputs[0].part_index, Some(1));
    }

    #[test]
    fn balances_a_large_single_note_fanout_across_layers() {
        let note_count = 50usize;
        let preparation_transaction_count = 5u64;
        let input =
            note_count as u64 * funding(10_000 * ZEC) + preparation_transaction_count * PREP_FEE;
        let plan = plan_padded_denominations(&[input], PREP_FEE, MIGRATION_FEE, 1)
            .unwrap()
            .unwrap();

        assert_eq!(plan.denominations.migration_outputs.len(), note_count);
        assert_eq!(plan.stages.len(), preparation_transaction_count as usize);
        assert_eq!(plan.layer_count, 2);
        assert_eq!(
            plan.denominations.split_fee_zatoshi,
            preparation_transaction_count * PREP_FEE
        );
        let root_count = plan
            .stages
            .iter()
            .filter(|stage| {
                stage
                    .inputs
                    .iter()
                    .all(|input| matches!(input, SplitStageInput::Original { .. }))
            })
            .count();
        assert_eq!(root_count, 1);
        assert_eq!(plan.stages[0].outputs.len(), 4);
        assert!(plan.stages[1..].iter().all(|stage| stage
            .inputs
            .iter()
            .all(|input| matches!(input, SplitStageInput::Prior { .. }))));
    }

    #[test]
    fn every_preparation_transaction_respects_actions_and_value() {
        let inputs = vec![7 * ZEC; 40];
        let plan = plan_padded_denominations(&inputs, PREP_FEE, MIGRATION_FEE, 1)
            .unwrap()
            .unwrap();

        for stage in &plan.stages {
            assert!(stage.requested_actions <= DENOMINATION_SPLIT_ACTIONS);
            assert_eq!(
                stage.padding_actions() + stage.requested_actions,
                DENOMINATION_SPLIT_ACTIONS
            );
            let input_total = stage
                .inputs
                .iter()
                .map(|input| input.value_zatoshi())
                .sum::<u64>();
            let output_total = stage
                .outputs
                .iter()
                .map(|output| output.value_zatoshi)
                .sum::<u64>();
            assert_eq!(input_total, output_total + PREP_FEE);
        }
    }
}
