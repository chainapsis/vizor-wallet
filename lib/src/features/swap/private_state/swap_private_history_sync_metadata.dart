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
  });

  final String plaintextHashBase64;
  final DateTime synchronizedAt;
  final PrivateStateVersion? remoteVersion;

  Map<String, Object?> toJson() => {
    'schema': _metadataSchemaVersion,
    'plaintext_hash': plaintextHashBase64,
    'synchronized_at': synchronizedAt.toUtc().toIso8601String(),
    'remote_revision': remoteVersion?.revision.toString(),
    'remote_envelope_hash': remoteVersion?.envelopeHashBase64,
  };

  static SwapPrivateHistorySyncMetadata? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.length != 5 ||
        raw['schema'] != _metadataSchemaVersion) {
      return null;
    }
    const keys = {
      'schema',
      'plaintext_hash',
      'synchronized_at',
      'remote_revision',
      'remote_envelope_hash',
    };
    if (raw.keys.any((key) => !keys.contains(key))) return null;
    final plaintextHash = raw['plaintext_hash'];
    final synchronizedAtRaw = raw['synchronized_at'];
    final revisionRaw = raw['remote_revision'];
    final envelopeHash = raw['remote_envelope_hash'];
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
    );
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

  Future<void> deleteForAccount({required String accountUuid});
}

class AppSecureStoreSwapPrivateHistorySyncMetadataStore
    implements SwapPrivateHistorySyncMetadataStore {
  const AppSecureStoreSwapPrivateHistorySyncMetadataStore(this._storage);

  final AppSecureStore _storage;

  @override
  Future<SwapPrivateHistorySyncMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  }) async {
    final encoded = await _storage.readString(_key(accountUuid, kind));
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
    return _storage.writeString(
      _key(accountUuid, kind),
      jsonEncode(metadata.toJson()),
    );
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    for (final kind in SwapPrivateHistoryKind.values) {
      await _storage.delete(_key(accountUuid, kind));
    }
  }

  static String _key(String accountUuid, SwapPrivateHistoryKind kind) =>
      '$_metadataKeyPrefix:$accountUuid:${kind.wireName}';
}
