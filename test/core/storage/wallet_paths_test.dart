import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';

class _UnreadableStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('storage unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final name in <String?>[null, '']) {
    test('a missing recorded wallet ($name) never generates a path', () async {
      FlutterSecureStorage.setMockInitialValues({kWalletDbNameKey: ?name});
      final store = AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      );
      var directoryReads = 0;
      final path = await getExistingWalletDbPath(
        secureStore: store,
        resolveSupportDirectory: () async {
          directoryReads++;
          return Directory('/unused');
        },
      );
      expect(path, isNull);
      expect(directoryReads, 0);
      expect(await store.readPlain(kWalletDbNameKey), name);
    });
  }

  test('the recorded path is used without creating wallet storage', () async {
    FlutterSecureStorage.setMockInitialValues({kWalletDbNameKey: 'wallet.db'});
    final store = AppSecureStore.testing(storage: const FlutterSecureStorage());
    final directory = await Directory.systemTemp.createTemp('wallet-path-');
    addTearDown(() => directory.delete(recursive: true));
    final path = await getExistingWalletDbPath(
      secureStore: store,
      resolveSupportDirectory: () async => directory,
    );
    expect(path, '${directory.path}${Platform.pathSeparator}wallet.db');
    expect(await directory.list().toList(), isEmpty);
    expect(await store.readPlain(kWalletDbNameKey), 'wallet.db');
  });

  test(
    'an unreadable recorded wallet never becomes an absent wallet',
    () async {
      final store = AppSecureStore.testing(storage: _UnreadableStorage());
      var directoryReads = 0;
      await expectLater(
        getExistingWalletDbPath(
          secureStore: store,
          resolveSupportDirectory: () async {
            directoryReads++;
            return Directory('/unused');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(directoryReads, 0);
    },
  );
}
