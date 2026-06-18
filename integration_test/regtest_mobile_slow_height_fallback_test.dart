import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/mobile_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

const _mnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _unifiedAddress = String.fromEnvironment('ZCASH_E2E_UNIFIED_ADDRESS');
const _primaryProxyUrl = 'http://127.0.0.1:19068';
const _fallbackToast =
    'Selected endpoint is unstable. Switched to fallback endpoint.';
const _primaryToast = 'Selected endpoint recovered. Switched back.';

/// Mobile regtest E2E: a primary endpoint whose reported height stops
/// advancing must trigger the slow-height fallback, recover when the
/// primary heals, and fall back again when it dies — the mobile
/// counterpart of regtest_slow_height_fallback_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'falls back from a slow-height primary and recovers on mobile',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      final proxy = RegtestLightwalletdProxy(log: logE2e);
      await proxy.start();
      addTearDown(proxy.stop);
      await _configureSlowPresetPrimary();

      logE2e('pumping app with slow regtest primary proxy');
      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: [
            rpcEndpointFailoverSettingsProvider.overrideWithValue(
              const RpcEndpointFailoverSettings(
                primaryProbeInterval: Duration(seconds: 3),
                slowHeightWindow: Duration(seconds: 3),
                minHeightIncreaseInSlowWindow: 2,
                slowFallbackLeadBlocks: 2,
              ),
            ),
          ],
        ),
      );

      await Clipboard.setData(const ClipboardData(text: _mnemonic));
      await importWalletViaPaste(
        tester,
        mnemonic: _mnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');

      final baselineHeight = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: mobileE2eLightwalletdUrl,
      );
      proxy.setSlowHeight(baselineHeight.toInt() + 1);
      await _pumpFor(tester, const Duration(seconds: 4));

      logE2e('funding while primary reports slow height');
      await _fundWallet('0.50');
      await pumpUntil(
        tester,
        () => tester.any(find.text(_fallbackToast)),
        description: 'slow-height fallback toast',
        timeout: const Duration(minutes: 2),
      );
      await waitForShieldedBalance(tester, '1.75 $mobileE2eTicker');

      logE2e('recovering primary proxy');
      proxy.setHealthy();
      await pumpUntil(
        tester,
        () => tester.any(find.text(_primaryToast)),
        description: 'primary recovery toast',
        timeout: const Duration(minutes: 2),
      );
      await _pumpFor(tester, const Duration(seconds: 5));

      logE2e('funding after primary recovery');
      await _fundWallet('0.25');
      await _waitForAnyShieldedBalance(tester, {'2 $mobileE2eTicker', '2.00 $mobileE2eTicker'});

      logE2e('making primary proxy unavailable');
      proxy.setDown();
      await _fundWallet('0.25');
      await pumpUntil(
        tester,
        () => tester.any(find.text(_fallbackToast)),
        description: 'fallback toast after primary down',
        timeout: const Duration(minutes: 2),
      );
      await waitForShieldedBalance(tester, '2.25 $mobileE2eTicker');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _configureSlowPresetPrimary() async {
  final storage = AppSecureStore.instance;
  await storage.writePlain(kRpcEndpointUrlKey, _primaryProxyUrl);
  await storage.writePlain(
    kRpcEndpointPresetKey,
    kRegtestSlowRpcEndpointPresetId,
  );
}

Future<void> _fundWallet(String amountZec) async {
  if (_unifiedAddress.isEmpty) {
    fail('ZCASH_E2E_UNIFIED_ADDRESS define is required for this test.');
  }
  logE2e('funding $_unifiedAddress with $amountZec');
  await postDriver('/fund-unmined-prepared', {
    'address': _unifiedAddress,
    'amount': amountZec,
  });
  await postDriver('/mine', {'blocks': 3});
}

Future<void> _waitForAnyShieldedBalance(
  WidgetTester tester,
  Set<String> accepted,
) async {
  await pumpUntil(
    tester,
    () => accepted.contains(
      textForKey(tester, const ValueKey('mobile_home_shielded_balance')),
    ),
    description: 'shielded balance to show one of $accepted',
    timeout: const Duration(minutes: 4),
  );
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
