//! Mainnet birthday estimates from sparse block-time anchors.
//!
//! These conversions deliberately do not verify a wallet-derived height with
//! lightwalletd. Date-based imports retain their 15-day safety margin in Dart.
//! Keep Blossom as an anchor: it changed the target block interval. Before a
//! release, verify recent-date errors and add or refresh a deep mainnet anchor
//! when needed; a dense block-time table is not required.

use super::network::WalletNetwork;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct BirthdayAnchor {
    pub(crate) height: u64,
    pub(crate) time: u32,
}

pub(crate) const MAINNET_BIRTHDAY_ANCHORS: [BirthdayAnchor; 9] = [
    BirthdayAnchor {
        height: 419_200,
        time: 1_540_779_337,
    },
    BirthdayAnchor {
        height: 653_600,
        time: 1_576_101_005,
    },
    BirthdayAnchor {
        height: 1_000_000,
        time: 1_602_206_541,
    },
    BirthdayAnchor {
        height: 1_500_000,
        time: 1_639_913_234,
    },
    BirthdayAnchor {
        height: 2_000_000,
        time: 1_677_602_242,
    },
    BirthdayAnchor {
        height: 2_500_000,
        time: 1_715_296_781,
    },
    BirthdayAnchor {
        height: 3_000_000,
        time: 1_752_983_473,
    },
    BirthdayAnchor {
        height: 3_450_000,
        time: 1_786_894_060,
    },
    // Verified 2026-10-01 against us.zec.stardust.rest and zec.rocks;
    // both reported tip 3,502,435 and this block's hash
    // 0000000000a8af9f2280d24f1ddddbf4ceeb6467ff77066d43a18d140a881f9a.
    BirthdayAnchor {
        height: 3_501_000,
        time: 1_790_738_270,
    },
];

pub(crate) const SAPLING_ACTIVATION: BirthdayAnchor = MAINNET_BIRTHDAY_ANCHORS[0];
const TARGET_SPACING_SECONDS: u64 = 75;

pub(crate) fn uses_mainnet_anchors(network: WalletNetwork) -> bool {
    network == WalletNetwork::Main && !cfg!(ironwood_masquerade)
}

pub(crate) fn validate_mainnet_tip(tip: BirthdayAnchor) -> Result<BirthdayAnchor, String> {
    if tip.height < SAPLING_ACTIVATION.height || tip.time < SAPLING_ACTIVATION.time {
        return Err("Mainnet tip predates Sapling activation".to_string());
    }
    if tip.height > u64::from(u32::MAX) {
        return Err("Mainnet tip height exceeds the supported range".to_string());
    }
    for anchor in MAINNET_BIRTHDAY_ANCHORS {
        if tip.height == anchor.height && tip.time != anchor.time {
            return Err("Mainnet tip time disagrees with the known block".to_string());
        }
        if tip.height > anchor.height && tip.time <= anchor.time {
            return Err("Mainnet tip time does not follow the previous anchor".to_string());
        }
    }
    Ok(tip)
}

/// Same interpolation and nearest-height rounding as the old mainnet fast
/// path, without its GetBlock verification, correction probes, or binary search.
pub(crate) fn mainnet_height_for_time(target: i64, tip: BirthdayAnchor) -> Result<u64, String> {
    validate_mainnet_tip(tip)?;
    if target <= i64::from(SAPLING_ACTIVATION.time) {
        return Ok(SAPLING_ACTIVATION.height);
    }
    if target >= i64::from(tip.time) {
        return Ok(tip.height);
    }
    let mut lower = SAPLING_ACTIVATION;
    for upper in MAINNET_BIRTHDAY_ANCHORS
        .iter()
        .copied()
        .skip(1)
        .take_while(|anchor| anchor.height < tip.height)
        .chain(std::iter::once(tip))
    {
        if target <= i64::from(upper.time) {
            let delta = divide_round_nearest(
                (i128::from(target) - i128::from(lower.time))
                    * i128::from(upper.height - lower.height),
                i128::from(upper.time - lower.time),
            );
            return Ok((i128::from(lower.height) + delta)
                .clamp(i128::from(lower.height), i128::from(upper.height))
                as u64);
        }
        lower = upper;
    }
    Err("No mainnet birthday interpolation segment".to_string())
}

/// Local estimate of a block's time. A later scanned block extends the final
/// segment; outside known segments use the post-Blossom target interval.
pub(crate) fn mainnet_time_for_height(height: u64, scanned: Option<BirthdayAnchor>) -> u32 {
    if height <= SAPLING_ACTIVATION.height {
        return SAPLING_ACTIVATION.time;
    }
    for pair in MAINNET_BIRTHDAY_ANCHORS.windows(2) {
        if height <= pair[1].height {
            return interpolate_time(pair[0], pair[1], height);
        }
    }
    let last = MAINNET_BIRTHDAY_ANCHORS[MAINNET_BIRTHDAY_ANCHORS.len() - 1];
    let upper = scanned.filter(|point| point.height > last.height && point.time > last.time);
    match upper {
        Some(upper) if height <= upper.height => interpolate_time(last, upper, height),
        Some(upper) => extrapolate_time(upper, height),
        None => extrapolate_time(last, height),
    }
}

fn interpolate_time(lower: BirthdayAnchor, upper: BirthdayAnchor, height: u64) -> u32 {
    let delta = divide_round_nearest(
        i128::from(height - lower.height) * i128::from(upper.time - lower.time),
        i128::from(upper.height - lower.height),
    );
    (i128::from(lower.time) + delta).clamp(i128::from(lower.time), i128::from(upper.time)) as u32
}

