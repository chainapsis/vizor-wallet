//! Work-unit sync progress.
//!
//! Progress is the share of estimated scan work finished for one sync job.
//! The work for a block range is a weighted sum of its blocks, its shielded
//! outputs, and the batches the engine cuts it into. Counting blocks alone
//! stalls for most of a full-history sync: the 2022 sandblasting window is a
//! small share of blocks but nearly all outputs and most of the scan time.
//! Counting outputs alone stalls on the long, nearly empty stretch before it.
//!
//! Output counts come from the compiled mainnet tree sizes and the downloaded
//! subtree completion heights, so estimating pending work sends no request.
//!
//! The job's id, total work and fraction live in `ext_vizor_sync_meta` until a
//! sync completes. The id is claimed when an attempt starts, so every event
//! names the job. A retry, an endpoint fallback or an app relaunch therefore
//! resumes the same fraction instead of starting again from zero. Work that
//! appeared since the last attempt keeps the fraction already shown and
//! stretches what remains of the job.

use std::time::{Duration, Instant};

use rusqlite::{params, OptionalExtension};
use zcash_client_backend::data_api::scanning::ScanRange;

use super::{
    elapsed, ensure_sync_meta_table, is_pending_scan_range, BATCH_BYTE_BUDGET,
    BATCH_SIZE_FOREGROUND, MIN_BATCH_BLOCKS, UNPLANNED_BATCH_BLOCKS,
};
use crate::wallet::db::{
    open_readonly_conn_with_timeout, open_wallet_raw_conn_with_timeout, SYNC_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::tree_states::{last_checkpoint_height, mainnet_tree_sizes};

// Relative scan cost of each unit; only the ratios matter. Fitted to the time
// each batch took in full restores from Sapling activation on a Galaxy A53 and
// an iPhone 16 Pro, and checked on an iPhone 12 mini, a two-account restore on
// the A53 and the desktop app. The earlier weights, from a desktop benchmark,
// ran the bar 8 to 13 points ahead of the time early in a phone restore, as the
// spam window took 76 to 83% of the time and 64 to 68% of the work; with these,
// no phone run strayed more than 5 points, and the desktop app reached half the
// time at 51% (52% before). A batch costs about the same whether its blocks are
// empty or not, so blocks add nothing beyond their batches.
const WORK_PER_BLOCK: f64 = 0.0;
const WORK_PER_SAPLING_OUTPUT: f64 = 21e-6;
const WORK_PER_ORCHARD_ACTION: f64 = 54e-6;
const WORK_PER_BATCH: f64 = 0.15;

// Compact-block bytes on the wire per output: field bytes plus protobuf
// framing (Sapling: note commitment, ephemeral key and 52-byte ciphertext;
// Orchard and Ironwood actions add the nullifier). Spends and transaction and
// block headers add little where outputs dominate, and are left out.
const COMPACT_SAPLING_OUTPUT_BYTES: f64 = 124.0;
const COMPACT_ACTION_BYTES: f64 = 158.0;

const SUBTREE_LEAVES: f64 = 65_536.0;
const POOL_TABLES: [&str; 3] = [
    "sapling_tree_shards",
    "orchard_tree_shards",
    "ironwood_tree_shards",
];

const PROGRESS_JOB_POLICY_VERSION: u32 = 1;
const PROGRESS_JOB_POLICY_VERSION_KEY: &str = "progress_job_policy_version";
const PROGRESS_JOB_ID_KEY: &str = "progress_job_id";
const PROGRESS_JOB_TOTAL_KEY: &str = "progress_job_total_work";
const PROGRESS_JOB_FRACTION_KEY: &str = "progress_job_fraction";
const PROGRESS_JOB_CLOSED_KEY: &str = "progress_job_closed";
const PROGRESS_JOB_FROM_COMPLETED_SYNC_KEY: &str = "progress_job_from_completed_sync";
const PROGRESS_JOB_WORK_MODEL_KEY: &str = "progress_job_work_model";
pub(super) const PROGRESS_JOB_KEYS: [&str; 7] = [
    PROGRESS_JOB_POLICY_VERSION_KEY,
    PROGRESS_JOB_ID_KEY,
    PROGRESS_JOB_TOTAL_KEY,
    PROGRESS_JOB_FRACTION_KEY,
    PROGRESS_JOB_CLOSED_KEY,
    PROGRESS_JOB_FROM_COMPLETED_SYNC_KEY,
    PROGRESS_JOB_WORK_MODEL_KEY,
];
const PROGRESS_JOB_PERSIST_INTERVAL: Duration = Duration::from_secs(15);
// Persist sooner when the total grows by more than this share.
const PROGRESS_JOB_TOTAL_PERSIST_GROWTH: f64 = 0.001;
// Past the last known point, outputs continue at the average rate over at
// least this many blocks, so a short final segment does not set the rate.
const EXTRAPOLATION_LOOKBACK_BLOCKS: u64 = 10_000;

/// Raised when the estimate's code changes in a way the constants in
/// [`work_model_fingerprint`] do not show.
const WORK_MODEL_REVISION: u32 = 1;

/// Cumulative output count of one pool: outputs in blocks below a height.
#[derive(Debug, Clone, Default)]
struct OutputCurve {
    /// `(height, outputs in blocks below height)`, strictly increasing in
    /// height and non-decreasing in count.
    points: Vec<(u64, f64)>,
}

impl OutputCurve {
    fn from_points(mut points: Vec<(u64, f64)>) -> Self {
        points.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.total_cmp(&b.1)));
        let mut curve: Vec<(u64, f64)> = Vec::with_capacity(points.len());
        for (height, count) in points {
            match curve.last_mut() {
                Some(last) if last.0 == height => last.1 = last.1.max(count),
                Some(last) if count < last.1 => {}
                _ => curve.push((height, count)),
            }
        }
        Self { points: curve }
    }

    /// Outputs in blocks below `height`. Linear between known points, from
    /// zero at height 0, and continued past the last point at the average
    /// rate of the last [`EXTRAPOLATION_LOOKBACK_BLOCKS`] or more.
    fn below(&self, height: u64) -> f64 {
        let Some(&(last_height, last_count)) = self.points.last() else {
            return 0.0;
        };
        let at = self.points.partition_point(|&(h, _)| h <= height);
        if at == self.points.len() {
            let lookback_floor = last_height.saturating_sub(EXTRAPOLATION_LOOKBACK_BLOCKS);
            let base = self.points.partition_point(|&(h, _)| h <= lookback_floor);
            let (prev_height, prev_count) = if base == 0 {
                (0, 0.0)
            } else {
                self.points[base - 1]
            };
            let span = last_height.saturating_sub(prev_height).max(1) as f64;
            let rate = (last_count - prev_count) / span;
            return last_count + rate * height.saturating_sub(last_height) as f64;
        }
        let (h1, c1) = self.points[at];
        let (h0, c0) = if at == 0 {
            (0, 0.0)
        } else {
            self.points[at - 1]
        };
        let span = h1.saturating_sub(h0).max(1) as f64;
        c0 + (c1 - c0) * height.saturating_sub(h0) as f64 / span
    }

    fn between(&self, start: u64, end: u64) -> f64 {
        if end <= start {
            return 0.0;
        }
        (self.below(end) - self.below(start)).max(0.0)
    }
}

/// Estimates scan work for block ranges from local data only.
#[derive(Debug, Clone)]
pub(super) struct WorkModel {
    /// Sapling, Orchard, Ironwood.
    curves: [OutputCurve; 3],
    /// Block cap used to count planned batches. A fixed reference, so a
    /// foreground/background mode switch does not move the fraction.
    reference_batch_size: u32,
    /// One past the last compiled checkpoint (0 without compiled data).
    /// Batch sizes estimate bytes only below it, so they do not depend on
    /// extrapolation or on subtrees newer than the build.
    plan_end: u64,
    /// Heights below `plan_end` where any curve changes slope, then
    /// `plan_end`. Bytes per block are constant between neighbours.
    plan_knots: Vec<u64>,
}

