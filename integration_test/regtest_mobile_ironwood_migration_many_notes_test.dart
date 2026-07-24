import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

const _fundedAmountZatoshi = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
  defaultValue: 1_000_020_000,
);
const _fundedNoteCount = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT',
  defaultValue: 20,
);
const _expectedSplitStageCount = int.fromEnvironment(
  'ZCASH_E2E_EXPECTED_SPLIT_STAGE_COUNT',
  defaultValue: 2,
);
const _expectedMigrationBatchCount = int.fromEnvironment(
  'ZCASH_E2E_EXPECTED_MIGRATION_BATCH_COUNT',
  defaultValue: 9,
);
final _fundedAmount = BigInt.from(_fundedAmountZatoshi);
final _fundedAmountText = ZecAmount.fromZatoshi(
  _fundedAmount,
).compactBalance.amountText;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'migrates $_fundedNoteCount Orchard notes on mobile',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(cleanupE2eWalletState);
      await cleanupE2eWalletState();

      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(
        tester,
        '$_fundedAmountText $mobileE2eTicker',
      );

      final accountUuid = await accountUuidAtOrder(0);
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        (initialChain['zcashdHeight'] as num).toInt(),
      );

      await postDriver('/activate', const {});
      await _waitForIronwoodSync(tester, container);
      await openMobilePrivateMigrationReview(tester);

      final plan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      expect(plan, isNotNull);
      final approvedPlan = plan!;
      expect(approvedPlan.totalInputZatoshi, _fundedAmount);
      expect(
        approvedPlan.denominationSplitStageCount,
        _expectedSplitStageCount,
      );
      expect(approvedPlan.plannedBatchCount, _expectedMigrationBatchCount);
      expect(
        approvedPlan.targetValuesZatoshi,
        hasLength(_expectedMigrationBatchCount),
      );

      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.denominationSplitTotalCount == _expectedSplitStageCount &&
            status.denominationSplitCompletedCount == 0 &&
            status.pendingSplitStageCount == _expectedSplitStageCount,
        description: 'first mobile many-note split stage',
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);

      for (
        var completedStageCount = 0;
        completedStageCount < _expectedSplitStageCount;
        completedStageCount++
      ) {
        await waitForMobileRegtestMempoolSize(tester, 1);
        await postDriver('/mine', const {'blocks': 10});
        await waitForMobileRegtestMigrationStatus(
          tester,
          accountUuid,
          (status) =>
              status.activeRunId == runId &&
              status.denominationSplitCompletedCount == completedStageCount + 1,
          description:
              'mobile many-note split confirmation '
              '${completedStageCount + 1}/$_expectedSplitStageCount',
          timeout: const Duration(minutes: 10),
        );
      }

      final scheduled = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.denominationSplitCompletedCount ==
                _expectedSplitStageCount &&
            status.scheduledBroadcasts.length == _expectedMigrationBatchCount,
        description: 'mobile many-note migration schedule',
        timeout: const Duration(minutes: 10),
      );
      expect(scheduled.targetValuesZatoshi, approvedPlan.targetValuesZatoshi);
      expect(
        scheduled.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        hasLength(_expectedMigrationBatchCount),
      );

      final submitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
        timeout: const Duration(minutes: 10),
      );
      expect(submitted.activeRunId, runId);
      expect(
        submitted.broadcastedTxCount + submitted.confirmedTxCount,
        submitted.totalCount,
      );

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.activeRunId == null,
        description: 'completed mobile many-note migration',
      );
      expect(complete.activeRunId, isNull);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      final orchardResidual = balance.orchard + balance.uneconomicValue;
      expect(balance.ironwood, approvedPlan.totalMigratableZatoshi);
      expect(orchardResidual, approvedPlan.orchardChangeZatoshi ?? BigInt.zero);
      expect(
        _fundedAmount - balance.ironwood - orchardResidual,
        approvedPlan.estimatedTotalFeeZatoshi,
      );
      await waitForHome(tester);
    },
    timeout: Timeout(Duration(minutes: _fundedNoteCount >= 100 ? 90 : 30)),
  );
}

Future<void> _waitForIdleSync(
  WidgetTester tester,
  ProviderContainer container,
  int targetHeight,
) {
  return pumpUntil(
    tester,
    () {
      final sync = container.read(syncProvider).value;
      return sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= targetHeight;
    },
    description: 'idle mobile many-note sync at $targetHeight',
    timeout: const Duration(minutes: 5),
  );
}

Future<void> _waitForIronwoodSync(
  WidgetTester tester,
  ProviderContainer container,
) {
  return pumpUntil(
    tester,
    () {
      final chain = container.read(chainUpgradeStatusProvider).value;
      final sync = container.read(syncProvider).value;
      return chain?.ironwoodActiveAtTip == true &&
          sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= 500;
    },
    description: 'active Ironwood many-note mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
