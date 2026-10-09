import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('reading the wallet DB name never mints one', () async {
    const storage = FlutterSecureStorage();
    final store = AppSecureStore.testing(storage: storage);

    expect(await store.readWalletDbName(), isNull);
    expect(await storage.readAll(), isEmpty, reason: 'nothing was written');

    // Only the creating accessor names a wallet, and the reader then sees it.
    final created = await store.ensureWalletDbName();
    expect(await store.readWalletDbName(), created);
  });

  test('the existing wallet path is null without a stored name', () async {
    var supportResolved = false;
    expect(
      await getExistingWalletDbPath(
        readDbName: () async => null,
        resolveSupportDirectory: () async {
          supportResolved = true;
          return Directory.systemTemp;
        },
      ),
      isNull,
    );
    expect(supportResolved, isFalse);
    expect(
      await getExistingWalletDbPath(
        readDbName: () async => 'zcash_wallet_abc.db',
        resolveSupportDirectory: () async => Directory('/support'),
      ),
      '/support${Platform.pathSeparator}zcash_wallet_abc.db',
    );
  });
}
