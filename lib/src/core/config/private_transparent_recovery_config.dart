import 'package:flutter/foundation.dart';

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

/// Shared private queries description for every platform's settings.
const kPrivateQueriesSettingsCopy =
    'Experimental. Recovers transparent funds privately, preventing the '
    'server from learning your transparent addresses. Looks up supported '
    'transactions without revealing their IDs to servers.';

/// Appended on iOS: background migration tracking cannot run privately, so
/// it stays off while private queries is on.
const kPrivateQueriesIosMigrationCopy =
    'While on, migration confirmations are checked only when Vizor is open.';

/// The private queries description for mobile settings on [platform].
String privateQueriesMobileSettingsCopy(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
    ? '$kPrivateQueriesSettingsCopy $kPrivateQueriesIosMigrationCopy'
    : kPrivateQueriesSettingsCopy;
