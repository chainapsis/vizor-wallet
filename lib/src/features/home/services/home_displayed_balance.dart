import '../../../providers/sync_provider.dart';

/// The balance Home's card shows for an account: its shielded holdings, or,
/// once a migration is running or complete ([ironwoodOnly]), those holdings
/// without the Orchard funds the migration moves (Home lists those as still
/// migrating). Sapling funds stay in both: the migration leaves them where
/// they are, and Send and Swap count them as available.
///
/// Desktop Home, mobile Home and the desktop sidebar all show this value, so
/// they cannot disagree.
/// Transparent funds and funds a pending transaction holds are not part of
/// it.
BigInt homeDisplayedBalance(SyncState sync, {required bool ironwoodOnly}) {
  if (!ironwoodOnly) return sync.displayShieldedBalance;
  final withoutOrchard =
      sync.displayShieldedBalance -
      sync.displayOrchardBalance -
      sync.displayOrchardPendingBalance;
  return withoutOrchard < BigInt.zero ? BigInt.zero : withoutOrchard;
}
