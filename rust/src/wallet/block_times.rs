//! Mainnet block times compiled into the binary.
//!
//! Converting between a wallet birthday date and height used to send
//! `GetBlock` requests at heights derived from the user's wallet, which told
//! lightwalletd the wallet's birthday. This table answers both directions
//! locally. Entry `i` of [`mainnet_data::TIMES`] is the header time of block
//! `START_HEIGHT + i * STEP`. Linear interpolation inside one 1,000-block span
//! stays within a few hours of the true time, far inside the 15-day import
//! safety margin.
//!
//! `scripts/update-mainnet-block-times.py` appends entries; a weekly workflow
//! runs it. Past the last entry, callers pass a chain point that carries no
//! wallet-specific information (the lightwalletd tip, or the wallet's own
//! highest scanned block), and without one the functions extrapolate at the
//! post-Blossom target spacing.

mod mainnet_data;

use mainnet_data::{START_HEIGHT, STEP, TIMES};

use crate::wallet::network::WalletNetwork;

/// Mainnet target block spacing since Blossom.
const TARGET_SPACING_SECONDS: u64 = 75;

/// A block height and its header time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct BlockTimePoint {
    pub(crate) height: u64,
    pub(crate) time: u32,
}

/// Whether the compiled-in table describes `network`'s chain.
///
/// Only real mainnet qualifies. Ironwood masquerade builds run a private test
/// chain under the `main` name, so its heights and times are unrelated to the
/// table.
pub(crate) fn table_covers(network: WalletNetwork) -> bool {
    network == WalletNetwork::Main && !cfg!(ironwood_masquerade)
}

fn table_point(index: usize) -> BlockTimePoint {
    BlockTimePoint {
        height: START_HEIGHT + index as u64 * STEP,
        time: TIMES[index],
    }
}

fn last_table_point() -> BlockTimePoint {
    table_point(TIMES.len() - 1)
}

/// Checks the tip against the latest table entry at or below its height.
/// Older tip snapshots remain valid even after the table has been extended.
pub(crate) fn tip_agrees_with_table(tip: BlockTimePoint) -> bool {
    if tip.height < START_HEIGHT {
        return false;
    }
    let index = ((tip.height - START_HEIGHT) / STEP).min((TIMES.len() - 1) as u64) as usize;
    let previous = table_point(index);
    if tip.height == previous.height {
        tip.time == previous.time
    } else {
        tip.time > previous.time
    }
}

/// `upper` when it extends the table forward in both height and time.
fn usable_upper(upper: Option<BlockTimePoint>) -> Option<BlockTimePoint> {
    let last = last_table_point();
    upper.filter(|point| point.height > last.height && point.time > last.time)
}

/// Estimates the first mainnet height whose block time reaches
/// `target_epoch_seconds`.
///
/// Targets at or before Sapling activation return the activation height. With
/// a `tip`, the result never exceeds `tip.height`, and targets past the table
/// interpolate toward the tip. Without one they extrapolate at the target
/// spacing.
pub(crate) fn mainnet_height_for_time(
    target_epoch_seconds: i64,
    tip: Option<BlockTimePoint>,
) -> u64 {
    let first = table_point(0);
    if target_epoch_seconds <= i64::from(first.time) {
        return first.height;
    }
    if let Some(tip) = tip {
        if target_epoch_seconds >= i64::from(tip.time) {
            return tip.height.max(first.height);
        }
    }

    // First entry whose time reaches the target; index 0 is excluded above.
    let index = TIMES.partition_point(|&time| i64::from(time) < target_epoch_seconds);
    let estimate = if index < TIMES.len() {
        interpolate_height(
            table_point(index - 1),
            table_point(index),
            target_epoch_seconds,
        )
    } else {
        let last = last_table_point();
        match usable_upper(tip) {
            Some(upper) => interpolate_height(last, upper, target_epoch_seconds),
            None => {
                let elapsed =
                    u64::try_from(target_epoch_seconds - i64::from(last.time)).unwrap_or_default();
                last.height + elapsed / TARGET_SPACING_SECONDS
            }
        }
    };
    match tip {
        Some(tip) => estimate.min(tip.height.max(first.height)),
        None => estimate,
    }
}

