//! The blocks around a network upgrade. A transaction commits to the
//! consensus branch at its target height, so one signed before an upgrade can
//! only be mined before it activates.

use zcash_protocol::consensus::{BlockHeight, BranchId, Parameters};

/// Blocks before an upgrade during which signed migration transactions are
/// held and new migrations refused. One sent closer could miss the last
/// old-branch block, and the wallet would keep its input spent until the
/// ZIP 318 expiry.
pub(crate) const BROADCAST_HOLD_BLOCKS: u32 = 10;

/// Nodes reject a transaction that expires within this many blocks of the
/// next one as expiring soon.
pub(crate) const TX_EXPIRING_SOON_BLOCKS: u32 = 3;

pub(crate) const START_HOLD_MESSAGE: &str =
    "Migrations can't start this close to the network upgrade. Try again after it activates.";
pub(crate) const SEND_HOLD_MESSAGE: &str =
    "Transactions can't be sent this close to the network upgrade. Try again after it activates.";
pub(crate) const MIGRATION_HOLD_MESSAGE: &str =
    "Migration transactions are held for the network upgrade.";
pub(crate) const MIGRATION_STOP_MESSAGE: &str = "The network upgrade stopped this migration. \
     Transactions signed before the upgrade can't be sent after it.";
pub(crate) const STALE_SCHEDULE_MESSAGE: &str =
    "Migration schedule was drawn before the network upgrade; review the plan again";

/// The first upgrade activation after `height`, if one is scheduled.
pub(crate) fn next_activation_after<P: Parameters>(
    network: &P,
    height: BlockHeight,
) -> Option<BlockHeight> {
    match BranchId::for_height(network, height).height_bounds(network) {
        Some((_, Some(next))) => Some(next),
        _ => None,
    }
}

/// Whether a block at `height` uses a different branch from a transaction
/// targeting `target_height`.
pub(crate) fn crosses<P: Parameters>(network: &P, target_height: u32, height: u32) -> bool {
    BranchId::for_height(network, BlockHeight::from_u32(target_height))
        != BranchId::for_height(network, BlockHeight::from_u32(height))
}

/// `expiry` capped at the last block of the branch at `target_height`.
pub(crate) fn cap_expiry_at_branch_end<P: Parameters>(
    network: &P,
    target_height: BlockHeight,
    expiry: BlockHeight,
) -> BlockHeight {
    next_activation_after(network, target_height)
        .map_or(expiry, |next| expiry.min((next - 1).max(target_height)))
}

/// Whether a transaction for `signed_target_height`, sent after
/// `chain_tip_height`, falls within the hold window before an upgrade.
pub(crate) fn holds_transaction<P: Parameters>(
    network: &P,
    signed_target_height: u32,
    chain_tip_height: u32,
) -> bool {
    crosses(
        network,
        signed_target_height,
        chain_tip_height
            .saturating_add(1)
            .saturating_add(BROADCAST_HOLD_BLOCKS),
    )
}

/// Refuses a new migration whose first transactions target `target_height`:
/// they would be held until the upgrade stops the run.
pub(crate) fn ensure_migration_can_start<P: Parameters>(
    network: &P,
    target_height: u32,
) -> Result<(), String> {
    if holds_transaction(network, target_height, target_height.saturating_sub(1)) {
        return Err(START_HOLD_MESSAGE.to_string());
    }
    Ok(())
}

/// The next upgrade after a chain tip and the tips from which the wallet
/// refuses work before it. Both refusals hold while the next block is still
/// on the old branch, through tip `next_activation_height - 2`.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct HoldHeights {
    pub next_activation_height: u32,
    /// New migrations: their transactions would be held until the upgrade
    /// stops the run.
    pub migration_hold_from_tip: u32,
    /// Transactions: their capped expiry would read as expiring soon.
    pub send_hold_from_tip: u32,
}

/// [`HoldHeights`] for the first upgrade that activates after `tip`, or none
/// when no upgrade is scheduled.
pub(crate) fn hold_heights<P: Parameters>(network: &P, tip: u32) -> Option<HoldHeights> {
    let next_activation_height =
        u32::from(next_activation_after(network, BlockHeight::from_u32(tip))?);
    let before_activation = |blocks: u32| {
        next_activation_height
            .saturating_sub(1)
            .saturating_sub(blocks)
    };
    Some(HoldHeights {
        next_activation_height,
        migration_hold_from_tip: before_activation(BROADCAST_HOLD_BLOCKS),
        send_hold_from_tip: before_activation(TX_EXPIRING_SOON_BLOCKS),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::network::WalletNetwork;
    use zcash_protocol::consensus::NetworkUpgrade;

    fn testnet_nu7() -> u32 {
        WalletNetwork::Test
            .activation_height(NetworkUpgrade::Nu7)
            .map(u32::from)
            .unwrap()
    }

    #[test]
    fn holds_transactions_built_in_the_last_ten_blocks() {
        let network = WalletNetwork::Test;
        let activation = testnet_nu7();
        let first_held_target = activation - BROADCAST_HOLD_BLOCKS;
        let built_at = |target: u32| holds_transaction(&network, target, target - 1);

        assert!(!built_at(first_held_target - 1));
        assert!(built_at(first_held_target));
        assert!(built_at(activation - 1));
        assert!(!built_at(activation));
        // Signed before the window, but the tip reached it during signing.
        assert!(holds_transaction(
            &network,
            first_held_target - 1,
            first_held_target - 1,
        ));
        assert_eq!(
            ensure_migration_can_start(&network, first_held_target).unwrap_err(),
            START_HOLD_MESSAGE
        );
        assert!(ensure_migration_can_start(&network, activation).is_ok());
    }

    #[test]
    fn next_activation_is_the_first_one_after_the_height() {
        let network = WalletNetwork::Test;
        let activation = testnet_nu7();
        assert_eq!(
            next_activation_after(&network, BlockHeight::from_u32(activation - 1)),
            Some(BlockHeight::from_u32(activation))
        );
        assert_eq!(
            next_activation_after(&network, BlockHeight::from_u32(activation)),
            None
        );
        assert_eq!(
            cap_expiry_at_branch_end(
                &network,
                BlockHeight::from_u32(activation - 5),
                BlockHeight::from_u32(activation + 35),
            ),
            BlockHeight::from_u32(activation - 1)
        );
    }
}
