import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/storage/app_secure_store.dart';
import 'swap_private_history_document.dart';

const _metadataSchemaVersion = 3;
const _legacyMetadataSchemaVersion = 2;
const _metadataKeyPrefix = 'zcash_finalized_activity_archive_v2';
const _maxLocallyHiddenRecords = 2048;

/// Local-only progress for the append-only finalized activity archive.
///
/// [hiddenRecordIds] are deliberately never uploaded. They keep an activity
/// deleted on this installation without deleting it from another device or
/// from recovery storage.
class FinalizedActivityArchiveMetadata {
  const FinalizedActivityArchiveMetadata({
    required this.lastSlot,
    this.hiddenRecordIds = const {},
    this.lastSnapshot,
  });

  final int lastSlot;
  final Set<String> hiddenRecordIds;
  final Uint8List? lastSnapshot;

  Map<String, Object?> toJson() => {
    'schema': _metadataSchemaVersion,
    'last_slot': lastSlot,
    'hidden_record_ids': hiddenRecordIds.toList()..sort(),
    'last_snapshot': lastSnapshot == null ? null : base64Encode(lastSnapshot!),
  };

  static FinalizedActivityArchiveMetadata? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    final schema = raw['schema'];
    final isLegacy = schema == _legacyMetadataSchemaVersion;
    final expectedKeys = isLegacy
        ? const {'schema', 'last_slot', 'hidden_record_ids'}
        : const {'schema', 'last_slot', 'hidden_record_ids', 'last_snapshot'};
    if (schema != _metadataSchemaVersion && !isLegacy ||
        raw.length != expectedKeys.length ||
        raw.keys.any((key) => !expectedKeys.contains(key))) {
      return null;
    }
    final lastSlot = raw['last_slot'];
    final hidden = raw['hidden_record_ids'];
    if (lastSlot is! int ||
        lastSlot < 0 ||
        hidden is! List ||
        hidden.length > _maxLocallyHiddenRecords ||
        hidden.any((value) => value is! String || value.trim().isEmpty)) {
      return null;
    }
    final hiddenIds = hidden.cast<String>().toSet();
    if (hiddenIds.length != hidden.length) return null;
    Uint8List? lastSnapshot;
    if (!isLegacy) {
      final encodedSnapshot = raw['last_snapshot'];
      if (encodedSnapshot != null && encodedSnapshot is! String) return null;
      if (encodedSnapshot is String) {
        try {
          lastSnapshot = base64Decode(encodedSnapshot);
        } on FormatException {
          return null;
        }
      }
    }
    if (lastSlot == 0 && lastSnapshot != null) return null;
    return FinalizedActivityArchiveMetadata(
      lastSlot: lastSlot,
      hiddenRecordIds: hiddenIds,
      lastSnapshot: lastSnapshot,
    );
  }
}

abstract interface class FinalizedActivityArchiveMetadataStore {
  Future<FinalizedActivityArchiveMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  });

  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required FinalizedActivityArchiveMetadata metadata,
  });

  Future<void> hideRecords({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required Iterable<String> recordIds,
  });

  Future<void> deleteForAccount({required String accountUuid});
}

class AppSecureStoreFinalizedActivityArchiveMetadataStore
    implements FinalizedActivityArchiveMetadataStore {
  AppSecureStoreFinalizedActivityArchiveMetadataStore(this._storage);

  final AppSecureStore _storage;
  final Map<String, Future<void>> _mutationTails = {};

  @override
  Future<FinalizedActivityArchiveMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  }) => _load(_key(accountUuid, kind));

  Future<FinalizedActivityArchiveMetadata?> _load(String key) async {
    final encoded = await _storage.readString(key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return FinalizedActivityArchiveMetadata.fromJson(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required FinalizedActivityArchiveMetadata metadata,
  }) {
    final key = _key(accountUuid, kind);
    return _serialize(key, () async {
      final current = await _load(key);
      final hidden = {
        ...?current?.hiddenRecordIds,
        ...metadata.hiddenRecordIds,
      };
      _validateHiddenCount(hidden);
      final next = FinalizedActivityArchiveMetadata(
        lastSlot: metadata.lastSlot >= (current?.lastSlot ?? 0)
            ? metadata.lastSlot
            : current!.lastSlot,
        hiddenRecordIds: hidden,
        lastSnapshot: metadata.lastSlot >= (current?.lastSlot ?? 0)
            ? metadata.lastSnapshot ?? current?.lastSnapshot
            : current!.lastSnapshot,
      );
      if (_metadataEquals(current, next)) return;
      await _write(key, next);
    });
  }

  @override
  Future<void> hideRecords({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required Iterable<String> recordIds,
  }) {
    final ids = recordIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return Future.value();
    final key = _key(accountUuid, kind);
    return _serialize(key, () async {
      final current = await _load(key);
      final hidden = {...?current?.hiddenRecordIds, ...ids};
      _validateHiddenCount(hidden);
      await _write(
        key,
        FinalizedActivityArchiveMetadata(
          lastSlot: current?.lastSlot ?? 0,
          hiddenRecordIds: hidden,
          lastSnapshot: current?.lastSnapshot,
        ),
      );
    });
  }

  Future<void> _write(String key, FinalizedActivityArchiveMetadata metadata) =>
      _storage.writeString(key, jsonEncode(metadata.toJson()));

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
        // A failed metadata mutation must not poison later local operations.
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

void _validateHiddenCount(Set<String> hidden) {
  if (hidden.length > _maxLocallyHiddenRecords) {
    throw StateError('Locally hidden activity limit exceeded.');
  }
}

bool _metadataEquals(
  FinalizedActivityArchiveMetadata? left,
  FinalizedActivityArchiveMetadata right,
) {
  if (left == null || left.lastSlot != right.lastSlot) return false;
  if (left.hiddenRecordIds.length != right.hiddenRecordIds.length ||
      !left.hiddenRecordIds.containsAll(right.hiddenRecordIds)) {
    return false;
  }
  final leftSnapshot = left.lastSnapshot;
  final rightSnapshot = right.lastSnapshot;
  if (identical(leftSnapshot, rightSnapshot)) return true;
  if (leftSnapshot == null ||
      rightSnapshot == null ||
      leftSnapshot.length != rightSnapshot.length) {
    return false;
  }
  for (var index = 0; index < leftSnapshot.length; index++) {
    if (leftSnapshot[index] != rightSnapshot[index]) return false;
  }
  return true;
}
