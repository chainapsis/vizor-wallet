import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';

class ControlledPrivacyStore extends AppSecureStore {
  ControlledPrivacyStore()
    : super.testing(storage: const FlutterSecureStorage());

  final values = <String, String>{};
  final writes = <String>[];
  Completer<void>? blocked;
  bool failWrites = false;
  final operations = <String>[];
  Future<void> Function(String operation)? beforeOperation;
  void Function(String operation)? afterOperation;

  Future<void> _before(String operation) async {
    operations.add(operation);
    await beforeOperation?.call(operation);
  }

  @override
  Future<String?> readPlain(String key) async {
    final operation = 'read:$key';
    await _before(operation);
    afterOperation?.call(operation);
    return values[key];
  }

  @override
  Future<void> delete(String key) async {
    final operation = 'delete:$key';
    await _before(operation);
    values.remove(key);
    afterOperation?.call(operation);
  }

  @override
  Future<void> writePlain(String key, String value) async {
    writes.add('$key=$value');
    await blocked?.future;
    final operation = 'write:$key=$value';
    await _before(operation);
    if (failWrites) throw StateError('storage unavailable');
    values[key] = value;
    afterOperation?.call(operation);
  }
}
