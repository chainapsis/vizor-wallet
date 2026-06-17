import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/mobile_regtest_flow.dart';

/// Mobile regtest E2E: create a wallet through the passcode onboarding
/// and reach a fully synced home. The regtest counterpart of the old
/// mainnet create-flow dogfood.
///
/// Run via scripts/e2e/flutter-ios-regtest-mobile-create-sync.sh.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'creates a regtest wallet via passcode onboarding and syncs',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      logE2e('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await createWalletWithPasscode(tester);

      await pumpUntil(
        tester,
        () => tester.any(find.text('Vizor is synced')),
        description: 'sync to complete',
        timeout: const Duration(minutes: 2),
      );
      logE2e('sync completed');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
