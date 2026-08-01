use std::collections::BTreeMap;

use rand::RngCore;
use zcash_protocol::value::Zatoshis;

use super::{
    preparation_plan::{
        plan_preparation, PrepError, PrepInput, PrepOutput, PreparationPlan, PREP_TX_ACTIONS,
    },
    DenominationPlan,
};

pub(crate) const DENOMINATION_SPLIT_ACTIONS: usize = PREP_TX_ACTIONS;

const APPROVED_PLAN_ORDER_ERROR: &str =
    "Approved migration denominations are not in canonical part order. Review the migration plan again.";

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
    pub layer_index: usize,
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

/// Plans a migration as the combined balances of `profile_count` synthetic
/// wallets. Each profile receives a deterministic log-uniform share of the
/// selected balance, then independently decomposes that share into canonical
/// ZIP 318 denominations. The exact native preparation graph is still checked
/// after every candidate, so this changes only denomination selection.
pub(crate) fn plan_custom_padded_denominations<R: RngCore + ?Sized>(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
    profile_count: u32,
    rng: &mut R,
) -> Result<Option<PaddedDenominationPlan>, String> {
    if !(1..=256).contains(&profile_count) {
        return Err("Custom migration profile count must be between 1 and 256".to_string());
    }

    let (positive_input_indices, _positive_input_values, total_input_zatoshi, available, prep_fee) =
        planning_inputs(input_values, fee_per_stage_zatoshi, minimum_output_zatoshi)?;
    if positive_input_indices.is_empty() {
        return Ok(None);
    }

    let minimum_denomination = super::ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI;
    let minimum_funding_note = minimum_denomination
        .checked_add(migration_fee_zatoshi)
        .ok_or("Minimum migration funding note overflow")?;
    let mut profile_budgets = synthetic_profile_budgets(
        total_input_zatoshi,
        usize::try_from(profile_count).map_err(|_| "Custom profile count overflow")?,
        rng,
    );
    let mut profile_order = (0..profile_budgets.len()).collect::<Vec<_>>();
    // A Fisher-Yates shuffle using the same deterministic stream avoids
    // repeatedly giving rounding priority to the first generated profile.
    for upper in (1..profile_order.len()).rev() {
        let selected = (rng.next_u64() % ((upper + 1) as u64)) as usize;
        profile_order.swap(upper, selected);
    }

    let mut crossing_values = Vec::new();
    let mut funding_values = Vec::new();
    let mut preparation = PreparationPlan::from_parts(Vec::new(), Vec::new());

    loop {
        let mut accepted_in_round = false;
        for profile_index in profile_order.iter().copied() {
            let profile_budget = profile_budgets[profile_index];
            if profile_budget < minimum_funding_note {
                continue;
            }

            let mut affordable = profile_budget
                .checked_sub(migration_fee_zatoshi)
                .expect("minimum funding note check guarantees the subtraction")
                .min(super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI);
            let mut accepted = None;
            while affordable >= minimum_denomination {
                let Some(crossing) = super::largest_zip318_denomination_at_or_below(affordable)
                else {
                    break;
                };
                let funding = crossing
                    .checked_add(migration_fee_zatoshi)
                    .ok_or("Prepared migration note value overflow")?;
                funding_values.push(funding);
                let typed_funding = typed_funding_values(&funding_values)?;

                match plan_preparation(&available, &typed_funding, prep_fee) {
                    Ok(candidate) => {
                        let candidate_fees = preparation_fee_total(
                            fee_per_stage_zatoshi,
                            candidate.transaction_count(),
                        )?;
                        let candidate_total =
                            checked_sum(&funding_values, "Migration funding total overflow")?
                                .checked_add(candidate_fees)
                                .ok_or("Migration candidate value overflow")?;
                        if candidate_total <= total_input_zatoshi {
                            accepted = Some((crossing, funding, candidate));
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

            if let Some((crossing, funding, candidate)) = accepted {
                crossing_values.push(crossing);
                profile_budgets[profile_index] = profile_budgets[profile_index]
                    .checked_sub(funding)
                    .ok_or("Custom profile budget underflow")?;
                preparation = candidate;
                accepted_in_round = true;
            }
        }
        if !accepted_in_round {
            break;
        }
    }

    finish_padded_plan(
        crossing_values,
        funding_values,
        preparation,
        positive_input_indices,
        total_input_zatoshi,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
    )
}

/// Rebuilds the native preparation graph for an already approved custom
/// denomination list. This is the signing-time balance-drift check.
pub(crate) fn plan_padded_denominations_for_targets(
    input_values: &[u64],
    target_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<Option<PaddedDenominationPlan>, String> {
    if target_values.is_empty() {
        return Ok(None);
    }
    if let Some(value) = target_values
        .iter()
        .find(|value| !super::is_zip318_canonical_denomination(**value))
    {
        return Err(format!(
            "Custom migration target {value} is not a canonical ZIP 318 denomination"
        ));
    }
    if !target_values.windows(2).all(|pair| pair[0] >= pair[1]) {
        return Err(APPROVED_PLAN_ORDER_ERROR.to_string());
    }

    let (positive_input_indices, _positive_input_values, total_input_zatoshi, available, prep_fee) =
        planning_inputs(input_values, fee_per_stage_zatoshi, minimum_output_zatoshi)?;
    if positive_input_indices.is_empty() {
        return Ok(None);
    }
    let funding_values = target_values
        .iter()
        .map(|value| {
            value
                .checked_add(migration_fee_zatoshi)
                .ok_or_else(|| "Prepared migration note value overflow".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let typed_funding = typed_funding_values(&funding_values)?;
    let preparation = match plan_preparation(&available, &typed_funding, prep_fee) {
        Ok(plan) => plan,
        Err(PrepError::InsufficientFunds) => {
            return Err("Saved custom migration plan no longer fits this balance".to_string())
        }
        Err(PrepError::BalanceInvalid) => {
            return Err("Migration preparation balance is invalid".to_string())
        }
    };
    let committed = checked_sum(&funding_values, "Migration funding total overflow")?
        .checked_add(preparation_fee_total(
            fee_per_stage_zatoshi,
            preparation.transaction_count(),
        )?)
        .ok_or("Migration candidate value overflow")?;
    if committed > total_input_zatoshi {
        return Err("Saved custom migration plan no longer fits this balance".to_string());
    }

    finish_padded_plan(
        target_values.to_vec(),
        funding_values,
        preparation,
        positive_input_indices,
        total_input_zatoshi,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
    )
}

fn planning_inputs(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<(Vec<usize>, Vec<u64>, u64, Vec<Zatoshis>, Zatoshis), String> {
    if fee_per_stage_zatoshi == 0 {
        return Err("Padded denomination stage fee must be positive".to_string());
    }
    if minimum_output_zatoshi != 1 {
        return Err(
            "Padded denomination stages require a 1-zatoshi minimum output to preserve the exact ZIP 317 fee"
                .to_string(),
        );
    }
    let positive_input_indices = input_values
        .iter()
        .enumerate()
        .filter_map(|(index, value)| (*value > 0).then_some(index))
        .collect::<Vec<_>>();
    let positive_input_values = positive_input_indices
        .iter()
        .map(|index| input_values[*index])
        .collect::<Vec<_>>();
    let total_input_zatoshi =
        checked_sum(&positive_input_values, "Selected Orchard value overflow")?;
    let available = positive_input_values
        .iter()
        .map(|value| {
            Zatoshis::from_u64(*value)
                .map_err(|_| "Selected Orchard note exceeds the maximum money supply".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let prep_fee = Zatoshis::from_u64(fee_per_stage_zatoshi)
        .map_err(|_| "Padded denomination fee is invalid".to_string())?;
    Ok((
        positive_input_indices,
        positive_input_values,
        total_input_zatoshi,
        available,
        prep_fee,
    ))
}

fn synthetic_profile_budgets(
    total: u64,
    count: usize,
    rng: &mut (impl RngCore + ?Sized),
) -> Vec<u64> {
    const MANTISSA_SCALE: f64 = (1u64 << 53) as f64;
    const SPREAD_RATIO: f64 = 100.0;
    let log_spread = SPREAD_RATIO.ln();
    let weights = (0..count)
        .map(|_| {
            let unit = ((rng.next_u64() >> 11) as f64) / MANTISSA_SCALE;
            ((unit - 0.5) * log_spread).exp()
        })
        .collect::<Vec<_>>();
    let weight_total = weights.iter().sum::<f64>();
    let mut allocated = 0u64;
    weights
        .into_iter()
        .enumerate()
        .map(|(index, weight)| {
            if index + 1 == count {
                total.saturating_sub(allocated)
            } else {
                let budget = ((total as f64) * weight / weight_total).floor() as u64;
                allocated = allocated.saturating_add(budget);
                budget
            }
        })
        .collect()
}

fn typed_funding_values(values: &[u64]) -> Result<Vec<Zatoshis>, String> {
    values
        .iter()
        .map(|value| {
            Zatoshis::from_u64(*value)
                .map_err(|_| "Prepared migration note value is invalid".to_string())
        })
        .collect()
}

fn preparation_fee_total(
    fee_per_stage_zatoshi: u64,
    transaction_count: usize,
) -> Result<u64, String> {
    fee_per_stage_zatoshi
        .checked_mul(
            u64::try_from(transaction_count)
                .map_err(|_| "Preparation transaction count overflow".to_string())?,
        )
        .ok_or_else(|| "Preparation fee total overflow".to_string())
}

#[allow(clippy::too_many_arguments)]
fn finish_padded_plan(
    crossing_values: Vec<u64>,
    funding_values: Vec<u64>,
    preparation: PreparationPlan,
    positive_input_indices: Vec<usize>,
    total_input_zatoshi: u64,
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<Option<PaddedDenominationPlan>, String> {
    if crossing_values.is_empty() {
        return Ok(None);
    }
    if crossing_values.len() != funding_values.len() {
        return Err("Migration denomination and funding note counts differ".to_string());
    }

    let mut denomination_funding = crossing_values
        .into_iter()
        .zip(funding_values)
        .collect::<Vec<_>>();
    // Prepared notes are reloaded in this order and selected by part index.
    denomination_funding.sort_unstable_by(|(left, _), (right, _)| right.cmp(left));
    let (crossing_values, funding_values): (Vec<_>, Vec<_>) =
        denomination_funding.into_iter().unzip();

    let split_fee_zatoshi =
        preparation_fee_total(fee_per_stage_zatoshi, preparation.transaction_count())?;
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
                layer_index,
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
    use rand::{rngs::StdRng, SeedableRng};

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

    #[test]
    fn fragmented_large_balance_does_not_leave_migratable_change() {
        let inputs = [
            vec![198_000_400; 5],
            vec![396_000_800; 5],
            vec![594_001_200; 5],
            vec![792_001_600; 5],
        ]
        .concat();
        let plan = plan_padded_denominations(&inputs, PREP_FEE, MIGRATION_FEE, 1)
            .unwrap()
            .unwrap();
        let change = plan.denominations.orchard_change.unwrap_or_default();
        let follow_up = plan_padded_denominations(&[change], PREP_FEE, MIGRATION_FEE, 1).unwrap();

        assert!(
            follow_up.is_none(),
            "planner left {change} zatoshi that requires another migration run"
        );
    }

    #[test]
    fn custom_profiles_are_deterministic_and_keep_large_notes_available() {
        let input = 1_000_000 * ZEC;
        let build = || {
            let mut rng = StdRng::seed_from_u64(42);
            plan_custom_padded_denominations(&[input], PREP_FEE, MIGRATION_FEE, 1, 1, &mut rng)
                .unwrap()
                .unwrap()
        };
        let first = build();
        let second = build();

        assert_eq!(first.denominations, second.denominations);
        assert!(first
            .denominations
            .migration_outputs
            .contains(&(10_000 * ZEC)));
        assert!(first
            .denominations
            .migration_outputs
            .iter()
            .all(|value| super::super::is_zip318_canonical_denomination(*value)));
    }

    #[test]
    fn more_profiles_shift_a_large_balance_into_lower_buckets() {
        let input = 50_000 * ZEC;
        let mut one_rng = StdRng::seed_from_u64(7);
        let one =
            plan_custom_padded_denominations(&[input], PREP_FEE, MIGRATION_FEE, 1, 1, &mut one_rng)
                .unwrap()
                .unwrap();
        let mut many_rng = StdRng::seed_from_u64(7);
        let many = plan_custom_padded_denominations(
            &[input],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            64,
            &mut many_rng,
        )
        .unwrap()
        .unwrap();
        let count_large = |plan: &PaddedDenominationPlan| {
            plan.denominations
                .migration_outputs
                .iter()
                .filter(|value| **value == 10_000 * ZEC)
                .count()
        };

        assert!(count_large(&many) < count_large(&one));
        assert!(
            many.denominations.migration_outputs.len() > one.denominations.migration_outputs.len()
        );
    }

    #[test]
    fn maximum_profile_count_still_plans_a_million_zec_balance() {
        let input = 1_000_000 * ZEC;
        let mut rng = StdRng::seed_from_u64(2026);
        let plan =
            plan_custom_padded_denominations(&[input], PREP_FEE, MIGRATION_FEE, 1, 256, &mut rng)
                .unwrap()
                .unwrap();

        assert!(plan
            .denominations
            .migration_outputs
            .contains(&(10_000 * ZEC)));
        assert!(plan.denominations.migration_outputs.len() > 256);
        assert_eq!(
            plan.denominations.total_input_zatoshi,
            plan.denominations.total_migratable_zatoshi
                + plan.denominations.orchard_change.unwrap_or_default()
                + plan.denominations.split_fee_zatoshi
                + MIGRATION_FEE * plan.denominations.migration_outputs.len() as u64
        );
    }

    #[test]
    fn custom_plan_matches_prepared_note_database_order() {
        let input = 50_000 * ZEC;
        let mut rng = StdRng::seed_from_u64(2026);
        let plan =
            plan_custom_padded_denominations(&[input], PREP_FEE, MIGRATION_FEE, 1, 64, &mut rng)
                .unwrap()
                .unwrap();

        assert!(plan
            .denominations
            .migration_outputs
            .windows(2)
            .all(|pair| pair[0] >= pair[1]));

        let mut prepared_funding_values = plan
            .direct_migration_inputs
            .iter()
            .map(|input| input.value_zatoshi)
            .chain(plan.stages.iter().flat_map(|stage| {
                stage
                    .outputs
                    .iter()
                    .filter(|output| output.kind == SplitTerminalKind::Migration)
                    .map(|output| output.value_zatoshi)
            }))
            .collect::<Vec<_>>();
        prepared_funding_values.sort_unstable_by(|left, right| right.cmp(left));
        let prepared_targets = prepared_funding_values
            .into_iter()
            .map(|value| value.checked_sub(MIGRATION_FEE).unwrap())
            .collect::<Vec<_>>();

        assert_eq!(plan.denominations.migration_outputs, prepared_targets);
    }

    #[test]
    fn approved_custom_targets_reject_non_database_order() {
        let error = plan_padded_denominations_for_targets(
            &[10 * ZEC],
            &[2 * ZEC, 5 * ZEC],
            PREP_FEE,
            MIGRATION_FEE,
            1,
        )
        .unwrap_err();

        assert_eq!(error, APPROVED_PLAN_ORDER_ERROR);
    }

    #[test]
    fn approved_custom_targets_rebuild_exactly() {
        let input = 50_000 * ZEC;
        let mut rng = StdRng::seed_from_u64(99);
        let preview =
            plan_custom_padded_denominations(&[input], PREP_FEE, MIGRATION_FEE, 1, 32, &mut rng)
                .unwrap()
                .unwrap();
        let rebuilt = plan_padded_denominations_for_targets(
            &[input],
            &preview.denominations.migration_outputs,
            PREP_FEE,
            MIGRATION_FEE,
            1,
        )
        .unwrap()
        .unwrap();

        assert_eq!(rebuilt, preview);
    }
}
