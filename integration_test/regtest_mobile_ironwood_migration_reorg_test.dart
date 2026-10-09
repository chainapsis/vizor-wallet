import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

final _fundedAmount = BigInt.from(1_100_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'rebuilds a mobile migration after its denomination split is reorged',
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
      await waitForShieldedBalance(tester, '0.011 $mobileE2eTicker');

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
      await openMobilePrivateMigrationOptions(tester);

      final plan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
        spacePreparationBroadcasts: false,
      );
      expect(plan, isNotNull);
      final approvedPlan = plan!;

      await startMobilePrivateMigration(tester);
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'initial mobile denomination split',
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);

      await waitForMobileRegtestMempoolSize(tester, 1);
      final denominationTxids = _txids(await getDriver('/mempool'), 'txids');
      expect(denominationTxids, hasLength(1));
      await postDriver('/mine', const {'blocks': 10});
      final scheduled = await prepareMobilePrivateMigrationSchedule(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.scheduledBroadcasts.isNotEmpty,
        description: 'initial mobile migration schedule',
        timeout: const Duration(minutes: 10),
      );
      expect(scheduled.targetValuesZatoshi, approvedPlan.targetValuesZatoshi);

      final firstChild = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
        submittedTarget: 1,
      );
      expect(firstChild.activeRunId, runId);
      expect(
        firstChild.broadcastedTxCount + firstChild.confirmedTxCount,
        greaterThan(0),
      );

      logE2e('reorging the mobile denomination split');
      late final Map<String, Object?> reorg;
      if (installedE2eRuntimeCaseManifest == null) {
        reorg = await postDriver('/reorg', const {'forkHeight': 500});
      } else {
        final children = firstChild.scheduledBroadcasts
            .where(
              (entry) =>
                  entry.status == 'broadcasted' || entry.status == 'confirmed',
            )
            .map((entry) => entry.txidHex)
            .toList();
        expect(children, isNotEmpty);
        expect(
          _txids(await getDriver('/mempool'), 'txids'),
          containsAll(children),
        );
        // The child was accepted against the mined denomination's Orchard
        // anchor. Invalidating that parent removes the anchor, so only restore
        // the denomination bytes; requiring the child in the fork-parent
        // mempool would demand a consensus-invalid transaction.
        final proof = await postDriver('/reorg-hold-fork', {
          'fork_height': 500,
          'required_txids': denominationTxids,
        });
        final restoration = proof['reintroduction'] as Map<String, Object?>;
        expect(
          _txids(restoration, 'invalidated_pending_txids'),
          containsAll(children),
        );
        reorg = {
          'oldTip': proof['old_tip_height'],
          'newTip': proof['new_tip_height'],
          'oldTipHash': proof['old_tip_hash'],
          'newTipHash': proof['new_tip_hash'],
          'heldTxids': proof['held_txids'],
          'reintroducedTxids': proof['reintroduced_txids'],
        };
      }
      expect(reorg['newTip'], (reorg['oldTip'] as int) + 1);
      expect(reorg['newTipHash'], isNot(reorg['oldTipHash']));
      final heldTransactions = _txids(reorg, 'heldTxids');
      final reintroducedDenominations = _txids(reorg, 'reintroducedTxids');
      expect(reintroducedDenominations, isNotEmpty);
      expect(reintroducedDenominations, containsAll(denominationTxids));

      final rolledBack = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingTxCount == 0 &&
            status.denominationSplitCompletedCount <
                status.denominationSplitTotalCount,
        description: 'mobile denomination reorg rollback',
      );
      expect(rolledBack.activeRunId, runId);

      await _releaseTransactions(reintroducedDenominations);
      await postDriver('/mine', const {'blocks': 10});
      final rebuilt = await prepareMobilePrivateMigrationSchedule(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.scheduledBroadcasts.isNotEmpty,
        description: 'rebuilt mobile migration schedule',
        timeout: const Duration(minutes: 10),
      );
      expect(rebuilt.totalCount, firstChild.totalCount);
      expect(rebuilt.targetValuesZatoshi, approvedPlan.targetValuesZatoshi);

      // The pre-reorg child may have the same transaction ID as its rebuilt
      // counterpart. Releasing all held transactions is valid in either case.
      await _releaseTransactions(heldTransactions);
      final submitted = await advanceMobileRegtestMigrationSchedule(
        tester,
        accountUuid,
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
        description: 'completed mobile migration after denomination reorg',
      );
      expect(complete.confirmedTxCount, complete.totalCount);

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
      markMobileE2eAssertionsCompleted();
    },
    timeout: const Timeout(Duration(minutes: 30)),
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
    description: 'idle mobile reorg sync at $targetHeight',
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
    description: 'active Ironwood mobile reorg sync',
    timeout: const Duration(minutes: 5),
  );
}

List<String> _txids(Map<String, Object?> payload, String key) {
  return (payload[key] as List<Object?>).cast<String>();
}

Future<void> _releaseTransactions(List<String> txids) async {
  if (txids.isEmpty) return;
  await postDriver(
    installedE2eRuntimeCaseManifest == null
        ? '/reorg/release'
        : '/release-held',
    {'txids': txids},
  );
}
