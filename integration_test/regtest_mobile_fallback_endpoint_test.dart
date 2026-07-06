import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';

import 'support/mobile_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _primaryProxyUrl = 'http://127.0.0.1:19068';
const _fallbackToast =
    'Selected endpoint is unstable. Switched to fallback endpoint.';

/// Mobile regtest E2E: when the selected endpoint dies before sync, the
/// app must fall back (toast) and still sync the imported balance — the
/// mobile counterpart of regtest_fallback_endpoint_test.dart. The proxy
/// runs inside the test process on the simulator.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'falls back when the primary endpoint dies before sync on mobile',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      final proxy = RegtestLightwalletdProxy(log: logE2e);
      await proxy.start();
      addTearDown(proxy.stop);
      await _configureProxyPresetPrimary();

      logE2e('pumping app with healthy primary endpoint proxy');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      // Import up to the birthday step against the healthy proxy, then
      // make it unavailable right before the import (and first sync)
      // kicks off.
      await tapAppButton(
        tester,
        const ValueKey('mobile_welcome_get_started'),
      );
      await tapWidget(
        tester,
        const ValueKey('mobile_welcome_import'),
      );
      await _pasteAndContinueToBirthday(tester);
      await tapWidget(
        tester,
        const ValueKey('mobile_import_birthday_mode_height'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('mobile_import_birthday_height')),
        '1',
      );
      await tester.pump();
      logE2e('making primary proxy unavailable before import completes');
      proxy.setDown();
      await tapAppButton(
        tester,
        const ValueKey('mobile_import_birthday_continue'),
        timeout: const Duration(minutes: 1),
      );
      await enterPasscode(tester, mobileE2ePasscode);
      await enterPasscode(tester, mobileE2ePasscode);
      await tapWidget(
        tester,
        const ValueKey('mobile_biometrics_not_now'),
        timeout: const Duration(seconds: 90),
      );
      await waitForHome(tester);

      await pumpUntil(
        tester,
        () => tester.any(find.text(_fallbackToast)),
        description: 'fallback endpoint toast during sync',
        timeout: const Duration(seconds: 60),
      );
      logE2e('fallback toast appeared during sync');

      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');
      logE2e('shielded balance synced through fallback');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _pasteAndContinueToBirthday(WidgetTester tester) async {
  await Clipboard.setData(const ClipboardData(text: _mnemonic));
  await tapAppButton(tester, const ValueKey('mobile_import_paste'));
  await tapAppButton(tester, const ValueKey('mobile_import_review_continue'));
}

Future<void> _configureProxyPresetPrimary() async {
  final storage = AppSecureStore.instance;
  await storage.writePlain(kRpcEndpointUrlKey, _primaryProxyUrl);
  await storage.writePlain(
    kRpcEndpointPresetKey,
    kRegtestSlowRpcEndpointPresetId,
  );
}
