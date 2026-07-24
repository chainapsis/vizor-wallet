fn random_schedule_block_offsets_with_rng<R: Rng + ?Sized>(
    count: usize,
    mean_delay_blocks: u32,
    max_delay_blocks: u32,
    rng: &mut R,
) -> Vec<u32> {
    assert!(mean_delay_blocks > 0);
    assert!(max_delay_blocks > 0);

    let mut offsets = Vec::with_capacity(count);
    let mut elapsed_blocks = 0u32;
    for _ in 0..count {
        let delay = loop {
            let uniform = rng.gen_range(f64::MIN_POSITIVE..1.0);
            let sampled = (-uniform.ln() * f64::from(mean_delay_blocks)).ceil() as u32;
            let sampled = sampled.max(1);
            if sampled <= max_delay_blocks {
                break sampled;
            }
        };
        elapsed_blocks = elapsed_blocks.saturating_add(delay);
        offsets.push(elapsed_blocks);
    }
    offsets
}

pub(crate) fn planned_transfer_schedule<R, I>(
    values: I,
    network: WalletNetwork,
    rng: &mut R,
) -> Vec<MigrationScheduleEntry>
where
    R: Rng + ?Sized,
    I: IntoIterator<Item = u64>,
{
    planned_transfer_schedule_for_parts_with_policy(
        values
            .into_iter()
            .enumerate()
            .map(|(part_index, value_zatoshi)| (part_index as u32, value_zatoshi)),
        network,
        configured_timing_policy(network),
        rng,
    )
}

fn planned_transfer_schedule_with_policy<R, I>(
    values: I,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    rng: &mut R,
) -> Vec<MigrationScheduleEntry>
where
    R: Rng + ?Sized,
    I: IntoIterator<Item = u64>,
{
    planned_transfer_schedule_for_parts_with_policy(
        values
            .into_iter()
            .enumerate()
            .map(|(part_index, value_zatoshi)| (part_index as u32, value_zatoshi)),
        network,
        timing_policy,
        rng,
    )
}

fn planned_transfer_schedule_for_parts_with_policy<R, I>(
    parts: I,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    rng: &mut R,
) -> Vec<MigrationScheduleEntry>
where
    R: Rng + ?Sized,
    I: IntoIterator<Item = (u32, u64)>,
{
    let mut parts = parts.into_iter().collect::<Vec<_>>();
    parts.shuffle(rng);
    let (mean_delay_blocks, max_delay_blocks) =
        schedule_parameters_with_policy(network, timing_policy);
    let offsets = std::iter::once(0)
        .chain(random_schedule_block_offsets_with_rng(
            parts.len().saturating_sub(1),
            mean_delay_blocks,
            max_delay_blocks,
            rng,
        ))
        .take(parts.len());
    parts
        .into_iter()
        .zip(offsets)
        .map(
            |((part_index, value_zatoshi), block_offset)| MigrationScheduleEntry {
                part_index: Some(part_index),
                value_zatoshi,
                block_offset,
            },
        )
        .collect()
}

pub(crate) fn validate_schedule(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    network: WalletNetwork,
) -> Result<(), String> {
    validate_schedule_with_policy(
        schedule,
        target_values,
        network,
        configured_timing_policy(network),
    )
}

fn validate_schedule_with_policy(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> Result<(), String> {
    if schedule.len() != target_values.len() {
        return Err("Approved migration schedule count changed".to_string());
    }
    let target_values_by_part = target_values.to_vec();
    let mut scheduled_values = schedule
        .iter()
        .map(|entry| entry.value_zatoshi)
        .collect::<Vec<_>>();
    let mut target_values = target_values_by_part.clone();
    scheduled_values.sort_unstable();
    target_values.sort_unstable();
    if scheduled_values != target_values {
        return Err("Approved migration schedule values changed".to_string());
    }
    validate_schedule_part_indexes(schedule, &target_values_by_part)?;

    let (_, max_delay_blocks) = schedule_parameters_with_policy(network, timing_policy);
    let mut previous_offset = 0;
    for (index, entry) in schedule.iter().enumerate() {
        let gap = entry
            .block_offset
            .checked_sub(previous_offset)
            .ok_or("Approved migration schedule is not ordered")?;
        let valid_gap = if index == 0 {
            gap <= max_delay_blocks
        } else {
            (1..=max_delay_blocks).contains(&gap)
        };
        if !valid_gap {
            return Err("Approved migration schedule delay is outside policy".to_string());
        }
        previous_offset = entry.block_offset;
    }
    Ok(())
}

fn validate_schedule_part_indexes(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
) -> Result<(), String> {
    if schedule.iter().all(|entry| entry.part_index.is_none()) {
        return Ok(());
    }
    if schedule.iter().any(|entry| entry.part_index.is_none()) {
        return Err("Approved migration schedule part indexes are incomplete".to_string());
    }

    let mut seen = BTreeSet::new();
    for entry in schedule {
        let part_index = entry
            .part_index
            .ok_or("Approved migration schedule part indexes are incomplete")?;
        let value = target_values
            .get(part_index as usize)
            .ok_or("Approved migration schedule part index is outside the plan")?;
        if !seen.insert(part_index) {
            return Err("Approved migration schedule part index is duplicated".to_string());
        }
        if *value != entry.value_zatoshi {
            return Err("Approved migration schedule part value changed".to_string());
        }
    }
    Ok(())
}
