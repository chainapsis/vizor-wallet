import '../l10n/l10n.dart';

/// Rust's network upgrade refusals.
enum NetworkUpgradeHold {
  /// Rust refuses new migrations and transactions in the last blocks before a
  /// network upgrade; the same action works again once it activates.
  hold,

  /// Rust refuses to start a migration whose approved schedule was drawn before
  /// the upgrade activated; a newly drawn plan can start.
  scheduleChanged;

  String message(AppLocalizations l10n) => switch (this) {
    NetworkUpgradeHold.hold => l10n.sendPaymentRequestCheckUpgradeHold,
    NetworkUpgradeHold.scheduleChanged =>
      l10n.sendPaymentRequestCheckUpgradeScheduleChanged,
  };
}

/// Classifies Rust's network upgrade refusals; null for any other error.
NetworkUpgradeHold? networkUpgradeHoldKind(Object error) {
  final text = error.toString();
  if (text.contains('this close to the network upgrade')) {
    return NetworkUpgradeHold.hold;
  }
  if (text.contains('drawn before the network upgrade')) {
    return NetworkUpgradeHold.scheduleChanged;
  }
  return null;
}

/// User copy for Rust's network upgrade refusals, or null for other errors.
String? networkUpgradeHoldMessage(AppLocalizations l10n, Object error) =>
    networkUpgradeHoldKind(error)?.message(l10n);

/// User copy for the hold before an upgrade.
String networkUpgradeHoldText(AppLocalizations l10n) =>
    NetworkUpgradeHold.hold.message(l10n);

/// Label for an action held until the upgrade activates.
String networkUpgradeHoldActionLabel(AppLocalizations l10n) =>
    l10n.commonPausedForNetworkUpgrade;
