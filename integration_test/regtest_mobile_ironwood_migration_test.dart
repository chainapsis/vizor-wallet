import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_state_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

const _fundedAmountZatoshi = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
  defaultValue: 1095000,
);
final _fundedAmount = BigInt.from(_fundedAmountZatoshi);
final _fundedAmountText = ZecAmount.fromZatoshi(
  _fundedAmount,
).compactBalance.amountText;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'migrates a mobile software wallet from Orchard to Ironwood',
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

      logE2e('activating Ironwood while the mobile app is running');
      // The zcashd chain activates NU6.3 here; the Zebra chain NU6.3 and NU7.
      await postDriver('/activate', const {});
      final activeChain = await getDriver('/status');
      expect(activeChain['ironwoodActive'], isTrue);
      await _waitForIronwoodSync(
        tester,
        container,
        (activeChain['zcashdHeight'] as num).toInt(),
      );
      await openMobilePrivateMigrationOptions(tester);

      final approvedPlan = await container.read(
        ironwoodMigrationPrivatePlanProvider.future,
      );
      expect(approvedPlan, isNotNull);
      expect(approvedPlan!.denominationSplitStageCount, 1);
      expect(approvedPlan.plannedBatchCount, 1);
      expect(approvedPlan.totalMigratableZatoshi, BigInt.from(1000000));
      // A 16-action split and a 3-action part, at 5,000 zatoshis per action
      // before NU7 and 1,000 from it (ZIP 2009).
      final marginalFee = activeChain['nu7Active'] == true ? 1000 : 5000;
      expect(
        approvedPlan.estimatedTotalFeeZatoshi,
        BigInt.from((16 + 3) * marginalFee),
      );

      await startMobilePrivateMigration(tester);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_ironwood_view_preparation_schedule_button'),
          ),
        ),
        description: 'mobile migration preparation status screen',
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await accountUuidAtOrder(0);
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'mobile denomination migration run',
      );
      expect(started.activeRunId, isNotNull);

      await postDriver('/mine', const {'blocks': 10});
      final scheduled = await _prepareSchedule(tester, container, accountUuid);
      expect(scheduled.totalCount, approvedPlan.plannedBatchCount);
      expect(
        scheduled.scheduledBroadcasts.map((entry) => entry.valueZatoshi),
        approvedPlan.scheduledTransfers.map((entry) => entry.valueZatoshi),
      );

      final firstSubmitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
        submittedTarget: 1,
      );
      expect(
        firstSubmitted.broadcastedTxCount + firstSubmitted.confirmedTxCount,
        1,
      );

      final allSubmitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
      );
      expect(
        allSubmitted.broadcastedTxCount + allSubmitted.confirmedTxCount,
        allSubmitted.totalCount,
      );

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == status.totalCount &&
            status.activeRunId == null,
        description: 'completed mobile Ironwood migration',
        timeout: const Duration(minutes: 5),
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

      await tapUntilVisible(
        tester,
        trigger: find.text('Done').hitTestable(),
        outcome: find.byKey(const ValueKey('mobile_home_shielded_balance')),
        description: 'completed migration result to return home',
        timeout: const Duration(minutes: 1),
      );
      await pumpUntil(
        tester,
        () => !tester.any(
          find.byKey(const ValueKey('mobile_home_ironwood_migration_banner')),
        ),
        description: 'completed migration CTA to disappear',
      );
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

/// Lets the status screen approve proofs until the run has a broadcast
/// schedule. A proof needs the prepared notes deep enough to anchor it, which
/// under NU7 can take more blocks than were mined above, so a run waiting for
/// that gets one block at a time, as `regtest_mobile_nu7_migration_stop_test`
/// does.
Future<rust_sync.MigrationStatus> _prepareSchedule(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 10));
  bool needsBlock(rust_sync.MigrationStatus status) =>
      status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase ||
      (status.phase == kIronwoodMigrationReadyToMigratePhase &&
          status.proofReady != true);
  while (DateTime.now().isBefore(deadline)) {
    final status = await mobileRegtestMigrationStatus(accountUuid);
    if (status.scheduledBroadcasts.isNotEmpty) return status;
    if (needsBlock(status)) {
      final tip = ((await getDriver('/status'))['zcashdHeight'] as num).toInt();
      logE2e(
        'schedule prep: phase=${status.phase} '
        'proofReady=${status.proofReady} tip=$tip; mining one block',
      );
      await postDriver('/mine', const {'blocks': 1});
      await _waitForIdleSync(tester, container, tip + 1);
      continue;
    }
    // Returns as soon as the run needs another block.
    await prepareMobilePrivateMigrationSchedule(
      tester,
      accountUuid,
      (status) => status.scheduledBroadcasts.isNotEmpty || needsBlock(status),
      description: 'mobile persisted migration schedule',
      timeout: deadline.difference(DateTime.now()),
    );
  }
  fail('Timed out preparing the mobile migration broadcast schedule.');
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
    description: 'idle mobile wallet sync at $targetHeight',
    timeout: const Duration(minutes: 5),
  );
}

Future<void> _waitForIronwoodSync(
  WidgetTester tester,
  ProviderContainer container,
  int activatedHeight,
) {
  return pumpUntil(
    tester,
    () {
      final chain = container.read(chainUpgradeStatusProvider).value;
      final sync = container.read(syncProvider).value;
      return chain?.ironwoodActiveAtTip == true &&
          sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= activatedHeight;
    },
    description: 'active Ironwood chain and completed mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
