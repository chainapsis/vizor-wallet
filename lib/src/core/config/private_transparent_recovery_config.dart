/// Development builds pass
/// --dart-define=ZCASH_PRIVATE_TRANSPARENT_RECOVERY=true so that "Private
/// queries" on mainnet also recovers transparent funds privately. Default
/// builds keep public transparent lookups and never raise a wallet's
/// transparent policy; turning the setting off still lowers one.
const kZcashPrivateTransparentRecoveryEnvKey =
    'ZCASH_PRIVATE_TRANSPARENT_RECOVERY';
const kZcashPrivateTransparentRecovery = bool.fromEnvironment(
  kZcashPrivateTransparentRecoveryEnvKey,
  defaultValue: false,
);

/// What "Private queries" adds in a build with the flag. Transparent funds
/// have no authority between turning it on and the first private recovery,
/// and Ledger accounts are paused rather than recovered privately.
const kPrivateTransparentRecoverySettingsCopy =
    'Also recovers transparent funds privately. Transparent funds stay '
    'unavailable until private recovery completes; Ledger transparent funds '
    'are not recovered privately.';

/// The "Private queries" [description], with what the setting does to
/// transparent funds in a build whose flag is [privateTransparentRecovery].
String privateQueriesDescription(
  String description, {
  bool privateTransparentRecovery = kZcashPrivateTransparentRecovery,
}) => privateTransparentRecovery
    ? '$description $kPrivateTransparentRecoverySettingsCopy'
    : description;
