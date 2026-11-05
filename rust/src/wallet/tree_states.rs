//! Mainnet note commitment tree states compiled into the binary.
//!
//! Scanning a new account starts with the tree state just below its first
//! block. Fetching it with `GetTreeState(birthday - 1)` told lightwalletd the
//! account's exact birthday, re-sent on every rescan. Restored birthdays are
//! instead rounded down to one past a point on a fixed height grid
//! ([`restore_birthday`]), so lightwalletd learns only the bucket. The grid is
//! every 10,000 blocks before NU7 and every 30,000 from it, about 8.7 days in
//! both eras. When the grid point is a checkpoint in this table, the sync
//! engine reads its state locally ([`mainnet_chain_state`]) and sends no
//! `GetTreeState` at all; a restore newer than the table fetches the grid
//! point's state, which reveals the same bucket the first `GetBlockRange`
//! already does.
//!
//! Newly created accounts keep their exact birthday (the chain tip), which
//! reveals only that a wallet was created now; rounding would scan up to a
//! bucket of extra blocks for nothing. Gift Card and payment-link claims keep
//! the exact height from the shared link, so claims stay fast.
//!
//! Entry `i` of [`mainnet_data::CHECKPOINTS`] holds lightwalletd's
//! `GetTreeState` fields for block `START_HEIGHT + i * STEP`.
//! `scripts/update-mainnet-tree-states.py` appends entries; the weekly
//! mainnet-table workflow runs it.

mod mainnet_data;

use mainnet_data::{CHECKPOINTS, START_HEIGHT, STEP};
use zcash_client_backend::data_api::chain::ChainState;
use zcash_client_backend::proto::service::TreeState;
use zcash_protocol::consensus::{NetworkUpgrade, Parameters, NU7_POW_TARGET_SPACING_RATIO};

use crate::wallet::block_times::table_covers;
use crate::wallet::network::WalletNetwork;

/// lightwalletd `GetTreeState` fields for one checkpoint, as hex strings.
pub(super) struct Checkpoint {
    pub(super) hash: &'static str,
    pub(super) sapling: &'static str,
    pub(super) orchard: &'static str,
    pub(super) ironwood: &'static str,
}

fn checkpoint_height(index: usize) -> u64 {
    START_HEIGHT + index as u64 * STEP
}

#[cfg(test)]
fn last_checkpoint_height() -> u64 {
    checkpoint_height(CHECKPOINTS.len() - 1)
}

fn checkpoint_index(height: u64) -> Option<usize> {
    let offset = height.checked_sub(START_HEIGHT)?;
    if offset % STEP != 0 {
        return None;
    }
    let index = usize::try_from(offset / STEP).ok()?;
    (index < CHECKPOINTS.len()).then_some(index)
}

fn parse_checkpoint(index: usize) -> std::io::Result<ChainState> {
    let checkpoint = &CHECKPOINTS[index];
    TreeState {
        network: "main".to_string(),
        height: checkpoint_height(index),
        hash: checkpoint.hash.to_string(),
        sapling_tree: checkpoint.sapling.to_string(),
        orchard_tree: checkpoint.orchard.to_string(),
        ironwood_tree: checkpoint.ironwood.to_string(),
        ..Default::default()
    }
    .to_chain_state()
}

/// The compiled chain state at the end of block `height`.
///
/// `None` unless `network` is real mainnet and `height` is exactly a
/// checkpoint. A checkpoint that fails to parse also returns `None`, so the
/// caller fetches the state from lightwalletd instead.
pub(crate) fn mainnet_chain_state(network: WalletNetwork, height: u64) -> Option<ChainState> {
    if !table_covers(network) {
        return None;
    }
    let index = checkpoint_index(height)?;
    match parse_checkpoint(index) {
        Ok(state) => Some(state),
        Err(error) => {
            log::error!("tree_states: compiled checkpoint {height} does not parse: {error}");
            None
        }
    }
}