impl WorkModel {
    pub(super) fn load(
        db_data_path: &str,
        network: WalletNetwork,
        reference_batch_size: u32,
    ) -> Result<Self, String> {
        let mut points = compiled_points(network);
        let plan_end = compiled_end(&points);
        for (pool, ends) in read_subtree_end_heights(db_data_path)?
            .into_iter()
            .enumerate()
        {
            for (index, end_height) in ends {
                points[pool].push((end_height + 1, (index + 1) as f64 * SUBTREE_LEAVES));
            }
        }
        Ok(Self::from_points(points, reference_batch_size, plan_end))
    }

    /// A model from the compiled tree sizes alone, for estimates made before
    /// a wallet DB exists.
    pub(super) fn compiled(network: WalletNetwork) -> Self {
        let points = compiled_points(network);
        let plan_end = compiled_end(&points);
        Self::from_points(points, BATCH_SIZE_FOREGROUND, plan_end)
    }

    fn from_points(points: [Vec<(u64, f64)>; 3], reference_batch_size: u32, plan_end: u64) -> Self {
        let [sapling, orchard, ironwood] = points;
        let curves = [
            OutputCurve::from_points(sapling),
            OutputCurve::from_points(orchard),
            OutputCurve::from_points(ironwood),
        ];
        let mut plan_knots: Vec<u64> = curves
            .iter()
            .flat_map(|curve| curve.points.iter().map(|&(height, _)| height))
            .filter(|&height| height < plan_end)
            .chain(std::iter::once(plan_end))
            .collect();
        plan_knots.sort_unstable();
        plan_knots.dedup();
        Self {
            curves,
            reference_batch_size: reference_batch_size.max(1),
            plan_end,
            plan_knots,
        }
    }

    /// Work of one full batch of empty blocks at the reference batch size.
    /// Growth below this never replaces a job.
    pub(super) fn reference_batch_work(&self) -> f64 {
        WORK_PER_BLOCK * f64::from(self.reference_batch_size) + WORK_PER_BATCH
    }

    /// Estimated work for blocks `[start, end)`.
    pub(super) fn range_work(&self, start: u64, end: u64) -> f64 {
        if end <= start {
            return 0.0;
        }
        let blocks = (end - start) as f64;
        let sapling = self.curves[0].between(start, end);
        let actions = self.curves[1].between(start, end) + self.curves[2].between(start, end);
        WORK_PER_BLOCK * blocks
            + WORK_PER_SAPLING_OUTPUT * sapling
            + WORK_PER_ORCHARD_ACTION * actions
            + WORK_PER_BATCH * self.planned_batches(start, end)
    }

    /// Estimated compact-block bytes to download for blocks `[start, end)`.
    pub(super) fn download_bytes(&self, start: u64, end: u64) -> f64 {
        let sapling = self.curves[0].between(start, end);
        let actions = self.curves[1].between(start, end) + self.curves[2].between(start, end);
        COMPACT_SAPLING_OUTPUT_BYTES * sapling + COMPACT_ACTION_BYTES * actions
    }

    /// Compact-block bytes that size batches for `[start, end)`: the
    /// download estimate below `plan_end`, zero past it.
    pub(super) fn plan_bytes(&self, start: u64, end: u64) -> f64 {
        self.download_bytes(start.min(self.plan_end), end.min(self.plan_end))
    }

    /// Blocks in the batch starting at `start`: as many as fit
    /// [`BATCH_BYTE_BUDGET`], at most `max_blocks` and at least
    /// [`MIN_BATCH_BLOCKS`] (or `max_blocks` when smaller). Past `plan_end`
    /// it takes at most [`UNPLANNED_BATCH_BLOCKS`].
    pub(super) fn batch_blocks(&self, start: u64, max_blocks: u32) -> u32 {
        let planned = u32::try_from(self.plan_end.saturating_sub(start)).unwrap_or(u32::MAX);
        let max = max_blocks
            .min(planned.saturating_add(UNPLANNED_BATCH_BLOCKS))
            .max(1);
        let min = MIN_BATCH_BLOCKS.min(max);
        let fits =
            |blocks: u32| self.plan_bytes(start, start + u64::from(blocks)) <= BATCH_BYTE_BUDGET;
        if fits(max) {
            return max;
        }
        if !fits(min) {
            return min;
        }
        // Bytes grow with the block count: `lo` fits and `hi` does not.
        let (mut lo, mut hi) = (min, max);
        while hi - lo > 1 {
            let mid = lo + (hi - lo) / 2;
            if fits(mid) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        lo
    }

    /// Batches the engine plans for `[start, end)` at the reference cap,
    /// counted fractionally so the count of a range equals the sum over any
    /// split of it. Between neighbouring knots bytes per block are constant,
    /// so each piece holds the larger of its bytes over the budget and its
    /// blocks over the cap, and at most its blocks over the minimum. Past
    /// `plan_end` the cap is at most [`UNPLANNED_BATCH_BLOCKS`].
    fn planned_batches(&self, start: u64, end: u64) -> f64 {
        if end <= start {
            return 0.0;
        }
        let planned_cap = f64::from(self.reference_batch_size);
        let unplanned_cap = f64::from(self.reference_batch_size.min(UNPLANNED_BATCH_BLOCKS));
        let min = f64::from(MIN_BATCH_BLOCKS.min(self.reference_batch_size));
        let first = self.plan_knots.partition_point(|&knot| knot <= start);
        let cuts = self.plan_knots[first..]
            .iter()
            .copied()
            .take_while(|&knot| knot < end)
            .chain(std::iter::once(end));
        let mut from = start;
        let mut batches = 0.0;
        for to in cuts {
            let blocks = (to - from) as f64;
            // Knots end at `plan_end`, so no piece crosses it.
            let cap = if from < self.plan_end {
                planned_cap
            } else {
                unplanned_cap
            };
            batches += (self.plan_bytes(from, to) / BATCH_BYTE_BUDGET)
                .max(blocks / cap)
                .min(blocks / min);
            from = to;
        }
        batches
    }

    /// Estimated work left in the pending ranges, up to the chain tip.
    pub(super) fn pending_work(&self, ranges: &[ScanRange], tip_height: u64) -> f64 {
        pending_blocks_up_to_tip(ranges, tip_height)
            .map(|(start, end)| self.range_work(start, end))
            .sum()
    }

    /// Estimated compact-block bytes left to download in the pending ranges,
    /// up to the chain tip.
    pub(super) fn pending_download_bytes(&self, ranges: &[ScanRange], tip_height: u64) -> f64 {
        pending_blocks_up_to_tip(ranges, tip_height)
            .map(|(start, end)| self.download_bytes(start, end))
            .sum()
    }
}

/// The `[start, end)` blocks of each pending range, cut at the chain tip.
fn pending_blocks_up_to_tip(
    ranges: &[ScanRange],
    tip_height: u64,
) -> impl Iterator<Item = (u64, u64)> + '_ {
    let tip_end = tip_height.saturating_add(1);
    ranges
        .iter()
        .filter(|range| is_pending_scan_range(range))
        .map(move |range| {
            let start = u64::from(u32::from(range.block_range().start));
            let end = u64::from(u32::from(range.block_range().end)).min(tip_end);
            (start, end)
        })
}

/// One past the last compiled checkpoint, or 0 without one.
fn compiled_end(points: &[Vec<(u64, f64)>; 3]) -> u64 {
    points[0].last().map_or(0, |&(height, _)| height)
}

