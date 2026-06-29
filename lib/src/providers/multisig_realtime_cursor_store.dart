import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';

const _multisigRealtimeCursorKeyPrefix = 'zcash_multisig_realtime_cursor_v1_';

final multisigRealtimeCursorStoreProvider = Provider(
  (ref) => MultisigRealtimeCursorStore(AppSecureStore.instance),
);

class MultisigRealtimeCursor {
  const MultisigRealtimeCursor({this.eventsCursor = 0, this.inboxCursor = 0});

  final int eventsCursor;
  final int inboxCursor;

  MultisigRealtimeCursor copyWith({int? eventsCursor, int? inboxCursor}) {
    return MultisigRealtimeCursor(
      eventsCursor: eventsCursor ?? this.eventsCursor,
      inboxCursor: inboxCursor ?? this.inboxCursor,
    );
  }

  Map<String, Object?> toJson() => {
    'eventsCursor': eventsCursor,
    'inboxCursor': inboxCursor,
  };

  static MultisigRealtimeCursor fromJson(Map<String, Object?> json) {
    return MultisigRealtimeCursor(
      eventsCursor: _readOptionalInt(json['eventsCursor']) ?? 0,
      inboxCursor: _readOptionalInt(json['inboxCursor']) ?? 0,
    );
  }
}

class MultisigRealtimeCursorStore {
  const MultisigRealtimeCursorStore(this._storage);

  final AppSecureStore _storage;

  Future<MultisigRealtimeCursor> read(String storageId) async {
    final raw = await _storage.readPlain(_cursorKey(storageId));
    if (raw == null || raw.trim().isEmpty) {
      return const MultisigRealtimeCursor();
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const MultisigRealtimeCursor();
    return MultisigRealtimeCursor.fromJson(decoded.cast<String, Object?>());
  }

  Future<void> write(String storageId, MultisigRealtimeCursor cursor) {
    return _storage.writePlain(
      _cursorKey(storageId),
      jsonEncode(cursor.toJson()),
    );
  }

  Future<void> advanceInboxCursor(String storageId, int cursor) async {
    final current = await read(storageId);
    final nextCursor = math.max(current.inboxCursor, cursor);
    if (nextCursor == current.inboxCursor) return;
    await write(storageId, current.copyWith(inboxCursor: nextCursor));
  }

  Future<void> advanceEventsCursor(String storageId, int cursor) async {
    final current = await read(storageId);
    final nextCursor = math.max(current.eventsCursor, cursor);
    if (nextCursor == current.eventsCursor) return;
    await write(storageId, current.copyWith(eventsCursor: nextCursor));
  }

  Future<void> clear(String storageId) {
    return _storage.delete(_cursorKey(storageId));
  }

  Future<void> clearAll() {
    return _storage.deletePlainKeysWithPrefix(_multisigRealtimeCursorKeyPrefix);
  }

  String _cursorKey(String storageId) {
    return '$_multisigRealtimeCursorKeyPrefix$storageId';
  }
}

int? _readOptionalInt(Object? value) {
  if (value is int) return value;
  if (value is BigInt) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
