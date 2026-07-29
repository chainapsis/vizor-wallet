import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

const _fallbackToast =
    'Selected endpoint is unstable. Switched to fallback endpoint.';
const _networkFailure =
    "Network connection lost. We'll keep trying automatically.";
const _endpointFailure =
    'Cannot reach the configured Zcash endpoint. Check your endpoint settings.';
const _genericFailure = 'Sync failed. Retry sync to continue.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'recovers from a stalled startup UTXO stream instead of staying at zero percent',
    (tester) async {
      await cleanupDesktopRegtestWallet();
      final proxy = RegtestLightwalletdProxy(log: e2eLog);
      await proxy.start();
      // Keep later scanning minimal while retaining a persisted completed tip.
      proxy.setSlowHeight(1);
      proxy.serveEmptyGenesisTreeState();
      addTearDown(() async {
        proxy.releaseStalledAddressUtxosStream();
        try {
          await cleanupDesktopRegtestWallet();
        } finally {
          await proxy.stop();
        }
      });

      final storage = AppSecureStore.instance;
      await storage.writePlain(kRpcEndpointUrlKey, proxy.url);
      await storage.writePlain(
        kRpcEndpointPresetKey,
        kCustomRpcEndpointPresetId,
      );

      e2eLog('pumping app with a custom endpoint proxy');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await tapAppButton(
        tester,
        const ValueKey('welcome_import_wallet_button'),
      );
      await enterAppText(
        tester,
        const ValueKey('import_mnemonic_first_word_field'),
        desktopRegtestMnemonic,
      );
      await tapAppButton(tester, const ValueKey('import_secret_submit_button'));
      await tapAppButton(tester, const ValueKey('import_birthday_skip_button'));
      await tapAppButton(
        tester,
        const ValueKey('unknown_birthday_confirm_button'),
      );
      await enterAppText(
        tester,
        const ValueKey('set_password_password_field'),
        desktopRegtestPassword,
      );
      await enterAppText(
        tester,
        const ValueKey('set_password_confirm_field'),
        desktopRegtestPassword,
      );
      proxy.stallNextAddressUtxosStreamAfterHeaders();
      await tapAppButton(tester, const ValueKey('set_password_submit_button'));

      await pumpUntil(
        tester,
        () => proxy.addressUtxosStreamCallCount >= 1,
        description: 'stalled transparent UTXO stream request',
        timeout: const Duration(seconds: 60),
      );
      expect(rust_sync.isSyncRunning(), isTrue);
      expect(find.text('0% Syncing...'), findsOneWidget);
      e2eLog('reproduced the pre-progress sync wait');

      await pumpUntil(
        tester,
        () =>
            proxy.addressUtxosStreamCallCount >= 2 &&
            !rust_sync.isSyncRunning() &&
            textForKey(tester, const ValueKey('sidebar_sync_text')) == 'Synced',
        description: 'completed sync after the stalled UTXO stream timeout',
        timeout: const Duration(seconds: 75),
      );

      expect(proxy.addressUtxosStreamCallCount, greaterThanOrEqualTo(2));
      expect(rust_sync.isSyncRunning(), isFalse);
      final persistedStatus = await rust_sync.getSyncStatus(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
      );
      expect(persistedStatus.isComplete, isTrue);
      expect(textForKey(tester, const ValueKey('sidebar_sync_text')), 'Synced');
      expect(find.text(_networkFailure), findsNothing);
      expect(find.text(_endpointFailure), findsNothing);
      expect(find.text(_genericFailure), findsNothing);
      expect(find.text(_fallbackToast), findsNothing);
      e2eLog('stalled UTXO stream recovered on the healthy retry');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