/// Output-count points from the compiled mainnet tree sizes (none elsewhere).
fn compiled_points(network: WalletNetwork) -> [Vec<(u64, f64)>; 3] {
    let mut points: [Vec<(u64, f64)>; 3] = Default::default();
    for &(height, sizes) in mainnet_tree_sizes(network) {
        for pool in 0..3 {
            // A checkpoint holds the tree size at the end of its block.
            points[pool].push((height + 1, sizes[pool] as f64));
        }
    }
    points
}

fn read_subtree_end_heights(db_data_path: &str) -> Result<[Vec<(u64, u64)>; 3], String> {
    let conn = open_readonly_conn_with_timeout(db_data_path, Some(SYNC_DB_BUSY_TIMEOUT))?;
    let mut out: [Vec<(u64, u64)>; 3] = Default::default();
    for (pool, table) in POOL_TABLES.iter().enumerate() {
        let sql = format!(
            "SELECT shard_index, subtree_end_height FROM {table}
             WHERE subtree_end_height IS NOT NULL ORDER BY shard_index"
        );
        let mut stmt = match conn.prepare(&sql) {
            Ok(stmt) => stmt,
            // A wallet created before this pool's table existed has no subtrees.
            Err(e) if e.to_string().contains("no such table") => continue,
            Err(e) => return Err(format!("read {table}: {e}")),
        };
        let rows = stmt
            .query_map([], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)))
            .map_err(|e| format!("read {table}: {e}"))?;
        for row in rows {
            let (index, end_height) = row.map_err(|e| format!("read {table}: {e}"))?;
            if index >= 0 && end_height >= 0 {
                out[pool].push((index as u64, end_height as u64));
            }
        }
    }
    Ok(out)
}

/// The persisted part of an unfinished sync job.
#[derive(Debug, Clone, PartialEq)]
pub(super) struct StoredProgressJob {
    pub(super) id: String,
    /// Zero while the job is claimed but its work not yet measured.
    pub(super) total_work: f64,
    /// Last fraction reported for the job, shown during the next attempt's
    /// preparation before its pending work is measured.
    pub(super) fraction: f64,
    /// Saved when the attempt ended (completed its loop, stopped, failed)
    /// rather than by a periodic save. The fraction then matches what was
    /// scanned, so less pending work at the next start went away unscanned.
    /// After a killed process the last save can be up to 15 seconds behind.
    pub(super) closed: bool,
    /// Claimed while the last sync stood completed: a catch-up. The status
    /// reports it, so a relaunch shows an interrupted catch-up as one.
    /// Missing in a job saved before the key existed, and read as false.
    pub(super) from_completed_sync: bool,
    /// Measured in this build's work units ([`work_model_fingerprint`]). A
    /// job saved by a build that sized batches or weighted work differently,
    /// or before the key existed, reads false.
    pub(super) current_work_model: bool,
}

impl StoredProgressJob {
    /// A new job whose work is not measured yet.
    pub(super) fn unmeasured() -> Self {
        Self {
            id: new_job_id(),
            total_work: 0.0,
            fraction: 0.0,
            closed: false,
            from_completed_sync: false,
            current_work_model: true,
        }
    }
}

/// Identifies the units a job's work is measured in: every constant
/// [`WorkModel`] reads (batch sizes, byte budget, weights, output bytes and the
/// extrapolation lookback), its code revision, and the compiled tree sizes it
/// estimates from. The weekly table update appends checkpoints, which changes
/// both the output estimate and where byte budgets apply, so an app update
/// resumes a job at its fraction. Production measures with the
/// [`BATCH_SIZE_FOREGROUND`] reference (`WorkModel::load` in the sync loop); a
/// second reference size would have to be part of this too.
pub(super) fn work_model_fingerprint() -> String {
    format!(
        "{WORK_MODEL_REVISION}/{BATCH_SIZE_FOREGROUND}/{BATCH_BYTE_BUDGET}/{MIN_BATCH_BLOCKS}/\
         {UNPLANNED_BATCH_BLOCKS}/{WORK_PER_BLOCK}/{WORK_PER_SAPLING_OUTPUT}/\
         {WORK_PER_ORCHARD_ACTION}/{WORK_PER_BATCH}/{COMPACT_SAPLING_OUTPUT_BYTES}/\
         {COMPACT_ACTION_BYTES}/{SUBTREE_LEAVES}/{EXTRAPOLATION_LOOKBACK_BLOCKS}/{}",
        last_checkpoint_height()
    )
}

pub(super) fn read_progress_job(db_data_path: &str) -> Result<Option<StoredProgressJob>, String> {
    let conn = open_readonly_conn_with_timeout(db_data_path, Some(SYNC_DB_BUSY_TIMEOUT))?;
    read_job(&conn)
}

/// Returns the stored job, or claims a new unmeasured one, inside the
/// transaction that marks a sync started. Every event of the attempt then
/// names the job, and an attempt that fails before measuring keeps the id.
/// A finished job (the scan finished, the attempt stopped before completing)
/// is returned too, so preparation keeps showing where it ended; measuring
/// it starts a new job from zero only when there is work to scan
/// ([`JobProgress::start`]), as after a completed sync.
/// A new job is a catch-up when `from_completed_sync`.
pub(super) fn claim_progress_job(
    tx: &rusqlite::Transaction<'_>,
    from_completed_sync: bool,
) -> Result<StoredProgressJob, String> {
    if let Some(job) = read_job(tx)? {
        return Ok(job);
    }
    let job = StoredProgressJob {
        from_completed_sync,
        ..StoredProgressJob::unmeasured()
    };
    write_job(tx, &job)?;
    Ok(job)
}

fn read_job(conn: &rusqlite::Connection) -> Result<Option<StoredProgressJob>, String> {
    let read = |key: &str| -> Result<Option<String>, String> {
        match conn
            .query_row(
                "SELECT value FROM ext_vizor_sync_meta WHERE key = ?1",
                params![key],
                |row| row.get::<_, String>(0),
            )
            .optional()
        {
            Ok(value) => Ok(value),
            Err(e) if e.to_string().contains("no such table") => Ok(None),
            Err(e) => Err(format!("read {key}: {e}")),
        }
    };
    let version = read(PROGRESS_JOB_POLICY_VERSION_KEY)?.and_then(|v| v.parse::<u32>().ok());
    if version != Some(PROGRESS_JOB_POLICY_VERSION) {
        return Ok(None);
    }
    let id = read(PROGRESS_JOB_ID_KEY)?.filter(|id| !id.is_empty());
    let total_work = read(PROGRESS_JOB_TOTAL_KEY)?.and_then(|v| v.parse::<f64>().ok());
    let fraction = read(PROGRESS_JOB_FRACTION_KEY)?
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(0.0);
    let closed = read(PROGRESS_JOB_CLOSED_KEY)?.as_deref() == Some("1");
    let from_completed_sync = read(PROGRESS_JOB_FROM_COMPLETED_SYNC_KEY)?.as_deref() == Some("1");
    let current_work_model =
        read(PROGRESS_JOB_WORK_MODEL_KEY)?.as_deref() == Some(work_model_fingerprint().as_str());
    match (id, total_work) {
        (Some(id), Some(total_work)) if total_work.is_finite() && total_work >= 0.0 => {
            Ok(Some(StoredProgressJob {
                id,
                total_work,
                fraction: if fraction.is_finite() {
                    fraction.clamp(0.0, 1.0)
                } else {
                    0.0
                },
                closed,
                from_completed_sync,
                current_work_model,
            }))
        }
        _ => Ok(None),
    }
}

pub(super) fn write_progress_job(
    db_data_path: &str,
    job: &StoredProgressJob,
) -> Result<(), String> {
    let mut conn = open_wallet_raw_conn_with_timeout(db_data_path, SYNC_DB_BUSY_TIMEOUT)?;
    ensure_sync_meta_table(&conn)?;
    let tx = conn
        .transaction()
        .map_err(|e| format!("begin progress job transaction: {e}"))?;
    write_job(&tx, job)?;
    tx.commit()
        .map_err(|e| format!("commit progress job transaction: {e}"))
}

