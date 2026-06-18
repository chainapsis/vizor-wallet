import 'dart:convert';

const kVizorForceDisableIosMobileSwapEnvKey =
    'VIZOR_FORCE_DISABLE_IOS_MOBILE_SWAP';
const kVizorForceDisableIosMobileSwap = bool.fromEnvironment(
  kVizorForceDisableIosMobileSwapEnvKey,
  defaultValue: false,
);

const kSwapEnabledOverrideUrl =
    'https://functions.vizor.cash/static/swap-enabled.json';

const _swapEnabledOverrideStorageKeyPrefix = 'vizor_swap_enabled_override_';

String swapEnabledOverrideStorageKey(String version) {
  return '$_swapEnabledOverrideStorageKeyPrefix$version';
}

bool parseSwapEnabledOverrideForVersion(String body, String version) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded[version] == true;
    }
    if (decoded is Map) {
      return decoded[version] == true;
    }
  } catch (_) {
    return false;
  }
  return false;
}
