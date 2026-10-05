import 'package:flutter/foundation.dart';

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

/// Debug builds only, for the transparent history harness
/// (`scripts/e2e/transparent-history-cases.sh --profile private --flutter
/// desktop`): --dart-define=ZCASH_E2E_PRIVATE_TRANSPARENT_REGTEST=true makes
/// "Private queries" available on regtest, where the harness runs its own
/// transparent PIR service. Off without the define, and constant `false` in
/// profile and release builds. Rust selects private recovery on regtest only
/// under its own debug-only switch, `ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT`.
const kZcashE2ePrivateTransparentRegtestEnvKey =
    'ZCASH_E2E_PRIVATE_TRANSPARENT_REGTEST';
const kZcashE2ePrivateTransparentRegtest =
    kDebugMode &&
    bool.fromEnvironment(
      kZcashE2ePrivateTransparentRegtestEnvKey,
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
