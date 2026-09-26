import 'package:shared_preferences/shared_preferences.dart';

/// Install-scoped preference key for private Ironwood recovery.
///
/// This lives in [SharedPreferences] rather than the `AppSecureStore`
/// plaintext lane on purpose: the secure-store bucket is wiped wholesale by
/// `AppSecureStore.deleteAll()` during a wallet reset, which would drop the
/// user's choice every time a wallet is reset and reimported. The setting
/// describes how this installation talks to the network, not what a particular
/// wallet holds, so it is deliberately retained across wallet resets.
const kEnhancePirEnabledPreferenceKey = 'zcash_enhance_pir_enabled';

/// Legacy secure-store key the preference used before it became install-scoped.
/// Read once at bootstrap so an upgrading install keeps its existing choice.
const kLegacyEnhancePirEnabledKey = 'vizor_enhance_pir_enabled';

abstract interface class EnhancePirPreferenceStore {
  /// Returns `null` when the preference has never been written, so callers can
  /// tell "never set" from "explicitly off" and run the legacy migration only
  /// while it is still needed.
  Future<bool?> readEnabled();

  Future<void> writeEnabled(bool enabled);
}

class SharedPreferencesEnhancePirStore implements EnhancePirPreferenceStore {
  const SharedPreferencesEnhancePirStore();

  @override
  Future<bool?> readEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kEnhancePirEnabledPreferenceKey);
  }

  @override
  Future<void> writeEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getBool(kEnhancePirEnabledPreferenceKey);
    try {
      final saved = await preferences.setBool(
        kEnhancePirEnabledPreferenceKey,
        enabled,
      );
      if (!saved) {
        throw StateError(
          'Could not save the private Ironwood recovery setting.',
        );
      }
    } catch (_) {
      // SharedPreferences changes its memory cache before the platform write.
      // Restore that cache as well as the last committed value on failure.
      try {
        if (previous == null) {
          await preferences.remove(kEnhancePirEnabledPreferenceKey);
        } else {
          await preferences.setBool(kEnhancePirEnabledPreferenceKey, previous);
        }
      } catch (_) {
        // Preserve the original write failure; the visible/Rust mode is unchanged.
      }
      rethrow;
    }
  }
}
