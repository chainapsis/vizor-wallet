use std::collections::{HashMap, HashSet};

use crate::wallet::network::WalletNetwork;

use super::{DenominationConfig, DenominationPlan};

pub(crate) const DENOMINATION_SPLIT_ACTIONS: usize = 16;

// Exact forest planning is a partition problem, so its worst case is
// exponential. Keep the amount of work deterministic and fall back to the
// value-pooling chain when a wallet has an unusually adversarial note set.
const FOREST_SEARCH_NODE_LIMIT: usize = 1_000_000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum SplitTerminalKind {
    Migration,
    OrchardChange,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SplitTerminalOutput {
    pub logical_index: usize,
    pub value_zatoshi: u64,
    pub kind: SplitTerminalKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct SplitStagePlan {
    pub original_input_indices: Vec<usize>,
    pub spends_previous_continuation: bool,
    pub terminal_outputs: Vec<SplitTerminalOutput>,
    pub continuation_value_zatoshi: Option<u64>,
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
pub(crate) struct PaddedDenominationPlan {
    pub denominations: DenominationPlan,
    pub stages: Vec<SplitStagePlan>,
}

/// Plans a padded split while preferring fewer stages.
///
/// Each candidate stage count gets a fresh denomination plan because subtracting
/// another padded transaction fee can change the decimal decomposition. Stage
/// counts are tried in ascending order. A bounded exact search considers
/// independent roots and continuation chains. If that search reaches its work
/// or mask bound, the deterministic single value-pooling chain remains the
/// fallback; that fallback is minimal among such chains, but isn't a proof that
/// no smaller forest exists.
pub(crate) fn plan_padded_denominations(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
    max_stages: usize,
    network: WalletNetwork,
) -> Result<Option<PaddedDenominationPlan>, String> {
    plan_padded_denominations_with_config(
        input_values,
        fee_per_stage_zatoshi,
        migration_fee_zatoshi,
        minimum_output_zatoshi,
        max_stages,
        super::denomination_config(network),
    )
}

fn plan_padded_denominations_with_config(
    input_values: &[u64],
    fee_per_stage_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
    max_stages: usize,
    denomination_config: DenominationConfig,
) -> Result<Option<PaddedDenominationPlan>, String> {
    if input_values.is_empty() {
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

    let total_input = input_values.iter().try_fold(0u64, |acc, value| {
        acc.checked_add(*value)
            .ok_or_else(|| "Selected Orchard value overflow".to_string())
    })?;

    for stage_count in 1..=max_stages {
        let total_fee = fee_per_stage_zatoshi
            .checked_mul(
                u64::try_from(stage_count)
                    .map_err(|_| "Denomination stage count overflow".to_string())?,
            )
            .ok_or("Denomination split fee overflow")?;
        let denominations = super::plan_denominations_with_config(
            total_input,
            total_fee,
            migration_fee_zatoshi,
            minimum_output_zatoshi,
            denomination_config,
        )?;
        if denominations.migration_outputs.is_empty() {
            return Ok(None);
        }
        let terminals = terminal_outputs(&denominations);
        let terminal_total = terminals.iter().try_fold(0u64, |acc, output| {
            acc.checked_add(output.value_zatoshi)
                .ok_or_else(|| "Denomination terminal total overflow".to_string())
        })?;
        let actual_fee = total_input
            .checked_sub(terminal_total)
            .ok_or("Denomination outputs exceed selected Orchard value")?;
        if actual_fee != total_fee {
            return Err(format!(
                "Denomination planner reserved {total_fee} zatoshis for {stage_count} padded stages but its outputs leave {actual_fee}"
            ));
        }

        if let Some(stages) =
            plan_exact_stage_count(input_values, &terminals, stage_count, fee_per_stage_zatoshi)?
        {
            return Ok(Some(PaddedDenominationPlan {
                denominations,
                stages,
            }));
        }
    }

    Err(format!(
        "Denomination split needs more than {max_stages} padded transactions"
    ))
}

fn terminal_outputs(plan: &DenominationPlan) -> Vec<SplitTerminalOutput> {
    let mut outputs = plan
        .migration_outputs
        .iter()
        .enumerate()
        .map(|(logical_index, value_zatoshi)| SplitTerminalOutput {
            logical_index,
            value_zatoshi: *value_zatoshi,
            kind: SplitTerminalKind::Migration,
        })
        .collect::<Vec<_>>();
    if let Some(value_zatoshi) = plan.orchard_change {
        outputs.push(SplitTerminalOutput {
            logical_index: plan.migration_outputs.len(),
            value_zatoshi,
            kind: SplitTerminalKind::OrchardChange,
        });
    }
    outputs
}

fn plan_exact_stage_count(
    input_values: &[u64],
    terminals: &[SplitTerminalOutput],
    stage_count: usize,
    fee_per_stage_zatoshi: u64,
) -> Result<Option<Vec<SplitStagePlan>>, String> {
    if stage_count == 0 || input_values.is_empty() || terminals.is_empty() {
        return Ok(None);
    }
    if terminals.iter().any(|output| output.value_zatoshi == 0) {
        return Err("Padded denomination terminal values must be positive".to_string());
    }

    let maximum_roots = input_values.len().min(terminals.len()).min(stage_count);
    let minimum_continuation_edges = stage_count.saturating_sub(maximum_roots);
    let minimum_continuation_actions = minimum_continuation_edges
        .checked_mul(2)
        .ok_or("Denomination continuation action count overflow")?;
    let required_real_actions = input_values
        .len()
        .checked_add(terminals.len())
        .and_then(|count| count.checked_add(minimum_continuation_actions))
        .ok_or("Denomination action count overflow")?;
    let action_capacity = DENOMINATION_SPLIT_ACTIONS
        .checked_mul(stage_count)
        .ok_or("Denomination action capacity overflow")?;
    if required_real_actions > action_capacity {
        return Ok(None);
    }

    if stage_count == 2 {
        if let Some(stages) = exact_two_root_plan(input_values, terminals, fee_per_stage_zatoshi)? {
            return Ok(Some(stages));
        }
    }

    if stage_count > 1 {
        if let Some(stages) =
            bounded_forest_plan(input_values, terminals, stage_count, fee_per_stage_zatoshi)?
        {
            return Ok(Some(stages));
        }
    }

    connected_chain_plan(input_values, terminals, stage_count, fee_per_stage_zatoshi)
}

#[derive(Default)]
struct ForestSearchBudget {
    nodes: usize,
    exhausted: bool,
}

impl ForestSearchBudget {
    fn charge(&mut self) -> bool {
        if self.nodes >= FOREST_SEARCH_NODE_LIMIT {
            self.exhausted = true;
            false
        } else {
            self.nodes += 1;
            true
        }
    }
}

struct ForestSearch<'a> {
    input_values: &'a [u64],
    terminals: &'a [SplitTerminalOutput],
    fee_per_stage_zatoshi: u64,
    budget: ForestSearchBudget,
    failed: HashSet<(u64, u64, usize)>,
}

fn bounded_forest_plan(
    input_values: &[u64],
    terminals: &[SplitTerminalOutput],
    stage_count: usize,
    fee_per_stage_zatoshi: u64,
) -> Result<Option<Vec<SplitStagePlan>>, String> {
    // The fixed masks keep the exact search allocation-free and bounded. Larger
    // wallets still use the deterministic value-pooling chain below.
    if input_values.len() > u64::BITS as usize || terminals.len() > u64::BITS as usize {
        return Ok(None);
    }

    let mut search = ForestSearch {
        input_values,
        terminals,
        fee_per_stage_zatoshi,
        budget: ForestSearchBudget::default(),
        failed: HashSet::new(),
    };
    search.search(
        low_bits(input_values.len()),
        low_bits(terminals.len()),
        stage_count,
    )
}

fn low_bits(count: usize) -> u64 {
    if count == u64::BITS as usize {
        u64::MAX
    } else {
        (1u64 << count) - 1
    }
}

impl ForestSearch<'_> {
    fn search(
        &mut self,
        remaining_inputs: u64,
        remaining_outputs: u64,
        stages_left: usize,
    ) -> Result<Option<Vec<SplitStagePlan>>, String> {
        if self.budget.exhausted || !self.budget.charge() {
            return Ok(None);
        }
        if stages_left == 0 {
            return Ok((remaining_inputs == 0 && remaining_outputs == 0).then(Vec::new));
        }
        if remaining_inputs == 0 || remaining_outputs == 0 {
            return Ok(None);
        }

        let state = (remaining_inputs, remaining_outputs, stages_left);
        if self.failed.contains(&state) {
            return Ok(None);
        }

        let input_count = remaining_inputs.count_ones() as usize;
        let output_count = remaining_outputs.count_ones() as usize;
        let maximum_roots = input_count.min(output_count).min(stages_left);
        let minimum_edges = stages_left.saturating_sub(maximum_roots);
        let minimum_continuation_actions = minimum_edges
            .checked_mul(2)
            .ok_or("Denomination forest continuation action overflow")?;
        let minimum_actions = input_count
            .checked_add(output_count)
            .and_then(|count| count.checked_add(minimum_continuation_actions))
            .ok_or("Denomination forest action count overflow")?;
        let action_capacity = DENOMINATION_SPLIT_ACTIONS
            .checked_mul(stages_left)
            .ok_or("Denomination forest action capacity overflow")?;
        if minimum_actions > action_capacity
            || !self.remaining_value_balances(remaining_inputs, remaining_outputs, stages_left)?
        {
            self.failed.insert(state);
            return Ok(None);
        }

        let anchor = 1u64 << remaining_inputs.trailing_zeros();
        let optional_inputs = remaining_inputs & !anchor;
        let mut optional_selection = 0u64;

        loop {
            if !self.budget.charge() {
                return Ok(None);
            }
            let component_inputs = anchor | optional_selection;
            let component_input_count = component_inputs.count_ones() as usize;
            let component_input_total = self.input_sum(component_inputs)?;

            // Shorter components are tried first, which prefers more roots and
            // shallower confirmation dependencies for a fixed stage count.
            for component_stages in 1..=stages_left {
                let item_capacity = component_item_capacity(component_stages)?;
                if component_input_count >= item_capacity {
                    continue;
                }
                let component_fee = u128::from(self.fee_per_stage_zatoshi)
                    .checked_mul(component_stages as u128)
                    .ok_or("Denomination component fee overflow")?;
                let Some(wanted_output_total) = component_input_total.checked_sub(component_fee)
                else {
                    continue;
                };
                if wanted_output_total == 0 {
                    continue;
                }
                let maximum_outputs = item_capacity - component_input_count;
                let output_selections = self.output_selections(
                    remaining_outputs,
                    wanted_output_total,
                    maximum_outputs,
                )?;
                for component_outputs in output_selections {
                    if self.budget.exhausted {
                        return Ok(None);
                    }
                    let next_inputs = remaining_inputs & !component_inputs;
                    let next_outputs = remaining_outputs & !component_outputs;
                    let next_stages = stages_left - component_stages;
                    if (next_stages == 0) != (next_inputs == 0 && next_outputs == 0)
                        || (next_stages > 0 && (next_inputs == 0 || next_outputs == 0))
                    {
                        continue;
                    }

                    let Some(mut component) =
                        self.component_plan(component_inputs, component_outputs, component_stages)?
                    else {
                        continue;
                    };
                    let Some(mut remainder) =
                        self.search(next_inputs, next_outputs, next_stages)?
                    else {
                        continue;
                    };
                    component.append(&mut remainder);
                    return Ok(Some(component));
                }
            }

            if optional_selection == optional_inputs {
                break;
            }
            optional_selection = optional_selection.wrapping_sub(optional_inputs) & optional_inputs;
        }

        if !self.budget.exhausted {
            self.failed.insert(state);
        }
        Ok(None)
    }

    fn remaining_value_balances(
        &self,
        input_mask: u64,
        output_mask: u64,
        stages: usize,
    ) -> Result<bool, String> {
        let inputs = self.input_sum(input_mask)?;
        let outputs = self.output_sum(output_mask)?;
        let fees = u128::from(self.fee_per_stage_zatoshi)
            .checked_mul(stages as u128)
            .ok_or("Denomination remaining fee overflow")?;
        Ok(outputs.checked_add(fees) == Some(inputs))
    }

    fn input_sum(&self, mask: u64) -> Result<u128, String> {
        masked_sum(
            mask,
            |index| self.input_values[index],
            "Denomination forest input overflow",
        )
    }

    fn output_sum(&self, mask: u64) -> Result<u128, String> {
        masked_sum(
            mask,
            |index| self.terminals[index].value_zatoshi,
            "Denomination forest output overflow",
        )
    }

    fn output_selections(
        &mut self,
        remaining_outputs: u64,
        wanted_total: u128,
        maximum_count: usize,
    ) -> Result<Vec<u64>, String> {
        if maximum_count == 0 || wanted_total > self.output_sum(remaining_outputs)? {
            return Ok(Vec::new());
        }
        let mut output_indices = bit_indices(remaining_outputs);
        output_indices.sort_by_key(|index| {
            (
                self.terminals[*index].value_zatoshi,
                self.terminals[*index].logical_index,
            )
        });
        let mut groups = Vec::<OutputValueGroup>::new();
        for index in output_indices {
            let value_zatoshi = self.terminals[index].value_zatoshi;
            if let Some(group) = groups
                .last_mut()
                .filter(|group| group.value_zatoshi == value_zatoshi)
            {
                group.indices.push(index);
            } else {
                groups.push(OutputValueGroup {
                    value_zatoshi,
                    indices: vec![index],
                });
            }
        }

        let mut selections = Vec::new();
        enumerate_grouped_outputs(
            &groups,
            0,
            wanted_total,
            maximum_count,
            0,
            0,
            &mut self.budget,
            &mut selections,
        )?;
        Ok(selections)
    }

    fn component_plan(
        &self,
        input_mask: u64,
        output_mask: u64,
        stage_count: usize,
    ) -> Result<Option<Vec<SplitStagePlan>>, String> {
        let input_indices = bit_indices(input_mask);
        let input_values = input_indices
            .iter()
            .map(|index| self.input_values[*index])
            .collect::<Vec<_>>();
        let outputs = bit_indices(output_mask)
            .into_iter()
            .map(|index| self.terminals[index].clone())
            .collect::<Vec<_>>();
        let Some(mut stages) = connected_chain_plan(
            &input_values,
            &outputs,
            stage_count,
            self.fee_per_stage_zatoshi,
        )?
        else {
            return Ok(None);
        };
        for stage in &mut stages {
            for index in &mut stage.original_input_indices {
                *index = input_indices[*index];
            }
        }
        Ok(Some(stages))
    }
}

fn component_item_capacity(stage_count: usize) -> Result<usize, String> {
    if stage_count == 1 {
        Ok(DENOMINATION_SPLIT_ACTIONS)
    } else {
        14usize
            .checked_mul(stage_count)
            .and_then(|count| count.checked_add(2))
            .ok_or_else(|| "Denomination component capacity overflow".to_string())
    }
}

fn masked_sum(
    mask: u64,
    value_at: impl Fn(usize) -> u64,
    overflow_message: &str,
) -> Result<u128, String> {
    bit_indices(mask).into_iter().try_fold(0u128, |sum, index| {
        sum.checked_add(u128::from(value_at(index)))
            .ok_or_else(|| overflow_message.to_string())
    })
}

fn bit_indices(mut mask: u64) -> Vec<usize> {
    let mut indices = Vec::with_capacity(mask.count_ones() as usize);
    while mask != 0 {
        let index = mask.trailing_zeros() as usize;
        indices.push(index);
        mask &= mask - 1;
    }
    indices
}

struct OutputValueGroup {
    value_zatoshi: u64,
    indices: Vec<usize>,
}

#[allow(clippy::too_many_arguments)]
fn enumerate_grouped_outputs(
    groups: &[OutputValueGroup],
    group_index: usize,
    remaining_total: u128,
    maximum_count: usize,
    selected_count: usize,
    selected_mask: u64,
    budget: &mut ForestSearchBudget,
    selections: &mut Vec<u64>,
) -> Result<(), String> {
    if !budget.charge() {
        return Ok(());
    }
    if remaining_total == 0 {
        if selected_count > 0 {
            selections.push(selected_mask);
        }
        return Ok(());
    }
    if group_index == groups.len() || selected_count == maximum_count {
        return Ok(());
    }
    let remaining_slots = maximum_count - selected_count;
    if remaining_total > maximum_grouped_output_sum(&groups[group_index..], remaining_slots)? {
        return Ok(());
    }

    let group = &groups[group_index];
    let maximum_take = group.indices.len().min(maximum_count - selected_count);
    for take in 0..=maximum_take {
        let value = u128::from(group.value_zatoshi)
            .checked_mul(take as u128)
            .ok_or("Denomination grouped output overflow")?;
        if value > remaining_total {
            break;
        }
        let mut next_mask = selected_mask;
        for index in group.indices.iter().take(take) {
            next_mask |= 1u64 << index;
        }
        enumerate_grouped_outputs(
            groups,
            group_index + 1,
            remaining_total - value,
            maximum_count,
            selected_count + take,
            next_mask,
            budget,
            selections,
        )?;
        if budget.exhausted {
            return Ok(());
        }
    }
    Ok(())
}

fn maximum_grouped_output_sum(
    groups: &[OutputValueGroup],
    mut remaining_slots: usize,
) -> Result<u128, String> {
    let mut total = 0u128;
    for group in groups.iter().rev() {
        let take = group.indices.len().min(remaining_slots);
        total = total
            .checked_add(
                u128::from(group.value_zatoshi)
                    .checked_mul(take as u128)
                    .ok_or("Denomination grouped output overflow")?,
            )
            .ok_or("Denomination grouped output total overflow")?;
        remaining_slots -= take;
        if remaining_slots == 0 {
            break;
        }
    }
    Ok(total)
}

#[derive(Clone, Copy)]
enum PartitionItem {
    Input(usize),
    Output(usize),
}

#[derive(Clone, Copy)]
struct HalfSubset {
    signed_sum: i128,
    input_count: u8,
    output_count: u8,
    mask: u32,
}

fn enumerate_half(
    items: &[PartitionItem],
    inputs: &[u64],
    outputs: &[SplitTerminalOutput],
) -> Vec<HalfSubset> {
    debug_assert!(items.len() <= 16);
    let mut subsets = Vec::with_capacity(1usize << items.len());
    for mask in 0..(1u32 << items.len()) {
        let mut signed_sum = 0i128;
        let mut input_count = 0u8;
        let mut output_count = 0u8;
        for (bit, item) in items.iter().enumerate() {
            if mask & (1u32 << bit) == 0 {
                continue;
            }
            match item {
                PartitionItem::Input(index) => {
                    signed_sum += i128::from(inputs[*index]);
                    input_count += 1;
                }
                PartitionItem::Output(index) => {
                    signed_sum -= i128::from(outputs[*index].value_zatoshi);
                    output_count += 1;
                }
            }
        }
        subsets.push(HalfSubset {
            signed_sum,
            input_count,
            output_count,
            mask,
        });
    }
    subsets
}

/// Finds two independent, exactly balanced roots. This is a meet-in-the-middle
/// search over at most 32 real items, which covers the 2-input/30-output case
/// without an exponential 30-output scan.
fn exact_two_root_plan(
    input_values: &[u64],
    terminals: &[SplitTerminalOutput],
    fee_per_stage_zatoshi: u64,
) -> Result<Option<Vec<SplitStagePlan>>, String> {
    let item_count = input_values
        .len()
        .checked_add(terminals.len())
        .ok_or("Denomination partition item count overflow")?;
    if input_values.len() < 2 || terminals.len() < 2 || item_count > DENOMINATION_SPLIT_ACTIONS * 2
    {
        return Ok(None);
    }

    let mut items = (0..input_values.len())
        .map(PartitionItem::Input)
        .chain((0..terminals.len()).map(PartitionItem::Output))
        .collect::<Vec<_>>();
    let second_items = items.split_off(item_count / 2);
    let first_items = items;
    let second_subsets = enumerate_half(&second_items, input_values, terminals);
    let mut second_by_key = HashMap::with_capacity(second_subsets.len());
    for subset in second_subsets {
        second_by_key
            .entry((subset.signed_sum, subset.input_count, subset.output_count))
            .or_insert(subset.mask);
    }

    let wanted = i128::from(fee_per_stage_zatoshi);
    for first in enumerate_half(&first_items, input_values, terminals) {
        for total_inputs in 1..input_values.len() {
            for total_outputs in 1..terminals.len() {
                let selected_count = total_inputs + total_outputs;
                if selected_count > DENOMINATION_SPLIT_ACTIONS
                    || item_count - selected_count > DENOMINATION_SPLIT_ACTIONS
                    || usize::from(first.input_count) > total_inputs
                    || usize::from(first.output_count) > total_outputs
                {
                    continue;
                }
                let needed_inputs = total_inputs - usize::from(first.input_count);
                let needed_outputs = total_outputs - usize::from(first.output_count);
                let (Ok(needed_inputs), Ok(needed_outputs)) =
                    (u8::try_from(needed_inputs), u8::try_from(needed_outputs))
                else {
                    continue;
                };
                let key = (wanted - first.signed_sum, needed_inputs, needed_outputs);
                let Some(second_mask) = second_by_key.get(&key).copied() else {
                    continue;
                };

                let mut selected_inputs = HashSet::new();
                let mut selected_outputs = HashSet::new();
                collect_partition_selection(
                    &first_items,
                    first.mask,
                    &mut selected_inputs,
                    &mut selected_outputs,
                );
                collect_partition_selection(
                    &second_items,
                    second_mask,
                    &mut selected_inputs,
                    &mut selected_outputs,
                );
                let mut first_stage = root_stage_from_selection(
                    input_values,
                    terminals,
                    &selected_inputs,
                    &selected_outputs,
                    fee_per_stage_zatoshi,
                )?;
                let other_inputs = (0..input_values.len())
                    .filter(|index| !selected_inputs.contains(index))
                    .collect::<HashSet<_>>();
                let other_outputs = (0..terminals.len())
                    .filter(|index| !selected_outputs.contains(index))
                    .collect::<HashSet<_>>();
                let mut second_stage = root_stage_from_selection(
                    input_values,
                    terminals,
                    &other_inputs,
                    &other_outputs,
                    fee_per_stage_zatoshi,
                )?;
                if first_stage.original_input_indices > second_stage.original_input_indices {
                    std::mem::swap(&mut first_stage, &mut second_stage);
                }
                return Ok(Some(vec![first_stage, second_stage]));
            }
        }
    }

    Ok(None)
}

fn collect_partition_selection(
    items: &[PartitionItem],
    mask: u32,
    selected_inputs: &mut HashSet<usize>,
    selected_outputs: &mut HashSet<usize>,
) {
    for (bit, item) in items.iter().enumerate() {
        if mask & (1u32 << bit) == 0 {
            continue;
        }
        match item {
            PartitionItem::Input(index) => {
                selected_inputs.insert(*index);
            }
            PartitionItem::Output(index) => {
                selected_outputs.insert(*index);
            }
        }
    }
}

fn root_stage_from_selection(
    input_values: &[u64],
    terminals: &[SplitTerminalOutput],
    selected_inputs: &HashSet<usize>,
    selected_outputs: &HashSet<usize>,
    fee_per_stage_zatoshi: u64,
) -> Result<SplitStagePlan, String> {
    let mut original_input_indices = selected_inputs.iter().copied().collect::<Vec<_>>();
    original_input_indices.sort_unstable();
    let mut terminal_indices = selected_outputs.iter().copied().collect::<Vec<_>>();
    terminal_indices.sort_unstable();
    let terminal_outputs = terminal_indices
        .into_iter()
        .map(|index| terminals[index].clone())
        .collect::<Vec<_>>();
    let input_total = original_input_indices.iter().try_fold(0u64, |acc, index| {
        acc.checked_add(input_values[*index])
            .ok_or_else(|| "Denomination root input overflow".to_string())
    })?;
    let output_total = terminal_outputs.iter().try_fold(0u64, |acc, output| {
        acc.checked_add(output.value_zatoshi)
            .ok_or_else(|| "Denomination root output overflow".to_string())
    })?;
    if input_total.checked_sub(output_total) != Some(fee_per_stage_zatoshi) {
        return Err("Denomination root partition is not value balanced".to_string());
    }
    let requested_actions = original_input_indices.len() + terminal_outputs.len();
    if requested_actions > DENOMINATION_SPLIT_ACTIONS {
        return Err("Denomination root exceeds the padded action limit".to_string());
    }
    Ok(SplitStagePlan {
        original_input_indices,
        spends_previous_continuation: false,
        terminal_outputs,
        continuation_value_zatoshi: None,
        fee_zatoshi: fee_per_stage_zatoshi,
        requested_actions,
    })
}

fn connected_chain_plan(
    input_values: &[u64],
    terminals: &[SplitTerminalOutput],
    stage_count: usize,
    fee_per_stage_zatoshi: u64,
) -> Result<Option<Vec<SplitStagePlan>>, String> {
    let mut input_order = (0..input_values.len()).collect::<Vec<_>>();
    input_order.sort_by_key(|index| (std::cmp::Reverse(input_values[*index]), *index));
    let mut output_order = terminals.to_vec();
    output_order.sort_by_key(|output| (output.value_zatoshi, output.logical_index));

    let input_prefix = prefix_sums(
        input_order.iter().map(|index| input_values[*index]),
        "Denomination input prefix overflow",
    )?;
    let output_prefix = prefix_sums(
        output_order.iter().map(|output| output.value_zatoshi),
        "Denomination output prefix overflow",
    )?;
    let mut failed = HashSet::new();
    let mut reversed = Vec::with_capacity(stage_count);
    let found = search_chain(
        0,
        0,
        0,
        stage_count,
        fee_per_stage_zatoshi,
        &input_order,
        &output_order,
        &input_prefix,
        &output_prefix,
        &mut failed,
        &mut reversed,
    )?;
    if !found {
        return Ok(None);
    }
    reversed.reverse();
    Ok(Some(reversed))
}

fn prefix_sums(
    values: impl IntoIterator<Item = u64>,
    overflow_message: &str,
) -> Result<Vec<u128>, String> {
    let mut sums = vec![0u128];
    for value in values {
        let next = sums
            .last()
            .copied()
            .and_then(|sum| sum.checked_add(u128::from(value)))
            .ok_or_else(|| overflow_message.to_string())?;
        sums.push(next);
    }
    Ok(sums)
}

#[allow(clippy::too_many_arguments)]
fn search_chain(
    stage_index: usize,
    input_offset: usize,
    output_offset: usize,
    stage_count: usize,
    fee_per_stage_zatoshi: u64,
    input_order: &[usize],
    output_order: &[SplitTerminalOutput],
    input_prefix: &[u128],
    output_prefix: &[u128],
    failed: &mut HashSet<(usize, usize, usize)>,
    reversed: &mut Vec<SplitStagePlan>,
) -> Result<bool, String> {
    let state = (stage_index, input_offset, output_offset);
    if failed.contains(&state) {
        return Ok(false);
    }

    let final_stage = stage_index + 1 == stage_count;
    let previous_spend = usize::from(stage_index > 0);
    let continuation_output = usize::from(!final_stage);
    let capacity = DENOMINATION_SPLIT_ACTIONS
        .checked_sub(previous_spend + continuation_output)
        .ok_or("Denomination stage capacity underflow")?;
    let remaining_inputs = input_order.len() - input_offset;
    let remaining_outputs = output_order.len() - output_offset;

    let input_range = if final_stage {
        remaining_inputs..=remaining_inputs
    } else {
        let minimum = usize::from(stage_index == 0);
        minimum..=remaining_inputs.min(capacity)
    };

    for take_inputs in input_range {
        let output_capacity = capacity.saturating_sub(take_inputs);
        let output_range = if final_stage {
            remaining_outputs..=remaining_outputs
        } else {
            0..=remaining_outputs.min(output_capacity)
        };
        for take_outputs in output_range.rev() {
            if take_inputs + take_outputs > capacity
                || (final_stage && take_outputs == 0)
                || (!final_stage && take_inputs == 0 && take_outputs == 0)
            {
                continue;
            }
            let next_input = input_offset + take_inputs;
            let next_output = output_offset + take_outputs;
            let input_total = input_prefix[next_input] - input_prefix[input_offset];
            let output_total = output_prefix[next_output] - output_prefix[output_offset];
            let previous_value = if stage_index == 0 {
                0
            } else {
                let consumed_inputs = input_prefix[input_offset];
                let emitted_outputs = output_prefix[output_offset];
                let paid_fees = u128::from(fee_per_stage_zatoshi)
                    .checked_mul(stage_index as u128)
                    .ok_or("Denomination paid fee overflow")?;
                let carried = consumed_inputs
                    .checked_sub(emitted_outputs)
                    .and_then(|value| value.checked_sub(paid_fees));
                let Some(carried) = carried else {
                    continue;
                };
                carried
            };
            let available = previous_value
                .checked_add(input_total)
                .ok_or("Denomination stage value overflow")?;
            let required = output_total
                .checked_add(u128::from(fee_per_stage_zatoshi))
                .ok_or("Denomination stage required value overflow")?;
            let Some(remainder) = available.checked_sub(required) else {
                continue;
            };
            if final_stage {
                if remainder != 0
                    || next_input != input_order.len()
                    || next_output != output_order.len()
                {
                    continue;
                }
            } else if remainder == 0 {
                continue;
            }

            let can_finish = if final_stage {
                true
            } else {
                search_chain(
                    stage_index + 1,
                    next_input,
                    next_output,
                    stage_count,
                    fee_per_stage_zatoshi,
                    input_order,
                    output_order,
                    input_prefix,
                    output_prefix,
                    failed,
                    reversed,
                )?
            };
            if !can_finish {
                continue;
            }

            let continuation_value_zatoshi = if final_stage {
                None
            } else {
                Some(
                    u64::try_from(remainder)
                        .map_err(|_| "Denomination continuation value overflow".to_string())?,
                )
            };
            reversed.push(SplitStagePlan {
                original_input_indices: input_order[input_offset..next_input].to_vec(),
                spends_previous_continuation: stage_index > 0,
                terminal_outputs: output_order[output_offset..next_output].to_vec(),
                continuation_value_zatoshi,
                fee_zatoshi: fee_per_stage_zatoshi,
                requested_actions: previous_spend
                    + take_inputs
                    + take_outputs
                    + continuation_output,
            });
            return Ok(true);
        }
    }

    failed.insert(state);
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FEE: u64 = 80_000;

    fn terminals(count: usize, value: u64) -> Vec<SplitTerminalOutput> {
        (0..count)
            .map(|logical_index| SplitTerminalOutput {
                logical_index,
                value_zatoshi: value,
                kind: SplitTerminalKind::Migration,
            })
            .collect()
    }

    fn assert_plan_balances(
        input_values: &[u64],
        outputs: &[SplitTerminalOutput],
        stages: &[SplitStagePlan],
    ) {
        let mut carry = 0u64;
        let mut used_inputs = HashSet::new();
        let mut used_outputs = HashSet::new();
        for stage in stages {
            let spend_actions = stage.original_input_indices.len()
                + usize::from(stage.spends_previous_continuation);
            let output_actions = stage.terminal_outputs.len()
                + usize::from(stage.continuation_value_zatoshi.is_some());
            assert_eq!(stage.requested_actions, spend_actions + output_actions);
            assert!(stage.requested_actions <= DENOMINATION_SPLIT_ACTIONS);
            if stage.spends_previous_continuation {
                assert!(carry > 0);
            } else {
                assert_eq!(carry, 0);
            }
            let input_total = stage
                .original_input_indices
                .iter()
                .map(|index| {
                    assert!(used_inputs.insert(*index));
                    input_values[*index]
                })
                .sum::<u64>();
            let output_total = stage
                .terminal_outputs
                .iter()
                .map(|output| {
                    assert!(used_outputs.insert(output.logical_index));
                    output.value_zatoshi
                })
                .sum::<u64>();
            let remainder = carry + input_total - output_total - stage.fee_zatoshi;
            assert_eq!(
                stage.continuation_value_zatoshi,
                (remainder > 0).then_some(remainder)
            );
            carry = remainder;
        }
        assert_eq!(carry, 0);
        assert_eq!(used_inputs.len(), input_values.len());
        assert_eq!(used_outputs.len(), outputs.len());
    }

    #[test]
    fn nu6_3_v6_orchard_uses_restricted_sum_action_counts() {
        let bundle_type = orchard::builder::BundleType::Transactional {
            bundle_required: false,
            pad_to_minimum: Some(DENOMINATION_SPLIT_ACTIONS as u8),
        };
        let flags = orchard::bundle::Flags::CROSS_ADDRESS_DISABLED;

        assert_eq!(
            flags.to_byte(orchard::bundle::BundleVersion::orchard_v3()),
            Some(0b011)
        );
        assert_eq!(
            orchard::bundle::Flags::ENABLED.to_byte(orchard::bundle::BundleVersion::orchard_v3()),
            None
        );
        assert_eq!(bundle_type.num_actions(flags, 1, 15), Ok(16));
        assert_eq!(bundle_type.num_actions(flags, 1, 16), Ok(17));
        assert_eq!(bundle_type.num_actions(flags, 2, 14), Ok(16));
        assert_eq!(
            bundle_type.num_actions(orchard::bundle::Flags::ENABLED, 1, 16),
            Ok(16)
        );
    }

    #[test]
    fn padded_planning_requires_exact_fee_invariants() {
        assert_eq!(
            plan_padded_denominations(
                &[1_000_000],
                FEE,
                15_000,
                2,
                64,
                WalletNetwork::Main,
            )
            .unwrap_err(),
            "Padded denomination stages require a 1-zatoshi minimum output to preserve the exact ZIP 317 fee"
        );

        let outputs = terminals(1, 0);
        assert_eq!(
            plan_exact_stage_count(&[FEE], &outputs, 1, FEE).unwrap_err(),
            "Padded denomination terminal values must be positive"
        );
    }

    #[test]
    fn testnet_padded_planning_uses_small_denominations() {
        let plan =
            plan_padded_denominations(&[11_180_000], FEE, 15_000, 1, 64, WalletNetwork::Test)
                .unwrap()
                .unwrap();

        assert_eq!(
            plan.denominations.migration_outputs,
            vec![10_000_000, 1_000_000, 100_000]
        );
        assert_eq!(plan.stages.len(), 1);
        assert_plan_balances(
            &[11_180_000],
            &terminal_outputs(&plan.denominations),
            &plan.stages,
        );
    }

    #[test]
    fn testnet_point_nine_zec_balance_fits_reusable_migration_batch() {
        let input_values = [90_000_000];
        let plan =
            plan_padded_denominations(&input_values, FEE, 15_000, 1, 64, WalletNetwork::Test)
                .unwrap()
                .unwrap();

        assert_eq!(plan.stages.len(), 2);
        assert_eq!(plan.denominations.split_fee_zatoshi, 2 * FEE);
        assert_eq!(plan.denominations.migration_outputs.len(), 26);
        assert_eq!(
            plan.denominations
                .migration_outputs
                .iter()
                .filter(|value| **value == 10_000_000)
                .count(),
            8
        );
        assert_eq!(
            plan.denominations
                .migration_outputs
                .iter()
                .filter(|value| **value == 1_000_000)
                .count(),
            9
        );
        assert_eq!(
            plan.denominations
                .migration_outputs
                .iter()
                .filter(|value| **value == 100_000)
                .count(),
            8
        );
        assert_eq!(plan.denominations.migration_outputs.last(), Some(&40_000));
        assert_plan_balances(
            &input_values,
            &terminal_outputs(&plan.denominations),
            &plan.stages,
        );
    }

    #[test]
    fn one_input_and_thirty_outputs_need_three_padded_stages() {
        let outputs = terminals(30, 1_000_000);
        let inputs = [30_000_000 + 3 * FEE];

        assert!(plan_exact_stage_count(&inputs, &outputs, 2, FEE)
            .unwrap()
            .is_none());
        let stages = plan_exact_stage_count(&inputs, &outputs, 3, FEE)
            .unwrap()
            .unwrap();

        assert_eq!(stages.len(), 3);
        assert_eq!(
            stages
                .iter()
                .map(|stage| stage.requested_actions)
                .collect::<Vec<_>>(),
            vec![16, 16, 3]
        );
        assert_eq!(
            stages
                .iter()
                .map(SplitStagePlan::padding_actions)
                .collect::<Vec<_>>(),
            vec![0, 0, 13]
        );
        assert_eq!(
            stages
                .iter()
                .flat_map(|stage| stage.terminal_outputs.iter())
                .count(),
            30
        );
    }

    #[test]
    fn one_input_two_stage_chain_caps_at_twenty_nine_outputs() {
        let outputs = terminals(29, 1_000_000);
        let inputs = [29_000_000 + 2 * FEE];
        let stages = plan_exact_stage_count(&inputs, &outputs, 2, FEE)
            .unwrap()
            .unwrap();

        assert_eq!(
            stages
                .iter()
                .map(|stage| stage.requested_actions)
                .collect::<Vec<_>>(),
            vec![16, 16]
        );

        let outputs = terminals(30, 1_000_000);
        let inputs = [30_000_000 + 2 * FEE];
        assert!(plan_exact_stage_count(&inputs, &outputs, 2, FEE)
            .unwrap()
            .is_none());
    }

    #[test]
    fn independently_fundable_inputs_make_two_full_roots() {
        let outputs = terminals(30, 1_000_000);
        let inputs = [15_000_000 + FEE, 15_000_000 + FEE];
        let stages = plan_exact_stage_count(&inputs, &outputs, 2, FEE)
            .unwrap()
            .unwrap();

        assert_eq!(stages.len(), 2);
        assert!(stages
            .iter()
            .all(|stage| !stage.spends_previous_continuation));
        assert!(stages
            .iter()
            .all(|stage| stage.continuation_value_zatoshi.is_none()));
        assert!(stages.iter().all(|stage| stage.requested_actions == 16));
        assert!(stages.iter().all(|stage| stage.padding_actions() == 0));
    }

    #[test]
    fn two_roots_require_an_exact_value_partition() {
        let outputs = terminals(30, 1_000_000);
        let inputs = [14_000_000 + FEE, 16_000_000 + FEE];

        assert!(exact_two_root_plan(&inputs, &outputs, FEE)
            .unwrap()
            .is_none());
        assert!(plan_exact_stage_count(&inputs, &outputs, 2, FEE)
            .unwrap()
            .is_none());
    }

    #[test]
    fn confirmed_inputs_can_join_a_later_chain_stage() {
        let outputs = terminals(20, 1_000_000);
        let inputs = [5_000_000, 15_000_000 + 2 * FEE];
        let stages = plan_exact_stage_count(&inputs, &outputs, 2, FEE)
            .unwrap()
            .unwrap();

        assert_eq!(stages.len(), 2);
        assert_eq!(
            stages
                .iter()
                .flat_map(|stage| stage.original_input_indices.iter())
                .copied()
                .collect::<HashSet<_>>(),
            HashSet::from([0, 1])
        );
        assert_eq!(stages[1].spends_previous_continuation, true);
    }

    #[test]
    fn three_inputs_can_fund_three_independent_roots_instead_of_four_chain_stages() {
        let outputs = terminals(45, 1_000_000);
        let inputs = [15_000_000 + FEE; 3];

        assert!(connected_chain_plan(&inputs, &outputs, 3, FEE)
            .unwrap()
            .is_none());
        let stages = plan_exact_stage_count(&inputs, &outputs, 3, FEE)
            .unwrap()
            .unwrap();

        assert_eq!(stages.len(), 3);
        assert!(stages
            .iter()
            .all(|stage| !stage.spends_previous_continuation));
        assert!(stages
            .iter()
            .all(|stage| stage.requested_actions == DENOMINATION_SPLIT_ACTIONS));
        assert_plan_balances(&inputs, &outputs, &stages);
    }

    #[test]
    fn three_inputs_can_fund_a_root_plus_a_two_stage_component() {
        let outputs = terminals(42, 1_000_000);
        let inputs = [14_000_000 + FEE, 10_000_000, 18_000_000 + 2 * FEE];

        assert!(connected_chain_plan(&inputs, &outputs, 3, FEE)
            .unwrap()
            .is_none());
        let stages = plan_exact_stage_count(&inputs, &outputs, 3, FEE)
            .unwrap()
            .unwrap();

        assert_eq!(stages.len(), 3);
        assert_eq!(
            stages
                .iter()
                .filter(|stage| !stage.spends_previous_continuation)
                .count(),
            2
        );
        assert_eq!(
            stages
                .iter()
                .filter(|stage| stage.spends_previous_continuation)
                .count(),
            1
        );
        assert_plan_balances(&inputs, &outputs, &stages);
    }

    #[test]
    fn forced_thirty_outputs_can_use_three_roots_for_many_existing_inputs() {
        let outputs = terminals(30, 1_000_000);
        let mut inputs = vec![1_000_000; 16];
        inputs[4] = 7_000_000 + FEE;
        inputs[9] = 7_000_000 + FEE;
        inputs[15] = 3_000_000 + FEE;

        assert!(connected_chain_plan(&inputs, &outputs, 3, FEE)
            .unwrap()
            .is_none());
        let stages = plan_exact_stage_count(&inputs, &outputs, 3, FEE)
            .unwrap()
            .unwrap();

        assert_eq!(stages.len(), 3);
        assert!(stages
            .iter()
            .all(|stage| !stage.spends_previous_continuation));
        assert_eq!(
            stages
                .iter()
                .map(|stage| stage.requested_actions)
                .sum::<usize>(),
            inputs.len() + outputs.len()
        );
        assert_plan_balances(&inputs, &outputs, &stages);
    }
}
