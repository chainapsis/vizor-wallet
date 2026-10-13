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

use zcash_client_backend::data_api::scanning::ScanRange;

use super::{
    elapsed, is_pending_scan_range, BATCH_SIZE_SANDBLASTING, SANDBLASTING_END, SANDBLASTING_START,
};
use crate::wallet::db::{open_readonly_conn_with_timeout, SYNC_DB_BUSY_TIMEOUT};
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
}
