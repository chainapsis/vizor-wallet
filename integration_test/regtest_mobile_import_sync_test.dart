import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/mobile_regtest_flow.dart';

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';

/// Mobile regtest E2E: import the funded wallet through the mobile
/// paste-import flow and verify the synced shielded balance — the
/// mobile counterpart of regtest_import_sync_test.dart. The funding
/// script (flutter-ios-regtest-mobile-import-sync.sh) sends 1.25 to
/// the shielded address before the test runs.
///
/// The mobile home has no transparent balance UI yet, so unlike the
/// desktop test only the shielded balance is asserted through the UI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'imports a funded regtest wallet on mobile and shows the balance',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      logE2e('pumping app');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await importWalletViaPaste(
        tester,
        mnemonic: _mnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );

      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
