import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

/// Home's transparent balance: the current amount, a last-known amount marked
/// as such, or an explicit unavailable state. Unknown funds never read as 0.
class TransparentBalanceDisplay {
  const TransparentBalanceDisplay._(this.amount, this.authority);

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
    };
  }

  /// The amount to show, or null when it is unknown.
  final BigInt? amount;
  final rust_sync.TransparentBalanceAuthority authority;

  /// Whether Home shows the transparent row. An unknown balance is shown so
  /// the user sees that transparent funds are unavailable.
  bool get visible => switch (authority) {
    rust_sync.TransparentBalanceAuthority.unavailable => true,
    _ => (amount ?? BigInt.zero) > BigInt.zero,
  };

  /// Row text, with [format] rendering a known amount.
  String text(String Function(BigInt) format) => switch (authority) {
    rust_sync.TransparentBalanceAuthority.current => format(amount!),
    rust_sync.TransparentBalanceAuthority.lastKnown =>
      '${format(amount ?? BigInt.zero)} (last known)',
    rust_sync.TransparentBalanceAuthority.unavailable => 'Unavailable',
  };
}
