import '../../../core/l10n/l10n.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

/// Home's transparent balance: the current amount, a last-known amount marked
/// as such, an explicit unavailable state, or a stopped private recovery with
/// what the user can do about it. Unknown funds never read as 0.
class TransparentBalanceDisplay {
  const TransparentBalanceDisplay._(this.amount, this.authority, [this.stop]);

  factory TransparentBalanceDisplay.of(SyncState sync) {
    return switch (sync.transparentAuthority) {
      // Funds a pending spend holds stay in the row, as in the total.
      rust_sync.TransparentBalanceAuthority.current =>
        TransparentBalanceDisplay._(
          sync.transparentBalance +
              sync.transparentPendingBalance +
              sync.transparentLockedBalance,
          rust_sync.TransparentBalanceAuthority.current,
        ),
      rust_sync.TransparentBalanceAuthority.lastKnown =>
        TransparentBalanceDisplay._(
          sync.transparentLastKnownBalance,
          rust_sync.TransparentBalanceAuthority.lastKnown,
        ),
      rust_sync.TransparentBalanceAuthority.unavailable =>
        const TransparentBalanceDisplay._(
          null,
          rust_sync.TransparentBalanceAuthority.unavailable,
        ),
      rust_sync.TransparentBalanceAuthority.stopped =>
        TransparentBalanceDisplay._(
          sync.transparentLastKnownBalance,
          rust_sync.TransparentBalanceAuthority.stopped,
          sync.transparentStop,
        ),
    };
  }

  /// The amount to show, or null when it is unknown. Only a `current` amount
  /// is spendable.
  final BigInt? amount;
  final rust_sync.TransparentBalanceAuthority authority;

  /// Why private recovery stopped, when [authority] is `stopped`.
  final rust_sync.TransparentStopReason? stop;

  /// Whether Home shows the transparent row. An unknown balance or a stopped
  /// recovery is shown so the user sees that transparent funds are
  /// unavailable.
  bool get visible => switch (authority) {
    rust_sync.TransparentBalanceAuthority.unavailable ||
    rust_sync.TransparentBalanceAuthority.stopped => true,
    _ => (amount ?? BigInt.zero) > BigInt.zero,
  };

  /// Row text, with [format] rendering a known amount.
  String text(AppLocalizations l10n, String Function(BigInt) format) =>
      switch (authority) {
        rust_sync.TransparentBalanceAuthority.current => format(amount!),
        rust_sync.TransparentBalanceAuthority.lastKnown =>
          l10n.homeTransparentLastKnown(format(amount ?? BigInt.zero)),
        rust_sync.TransparentBalanceAuthority.unavailable =>
          l10n.homeTransparentUnavailable,
        rust_sync.TransparentBalanceAuthority.stopped => switch (amount) {
          final amount? => l10n.homeTransparentLastKnownStopped(format(amount)),
          null => l10n.homeTransparentRecoveryStopped,
        },
      };

  /// Why recovery stopped and what the user can do about it, or null when it
  /// has not stopped.
  String? hint(AppLocalizations l10n) => switch (stop) {
    null => null,
    rust_sync.TransparentStopReason.quarantined =>
      l10n.homeTransparentStopQuarantined,
    rust_sync.TransparentStopReason.legacyDiscrepancy =>
      l10n.homeTransparentStopLegacyDiscrepancy,
    rust_sync.TransparentStopReason.withdrawn =>
      l10n.homeTransparentStopWithdrawn,
    rust_sync.TransparentStopReason.stalled => l10n.homeTransparentStopStalled,
    rust_sync.TransparentStopReason.optOutUnfinished =>
      l10n.homeTransparentStopOptOutUnfinished,
  };
}
