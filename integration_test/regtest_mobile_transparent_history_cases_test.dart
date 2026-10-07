// Transparent history qualification suite, app layer (mobile, public mode).
//
// Run through scripts/e2e/transparent-history-cases.sh --flutter mobile (iOS
// simulator, VIZOR_FORM_FACTOR=mobile via run_mobile_e2e). Same checks as the
// desktop test against the mobile activity tab and status screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';

import 'support/mobile_regtest_flow.dart';
import 'support/transparent_history_cases_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('H01-H13 activity after a fresh restore (mobile, public mode)', (
    tester,
  ) async {
    tolerateRenderOverflows();
    final rows = thExpectedUiRows();
    addTearDown(cleanupE2eWalletState);
    await cleanupE2eWalletState();
    // Swap rows are mainnet-gated; H11 needs them to show retained records.
    await tester.pumpWidget(
      await buildBootstrappedZcashWalletApp(
        overrides: [swapFeatureEnabledProvider.overrideWithValue(true)],
      ),
    );

    // A0 is restored and synced alone before A1 is added, so adding an
    // account rewinds a synced wallet, the order users reach.
    await importWalletViaPaste(
      tester,
      mnemonic: thA0Mnemonic,
      birthdayHeight: 1,
      isFirstWallet: true,
    );
    await thWaitForSynchronized(tester);
    await openAddAccountFlow(tester);
    await importWalletViaPaste(
      tester,
      mnemonic: thA1Mnemonic,
      birthdayHeight: 1,
      isFirstWallet: false,
    );
    final uuids = {
      'A0': await accountUuidAtOrder(0),
      'A1': await accountUuidAtOrder(1),
    };

    final failures = <String>[];
    for (final account in ['A0', 'A1']) {
      final expected = rows.where((r) => r.account == account).toList();
      if (expected.isEmpty) continue;
      await switchAccountTo(tester, uuids[account]!);
      await thWaitForHistory(
        tester,
        accountUuid: uuids[account]!,
        rows: expected,
      );
      await openActivityTab(tester);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      failures.addAll(
        await thVerifyActivity(
          tester,
          account: account,
          rows: expected,
          ticker: mobileE2eTicker,
          mobile: true,
          dragAt: Offset(size.width * 0.5, size.height * 0.55),
          returnToActivity: () async {
            await tapBack(tester);
            await settle(tester, const Duration(milliseconds: 400));
          },
        ),
      );
      if (account == 'A0' && expected.any((r) => r.intent == 'swap_deposit')) {
        failures.addAll(
          await thVerifySwapRecord(
            tester,
            rows: expected,
            accountUuid: uuids[account]!,
            dragAt: Offset(size.width * 0.5, size.height * 0.55),
            reopenActivity: () async {
              await openHomeTab(tester);
              await openActivityTab(tester);
            },
          ),
        );
      }
      await openHomeTab(tester);
    }
    logE2e('checked ${rows.length} expected rows; ${failures.length} failures');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 40)));
}
