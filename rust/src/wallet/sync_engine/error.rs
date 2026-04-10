//! Error taxonomy for the sync engine.
//!
//! Historically every failure inside the sync loop was flattened to a `String`
//! via the `err()` helper, which left the outer retry wrapper unable to tell a
//! chain reorg apart from a transient gRPC failure apart from an irrecoverable
//! DB corruption. The result was that reorgs (librustzcash's `PrevHashMismatch`
//! / `BlockHeightDiscontinuity`) would propagate up as plain error strings,
//! `run_sync_inner` would retry them three times against the same failing DB
//! state, and the wallet would land in a permanent error state.
//!
//! `SyncError` is the typed replacement. Every call-site inside `sync_engine`
//! and its peers returns `Result<_, SyncError>`; the public FRB / C-FFI
//! surface still collapses it to `String` for ABI compatibility in
//! `run_sync_inner`.

use std::fmt;

/// Classified sync-engine failure. Carries enough information for the retry
/// wrapper to pick the right recovery strategy via `recovery_strategy`.
#[derive(Debug, Clone)]
pub(crate) enum SyncError {
    /// `scan_cached_blocks` reported a `PrevHashMismatch` or
    /// `BlockHeightDiscontinuity` at `at_height`, meaning the wallet's
    /// stored chain state no longer agrees with the one lightwalletd is
    /// serving. Recovery is to `truncate_to_height(at_height - REWIND_DISTANCE)`
    /// and restart the scan loop from the rewound state.
    Continuity { at_height: u64, detail: String },

    /// Transient network or gRPC failure. The existing exponential-backoff
    /// retry path is the right response.
    Network(String),

    /// Local SQLite / `WalletDb` failure. Usually non-retryable (permissions,
    /// disk full, schema corruption) — propagate up and let the caller decide.
    Db(String),

    /// Serialization / deserialization failure for a compact block, tree
    /// state, transaction, or similar on-wire structure. Non-retryable
    /// because re-fetching the same bytes is unlikely to parse differently.
    Parse(String),

    /// Unclassified error. Treated as transient by default (retry-with-backoff)
    /// so we fail safe toward "try again" rather than "bail out".
    Other(String),
}

/// Strategy the sync loop should apply when it encounters a `SyncError`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum RecoveryStrategy {
    /// Retry the failing operation after exponential backoff. The outer
    /// `run_sync_inner` wrapper already implements this with a 3-retry,
    /// 2s/4s/8s schedule.
    RetryWithBackoff,

    /// Rewind the wallet's chain state to `to_height` (via
    /// `WalletDb::truncate_to_height`) and restart the scan loop. Used for
    /// continuity errors.
    Rewind { to_height: u64 },

    /// No automatic recovery is safe. Propagate the error up to the caller.
    Fatal,
}

/// Number of blocks the wallet rewinds past a detected reorg. Matches
/// `CompactBlockProcessor.REWIND_DISTANCE` in zcash-android-wallet-sdk.
///
/// The actual rewind height may land earlier than `at_height - REWIND_DISTANCE`
/// because `truncate_to_height` only accepts checkpoint boundaries; that's
/// librustzcash's responsibility to enforce.
pub(crate) const REWIND_DISTANCE: u64 = 10;

/// Maximum number of reorg-triggered rewinds allowed inside a single
/// `run_sync_impl` invocation. Caps runaway rewind loops: if the chain is
/// flapping fast enough to blow through this budget, `run_sync_impl` bails
/// out so the outer `run_sync_inner` retry wrapper (and eventually the Dart
/// polling loop) can try again with a fresh budget. Without this the same
/// sync run could keep rewinding backward indefinitely.
pub(crate) const MAX_REWINDS_PER_RUN: u32 = 3;

impl SyncError {
    /// Log and construct a `Continuity` error in one step.
    ///
    /// Uses `log::warn!` rather than `log::error!` because a reorg is an
    /// expected, recoverable event — the reorg-recovery path in the scan
    /// loop will rewind the wallet and restart automatically.
    pub(crate) fn continuity(at_height: u64, detail: impl Into<String>) -> Self {
        let detail = detail.into();
        log::warn!("sync: chain continuity broken at height {at_height}: {detail}");
        SyncError::Continuity { at_height, detail }
    }

