//! One immutable source-selection decision for a transaction-data operation.

use std::sync::atomic::{AtomicBool, Ordering};

use zcash_client_backend::data_api::status::TransactionStatusMode;

use zcash_client_backend::data_api::enhance_pir::EnhancementMode;
use zcash_client_backend::data_api::transparent_ledger::{
    AppliedTransparentPolicy, TransparentLedgerMode, TransparentLedgerRead,
};

use crate::wallet::network::WalletNetwork;
use crate::wallet::sync_engine::{SyncError, WalletDatabase};

/// Whether the private-queries preference in effect was read from storage,
/// not assumed private because the read failed. Only a confirmed preference
/// may durably raise a wallet's transparent policy.
static PREFERENCE_CONFIRMED: AtomicBool = AtomicBool::new(false);

/// Records whether the private-queries preference was read from storage.
pub(crate) fn set_preference_confirmed(confirmed: bool) {
    PREFERENCE_CONFIRMED.store(confirmed, Ordering::SeqCst);
}

/// The transparent ledger mode for the private queries `preference` on
/// `network`.
///
/// `PrivateRequired` only on mainnet with private queries on, outside
/// masquerade builds; otherwise `Public`. It never weakens a wallet: reads
/// honor a stricter durable policy, and only an explicit toggle-off lowers
/// one.
pub(crate) fn transparent_mode_for_preference(
    network: WalletNetwork,
    preference: bool,
) -> TransparentLedgerMode {
    if network == WalletNetwork::Main && preference && !cfg!(ironwood_masquerade) {
        TransparentLedgerMode::PrivateRequired
    } else {
        TransparentLedgerMode::Public
    }
}

/// The transparent ledger mode for the live private queries preference.
pub(crate) fn live_transparent_mode(network: WalletNetwork) -> TransparentLedgerMode {
    transparent_mode_for_preference(network, crate::api::sync::enhance_pir_enabled())
}

/// Transparent ledger mode for a handle on the wallet at `db_path`.
///
/// Production returns [`live_transparent_mode`]. Tests override the mode for
/// one wallet file through [`test_mode`], so private activation runs through
/// the same handle openers, balance reads, and spend paths as production
/// without touching the process-wide preference.
pub(crate) fn transparent_ledger_mode_for(
    db_path: &str,
    network: WalletNetwork,
) -> TransparentLedgerMode {
    #[cfg(test)]
    if let Some(mode) = test_mode::get(db_path) {
        return mode.mode;
    }
    let _ = db_path;
    live_transparent_mode(network)
}

/// Whether private queries are in effect for the wallet at `db_path`: on, on
/// mainnet. Only then does private recovery run. A wallet that durably
/// requires private recovery while they are off (turning them off did not
/// finish) keeps the stricter policy, so its transparent funds stay
/// unavailable until private queries are turned off again.
pub(crate) fn private_queries_active(db_path: &str, network: WalletNetwork) -> bool {
    transparent_ledger_mode_for(db_path, network) == TransparentLedgerMode::PrivateRequired
}

/// Whether a durable policy may be raised to `PrivateRequired` for the wallet
/// at `db_path` without an explicit toggle: the live mode is `PrivateRequired`
/// and the preference behind it was read, not assumed. An unreadable
/// preference still opens private handles for the launch, which withholds
/// public lookups, but never writes a policy.
pub(crate) fn may_raise(db_path: &str, network: WalletNetwork) -> bool {
    #[cfg(test)]
    if let Some(mode) = test_mode::get(db_path) {
        return mode.mode == TransparentLedgerMode::PrivateRequired && mode.confirmed;
    }
    let _ = db_path;
    live_transparent_mode(network) == TransparentLedgerMode::PrivateRequired
        && PREFERENCE_CONFIRMED.load(Ordering::SeqCst)
}

/// Test seam: a per-wallet-file mode override, standing in for the live
/// preference and confirmation. Keyed by path, so parallel
/// tests on other wallets are unaffected and no test changes the
/// process-wide values.
#[cfg(test)]
pub(crate) mod test_mode {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock, PoisonError};

    use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerMode;

    #[derive(Clone, Copy, Debug)]
    pub(crate) struct Override {
        /// The mode handles on the wallet are opened with.
        pub(crate) mode: TransparentLedgerMode,
        /// Whether the preference behind `mode` counts as read from storage.
        pub(crate) confirmed: bool,
    }

    fn overrides() -> &'static Mutex<HashMap<String, Override>> {
        static OVERRIDES: OnceLock<Mutex<HashMap<String, Override>>> = OnceLock::new();
        OVERRIDES.get_or_init(Default::default)
    }

    pub(crate) fn get(db_path: &str) -> Option<Override> {
        overrides()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .get(db_path)
            .copied()
    }

    /// Handles opened on `db_path` use `mode`, from a confirmed preference,
    /// until the guard drops.
    pub(crate) fn set(db_path: &str, mode: TransparentLedgerMode) -> ModeOverride {
        set_with(db_path, mode, true)
    }

    /// Handles opened on `db_path` use `mode` until the guard drops; whether
    /// the preference behind it was read is `confirmed`.
    pub(crate) fn set_with(
        db_path: &str,
        mode: TransparentLedgerMode,
        confirmed: bool,
    ) -> ModeOverride {
        overrides()
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(db_path.to_owned(), Override { mode, confirmed });
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
/// on the supported network: see [`transparent_mode_for_preference`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct EnhancementPolicy {
    private: bool,
    transparent: TransparentLedgerMode,
}

