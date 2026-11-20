import '../../../providers/sync_provider.dart';

/// The balance Home's card shows for an account: its shielded holdings, or
/// the Ironwood pool alone once a migration is running or complete
/// ([ironwoodOnly]).
///
/// The desktop sidebar shows this same value, so the two cannot disagree.
/// Transparent funds and funds a pending transaction holds are not part of
/// it.
BigInt homeDisplayedBalance(SyncState sync, {required bool ironwoodOnly}) =>
    ironwoodOnly
    ? sync.displayIronwoodBalance + sync.displayIronwoodPendingBalance
    : sync.displayShieldedBalance;
