import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import 'home_displayed_balance.dart';
import 'transparent_balance_display.dart';

/// The balance Home's card and the desktop sidebar show for an account
/// ([homeDisplayedBalance]), and the holdings that number leaves out.
///
/// The parts come from the sync state's display fields, never from a
/// difference against its total, so a stale total cannot appear as funds on
/// hold.
class AccountBalanceBreakdown {
  const AccountBalanceBreakdown._({
    required this.ironwoodOnly,
    required this.headline,
    required this.transparent,
    required this.migrating,
    required this.onHold,
  });

  /// [ironwoodOnly] is whether Home presents only the Ironwood pool, as it
  /// does once a migration is running or complete.
  factory AccountBalanceBreakdown.of(
    SyncState sync, {
    required bool ironwoodOnly,
  }) {
    final transparent = TransparentBalanceDisplay.of(sync);
    final locked = sync.displayShieldedLockedBalance;
    // A migration's locked Orchard notes are part of what is still migrating.
    final onHold = ironwoodOnly
        ? locked - sync.displayOrchardLockedBalance
        : locked;
    return AccountBalanceBreakdown._(
      ironwoodOnly: ironwoodOnly,
      headline: homeDisplayedBalance(sync, ironwoodOnly: ironwoodOnly),
      transparent:
          transparent.authority == rust_sync.TransparentBalanceAuthority.current
          ? transparent.amount ?? BigInt.zero
          : BigInt.zero,
      migrating: ironwoodOnly
          ? sync.displayOrchardHoldingsBalance
          : BigInt.zero,
      onHold: onHold < BigInt.zero ? BigInt.zero : onHold,
    );
  }

  /// Whether [headline] is the Ironwood pool alone.
  final bool ironwoodOnly;

  /// What Home's balance card and the sidebar show.
  final BigInt headline;

  /// Transparent funds, counted only while their amount is current.
  final BigInt transparent;

  /// Orchard holdings while Home shows Ironwood only; zero otherwise.
  final BigInt migrating;

  /// Shielded funds a pending transaction holds, apart from [migrating].
  final BigInt onHold;

  /// Whether the account holds anything [headline] leaves out.
  bool get hasMore =>
      transparent > BigInt.zero ||
      migrating > BigInt.zero ||
      onHold > BigInt.zero;

  @override
  bool operator ==(Object other) =>
      other is AccountBalanceBreakdown &&
      other.ironwoodOnly == ironwoodOnly &&
      other.headline == headline &&
      other.transparent == transparent &&
      other.migrating == migrating &&
      other.onHold == onHold;

  @override
  int get hashCode =>
      Object.hash(ironwoodOnly, headline, transparent, migrating, onHold);
}
