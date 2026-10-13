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
    elapsed, ensure_sync_meta_table, is_pending_scan_range, BATCH_SIZE_SANDBLASTING,
    SANDBLASTING_END, SANDBLASTING_START,
};
use crate::wallet::db::{
    open_readonly_conn_with_timeout, open_wallet_raw_conn_with_timeout, SYNC_DB_BUSY_TIMEOUT,
};
use crate::wallet::network::WalletNetwork;
use crate::wallet::tree_states::mainnet_tree_sizes;

// Relative scan cost of each unit, in seconds on a desktop mainnet benchmark.
// Only the ratios matter. Mobile uses the same ratios with its own batch size;
// they have not been measured on a phone.
const WORK_PER_BLOCK: f64 = 0.37e-3;
const WORK_PER_SAPLING_OUTPUT: f64 = 21e-6;
const WORK_PER_ORCHARD_ACTION: f64 = 40e-6;
const WORK_PER_BATCH: f64 = 0.25;

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
pub(super) const PROGRESS_JOB_KEYS: [&str; 4] = [
    PROGRESS_JOB_POLICY_VERSION_KEY,
    PROGRESS_JOB_ID_KEY,
    PROGRESS_JOB_TOTAL_KEY,
    PROGRESS_JOB_FRACTION_KEY,
];
// After a failed save, the next try waits this long instead of every batch.
const PROGRESS_JOB_RETRY_INTERVAL: Duration = Duration::from_secs(15);
// Past the last known point, outputs continue at the average rate over at
// least this many blocks, so a short final segment does not set the rate.
const EXTRAPOLATION_LOOKBACK_BLOCKS: u64 = 10_000;

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
    /// Batch size used to count planned batches. A fixed reference, so a
    /// foreground/background mode switch does not move the fraction.
    reference_batch_size: u32,
}

impl WorkModel {
    pub(super) fn load(
        db_data_path: &str,
        network: WalletNetwork,
        reference_batch_size: u32,
    ) -> Self {
        let mut points: [Vec<(u64, f64)>; 3] = Default::default();
        for &(height, sizes) in mainnet_tree_sizes(network) {
            for pool in 0..3 {
                // A checkpoint holds the tree size at the end of its block.
                points[pool].push((height + 1, sizes[pool] as f64));
            }
        }
        match read_subtree_end_heights(db_data_path) {
            Ok(subtrees) => {
                for (pool, ends) in subtrees.into_iter().enumerate() {
                    for (index, end_height) in ends {
                        points[pool].push((end_height + 1, (index + 1) as f64 * SUBTREE_LEAVES));
                    }
                }
            }
            Err(e) => log::warn!(
                "[{}] sync: subtree heights unavailable for progress estimate: {e}",
                elapsed(),
            ),
        }
        Self::from_points(points, reference_batch_size)
    }

    fn from_points(points: [Vec<(u64, f64)>; 3], reference_batch_size: u32) -> Self {
        let [sapling, orchard, ironwood] = points;
        Self {
            curves: [
                OutputCurve::from_points(sapling),
                OutputCurve::from_points(orchard),
                OutputCurve::from_points(ironwood),
            ],
            reference_batch_size: reference_batch_size.max(1),
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

    /// Batches the engine plans for `[start, end)`, counted fractionally so
    /// the count of a range equals the sum over any split of it.
    fn planned_batches(&self, start: u64, end: u64) -> f64 {
        let sand_start = u64::from(SANDBLASTING_START);
        let sand_end = u64::from(SANDBLASTING_END);
        let sand_blocks = end.min(sand_end).saturating_sub(start.max(sand_start));
        let other_blocks = (end - start) - sand_blocks;
        sand_blocks as f64 / f64::from(BATCH_SIZE_SANDBLASTING)
            + other_blocks as f64 / f64::from(self.reference_batch_size)
    }

    /// Estimated work left in the pending ranges, up to the chain tip.
    pub(super) fn pending_work(&self, ranges: &[ScanRange], tip_height: u64) -> f64 {
        let tip_end = tip_height.saturating_add(1);
        ranges
            .iter()
            .filter(|range| is_pending_scan_range(range))
            .map(|range| {
                let start = u64::from(u32::from(range.block_range().start));
                let end = u64::from(u32::from(range.block_range().end)).min(tip_end);
                self.range_work(start, end)
            })
            .sum()
    }
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
}

impl StoredProgressJob {
    /// A new job whose work is not measured yet.
    pub(super) fn unmeasured() -> Self {
        Self {
            id: new_job_id(),
            total_work: 0.0,
            fraction: 0.0,
        }
    }

    /// Scanned everything it measured; only an attempt that stopped before
    /// marking the sync complete leaves such a job behind.
    pub(super) fn is_finished(&self) -> bool {
        self.total_work > 0.0 && self.fraction >= 1.0
    }
}

pub(super) fn read_progress_job(db_data_path: &str) -> Result<Option<StoredProgressJob>, String> {
    let conn = open_readonly_conn_with_timeout(db_data_path, Some(SYNC_DB_BUSY_TIMEOUT))?;
    read_job(&conn)
}

/// Returns the unfinished job, or claims a new unmeasured one, inside the
/// transaction that marks a sync started. Every event of the attempt then
/// names the job, and an attempt that fails before measuring keeps the id.
/// A finished job is not resumed: the next catch-up is a new job from zero,
/// as after a completed sync.
pub(super) fn claim_progress_job(
    tx: &rusqlite::Transaction<'_>,
) -> Result<StoredProgressJob, String> {
    if let Some(job) = read_job(tx)?.filter(|job| !job.is_finished()) {
        return Ok(job);
    }
    let job = StoredProgressJob::unmeasured();
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
            }))
        }
        _ => Ok(None),
    }
}

