//! Wallet fees follow the consensus schedule at the transaction target height.
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

pub(crate) const LEGACY_MARGINAL_FEE: u64 = 5_000;
pub(crate) const NU7_MARGINAL_FEE: u64 = 1_000;

pub(crate) fn marginal_fee<P: Parameters>(network: &P, target: BlockHeight) -> u64 {
    if network.is_nu_active(NetworkUpgrade::Nu7, target) {
        NU7_MARGINAL_FEE
    } else {
        LEGACY_MARGINAL_FEE
    }
}