    /// Log and construct a `Network` error in one step.
    pub(crate) fn net(msg: impl Into<String>) -> Self {
        let msg = msg.into();
        log::error!("sync: {msg}");
        SyncError::Network(msg)
    }

    /// Log and construct a `Db` error in one step.
    pub(crate) fn db(msg: impl Into<String>) -> Self {
        let msg = msg.into();
        log::error!("sync: {msg}");
        SyncError::Db(msg)
    }

    /// Log and construct a `Parse` error in one step.
    pub(crate) fn parse(msg: impl Into<String>) -> Self {
        let msg = msg.into();
        log::error!("sync: {msg}");
        SyncError::Parse(msg)
    }

    /// Log and construct an `Other` error in one step. Used for call sites
    /// that don't fit a specific category (and for `scan_cached_blocks`
    /// fall-through cases that the scan branch didn't classify).
    pub(crate) fn other(msg: impl Into<String>) -> Self {
        let msg = msg.into();
        log::error!("sync: {msg}");
        SyncError::Other(msg)
    }

    /// Whether this error is a chain reorg requiring rewind recovery.
    #[allow(dead_code)] // currently unused outside recovery_strategy itself
    pub(crate) fn is_continuity(&self) -> bool {
        matches!(self, SyncError::Continuity { .. })
    }

    /// Whether the error looks transient and worth retrying via plain backoff
    /// (no rewind, no caller intervention).
    #[allow(dead_code)] // currently unused outside recovery_strategy itself
    pub(crate) fn is_transient(&self) -> bool {
        matches!(self, SyncError::Network(_) | SyncError::Other(_))
    }

    /// The height at which a continuity break was detected, if this is a
    /// `Continuity` error.
    #[allow(dead_code)] // currently unused outside recovery_strategy itself
    pub(crate) fn continuity_height(&self) -> Option<u64> {
        match self {
            SyncError::Continuity { at_height, .. } => Some(*at_height),
            _ => None,
        }
    }

    /// Map this error to the recovery action the sync loop should take.
    pub(crate) fn recovery_strategy(&self) -> RecoveryStrategy {
        match self {
            SyncError::Continuity { at_height, .. } => RecoveryStrategy::Rewind {
                to_height: at_height.saturating_sub(REWIND_DISTANCE),
            },
            SyncError::Network(_) | SyncError::Other(_) => RecoveryStrategy::RetryWithBackoff,
            SyncError::Db(_) | SyncError::Parse(_) => RecoveryStrategy::Fatal,
        }
    }
}

impl fmt::Display for SyncError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SyncError::Continuity { at_height, detail } => {
                write!(f, "chain continuity broken at height {at_height}: {detail}")
            }
            SyncError::Network(msg) => write!(f, "network: {msg}"),
            SyncError::Db(msg) => write!(f, "db: {msg}"),
            SyncError::Parse(msg) => write!(f, "parse: {msg}"),
            SyncError::Other(msg) => write!(f, "other: {msg}"),
        }
    }
}

