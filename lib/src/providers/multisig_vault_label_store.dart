import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';

const _multisigVaultLabelKeyPrefix = 'zcash_multisig_vault_labels_v1_';

final multisigVaultLabelStoreProvider = Provider(
  (ref) => MultisigVaultLabelStore(AppSecureStore.instance),
);

/// Participant labels for a finalized vault, decrypted from `vault_label`
/// broadcast messages (sealed under the group-derived metadata key, so the
/// coordinator never sees them). Keyed by `<sessionId>:<participantId>`
/// (the material storage id) and stored encrypted at rest.
class MultisigVaultLabelStore {
  const MultisigVaultLabelStore(this._storage);

  final AppSecureStore _storage;

  Future<Map<String, String>> read(String storageId) async {
    final raw = await _storage.readSecretStringWithOptions(
      _labelKey(storageId),
    );
    if (raw == null || raw.trim().isEmpty) return const <String, String>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const <String, String>{};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  Future<void> setLabels(String storageId, Map<String, String> labels) async {
    if (labels.isEmpty) return;
    final current = {...await read(storageId), ...labels};
    await _storage.writeSecretString(
      _labelKey(storageId),
      jsonEncode(current),
    );
  }

  Future<void> clear(String storageId) {
    return _storage.delete(_labelKey(storageId));
  }

  String _labelKey(String storageId) {
    return '$_multisigVaultLabelKeyPrefix$storageId';
  }
}
