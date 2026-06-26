import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;

const kZcashLocalTestProfileEnvKey = 'ZCASH_LOCAL_TEST_PROFILE';
const _localTestProfileRaw = String.fromEnvironment(
  kZcashLocalTestProfileEnvKey,
);

String? zcashLocalTestProfile() {
  return normalizeZcashLocalTestProfile(
    _localTestProfileRaw,
    releaseMode: kReleaseMode,
  );
}

String applyLocalTestProfileToServiceName(String serviceName) {
  final profile = zcashLocalTestProfile();
  return profile == null ? serviceName : '$serviceName.local.$profile';
}

@visibleForTesting
String? normalizeZcashLocalTestProfile(
  String raw, {
  required bool releaseMode,
}) {
  if (releaseMode) return null;

  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final normalized = trimmed.toLowerCase();
  final valid = RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$').hasMatch(normalized);
  if (!valid) {
    throw StateError(
      '$kZcashLocalTestProfileEnvKey must start with a letter or digit and '
      'contain only letters, digits, underscores, or hyphens.',
    );
  }

  return normalized;
}
