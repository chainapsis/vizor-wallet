import 'package:shared_preferences/shared_preferences.dart';

/// Install-scoped preference key for private queries.
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
        throw StateError('Could not save the private queries setting.');
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

/// Install-scoped marker of an explicit private queries opt-out whose
/// transparent lowering has not finished yet.
///
/// Written before the wallet's durable transparent policy is lowered and
/// cleared only once the lowering succeeded, so an opt-out the app did not
/// live to finish is retried at the next launch. Kept beside the preference,
/// outside the secure-store bucket a wallet reset wipes, for the same reason.
const kTransparentOptOutPendingKey = 'zcash_transparent_opt_out_pending';

abstract interface class TransparentOptOutStore {
  /// Whether an opt-out is pending; `false` when never written. Throws when
  /// the marker cannot be read, which callers treat as unknown: an unknown
  /// state never lowers the wallet's policy.
  Future<bool> readPending();

  Future<void> writePending(bool pending);
}

class SharedPreferencesTransparentOptOutStore
    implements TransparentOptOutStore {
  const SharedPreferencesTransparentOptOutStore();

  @override
  Future<bool> readPending() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kTransparentOptOutPendingKey) ?? false;
  }

  @override
  Future<void> writePending(bool pending) async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getBool(kTransparentOptOutPendingKey);
    try {
      final saved = pending
          ? await preferences.setBool(kTransparentOptOutPendingKey, true)
          : await preferences.remove(kTransparentOptOutPendingKey);
      if (!saved) {
        throw StateError('Could not save the private queries opt-out.');
      }
    } catch (_) {
      // SharedPreferences changes its memory cache before the platform write.
      // Restore that cache to the last committed value, so a read in this
      // launch never reports an intent that was not saved.
      try {
        if (previous == null) {
          await preferences.remove(kTransparentOptOutPendingKey);
        } else {
          await preferences.setBool(kTransparentOptOutPendingKey, previous);
        }
      } catch (_) {
        // Preserve the original write failure.
      }
      rethrow;
    }
  }
}