/// Estimates the header time of mainnet block `height`.
///
/// Heights at or before Sapling activation return the activation time. Past
/// the table, `upper` (a known later block) anchors the estimate; without one
/// the estimate extrapolates at the target spacing.
pub(crate) fn mainnet_time_for_height(height: u64, upper: Option<BlockTimePoint>) -> u32 {
    let first = table_point(0);
    if height <= first.height {
        return first.time;
    }

    let index = usize::try_from((height - first.height) / STEP).unwrap_or(usize::MAX);
    if index < TIMES.len() - 1 {
        return interpolate_time(table_point(index), table_point(index + 1), height);
    }

    let last = last_table_point();
    match usable_upper(upper) {
        Some(upper) if height <= upper.height => interpolate_time(last, upper, height),
        Some(upper) => extrapolate_time(upper, height),
        None => extrapolate_time(last, height),
    }
}

fn interpolate_height(lower: BlockTimePoint, upper: BlockTimePoint, target: i64) -> u64 {
    let time_span = i128::from(upper.time) - i128::from(lower.time);
    let height_span = i128::from(upper.height) - i128::from(lower.height);
    if time_span <= 0 {
        return lower.height;
    }
    let delta = divide_round_nearest(
        (i128::from(target) - i128::from(lower.time)) * height_span,
        time_span,
    );
    (i128::from(lower.height) + delta).clamp(i128::from(lower.height), i128::from(upper.height))
        as u64
}

fn interpolate_time(lower: BlockTimePoint, upper: BlockTimePoint, height: u64) -> u32 {
    let time_span = i128::from(upper.time) - i128::from(lower.time);
    let height_span = i128::from(upper.height) - i128::from(lower.height);
    if height_span <= 0 {
        return lower.time;
    }
    let delta = divide_round_nearest(
        (i128::from(height) - i128::from(lower.height)) * time_span,
        height_span,
    );
    (i128::from(lower.time) + delta).clamp(i128::from(lower.time), i128::from(upper.time)) as u32
}

fn extrapolate_time(from: BlockTimePoint, height: u64) -> u32 {
    let elapsed = height
        .saturating_sub(from.height)
        .saturating_mul(TARGET_SPACING_SECONDS);
    u32::try_from(u64::from(from.time).saturating_add(elapsed)).unwrap_or(u32::MAX)
}