fn extrapolate_time(from: BirthdayAnchor, height: u64) -> u32 {
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

    fn tip() -> BirthdayAnchor {
        BirthdayAnchor {
            height: 3_502_435,
            time: 1_790_846_257,
        }
    }

    #[test]
    fn known_anchors_and_blossom_boundary_keep_their_heights_and_times() {
        for anchor in MAINNET_BIRTHDAY_ANCHORS {
            assert_eq!(
                mainnet_height_for_time(i64::from(anchor.time), tip()).unwrap(),
                anchor.height
            );
            assert_eq!(mainnet_time_for_height(anchor.height, None), anchor.time);
        }
        let blossom = MAINNET_BIRTHDAY_ANCHORS[1];
        assert_eq!(
            mainnet_time_for_height(blossom.height - 1, None),
            blossom.time - 151
        );
        assert_eq!(
            mainnet_time_for_height(blossom.height + 1, None),
            blossom.time + 75
        );
    }

    #[test]
    fn boundaries_and_historical_tips_do_not_use_future_anchors() {
        assert_eq!(
            mainnet_height_for_time(i64::MIN, tip()).unwrap(),
            SAPLING_ACTIVATION.height
        );
        assert_eq!(
            mainnet_height_for_time(i64::MAX, tip()).unwrap(),
            tip().height
        );
        assert_eq!(mainnet_time_for_height(0, None), SAPLING_ACTIVATION.time);
        let old_tip = BirthdayAnchor {
            height: 600_200,
            time: 1_568_053_650,
        };
        let target = i64::from(SAPLING_ACTIVATION.time)
            + i64::from(old_tip.time - SAPLING_ACTIVATION.time) / 2;
        assert_eq!(mainnet_height_for_time(target, old_tip).unwrap(), 509_700);
    }

    #[test]
    fn inconsistent_tips_are_errors_instead_of_triggering_network_search() {
        for invalid in [
            BirthdayAnchor {
                height: SAPLING_ACTIVATION.height - 1,
                time: SAPLING_ACTIVATION.time,
            },
            BirthdayAnchor {
                height: tip().height,
                time: 0,
            },
            BirthdayAnchor {
                height: 3_450_001,
                time: MAINNET_BIRTHDAY_ANCHORS[7].time,
            },
            BirthdayAnchor {
                height: 3_450_000,
                time: MAINNET_BIRTHDAY_ANCHORS[7].time + 1,
            },
            BirthdayAnchor {
                height: u64::MAX,
                time: tip().time,
            },
        ] {
            assert!(mainnet_height_for_time(1_677_602_242, invalid).is_err());
        }
    }

    #[test]
    fn newer_times_use_the_tip_and_scanned_block_as_endpoints() {
        let last = *MAINNET_BIRTHDAY_ANCHORS.last().unwrap();
        let upper = BirthdayAnchor {
            height: last.height + 10_000,
            time: last.time + 1_000_000,
        };
        assert_eq!(
            mainnet_height_for_time(i64::from(last.time + 500_000), upper).unwrap(),
            last.height + 5_000
        );
        assert_eq!(
            mainnet_time_for_height(last.height + 5_000, Some(upper)),
            last.time + 500_000
        );
        assert_eq!(
            mainnet_time_for_height(last.height + 5_000, None),
            last.time + 375_000
        );
        assert_eq!(
            mainnet_time_for_height(upper.height + 10, Some(upper)),
            upper.time + 750
        );
        assert_eq!(mainnet_time_for_height(u64::MAX, None), u32::MAX);
        assert_eq!(
            mainnet_time_for_height(last.height + 10, Some(SAPLING_ACTIVATION)),
            last.time + 750
        );
    }

    #[test]
    fn only_real_mainnet_uses_the_anchors() {
        assert_eq!(
            uses_mainnet_anchors(WalletNetwork::Main),
            !cfg!(ironwood_masquerade)
        );
        assert!(!uses_mainnet_anchors(WalletNetwork::Test));
        assert!(!uses_mainnet_anchors(WalletNetwork::Regtest));
    }

    #[test]
    fn independent_header_samples_stay_within_the_old_six_hour_tolerance() {
        // Header times sampled independently of the interpolation anchors.
        // Includes both sides of Blossom and the worst height-error sample
        // from the 3,080-point offline comparison (1,757,200 -> 1,757,270).
        let samples = [
            (420_200, 1_540_928_766),
            (600_200, 1_568_053_650),
            (653_200, 1_576_041_022),
            (654_200, 1_576_147_574),
            (800_200, 1_587_149_113),
            (1_250_200, 1_621_071_966),
            (1_757_200, 1_659_305_748),
            (2_250_200, 1_696_465_431),
            (2_750_200, 1_734_155_008),
            (3_250_200, 1_771_836_427),
            (3_450_200, 1_786_909_712),
            (3_498_200, 1_790_527_223),
            (3_502_435, 1_790_846_257),
        ];
        for (height, time) in samples {
            let estimate = mainnet_height_for_time(i64::from(time), tip()).unwrap();
            // Before Blossom use 150 seconds per block; after it, 75 seconds.
            let spacing = if height < 653_600 { 150 } else { 75 };
            assert!(
                estimate.abs_diff(height) * spacing < 6 * 60 * 60,
                "height {height}: estimated {estimate}"
            );
            for scanned in [None, Some(tip())] {
                let local_time = mainnet_time_for_height(height, scanned);
                assert!(
                    local_time.abs_diff(time) < 6 * 60 * 60,
                    "height {height}: time {local_time} vs {time}"
                );
            }
        }
    }
}
