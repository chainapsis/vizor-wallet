import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';

import 'support/mobile_regtest_flow.dart';

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _screenshotDriverUrl = String.fromEnvironment(
  'ZCASH_E2E_SCREENSHOT_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39070',
);

/// Focused design capture for the mobile send flow. It uses the same host-side
/// screenshot driver as the full screenshot tour, but stops at the send states
/// needed for route-step refactors.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('captures the mobile send flow states', (tester) async {
    tolerateRenderOverflows();
    addTearDown(() async {
      await cleanupE2eWalletState();
    });
    await cleanupE2eWalletState();

    Future<void> shot(String name) async {
      await settle(tester, const Duration(milliseconds: 700));
      await postDriver('/screenshot', {
        'name': name,
      }, baseUrl: _screenshotDriverUrl);
      logE2e('shot $name');
    }

    logE2e('pumping app');
    await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
    await pumpUntil(
      tester,
      () =>
          tester.any(find.byKey(const ValueKey('mobile_welcome_get_started'))),
      description: 'welcome screen',
      timeout: const Duration(minutes: 1),
    );

    await importWalletViaPaste(
      tester,
      mnemonic: _mnemonic,
      birthdayHeight: 1,
      isFirstWallet: true,
    );
    await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');
    await pumpUntil(
      tester,
      () => tester.any(find.text('Vizor is synced')),
      description: 'sync to complete',
      timeout: const Duration(minutes: 2),
    );

    final ownAddress = await copyShieldedAddress(tester);
    await tapWidget(tester, const ValueKey('mobile_home_send'));
    await pumpUntil(
      tester,
      () => tester.any(find.text('Select Recipient')),
      description: 'send recipient step',
    );
    await shot('01_send_recipient');

    await enterText(
      tester,
      const ValueKey('mobile_send_address_field'),
      ownAddress,
    );
    await shot('02_send_recipient_filled');

    await tapAppButton(
      tester,
      const ValueKey('mobile_send_continue'),
      timeout: const Duration(minutes: 1),
    );
    await pumpUntil(
      tester,
      () => tester.any(find.text('Enter Amount')),
      description: 'send amount step',
    );
    await shot('03_send_amount_empty');

    await enterText(tester, const ValueKey('mobile_send_amount_input'), '0.25');
    await pumpUntil(
      tester,
      () => tester.any(find.text('Finish & review')),
      description: 'amount ready',
      timeout: const Duration(minutes: 1),
    );
    await shot('04_send_amount_ready');

    await tapAppButton(
      tester,
      const ValueKey('mobile_send_review_button'),
      timeout: const Duration(minutes: 1),
    );
    await pumpUntil(
      tester,
      () => tester.any(find.text('Review Send')),
      description: 'send review step',
    );
    await shot('05_send_review');

    await tapWidget(tester, const ValueKey('mobile_send_memo_row'));
    await pumpUntil(
      tester,
      () => tester.any(find.byKey(const ValueKey('mobile_send_memo_field'))),
      description: 'memo sheet',
    );
    await shot('06_send_memo_sheet');

    await enterText(
      tester,
      const ValueKey('mobile_send_memo_field'),
      'Zcash is a privacy-focused cryptocurrency',
    );
    await tapAppButton(tester, const ValueKey('mobile_send_memo_save'));
    await settle(tester, const Duration(milliseconds: 400));
    await shot('07_send_review_with_memo');

    await tapWidget(tester, const ValueKey('mobile_send_full_address'));
    await settle(tester, const Duration(milliseconds: 400));
    await shot('08_send_full_address');
    await tester.tap(find.text('Cancel').last);
    await settle(tester, const Duration(milliseconds: 400));

    await tapAppButton(
      tester,
      const ValueKey('mobile_send_confirm'),
      timeout: const Duration(minutes: 1),
    );
    await pumpUntil(
      tester,
      () =>
          tester.any(find.byKey(const ValueKey('mobile_send_status_sending'))),
      description: 'send status to start',
      timeout: const Duration(minutes: 1),
    );
    await shot('09_send_sending');

    await pumpUntil(
      tester,
      () => tester.any(
        find.byKey(const ValueKey('mobile_send_status_succeeded')),
      ),
      description: 'send status to succeed',
      timeout: const Duration(minutes: 4),
    );
    await shot('10_send_success');
  });
}
