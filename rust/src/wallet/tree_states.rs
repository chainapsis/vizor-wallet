//! Mainnet note commitment tree states compiled into the binary.
//!
//! Scanning a new account starts with the tree state just below its first
//! block. Fetching it with `GetTreeState(birthday - 1)` told lightwalletd the
//! account's exact birthday, re-sent on every rescan. Restore birthdays are
//! instead rounded down to one past a checkpoint in this table
//! ([`privacy_birthday`]), and the sync engine reads that checkpoint's state
//! locally ([`mainnet_chain_state`]). lightwalletd then learns only the
//! 10,000-block bucket from the first `GetBlockRange` request.
//!
//! Birthdays past the last checkpoint stay exact. That keeps new wallets,
//! whose birthday is the chain tip, from scanning up to a bucket of extra
//! blocks; the cost is that a restore of a wallet younger than the table still
//! sends its exact birthday.
//!
//! Entry `i` of [`mainnet_data::CHECKPOINTS`] holds lightwalletd's
//! `GetTreeState` fields for block `START_HEIGHT + i * STEP`.
//! `scripts/update-mainnet-tree-states.py` appends entries; the weekly
//! mainnet-table workflow runs it.

mod mainnet_data;

use mainnet_data::{CHECKPOINTS, START_HEIGHT, STEP};
use zcash_client_backend::data_api::chain::ChainState;
use zcash_client_backend::proto::service::TreeState;
use zcash_protocol::consensus::{NetworkUpgrade, Parameters};

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

/// The birthday to store for an account whose requested birthday is
/// `birthday`, so that scanning starts right after a compiled checkpoint.
///
/// On real mainnet a birthday at or below the last checkpoint moves down to
/// one past the highest checkpoint below it, or to Sapling activation when no
/// checkpoint is below it. An earlier birthday only scans more blocks, and
/// never misses funds. Birthdays past the last checkpoint and all other
/// networks are unchanged.
pub(crate) fn privacy_birthday(network: WalletNetwork, birthday: u64) -> u64 {
    if !table_covers(network) {
        return birthday;
    }
    let Some(sapling_activation) = network
        .activation_height(NetworkUpgrade::Sapling)
        .map(|height| u64::from(u32::from(height)))
    else {
        return birthday;
    };
    if birthday <= sapling_activation || birthday > last_checkpoint_height() {
        return birthday;
    }
    let prior = birthday - 1;
    if prior < START_HEIGHT {
        return sapling_activation;
    }
    START_HEIGHT + (prior - START_HEIGHT) / STEP * STEP + 1
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAPLING_ACTIVATION: u64 = 419_200;
    const NU5_ACTIVATION: u64 = 1_687_104;
    const NU6_3_ACTIVATION: u64 = 3_428_143;

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

    #[cfg(not(ironwood_masquerade))]
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
            assert_eq!(privacy_birthday(network, 1_234_567), 1_234_567);
        }
    }

    #[cfg(ironwood_masquerade)]
    #[test]
    fn masquerade_builds_never_use_the_table() {
        assert!(mainnet_chain_state(WalletNetwork::Main, 1_000_000).is_none());
        assert_eq!(privacy_birthday(WalletNetwork::Main, 1_234_567), 1_234_567);
    }

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn privacy_birthday_starts_right_after_a_checkpoint() {
        let main = WalletNetwork::Main;
        // Mid-bucket rounds down.
        assert_eq!(privacy_birthday(main, 1_234_567), 1_230_001);
        // Already one past a checkpoint: unchanged.
        assert_eq!(privacy_birthday(main, 1_230_001), 1_230_001);
        // A checkpoint height itself belongs to the bucket below.
        assert_eq!(privacy_birthday(main, 1_230_000), 1_220_001);
        // Below the first checkpoint: Sapling activation, which scans from an
        // empty state without any request.
        assert_eq!(privacy_birthday(main, 420_000), SAPLING_ACTIVATION);
        assert_eq!(privacy_birthday(main, 419_201), SAPLING_ACTIVATION);
        assert_eq!(privacy_birthday(main, 420_001), 420_001);
        // At or before Sapling activation: unchanged.
        assert_eq!(
            privacy_birthday(main, SAPLING_ACTIVATION),
            SAPLING_ACTIVATION
        );
        assert_eq!(privacy_birthday(main, 1), 1);
        // Past the table: unchanged.
        let last = last_checkpoint_height();
        assert_eq!(privacy_birthday(main, last + 1), last + 1);
        assert_eq!(privacy_birthday(main, last + 5_000), last + 5_000);
        assert_eq!(privacy_birthday(main, last), last - STEP + 1);
    }

    #[cfg(not(ironwood_masquerade))]
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
            let rounded = privacy_birthday(main, birthday);
            assert!(rounded <= birthday);
            assert!(
                mainnet_chain_state(main, rounded - 1).is_some(),
                "no checkpoint below rounded birthday {rounded}"
            );
        }
    }
}
