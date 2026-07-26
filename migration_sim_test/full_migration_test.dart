import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../integration_test/support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);
const _blockIntervalMs = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_BLOCK_INTERVAL_MS',
  defaultValue: 3000,
);
const _maxBlocks = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_MAX_BLOCKS',
  defaultValue: 160,
);
const _fundedZatoshi = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
  defaultValue: 9900020000,
);
const _fundingNoteCount = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT',
  defaultValue: 20,
);
const _homeHoldMs = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_HOME_HOLD_MS',
  defaultValue: 15000,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The default integration-test frame policy renders primarily when the
  // driver pumps. This simulation is intentionally watched by a person, so
  // honor the application's own frame requests just like a normal app run.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'migrates a large many-note wallet at a controlled block cadence',
    (tester) async {
      expect(kZcashFastTestnetMigration, isTrue);
      expect(_fundedZatoshi, greaterThanOrEqualTo(1000000000));
      expect(_fundingNoteCount, greaterThanOrEqualTo(10));
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      final accountUuid = await firstDesktopRegtestAccountUuid();
      final dbPath = await getWalletDbPath();
      e2eLog(
        'migration-sim wallet_db=$dbPath account=$accountUuid '
        'funded=$_fundedZatoshi notes=$_fundingNoteCount',
      );

      final providerContainer = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await _waitForOrchardBalance(
        tester,
        dbPath,
        accountUuid,
        BigInt.from(_fundedZatoshi),
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
      final approvedPlan = plan!;
      expect(
        approvedPlan.totalInputZatoshi,
        BigInt.from(_fundedZatoshi),
      );
      expect(approvedPlan.denominationSplitStageCount, greaterThanOrEqualTo(2));
      expect(approvedPlan.scheduledTransfers.length, greaterThan(6));
      e2eLog(
        'migration-sim plan '
        'stages=${approvedPlan.denominationSplitStageCount} '
        'parts=${approvedPlan.scheduledTransfers.length} '
        'splitFee=${approvedPlan.denominationSplitFeeZatoshi} '
        'migrationFee=${approvedPlan.migrationFeeZatoshi} '
        'totalFee=${approvedPlan.estimatedTotalFeeZatoshi}',
      );

      await startPrivateMigrationFromReview(tester);
      final started = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null &&
            status.denominationSplitTotalCount ==
                approvedPlan.denominationSplitStageCount,
        description: 'persisted full migration',
        timeout: const Duration(minutes: 8),
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);
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
          'denomConf=${status.denominationConfirmationCount}/'
          '${status.denominationConfirmationTarget} '
          'transfers=${status.confirmedTxCount}/'
          '${status.broadcastedTxCount}/${status.totalCount} '
          'next=${status.nextActionHeight} '
          'mempool=${mempool['size']}',
        );

        if (status.phase == kIronwoodMigrationCompletePhase) {
          expect(status.activeRunId, isNull);
          expect(status.confirmedTxCount, status.totalCount);
          expect(status.totalCount, approvedPlan.scheduledTransfers.length);
          expect(
            status.parts.every(
              (part) => part.state == rust_sync.MigrationPartState.completed,
            ),
            isTrue,
          );
          await _expectFinalBalance(
            dbPath,
            accountUuid,
            approvedPlan,
          );
          await _returnHomeAfterCompletion(
            tester,
            providerContainer,
            accountUuid,
          );
          e2eLog(
            'migration-sim FULL_MIGRATION_COMPLETE '
            'height=${chain['zcashdHeight']} run=$runId',
          );
          e2eLog('migration-sim holding Home for ${_homeHoldMs}ms');
          await Future<void>.delayed(
            const Duration(milliseconds: _homeHoldMs),
          );
          await tester.pump();
          return;
        }
        if (mined == _maxBlocks) break;

        await Future<void>.delayed(
          const Duration(milliseconds: _blockIntervalMs),
        );
        await tester.pump();
        final currentHeight = (chain['zcashdHeight'] as num).toInt();
        final nextActionHeight = status.nextActionHeight;
        var blocksToMine = 1;
        if (nextActionHeight != null &&
            nextActionHeight > currentHeight + 1) {
          final gap = nextActionHeight - currentHeight;
          // Keep a mined transaction's confirmation transition observable,
          // then skip any remaining empty range on the following tick.
          blocksToMine = status.broadcastedTxCount > 0 && gap > 3 ? 3 : gap;
          e2eLog(
            'migration-sim advancing $blocksToMine block(s) toward '
            'next action $nextActionHeight',
          );
        }
        await ironwoodDriverPost(
          _driverUrl,
          '/mine',
          payload: {'blocks': blocksToMine},
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
        'Full migration did not complete within $_maxBlocks blocks. '
        'phase=${last.phase}, denomination='
        '${last.denominationSplitCompletedCount}/'
        '${last.denominationSplitTotalCount}, transfers='
        '${last.confirmedTxCount}/${last.broadcastedTxCount}/'
        '${last.totalCount}, next=${last.nextActionHeight}',
      );
    },
    timeout: const Timeout(Duration(minutes: 40)),
  );
}

Future<void> _returnHomeAfterCompletion(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid,
) async {
  final request = IronwoodMigrationStatusRequest(
    network: 'regtest',
    accountUuid: accountUuid,
  );
  container.invalidate(ironwoodMigrationStatusProvider(request));
  await container.read(ironwoodMigrationStatusProvider(request).future);
  await tester.pump();
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('ironwood_migration_status_complete')),
    ),
    description: 'completed migration UI',
    timeout: const Duration(minutes: 2),
  );
  await tapAppButton(
    tester,
    const ValueKey('ironwood_migration_status_action_button'),
  );
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'Home after full migration',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> _waitForOrchardBalance(
  WidgetTester tester,
  String dbPath,
  String accountUuid,
  BigInt expected,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  rust_sync.WalletBalance? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await rust_sync.getBalance(
      dbPath: dbPath,
      network: 'regtest',
      accountUuid: accountUuid,
    );
    if (last.orchard == expected) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Expected Orchard balance $expected, last balance: ${last?.orchard}.');
}

Future<void> _expectFinalBalance(
  String dbPath,
  String accountUuid,
  rust_sync.OrchardMigrationPrivatePlan plan,
) async {
  final balance = await rust_sync.getBalance(
    dbPath: dbPath,
    network: 'regtest',
    accountUuid: accountUuid,
  );
  final retainedOrchard = balance.orchard + balance.uneconomicValue;
  expect(balance.ironwood, plan.totalMigratableZatoshi);
  expect(
    retainedOrchard,
    plan.orchardChangeZatoshi ?? BigInt.zero,
  );
  expect(
    BigInt.from(_fundedZatoshi) - balance.ironwood - retainedOrchard,
    plan.estimatedTotalFeeZatoshi,
  );
}
