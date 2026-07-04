import 'dart:convert';

import '../../../../core/storage/app_secure_store.dart';

/// Durable persistence for in-flight zwap swap recovery material.
///
/// Each entry is the JSON-serialized recovery state for one atomic swap (the
/// `_Settle` fields plus the intent's mutable flags), keyed by the orderbook
/// swap id. This survives an app restart so a swap that was in-flight when the
/// process died can be rehydrated and resumed by `ZwapSwapAdapter.getStatus`
/// instead of being orphaned.
///
/// SECURITY: this store holds joint-note VIEWING keys + adaptor material, not
/// the wallet seed or the orderbook bearer token. Both of those are
/// re-derived / re-authenticated on load (never persisted here). Values are
/// written through the encrypted-secret path, so an unlocked session is
/// required to read them back — which is fine, because resuming a swap needs
/// the account seed (also unlock-gated) anyway.
abstract interface class ZwapIntentStore {
  /// Persist (or overwrite) one swap's recovery material, keyed by [obSwapId].
  Future<void> save(String obSwapId, Map<String, Object?> json);

  /// Load every persisted swap for the active account. Returns the decoded
  /// JSON maps; the caller is responsible for reviving them into intents.
  Future<List<Map<String, dynamic>>> loadAll();

  /// Remove one persisted swap once it reaches a terminal state.
  Future<void> delete(String obSwapId);
}

/// [ZwapIntentStore] backed by [AppSecureStore]. Entries live under a single
/// account-scoped key holding a JSON map of `obSwapId -> recoveryJson`, written
/// as an encrypted secret. The account uuid is resolved lazily per call so the
/// store always reads/writes the currently active account's swaps.
class AppSecureStoreZwapIntentStore implements ZwapIntentStore {
  AppSecureStoreZwapIntentStore({
    required this.storage,
    required this.activeAccountUuid,
  });

  final AppSecureStore storage;

  /// Resolves the active account uuid at call time (null when locked or when no
  /// account is active — in which case the store no-ops rather than throwing).
  final String? Function() activeAccountUuid;

  static const _keyPrefix = 'zcash_zwap_intents_v1';

  String? _storageKey() {
    final uuid = activeAccountUuid();
    if (uuid == null || uuid.isEmpty) return null;
    return '$_keyPrefix:$uuid';
  }

  Future<Map<String, dynamic>> _readMap(String key) async {
    final raw = await storage.readSecretStringWithOptions(
      key,
      requireUnlockedSession: true,
    );
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Corrupt payload — treat as empty; a subsequent save overwrites it.
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> save(String obSwapId, Map<String, Object?> json) async {
    final key = _storageKey();
    if (key == null) return;
    final map = await _readMap(key);
    map[obSwapId] = json;
    await storage.writeSecretString(key, jsonEncode(map));
  }

  @override
  Future<List<Map<String, dynamic>>> loadAll() async {
    final key = _storageKey();
    if (key == null) return const [];
    final map = await _readMap(key);
    return [
      for (final entry in map.values)
        if (entry is Map<String, dynamic>) entry,
    ];
  }

  @override
  Future<void> delete(String obSwapId) async {
    final key = _storageKey();
    if (key == null) return;
    final map = await _readMap(key);
    if (map.remove(obSwapId) == null) return;
    if (map.isEmpty) {
      await storage.delete(key);
    } else {
      await storage.writeSecretString(key, jsonEncode(map));
    }
  }
}