/// The birthday to store for a restored account whose requested birthday is
/// `birthday`, so that scanning starts right after a grid point.
///
/// On real mainnet the birthday moves down to one past the highest grid point
/// below it, or to Sapling activation when no grid point is below it. An
/// earlier birthday only scans more blocks, and never misses funds. Birthdays
/// at or before Sapling activation and all other networks are unchanged.
pub(crate) fn restore_birthday(network: WalletNetwork, birthday: u64) -> u64 {
    if !table_covers(network) {
        return birthday;
    }
    let activation = |upgrade| {
        network
            .activation_height(upgrade)
            .map(|height| u64::from(u32::from(height)))
    };
    let Some(sapling_activation) = activation(NetworkUpgrade::Sapling) else {
        return birthday;
    };
    if birthday <= sapling_activation {
        return birthday;
    }
    let prior = birthday - 1;
    if prior < START_HEIGHT {
        return sapling_activation;
    }
    grid_point_at_or_below(prior, activation(NetworkUpgrade::Nu7)) + 1
}

/// The highest grid point at or below `height`, where `height >= START_HEIGHT`.
///
/// Grid points are every `STEP` blocks from `START_HEIGHT` before NU7, and
/// every `STEP` times the NU7 spacing ratio from it, so buckets keep their
/// duration and every grid point is a checkpoint height. The bucket that
/// contains the activation starts at the last grid point before it. A height
/// grid rather than a calendar keeps the buckets identical across app versions.
fn grid_point_at_or_below(height: u64, nu7: Option<u64>) -> u64 {
    let step_at = |height| match nu7 {
        Some(activation) if height >= activation => STEP * u64::from(NU7_POW_TARGET_SPACING_RATIO),
        _ => STEP,
    };
    let round_down = |height: u64| height - (height - START_HEIGHT) % step_at(height);
    let point = round_down(height);
    match nu7 {
        Some(activation) if point < activation && activation <= height => {
            round_down(activation - 1)
        }
        _ => point,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAPLING_ACTIVATION: u64 = 419_200;
    const NU5_ACTIVATION: u64 = 1_687_104;
    const NU6_3_ACTIVATION: u64 = 3_428_143;
    const NU7_ACTIVATION: u64 = 3_543_405;

    #[test]
    fn every_checkpoint_parses_at_its_height() {
        let mut previous = (0, 0, 0);
        for index in 0..CHECKPOINTS.len() {
            let height = checkpoint_height(index);
            let state = parse_checkpoint(index)
                .unwrap_or_else(|error| panic!("checkpoint {height} does not parse: {error}"));
            assert_eq!(u64::from(u32::from(state.block_height())), height);

            let sizes = (
                state.final_sapling_tree().tree_size(),
                state.final_orchard_tree().tree_size(),
                state.final_ironwood_tree().tree_size(),
            );
            assert!(sizes.0 > 0, "empty Sapling tree at {height}");
            if height < NU5_ACTIVATION {
                assert_eq!(sizes.1, 0, "Orchard tree before NU5 at {height}");
            }
            if height < NU6_3_ACTIVATION {
                assert_eq!(sizes.2, 0, "Ironwood tree before NU6.3 at {height}");
            }
            assert!(
                sizes.0 >= previous.0 && sizes.1 >= previous.1 && sizes.2 >= previous.2,
                "a tree shrinks at {height}"
            );
            previous = sizes;
        }
        assert!(last_checkpoint_height() >= 3_490_000);
    }

    #[test]
    fn mainnet_chain_state_serves_only_exact_checkpoints() {
        let state = mainnet_chain_state(WalletNetwork::Main, 1_000_000).unwrap();
        assert_eq!(u32::from(state.block_height()), 1_000_000);
        assert!(mainnet_chain_state(WalletNetwork::Main, 1_000_001).is_none());
        assert!(mainnet_chain_state(WalletNetwork::Main, START_HEIGHT - STEP).is_none());
        assert!(
            mainnet_chain_state(WalletNetwork::Main, last_checkpoint_height() + STEP).is_none()
        );
    }

    #[test]
    fn other_networks_never_use_the_table() {
        for network in [WalletNetwork::Test, WalletNetwork::Regtest] {
            assert!(mainnet_chain_state(network, 1_000_000).is_none());
            assert_eq!(restore_birthday(network, 1_234_567), 1_234_567);
        }
    }

    #[test]
    fn restore_birthday_starts_right_after_a_grid_point() {
        let main = WalletNetwork::Main;
        // Mid-bucket rounds down.
        assert_eq!(restore_birthday(main, 1_234_567), 1_230_001);
        // Already one past a checkpoint: unchanged.
        assert_eq!(restore_birthday(main, 1_230_001), 1_230_001);
        // A checkpoint height itself belongs to the bucket below.
        assert_eq!(restore_birthday(main, 1_230_000), 1_220_001);
        // Below the first checkpoint: Sapling activation, which scans from an
        // empty state without any request.
        assert_eq!(restore_birthday(main, 420_000), SAPLING_ACTIVATION);
        assert_eq!(restore_birthday(main, 419_201), SAPLING_ACTIVATION);
        assert_eq!(restore_birthday(main, 420_001), 420_001);
        // At or before Sapling activation: unchanged.
        assert_eq!(
            restore_birthday(main, SAPLING_ACTIVATION),
            SAPLING_ACTIVATION
        );
        assert_eq!(restore_birthday(main, 1), 1);
        // Past the table: still on the grid, whose point's state is then
        // fetched from lightwalletd and reveals only the bucket.
        assert_eq!(restore_birthday(main, 9_000_123), 9_000_001);
        assert!(mainnet_chain_state(main, 9_000_000).is_none());
    }

    #[test]
    fn restore_birthday_grid_widens_at_nu7() {
        let main = WalletNetwork::Main;
        assert_eq!(
            main.activation_height(NetworkUpgrade::Nu7)
                .map(|height| u64::from(u32::from(height))),
            Some(NU7_ACTIVATION)
        );
        // Before NU7: every 10,000 blocks.
        assert_eq!(restore_birthday(main, 3_539_999), 3_530_001);
        assert_eq!(restore_birthday(main, 3_540_000), 3_530_001);
        // The bucket containing the activation starts at the last grid point
        // before it and ends at the first 30,000-block point after it.
        for birthday in [
            3_540_001,
            NU7_ACTIVATION - 1,
            NU7_ACTIVATION,
            NU7_ACTIVATION + 1,
            3_560_001,
            3_570_000,
        ] {
            assert_eq!(restore_birthday(main, birthday), 3_540_001, "{birthday}");
        }
        // From NU7: every 30,000 blocks.
        assert_eq!(restore_birthday(main, 3_570_001), 3_570_001);
        assert_eq!(restore_birthday(main, 3_600_000), 3_570_001);
        assert_eq!(restore_birthday(main, 3_600_001), 3_600_001);
    }

    #[test]
    fn grid_points_are_checkpoint_heights_and_keep_their_spacing() {
        let wide = STEP * u64::from(NU7_POW_TARGET_SPACING_RATIO);
        for activation in [NU7_ACTIVATION, 3_540_000, 3_540_001, START_HEIGHT + 1] {
            let mut previous = START_HEIGHT;
            for height in (START_HEIGHT..activation + 3 * wide).step_by(7) {
                let point = grid_point_at_or_below(height, Some(activation));
                assert!(
                    previous <= point && point <= height,
                    "{activation} {height}"
                );
                assert_eq!((point - START_HEIGHT) % STEP, 0, "{activation} {height}");
                let step = if point >= activation { wide } else { STEP };
                assert_eq!((point - START_HEIGHT) % step, 0, "{activation} {height}");
                if height < activation {
                    assert!(height - point < STEP, "{activation} {height}");
                } else if height >= activation + wide {
                    assert!(height - point < wide, "{activation} {height}");
                }
                previous = point;
            }
        }
        assert_eq!(grid_point_at_or_below(9_000_123, None), 9_000_000);
        assert_eq!(grid_point_at_or_below(3_569_999, None), 3_560_000);
    }

    #[test]
    fn every_rounded_birthday_has_a_local_start_state() {
        let main = WalletNetwork::Main;
        for birthday in [
            420_001,
            777_777,
            1_687_105,
            3_428_143,
            last_checkpoint_height(),
        ] {
            let rounded = restore_birthday(main, birthday);
            assert!(rounded <= birthday);
            assert!(
                mainnet_chain_state(main, rounded - 1).is_some(),
                "no checkpoint below rounded birthday {rounded}"
            );
        }
    }
}
