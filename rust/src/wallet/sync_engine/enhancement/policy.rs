//! One immutable source-selection decision for a transaction-data operation.

use std::borrow::Borrow;
use std::sync::atomic::{AtomicBool, Ordering};

use zcash_client_backend::data_api::status::TransactionStatusMode;

use zcash_client_backend::data_api::enhance_pir::EnhancementMode;
use zcash_client_backend::data_api::transparent_ledger::{
    AppliedTransparentPolicy, TransparentLedgerMode, TransparentLedgerRead,
};
use zcash_client_sqlite::{error::SqliteClientError, WalletDb};
use zcash_protocol::consensus;

use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::{SyncError, WalletDatabase};

/// The `ZCASH_PRIVATE_TRANSPARENT_RECOVERY` development flag, pushed once at
/// runtime start. Default builds leave it off and never select a private
/// transparent mode.
static PRIVATE_TRANSPARENT_RECOVERY: AtomicBool = AtomicBool::new(false);

/// Whether the private-queries preference in effect was read from storage,
/// not assumed private because the read failed. Only a confirmed preference
/// may durably raise a wallet's transparent policy.
static PREFERENCE_CONFIRMED: AtomicBool = AtomicBool::new(false);

/// Records the build's development flag. Called once at runtime start.
pub(crate) fn configure_private_transparent_recovery(enabled: bool) {
    PRIVATE_TRANSPARENT_RECOVERY.store(enabled, Ordering::SeqCst);
}

/// Whether this build may select private transparent recovery.
pub(crate) fn private_transparent_recovery() -> bool {
    PRIVATE_TRANSPARENT_RECOVERY.load(Ordering::SeqCst)
}

/// Records whether the private-queries preference was read from storage.
pub(crate) fn set_preference_confirmed(confirmed: bool) {
    PREFERENCE_CONFIRMED.store(confirmed, Ordering::SeqCst);
}

/// The transparent ledger mode that `preference` selects on `network` in a
/// build whose development flag is `build_flag`.
///
/// `PrivateRequired` only on mainnet, with private queries on and the flag
/// set, outside masquerade builds; otherwise `Public`. The selection never
/// weakens a wallet: openers adopt a stricter durable policy, and only an
/// explicit toggle-off lowers one.
pub(crate) fn select_transparent_mode(
    network: WalletNetwork,
    preference: bool,
    build_flag: bool,
) -> TransparentLedgerMode {
    if network == WalletNetwork::Main && preference && build_flag && !cfg!(ironwood_masquerade) {
        TransparentLedgerMode::PrivateRequired
    } else {
        TransparentLedgerMode::Public
    }
}

/// The selection from the live preference and development flag.
pub(crate) fn selected_transparent_mode(network: WalletNetwork) -> TransparentLedgerMode {
    select_transparent_mode(
        network,
        crate::api::sync::enhance_pir_enabled(),
        private_transparent_recovery(),
    )
}

/// Transparent ledger mode for a handle on the wallet at `db_path`.
///
/// Production returns [`selected_transparent_mode`]. Tests select a mode for
/// one wallet file through [`test_mode`], so private activation runs through
/// the same handle openers, balance reads, and spend paths as production
/// without touching the process-wide preference or flag.
pub(crate) fn transparent_ledger_mode_for(
    db_path: &str,
    network: WalletNetwork,
) -> TransparentLedgerMode {
    #[cfg(test)]
    if let Some(selection) = test_mode::get(db_path) {
        return selection.mode;
    }
    let _ = db_path;
    selected_transparent_mode(network)
}

/// Whether this build recovers the wallet at `db_path` privately: only a
/// `PrivateRequired` selection runs private recovery. A wallet that durably
/// requires it in a build that does not select it keeps the stricter policy,
/// so its transparent funds stay unavailable until private queries are turned
/// off.
pub(crate) fn selects_private_recovery(db_path: &str, network: WalletNetwork) -> bool {
    transparent_ledger_mode_for(db_path, network) == TransparentLedgerMode::PrivateRequired
}

/// Whether a durable policy may be raised to `PrivateRequired` for the wallet
/// at `db_path` without an explicit toggle: the selection is `PrivateRequired`
/// and the preference behind it was read, not assumed. An unreadable
/// preference still selects private handles for the launch, which withholds
/// public lookups, but never writes a policy.
pub(crate) fn may_raise(db_path: &str, network: WalletNetwork) -> bool {
    #[cfg(test)]
    if let Some(selection) = test_mode::get(db_path) {
        return selection.mode == TransparentLedgerMode::PrivateRequired && selection.confirmed;
    }
    let _ = db_path;
    selected_transparent_mode(network) == TransparentLedgerMode::PrivateRequired
        && PREFERENCE_CONFIRMED.load(Ordering::SeqCst)
}

