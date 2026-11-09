/// The user's choice to use Zcash Name Service (ZNS) names.
///
/// Names are off until the user turns them on in Settings. While they are
/// off the wallet makes no request to a ZNS resolver: a name typed into a
/// recipient or contact field only says where to turn names on.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kZnsNamesEnabledStorageKey = 'vizor_zns_names_enabled';

/// Persists whether Zcash names are on.
abstract interface class ZnsNamesSettingStore {
  Future<bool> readEnabled();

  Future<void> writeEnabled(bool enabled);
}

class SharedPreferencesZnsNamesSettingStore implements ZnsNamesSettingStore {
  const SharedPreferencesZnsNamesSettingStore();

  @override
  Future<bool> readEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kZnsNamesEnabledStorageKey) ?? false;
  }

  @override
  Future<void> writeEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(
      kZnsNamesEnabledStorageKey,
      enabled,
    );
    if (!saved) {
      throw StateError('Could not save the Zcash names setting.');
    }
  }
}

/// Overridable in tests; production writes go to shared preferences.
final znsNamesSettingStoreProvider = Provider<ZnsNamesSettingStore>(
  (_) => const SharedPreferencesZnsNamesSettingStore(),
);

/// Loads and updates the Zcash names setting.
class ZnsNamesEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    try {
      return await ref.watch(znsNamesSettingStoreProvider).readEnabled();
    } catch (error) {
      debugPrint('[zcash] ZNS: failed to load the names setting: $error');
      return false;
    }
  }

  /// Persists [enabled] before publishing it, so a failed write leaves names
  /// as they were.
  Future<void> setEnabled(bool enabled) async {
    if (state.value == enabled) return;
    await ref.read(znsNamesSettingStoreProvider).writeEnabled(enabled);
    state = AsyncData(enabled);
  }
}

final znsNamesEnabledProvider =
    AsyncNotifierProvider<ZnsNamesEnabledNotifier, bool>(
      ZnsNamesEnabledNotifier.new,
    );

/// Whether Zcash names are on right now. Off while the setting loads or
/// when it could not be read.
final znsNamesOnProvider = Provider<bool>(
  (ref) => ref.watch(znsNamesEnabledProvider).value ?? false,
);
