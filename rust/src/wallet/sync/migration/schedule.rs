const UNIT_STEP: f64 = 1.0 / ((1u64 << 53) as f64);
const U64_TO_MANTISSA_SHIFT: u32 = 11;

fn draw_unit_left_open<R: RngCore + ?Sized>(rng: &mut R) -> f64 {
    1.0 - ((rng.next_u64() >> U64_TO_MANTISSA_SHIFT) as f64) * UNIT_STEP
}

fn round_nonnegative_to_u32(value: f64) -> u32 {
    (value + 0.5) as u64 as u32
}

pub(crate) fn seeded_custom_schedule_rng(plan_seed: u64) -> rand::rngs::StdRng {
    // Keep schedule draws independent from the amount-group draws.
    rand::SeedableRng::seed_from_u64(plan_seed ^ 0xa5a5_5a5a_d3c3_3c3c)
}

fn random_schedule_block_offsets_with_rng<R: RngCore + CryptoRng + ?Sized>(
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
            let uniform = draw_unit_left_open(rng);
            let sampled =
                round_nonnegative_to_u32(-uniform.ln() * f64::from(mean_delay_blocks));
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
    R: RngCore + CryptoRng + ?Sized,
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

/// Merges independent ZIP 318 broadcast lanes into one approved schedule.
/// Each lane retains the configured network mean interval; increasing
/// `parallel_schedule_count` compresses only the aggregate wall-clock schedule.
/// This models parallel schedules; transaction construction, signing, and
/// broadcast execution remain serialized by the migration send path.
pub(crate) fn planned_custom_transfer_schedule<R, I>(
    values: I,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    parallel_schedule_count: u32,
    rng: &mut R,
) -> Result<Vec<MigrationScheduleEntry>, String>
where
    R: RngCore + CryptoRng + ?Sized,
    I: IntoIterator<Item = u64>,
{
    validate_custom_parallel_schedule_count(parallel_schedule_count)?;
    let mut parts = values
        .into_iter()
        .enumerate()
        .map(|(part_index, value_zatoshi)| (part_index as u32, value_zatoshi))
        .collect::<Vec<_>>();
    let part_count = u32::try_from(parts.len())
        .map_err(|_| "Custom migration part count exceeds u32".to_string())?;
    let (_, max_delay_blocks) =
        custom_schedule_parameters(network, timing_policy, parallel_schedule_count, part_count)?;
    let (lane_mean_delay_blocks, _) = schedule_parameters_with_policy(network, timing_policy);
    let lane_count = usize::try_from(parallel_schedule_count.min(part_count.max(1)))
        .map_err(|_| "Custom migration parallel schedule count overflow".to_string())?;
    parts.shuffle(rng);

    let mut lanes = vec![Vec::new(); lane_count];
    for (index, part) in parts.into_iter().enumerate() {
        lanes[index % lane_count].push(part);
    }
    let mut merged = Vec::new();
    for lane in lanes {
        let offsets = random_schedule_block_offsets_with_rng(
            lane.len(),
            lane_mean_delay_blocks,
            max_delay_blocks,
            rng,
        );
        merged.extend(lane.into_iter().zip(offsets).map(
            |((part_index, value_zatoshi), block_offset)| MigrationScheduleEntry {
                part_index: Some(part_index),
                value_zatoshi,
                block_offset,
            },
        ));
    }
    merged.sort_by_key(|entry| (entry.block_offset, entry.part_index));
    Ok(merged)
}

fn planned_transfer_schedule_with_policy<R, I>(
    values: I,
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    rng: &mut R,
) -> Vec<MigrationScheduleEntry>
where
    R: RngCore + CryptoRng + ?Sized,
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
    R: RngCore + CryptoRng + ?Sized,
    I: IntoIterator<Item = (u32, u64)>,
{
    let mut parts = parts.into_iter().collect::<Vec<_>>();
    parts.shuffle(rng);
    let (mean_delay_blocks, max_delay_blocks) =
        schedule_parameters_with_policy_for_part_count(network, timing_policy, parts.len());
    let offsets = random_schedule_block_offsets_with_rng(
        parts.len(),
        mean_delay_blocks,
        max_delay_blocks,
        rng,
    );
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

/// Fresh cumulative offsets for rebuilt migration parts, aligned with
/// `recoveries` (`(part_index, value_zatoshi)`) order. The caller appends them
/// to the run's persisted recovery ladder instead of replaying each part's
/// original whole-run offset.
pub(crate) fn rebuild_schedule_block_offsets<R: RngCore + CryptoRng + ?Sized>(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    recoveries: &[(u32, u64)],
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    rng: &mut R,
) -> Result<Vec<u32>, String> {
    let (mean_delay_blocks, max_delay_blocks) =
        schedule_parameters_with_policy(network, timing_policy);
    rebuild_schedule_block_offsets_with_parameters(
        schedule,
        target_values,
        recoveries,
        mean_delay_blocks,
        max_delay_blocks,
        rng,
    )
}

pub(super) fn rebuild_schedule_block_offsets_with_parameters<R: RngCore + CryptoRng + ?Sized>(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    recoveries: &[(u32, u64)],
    mean_delay_blocks: u32,
    max_delay_blocks: u32,
    rng: &mut R,
) -> Result<Vec<u32>, String> {
    for (part_index, value_zatoshi) in recoveries {
        schedule_block_offset_for_part(schedule, target_values, *part_index, *value_zatoshi)
            .ok_or("Approved migration schedule is missing a recovery child")?;
    }

    let offsets = random_schedule_block_offsets_with_rng(
        recoveries.len(),
        mean_delay_blocks,
        max_delay_blocks,
        rng,
    );
    // Hand out the cumulative slots in a shuffled order so the rebuilt
    // broadcast order does not reveal which original part each transfer is.
    let mut slots = (0..recoveries.len()).collect::<Vec<_>>();
    slots.shuffle(rng);
    let mut assigned = vec![0u32; recoveries.len()];
    for (slot, offset) in slots.into_iter().zip(offsets) {
        assigned[slot] = offset;
    }
    Ok(assigned)
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
    for entry in schedule {
        let gap = entry
            .block_offset
            .checked_sub(previous_offset)
            .ok_or("Approved migration schedule is not ordered")?;
        if gap > max_delay_blocks {
            return Err("Approved migration schedule delay is outside policy".to_string());
        }
        previous_offset = entry.block_offset;
    }
    Ok(())
}

pub(crate) fn validate_custom_schedule(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    parallel_schedule_count: u32,
) -> Result<(), String> {
    let part_count = u32::try_from(target_values.len())
        .map_err(|_| "Custom migration part count exceeds u32".to_string())?;
    let (_, max_delay_blocks) =
        custom_schedule_parameters(
            network,
            timing_policy,
            parallel_schedule_count,
            part_count,
        )?;
    validate_schedule_with_max_delay(schedule, target_values, max_delay_blocks)
}

fn validate_schedule_with_max_delay(
    schedule: &[MigrationScheduleEntry],
    target_values: &[u64],
    max_delay_blocks: u32,
) -> Result<(), String> {
    if schedule.len() != target_values.len() {
        return Err("Approved migration schedule count changed".to_string());
    }
    let target_values_by_part = target_values.to_vec();
    let mut scheduled_values = schedule
        .iter()
        .map(|entry| entry.value_zatoshi)
        .collect::<Vec<_>>();
    let mut sorted_target_values = target_values_by_part.clone();
    scheduled_values.sort_unstable();
    sorted_target_values.sort_unstable();
    if scheduled_values != sorted_target_values {
        return Err("Approved migration schedule values changed".to_string());
    }
    validate_schedule_part_indexes(schedule, &target_values_by_part)?;

    let mut previous_offset = 0;
    for entry in schedule {
        let gap = entry
            .block_offset
            .checked_sub(previous_offset)
            .ok_or("Approved migration schedule is not ordered")?;
        if gap > max_delay_blocks {
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

#[cfg(test)]
mod custom_schedule_tests {
    use super::*;
    use rand::{rngs::StdRng, SeedableRng};

    #[test]
    fn custom_schedule_is_deterministic_and_covers_every_part_once() {
        let values = (1..=40).collect::<Vec<_>>();
        let build = || {
            let mut rng = StdRng::seed_from_u64(1234);
            planned_custom_transfer_schedule(
                values.iter().copied(),
                WalletNetwork::Main,
                MigrationTimingPolicy::Standard90Minutes,
                4,
                &mut rng,
            )
            .unwrap()
        };
        let first = build();
        let second = build();

        assert_eq!(first, second);
        validate_custom_schedule(
            &first,
            &values,
            WalletNetwork::Main,
            MigrationTimingPolicy::Standard90Minutes,
            4,
        )
        .unwrap();
        assert!(first
            .windows(2)
            .all(|pair| pair[0].block_offset <= pair[1].block_offset));
    }

    #[test]
    fn parallel_schedules_compress_the_same_number_of_transfers() {
        let values = vec![1; 200];
        let mut one_rng = StdRng::seed_from_u64(55);
        let one = planned_custom_transfer_schedule(
            values.iter().copied(),
            WalletNetwork::Main,
            MigrationTimingPolicy::Standard90Minutes,
            1,
            &mut one_rng,
        )
        .unwrap();
        let mut eight_rng = StdRng::seed_from_u64(55);
        let eight = planned_custom_transfer_schedule(
            values.iter().copied(),
            WalletNetwork::Main,
            MigrationTimingPolicy::Standard90Minutes,
            8,
            &mut eight_rng,
        )
        .unwrap();
        let mut thirty_two_rng = StdRng::seed_from_u64(55);
        let thirty_two = planned_custom_transfer_schedule(
            values.iter().copied(),
            WalletNetwork::Main,
            MigrationTimingPolicy::Standard90Minutes,
            32,
            &mut thirty_two_rng,
        )
        .unwrap();

        assert_eq!(one.len(), eight.len());
        assert_eq!(one.len(), thirty_two.len());
        validate_custom_schedule(
            &thirty_two,
            &values,
            WalletNetwork::Main,
            MigrationTimingPolicy::Standard90Minutes,
            32,
        )
        .unwrap();
        assert!(eight.last().unwrap().block_offset < one.last().unwrap().block_offset);
        assert_eq!(
            custom_schedule_parameters(
                WalletNetwork::Main,
                MigrationTimingPolicy::Standard90Minutes,
                32,
                values.len() as u32,
            )
            .unwrap()
            .0,
            2
        );
        assert_eq!(
            custom_schedule_parameters(
                WalletNetwork::Main,
                MigrationTimingPolicy::Standard90Minutes,
                33,
                values.len() as u32,
            )
            .unwrap_err(),
            "Custom migration parallel schedule count must be between 1 and 32"
        );
    }

    #[test]
    fn custom_schedule_uses_the_configured_network_timing() {
        assert_eq!(
            custom_schedule_parameters(
                WalletNetwork::Regtest,
                MigrationTimingPolicy::Standard,
                8,
                100,
            )
            .unwrap(),
            (1, REGTEST_TRANSFER_MAX_DELAY_BLOCKS),
        );
        assert_eq!(
            custom_schedule_parameters(
                WalletNetwork::Test,
                MigrationTimingPolicy::FastTestnet,
                4,
                100,
            )
            .unwrap(),
            (3, FAST_TESTNET_TRANSFER_MAX_DELAY_BLOCKS),
        );

        let values = vec![1; 100];
        let mut rng = StdRng::seed_from_u64(55);
        let schedule = planned_custom_transfer_schedule(
            values.iter().copied(),
            WalletNetwork::Regtest,
            MigrationTimingPolicy::Standard,
            4,
            &mut rng,
        )
        .unwrap();
        validate_custom_schedule(
            &schedule,
            &values,
            WalletNetwork::Regtest,
            MigrationTimingPolicy::Standard,
            4,
        )
        .unwrap();
        assert!(schedule.last().unwrap().block_offset <= 25 * REGTEST_TRANSFER_MAX_DELAY_BLOCKS);
    }

    #[test]
    fn custom_schedule_caps_parallelism_at_the_transfer_count() {
        let values = vec![1, 2];
        let build = |parallel_schedules| {
            let mut rng = StdRng::seed_from_u64(55);
            planned_custom_transfer_schedule(
                values.iter().copied(),
                WalletNetwork::Main,
                MigrationTimingPolicy::Standard90Minutes,
                parallel_schedules,
                &mut rng,
            )
            .unwrap()
        };

        assert_eq!(build(32), build(2));
        assert_eq!(
            custom_schedule_parameters(
                WalletNetwork::Main,
                MigrationTimingPolicy::Standard90Minutes,
                32,
                values.len() as u32,
            )
            .unwrap(),
            (33, ZIP318_TRANSFER_MAX_DELAY_BLOCKS),
        );
    }
}
