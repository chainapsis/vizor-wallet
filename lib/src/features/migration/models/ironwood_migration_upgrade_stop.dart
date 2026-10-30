const kIronwoodUpgradeStopRingMessage = 'Stopped by the\nnetwork upgrade';
// No amount: the review shows the exact figure after fees.
const kIronwoodUpgradeStopMoveRemainingLabel = 'Move remaining balance';
const kIronwoodUpgradeStopBody =
    'Transfers signed before the upgrade can’t be sent after it. Your funds '
    'are safe.';

/// Amounts for a migration that the NU7 upgrade stopped mid-run.
class IronwoodMigrationUpgradeStop {
  const IronwoodMigrationUpgradeStop({
    required this.migratedAmountText,
    required this.remainingAmountText,
    required this.completedParts,
    required this.totalParts,
  });

  final String migratedAmountText;
  final String remainingAmountText;
  final int completedParts;
  final int totalParts;
}
