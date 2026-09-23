use std::num::NonZeroU32;

use zcash_client_backend::data_api::wallet::ConfirmationsPolicy;

pub(crate) mod addresses;
pub(crate) mod db;
pub mod keys;
pub(crate) mod gift_card_tracking;
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
// Gift Card claims spend a bearer card into the recipient's own wallet. Two
// confirmations anchor one block below the tip, so a one-block reorg cannot
// invalidate the claim.
const PAYMENT_LINK_CLAIM_CONFIRMATIONS: u32 = 2;

fn confirmations_policy() -> ConfirmationsPolicy {
    ConfirmationsPolicy::new(
        NonZeroU32::new(TRUSTED_CONFIRMATIONS).expect("trusted confirmations are nonzero"),
        NonZeroU32::new(UNTRUSTED_CONFIRMATIONS).expect("untrusted confirmations are nonzero"),
        ALLOW_ZERO_CONFIRMATION_SHIELDING,
    )
    .expect("trusted confirmations do not exceed untrusted confirmations")
}

fn payment_link_claim_confirmations_policy() -> ConfirmationsPolicy {
    let confirmations =
        NonZeroU32::new(PAYMENT_LINK_CLAIM_CONFIRMATIONS).expect("claim confirmations are nonzero");
    ConfirmationsPolicy::new(confirmations, confirmations, false)
        .expect("claim confirmations are symmetric")
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

    #[test]
    fn gift_card_claims_spend_external_funds_after_two_confirmations() {
        let policy = payment_link_claim_confirmations_policy();
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

        assert_eq!(
            u32::from(policy.trusted()),
            PAYMENT_LINK_CLAIM_CONFIRMATIONS
        );
        assert_eq!(
            u32::from(policy.untrusted()),
            PAYMENT_LINK_CLAIM_CONFIRMATIONS
        );
        assert_eq!(confirmations_remaining(101), 1);
        assert_eq!(confirmations_remaining(102), 0);
    }
}
