import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../integration_test/support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);
const _blockIntervalMs = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_BLOCK_INTERVAL_MS',
  defaultValue: 6000,
);
const _maxBlocks = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_MAX_BLOCKS',
  defaultValue: 40,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'prepares and confirms a denomination split at a controlled block cadence',
    (tester) async {
      expect(kZcashFastTestnetMigration, isTrue);
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      final accountUuid = await firstDesktopRegtestAccountUuid();
      final dbPath = await getWalletDbPath();
      e2eLog('migration-sim wallet_db=$dbPath account=$accountUuid');

      final providerContainer = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );

      e2eLog('migration-sim activating local NU6.3 chain');
      await ironwoodDriverPost(_driverUrl, '/activate');
      await pumpUntil(
        tester,
        () {
          final chain = providerContainer
              .read(chainUpgradeStatusProvider)
              .value;
          final sync = providerContainer.read(syncProvider).value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >=
                  (initialChain['ironwoodActivationHeight'] as num).toInt();
        },
        description: 'local Ironwood activation sync',
        timeout: const Duration(minutes: 5),
      );

      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'migration announcement',
        timeout: const Duration(minutes: 2),
      );
      await dismissIronwoodAnnouncement(tester);
      await openPrivateMigrationReview(tester);

      final plan = await providerContainer.read(
        ironwoodMigrationPrivatePlanProvider.future,
      );
      expect(plan, isNotNull);
      expect(plan!.denominationSplitStageCount, 1);
      expect(plan.scheduledTransfers, hasLength(6));
      e2eLog(
        'migration-sim plan stages=${plan.denominationSplitStageCount} '
        'parts=${plan.scheduledTransfers.length} '
        'splitFee=${plan.denominationSplitFeeZatoshi}',
      );

      await startPrivateMigrationFromReview(tester);
      final started = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null &&
            status.denominationSplitTotalCount == 1,
        description: 'persisted denomination split',
        timeout: const Duration(minutes: 5),
      );
      expect(started.scheduleMeanDelayBlocks, 12);
      expect(started.scheduleMaxDelayBlocks, 48);

      for (var mined = 0; mined <= _maxBlocks; mined++) {
        final status = await desktopRegtestMigrationStatus(accountUuid);
        final chain = await ironwoodDriverGet(_driverUrl, '/status');
        final mempool = await ironwoodDriverGet(_driverUrl, '/mempool');
        e2eLog(
          'migration-sim tick=$mined '
          'height=${chain['zcashdHeight']} '
          'phase=${status.phase} '
          'denom=${status.denominationSplitCompletedCount}/'
          '${status.denominationSplitTotalCount} '
          'confirmations=${status.denominationConfirmationCount}/'
          '${status.denominationConfirmationTarget} '
          'next=${status.nextActionHeight} '
          'mempool=${mempool['size']}',
        );

        if (status.denominationSplitTotalCount > 0 &&
            status.denominationSplitCompletedCount ==
                status.denominationSplitTotalCount) {
          expect(
            status.denominationConfirmationCount,
            greaterThanOrEqualTo(status.denominationConfirmationTarget),
          );
          e2eLog(
            'migration-sim PREPARE_COMPLETE '
            'height=${chain['zcashdHeight']} run=${status.activeRunId}',
          );
          return;
        }
        if (mined == _maxBlocks) break;

        await Future<void>.delayed(
          const Duration(milliseconds: _blockIntervalMs),
        );
        await tester.pump();
        await ironwoodDriverPost(
          _driverUrl,
          '/mine',
          payload: const {'blocks': 1},
        );
        final minedChain = await ironwoodDriverGet(_driverUrl, '/status');
        final targetHeight = (minedChain['zcashdHeight'] as num).toInt();
        await pumpUntil(
          tester,
          () {
            final sync = providerContainer.read(syncProvider).value;
            return (sync?.scannedHeight ?? 0) >= targetHeight;
          },
          description: 'wallet sync to simulated block $targetHeight',
          timeout: const Duration(minutes: 2),
        );
      }

      final last = await desktopRegtestMigrationStatus(accountUuid);
      fail(
        'Denomination split did not complete within $_maxBlocks blocks. '
        'phase=${last.phase}, confirmations='
        '${last.denominationConfirmationCount}/'
        '${last.denominationConfirmationTarget}, next=${last.nextActionHeight}',
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
