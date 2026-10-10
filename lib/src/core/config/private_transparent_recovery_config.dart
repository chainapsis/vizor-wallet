/// What private queries adds to supported mainnet transparent recovery.
/// Transparent funds are unavailable until recovery completes; Ledger
/// accounts are paused rather than recovered privately.
const kPrivateTransparentRecoverySettingsCopy =
    'Also recovers transparent funds privately. Transparent funds stay '
    'unavailable until private recovery completes; Ledger transparent funds '
    'are not recovered privately.';

/// Includes transparent recovery in the private queries disclosure.
String privateQueriesDescription(String description) =>
    '$description $kPrivateTransparentRecoverySettingsCopy';
