//! The blocks around a network upgrade. A transaction commits to the
//! consensus branch at its target height, so one signed before an upgrade can
//! only be mined before it activates.

use zcash_protocol::consensus::{BlockHeight, BranchId, Parameters};

/// Nodes reject a transaction that expires within this many blocks of the
/// next one as expiring soon.
pub(crate) const TX_EXPIRING_SOON_BLOCKS: u32 = 3;

pub(crate) const SEND_HOLD_MESSAGE: &str =
    "Transactions can't be sent this close to the network upgrade. Try again after it activates.";

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

/// The next upgrade after a chain tip and the tip from which the wallet
/// refuses transactions before it. The refusal holds while the next block is
/// still on the old branch, through tip `next_activation_height - 2`.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct HoldHeights {
    pub next_activation_height: u32,
    /// Transactions: their capped expiry would read as expiring soon.
    pub send_hold_from_tip: u32,
}

/// [`HoldHeights`] for the first upgrade that activates after `tip`, or none
/// when no upgrade is scheduled.
pub(crate) fn hold_heights<P: Parameters>(network: &P, tip: u32) -> Option<HoldHeights> {
    let next_activation_height =
        u32::from(next_activation_after(network, BlockHeight::from_u32(tip))?);
    Some(HoldHeights {
        next_activation_height,
        send_hold_from_tip: next_activation_height
            .saturating_sub(1)
            .saturating_sub(TX_EXPIRING_SOON_BLOCKS),
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
