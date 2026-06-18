import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';

import 'support/mobile_regtest_flow.dart';

const _accountsKey = 'zcash_accounts';
const _holdAfterCreate = bool.fromEnvironment('ZCASH_E2E_HOLD_AFTER_CREATE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'creates mainnet wallet state for fresh-install keychain cleanup E2E',
    (tester) async {
      tolerateRenderOverflows();
      expect(kZcashDefaultNetworkName, ZcashNetwork.mainnet.name);

      logE2e('pumping mainnet app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await createWalletWithPasscode(tester);

      final storage = AppSecureStore.instance;
      final accountsJson = await storage.readString(_accountsKey);
      expect(accountsJson, isNotNull);
      expect(accountsJson, isNotEmpty);

      final dbName = await storage.readPlain(kWalletDbNameKey);
      expect(dbName, isNotNull);
      expect(dbName!, startsWith('zcash_wallet_'));
      expect(dbName, endsWith('.db'));

      final dbPath = await getWalletDbPath();
      expect(File(dbPath).existsSync(), isTrue);
      logE2e('mainnet wallet state created with DB $dbName');

      while (_holdAfterCreate) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
