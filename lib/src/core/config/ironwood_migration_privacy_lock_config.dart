import 'package:flutter/foundation.dart' show kDebugMode;

const kIronwoodMigrationPrivacyLockDebugFlag =
    'VIZOR_IRONWOOD_MIGRATION_PRIVACY_LOCK';

const _debugPrivacyLockEnabled = bool.fromEnvironment(
  kIronwoodMigrationPrivacyLockDebugFlag,
);

/// The unattended-migration privacy lock is mandatory in production builds.
///
/// Debug builds opt in explicitly so ordinary widget and integration tests do
/// not acquire a one-minute global idle timer merely because they exercise an
/// in-progress migration state.
const kIronwoodMigrationPrivacyLockEnabled =
    !kDebugMode || _debugPrivacyLockEnabled;

bool resolveIronwoodMigrationPrivacyLockEnabled({
  required bool debugMode,
  required bool debugFlagEnabled,
}) {
  return !debugMode || debugFlagEnabled;
}
