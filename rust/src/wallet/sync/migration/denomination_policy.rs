#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DenominationPlan {
    /// Canonical ZIP 318 denominations in non-increasing migration part order.
    /// This matches prepared funding notes reloaded in descending value order.
    /// Each funding note is `denomination + fee`.
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

    loop {
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

/// The ZIP 318 canonical expiry for a part scheduled at `scheduled_height`.
/// The expiry modulus is 34,560 blocks before NU7 activation and 103,680
/// blocks from it, both about 30 days.
pub(crate) fn zip318_canonical_migration_expiry_height<P: Parameters>(
    network: &P,
    scheduled_height: u32,
) -> Result<u32, String> {
    canonical_expiry_with_spacing(BlockSpacing::for_network(network), scheduled_height)
}

fn canonical_expiry_with_spacing(spacing: BlockSpacing, scheduled_height: u32) -> Result<u32, String> {
    let expiry = u32::from(zcash_protocol::zip318::expiry_height(
        &spacing,
        BlockHeight::from_u32(scheduled_height),
    ));
    // The library saturates instead of failing.
    (expiry < u32::MAX)
        .then_some(expiry)
        .ok_or_else(|| "ZIP 318 canonical expiry height overflow".to_string())
}

/// The canonical expiry under the pre-NU7 modulus, which every build before
/// NU7 support used at every height.
pub(crate) fn legacy_zip318_canonical_migration_expiry_height(
    scheduled_height: u32,
) -> Result<u32, String> {
    canonical_expiry_with_spacing(BlockSpacing::UNIFORM, scheduled_height)
}

/// Whether a stored part's expiry is canonical. Builds before NU7 support
/// used the pre-NU7 modulus at every height. Their parts scheduled past
/// activation are held and then stopped, so reading them must not fail the
/// whole run before that.
pub(crate) fn is_stored_migration_expiry_canonical(
    network: WalletNetwork,
    scheduled_height: u32,
    expiry_height: u32,
) -> Result<bool, String> {
    Ok(
        expiry_height == zip318_canonical_migration_expiry_height(&network, scheduled_height)?
            || expiry_height == legacy_zip318_canonical_migration_expiry_height(scheduled_height)?,
    )
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

pub(crate) fn anchor_bucket_modulus(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> u32 {
    match network {
        WalletNetwork::Regtest if timing_policy == MigrationTimingPolicy::FastTestnet => {
            FAST_TESTNET_ANCHOR_BUCKET_MODULUS
        }
        WalletNetwork::Regtest => REGTEST_ANCHOR_BUCKET_MODULUS,
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => {
            FAST_TESTNET_ANCHOR_BUCKET_MODULUS
        }
        WalletNetwork::Main | WalletNetwork::Test => ZIP318_ANCHOR_BUCKET_MODULUS,
    }
}

/// The boundaries a run anchors to. The modulus is in ZIP 318 reference
/// blocks, so from NU7 activation boundaries fall every 3 × 144 blocks, the
/// same grid the wallet library retains its durable anchors on.
pub(crate) fn anchor_grid(network: WalletNetwork, timing_policy: MigrationTimingPolicy) -> AnchorGrid {
    let interval = NonZeroU32::new(anchor_bucket_modulus(network, timing_policy))
        .expect("anchor bucket modulus is nonzero");
    AnchorGrid::new(
        AnchorBucketInterval::custom(interval),
        BlockSpacing::for_network(&network),
    )
}

fn anchor_bucket_min_age(network: WalletNetwork, timing_policy: MigrationTimingPolicy) -> u32 {
    match network {
        WalletNetwork::Regtest if timing_policy == MigrationTimingPolicy::FastTestnet => 1,
        // Empty regtest blocks do not add commitment-tree checkpoints. Allow
        // the checkpoint containing the denomination note so E2E can advance.
        WalletNetwork::Regtest => 0,
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => 1,
        WalletNetwork::Main | WalletNetwork::Test
            if matches!(
                timing_policy,
                MigrationTimingPolicy::Standard90MinutesLatestAnchor
            ) =>
        {
            0
        }
        WalletNetwork::Main | WalletNetwork::Test => 1,
    }
}

#[cfg(test)]
pub(crate) fn proof_readiness_delay_blocks(
    network: WalletNetwork,
    estimated_mined_height: u32,
) -> Result<u32, String> {
    let confirmation_lag = ConfirmationsPolicy::default()
        .trusted()
        .get()
        .saturating_sub(1);
    let trusted_height = estimated_mined_height
        .checked_add(confirmation_lag)
        .ok_or("Migration proof readiness delay overflow")?;
    estimated_proof_ready_height(network, estimated_mined_height)?
        .checked_sub(trusted_height)
        .ok_or_else(|| "Migration proof readiness delay underflow".to_string())
}

pub(crate) fn estimated_proof_ready_height(
    network: WalletNetwork,
    estimated_mined_height: u32,
) -> Result<u32, String> {
    proof_ready_height_for_note_mined_height(
        network,
        configured_timing_policy(network),
        estimated_mined_height,
    )
}

pub(crate) fn proof_ready_height_for_note_mined_height(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    mined_height: u32,
) -> Result<u32, String> {
    let grid = anchor_grid(network, timing_policy);
    let confirmation_lag = ConfirmationsPolicy::default()
        .trusted()
        .get()
        .saturating_sub(1);
    let mut boundary = BlockHeight::from_u32(anchor_boundary_containing_note_with_policy(
        network,
        timing_policy,
        mined_height,
    )?);
    for _ in 0..anchor_bucket_min_age(network, timing_policy) {
        boundary = grid.boundary_after(boundary);
    }
    u32::from(boundary)
        .checked_add(confirmation_lag)
        .filter(|height| *height < u32::MAX)
        .ok_or_else(|| "Migration proof readiness height overflow".to_string())
}

pub(crate) fn anchor_boundary_containing_note_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    mined_height: u32,
) -> Result<u32, String> {
    let grid = anchor_grid(network, timing_policy);
    let boundary = grid.boundary_at_or_above(BlockHeight::from_u32(mined_height));
    // The grid saturates at the top of the height range instead of failing.
    if !grid.is_boundary(boundary) {
        return Err("Migration anchor boundary overflow".to_string());
    }
    Ok(u32::from(boundary))
}

pub(crate) fn next_anchor_retry_height_after(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    fully_scanned_height: u32,
) -> Result<u32, String> {
    let grid = anchor_grid(network, timing_policy);
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
    u32::from(grid.boundary_after(BlockHeight::from_u32(boundary_reference)))
        .checked_add(confirmation_lag)
        .filter(|height| *height < u32::MAX)
        .ok_or_else(|| "Migration proof retry height overflow".to_string())
}

#[cfg(test)]
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
    let boundary = u32::from(
        anchor_grid(network, timing_policy).boundary_at_or_below(BlockHeight::from_u32(height)),
    );
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
    // Ages count boundaries, whose spacing changes at NU7 activation.
    let grid = anchor_grid(network, timing_policy);
    let anchor = BlockHeight::from_u32(anchor_boundary);
    let mut boundary = BlockHeight::from_u32(latest_boundary);
    let mut age = 0;
    while boundary > anchor {
        if age == ZIP318_ANCHOR_AGE_CAP {
            return None;
        }
        boundary = grid.boundary_before(boundary)?;
        age += 1;
    }
    (boundary == anchor
        && (anchor_bucket_min_age(network, timing_policy)..=ZIP318_ANCHOR_AGE_CAP).contains(&age))
    .then_some(age)
}

#[cfg(test)]
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
    let grid = anchor_grid(network, timing_policy);
    let min_age = anchor_bucket_min_age(network, timing_policy);
    let mut candidates = Vec::new();
    let mut boundary = Some(BlockHeight::from_u32(latest_boundary));
    for age in 0..=ZIP318_ANCHOR_AGE_CAP {
        let Some(current) = boundary else {
            break;
        };
        if u32::from(current) < lower_bound {
            break;
        }
        if age >= min_age {
            candidates.push(u32::from(current));
        }
        boundary = grid.boundary_before(current);
    }
    candidates
}

#[cfg(test)]
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
    if anchor_boundary == 0
        || !anchor_grid(network, timing_policy).is_boundary(BlockHeight::from_u32(anchor_boundary))
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

#[cfg(test)]
pub(crate) fn zip318_draw_anchor_boundary_for_note(
    network: WalletNetwork,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
) -> Option<u32> {
    zip318_draw_anchor_boundary_for_note_with_policy(
        network,
        configured_timing_policy(network),
        observed_anchor_height,
        note_mined_height,
        nu6_3_activation_height,
    )
}

#[cfg(test)]
pub(crate) fn zip318_draw_anchor_boundary_for_note_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    observed_anchor_height: u32,
    note_mined_height: u32,
    nu6_3_activation_height: u32,
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
    )
}

pub(crate) fn zip318_draw_anchor_boundary_from_available_with_policy(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    observed_anchor_height: u32,
    available_candidates: &[u32],
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
