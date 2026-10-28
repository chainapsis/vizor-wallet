/// Rust refuses new migrations and transactions in the last blocks before a
/// network upgrade; the same action works again once it activates.
const kNetworkUpgradeHoldMessage =
    'Paused for the network upgrade. Try again in a few minutes.';

/// [kNetworkUpgradeHoldMessage] for Rust's upgrade hold errors.
String? networkUpgradeHoldMessage(Object error) =>
    error.toString().contains('this close to the network upgrade')
    ? kNetworkUpgradeHoldMessage
    : null;

/// Label for an action held until the upgrade activates.
const kNetworkUpgradeHoldActionLabel = 'Paused for network upgrade';
