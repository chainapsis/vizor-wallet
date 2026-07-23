#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DenominationPlan {
    /// Canonical ZIP 318 denominations to be emitted as Ironwood outputs.
    /// The note-preparation outputs that fund these are `denomination + fee`.
    pub migration_outputs: Vec<u64>,
    pub orchard_change: Option<u64>,
    pub split_fee_zatoshi: u64,
    pub migration_fee_zatoshi: u64,
    pub total_input_zatoshi: u64,
    pub total_migratable_zatoshi: u64,
}

pub(crate) fn plan_denominations(
    total_input_zatoshi: u64,
    split_fee_zatoshi: u64,
    migration_fee_zatoshi: u64,
    minimum_output_zatoshi: u64,
) -> Result<DenominationPlan, String> {
    if total_input_zatoshi <= split_fee_zatoshi {
        return Ok(DenominationPlan {
            migration_outputs: Vec::new(),
            orchard_change: None,
            split_fee_zatoshi: total_input_zatoshi,
            migration_fee_zatoshi,
            total_input_zatoshi,
            total_migratable_zatoshi: 0,
        });
    }

    let mut remaining = total_input_zatoshi
        .checked_sub(split_fee_zatoshi)
        .ok_or("Denomination split fee underflow")?;
    let mut outputs = Vec::new();

    while outputs.len() < MIGRATION_MAX_PREPARED_NOTES_PER_RUN {
        let Some(spendable_after_fee) = remaining.checked_sub(migration_fee_zatoshi) else {
            break;
        };
        let Some(denomination) = largest_zip318_denomination_at_or_below(spendable_after_fee)
        else {
            break;
        };
        outputs.push(denomination);
        remaining = remaining
            .checked_sub(denomination)
            .and_then(|value| value.checked_sub(migration_fee_zatoshi))
            .ok_or("Canonical denomination fee underflow")?;
    }

    let orchard_change = (remaining >= minimum_output_zatoshi).then_some(remaining);

    let total_migratable_zatoshi = outputs.iter().try_fold(0u64, |acc, value| {
        acc.checked_add(*value)
            .ok_or("Migratable total overflow".to_string())
    })?;

    Ok(DenominationPlan {
        migration_outputs: outputs,
        orchard_change,
        split_fee_zatoshi,
        migration_fee_zatoshi,
        total_input_zatoshi,
        total_migratable_zatoshi,
    })
}

pub(crate) fn is_zip318_canonical_denomination(value_zatoshi: u64) -> bool {
    largest_zip318_denomination_at_or_below(value_zatoshi) == Some(value_zatoshi)
}

pub(crate) fn zip318_canonical_migration_expiry_height(
    scheduled_height: u32,
) -> Result<u32, String> {
    let boundary = scheduled_height - (scheduled_height % ZIP318_EXPIRY_MODULUS);
    let window = ZIP318_EXPIRY_MODULUS
        .checked_mul(2)
        .ok_or_else(|| "ZIP 318 expiry window overflow".to_string())?;

    boundary
        .checked_add(window)
        .ok_or_else(|| "ZIP 318 canonical expiry height overflow".to_string())
}

fn largest_zip318_denomination_at_or_below(value_zatoshi: u64) -> Option<u64> {
    if value_zatoshi < ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI {
        return None;
    }

    let mut magnitude = ZIP318_MAX_RESIDUAL_VALUE_ZATOSHI;
    let mut best = None;
    loop {
        for multiplier in [1u64, 2, 5] {
            let Some(denomination) = magnitude.checked_mul(multiplier) else {
                continue;
            };
            if denomination <= value_zatoshi
                && denomination <= ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI
            {
                best = Some(denomination);
            }
        }
        if magnitude >= ZIP318_MAX_MIGRATION_DENOMINATION_ZATOSHI {
            break;
        }
        magnitude = magnitude.checked_mul(10)?;
    }
    best
}

fn anchor_bucket_modulus(network: WalletNetwork, timing_policy: MigrationTimingPolicy) -> u32 {
    match network {
        WalletNetwork::Regtest => REGTEST_ANCHOR_BUCKET_MODULUS,
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => {
            REGTEST_ANCHOR_BUCKET_MODULUS
        }
        WalletNetwork::Main | WalletNetwork::Test => ZIP318_ANCHOR_BUCKET_MODULUS,
    }
}

