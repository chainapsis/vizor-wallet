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
