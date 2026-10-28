const kIronwoodUpgradeStopRingMessage = 'Stopped by the\nnetwork upgrade';
const kIronwoodUpgradeStopBody =
    'Transfers signed before the upgrade can’t be sent after it. Your funds '
    'are safe.';

/// Migrations cannot start in the last blocks before an upgrade; the same
/// action works again once it activates.
const kIronwoodUpgradeHoldStartMessage =
    'The network upgrade is about to activate. Try again in a few minutes.';

/// [kIronwoodUpgradeHoldStartMessage] for Rust's upgrade hold error.
String? ironwoodUpgradeHoldStartMessage(Object error) =>
    error.toString().contains('this close to the network upgrade')
    ? kIronwoodUpgradeHoldStartMessage
    : null;

/// Amounts for a migration that the NU7 upgrade stopped mid-run.
class IronwoodMigrationUpgradeStop {
  const IronwoodMigrationUpgradeStop({
    required this.migratedAmountText,
    required this.remainingAmountText,
    required this.completedParts,
    required this.totalParts,
    this.amountsHidden = false,
  });

  final String migratedAmountText;
  final String remainingAmountText;
  final int completedParts;
  final int totalParts;

  /// Privacy mode masks the amounts, so the action names no amount either.
  final bool amountsHidden;

  String get moveRemainingLabel => amountsHidden
      ? 'Move remaining balance'
      : 'Move remaining $remainingAmountText';
}
