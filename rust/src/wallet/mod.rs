use std::num::NonZeroU32;

use zcash_client_backend::data_api::wallet::ConfirmationsPolicy;

pub(crate) mod db;
pub mod keys;
pub mod keystone;
pub mod ledger;
pub mod network;
pub mod secret_payload;
pub mod secret_store;
pub mod sync;
pub mod sync_engine;
pub(crate) mod transparent_receive_cache;
pub mod voting;
pub(crate) mod wallet_summary_cache;

const TRUSTED_CONFIRMATIONS: u32 = 3;
// Vizor's product policy accepts externally received funds sooner than the
// ZIP 315 default of 10 confirmations.
const UNTRUSTED_CONFIRMATIONS: u32 = 6;
const ALLOW_ZERO_CONFIRMATION_SHIELDING: bool = true;

fn confirmations_policy() -> ConfirmationsPolicy {
    ConfirmationsPolicy::new(
        NonZeroU32::new(TRUSTED_CONFIRMATIONS).expect("trusted confirmations are nonzero"),
        NonZeroU32::new(UNTRUSTED_CONFIRMATIONS).expect("untrusted confirmations are nonzero"),
        ALLOW_ZERO_CONFIRMATION_SHIELDING,
    )
    .expect("trusted confirmations do not exceed untrusted confirmations")
}

#[cfg(test)]
mod tests {
    use super::*;
    use zcash_client_backend::data_api::wallet::TargetHeight;
    use zcash_protocol::{consensus::BlockHeight, PoolType, ShieldedPool};
    use zip32::Scope;

    #[test]
    fn confirmation_policy_uses_six_confirmations_for_external_funds() {
        let policy = confirmations_policy();

        assert_eq!(u32::from(policy.trusted()), TRUSTED_CONFIRMATIONS);
        assert_eq!(u32::from(policy.untrusted()), UNTRUSTED_CONFIRMATIONS);
    }

    #[test]
    fn external_funds_become_spendable_after_six_confirmations() {
        let policy = confirmations_policy();
        let confirmations_remaining = |target_height| {
            policy.confirmations_until_spendable(
                TargetHeight::from(target_height),
                PoolType::Shielded(ShieldedPool::Orchard),
                Some(Scope::External),
                Some(BlockHeight::from_u32(100)),
                false,
                None,
                false,
            )
        };

        assert_eq!(confirmations_remaining(105), 1);
        assert_eq!(confirmations_remaining(106), 0);
    }
}
