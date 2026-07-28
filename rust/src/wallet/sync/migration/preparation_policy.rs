pub(crate) const ZIP318_PREPARATION_MEAN_DELAY_BLOCKS: u32 = 24;
pub(crate) const ZIP318_PREPARATION_MAX_DELAY_BLOCKS: u32 = 96;
const REGTEST_PREPARATION_MEAN_DELAY_BLOCKS: u32 = 1;
const REGTEST_PREPARATION_MAX_DELAY_BLOCKS: u32 = 4;
const FAST_TESTNET_PREPARATION_MEAN_DELAY_BLOCKS: u32 = 4;
const FAST_TESTNET_PREPARATION_MAX_DELAY_BLOCKS: u32 = 16;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum PreparationTimingPolicy {
    Immediate,
    Zip318Spaced,
}

impl PreparationTimingPolicy {
    pub(crate) const fn from_spacing_enabled(enabled: bool) -> Self {
        if enabled {
            Self::Zip318Spaced
        } else {
            Self::Immediate
        }
    }

    const fn as_str(self) -> &'static str {
        match self {
            Self::Immediate => "immediate",
            Self::Zip318Spaced => "zip318_spaced",
        }
    }

    fn from_str(value: &str) -> Result<Self, String> {
        match value {
            "immediate" => Ok(Self::Immediate),
            "zip318_spaced" => Ok(Self::Zip318Spaced),
            _ => Err(format!(
                "Unsupported migration preparation timing policy: {value}"
            )),
        }
    }
}

