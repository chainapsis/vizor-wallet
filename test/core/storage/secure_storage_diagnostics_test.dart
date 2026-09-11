import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/secure_storage_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'vizor-diagnostics-test-',
    );
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await directory.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> records() async {
    final result = <Map<String, dynamic>>[];
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.jsonl')) continue;
      for (final line in await file.readAsLines()) {
        result.add(jsonDecode(line) as Map<String, dynamic>);
      }
    }
    return result;
  }

  test('keyring waits and controls record only fixed event names', () async {
    final diagnostics = SecureStorageDiagnostics.testing(directory);
    await diagnostics.initialize();
    for (final stage in StorageKeyringStage.values) {
      await diagnostics.keyringState(stage);
    }
    for (final action in StorageKeyringAction.values) {
      await diagnostics.keyringAction(action);
    }
    final events = (await records()).skip(1).toList();
    expect(
      events.map((e) => e['stage']).whereType<String>(),
      StorageKeyringStage.values.map((stage) => stage.name),
    );
    expect(
      events.map((e) => e['action']).whereType<String>(),
      StorageKeyringAction.values.map((action) => action.name),
    );
    for (final event in events) {
      expect(
        event.keys.toSet().difference({
          'time',
          'session',
          'pid',
          'event',
          'stage',
          'action',
        }),
        isEmpty,
      );
    }
  });

  test(
    'records missing reads and mutations without persisting private data',
    () async {
      final diagnostics = SecureStorageDiagnostics.testing(directory);
      await diagnostics.initialize();
      final store = AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
        diagnostics: diagnostics,
      );
      const privateValues = [
        'FixturePassword123!',
        'secret-verifier-salt-fixture',
        'account-uuid-sensitive-fixture',
        'mnemonic fixture words must never be in diagnostics',
        'https://private-user:private-token@example.invalid/rpc',
        'zcash_wallet_privatebasename.db',
      ];
      await store.readPlain(kWalletDbNameKey);
      await store.writePlain(kWalletDbNameKey, privateValues.last);
      await store.readPlain(kWalletDbNameKey);
      await store.writePlain('zcash_password_verifier', privateValues[0]);
      await store.writePlain('zcash_password_verifier_salt', privateValues[1]);
      await store.writePlain(
        'zcash_account_mnemonic_${privateValues[2]}',
        privateValues[3],
      );
      await store.readPlain('zcash_account_mnemonic_${privateValues[2]}');
      await store.writePlain(kRpcEndpointUrlKey, privateValues[4]);
      await store.delete('zcash_password_verifier');
      await diagnostics.trace(
        'read "${privateValues[2]}"',
        () async => {privateValues[0]: privateValues[3]},
      );
      await diagnostics.trace(
        'read "$kWalletDbNameKey"',
        () async => privateValues[3],
      );
      await store.deleteAll();
      final rows = await records();
      final encoded = jsonEncode(rows);
      for (final value in privateValues) {
        expect(encoded, isNot(contains(value)));
      }
      final reads = rows
          .where(
            (r) => r['event'] == 'storage_end' && r['category'] == 'db_locator',
          )
          .toList();
      expect(reads.first['read_state'], 'missing');
      expect(reads.any((r) => r['locator_fingerprint'] is String), isTrue);
      expect(reads.last['locator_valid'], isFalse);
      expect(reads.last.containsKey('locator_fingerprint'), isFalse);
      expect(rows.any((r) => r['category'] == 'software_secret'), isTrue);
      expect(rows.any((r) => r['category'] == 'rpc_endpoint'), isTrue);
      expect(rows.any((r) => r['verb'] == 'delete_all'), isTrue);
      for (final end in rows.where((r) => r['event'] == 'storage_end')) {
        expect(
          rows.where(
            (r) =>
                r['event'] == 'storage_begin' &&
                r['operation'] == end['operation'],
          ),
          hasLength(1),
        );
      }
    },
  );

  test(
    'storage errors retain their original cause without logging its text',
    () async {
      final diagnostics = SecureStorageDiagnostics.testing(directory);
      await diagnostics.initialize();
      final error = PlatformException(
        code: 'sensitive-error-code',
        message: 'secret error payload',
        details: 'secret details',
      );
      FlutterSecureStorage.setMockInitialValues(_UnreadableStorage(error));
      final store = AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
        diagnostics: diagnostics,
      );
      await expectLater(
        store.readPlain('zcash_accounts'),
        throwsA(
          isA<SecureStorageUnavailableException>().having(
            (e) => e.cause,
            'original cause',
            same(error),
          ),
        ),
      );
      final rows = await records();
      expect(rows.last['outcome'], 'error');
      expect(rows.last['error_kind'], 'platform');
      expect(jsonEncode(rows), isNot(contains('sensitive-error-code')));
      expect(jsonEncode(rows), isNot(contains('secret')));
    },
  );

  test(
    'upstream error codes are recorded without native error payloads',
    () async {
      final diagnostics = SecureStorageDiagnostics.testing(directory);
      await diagnostics.initialize();
      for (final code in [
        'KeyringLocked',
        'SecretNotFound',
        'Libsecret error',
        'StorageError',
      ]) {
        await expectLater(
          diagnostics.trace('read "zcash_accounts"', () async {
            throw PlatformException(
              code: code,
              message: 'private native payload',
            );
          }),
          throwsA(isA<PlatformException>()),
        );
      }
      final rows = await records();
      expect(
        rows
            .where((row) => row['event'] == 'storage_end')
            .map((row) => row['storage_error']),
        ['KeyringLocked', 'SecretNotFound', 'Libsecret error', 'StorageError'],
      );
      expect(jsonEncode(rows), isNot(contains('private native payload')));
    },
  );

  test(
    'rotation bounds storage and preserves unrelated files and symlinks',
    () async {
      final sentinel = File('${directory.path}/unrelated.txt');
      await sentinel.writeAsString('keep this');
      final link = Link('${directory.path}/secure-storage-1-1-1-1.jsonl');
      await link.create(sentinel.path);
      final diagnostics = SecureStorageDiagnostics.testing(
        directory,
        maxFileBytes: 1024,
        maxFiles: 3,
      );
      await diagnostics.initialize();
      for (var i = 0; i < 30; i++) {
        await diagnostics.trace(
          'read "zcash_accounts"',
          () async => 'private account data',
        );
      }
      final files = (await directory.list(followLinks: false).toList())
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList();
      expect(files, hasLength(3));
      for (final file in files) {
        expect(await file.length(), lessThanOrEqualTo(1024));
      }
      expect(await sentinel.readAsString(), 'keep this');
      expect(await link.exists(), isTrue);
      // All retained records remain valid JSON even after several rotations.
      for (final file in files) {
        for (final line in await file.readAsLines()) {
          expect(jsonDecode(line), isA<Map>());
        }
      }
    },
  );

  test('logger failure cannot block storage or hide a storage error', () async {
    final blockingFile = File('${directory.path}/not-a-directory');
    await blockingFile.writeAsString('keep');
    final diagnostics = SecureStorageDiagnostics.testing(
      Directory(blockingFile.path),
    );
    await diagnostics.initialize();
    final store = AppSecureStore.testing(
      storage: const FlutterSecureStorage(),
      diagnostics: diagnostics,
    );
    await store.writePlain('fixture-key', 'fixture-value');
    expect(await store.readPlain('fixture-key'), 'fixture-value');
    final error = PlatformException(code: 'expected-storage-error');
    FlutterSecureStorage.setMockInitialValues(_UnreadableStorage(error));
    await expectLater(
      store.readPlain('fixture-key'),
      throwsA(
        isA<SecureStorageUnavailableException>().having(
          (e) => e.cause,
          'original cause',
          same(error),
        ),
      ),
    );
    expect(await blockingFile.readAsString(), 'keep');
  });

  test('independent sessions keep their operation IDs distinct', () async {
    final first = SecureStorageDiagnostics.testing(directory);
    final second = SecureStorageDiagnostics.testing(directory);
    await Future.wait([first.initialize(), second.initialize()]);
    await Future.wait([
      first.trace('read "zcash_accounts"', () async => null),
      second.trace('read "zcash_accounts"', () async => 'present'),
    ]);
    final rows = await records();
    final ends = rows.where((r) => r['event'] == 'storage_end').toList();
    expect(ends, hasLength(2));
    expect(ends.map((r) => r['session']).toSet(), hasLength(2));
    expect(ends.map((r) => r['read_state']).toSet(), {'missing', 'present'});
  });
}

class _UnreadableStorage extends MapBase<String, String> {
  _UnreadableStorage(this.error);
  final PlatformException error;
  @override
  Iterable<String> get keys => const [];
  @override
  String? operator [](Object? key) => throw error;
  @override
  void operator []=(String key, String value) => throw error;
  @override
  String? remove(Object? key) => throw error;
  @override
  void clear() {}
}
