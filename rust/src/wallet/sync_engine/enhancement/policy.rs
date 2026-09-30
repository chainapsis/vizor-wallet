//! One immutable source-selection decision for a transaction-data operation.

use zcash_client_backend::data_api::status::TransactionStatusMode;

use zcash_client_backend::data_api::enhance_pir::EnhancementMode;
use zcash_client_backend::data_api::transparent_ledger::{
    AppliedTransparentPolicy, TransparentLedgerMode, TransparentLedgerRead,
};

use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::{SyncError, WalletDatabase};

/// Transparent ledger mode for every wallet handle this build opens.
///
/// Always `Public`: this build has no private transparent recovery, so it
/// keeps public transparent authority. A wallet whose durably applied policy is
/// stricter stays blocked instead of being weakened. Private modes will derive
/// from the private-queries preference once transparent PIR recovery exists.
pub(crate) fn transparent_ledger_mode() -> TransparentLedgerMode {
    TransparentLedgerMode::Public
}

/// Resolves the install preference once so status and payload retrieval cannot
/// observe different values during the same operation.
///
/// The transparent ledger mode is captured with it. Production always captures
/// [`transparent_ledger_mode`]; the private-queries preference selects only the
/// status and payload sources.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct EnhancementPolicy {
    private: bool,
    transparent: TransparentLedgerMode,
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
            transparent: transparent_ledger_mode(),
        }
    }

    /// Test seam for the stricter transparent path, which production cannot
    /// select before private transparent recovery exists.
    #[cfg(test)]
    pub(crate) fn with_transparent_mode(self, transparent: TransparentLedgerMode) -> Self {
        Self {
            transparent,
            ..self
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
        db.set_transparent_ledger_mode(self.transparent);
        db.set_enhancement_mode(self.payload_mode());
        db.set_status_mode(self.status_mode());
    }

    /// Resolves whether this operation may send transparent addresses, scripts,
    /// outpoints, or txids to public lightwalletd.
    ///
    /// Takes the stricter of the captured mode and the policy durably applied to
    /// the wallet, so a newer build's `PrivateRequired` or a transition made by
    /// another connection is never weakened by this handle.
    pub(crate) fn public_transparent_lookups(
        self,
        db: &WalletDatabase,
    ) -> Result<PublicTransparentLookups, SyncError> {
        if !self.transparent.retains_public_authority() {
            return Ok(PublicTransparentLookups::Withheld);
        }
        let applied = db
            .applied_transparent_policy()
            .map_err(|error| SyncError::db(format!("applied_transparent_policy: {error}")))?;
        Ok(if applied.mode.retains_public_authority() {
            PublicTransparentLookups::Allowed {
                generation: Some(applied.generation),
            }
        } else {
            PublicTransparentLookups::Withheld
        })
    }

    /// The same decision for a request made before any wallet database exists,
    /// such as an import preview. Only the captured mode applies.
    pub(crate) fn pre_db_public_transparent_lookups(self) -> PublicTransparentLookups {
        if self.transparent.retains_public_authority() {
            PublicTransparentLookups::Allowed { generation: None }
        } else {
            PublicTransparentLookups::Withheld
        }
    }
}

/// Whether public transparent lookups are authorized for one operation.
///
/// `Withheld` sends nothing and deletes nothing: unfinished work stays durable
/// until a later operation is authorized.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum PublicTransparentLookups {
    /// Authorized under the durable policy generation captured with it, when a
    /// wallet database exists.
    Allowed {
        generation: Option<u64>,
    },
    Withheld,
}

impl PublicTransparentLookups {
    pub(crate) fn is_allowed(self) -> bool {
        matches!(self, Self::Allowed { .. })
    }

    /// Commit check before each public dispatch: still authorized only while the
    /// durable policy generation is unchanged and retains public authority. A
    /// transition by another connection withholds the rest of the operation.
    pub(crate) fn still_allowed(self, db: &WalletDatabase) -> Result<bool, SyncError> {
        if !self.is_allowed() {
            return Ok(false);
        }
        let applied = db
            .applied_transparent_policy()
            .map_err(|error| SyncError::db(format!("applied_transparent_policy: {error}")))?;
        Ok(self.permits(applied))
    }

    /// Whether `applied`, read by the caller, still authorizes these lookups.
    /// Read it in the same SQLite transaction as a write to make that write's
    /// commit check atomic with it.
    pub(crate) fn permits(self, applied: AppliedTransparentPolicy) -> bool {
        let Self::Allowed { generation } = self else {
            return false;
        };
        applied.mode.retains_public_authority()
            && generation.map_or(true, |generation| generation == applied.generation)
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
