import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

/// Home's transparent balance: the current amount, a last-known amount marked
/// as such, an explicit unavailable state, or a stopped private recovery with
/// what the user can do about it. Unknown funds never read as 0.
class TransparentBalanceDisplay {
  const TransparentBalanceDisplay._(this.amount, this.authority, [this.stop]);

  factory TransparentBalanceDisplay.of(SyncState sync) {
    return switch (sync.transparentAuthority) {
      rust_sync.TransparentBalanceAuthority.current =>
        TransparentBalanceDisplay._(
          sync.transparentBalance + sync.transparentPendingBalance,
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
  String text(String Function(BigInt) format) => switch (authority) {
    rust_sync.TransparentBalanceAuthority.current => format(amount!),
    rust_sync.TransparentBalanceAuthority.lastKnown =>
      '${format(amount ?? BigInt.zero)} (last known)',
    rust_sync.TransparentBalanceAuthority.unavailable => 'Unavailable',
    rust_sync.TransparentBalanceAuthority.stopped => switch (amount) {
      final amount? => '${format(amount)} (last known, recovery stopped)',
      null => 'Recovery stopped',
    },
  };

  /// Why recovery stopped and what the user can do about it, or null when it
  /// has not stopped.
  String? get hint => switch (stop) {
    null => null,
    rust_sync.TransparentStopReason.quarantined =>
      'Private recovery found conflicting records for this account. Turn off '
          'Private queries to restore public lookups.',
    rust_sync.TransparentStopReason.ledger =>
      'Ledger transparent funds are not recovered privately. Turn off Private '
          'queries to restore public lookups.',
    rust_sync.TransparentStopReason.legacyDiscrepancy =>
      "Earlier public records don't match private recovery. Turn off Private "
          'queries to restore public lookups.',
    rust_sync.TransparentStopReason.withdrawn =>
      'The private recovery service withdrew data for this account. Vizor '
          'will try again later.',
    rust_sync.TransparentStopReason.stalled =>
      "Private recovery can't make progress for this account. Vizor will try "
          'again later.',
    rust_sync.TransparentStopReason.notSelected =>
      'Private transparent recovery is not available in this build. Turn off '
          'Private queries to restore public lookups. If it is already off, '
          'turn it on and then off.',
  };
}
