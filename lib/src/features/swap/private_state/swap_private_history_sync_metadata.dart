import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/storage/app_secure_store.dart';
import 'swap_private_history_document.dart';

const _metadataSchemaVersion = 4;
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
    this.archiveState,
  });

  final int lastSlot;
  final Set<String> hiddenRecordIds;

  /// Locally cached merge of every delta through [lastSlot].
  ///
  /// This is local progress metadata, not a copy of any individual remote
  /// object. It lets later passes identify records that are new or have gained
  /// finalized evidence without rereading immutable slots.
  final Uint8List? archiveState;

  Map<String, Object?> toJson() => {
    'schema': _metadataSchemaVersion,
    'last_slot': lastSlot,
    'hidden_record_ids': hiddenRecordIds.toList()..sort(),
    'archive_state': archiveState == null ? null : base64Encode(archiveState!),
  };

  static FinalizedActivityArchiveMetadata? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    const expectedKeys = {
      'schema',
      'last_slot',
      'hidden_record_ids',
      'archive_state',
    };
    if (raw['schema'] != _metadataSchemaVersion ||
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
    Uint8List? archiveState;
    final encodedState = raw['archive_state'];
    if (encodedState != null && encodedState is! String) return null;
    if (encodedState is String) {
      try {
        archiveState = base64Decode(encodedState);
      } on FormatException {
        return null;
      }
    }
    if ((lastSlot == 0) != (archiveState == null)) return null;
    return FinalizedActivityArchiveMetadata(
      lastSlot: lastSlot,
      hiddenRecordIds: hiddenIds,
      archiveState: archiveState,
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
        archiveState: metadata.lastSlot >= (current?.lastSlot ?? 0)
            ? metadata.archiveState ?? current?.archiveState
            : current!.archiveState,
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
          archiveState: current?.archiveState,
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
  final leftState = left.archiveState;
  final rightState = right.archiveState;
  if (identical(leftState, rightState)) return true;
  if (leftState == null ||
      rightState == null ||
      leftState.length != rightState.length) {
    return false;
  }
  for (var index = 0; index < leftState.length; index++) {
    if (leftState[index] != rightState[index]) return false;
  }
  return true;
}