fn divide_round_nearest(numerator: i128, denominator: i128) -> i128 {
    let adjustment = denominator / 2;
    if numerator >= 0 {
        (numerator + adjustment) / denominator
    } else {
        (numerator - adjustment) / denominator
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAPLING_ACTIVATION: BlockTimePoint = BlockTimePoint {
        height: 419_200,
        time: 1_540_779_337,
    };

    // Exact header times of known mainnet blocks, independent of the table.
    // These were the interpolation anchors of the previous estimator.
    const KNOWN_BLOCKS: [BlockTimePoint; 8] = [
        SAPLING_ACTIVATION,
        BlockTimePoint {
            height: 653_600,
            time: 1_576_101_005,
        },
        BlockTimePoint {
            height: 1_000_000,
            time: 1_602_206_541,
        },
        BlockTimePoint {
            height: 1_500_000,
            time: 1_639_913_234,
        },
        BlockTimePoint {
            height: 2_000_000,
            time: 1_677_602_242,
        },
        BlockTimePoint {
            height: 2_500_000,
            time: 1_715_296_781,
        },
        BlockTimePoint {
            height: 3_000_000,
            time: 1_752_983_473,
        },
        BlockTimePoint {
            height: 3_450_000,
            time: 1_786_894_060,
        },
    ];

    // Six hours, the tolerance the previous estimator accepted after probing.
    const TOLERANCE_SECONDS: i64 = 6 * 60 * 60;

    fn tip_after_table() -> BlockTimePoint {
        let last = last_table_point();
        BlockTimePoint {
            height: last.height + 10_000,
            time: last.time + 10_000 * 75,
        }
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn table_covers_only_real_mainnet() {
        assert!(table_covers(WalletNetwork::Main));
        assert!(!table_covers(WalletNetwork::Test));
        assert!(!table_covers(WalletNetwork::Regtest));
    }

    #[cfg(ironwood_masquerade)]
    #[test]
    fn masquerade_builds_never_use_the_table() {
        for network in [
            WalletNetwork::Main,
            WalletNetwork::Test,
            WalletNetwork::Regtest,
        ] {
            assert!(!table_covers(network));
        }
    }

    #[test]
    fn table_starts_at_sapling_activation_and_never_goes_backwards() {
        assert_eq!(table_point(0), SAPLING_ACTIVATION);
        assert!(TIMES.windows(2).all(|pair| pair[0] <= pair[1]));
        assert!(last_table_point().height >= 3_450_000);
    }

    #[test]
    fn known_blocks_round_trip_within_tolerance() {
        for block in KNOWN_BLOCKS {
            let time = i64::from(mainnet_time_for_height(block.height, None));
            assert!(
                (time - i64::from(block.time)).abs() <= TOLERANCE_SECONDS,
                "time for {}: {time} vs {}",
                block.height,
                block.time
            );

            let height = mainnet_height_for_time(i64::from(block.time), None);
            let estimated_time = i64::from(mainnet_time_for_height(height, None));
            assert!(
                (estimated_time - i64::from(block.time)).abs() <= TOLERANCE_SECONDS,
                "height for {}: {height}",
                block.height
            );
        }
    }

    #[test]
    fn tip_validation_accepts_old_snapshots_and_rejects_inconsistent_times() {
        let old = table_point(TIMES.len() / 2);
        assert!(tip_agrees_with_table(old));
        assert!(tip_agrees_with_table(tip_after_table()));
        assert!(!tip_agrees_with_table(BlockTimePoint {
            time: old.time + 1,
            ..old
        }));
        assert!(!tip_agrees_with_table(BlockTimePoint {
            height: old.height + 1,
            ..old
        }));
    }

    #[test]
    fn table_points_are_exact() {
        for index in [0, 1, TIMES.len() / 2, TIMES.len() - 1] {
            let point = table_point(index);
            assert_eq!(mainnet_time_for_height(point.height, None), point.time);
        }
    }

    #[test]
    fn dates_before_sapling_clamp_to_activation() {
        assert_eq!(mainnet_height_for_time(0, None), SAPLING_ACTIVATION.height);
        assert_eq!(
            mainnet_height_for_time(i64::from(SAPLING_ACTIVATION.time), None),
            SAPLING_ACTIVATION.height
        );
        assert_eq!(mainnet_time_for_height(1, None), SAPLING_ACTIVATION.time);
    }

    #[test]
    fn heights_never_exceed_the_tip() {
        let tip = tip_after_table();
        assert_eq!(
            mainnet_height_for_time(i64::from(tip.time), Some(tip)),
            tip.height
        );
        assert_eq!(mainnet_height_for_time(i64::MAX, Some(tip)), tip.height);

        let stale_tip = table_point(TIMES.len() / 2);
        assert_eq!(
            mainnet_height_for_time(i64::from(last_table_point().time), Some(stale_tip)),
            stale_tip.height
        );
    }

    #[test]
    fn past_the_table_interpolates_toward_the_tip() {
        let last = last_table_point();
        let tip = BlockTimePoint {
            height: last.height + 10_000,
            // Slower than target spacing, so interpolation and extrapolation differ.
            time: last.time + 10_000 * 100,
        };
        let midpoint = i64::from(last.time) + 5_000 * 100;

        assert_eq!(
            mainnet_height_for_time(midpoint, Some(tip)),
            last.height + 5_000
        );
        assert_eq!(
            mainnet_height_for_time(midpoint, None),
            last.height + 5_000 * 100 / 75
        );
    }

    #[test]
    fn past_the_table_times_use_the_upper_point() {
        let last = last_table_point();
        let upper = BlockTimePoint {
            height: last.height + 10_000,
            time: last.time + 10_000 * 100,
        };

        assert_eq!(
            mainnet_time_for_height(last.height + 5_000, Some(upper)),
            last.time + 5_000 * 100
        );
        assert_eq!(
            mainnet_time_for_height(upper.height + 10, Some(upper)),
            upper.time + 10 * 75
        );
        assert_eq!(
            mainnet_time_for_height(last.height + 5_000, None),
            last.time + 5_000 * 75
        );
    }

    #[test]
    fn extreme_heights_saturate_instead_of_overflowing() {
        assert_eq!(mainnet_time_for_height(u64::MAX, None), u32::MAX);
        assert_eq!(
            mainnet_time_for_height(u64::MAX, Some(tip_after_table())),
            u32::MAX
        );
    }

    #[test]
    fn upper_points_inside_the_table_are_ignored() {
        let last = last_table_point();
        let inside = table_point(1);
        assert_eq!(
            mainnet_time_for_height(last.height + 100, Some(inside)),
            last.time + 100 * 75
        );
    }
}
