use std::collections::BTreeMap;

use rand::{rngs::OsRng, RngCore};
use zcash_protocol::value::Zatoshis;

use super::{
    preparation_plan::{
        plan_preparation, PrepError, PrepInput, PrepOutput, PreparationPlan, PREP_TX_ACTIONS,
    },
    DenominationPlan,
};

pub(crate) const DENOMINATION_SPLIT_ACTIONS: usize = PREP_TX_ACTIONS;

const TEN_THOUSAND_ZEC_ZATOSHI: u64 = super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI;
const FIVE_THOUSAND_ZEC_ZATOSHI: u64 = TEN_THOUSAND_ZEC_ZATOSHI / 2;
const TWO_THOUSAND_ZEC_ZATOSHI: u64 = TEN_THOUSAND_ZEC_ZATOSHI / 5;
const ONE_THOUSAND_ZEC_ZATOSHI: u64 = TEN_THOUSAND_ZEC_ZATOSHI / 10;

/// Vizor's configurable policy for optional ZIP 318 denomination refinement.
/// Each percentage is an independent gate applied recursively to that bucket.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct DenominationRefinementPolicy {
    ten_thousand_split_percent: u32,
    five_thousand_split_percent: u32,
    two_thousand_split_percent: u32,
}

/// A selected refinement and every recursively selected child split.
/// Collapsing any node back to its value preserves a canonical denomination.
#[derive(Clone, Debug, Eq, PartialEq)]
struct DenominationRefinement {
    value_zatoshi: u64,
    children: Vec<Self>,
}

impl DenominationRefinement {
    fn leaf(value_zatoshi: u64) -> Self {
        Self {
            value_zatoshi,
            children: Vec::new(),
        }
    }
}

impl DenominationRefinementPolicy {
    const fn new(
        ten_thousand_split_percent: u32,
        five_thousand_split_percent: u32,
        two_thousand_split_percent: u32,
    ) -> Self {
        assert!(
            ten_thousand_split_percent <= 100
                && five_thousand_split_percent <= 100
                && two_thousand_split_percent <= 100,
            "denomination refinement percentage exceeds 100"
        );
        Self {
            ten_thousand_split_percent,
            five_thousand_split_percent,
            two_thousand_split_percent,
        }
    }

    /// Keeps each gate and child shape together when refinable buckets change.
    fn split_rule(self, denomination_zatoshi: u64) -> Option<(u32, &'static [u64])> {
        match denomination_zatoshi {
            TEN_THOUSAND_ZEC_ZATOSHI => Some((
                self.ten_thousand_split_percent,
                &[FIVE_THOUSAND_ZEC_ZATOSHI, FIVE_THOUSAND_ZEC_ZATOSHI],
            )),
            FIVE_THOUSAND_ZEC_ZATOSHI => Some((
                self.five_thousand_split_percent,
                &[
                    TWO_THOUSAND_ZEC_ZATOSHI,
                    TWO_THOUSAND_ZEC_ZATOSHI,
                    ONE_THOUSAND_ZEC_ZATOSHI,
                ],
            )),
            TWO_THOUSAND_ZEC_ZATOSHI => Some((
                self.two_thousand_split_percent,
                &[ONE_THOUSAND_ZEC_ZATOSHI, ONE_THOUSAND_ZEC_ZATOSHI],
            )),
            _ => None,
        }
    }
}

// These are Vizor policy values, not ZIP 318's provisional selection weights.
const AGGRESSIVE_REFINEMENT_POLICY: DenominationRefinementPolicy =
    DenominationRefinementPolicy::new(80, 55, 35);
const APPROVED_PLAN_STALE_ERROR: &str =
    "Approved migration plan no longer matches the spendable Orchard balance. Review the migration plan again.";
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

struct PlanningContext {
    positive_input_indices: Vec<usize>,
    total_input_zatoshi: u64,
    available: Vec<Zatoshis>,
    prep_fee: Zatoshis,
}

