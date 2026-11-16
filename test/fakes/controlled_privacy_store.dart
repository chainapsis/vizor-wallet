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

  @override
  Future<void> writePlain(String key, String value) async {
    writes.add('$key=$value');
    await blocked?.future;
    if (failWrites) throw StateError('storage unavailable');
    values[key] = value;
  }
}
