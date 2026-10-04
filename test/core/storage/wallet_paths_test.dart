import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';

void main() {
  // Integration lanes that share the installed app's bundle and network rely
  // on this override to keep every wallet path inside their sandbox.
  test('isolated wallet storage resolves inside the sandbox', () async {
    final sandbox = await Directory.systemTemp.createTemp('wallet-paths-test.');
    addTearDown(() => sandbox.delete(recursive: true));
    debugWalletStorageDirectory = sandbox;
    addTearDown(() => debugWalletStorageDirectory = null);

    expect(await getWalletDbName(), kDebugWalletDbName);
    expect(
      await getWalletDbPath(),
      '${sandbox.path}${Platform.pathSeparator}$kDebugWalletDbName',
    );
    expect(await getTorDataDirectoryPath(), startsWith(sandbox.path));
    expect(await getGiftCardTrackingDbPath('main'), startsWith(sandbox.path));
  });
}