fn anchor_bucket_min_age(network: WalletNetwork, timing_policy: MigrationTimingPolicy) -> u32 {
    match network {
        // Empty regtest blocks do not add commitment-tree checkpoints. Allow
        // the checkpoint containing the denomination note so E2E can advance.
        WalletNetwork::Regtest => 0,
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => 0,
        WalletNetwork::Main | WalletNetwork::Test => 1,
    }
}

pub(crate) fn proof_readiness_delay_blocks(
    network: WalletNetwork,
    estimated_mined_height: u32,
) -> Result<u32, String> {
    let timing_policy = configured_timing_policy(network);
    let confirmation_lag = ConfirmationsPolicy::default()
        .trusted()
        .get()
        .saturating_sub(1);
    let trusted_height = estimated_mined_height
        .checked_add(confirmation_lag)
        .ok_or("Migration proof readiness delay overflow")?;
    proof_ready_height_for_note_mined_height(network, timing_policy, estimated_mined_height)?
        .checked_sub(trusted_height)
        .ok_or_else(|| "Migration proof readiness delay underflow".to_string())
}

pub(crate) fn proof_ready_height_for_note_mined_height(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    mined_height: u32,
) -> Result<u32, String> {
    let modulus = anchor_bucket_modulus(network, timing_policy);
    let confirmation_lag = ConfirmationsPolicy::default()
        .trusted()
        .get()
        .saturating_sub(1);
    let remainder = mined_height % modulus;
    let containing_boundary = if remainder == 0 {
        mined_height
    } else {
        mined_height
            .checked_add(modulus - remainder)
            .ok_or("Migration proof readiness height overflow")?
    };
    let aging_blocks = modulus
        .checked_mul(anchor_bucket_min_age(network, timing_policy))
        .ok_or("Migration proof readiness height overflow")?;
    containing_boundary
        .checked_add(aging_blocks)
        .and_then(|height| height.checked_add(confirmation_lag))
        .ok_or_else(|| "Migration proof readiness height overflow".to_string())
}

pub(crate) fn next_anchor_retry_height_after(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    fully_scanned_height: u32,
) -> Result<u32, String> {
    let modulus = anchor_bucket_modulus(network, timing_policy);
    let confirmation_lag = ConfirmationsPolicy::default()
        .trusted()
        .get()
        .saturating_sub(1);
    // Standard ZIP 318 selection excludes the newest boundary. Base the next
    // retry on the trusted anchor height so a boundary that is about to age
    // into the candidate set is not skipped for a full bucket.
    let boundary_reference = if anchor_bucket_min_age(network, timing_policy) > 0 {
        fully_scanned_height.saturating_sub(confirmation_lag)
    } else {
        fully_scanned_height
    };
    let distance = modulus - (boundary_reference % modulus);
    boundary_reference
        .checked_add(distance)
        .and_then(|boundary| boundary.checked_add(confirmation_lag))
        .ok_or_else(|| "Migration proof retry height overflow".to_string())
}

pub(crate) fn zip318_anchor_boundary_at_or_before(
    network: WalletNetwork,
    height: u32,
) -> Option<u32> {
    zip318_anchor_boundary_at_or_before_with_policy(
        network,
        configured_timing_policy(network),
        height,
    )
}

pub(crate) fn zip318_anchor_boundary_at_or_before_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    height: u32,
) -> Option<u32> {
    let modulus = anchor_bucket_modulus(network, timing_policy);
    let boundary = height - (height % modulus);
    (boundary > 0).then_some(boundary)
}

fn zip318_anchor_boundary_age(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    latest_boundary: u32,
    anchor_boundary: u32,
) -> Option<u32> {
    if anchor_boundary > latest_boundary {
        return None;
    }
    let delta = latest_boundary.checked_sub(anchor_boundary)?;
    let modulus = anchor_bucket_modulus(network, timing_policy);
    if delta % modulus != 0 {
        return None;
    }
    let age = delta / modulus;
    (anchor_bucket_min_age(network, timing_policy)..=ZIP318_ANCHOR_AGE_CAP)
        .contains(&age)
        .then_some(age)
}

