//! One immutable source-selection decision for a transaction-data operation.

use zcash_client_backend::data_api::status::TransactionStatusMode;

use zcash_client_backend::data_api::enhance_pir::EnhancementMode;

use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::WalletDatabase;

/// Resolves the install preference once so status and payload retrieval cannot
/// observe different values during the same operation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct EnhancementPolicy {
    private: bool,
}

impl EnhancementPolicy {
    pub(crate) fn current(network: WalletNetwork) -> Self {
        Self::for_preference(network, crate::api::sync::enhance_pir_enabled())
    }

    pub(crate) fn for_preference(network: WalletNetwork, private_preference: bool) -> Self {
        Self {
            private: network == WalletNetwork::Main
                && private_preference
                && !cfg!(ironwood_masquerade),
        }
    }

    pub(crate) fn is_private(self) -> bool {
        self.private
    }

    pub(crate) fn status_mode(self) -> TransactionStatusMode {
        if self.private {
            TransactionStatusMode::Private
        } else {
            TransactionStatusMode::Public
        }
    }

    pub(crate) fn payload_mode(self) -> EnhancementMode {
        if self.private {
            EnhancementMode::PrivateIronwood
        } else {
            EnhancementMode::Standard
        }
    }

    pub(crate) fn configure_db(self, db: &mut WalletDatabase) {
        db.set_enhancement_mode(self.payload_mode());
        db.set_status_mode(self.status_mode());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(not(ironwood_masquerade))]
    #[test]
    fn private_preference_selects_private_status_and_payload_on_mainnet() {
        let policy = EnhancementPolicy::for_preference(WalletNetwork::Main, true);
        assert!(policy.is_private());
        assert_eq!(policy.status_mode(), TransactionStatusMode::Private);
        assert_eq!(policy.payload_mode(), EnhancementMode::PrivateIronwood);
    }

    #[cfg(ironwood_masquerade)]
    #[test]
    fn private_preference_is_unavailable_in_masquerade_builds() {
        let policy = EnhancementPolicy::for_preference(WalletNetwork::Main, true);
        assert!(!policy.is_private());
        assert_eq!(policy.status_mode(), TransactionStatusMode::Public);
        assert_eq!(policy.payload_mode(), EnhancementMode::Standard);
    }

    #[test]
    fn private_preference_is_unavailable_off_mainnet() {
        for network in [WalletNetwork::Test, WalletNetwork::Regtest] {
            let policy = EnhancementPolicy::for_preference(network, true);
            assert!(!policy.is_private());
            assert_eq!(policy.status_mode(), TransactionStatusMode::Public);
            assert_eq!(policy.payload_mode(), EnhancementMode::Standard);
        }
    }

    #[test]
    fn disabled_preference_selects_both_public_modes() {
        let policy = EnhancementPolicy::for_preference(WalletNetwork::Main, false);
        assert!(!policy.is_private());
        assert_eq!(policy.status_mode(), TransactionStatusMode::Public);
        assert_eq!(policy.payload_mode(), EnhancementMode::Standard);
    }
}