impl std::error::Error for SyncError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn continuity_reports_its_height_and_classifies_itself() {
        let e = SyncError::Continuity {
            at_height: 2_500_000,
            detail: "prev_hash mismatch".into(),
        };
        assert!(e.is_continuity());
        assert!(!e.is_transient());
        assert_eq!(e.continuity_height(), Some(2_500_000));
    }

    #[test]
    fn network_is_transient_not_continuity() {
        let e = SyncError::Network("connection reset by peer".into());
        assert!(!e.is_continuity());
        assert!(e.is_transient());
        assert_eq!(e.continuity_height(), None);
    }

    #[test]
    fn other_is_transient_as_conservative_default() {
        // `Other` means we couldn't classify — err on the side of retry
        // rather than bailing out.
        let e = SyncError::Other("unknown".into());
        assert!(e.is_transient());
    }

    #[test]
    fn db_and_parse_are_fatal() {
        assert_eq!(
            SyncError::Db("disk full".into()).recovery_strategy(),
            RecoveryStrategy::Fatal,
        );
        assert_eq!(
            SyncError::Parse("bad tree state".into()).recovery_strategy(),
            RecoveryStrategy::Fatal,
        );
    }

    #[test]
    fn network_and_other_recover_via_backoff() {
        assert_eq!(
            SyncError::Network("timeout".into()).recovery_strategy(),
            RecoveryStrategy::RetryWithBackoff,
        );
        assert_eq!(
            SyncError::Other("???".into()).recovery_strategy(),
            RecoveryStrategy::RetryWithBackoff,
        );
    }

    #[test]
    fn continuity_recovery_rewinds_by_the_fixed_distance() {
        let e = SyncError::Continuity {
            at_height: 2_500_000,
            detail: String::new(),
        };
        assert_eq!(
            e.recovery_strategy(),
            RecoveryStrategy::Rewind {
                to_height: 2_500_000 - REWIND_DISTANCE,
            },
        );
    }

    #[test]
    fn continuity_rewind_does_not_underflow_near_genesis() {
        // Pathological: reorg detected at a height smaller than
        // REWIND_DISTANCE. The target should clamp at 0 rather than panic
        // or wrap around.
        let e = SyncError::Continuity {
            at_height: 5,
            detail: String::new(),
        };
        assert_eq!(
            e.recovery_strategy(),
            RecoveryStrategy::Rewind { to_height: 0 },
        );
    }

    #[test]
    fn display_includes_height_and_detail_for_continuity() {
        let e = SyncError::Continuity {
            at_height: 2_500_000,
            detail: "prev_hash mismatch".into(),
        };
        let s = format!("{e}");
        assert!(s.contains("2500000"), "display should include height: {s}");
        assert!(s.contains("prev_hash mismatch"), "display should include detail: {s}");
    }

    #[test]
    fn display_tags_other_variants_distinctly() {
        assert!(format!("{}", SyncError::Network("x".into())).starts_with("network: "));
        assert!(format!("{}", SyncError::Db("x".into())).starts_with("db: "));
        assert!(format!("{}", SyncError::Parse("x".into())).starts_with("parse: "));
        assert!(format!("{}", SyncError::Other("x".into())).starts_with("other: "));
    }

    #[test]
    fn rewind_budget_is_nonzero_and_small() {
        // If MAX_REWINDS_PER_RUN gets set to 0 the loop would bail on the
        // first reorg, defeating the fix. If it gets cranked absurdly high
        // the loop could spin forever against a flapping chain. 3 matches
        // Zashi's REWIND_DISTANCE usage pattern (bounded, room to recover
        // across a handful of quick reorgs).
        assert!(MAX_REWINDS_PER_RUN >= 1);
        assert!(MAX_REWINDS_PER_RUN <= 10);
    }

    #[test]
    fn continuity_constructor_records_height_and_detail() {
        // Exercise the `SyncError::continuity` constructor the
        // `scan_cached_blocks` call site uses. The recovery loop matches
        // against this variant to decide whether to rewind.
        let e = SyncError::continuity(2_500_000, "prev_hash mismatch at 2500000");
        assert!(e.is_continuity());
        assert_eq!(e.continuity_height(), Some(2_500_000));
        match &e {
            SyncError::Continuity { at_height, detail } => {
                assert_eq!(*at_height, 2_500_000);
                assert_eq!(detail, "prev_hash mismatch at 2500000");
            }
            other => panic!("expected Continuity, got {other:?}"),
        }
        // And the recovery strategy should rewind 10 blocks back from the
        // detected height.
        assert_eq!(
            e.recovery_strategy(),
            RecoveryStrategy::Rewind {
                to_height: 2_500_000 - REWIND_DISTANCE,
            },
        );
    }
}
