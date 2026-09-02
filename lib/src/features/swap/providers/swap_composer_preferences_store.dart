import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/swap_models.dart';

const _swapComposerPreferencesKey = 'zcash_swap_composer_preferences_v1';

String _swapComposerPreferencesKeyFor(String accountUuid) =>
    '$_swapComposerPreferencesKey:$accountUuid';

final swapComposerPreferencesStoreProvider =
    Provider<SwapComposerPreferencesStore>((ref) {
      return AppSecureStoreSwapComposerPreferencesStore(
        AppSecureStore.instance,
      );
    });

abstract interface class SwapComposerPreferencesStore {
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  });

  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  });
}

class AppSecureStoreSwapComposerPreferencesStore
    implements SwapComposerPreferencesStore {
  const AppSecureStoreSwapComposerPreferencesStore(this._storage);

  final AppSecureStore _storage;

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async {
    final raw = await _storage.readString(
      _swapComposerPreferencesKeyFor(accountUuid),
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return _preferencesFromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {
    await _storage.writeString(
      _swapComposerPreferencesKeyFor(accountUuid),
      jsonEncode(_preferencesToJson(preferences)),
    );
  }
}

Map<String, Object?> _preferencesToJson(SwapComposerPreferences preferences) {
  return {
    'direction': preferences.direction.name,
    'externalAsset': preferences.externalAsset.toPersistedJson(),
    'slippageBps': preferences.slippageBps,
  };
}

SwapComposerPreferences? _preferencesFromJson(Map<String, dynamic> json) {
  final direction = _optionalEnumByName(
    SwapDirection.values,
    json['direction'],
  );
  final externalAsset = SwapAsset.fromPersistedJson(json['externalAsset']);
  if (direction == null || externalAsset == null) return null;
  if (externalAsset == SwapAsset.zec) return null;
  final slippageBps = _optionalInt(json['slippageBps'])?.clamp(10, 500).toInt();
  return SwapComposerPreferences(
    direction: direction,
    externalAsset: externalAsset,
    slippageBps: slippageBps ?? defaultSwapSlippageBps,
  );
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

T? _optionalEnumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
