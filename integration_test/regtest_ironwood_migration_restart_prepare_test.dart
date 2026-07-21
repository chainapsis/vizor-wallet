import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'persists an active migration while lightwalletd is unavailable',
    (tester) async {
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      await pumpUntil(
        tester,
        () =>
            textForKey(
              tester,
              const ValueKey('home_desktop_balance_amount_text'),
            ) ==
            '0.011',
        description: 'pre-Ironwood Orchard balance to render',
        timeout: const Duration(minutes: 5),
      );

      final providerContainer = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await pumpUntil(
        tester,
        () {
          final sync = providerContainer.read(syncProvider).value;
          return sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >=
                  (initialChain['zcashdHeight'] as num);
        },
        description: 'idle pre-Ironwood wallet sync',
        timeout: const Duration(minutes: 5),
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
      await _waitForIronwoodSync(tester, providerContainer);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'Ironwood announcement after activation',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);
      await openPrivateMigrationReview(tester);

      e2eLog('stopping lightwalletd before migration authorization');
      await ironwoodDriverPost(_driverUrl, '/lightwalletd/stop');
      await startPrivateMigrationFromReview(tester);
      final accountUuid = await firstDesktopRegtestAccountUuid();
      await waitForDesktopRegtestPreparingStatusScreen(
        tester,
        accountUuid,
        description: 'persisted denomination run while lightwalletd is offline',
        timeout: const Duration(minutes: 3),
      );

      final status = await desktopRegtestMigrationStatus(accountUuid);
      expect(status.activeRunId, isNotNull);
      expect(status.phase, 'waiting_denom_confirmations');
      expect(status.denominationSplitTotalCount, greaterThan(0));
      expect(status.pendingSplitStageCount, greaterThan(0));
      e2eLog('prepared active run ${status.activeRunId} for process restart');

      await stopRustWorkForCleanup();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _waitForIronwoodSync(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
    description: 'active Ironwood chain and completed wallet sync',
    timeout: const Duration(minutes: 5),
  );

  final inputs = container.read(ironwoodMigrationInputsProvider);
  expect(inputs.hasAccountScopedData, isTrue);
  expect(inputs.hasOrchardFunds, isTrue);
}
