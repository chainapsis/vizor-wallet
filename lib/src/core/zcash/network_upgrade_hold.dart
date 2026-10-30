/// Rust refuses new migrations and transactions in the last blocks before a
/// network upgrade; the same action works again once it activates.
const kNetworkUpgradeHoldMessage =
    'Paused for the network upgrade. Try again in a few minutes.';

/// Rust refuses to start a migration whose approved schedule was drawn before
/// the upgrade activated; a newly drawn plan can start.
const kNetworkUpgradeScheduleChangedMessage =
    'The network upgrade changed the migration timing. Review the plan and start again.';

/// User copy for Rust's network upgrade refusals: [kNetworkUpgradeHoldMessage]
/// for the hold before an upgrade, [kNetworkUpgradeScheduleChangedMessage] for
/// a migration schedule drawn before it.
String? networkUpgradeHoldMessage(Object error) {
  final text = error.toString();
  if (text.contains('this close to the network upgrade')) {
    return kNetworkUpgradeHoldMessage;
  }
  if (text.contains('drawn before the network upgrade')) {
    return kNetworkUpgradeScheduleChangedMessage;
  }
  return null;
}

/// Label for an action held until the upgrade activates.
const kNetworkUpgradeHoldActionLabel = 'Paused for network upgrade';
