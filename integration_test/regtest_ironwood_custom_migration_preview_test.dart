import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39084',
);
const _simulatedBalanceZec = String.fromEnvironment(
  'ZCASH_REGTEST_FAKE_MIGRATION_BALANCE_ZEC',
);
const _reviewHoldMs = int.fromEnvironment(
  'ZCASH_E2E_CUSTOM_MIGRATION_PREVIEW_HOLD_MS',
  defaultValue: 0,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'opens an interactive custom migration preview for a simulated balance',
    (tester) async {
      expect(_simulatedBalanceZec, isNotEmpty);
      addTearDown(cleanupDesktopRegtestWallet);
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await pumpUntil(
        tester,
        () {
          final sync = container.read(syncProvider).value;
          return sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >=
                  (initialChain['zcashdHeight'] as num);
        },
        description: 'funded pre-Ironwood wallet sync',
        timeout: const Duration(minutes: 5),
      );

      e2eLog('activating Ironwood for the custom migration preview');
      await ironwoodDriverPost(_driverUrl, '/activate');
      await pumpUntil(
        tester,
        () {
          final chain = container.read(chainUpgradeStatusProvider).value;
          final sync = container.read(syncProvider).value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >= 500;
        },
        description: 'active Ironwood wallet sync',
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'Ironwood migration announcement',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);
      await openCustomMigrationReview(tester);

      await pumpUntil(
        tester,
        () =>
            tester.any(
              find.byKey(const ValueKey('custom_migration_histogram')),
            ) &&
            tester.any(find.byKey(const ValueKey('custom_migration_timeline'))),
        description: 'simulated custom migration plan',
        timeout: const Duration(minutes: 5),
      );
      expect(find.textContaining('$_simulatedBalanceZec ZEC'), findsOneWidget);
      final continueButton = tester.widget<AppButton>(
        find.byKey(const ValueKey('custom_migration_continue_button')),
      );
      expect(continueButton.onPressed, isNull);

      if (_reviewHoldMs > 0) {
        e2eLog(
          'custom preview ready for manual review; keeping it open for '
          '${_reviewHoldMs}ms',
        );
        // Live test bindings otherwise turn physical clicks into finder hints.
        binding.shouldPropagateDevicePointerEvents = true;
        try {
          final deadline = DateTime.now().add(
            const Duration(milliseconds: _reviewHoldMs),
          );
          while (DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        } finally {
          binding.shouldPropagateDevicePointerEvents = false;
        }
      }
    },
    timeout: Timeout(Duration(milliseconds: _reviewHoldMs + 10 * 60 * 1000)),
  );
}
