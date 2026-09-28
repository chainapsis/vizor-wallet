import 'dart:async';
import 'dart:convert';

import 'package:zcash_wallet/src/core/input/app_password_input_source.dart';

const source = <String, Object?>{'platform': 'macos', 'id': 'test.layout'};

class FakePlatform implements PasswordInputSourcePlatform {
  Map<String, Object?>? current = source;
  Completer<Map<String, Object?>?>? pending;
  int captures = 0;
  final restored = <Map<String, Object?>>[];
  bool fail = false;
  @override
  Future<Map<String, Object?>?> capture() async {
    captures++;
    if (fail) throw StateError('unavailable');
    return pending == null ? current : pending!.future;
  }

  @override
  Future<void> restore(
    Map<String, Object?> target,
    Map<String, Object?> expected,
  ) async {
    if (fail) throw StateError('unavailable');
    // Model the native compare-before-select contract.
    if (jsonEncode(current) != jsonEncode(expected)) return;
    restored.add(target);
  }
}

class FakeStore implements PasswordInputSourceStore {
  String? value;
  bool fail = false;
  Completer<String?>? pendingRead;
  Completer<void>? pendingWrite;
  int writes = 0;
  @override
  Future<String?> read() async {
    if (fail) throw StateError('unavailable');
    return pendingRead == null ? value : pendingRead!.future;
  }

  @override
  Future<void> write(String value) async {
    writes++;
    if (pendingWrite != null) await pendingWrite!.future;
    if (fail) throw StateError('unavailable');
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
