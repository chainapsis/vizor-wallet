pub(crate) const ZIP318_PREPARATION_MEAN_DELAY_BLOCKS: u32 = 24;
pub(crate) const ZIP318_PREPARATION_MAX_DELAY_BLOCKS: u32 = 96;
const REGTEST_PREPARATION_MEAN_DELAY_BLOCKS: u32 = 1;
const REGTEST_PREPARATION_MAX_DELAY_BLOCKS: u32 = 4;

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
        WalletNetwork::Regtest => (
            REGTEST_PREPARATION_MEAN_DELAY_BLOCKS,
            REGTEST_PREPARATION_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Test if timing_policy == MigrationTimingPolicy::FastTestnet => (
            REGTEST_PREPARATION_MEAN_DELAY_BLOCKS,
            REGTEST_PREPARATION_MAX_DELAY_BLOCKS,
        ),
        WalletNetwork::Main | WalletNetwork::Test => (
            ZIP318_PREPARATION_MEAN_DELAY_BLOCKS,
            ZIP318_PREPARATION_MAX_DELAY_BLOCKS,
        ),
    }
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

fn preparation_policies_for_run_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<(PreparationTimingPolicy, MigrationTimingPolicy), String> {
    let (preparation_value, migration_value) = conn
        .query_row(
            &format!(
                "SELECT preparation_timing_policy, timing_policy
                 FROM {RUNS_TABLE} WHERE run_id = ?1"
            ),
            params![run_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .map_err(|e| format!("Read migration preparation policies: {e}"))?;
    Ok((
        PreparationTimingPolicy::from_str(&preparation_value)?,
        MigrationTimingPolicy::from_str(&migration_value)?,
    ))
}

fn preparation_timing_policy_for_run_with_conn(
    conn: &rusqlite::Connection,
    run_id: &str,
) -> Result<PreparationTimingPolicy, String> {
    preparation_policies_for_run_with_conn(conn, run_id).map(|(policy, _)| policy)
}

pub(crate) fn preparation_timing_policy_for_run(
    db_path: &str,
    run_id: &str,
) -> Result<PreparationTimingPolicy, String> {
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    ensure_schema(&conn)?;
    preparation_timing_policy_for_run_with_conn(&conn, run_id)
}

fn initialize_preparation_schedule_with_tx<R: RngCore + CryptoRng + ?Sized>(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    network: WalletNetwork,
    policy: PreparationTimingPolicy,
    rng: &mut R,
) -> Result<(), String> {
    if policy == PreparationTimingPolicy::Immediate {
        return Ok(());
    }
    let (_, timing_policy) = preparation_policies_for_run_with_conn(tx, run_id)?;

    let mut stmt = tx
        .prepare_cached(&format!(
            "SELECT stage_index, target_height
             FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND status = 'pending'
             ORDER BY stage_index ASC"
        ))
        .map_err(|e| format!("Prepare root denomination schedule query: {e}"))?;
    let mut roots = stmt
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, u32>(0)?, row.get::<_, u32>(1)?))
        })
        .map_err(|e| format!("Query root denomination schedule: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read root denomination schedule: {e}"))?;
    drop(stmt);
    if roots.is_empty() {
        return Err("Migration denomination plan has no broadcastable root".to_string());
    }

    roots.shuffle(rng);
    let mut scheduled_height = roots
        .iter()
        .map(|(_, target_height)| target_height.saturating_sub(1))
        .min()
        .unwrap_or(0);
    for (stage_index, _) in roots {
        scheduled_height = scheduled_height
            .checked_add(preparation_delay_with_rng(network, timing_policy, rng))
            .ok_or("Migration preparation scheduled height overflow")?;
        tx.execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET scheduled_height = ?1
                 WHERE run_id = ?2 AND stage_index = ?3 AND status = 'pending'"
            ),
            params![scheduled_height, run_id, stage_index],
        )
        .map_err(|e| format!("Schedule root denomination stage: {e}"))?;
    }
    Ok(())
}