fn write_job(tx: &rusqlite::Transaction<'_>, job: &StoredProgressJob) -> Result<(), String> {
    for (key, value) in [
        (
            PROGRESS_JOB_POLICY_VERSION_KEY,
            PROGRESS_JOB_POLICY_VERSION.to_string(),
        ),
        (PROGRESS_JOB_ID_KEY, job.id.clone()),
        (PROGRESS_JOB_TOTAL_KEY, job.total_work.to_string()),
        (PROGRESS_JOB_FRACTION_KEY, job.fraction.to_string()),
        (PROGRESS_JOB_CLOSED_KEY, u8::from(job.closed).to_string()),
        (
            PROGRESS_JOB_FROM_COMPLETED_SYNC_KEY,
            u8::from(job.from_completed_sync).to_string(),
        ),
        (PROGRESS_JOB_WORK_MODEL_KEY, work_model_fingerprint()),
    ] {
        tx.execute(
            "INSERT INTO ext_vizor_sync_meta(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )
        .map_err(|e| format!("write {key}: {e}"))?;
    }
    Ok(())
}

/// Removes the progress job inside a transaction that marks a sync complete.
pub(super) fn clear_progress_job(tx: &rusqlite::Transaction<'_>) -> Result<(), String> {
    for key in PROGRESS_JOB_KEYS {
        tx.execute(
            "DELETE FROM ext_vizor_sync_meta WHERE key = ?1",
            params![key],
        )
        .map_err(|e| format!("clear {key}: {e}"))?;
    }
    Ok(())
}

fn new_job_id() -> String {
    format!("{:016x}", rand::random::<u64>())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum JobStart {
    New,
    Resumed,
    /// More new work is pending than the stored job had finished, such as
    /// after an account with an older birthday was added. The job restarts
    /// under a new id so the display resets instead of crawling from the old
    /// fraction.
    Replaced,
}

/// Progress of one sync job in work units.
#[derive(Debug)]
pub(super) struct JobProgress {
    id: String,
    total: f64,
    remaining: f64,
    persisted_total: f64,
    persisted_at: Option<Instant>,
    /// Wallet DB the job is saved to, recorded by the first save. Dropping
    /// the job saves it there as closed, unless the sync completed.
    store: Option<String>,
    /// See [`StoredProgressJob::from_completed_sync`].
    from_completed_sync: bool,
}

impl JobProgress {
    /// Continues `stored` with `pending` work measured for this attempt.
    ///
    /// Work that appeared since the stored fraction (blocks mined while the
    /// app was closed, a rewind), or went away after an attempt that saved
    /// where it stopped (a deleted account), keeps that fraction and rescales
    /// the rest, so the display neither drops nor jumps.
    /// Growth beyond what the job had finished, and at least
    /// `min_replace_growth`, starts a new job.
    /// A job measured in other work units keeps its fraction and rescales the
    /// rest whichever way the new measurement differs.
    pub(super) fn start(
        stored: StoredProgressJob,
        pending: f64,
        min_replace_growth: f64,
    ) -> (Self, JobStart) {
        let pending = pending.max(0.0);
        let StoredProgressJob {
            id,
            total_work: stored_total,
            fraction,
            closed,
            from_completed_sync,
            current_work_model,
        } = stored;
        let (id, total, start) = if stored_total <= 0.0 {
            // Claimed when the attempt began; this is its first measurement.
            (id, pending, JobStart::New)
        } else {
            let done = fraction * stored_total;
            let expected = stored_total - done;
            let growth = pending - expected;
            let eps = 1e-9 * stored_total.max(1.0);
            if !current_work_model && expected > eps && pending > eps {
                // Saved by a build that counted work differently: its units do
                // not compare with this measurement, so a difference is neither
                // scanned work nor new work.
                (id, pending / (1.0 - fraction), JobStart::Resumed)
            } else if growth.abs() <= eps || (growth < 0.0 && !closed) {
                // Unchanged, or less work after an attempt that did not save
                // where it stopped: it scanned past its last periodic save.
                (id, stored_total, JobStart::Resumed)
            } else if growth > 0.0 && (expected <= eps || growth > done.max(min_replace_growth)) {
                // A finished job has no remaining share to stretch new work
                // over, and more new work than was finished outgrows one.
                (new_job_id(), pending, JobStart::Replaced)
            } else {
                (id, pending / (1.0 - fraction), JobStart::Resumed)
            }
        };
        let job = Self {
            id,
            total,
            remaining: pending,
            persisted_total: 0.0,
            persisted_at: None,
            store: None,
            // A replacement follows a job that never completed.
            from_completed_sync: from_completed_sync && start != JobStart::Replaced,
        };
        (job, start)
    }

    pub(super) fn id(&self) -> &str {
        &self.id
    }

    /// See [`StoredProgressJob::from_completed_sync`].
    pub(super) fn from_completed_sync(&self) -> bool {
        self.from_completed_sync
    }

    /// Not a catch-up after all; the next save stores that.
    pub(super) fn clear_from_completed_sync(&mut self) {
        self.from_completed_sync = false;
    }

    pub(super) fn total(&self) -> f64 {
        self.total
    }

    pub(super) fn remaining(&self) -> f64 {
        self.remaining
    }

    pub(super) fn fraction(&self) -> f64 {
        if self.total <= 0.0 {
            return 1.0;
        }
        (1.0 - self.remaining / self.total).clamp(0.0, 1.0)
    }

    /// The fraction once `work` more is finished, for the display target.
    pub(super) fn fraction_after(&self, work: f64) -> f64 {
        if self.total <= 0.0 {
            return 1.0;
        }
        (1.0 - (self.remaining - work).max(0.0) / self.total).clamp(0.0, 1.0)
    }

    /// Records pending work measured outside a scanned batch. Any increase is
    /// new work (a rewind, a repair, a new range) and raises the total; a
    /// decrease (a deleted account, pruned ranges) keeps the fraction.
    pub(super) fn observe(&mut self, pending: f64) {
        let expected = self.remaining;
        self.record(expected, pending);
    }

    /// Records pending work after scanning a batch estimated at `batch_work`.
    /// Pending work beyond what the batch should have left is new work, such
    /// as blocks mined since the batch began.
    pub(super) fn observe_after_batch(&mut self, batch_work: f64, pending: f64) {
        let expected = (self.remaining - batch_work).max(0.0);
        self.record(expected, pending);
    }

    fn record(&mut self, expected: f64, pending: f64) {
        let pending = pending.max(0.0);
        let growth = pending - expected;
        let eps = 1e-9 * self.total.max(1.0);
        if growth > eps {
            self.total += growth;
        } else if growth < -eps {
            // Work that went away unscanned is not progress: keep the fraction
            // this measurement expected and spread what is left over the rest.
            self.total *= pending / expected;
        }
        if self.total < pending {
            self.total = pending;
        }
        self.remaining = pending;
    }

    /// Stores the job when it has work, at most every few seconds unless the
    /// total grew noticeably. Failure only costs resume accuracy, so it is
    /// logged and ignored.
    pub(super) fn persist_if_due(&mut self, db_data_path: &str, force: bool) {
        if self.store.is_none() {
            self.store = Some(db_data_path.to_owned());
        }
        if self.total <= 0.0 {
            return;
        }
        let grown = self.total > self.persisted_total * (1.0 + PROGRESS_JOB_TOTAL_PERSIST_GROWTH);
        let due = self
            .persisted_at
            .is_none_or(|at| at.elapsed() >= PROGRESS_JOB_PERSIST_INTERVAL);
        if !(force || grown || due) {
            return;
        }
        match self.save(db_data_path, false) {
            Ok(()) => {
                self.persisted_total = self.total;
                self.persisted_at = Some(Instant::now());
            }
            Err(e) => {
                // Retry after the normal interval instead of on every batch.
                self.persisted_total = self.total;
                self.persisted_at = Some(Instant::now());
                log::warn!("[{}] sync: progress job not saved: {e}", elapsed());
            }
        }
    }

    /// The sync completed and cleared the job; dropping it saves nothing.
    pub(super) fn complete(&mut self) {
        self.store = None;
    }

    fn save(&self, db_data_path: &str, closed: bool) -> Result<(), String> {
        let stored = StoredProgressJob {
            id: self.id.clone(),
            total_work: self.total,
            fraction: self.fraction(),
            closed,
            from_completed_sync: self.from_completed_sync,
            current_work_model: true,
        };
        crate::wallet::db::with_wallet_db_write_lock("sync_engine.progress_job", || {
            write_progress_job(db_data_path, &stored)
        })
    }
}

impl Drop for JobProgress {
    /// Saves where the attempt stopped, however it ended, so the next attempt
    /// can tell work that went away from scanning a periodic save missed. A
    /// wallet DB that is gone (a reset) is not recreated.
    fn drop(&mut self) {
        let Some(path) = self.store.take() else {
            return;
        };
        if self.total <= 0.0 || !std::path::Path::new(&path).exists() {
            return;
        }
        if let Err(e) = self.save(&path, true) {
            log::warn!(
                "[{}] sync: progress job not saved at attempt end: {e}",
                elapsed()
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::data_api::scanning::ScanPriority;
    use zcash_protocol::consensus::BlockHeight;

    fn range(start: u32, end: u32, priority: ScanPriority) -> ScanRange {
        ScanRange::from_parts(
            BlockHeight::from_u32(start)..BlockHeight::from_u32(end),
            priority,
        )
    }

    fn model_without_outputs(reference_batch_size: u32) -> WorkModel {
        WorkModel::from_points(Default::default(), reference_batch_size, 0)
    }

    /// Batch starts and sizes the engine plans over `[start, end)`.
    fn plan(model: &WorkModel, start: u64, end: u64, cap: u32) -> Vec<(u64, u32)> {
        let mut batches = Vec::new();
        let mut next = start;
        while next < end {
            let blocks = model.batch_blocks(next, cap);
            batches.push((next, blocks));
            next += u64::from(blocks);
        }
        batches
    }

    fn new_job(pending: f64) -> JobProgress {
        let (job, start) = JobProgress::start(StoredProgressJob::unmeasured(), pending, 1.0);
        assert_eq!(start, JobStart::New);
        job
    }

    /// A job last saved by a periodic save, as a killed process leaves it.
    fn stored(total_work: f64, fraction: f64) -> StoredProgressJob {
        StoredProgressJob {
            id: "abc".into(),
            total_work,
            fraction,
            closed: false,
            from_completed_sync: false,
            current_work_model: true,
        }
    }

    /// A job saved where its attempt stopped.
    fn closed(total_work: f64, fraction: f64) -> StoredProgressJob {
        StoredProgressJob {
            closed: true,
            ..stored(total_work, fraction)
        }
    }

    fn temp_db() -> (tempfile::TempDir, String) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db").to_str().unwrap().to_string();
        rusqlite::Connection::open(&path).unwrap();
        (dir, path)
    }

    #[test]
    fn output_curve_interpolates_and_extends_at_the_lookback_rate() {
        let curve = OutputCurve::from_points(vec![(100, 1_000.0), (200, 3_000.0)]);
        assert_eq!(curve.below(0), 0.0);
        assert_eq!(curve.below(50), 500.0);
        assert_eq!(curve.below(150), 2_000.0);
        assert_eq!(curve.below(200), 3_000.0);
        // Both points lie within the lookback, so the rate runs from zero.
        assert_eq!(curve.below(250), 3_750.0);
        assert_eq!(curve.between(150, 250), 1_750.0);
    }

    #[test]
    fn a_short_final_segment_does_not_set_the_extrapolated_rate() {
        // A subtree that completed 10 blocks after a checkpoint looks like
        // 100 outputs per block; the last 10,000 blocks average 0.2.
        let curve = OutputCurve::from_points(vec![
            (10_000, 1_000.0),
            (20_000, 2_000.0),
            (20_010, 3_000.0),
        ]);
        let rate = (3_000.0 - 1_000.0) / 10_010.0;
        assert!((curve.below(30_010) - (3_000.0 + rate * 10_000.0)).abs() < 1e-9);
    }

    #[test]
    fn output_curve_drops_points_that_would_shrink_the_tree() {
        let curve = OutputCurve::from_points(vec![(300, 900.0), (100, 1_000.0), (200, 500.0)]);
        assert_eq!(curve.points, vec![(100, 1_000.0)]);
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn mainnet_curve_matches_compiled_checkpoints() {
        let sizes = mainnet_tree_sizes(WalletNetwork::Main);
        let mut points: [Vec<(u64, f64)>; 3] = Default::default();
        for &(height, s) in sizes {
            for pool in 0..3 {
                points[pool].push((height + 1, s[pool] as f64));
            }
        }
        let plan_end = sizes.last().unwrap().0 + 1;
        let model = WorkModel::from_points(points, 2_000, plan_end);
        assert_eq!(
            model.plan_end,
            WorkModel::compiled(WalletNetwork::Main).plan_end
        );
        let (height, s) = sizes[200];
        assert_eq!(model.curves[0].below(height + 1), s[0] as f64);
        assert_eq!(model.curves[1].below(height + 1), s[1] as f64);
        // A whole checkpoint step holds exactly the outputs between the two checkpoints.
        let (next_height, next) = sizes[201];
        assert_eq!(
            model.curves[0].between(height + 1, next_height + 1),
            (next[0] - s[0]) as f64
        );
    }

    #[test]
    fn subtree_end_heights_become_points() {
        let model = WorkModel::from_points(
            [vec![(1_001, 65_536.0), (2_001, 131_072.0)], vec![], vec![]],
            2_000,
            0,
        );
        assert_eq!(model.curves[0].below(2_001), 131_072.0);
        assert_eq!(model.curves[0].between(1_001, 2_001), 65_536.0);
    }

    #[test]
    fn load_reads_completed_subtrees_of_each_pool_table() {
        let (_dir, path) = temp_db();
        let conn = rusqlite::Connection::open(&path).unwrap();
        // No ironwood table: a wallet created before the pool existed.
        conn.execute_batch(
            "CREATE TABLE sapling_tree_shards (
                 shard_index INTEGER PRIMARY KEY, subtree_end_height INTEGER);
             CREATE TABLE orchard_tree_shards (
                 shard_index INTEGER PRIMARY KEY, subtree_end_height INTEGER);
             INSERT INTO sapling_tree_shards VALUES (0, 1000), (1, 2000), (2, NULL);
             INSERT INTO orchard_tree_shards VALUES (0, 5000);",
        )
        .unwrap();

        // Off mainnet there are no compiled sizes, so only subtrees count.
        let model = WorkModel::load(&path, WalletNetwork::Test, 2_000).unwrap();
        // Subtree i holds leaves up to (i + 1) * 2^16 once its end block is in.
        assert_eq!(
            model.curves[0].points,
            vec![(1_001, 65_536.0), (2_001, 131_072.0)]
        );
        assert_eq!(model.curves[1].points, vec![(5_001, 65_536.0)]);
        assert!(model.curves[2].points.is_empty());
        // Without compiled data the subtrees do not size batches.
        assert_eq!(model.plan_end, 0);
        assert_eq!(model.plan_bytes(1_001, 5_001), 0.0);
        assert_eq!(model.batch_blocks(1_001, 1_000), 1_000);
    }

    #[test]
    fn planned_batches_follow_the_byte_budget() {
        // Without compiled data every batch is the cap.
        let model = model_without_outputs(2_000);
        assert!((model.planned_batches(419_200, 3_390_000) - 2_970_800.0 / 2_000.0).abs() < 1e-9);
        // A larger cap counts the unplanned cap there, as the planner sizes
        // those batches.
        let model = model_without_outputs(10_000);
        let unplanned = f64::from(UNPLANNED_BATCH_BLOCKS);
        assert!((model.planned_batches(0, 20_000) - 20_000.0 / unplanned).abs() < 1e-9);
        let sparse = WorkModel::from_points(Default::default(), 10_000, 100_000);
        assert!((sparse.planned_batches(0, 120_000) - (10.0 + 20_000.0 / unplanned)).abs() < 1e-9);
        assert_eq!(
            plan(&sparse, 90_000, 104_000, 10_000),
            [(90_000, 10_000), (100_000, 2_000), (102_000, 2_000)]
        );

        // Sapling outputs worth one budget per 100 blocks over 1,000,000..
        // 1,100,000, then one budget per 2 blocks over 1,100,000..1,101,000.
        let per_budget = BATCH_BYTE_BUDGET / COMPACT_SAPLING_OUTPUT_BYTES;
        let dense = 1_000.0 * per_budget;
        let model = WorkModel::from_points(
            [
                vec![
                    (1_000_000, 0.0),
                    (1_100_000, dense),
                    (1_101_000, dense + 500.0 * per_budget),
                ],
                vec![],
                vec![],
            ],
            2_000,
            u64::MAX,
        );
        let close = |a: f64, b: f64| (a - b).abs() < 1e-9 * b.max(1.0);
        // Sparse blocks: one batch per cap.
        assert!(close(model.planned_batches(0, 1_000_000), 500.0));
        // Dense blocks: one batch per budget.
        assert!(close(model.planned_batches(1_000_000, 1_100_000), 1_000.0));
        // Denser still: one batch per `MIN_BATCH_BLOCKS`.
        let min = f64::from(MIN_BATCH_BLOCKS);
        assert!(close(
            model.planned_batches(1_100_000, 1_101_000),
            1_000.0 / min
        ));
        assert!(close(
            model.planned_batches(0, 1_101_000),
            500.0 + 1_000.0 + 1_000.0 / min,
        ));
        // The planner agrees, down to the minimum.
        assert_eq!(plan(&model, 1_000_000, 1_100_000, 2_000).len(), 1_000);
        let floor = plan(&model, 1_100_000, 1_101_000, 2_000);
        assert!(floor.iter().all(|&(_, blocks)| blocks == MIN_BATCH_BLOCKS));
        assert_eq!(floor.len(), 1_000 / MIN_BATCH_BLOCKS as usize);
    }

    #[test]
    fn batches_shrink_in_a_subtree_burst() {
        // A compiled-like step whose outputs average half a budget per cap
        // batch, all of them inside a 1,000-block burst.
        let cap = 1_000;
        let outputs = 5.0 * BATCH_BYTE_BUDGET / COMPACT_SAPLING_OUTPUT_BYTES;
        let sparse = vec![(100_001, 0.0), (110_001, outputs)];
        let compiled = WorkModel::from_points([sparse.clone(), vec![], vec![]], cap, 110_001);
        assert!(plan(&compiled, 100_001, 110_001, cap)
            .iter()
            .all(|&(_, blocks)| blocks == cap));

        let mut knotted = sparse;
        knotted.extend([(104_001, 0.0), (105_001, outputs)]);
        let model = WorkModel::from_points([knotted, vec![], vec![]], cap, 110_001);
        let batches = plan(&model, 100_001, 110_001, cap);
        assert!(batches.iter().any(|&(_, blocks)| blocks < cap / 4));
        for (start, blocks) in batches {
            let bytes = model.plan_bytes(start, start + u64::from(blocks));
            assert!(bytes <= BATCH_BYTE_BUDGET || blocks == MIN_BATCH_BLOCKS);
        }
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn planner_and_progress_count_the_same_batches() {
        let main = WorkModel::compiled(WalletNetwork::Main);
        let range_end = BlockHeight::from_u32(u32::try_from(main.plan_end).unwrap());
        let mut next = BlockHeight::from_u32(419_200);
        let mut planned = 0u32;
        while let Some((_, end)) =
            super::super::planned_batch_end(&main, BATCH_SIZE_FOREGROUND, next, range_end)
        {
            planned += 1;
            next = end;
        }
        let counted = main.planned_batches(419_200, main.plan_end);
        assert!(
            (f64::from(planned) - counted).abs() <= 1.0 + 0.005 * counted,
            "planner {planned} vs progress {counted}",
        );
    }

    #[test]
    fn range_work_is_additive_across_splits() {
        let model = WorkModel::from_points(
            [
                vec![(1_000_000, 10_000_000.0), (1_800_000, 80_000_000.0)],
                vec![(1_700_000, 0.0), (2_000_000, 40_000_000.0)],
                vec![],
            ],
            2_000,
            u64::MAX,
        );
        let whole = model.range_work(1_600_000, 2_100_000);
        let split = model.range_work(1_600_000, 1_722_700)
            + model.range_work(1_722_700, 1_722_800)
            + model.range_work(1_722_800, 2_100_000);
        assert!((whole - split).abs() < 1e-6 * whole);
    }

    #[test]
    fn pending_work_counts_only_pending_ranges_up_to_the_tip() {
        let model = model_without_outputs(1_000);
        let ranges = [
            range(10_000, 12_000, ScanPriority::Historic),
            range(12_000, 13_000, ScanPriority::Scanned),
            range(13_000, 20_000, ScanPriority::ChainTip),
        ];
        let expected = model.range_work(10_000, 12_000) + model.range_work(13_000, 15_001);
        assert!((model.pending_work(&ranges, 15_000) - expected).abs() < 1e-12);
    }

    #[test]
    fn pending_download_bytes_count_only_pending_ranges_up_to_the_tip() {
        let model = WorkModel::from_points(
            [
                vec![(10_000, 0.0), (20_000, 1_000_000.0)],
                vec![(10_000, 0.0), (20_000, 500_000.0)],
                vec![],
            ],
            1_000,
            u64::MAX,
        );
        let ranges = [
            range(10_000, 12_000, ScanPriority::Historic),
            range(12_000, 13_000, ScanPriority::Scanned),
            range(13_000, 20_000, ScanPriority::ChainTip),
        ];
        let expected = model.download_bytes(10_000, 12_000) + model.download_bytes(13_000, 15_001);
        assert!(expected > 0.0);
        assert!((model.pending_download_bytes(&ranges, 15_000) - expected).abs() < 1e-6);
    }

    #[test]
    fn job_fraction_advances_by_batch_work_and_absorbs_tip_growth() {
        let mut job = new_job(100.0);
        assert_eq!(job.fraction(), 0.0);
        assert!((job.fraction_after(25.0) - 0.25).abs() < 1e-12);

        job.observe_after_batch(25.0, 75.0);
        assert!((job.fraction() - 0.25).abs() < 1e-12);

        // A batch of 25 also brought 5 units of newly mined blocks.
        job.observe_after_batch(25.0, 55.0);
        assert!((job.total() - 105.0).abs() < 1e-12);
        assert!((job.fraction() - 50.0 / 105.0).abs() < 1e-12);

        job.observe_after_batch(55.0, 0.0);
        assert_eq!(job.fraction(), 1.0);
    }

    #[test]
    fn rewound_work_raises_the_total_instead_of_restarting() {
        let mut job = new_job(1_000.0);
        job.observe_after_batch(600.0, 400.0);
        assert!((job.fraction() - 0.6).abs() < 1e-12);
        // A reorg requeues 10 units: a small, legitimate dip, not a reset.
        job.observe(410.0);
        assert!((job.total() - 1_010.0).abs() < 1e-12);
        assert!((job.fraction() - 600.0 / 1_010.0).abs() < 1e-12);
        // Measuring again without change keeps the fraction.
        job.observe(410.0);
        assert!((job.fraction() - 600.0 / 1_010.0).abs() < 1e-12);
    }

    #[test]
    fn an_unmeasured_claim_keeps_its_id() {
        let claimed = StoredProgressJob::unmeasured();
        let id = claimed.id.clone();
        let (job, start) = JobProgress::start(claimed, 250.0, 1.0);
        assert_eq!(start, JobStart::New);
        assert_eq!(job.id(), id);
        assert_eq!(job.total(), 250.0);
        assert_eq!(job.fraction(), 0.0);
    }

    #[test]
    fn a_stored_job_resumes_its_fraction_and_id() {
        let (job, start) = JobProgress::start(stored(1_000.0, 0.6), 400.0, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert_eq!(job.id(), "abc");
        assert!((job.fraction() - 0.6).abs() < 1e-12);

        // Less work than stored after a killed process is scanning done
        // after the last periodic save.
        let (job, _) = JobProgress::start(stored(1_000.0, 0.6), 300.0, 1.0);
        assert_eq!(job.id(), "abc");
        assert!((job.fraction() - 0.7).abs() < 1e-12);

        // After an attempt saved where it stopped, the same decrease is work
        // that went away unscanned (a deleted account): the fraction stays.
        let (job, _) = JobProgress::start(closed(1_000.0, 0.6), 300.0, 1.0);
        assert!((job.fraction() - 0.6).abs() < 1e-12);

        // Unchanged work resumes either way.
        let (job, _) = JobProgress::start(closed(1_000.0, 0.6), 400.0, 1.0);
        assert!((job.fraction() - 0.6).abs() < 1e-12);
    }

    #[test]
    fn work_added_between_attempts_keeps_the_fraction_already_shown() {
        // 50 units mined while the app was closed, at 60% of 1,000.
        let (mut job, start) = JobProgress::start(stored(1_000.0, 0.6), 450.0, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert_eq!(job.id(), "abc");
        assert!((job.fraction() - 0.6).abs() < 1e-12);
        assert!((job.total() - 1_125.0).abs() < 1e-9);
        // The rest advances at the stretched scale.
        job.observe_after_batch(45.0, 405.0);
        assert!((job.fraction() - 0.64).abs() < 1e-12);
    }

    #[test]
    fn removed_work_keeps_the_fraction_and_rescales_the_rest() {
        let mut job = new_job(1_000.0);
        job.observe_after_batch(200.0, 800.0);
        assert!((job.fraction() - 0.2).abs() < 1e-12);
        // An account with old history is deleted: 760 of the 800 units go
        // away without being scanned. The bar stays where it was.
        job.observe(40.0);
        assert!((job.fraction() - 0.2).abs() < 1e-12);
        assert!((job.total() - 50.0).abs() < 1e-9);
        // What is left fills the remaining 80%.
        job.observe_after_batch(20.0, 20.0);
        assert!((job.fraction() - 0.6).abs() < 1e-12);
        job.observe_after_batch(20.0, 0.0);
        assert!((job.fraction() - 1.0).abs() < 1e-12);
    }

    #[test]
    fn work_removed_between_attempts_keeps_the_fraction_already_shown() {
        // The account was deleted while the sync was paused at 20% of 1,000;
        // pausing ended the attempt, which saved where it stopped.
        let (mut job, start) = JobProgress::start(closed(1_000.0, 0.2), 40.0, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert_eq!(job.id(), "abc");
        assert!((job.fraction() - 0.2).abs() < 1e-12);
        assert!((job.total() - 50.0).abs() < 1e-9);
        job.observe_after_batch(20.0, 20.0);
        assert!((job.fraction() - 0.6).abs() < 1e-12);
    }

    #[test]
    fn a_block_mined_before_the_first_batch_resumes_the_job() {
        // A small job failed before committing a batch; one more block is
        // pending on retry. It is the same job, not a replacement.
        let one_block = WORK_PER_BLOCK;
        let (job, start) = JobProgress::start(stored(0.3, 0.0), 0.3 + one_block, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert_eq!(job.id(), "abc");
        assert_eq!(job.fraction(), 0.0);
        assert!((job.total() - (0.3 + one_block)).abs() < 1e-12);
    }

    #[test]
    fn more_new_work_than_the_job_finished_replaces_it() {
        // 1,100 new units against 600 finished: an older account was added.
        let (job, start) = JobProgress::start(stored(1_000.0, 0.6), 1_500.0, 1.0);
        assert_eq!(start, JobStart::Replaced);
        assert_ne!(job.id(), "abc");
        assert_eq!(job.fraction(), 0.0);
        assert_eq!(job.total(), 1_500.0);

        // Growth above what was finished but below one batch of work resumes.
        let (job, start) = JobProgress::start(stored(1.0, 0.2), 0.8 + 0.5, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert!((job.fraction() - 0.2).abs() < 1e-12);
    }

    #[test]
    fn a_catch_up_stays_one_unless_its_job_is_replaced() {
        let catch_up = |total_work, fraction| StoredProgressJob {
            from_completed_sync: true,
            ..stored(total_work, fraction)
        };
        let claimed = StoredProgressJob {
            from_completed_sync: true,
            ..StoredProgressJob::unmeasured()
        };
        let (mut job, start) = JobProgress::start(claimed, 40.0, 1.0);
        assert_eq!(start, JobStart::New);
        assert!(job.from_completed_sync);
        let (_dir, path) = temp_db();
        let stored_catch_up = |path: &str| {
            read_progress_job(path)
                .unwrap()
                .unwrap()
                .from_completed_sync
        };
        job.persist_if_due(&path, true);
        assert!(stored_catch_up(&path));
        job.clear_from_completed_sync();
        job.persist_if_due(&path, true);
        assert!(!stored_catch_up(&path));

        let (job, start) = JobProgress::start(catch_up(1_000.0, 0.6), 400.0, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert!(job.from_completed_sync);
        // More new work than was finished: a new job, after one that never
        // completed.
        let (job, start) = JobProgress::start(catch_up(1_000.0, 0.6), 1_500.0, 1.0);
        assert_eq!(start, JobStart::Replaced);
        assert!(!job.from_completed_sync);
    }

    #[test]
    fn a_finished_job_has_no_remaining_share_to_stretch() {
        // A finished job with new work starts over; start() must not divide
        // by zero. Without new work it stays finished.
        let (job, start) = JobProgress::start(stored(1_000.0, 1.0), 0.5, 1.0);
        assert_eq!(start, JobStart::Replaced);
        assert_ne!(job.id(), "abc");
        assert_eq!(job.fraction(), 0.0);

        let (job, start) = JobProgress::start(stored(1_000.0, 1.0), 0.0, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert_eq!(job.fraction(), 1.0);
    }

    #[test]
    fn an_empty_job_is_complete() {
        let job = new_job(0.0);
        assert_eq!(job.fraction(), 1.0);
        assert_eq!(job.fraction_after(10.0), 1.0);
    }

    #[test]
    fn reference_batch_work_counts_empty_blocks_and_one_batch() {
        let model = model_without_outputs(2_000);
        assert!((model.reference_batch_work() - model.range_work(100_000, 102_000)).abs() < 1e-12);
    }

    #[test]
    fn progress_job_round_trips_and_clears() {
        let (_dir, path) = temp_db();
        let path = path.as_str();
        assert_eq!(read_progress_job(path).unwrap(), None);

        for (closed, from_completed_sync) in [(false, false), (true, false), (false, true)] {
            let job = StoredProgressJob {
                id: "0123456789abcdef".into(),
                total_work: 1234.5,
                fraction: 0.42,
                closed,
                from_completed_sync,
                current_work_model: true,
            };
            write_progress_job(path, &job).unwrap();
            assert_eq!(read_progress_job(path).unwrap(), Some(job));
        }

        let mut conn = rusqlite::Connection::open(path).unwrap();
        let tx = conn.transaction().unwrap();
        clear_progress_job(&tx).unwrap();
        tx.commit().unwrap();
        assert_eq!(read_progress_job(path).unwrap(), None);
        let catch_up_keys: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM ext_vizor_sync_meta WHERE key LIKE 'progress_job_%'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(catch_up_keys, 0);

        // A job saved before the catch-up key existed reads as not one.
        let job = StoredProgressJob {
            from_completed_sync: true,
            ..stored(10.0, 0.5)
        };
        write_progress_job(path, &job).unwrap();
        conn.execute(
            "DELETE FROM ext_vizor_sync_meta WHERE key = ?1",
            params![PROGRESS_JOB_FROM_COMPLETED_SYNC_KEY],
        )
        .unwrap();
        assert_eq!(
            read_progress_job(path).unwrap(),
            Some(StoredProgressJob {
                from_completed_sync: false,
                ..job
            })
        );

        // A job saved by a build that counted work differently, or before the
        // work model key existed, reads as measured in other units.
        let job = stored(10.0, 0.5);
        write_progress_job(path, &job).unwrap();
        conn.execute(
            "UPDATE ext_vizor_sync_meta SET value = 'older' WHERE key = ?1",
            params![PROGRESS_JOB_WORK_MODEL_KEY],
        )
        .unwrap();
        let other_units = Some(StoredProgressJob {
            current_work_model: false,
            ..job.clone()
        });
        assert_eq!(read_progress_job(path).unwrap(), other_units);
        conn.execute(
            "DELETE FROM ext_vizor_sync_meta WHERE key = ?1",
            params![PROGRESS_JOB_WORK_MODEL_KEY],
        )
        .unwrap();
        assert_eq!(read_progress_job(path).unwrap(), other_units);
    }

    #[test]
    fn the_work_model_names_the_compiled_table_and_lookback() {
        // An app update that appends checkpoints counts work differently.
        let newest = last_checkpoint_height();
        assert!(newest > 0);
        let fingerprint = work_model_fingerprint();
        assert!(fingerprint.starts_with(&format!("{WORK_MODEL_REVISION}/")));
        assert!(fingerprint.ends_with(&format!("/{EXTRAPOLATION_LOOKBACK_BLOCKS}/{newest}")));
    }

    #[test]
    fn a_job_measured_in_other_units_resumes_at_its_fraction() {
        let other_units = |total_work: f64, fraction: f64| StoredProgressJob {
            current_work_model: false,
            ..stored(total_work, fraction)
        };

        // Fewer units under the new model: read as scanned work, the stored
        // 4.7% would jump to a third.
        let (job, start) = JobProgress::start(other_units(145.86, 0.047), 97.5, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert_eq!(job.id(), "abc");
        assert!((job.fraction() - 0.047).abs() < 1e-9, "{}", job.fraction());
        let (same_units, _) = JobProgress::start(stored(145.86, 0.047), 97.5, 1.0);
        assert!(same_units.fraction() > 0.3);

        // More units than the job had finished: read as new work, the job
        // would start over from zero.
        let (job, start) = JobProgress::start(other_units(1_000.0, 0.1), 2_000.0, 1.0);
        assert_eq!(start, JobStart::Resumed);
        assert!((job.fraction() - 0.1).abs() < 1e-9, "{}", job.fraction());
        let (_, start) = JobProgress::start(stored(1_000.0, 0.1), 2_000.0, 1.0);
        assert_eq!(start, JobStart::Replaced);

        // A finished job still starts over when there is work to scan.
        let (_, start) = JobProgress::start(other_units(1_000.0, 1.0), 50.0, 1.0);
        assert_eq!(start, JobStart::Replaced);
    }

    #[test]
    fn claiming_keeps_the_stored_job_and_names_a_new_one_otherwise() {
        let (_dir, path) = temp_db();
        let claim_after = |completed: bool| {
            let mut conn = rusqlite::Connection::open(&path).unwrap();
            ensure_sync_meta_table(&conn).unwrap();
            let tx = conn.transaction().unwrap();
            let job = claim_progress_job(&tx, completed).unwrap();
            tx.commit().unwrap();
            job
        };
        let claim = || claim_after(false);

        let first = claim();
        assert_eq!(first.total_work, 0.0);
        assert_eq!(first.id.len(), 16);
        // An attempt that fails before measuring keeps the id for the retry.
        assert_eq!(claim(), first);
        assert_eq!(read_progress_job(&path).unwrap(), Some(first.clone()));

        let measured = StoredProgressJob {
            id: first.id.clone(),
            total_work: 500.0,
            fraction: 0.25,
            closed: false,
            from_completed_sync: false,
            current_work_model: true,
        };
        write_progress_job(&path, &measured).unwrap();
        assert_eq!(claim(), measured);

        // The scan finished but the attempt stopped before completing: the
        // next attempt's preparation keeps the job; measuring replaces it.
        let finished = StoredProgressJob {
            fraction: 1.0,
            ..measured
        };
        write_progress_job(&path, &finished).unwrap();
        assert_eq!(claim(), finished);

        let mut conn = rusqlite::Connection::open(&path).unwrap();
        let tx = conn.transaction().unwrap();
        clear_progress_job(&tx).unwrap();
        tx.commit().unwrap();
        assert_ne!(claim().id, first.id);

        // After a completed sync the new job is a catch-up, and stays one
        // for the attempts that resume it.
        let mut conn = rusqlite::Connection::open(&path).unwrap();
        let tx = conn.transaction().unwrap();
        clear_progress_job(&tx).unwrap();
        tx.commit().unwrap();
        let catch_up = claim_after(true);
        assert!(catch_up.from_completed_sync);
        assert_eq!(claim_after(false), catch_up);
    }

    #[test]
    fn an_attempt_saves_open_and_closes_where_it_stopped() {
        let (_dir, path) = temp_db();
        let mut job = new_job(1_000.0);
        job.persist_if_due(&path, true);
        job.observe_after_batch(100.0, 900.0);
        job.persist_if_due(&path, true);
        let saved = read_progress_job(&path).unwrap().unwrap();
        assert!(!saved.closed);
        assert!((saved.fraction - 0.1).abs() < 1e-12);

        // A batch after the last periodic save is in the closing save.
        job.observe_after_batch(100.0, 800.0);
        let id = job.id().to_string();
        drop(job);
        let saved = read_progress_job(&path).unwrap().unwrap();
        assert!(saved.closed);
        assert_eq!(saved.id, id);
        assert!((saved.fraction - 0.2).abs() < 1e-12);
    }

    #[test]
    fn a_completed_attempt_does_not_store_its_job_again() {
        let (_dir, path) = temp_db();
        let mut job = new_job(1_000.0);
        job.persist_if_due(&path, true);
        job.observe_after_batch(1_000.0, 0.0);
        let mut conn = rusqlite::Connection::open(&path).unwrap();
        let tx = conn.transaction().unwrap();
        clear_progress_job(&tx).unwrap();
        tx.commit().unwrap();
        job.complete();
        drop(job);
        assert_eq!(read_progress_job(&path).unwrap(), None);
    }

    #[test]
    fn closing_does_not_recreate_a_removed_wallet_db() {
        let (dir, path) = temp_db();
        let mut job = new_job(1_000.0);
        job.persist_if_due(&path, true);
        std::fs::remove_file(&path).unwrap();
        drop(job);
        assert!(!std::path::Path::new(&path).exists());
        drop(dir);
    }

    #[test]
    fn a_job_from_another_policy_version_is_ignored() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        write_progress_job(path, &stored(10.0, 0.5)).unwrap();
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute(
            "UPDATE ext_vizor_sync_meta SET value = '0' WHERE key = ?1",
            params![PROGRESS_JOB_POLICY_VERSION_KEY],
        )
        .unwrap();
        assert_eq!(read_progress_job(path).unwrap(), None);
    }
}
