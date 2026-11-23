import '../../../providers/sync_provider.dart';
import '../../migration/providers/ironwood_migration_announcement_provider.dart';

/// The balance Home's card shows for an account.
///
/// - Normally, every shielded pool.
/// - While a migration is required, the Orchard funds it will move.
/// - Once a migration is running or complete, every shielded pool except the
///   Orchard funds still moving, which Home lists as still migrating. Sapling
///   funds stay in: the migration does not move them.
///
/// Desktop Home, mobile Home and the desktop sidebar all show this value, so
/// they cannot disagree. Transparent funds and funds a pending transaction
/// holds are not part of it.
BigInt homeDisplayedBalance(
  SyncState sync,
  IronwoodHomeBalancePresentationMode mode,
) {
  final orchard =
      sync.displayOrchardBalance + sync.displayOrchardPendingBalance;
  switch (mode) {
    case IronwoodHomeBalancePresentationMode.allShielded:
      return sync.displayShieldedBalance;
    case IronwoodHomeBalancePresentationMode.orchardOnly:
      return orchard;
    case IronwoodHomeBalancePresentationMode.ironwoodAndSapling:
      final rest = sync.displayShieldedBalance - orchard;
      return rest < BigInt.zero ? BigInt.zero : rest;
  }
}