/// Raises `db` to `PrivateRequired` when the wallet durably requires it, so
/// a handle is never weaker than its wallet, whatever this build selects.
///
/// Reacts only to that conflict. Any other error leaves the handle as
/// configured, for its first ledger read to report.
pub(crate) fn adopt_durable_private<C, P, CL, R>(db: &mut WalletDb<C, P, CL, R>)
where
    C: Borrow<rusqlite::Connection>,
    P: consensus::Parameters,
{
    if let Err(SqliteClientError::TransparentLedgerPolicyConflict {
        applied: TransparentLedgerMode::PrivateRequired,
        ..
    }) = db.transparent_ledger_mode()
    {
        db.set_transparent_ledger_mode(TransparentLedgerMode::PrivateRequired);
    }
}

/// Test seam: a per-wallet-file selection, standing in for the live
/// preference, development flag, and confirmation. Keyed by path, so parallel
/// tests on other wallets are unaffected and no test changes the
/// process-wide values.
#[cfg(test)]
pub(crate) mod test_mode {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock, PoisonError};

    use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerMode;

    #[derive(Clone, Copy, Debug)]
    pub(crate) struct Selection {
        /// The mode handles on the wallet are opened with.
        pub(crate) mode: TransparentLedgerMode,
        /// Whether the preference behind `mode` counts as read from storage.
        pub(crate) confirmed: bool,
    }

    fn overrides() -> &'static Mutex<HashMap<String, Selection>> {
        static OVERRIDES: OnceLock<Mutex<HashMap<String, Selection>>> = OnceLock::new();
        OVERRIDES.get_or_init(Default::default)
    }

    pub(crate) fn get(db_path: &str) -> Option<Selection> {
        overrides()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(db_path)
            .copied()
    }

    /// Handles opened on `db_path` use `mode`, from a confirmed preference,
    /// until the guard drops.
    pub(crate) fn set(db_path: &str, mode: TransparentLedgerMode) -> ModeOverride {
        select(db_path, mode, true)
    }

    /// Handles opened on `db_path` use `mode` until the guard drops; whether
    /// the preference behind it was read is `confirmed`.
    pub(crate) fn select(
        db_path: &str,
        mode: TransparentLedgerMode,
        confirmed: bool,
    ) -> ModeOverride {
        overrides()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(db_path.to_owned(), Selection { mode, confirmed });
        ModeOverride(db_path.to_owned())
    }

    pub(crate) struct ModeOverride(String);

    impl Drop for ModeOverride {
        fn drop(&mut self) {
            overrides()
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .remove(&self.0);
        }
    }
}

/// Resolves the install preference once so status and payload retrieval cannot
/// observe different values during the same operation.
///
/// The transparent ledger mode is captured with it, from the same preference
/// and the build's development flag: see [`select_transparent_mode`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct EnhancementPolicy {
    private: bool,
    transparent: TransparentLedgerMode,
}

impl EnhancementPolicy {
    pub(crate) fn current(network: WalletNetwork) -> Self {
        Self::for_preference(network, crate::api::sync::enhance_pir_enabled())
    }

    /// The policy `private_preference` selects in this build.
    pub(crate) fn for_preference(network: WalletNetwork, private_preference: bool) -> Self {
        Self::for_inputs(network, private_preference, private_transparent_recovery())
    }

    /// The policy `preference` selects in a build whose development flag is
    /// `build_flag`.
    pub(crate) fn for_inputs(network: WalletNetwork, preference: bool, build_flag: bool) -> Self {
        Self {
            private: network == WalletNetwork::Main && preference && !cfg!(ironwood_masquerade),
            transparent: select_transparent_mode(network, preference, build_flag),
        }
    }

    /// Test seam for a transparent mode this build would not select for the
    /// test's network.
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

    /// The transparent ledger mode captured for this operation.
    pub(crate) fn transparent_mode(self) -> TransparentLedgerMode {
        self.transparent
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

    /// Configures `db` for this operation. The handle then adopts a durable
    /// `PrivateRequired`, so a weaker captured mode pauses transparent work on
    /// a private wallet instead of failing every read against it.
    pub(crate) fn configure_db(self, db: &mut WalletDatabase) {
        db.set_transparent_ledger_mode(self.transparent);
        adopt_durable_private(db);
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

    #[test]
    fn select_transparent_mode_needs_flag_preference_and_mainnet() {
        let private = if cfg!(ironwood_masquerade) {
            TransparentLedgerMode::Public
        } else {
            TransparentLedgerMode::PrivateRequired
        };
        for network in [
            WalletNetwork::Main,
            WalletNetwork::Test,
            WalletNetwork::Regtest,
        ] {
            for preference in [false, true] {
                for build_flag in [false, true] {
                    let expected = if network == WalletNetwork::Main && preference && build_flag {
                        private
                    } else {
                        TransparentLedgerMode::Public
                    };
                    assert_eq!(
                        select_transparent_mode(network, preference, build_flag),
                        expected,
                        "{network:?}, preference {preference}, flag {build_flag}"
                    );
                    // The captured policy agrees with the handles' selection,
                    // and the flag never changes status or payload routing.
                    let policy = EnhancementPolicy::for_inputs(network, preference, build_flag);
                    assert_eq!(policy.transparent_mode(), expected);
                    assert_eq!(
                        policy.is_private(),
                        EnhancementPolicy::for_inputs(network, preference, !build_flag)
                            .is_private()
                    );
                }
            }
        }
    }

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
