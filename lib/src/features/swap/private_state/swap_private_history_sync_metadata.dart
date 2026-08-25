import 'dart:async';
import 'dart:convert';

import '../../../core/storage/app_secure_store.dart';
import '../../../core/private_state_sync/private_state_models.dart';
import 'swap_private_history_document.dart';

const _metadataSchemaVersion = 1;
const _metadataKeyPrefix = 'zcash_private_history_sync_v1';

class SwapPrivateHistorySyncMetadata {
  const SwapPrivateHistorySyncMetadata({
    required this.plaintextHashBase64,
    required this.synchronizedAt,
    this.remoteVersion,
    this.tombstones = const {},
  });

  final String plaintextHashBase64;
  final DateTime synchronizedAt;
  final PrivateStateVersion? remoteVersion;
  final Map<String, DateTime> tombstones;

  Map<String, Object?> toJson() => {
    'schema': _metadataSchemaVersion,
    'plaintext_hash': plaintextHashBase64,
    'synchronized_at': synchronizedAt.toUtc().toIso8601String(),
    'remote_revision': remoteVersion?.revision.toString(),
    'remote_envelope_hash': remoteVersion?.envelopeHashBase64,
    'tombstones': {
      for (final entry in tombstones.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
    },
  };

  static SwapPrivateHistorySyncMetadata? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        (raw.length != 5 && raw.length != 6) ||
        raw['schema'] != _metadataSchemaVersion) {
      return null;
    }
    const keys = {
      'schema',
      'plaintext_hash',
      'synchronized_at',
      'remote_revision',
      'remote_envelope_hash',
      'tombstones',
    };
    if (raw.keys.any((key) => !keys.contains(key))) return null;
    final plaintextHash = raw['plaintext_hash'];
    final synchronizedAtRaw = raw['synchronized_at'];
    final revisionRaw = raw['remote_revision'];
    final envelopeHash = raw['remote_envelope_hash'];
    final tombstones = _tombstonesFromJson(raw['tombstones']);
    if (tombstones == null) return null;
    if (plaintextHash is! String ||
        plaintextHash.isEmpty ||
        synchronizedAtRaw is! String) {
      return null;
    }
    final synchronizedAt = DateTime.tryParse(synchronizedAtRaw)?.toUtc();
    if (synchronizedAt == null) return null;
    if (revisionRaw == null && envelopeHash == null) {
      return SwapPrivateHistorySyncMetadata(
        plaintextHashBase64: plaintextHash,
        synchronizedAt: synchronizedAt,
        tombstones: tombstones,
      );
    }
    if (revisionRaw is! String || envelopeHash is! String) return null;
    final revision = BigInt.tryParse(revisionRaw);
    if (revision == null || revision < BigInt.one || envelopeHash.isEmpty) {
      return null;
    }
    return SwapPrivateHistorySyncMetadata(
      plaintextHashBase64: plaintextHash,
      synchronizedAt: synchronizedAt,
      remoteVersion: PrivateStateVersion(
        revision: revision,
        envelopeHashBase64: envelopeHash,
      ),
      tombstones: tombstones,
    );
  }

  static Map<String, DateTime>? _tombstonesFromJson(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map<String, dynamic> || raw.length > 2048) return null;
    final result = <String, DateTime>{};
    for (final entry in raw.entries) {
      if (entry.key.trim().isEmpty || entry.value is! String) return null;
      final deletedAt = DateTime.tryParse(entry.value as String)?.toUtc();
      if (deletedAt == null) return null;
      result[entry.key] = deletedAt;
    }
    return result;
  }
}

abstract interface class SwapPrivateHistorySyncMetadataStore {
  Future<SwapPrivateHistorySyncMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  });

  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required SwapPrivateHistorySyncMetadata metadata,
  });

  Future<void> addTombstones({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required Map<String, DateTime> tombstones,
  });

  Future<void> deleteForAccount({required String accountUuid});
}

class AppSecureStoreSwapPrivateHistorySyncMetadataStore
    implements SwapPrivateHistorySyncMetadataStore {
  AppSecureStoreSwapPrivateHistorySyncMetadataStore(this._storage);

  final AppSecureStore _storage;
  final Map<String, Future<void>> _mutationTails = {};

  @override
  Future<SwapPrivateHistorySyncMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  }) async {
    return _load(_key(accountUuid, kind));
  }

  Future<SwapPrivateHistorySyncMetadata?> _load(String key) async {
    final encoded = await _storage.readString(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return SwapPrivateHistorySyncMetadata.fromJson(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required SwapPrivateHistorySyncMetadata metadata,
  }) {
    final key = _key(accountUuid, kind);
    return _serialize(key, () async {
      final current = await _load(key);
      final merged = _mergeTombstones(
        current?.tombstones ?? const {},
        metadata.tombstones,
      );
      _validateTombstoneCount(merged);
      await _storage.writeString(
        key,
        jsonEncode(
          SwapPrivateHistorySyncMetadata(
            plaintextHashBase64: metadata.plaintextHashBase64,
            synchronizedAt: metadata.synchronizedAt,
            remoteVersion: metadata.remoteVersion,
            tombstones: merged,
          ).toJson(),
        ),
      );
    });
  }

  @override
  Future<void> addTombstones({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required Map<String, DateTime> tombstones,
  }) {
    if (tombstones.isEmpty) return Future.value();
    final key = _key(accountUuid, kind);
    return _serialize(key, () async {
      final current = await _load(key);
      final merged = _mergeTombstones(
        current?.tombstones ?? const {},
        tombstones,
      );
      _validateTombstoneCount(merged);
      await _storage.writeString(
        key,
        jsonEncode(
          SwapPrivateHistorySyncMetadata(
            plaintextHashBase64: current?.plaintextHashBase64 ?? 'pending',
            synchronizedAt: current?.synchronizedAt ?? DateTime.now().toUtc(),
            remoteVersion: current?.remoteVersion,
            tombstones: merged,
          ).toJson(),
        ),
      );
    });
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    for (final kind in SwapPrivateHistoryKind.values) {
      await _storage.delete(_key(accountUuid, kind));
    }
  }

  static String _key(String accountUuid, SwapPrivateHistoryKind kind) =>
      '$_metadataKeyPrefix:$accountUuid:${kind.wireName}';

  Future<T> _serialize<T>(String key, Future<T> Function() action) async {
    final previous = _mutationTails[key] ?? Future.value();
    final turn = Completer<void>();
    _mutationTails[key] = turn.future;
    try {
      try {
        await previous;
      } on Object {
        // A failed metadata mutation must not poison later tombstones.
      }
      return await action();
    } finally {
      turn.complete();
      if (identical(_mutationTails[key], turn.future)) {
        _mutationTails.remove(key);
      }
    }
  }
}

Map<String, DateTime> _mergeTombstones(
  Map<String, DateTime> left,
  Map<String, DateTime> right,
) {
  final merged = Map<String, DateTime>.of(left);
  for (final entry in right.entries) {
    final existing = merged[entry.key];
    if (existing == null || entry.value.isAfter(existing)) {
      merged[entry.key] = entry.value.toUtc();
    }
  }
  return merged;
}

void _validateTombstoneCount(Map<String, DateTime> tombstones) {
  if (tombstones.length > 2048) {
    throw StateError('Private history tombstone limit exceeded.');
  }
}
