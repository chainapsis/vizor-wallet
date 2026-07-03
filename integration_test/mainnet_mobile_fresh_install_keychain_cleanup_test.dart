import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';

import 'support/mobile_regtest_flow.dart';

const _accountsKey = 'zcash_accounts';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'clears stale mainnet keychain values after app uninstall',
    (tester) async {
      tolerateRenderOverflows();
      expect(kZcashDefaultNetworkName, ZcashNetwork.mainnet.name);

      logE2e('pumping mainnet app after host-side uninstall');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_welcome_get_started')),
        ),
        description: 'fresh install welcome screen',
        timeout: const Duration(minutes: 1),
      );

      final storage = AppSecureStore.instance;
      expect(await storage.readString(_accountsKey), isNull);
      expect(await storage.isPasswordConfigured(), isFalse);
      logE2e('stale mainnet keychain values were cleared');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