fn preparation_schedule_parameters(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
) -> (u32, u32) {
    match network {
        WalletNetwork::Regtest if timing_policy == MigrationTimingPolicy::FastTestnet => (
            FAST_TESTNET_PREPARATION_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_PREPARATION_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Regtest => (
            REGTEST_PREPARATION_MEAN_DELAY_BLOCKS,
            REGTEST_PREPARATION_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => (
            FAST_TESTNET_PREPARATION_MEAN_DELAY_BLOCKS,
            FAST_TESTNET_PREPARATION_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Main | WalletNetwork::Test => (
            ZIP318_PREPARATION_MEAN_DELAY_BLOCKS,
            ZIP318_PREPARATION_MAX_DELAY_BLOCKS,
        ),
    }
}

pub(crate) fn estimated_preparation_spacing_delay_blocks(
    network: WalletNetwork,
    preparation_policy: PreparationTimingPolicy,
    transaction_count: u32,
) -> Result<u32, String> {
    if preparation_policy == PreparationTimingPolicy::Immediate {
        return Ok(0);
    }
    preparation_schedule_parameters(network, configured_timing_policy(network))
        .0
        .checked_mul(transaction_count)
        .ok_or_else(|| "Migration preparation spacing estimate overflow".to_string())
}

fn preparation_delay_with_rng<R: RngCore + CryptoRng + ?Sized>(
    network: WalletNetwork,
    timing_policy: MigrationTimingPolicy,
    rng: &mut R,
) -> u32 {
    let (mean_delay_blocks, max_delay_blocks) =
        preparation_schedule_parameters(network, timing_policy);
    loop {
        let uniform = draw_unit_left_open(rng);
        let sampled = round_nonnegative_to_u32(-uniform.ln() * f64::from(mean_delay_blocks));
        if sampled <= max_delay_blocks {
            return sampled;
        }
    }
}

/// Draws and assigns every preparation transaction's broadcast height before
/// the transaction is signed. Later layers are based past the preceding
/// layer's schedule so their inputs have time to become spendable.
pub(crate) fn planned_preparation_scheduled_heights<
    R: RngCore + CryptoRng + ?Sized,
>(
    network: WalletNetwork,
    preparation_policy: PreparationTimingPolicy,
    timing_policy: MigrationTimingPolicy,
    target_height: u32,
    stage_layers: &[usize],
    rng: &mut R,
) -> Result<Vec<u32>, String> {
    let Some(last_layer) = stage_layers.iter().copied().max() else {
        return Ok(Vec::new());
    };
    let mut heights = vec![0; stage_layers.len()];
    let mut layer_base = target_height.saturating_sub(1);

    for layer_index in 0..=last_layer {
        let mut stage_indices = stage_layers
            .iter()
            .enumerate()
            .filter_map(|(stage_index, layer)| (*layer == layer_index).then_some(stage_index))
            .collect::<Vec<_>>();
        if stage_indices.is_empty() {
            return Err(format!(
                "Migration preparation schedule is missing layer {layer_index}"
            ));
        }
        if preparation_policy == PreparationTimingPolicy::Zip318Spaced {
            stage_indices.shuffle(rng);
        }

        let mut scheduled_height = layer_base;
        for stage_index in stage_indices {
            if preparation_policy == PreparationTimingPolicy::Zip318Spaced {
                scheduled_height = scheduled_height
                    .checked_add(preparation_delay_with_rng(network, timing_policy, rng))
                    .ok_or("Migration preparation scheduled height overflow")?;
            }
            heights[stage_index] = scheduled_height;
        }
        layer_base = scheduled_height
            .checked_add(denomination_confirmations_required())
            .ok_or("Migration preparation layer height overflow")?;
    }

    Ok(heights)
}

/// Re-randomizes the operational broadcast heights of every remaining stage
/// after a preparation broadcast misses its planned height. The original
/// schedule remains unchanged because it determines the signed expiry height.
pub(crate) fn rerandomize_remaining_preparation_broadcast_heights<
    R: RngCore + CryptoRng + ?Sized,
>(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    network: WalletNetwork,
    chain_tip_height: u32,
    rng: &mut R,
) -> Result<u32, String> {
    if preparation_timing_policy_for_run_with_conn(tx, run_id)?
        == PreparationTimingPolicy::Immediate
    {
        return Ok(0);
    }
    let timing_policy = timing_policy_for_run_with_conn(tx, run_id, network)?;
    let remaining = {
        let mut stmt = tx
            .prepare_cached(&format!(
                "SELECT stage_index, scheduled_height,
                        broadcast_not_before_height
                 FROM {STAGES_TABLE}
                 WHERE run_id = ?1
                   AND status IN ('awaiting_inputs', 'pending')
                 ORDER BY MAX(scheduled_height,
                              COALESCE(broadcast_not_before_height, 0)) ASC,
                          stage_index ASC"
            ))
            .map_err(|e| format!("Prepare remaining denomination catch-up query: {e}"))?;
        let rows = stmt
            .query_map(params![run_id], |row| {
                Ok((
                    row.get::<_, u32>(0)?,
                    row.get::<_, u32>(1)?,
                    row.get::<_, Option<u32>>(2)?,
                ))
            })
            .map_err(|e| format!("Query remaining denomination catch-up stages: {e}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Read remaining denomination catch-up stage: {e}"))?
    };

    let mut preceding_height = chain_tip_height;
    for (stage_index, scheduled_height, existing_not_before_height) in &remaining {
        let randomized_height = preceding_height
            .checked_add(preparation_delay_with_rng(network, timing_policy, rng))
            .ok_or("Migration preparation catch-up height overflow")?;
        let effective_height = randomized_height
            .max(*scheduled_height)
            .max(existing_not_before_height.unwrap_or(0));
        tx.execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET broadcast_not_before_height = ?1
                 WHERE run_id = ?2 AND stage_index = ?3
                   AND status IN ('awaiting_inputs', 'pending')"
            ),
            params![effective_height, run_id, stage_index],
        )
        .map_err(|e| format!("Reschedule migration denomination catch-up stage: {e}"))?;
        preceding_height = effective_height;
    }

    u32::try_from(remaining.len())
        .map_err(|_| "Migration preparation catch-up count exceeds u32".to_string())
}

fn preparation_timing_policy_for_run_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<PreparationTimingPolicy, String> {
    let value = conn
        .query_row(
            &format!(
                "SELECT preparation_timing_policy
                 FROM {RUNS_TABLE} WHERE run_id = ?1"
            ),
            params![run_id],
            |row| row.get::<_, String>(0),
        )
        .map_err(|e| format!("Read migration preparation timing policy: {e}"))?;
    PreparationTimingPolicy::from_str(&value)
}

pub(crate) fn preparation_timing_policy_for_run(
    db_path: &str,
    run_id: &str,
) -> Result<PreparationTimingPolicy, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    preparation_timing_policy_for_run_with_conn(&conn, run_id)
}