impl EnhancementPolicy {
    pub(crate) fn current(network: WalletNetwork) -> Self {
        Self::for_preference(network, crate::api::sync::enhance_pir_enabled())
    }

    /// Captures the private queries preference for the supported network.
    pub(crate) fn for_preference(network: WalletNetwork, preference: bool) -> Self {
        Self {
            private: network == WalletNetwork::Main && preference && !cfg!(ironwood_masquerade),
            transparent: transparent_mode_for_preference(network, preference),
        }
    }

    /// Test seam for private queries on a network that has no service.
    #[cfg(test)]
    pub(crate) fn with_private_queries(self) -> Self {
        Self {
            private: true,
            ..self
        }
    }

    /// Test seam for a transparent mode the test's network and preference
    /// would not produce.
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

    /// Configures `db` for this operation. The library resolves the handle
    /// under a durable `PrivateRequired`, so a weaker captured mode pauses
    /// transparent work on a private wallet instead of failing every read
    /// against it.
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

    #[test]
    fn private_queries_select_transparent_recovery_on_supported_mainnet() {
        for network in [
            WalletNetwork::Main,
            WalletNetwork::Test,
            WalletNetwork::Regtest,
        ] {
            for preference in [false, true] {
                let enabled =
                    network == WalletNetwork::Main && preference && !cfg!(ironwood_masquerade);
                let expected = if enabled {
                    TransparentLedgerMode::PrivateRequired
                } else {
                    TransparentLedgerMode::Public
                };
                let policy = EnhancementPolicy::for_preference(network, preference);
                assert_eq!(
                    transparent_mode_for_preference(network, preference),
                    expected
                );
                assert_eq!(policy.transparent_mode(), expected);
                assert_eq!(policy.is_private(), enabled);
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

    /// A supplemental source guard: release builds must ignore every
    /// development switch, so each environment read in the crate's sources
    /// sits under a debug-build gate (`cfg(debug_assertions)` or
    /// `cfg!(debug_assertions)` at most a few lines above it), or in a test.
    /// It cannot prove a gate is correct; it catches a new read added without
    /// one. Run the gate tests themselves with `cargo test --release` to see
    /// the switches off.
    #[test]
    fn every_environment_switch_is_read_only_in_debug_builds_or_tests() {
        fn walk(dir: &std::path::Path, files: &mut Vec<std::path::PathBuf>) {
            for entry in std::fs::read_dir(dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    walk(&path, files);
                } else if path.extension().is_some_and(|ext| ext == "rs") {
                    files.push(path);
                }
            }
        }
        const WINDOW: usize = 12;
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let mut files = Vec::new();
        walk(&root, &mut files);
        let mut ungated = Vec::new();
        for path in files {
            let relative = path.strip_prefix(&root).unwrap();
            // Test-only files: a `tests/` module directory or `*tests.rs`.
            if path.ends_with("frb_generated.rs")
                || relative
                    .components()
                    .any(|part| part.as_os_str() == "tests")
                || relative
                    .file_name()
                    .is_some_and(|name| name.to_string_lossy().ends_with("tests.rs"))
            {
                continue;
            }
            let source = std::fs::read_to_string(&path).unwrap();
            let lines: Vec<&str> = source.lines().collect();
            // Everything after a file's `#[cfg(test)] mod tests` is test code.
            let test_module = (1..lines.len())
                .find(|&index| {
                    lines[index - 1].trim() == "#[cfg(test)]"
                        && lines[index].trim_start().starts_with("mod tests")
                })
                .unwrap_or(lines.len());
            for (index, line) in lines.iter().enumerate().take(test_module) {
                let code = line.trim_start();
                let reads = ["env::var(", "env::var_os("]
                    .iter()
                    .any(|read| code.contains(read) && !code.contains(&format!("\"{read}")));
                if code.starts_with("//") || !reads {
                    continue;
                }
                let gated = lines[index.saturating_sub(WINDOW)..=index]
                    .iter()
                    .any(|above| {
                        above.contains("cfg(debug_assertions)")
                            || above.contains("cfg!(debug_assertions)")
                            || above.contains("#[test]")
                            || above.contains("#[tokio::test")
                            || above.contains("#[cfg(test)]")
                    });
                if !gated {
                    ungated.push(format!("{}:{}: {}", relative.display(), index + 1, code));
                }
            }
        }
        assert!(
            ungated.is_empty(),
            "environment reads outside a debug-build gate or a test:\n{}",
            ungated.join("\n")
        );
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
