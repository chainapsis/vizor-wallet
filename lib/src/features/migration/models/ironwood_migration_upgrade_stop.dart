const kIronwoodUpgradeStopRingMessage = 'Stopped by the\nnetwork upgrade';
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

  String get moveRemainingLabel => 'Move remaining $remainingAmountText';
}