/// Plans canonical ZIP 318 denominations and the native preparation graph.
///
/// This mirrors the upstream backend's coupling between denomination selection
/// and preparation layout. The preparation planner is consulted after every
/// candidate note, so exact-note reuse, consolidation, fanout, and their real
/// padded transaction fees all affect which denominations fit. Planning stops
/// only when the remaining balance cannot fund another canonical migration
/// note and its preparation cost. The configured policy can recursively refine
/// 10,000, 5,000, and 2,000 ZEC buckets, with 1,000 ZEC as the floor.
pub(crate) fn plan_padded_denominations(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<Option<PaddedDenominationPlan>, String> {
    plan_padded_denominations_with_rng(
        input_values,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
        &mut OsRng,
    )
}

/// Retains the deterministic fallback for builders that have no approved
/// target list to replay. New plans use [`plan_padded_denominations`].
pub(crate) fn plan_padded_denominations_without_refinement(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<Option<PaddedDenominationPlan>, String> {
    plan_padded_denominations_with_refiner(
        input_values,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
        DenominationRefinement::leaf,
    )
}

fn plan_padded_denominations_with_rng<R: RngCore + ?Sized>(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
    rng: &mut R,
) -> Result<Option<PaddedDenominationPlan>, String> {
    plan_padded_denominations_with_policy_and_rng(
        input_values,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
        AGGRESSIVE_REFINEMENT_POLICY,
        rng,
    )
}

fn plan_padded_denominations_with_policy_and_rng<R: RngCore + ?Sized>(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
    policy: DenominationRefinementPolicy,
    rng: &mut R,
) -> Result<Option<PaddedDenominationPlan>, String> {
    plan_padded_denominations_with_refiner(
        input_values,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
        |greedy| refine_denomination(greedy, policy, rng),
    )
}

fn plan_padded_denominations_with_refiner<F: FnMut(u64) -> DenominationRefinement>(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
    mut refine: F,
) -> Result<Option<PaddedDenominationPlan>, String> {
    let Some(context) =
        planning_context(input_values, fee_per_stage_zatoshi, minimum_output_zatoshi)?
    else {
        return Ok(None);
    };

    let minimum_denomination = super::ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI;
    let minimum_funding_note = minimum_denomination
        .checked_add(migration_fee_zatoshi)
        .ok_or("Minimum migration funding note overflow")?;
    let mut crossing_values = Vec::new();
    let mut funding_values = Vec::new();
    let mut preparation = PreparationPlan::from_parts(Vec::new(), Vec::new());

    loop {
        let committed = committed_value(&funding_values, &preparation, fee_per_stage_zatoshi)?;
        let budget = context.total_input_zatoshi.saturating_sub(committed);
        if budget < minimum_funding_note {
            break;
        }

        let mut affordable = budget
            .checked_sub(migration_fee_zatoshi)
            .expect("minimum funding note check guarantees the subtraction")
            .min(super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI);
        let mut accepted = None;
        while affordable >= minimum_denomination {
            let Some(greedy) = super::largest_zip318_denomination_at_or_below(affordable) else {
                break;
            };
            let refinement = refine(greedy);
            if refinement.value_zatoshi != greedy {
                return Err("Denomination refinement must preserve the selected value".to_string());
            }
            let candidates = refinement_candidates(&refinement)?;

            for candidate in candidates {
                let prior_crossing_count = crossing_values.len();
                crossing_values.extend_from_slice(&candidate);
                match preparation_for_crossings(
                    &context,
                    &crossing_values,
                    fee_per_stage_zatoshi,
                    migration_fee_zatoshi,
                )? {
                    Some((candidate_funding, candidate_preparation)) => {
                        funding_values = candidate_funding;
                        accepted = Some(candidate_preparation);
                        break;
                    }
                    None => {
                        crossing_values.truncate(prior_crossing_count);
                    }
                }
            }

            if accepted.is_some() || greedy == minimum_denomination {
                break;
            }
            affordable = greedy - 1;
        }

        let Some(candidate) = accepted else {
            break;
        };
        preparation = candidate;
    }

    finish_plan(
        context,
        crossing_values,
        funding_values,
        preparation,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
    )
}

/// Rebuilds a preparation graph for denomination values that were already
/// approved and persisted. This must not draw randomness again.
pub(crate) fn plan_padded_denominations_for_targets(
    input_values: &[u64],
    target_values_zatoshi: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<Option<PaddedDenominationPlan>, String> {
    if target_values_zatoshi.is_empty() {
        return Ok(None);
    }
    for value in target_values_zatoshi {
        if !super::is_zip318_canonical_denomination(*value) {
            return Err(format!(
                "Approved migration denomination {value} is not canonical"
            ));
        }
    }
    if !target_values_zatoshi
        .windows(2)
        .all(|pair| pair[0] >= pair[1])
    {
        return Err(APPROVED_PLAN_ORDER_ERROR.to_string());
    }

    let Some(context) =
        planning_context(input_values, fee_per_stage_zatoshi, minimum_output_zatoshi)?
    else {
        return Err(APPROVED_PLAN_STALE_ERROR.to_string());
    };

    let Some((funding_values, preparation)) = preparation_for_crossings(
        &context,
        target_values_zatoshi,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
    )?
    else {
        return Err(APPROVED_PLAN_STALE_ERROR.to_string());
    };
    if can_append_canonical_denomination(
        &context,
        target_values_zatoshi,
        &funding_values,
        &preparation,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
    )? {
        return Err(APPROVED_PLAN_STALE_ERROR.to_string());
    }

    finish_plan(
        context,
        target_values_zatoshi.to_vec(),
        funding_values,
        preparation,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
    )
}

fn planning_context(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<Option<PlanningContext>, String> {
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

    Ok(Some(PlanningContext {
        positive_input_indices,
        total_input_zatoshi,
        available,
        prep_fee,
    }))
}

fn refine_denomination<R: RngCore + ?Sized>(
    denomination_zatoshi: u64,
    policy: DenominationRefinementPolicy,
    rng: &mut R,
) -> DenominationRefinement {
    let Some((split_percent, children)) = policy.split_rule(denomination_zatoshi) else {
        return DenominationRefinement::leaf(denomination_zatoshi);
    };
    if split_percent == 0 || rng.next_u32() % 100 >= split_percent {
        return DenominationRefinement::leaf(denomination_zatoshi);
    }

    DenominationRefinement {
        value_zatoshi: denomination_zatoshi,
        children: children
            .iter()
            .map(|child| refine_denomination(*child, policy, rng))
            .collect(),
    }
}

/// Returns every valid pruning of a selected refinement tree, ordered from the
/// most split candidate to the unsplit root so the planner keeps the deepest
/// affordable result. The current policy produces at most 26 candidates.
fn refinement_candidates(refinement: &DenominationRefinement) -> Result<Vec<Vec<u64>>, String> {
    if !super::is_zip318_canonical_denomination(refinement.value_zatoshi) {
        return Err("Denomination refinement produced a noncanonical value".to_string());
    }
    if refinement.children.is_empty() {
        return Ok(vec![vec![refinement.value_zatoshi]]);
    }

    let child_values = refinement
        .children
        .iter()
        .map(|child| child.value_zatoshi)
        .collect::<Vec<_>>();
    if checked_sum(&child_values, "Denomination refinement total overflow")?
        != refinement.value_zatoshi
    {
        return Err("Denomination refinement must preserve the selected value".to_string());
    }

    let mut expanded = vec![Vec::new()];
    for child in &refinement.children {
        let child_candidates = refinement_candidates(child)?;
        let combined_capacity = expanded
            .len()
            .checked_mul(child_candidates.len())
            .ok_or("Denomination refinement candidate count overflow")?;
        let mut combined = Vec::with_capacity(combined_capacity);
        for prefix in expanded {
            for child_candidate in &child_candidates {
                let mut candidate = Vec::with_capacity(prefix.len() + child_candidate.len());
                candidate.extend_from_slice(&prefix);
                candidate.extend_from_slice(child_candidate);
                combined.push(candidate);
            }
        }
        expanded = combined;
    }
    expanded.push(vec![refinement.value_zatoshi]);

    for candidate in &mut expanded {
        candidate.sort_unstable_by(|left, right| right.cmp(left));
    }
    expanded
        .sort_unstable_by(|left, right| right.len().cmp(&left.len()).then_with(|| left.cmp(right)));
    expanded.dedup();
    Ok(expanded)
}

fn preparation_for_crossings(
    context: &PlanningContext,
    crossing_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
) -> Result<Option<(Vec<u64>, PreparationPlan)>, String> {
    let funding_values = crossing_values
        .iter()
        .map(|crossing| {
            crossing
                .checked_add(migration_fee_zatoshi)
                .ok_or_else(|| "Prepared migration note value overflow".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let typed_funding = funding_values
        .iter()
        .map(|value| {
            Zatoshis::from_u64(*value)
                .map_err(|_| "Prepared migration note value is invalid".to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    let preparation = match plan_preparation(&context.available, &typed_funding, context.prep_fee) {
        Ok(candidate) => candidate,
        Err(PrepError::InsufficientFunds) => return Ok(None),
        Err(PrepError::BalanceInvalid) => {
            return Err("Migration preparation balance is invalid".to_string());
        }
    };
    let committed = committed_value(&funding_values, &preparation, fee_per_stage_zatoshi)?;
    Ok((committed <= context.total_input_zatoshi).then_some((funding_values, preparation)))
}

fn can_append_canonical_denomination(
    context: &PlanningContext,
    crossing_values: &[u64],
    funding_values: &[u64],
    preparation: &PreparationPlan,
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
) -> Result<bool, String> {
    let committed = committed_value(funding_values, preparation, fee_per_stage_zatoshi)?;
    let budget = context.total_input_zatoshi.saturating_sub(committed);
    let minimum_denomination = super::ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI;
    let minimum_funding_note = minimum_denomination
        .checked_add(migration_fee_zatoshi)
        .ok_or("Minimum migration funding note overflow")?;
    if budget < minimum_funding_note {
        return Ok(false);
    }

    let mut affordable = budget
        .checked_sub(migration_fee_zatoshi)
        .expect("minimum funding note check guarantees the subtraction")
        .min(super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI);
    let mut trial = crossing_values.to_vec();
    while affordable >= minimum_denomination {
        let Some(crossing) = super::largest_zip318_denomination_at_or_below(affordable) else {
            break;
        };
        trial.push(crossing);
        if preparation_for_crossings(
            context,
            &trial,
            fee_per_stage_zatoshi,
            migration_fee_zatoshi,
        )?
        .is_some()
        {
            return Ok(true);
        }
        trial.pop();
        if crossing == minimum_denomination {
            break;
        }
        affordable = crossing - 1;
    }
    Ok(false)
}

fn committed_value(
    funding_values: &[u64],
    preparation: &PreparationPlan,
    fee_per_stage_zatoshi: u64,
) -> Result<u64, String> {
    let funding_total = checked_sum(funding_values, "Migration funding total overflow")?;
    let prep_fees = fee_per_stage_zatoshi
        .checked_mul(
            u64::try_from(preparation.transaction_count())
                .map_err(|_| "Preparation transaction count overflow".to_string())?,
        )
        .ok_or("Preparation fee total overflow")?;
    funding_total
        .checked_add(prep_fees)
        .ok_or_else(|| "Migration committed value overflow".to_string())
}

fn finish_plan(
    context: PlanningContext,
    crossing_values: Vec<u64>,
    funding_values: Vec<u64>,
    preparation: PreparationPlan,
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

    let split_fee_zatoshi = fee_per_stage_zatoshi
        .checked_mul(
            u64::try_from(preparation.transaction_count())
                .map_err(|_| "Preparation transaction count overflow".to_string())?,
        )
        .ok_or("Preparation fee total overflow")?;
    let funding_total = checked_sum(&funding_values, "Migration funding total overflow")?;
    let remaining = context
        .total_input_zatoshi
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
        total_input_zatoshi: context.total_input_zatoshi,
        total_migratable_zatoshi,
    };

    translate_preparation_plan(
        preparation,
        denominations,
        &context.positive_input_indices,
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
    use rand::{rngs::mock::StepRng, rngs::StdRng, SeedableRng};
    use std::collections::VecDeque;

    const ZEC: u64 = 100_000_000;
    const PREP_FEE: u64 = 80_000;
    const MIGRATION_FEE: u64 = 15_000;

    struct ScriptedRng {
        rolls: VecDeque<u32>,
    }

    impl ScriptedRng {
        fn new(rolls: impl IntoIterator<Item = u32>) -> Self {
            Self {
                rolls: rolls.into_iter().collect(),
            }
        }

        fn assert_exhausted(&self) {
            assert!(self.rolls.is_empty(), "unused scripted random rolls");
        }
    }

    impl RngCore for ScriptedRng {
        fn next_u32(&mut self) -> u32 {
            self.rolls
                .pop_front()
                .expect("denomination refinement requested an unexpected random roll")
        }

        fn next_u64(&mut self) -> u64 {
            (u64::from(self.next_u32()) << 32) | u64::from(self.next_u32())
        }

        fn fill_bytes(&mut self, dest: &mut [u8]) {
            for chunk in dest.chunks_mut(4) {
                let bytes = self.next_u32().to_le_bytes();
                chunk.copy_from_slice(&bytes[..chunk.len()]);
            }
        }

        fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), rand::Error> {
            self.fill_bytes(dest);
            Ok(())
        }
    }

    fn funding(crossing: u64) -> u64 {
        crossing + MIGRATION_FEE
    }

    fn plan_without_refinement(
        input_values: &[u64],
    ) -> Result<Option<PaddedDenominationPlan>, String> {
        plan_padded_denominations_without_refinement(input_values, PREP_FEE, MIGRATION_FEE, 1)
    }

    #[test]
    fn aggressive_policy_uses_configured_gate_percentages() {
        assert_eq!(
            AGGRESSIVE_REFINEMENT_POLICY,
            DenominationRefinementPolicy::new(80, 55, 35)
        );
        let cases = [
            (
                10_000 * ZEC,
                DenominationRefinementPolicy::new(80, 0, 0),
                80,
            ),
            (5_000 * ZEC, DenominationRefinementPolicy::new(0, 55, 0), 55),
            (2_000 * ZEC, DenominationRefinementPolicy::new(0, 0, 35), 35),
        ];

        for (denomination, policy, expected_refined_rolls) in cases {
            let refined_rolls = (0..100u64)
                .filter(|roll| {
                    let mut rng = StepRng::new(*roll, 0);
                    !refine_denomination(denomination, policy, &mut rng)
                        .children
                        .is_empty()
                })
                .count();

            assert_eq!(refined_rolls, expected_refined_rolls);
        }
    }

    #[test]
    fn ten_thousand_zec_balance_has_deterministic_refinement_examples() {
        let input = 10_000 * ZEC + 230_000;
        let cases = [
            ("keep 10k", vec![80], vec![10_000 * ZEC], Some(135_000)),
            (
                "split to 5k",
                vec![0, 55, 55],
                vec![5_000 * ZEC, 5_000 * ZEC],
                Some(120_000),
            ),
            (
                "split one 5k child",
                vec![0, 55, 0, 35, 35],
                vec![5_000 * ZEC, 2_000 * ZEC, 2_000 * ZEC, 1_000 * ZEC],
                Some(90_000),
            ),
            (
                "split one 2k grandchild",
                vec![0, 55, 0, 35, 0],
                vec![
                    5_000 * ZEC,
                    2_000 * ZEC,
                    1_000 * ZEC,
                    1_000 * ZEC,
                    1_000 * ZEC,
                ],
                Some(75_000),
            ),
            (
                "split to the 1k floor",
                vec![0; 7],
                vec![1_000 * ZEC; 10],
                None,
            ),
        ];

        for (name, rolls, expected, expected_change) in cases {
            let mut rng = ScriptedRng::new(rolls);
            let plan =
                plan_padded_denominations_with_rng(&[input], PREP_FEE, MIGRATION_FEE, 1, &mut rng)
                    .unwrap()
                    .unwrap();
            rng.assert_exhausted();

            assert_eq!(plan.denominations.migration_outputs, expected, "{name}");
            assert_eq!(plan.denominations.orchard_change, expected_change, "{name}");
            assert!(plan.denominations.migration_outputs.iter().all(|value| {
                *value <= super::super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI
            }));
        }
    }

    #[test]
    fn randomized_plan_matches_prepared_note_database_order() {
        let input = 10_000 * ZEC + 230_000;
        let mut rng = StepRng::new(0, 65);
        let plan =
            plan_padded_denominations_with_rng(&[input], PREP_FEE, MIGRATION_FEE, 1, &mut rng)
                .unwrap()
                .unwrap();

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
    fn randomized_plans_replay_exactly_across_balances_and_input_shapes() {
        let mut case_rng = StdRng::seed_from_u64(0x5eed_0318);

        for case_index in 0..1_500 {
            let balance_zec = 1 + case_rng.next_u64() % 300_000;
            let total_zatoshi = balance_zec.checked_mul(ZEC).unwrap();
            let input_count = 1 + (case_rng.next_u32() % 4) as usize;
            let mut remaining = total_zatoshi;
            let mut inputs = Vec::with_capacity(input_count);
            for remaining_input_count in (1..input_count).rev() {
                let reserved = remaining_input_count as u64;
                let value = 1 + case_rng.next_u64() % (remaining - reserved);
                inputs.push(value);
                remaining -= value;
            }
            inputs.push(remaining);

            let mut plan_rng = StdRng::seed_from_u64(case_rng.next_u64());
            let planned = plan_padded_denominations_with_rng(
                &inputs,
                PREP_FEE,
                MIGRATION_FEE,
                1,
                &mut plan_rng,
            )
            .unwrap()
            .unwrap();
            let outputs = &planned.denominations.migration_outputs;

            assert!(
                outputs.windows(2).all(|pair| pair[0] >= pair[1]),
                "case {case_index} is not in prepared-note order"
            );
            assert!(outputs.iter().all(|value| {
                *value <= super::super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI
                    && super::super::is_zip318_canonical_denomination(*value)
            }));

            let replayed =
                plan_padded_denominations_for_targets(&inputs, outputs, PREP_FEE, MIGRATION_FEE, 1)
                    .unwrap()
                    .unwrap();
            assert_eq!(planned, replayed, "case {case_index} did not replay");
        }

        let mut large_plan_rng = StdRng::seed_from_u64(0x1_000_000);
        let large_plan = plan_padded_denominations_with_rng(
            &[1_000_000 * ZEC],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            &mut large_plan_rng,
        )
        .unwrap()
        .unwrap();
        let large_replay = plan_padded_denominations_for_targets(
            &[1_000_000 * ZEC],
            &large_plan.denominations.migration_outputs,
            PREP_FEE,
            MIGRATION_FEE,
            1,
        )
        .unwrap()
        .unwrap();
        assert_eq!(large_plan, large_replay);
    }

    #[test]
    fn twenty_five_thousand_zec_balance_can_refine_every_eligible_bucket() {
        let input = 25_000 * ZEC + 900_000;
        let mut keep_rng = StepRng::new(80, 0);
        let greedy =
            plan_padded_denominations_with_rng(&[input], PREP_FEE, MIGRATION_FEE, 1, &mut keep_rng)
                .unwrap()
                .unwrap();
        let mut refine_rng = StepRng::new(0, 0);
        let refined = plan_padded_denominations_with_rng(
            &[input],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            &mut refine_rng,
        )
        .unwrap()
        .unwrap();

        assert_eq!(
            greedy.denominations.migration_outputs,
            vec![10_000 * ZEC, 10_000 * ZEC, 5_000 * ZEC]
        );
        assert_eq!(
            refined.denominations.migration_outputs,
            vec![1_000 * ZEC; 25]
        );
    }

    #[test]
    fn refinement_recurses_through_five_and_two_thousand_zec_children() {
        let input = 10_000 * ZEC + 230_000;
        let mut rng = StepRng::new(0, 0);
        let plan =
            plan_padded_denominations_with_rng(&[input], PREP_FEE, MIGRATION_FEE, 1, &mut rng)
                .unwrap()
                .unwrap();

        assert_eq!(plan.denominations.migration_outputs, vec![1_000 * ZEC; 10]);
    }

    #[test]
    fn existing_five_and_two_thousand_zec_roots_are_also_refined() {
        let input = 7_000 * ZEC + 185_000;
        let mut rng = StepRng::new(0, 0);
        let plan =
            plan_padded_denominations_with_rng(&[input], PREP_FEE, MIGRATION_FEE, 1, &mut rng)
                .unwrap()
                .unwrap();

        assert_eq!(plan.denominations.migration_outputs, vec![1_000 * ZEC; 7]);
        assert_eq!(plan.denominations.orchard_change, None);
    }

    #[test]
    fn policy_configuration_controls_recursive_depth() {
        let input = 10_000 * ZEC + 230_000;
        let mut shallow_rng = ScriptedRng::new([0]);
        let shallow = plan_padded_denominations_with_policy_and_rng(
            &[input],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            DenominationRefinementPolicy::new(100, 0, 0),
            &mut shallow_rng,
        )
        .unwrap()
        .unwrap();
        shallow_rng.assert_exhausted();

        let mut deep_rng = ScriptedRng::new([0; 7]);
        let deep = plan_padded_denominations_with_policy_and_rng(
            &[input],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            DenominationRefinementPolicy::new(100, 100, 100),
            &mut deep_rng,
        )
        .unwrap()
        .unwrap();
        deep_rng.assert_exhausted();

        assert_eq!(
            shallow.denominations.migration_outputs,
            vec![5_000 * ZEC, 5_000 * ZEC]
        );
        assert_eq!(deep.denominations.migration_outputs, vec![1_000 * ZEC; 10]);
    }

    #[test]
    fn unaffordable_recursive_subtree_falls_back_to_its_parent() {
        let mut rng = StepRng::new(0, 0);
        let plan = plan_padded_denominations_with_rng(
            &[funding(5_000 * ZEC)],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            &mut rng,
        )
        .unwrap()
        .unwrap();

        assert_eq!(plan.denominations.migration_outputs, vec![5_000 * ZEC]);
        assert!(plan.stages.is_empty());
        assert_eq!(plan.direct_migration_inputs.len(), 1);
    }

    #[test]
    fn unaffordable_descendant_preserves_affordable_ancestor_split() {
        let mut rng = ScriptedRng::new([0, 55, 0, 35, 35]);
        let plan = plan_padded_denominations_with_rng(
            &[10_000 * ZEC + 120_000],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            &mut rng,
        )
        .unwrap()
        .unwrap();
        rng.assert_exhausted();

        assert_eq!(
            plan.denominations.migration_outputs,
            vec![5_000 * ZEC, 5_000 * ZEC]
        );
        assert_eq!(plan.denominations.orchard_change, Some(10_000));
    }

    #[test]
    fn fifty_thousand_zec_balance_has_a_deterministic_aggressive_example() {
        let rolls = [
            80, // 10
            0, 55, 55, // 5 + 5
            0, 55, 0, 35, 35, // 5 + 2 + 2 + 1
            0, 55, 0, 35, 0, // 5 + 2 + 1 + 1 + 1
            0, 0, 35, 35, 0, 35, 0, // 2 + 2 + 2 + 1 + 1 + 1 + 1
        ];
        let mut rng = ScriptedRng::new(rolls);
        let plan = plan_padded_denominations_with_rng(
            &[50_000 * ZEC + 900_000],
            PREP_FEE,
            MIGRATION_FEE,
            1,
            &mut rng,
        )
        .unwrap()
        .unwrap();
        rng.assert_exhausted();

        let expected = [
            vec![10_000 * ZEC],
            vec![5_000 * ZEC; 4],
            vec![2_000 * ZEC; 6],
            vec![1_000 * ZEC; 8],
        ]
        .concat();
        assert_eq!(plan.denominations.migration_outputs, expected);
        assert_eq!(plan.denominations.migration_outputs.len(), 19);
    }

    #[test]
    fn approved_refined_targets_rebuild_without_another_random_draw() {
        let input = 10_000 * ZEC + 230_000;
        let targets = vec![5_000 * ZEC, 2_000 * ZEC, 2_000 * ZEC, 1_000 * ZEC];
        let plan =
            plan_padded_denominations_for_targets(&[input], &targets, PREP_FEE, MIGRATION_FEE, 1)
                .unwrap()
                .unwrap();

        assert_eq!(plan.denominations.migration_outputs, targets);
        assert_eq!(plan.denominations.orchard_change, Some(90_000));
    }

    #[test]
    fn approved_targets_reject_non_database_order() {
        let targets = vec![2_000 * ZEC, 5_000 * ZEC, 2_000 * ZEC, 1_000 * ZEC];
        let error = plan_padded_denominations_for_targets(
            &[10_000 * ZEC + 230_000],
            &targets,
            PREP_FEE,
            MIGRATION_FEE,
            1,
        )
        .unwrap_err();

        assert_eq!(
            error,
            "Approved migration denominations are not in canonical part order. Review the migration plan again."
        );
    }

    #[test]
    fn approved_targets_report_when_the_balance_can_no_longer_fund_them() {
        let targets = vec![5_000 * ZEC, 2_000 * ZEC, 2_000 * ZEC, 1_000 * ZEC];
        let error = plan_padded_denominations_for_targets(
            &[10_000 * ZEC + 100_000],
            &targets,
            PREP_FEE,
            MIGRATION_FEE,
            1,
        )
        .unwrap_err();

        assert_eq!(
            error,
            "Approved migration plan no longer matches the spendable Orchard balance. Review the migration plan again."
        );
    }

    #[test]
    fn approved_targets_report_when_the_balance_can_fund_another_part() {
        let targets = vec![5_000 * ZEC, 2_000 * ZEC, 2_000 * ZEC, 1_000 * ZEC];
        let error = plan_padded_denominations_for_targets(
            &[10_000 * ZEC + 2_300_000],
            &targets,
            PREP_FEE,
            MIGRATION_FEE,
            1,
        )
        .unwrap_err();

        assert_eq!(
            error,
            "Approved migration plan no longer matches the spendable Orchard balance. Review the migration plan again."
        );
    }

    #[test]
    fn direct_refined_targets_can_diverge_from_a_greedy_rebuild() {
        let inputs = [
            funding(5_000 * ZEC),
            funding(5_000 * ZEC),
            2 * PREP_FEE - MIGRATION_FEE,
        ];
        let refined =
            plan_padded_denominations_with_refiner(&inputs, PREP_FEE, MIGRATION_FEE, 1, |greedy| {
                if greedy == super::super::ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI {
                    DenominationRefinement {
                        value_zatoshi: greedy,
                        children: vec![
                            DenominationRefinement::leaf(5_000 * ZEC),
                            DenominationRefinement::leaf(5_000 * ZEC),
                        ],
                    }
                } else {
                    DenominationRefinement::leaf(greedy)
                }
            })
            .unwrap()
            .unwrap();
        let greedy = plan_without_refinement(&inputs).unwrap().unwrap();

        assert_eq!(
            refined.denominations.migration_outputs,
            vec![5_000 * ZEC, 5_000 * ZEC]
        );
        assert!(refined.stages.is_empty());
        assert_eq!(greedy.denominations.migration_outputs, vec![10_000 * ZEC]);
        assert_eq!(greedy.stages.len(), 2);
    }

    #[test]
    fn reuses_an_exact_funding_note_without_a_preparation_transaction() {
        let plan = plan_without_refinement(&[funding(100 * ZEC)])
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
        let plan = plan_without_refinement(&inputs).unwrap().unwrap();

        assert_eq!(plan.denominations.migration_outputs.len(), inputs.len());
        assert_eq!(plan.direct_migration_inputs.len(), inputs.len());
        assert!(plan.stages.is_empty());
        assert_eq!(plan.denominations.orchard_change, None);
    }

    #[test]
    fn combines_direct_funding_with_a_minted_funding_note() {
        let plan = plan_without_refinement(&[funding(100 * ZEC), funding(20 * ZEC) + PREP_FEE])
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
        let plan = plan_without_refinement(&[input]).unwrap().unwrap();

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
        let plan = plan_without_refinement(&inputs).unwrap().unwrap();

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
        let plan = plan_without_refinement(&inputs).unwrap().unwrap();
        let change = plan.denominations.orchard_change.unwrap_or_default();
        let follow_up = plan_without_refinement(&[change]).unwrap();

        assert!(
            follow_up.is_none(),
            "planner left {change} zatoshi that requires another migration run"
        );
    }
}