pub(crate) fn zip318_anchor_candidate_boundaries(
    network: WalletNetwork,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Vec<u32> {
    zip318_anchor_candidate_boundaries_with_policy(
        network,
        configured_timing_policy(network),
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
    )
}

pub(crate) fn zip318_anchor_candidate_boundaries_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Vec<u32> {
    let Some(latest_boundary) = zip318_anchor_boundary_at_or_before_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
    ) else {
        return Vec::new();
    };
    let lower_bound = note_mined_height.max(nu6_3_activation_height.saturating_add(1));
    let mut candidates = Vec::new();
    for age in anchor_bucket_min_age(network, timing_policy)..=ZIP318_ANCHOR_AGE_CAP {
        let Some(distance) = age.checked_mul(anchor_bucket_modulus(network, timing_policy)) else {
            break;
        };
        let Some(boundary) = latest_boundary.checked_sub(distance) else {
            break;
        };
        if boundary < lower_bound {
            break;
        }
        candidates.push(boundary);
    }
    candidates
}

pub(crate) fn zip318_anchor_boundary_is_candidate(
    network: WalletNetwork,
    anchor_boundary: u32,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> bool {
    zip318_anchor_boundary_is_candidate_with_policy(
        network,
        configured_timing_policy(network),
        anchor_boundary,
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
    )
}

pub(crate) fn zip318_anchor_boundary_is_candidate_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    anchor_boundary: u32,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> bool {
    if anchor_boundary == 0 || anchor_boundary % anchor_bucket_modulus(network, timing_policy) != 0
    {
        return false;
    }
    if anchor_boundary < note_mined_height || anchor_boundary <= nu6_3_activation_height {
        return false;
    }
    let Some(latest_boundary) = zip318_anchor_boundary_at_or_before_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
    ) else {
        return false;
    };
    zip318_anchor_boundary_age(network, timing_policy, latest_boundary, anchor_boundary).is_some()
}

pub(crate) fn zip318_draw_anchor_boundary_for_note(
    network: WalletNetwork,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Option<u32> {
    zip318_draw_anchor_boundary_for_note_with_cohorts(
        network,
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
        &BTreeMap::new(),
    )
}

pub(crate) fn zip318_draw_anchor_boundary_for_note_with_cohorts(
    network: WalletNetwork,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
    cohort_counts: &BTreeMap<u32, u32>,
) -> Option<u32> {
    zip318_draw_anchor_boundary_for_note_with_cohorts_and_policy(
        network,
        configured_timing_policy(network),
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
        cohort_counts,
    )
}

pub(crate) fn zip318_draw_anchor_boundary_for_note_with_cohorts_and_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
    cohort_counts: &BTreeMap<u32, u32>,
) -> Option<u32> {
    let candidates = zip318_anchor_candidate_boundaries_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
    );
    zip318_draw_anchor_boundary_from_available_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
        &candidates,
        cohort_counts,
    )
}

pub(crate) fn zip318_draw_anchor_boundary_from_available_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    observed_anchor_height: u32,
    available_candidates: &[u32],
    cohort_counts: &BTreeMap<u32, u32>,
) -> Option<u32> {
    let latest_boundary = zip318_anchor_boundary_at_or_before_with_policy(
        network,
        timing_policy,
        observed_anchor_height,
    )?;
    if available_candidates.is_empty() {
        return None;
    }

    let mut weighted = Vec::with_capacity(available_candidates.len());
    let mut total_weight = 0u32;
    for boundary in available_candidates.iter().copied() {
        if cohort_counts.get(&boundary).copied().unwrap_or_default()
            >= ZIP318_MAX_PARTS_PER_ANCHOR_COHORT
        {
            continue;
        }
        let age = zip318_anchor_boundary_age(network, timing_policy, latest_boundary, boundary)?;
        let weight = 1u32 << (ZIP318_ANCHOR_AGE_CAP - age);
        total_weight = total_weight.checked_add(weight)?;
        weighted.push((boundary, weight));
    }

    if total_weight == 0 {
        return None;
    }

    let mut draw = OsRng.gen_range(0..total_weight);
    for (boundary, weight) in weighted {
        if draw < weight {
            return Some(boundary);
        }
        draw -= weight;
    }
    None
}