fn write_progress_job(db_data_path: &str, job: &StoredProgressJob) -> Result<(), String> {
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
#[derive(Debug, Clone)]
pub(super) struct JobProgress {
    id: String,
    total: f64,
    remaining: f64,
    retry_after: Option<Instant>,
}

impl JobProgress {
    /// Continues `stored` with `pending` work measured for this attempt.
    ///
    /// Work that appeared or went away since the stored fraction (blocks mined
    /// while the app was closed, a rewind, a deleted account) keeps that
    /// fraction and rescales the rest, so the display neither drops nor jumps.
    /// Growth beyond what the job had finished, and at least
    /// `min_replace_growth`, starts a new job.
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
        } = stored;
        let (id, total, start) = if stored_total <= 0.0 {
            // Claimed when the attempt began; this is its first measurement.
            (id, pending, JobStart::New)
        } else {
            let done = fraction * stored_total;
            let expected = stored_total - done;
            let growth = pending - expected;
            let eps = 1e-9 * stored_total.max(1.0);
            if growth.abs() <= eps {
                (id, stored_total, JobStart::Resumed)
            } else if growth > 0.0 && (expected <= eps || growth > done.max(min_replace_growth)) {
                // Claiming already starts over after a finished job; nothing
                // is left to stretch over here either.
                (new_job_id(), pending, JobStart::Replaced)
            } else {
                (id, pending / (1.0 - fraction), JobStart::Resumed)
            }
        };
        let job = Self {
            id,
            total,
            remaining: pending,
            retry_after: None,
        };
        (job, start)
    }

    pub(super) fn id(&self) -> &str {
        &self.id
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

    /// Stores the job when it has work. The engine saves it after every
    /// batch, so the stored fraction lags the scan by at most one batch and a
    /// resumed attempt can read less pending work as work that went away, not
    /// as scanning it never recorded. Failure only costs resume accuracy, so it
    /// is logged and the next try waits.
    pub(super) fn persist(&mut self, db_data_path: &str) {
        if self.total <= 0.0 || self.retry_after.is_some_and(|at| Instant::now() < at) {
            return;
        }
        let stored = StoredProgressJob {
            id: self.id.clone(),
            total_work: self.total,
            fraction: self.fraction(),
        };
        match crate::wallet::db::with_wallet_db_write_lock("sync_engine.progress_job", || {
            write_progress_job(db_data_path, &stored)
        }) {
            Ok(()) => self.retry_after = None,
            Err(e) => {
                self.retry_after = Some(Instant::now() + PROGRESS_JOB_RETRY_INTERVAL);
                log::warn!("[{}] sync: progress job not saved: {e}", elapsed());
            }
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
        WorkModel::from_points(Default::default(), reference_batch_size)
    }

    fn new_job(pending: f64) -> JobProgress {
        let (job, start) = JobProgress::start(StoredProgressJob::unmeasured(), pending, 1.0);
        assert_eq!(start, JobStart::New);
        job
    }

    fn stored(total_work: f64, fraction: f64) -> StoredProgressJob {
        StoredProgressJob {
            id: "abc".into(),
            total_work,
            fraction,
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
        let model = WorkModel::from_points(points, 2_000);
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
        let model = WorkModel::load(&path, WalletNetwork::Test, 2_000);
        // Subtree i holds leaves up to (i + 1) * 2^16 once its end block is in.
        assert_eq!(
            model.curves[0].points,
            vec![(1_001, 65_536.0), (2_001, 131_072.0)]
        );
        assert_eq!(model.curves[1].points, vec![(5_001, 65_536.0)]);
        assert!(model.curves[2].points.is_empty());
    }

    #[test]
    fn planned_batches_follow_the_sandblasting_window() {
        let model = model_without_outputs(2_000);
        // The full-sync historic range: 646 + 3,400 + 670 batches.
        let pre = model.planned_batches(419_200, 1_710_000);
        let sand = model.planned_batches(1_710_000, 2_050_000);
        let post = model.planned_batches(2_050_000, 3_390_000);
        assert!((pre - 645.4).abs() < 1e-9);
        assert!((sand - 3_400.0).abs() < 1e-9);
        assert!((post - 670.0).abs() < 1e-9);
        assert!((model.planned_batches(419_200, 3_390_000) - (pre + sand + post)).abs() < 1e-6);
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

        // The job is saved after every batch, so less work than stored went
        // away unscanned (a deleted account): the fraction stays.
        let (job, _) = JobProgress::start(stored(1_000.0, 0.6), 300.0, 1.0);
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
        // The account was deleted while the sync was paused at 20% of 1,000.
        let (mut job, start) = JobProgress::start(stored(1_000.0, 0.2), 40.0, 1.0);
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
    fn a_finished_job_has_no_remaining_share_to_stretch() {
        // Claiming replaces such a job first; start() must not divide by zero.
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

        let job = StoredProgressJob {
            id: "0123456789abcdef".into(),
            total_work: 1234.5,
            fraction: 0.42,
        };
        write_progress_job(path, &job).unwrap();
        assert_eq!(read_progress_job(path).unwrap(), Some(job));

        let mut conn = rusqlite::Connection::open(path).unwrap();
        let tx = conn.transaction().unwrap();
        clear_progress_job(&tx).unwrap();
        tx.commit().unwrap();
        assert_eq!(read_progress_job(path).unwrap(), None);
    }

    #[test]
    fn claiming_keeps_an_unfinished_job_and_names_a_new_one_otherwise() {
        let (_dir, path) = temp_db();
        let claim = || {
            let mut conn = rusqlite::Connection::open(&path).unwrap();
            ensure_sync_meta_table(&conn).unwrap();
            let tx = conn.transaction().unwrap();
            let job = claim_progress_job(&tx).unwrap();
            tx.commit().unwrap();
            job
        };

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
        };
        write_progress_job(&path, &measured).unwrap();
        assert_eq!(claim(), measured);

        // The scan finished but the attempt stopped before completing: the
        // next catch-up is a new job.
        let finished = StoredProgressJob {
            fraction: 1.0,
            ..measured
        };
        write_progress_job(&path, &finished).unwrap();
        let after_finished = claim();
        assert_ne!(after_finished.id, first.id);
        assert_eq!(after_finished.total_work, 0.0);

        let mut conn = rusqlite::Connection::open(&path).unwrap();
        let tx = conn.transaction().unwrap();
        clear_progress_job(&tx).unwrap();
        tx.commit().unwrap();
        assert_ne!(claim().id, after_finished.id);
    }

    #[test]
    fn a_job_from_another_policy_version_is_ignored() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("wallet.db");
        let path = path.to_str().unwrap();
        write_progress_job(
            path,
            &StoredProgressJob {
                id: "abc".into(),
                total_work: 10.0,
                fraction: 0.5,
            },
        )
        .unwrap();
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute(
            "UPDATE ext_vizor_sync_meta SET value = '0' WHERE key = ?1",
            params![PROGRESS_JOB_POLICY_VERSION_KEY],
        )
        .unwrap();
        assert_eq!(read_progress_job(path).unwrap(), None);
    }
}
