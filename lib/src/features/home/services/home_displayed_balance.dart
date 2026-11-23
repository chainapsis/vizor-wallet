import '../../../providers/sync_provider.dart';

/// The balance Home's card shows for an account: its shielded funds in every
/// pool. That includes Sapling funds and Orchard funds a migration is still
/// moving, which Home also lists as still migrating, so the number does not
/// drop while funds move.
///
/// Desktop Home, mobile Home and the desktop sidebar all show this value, so
/// they cannot disagree. Transparent funds and funds a pending transaction
/// holds are not part of it.
BigInt homeDisplayedBalance(SyncState sync) => sync.displayShieldedBalance;