fn reschedule_pending_preparation_stages_with_tx<R: RngCore + CryptoRng + ?Sized>(
    tx: &rusqlite::Transaction<'_>,
    run_id: &str,
    network: WalletNetwork,
    rng: &mut R,
) -> Result<(), String> {
    let (preparation_policy, timing_policy) =
        preparation_policies_for_run_with_conn(tx, run_id)?;
    if preparation_policy == PreparationTimingPolicy::Immediate {
        return Ok(());
    }

    let mut stmt = tx
        .prepare_cached(&format!(
            "SELECT stage_index, target_height
             FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND status = 'pending'
             ORDER BY scheduled_height ASC, stage_index ASC"
        ))
        .map_err(|e| format!("Prepare denomination reschedule query: {e}"))?;
    let pending = stmt
        .query_map(params![run_id], |row| {
            Ok((row.get::<_, u32>(0)?, row.get::<_, u32>(1)?))
        })
        .map_err(|e| format!("Query denomination stages to reschedule: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read denomination stages to reschedule: {e}"))?;
    drop(stmt);
    if pending.is_empty() {
        return Ok(());
    }

    let previous_scheduled_height = tx
        .query_row(
            &format!(
                "SELECT MAX(scheduled_height)
                 FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND status != 'pending'
                   AND scheduled_height > 0"
            ),
            params![run_id],
            |row| row.get::<_, Option<u32>>(0),
        )
        .map_err(|e| format!("Read previous denomination schedule: {e}"))?;
    let mut scheduled_height = previous_scheduled_height.unwrap_or_else(|| {
        pending
            .iter()
            .map(|(_, target_height)| target_height.saturating_sub(1))
            .min()
            .unwrap_or(0)
    });
    for (stage_index, _) in pending {
        scheduled_height = scheduled_height
            .checked_add(preparation_delay_with_rng(network, timing_policy, rng))
            .ok_or("Migration preparation scheduled height overflow")?;
        tx.execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET scheduled_height = ?1
                 WHERE run_id = ?2 AND stage_index = ?3 AND status = 'pending'"
            ),
            params![scheduled_height, run_id, stage_index],
        )
        .map_err(|e| format!("Reschedule denomination stage: {e}"))?;
    }
    Ok(())
}

pub(crate) fn next_preparation_scheduled_height<R: RngCore + CryptoRng + ?Sized>(
    conn: &rusqlite::Connection,
    run_id: &str,
    network: WalletNetwork,
    observed_height: u32,
    rng: &mut R,
) -> Result<u32, String> {
    let (preparation_policy, timing_policy) =
        preparation_policies_for_run_with_conn(conn, run_id)?;
    if preparation_policy == PreparationTimingPolicy::Immediate {
        return Ok(0);
    }
    let last_scheduled_height = conn
        .query_row(
            &format!(
                "SELECT MAX(scheduled_height)
                 FROM {STAGES_TABLE}
                 WHERE run_id = ?1 AND scheduled_height > 0"
            ),
            params![run_id],
            |row| row.get::<_, Option<u32>>(0),
        )
        .map_err(|e| format!("Read latest denomination schedule: {e}"))?
        .unwrap_or(observed_height);
    observed_height
        .max(last_scheduled_height)
        .checked_add(preparation_delay_with_rng(network, timing_policy, rng))
        .ok_or_else(|| "Migration preparation scheduled height overflow".to_string())
}

pub(crate) fn reschedule_remaining_preparation_stages<R: RngCore + CryptoRng + ?Sized>(
    conn: &rusqlite::Connection,
    run_id: &str,
    network: WalletNetwork,
    observed_height: u32,
    rng: &mut R,
) -> Result<(), String> {
    let (preparation_policy, timing_policy) =
        preparation_policies_for_run_with_conn(conn, run_id)?;
    if preparation_policy == PreparationTimingPolicy::Immediate {
        return Ok(());
    }
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT stage_index
             FROM {STAGES_TABLE}
             WHERE run_id = ?1 AND status = 'pending'
             ORDER BY scheduled_height ASC, stage_index ASC"
        ))
        .map_err(|e| format!("Prepare remaining denomination schedule query: {e}"))?;
    let remaining = stmt
        .query_map(params![run_id], |row| row.get::<_, u32>(0))
        .map_err(|e| format!("Query remaining denomination schedule: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Read remaining denomination schedule: {e}"))?;
    drop(stmt);

    let tx = conn
        .unchecked_transaction()
        .map_err(|e| format!("Begin remaining denomination reschedule: {e}"))?;
    let mut scheduled_height = observed_height;
    for stage_index in remaining {
        scheduled_height = scheduled_height
            .checked_add(preparation_delay_with_rng(network, timing_policy, rng))
            .ok_or("Migration preparation scheduled height overflow")?;
        tx.execute(
            &format!(
                "UPDATE {STAGES_TABLE}
                 SET scheduled_height = ?1
                 WHERE run_id = ?2 AND stage_index = ?3 AND status = 'pending'"
            ),
            params![scheduled_height, run_id, stage_index],
        )
        .map_err(|e| format!("Reschedule remaining denomination stage: {e}"))?;
    }
    tx.commit()
        .map_err(|e| format!("Commit remaining denomination reschedule: {e}"))
}
