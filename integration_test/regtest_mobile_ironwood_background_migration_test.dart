import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_background_migration_flow.dart';
import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'native background wakes cap proving and submit due children while Flutter is paused',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        resumeFlutterAfterNativeBackgroundMigration(tester);
        try {
          await postDriver('/lightwalletd/start', const {});
        } catch (_) {
          // The runner resets the stack after a failed recovery attempt.
        }
        await revokeAllBackgroundMigrationAuthorization(ignoreErrors: true);
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await revokeAllBackgroundMigrationAuthorization();
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '1.23 $mobileE2eTicker');

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
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await accountUuidAtOrder(0);
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'background migration denomination run',
      );
      expect(started.activeRunId, isNotNull);
      expect(started.totalCount, greaterThanOrEqualTo(2));
      expect(started.pendingTxCount, 0);
      expect(started.signedChildPcztCount, greaterThanOrEqualTo(2));

      final submittedBefore =
          started.broadcastedTxCount + started.confirmedTxCount;
      expect(started.totalCount - submittedBefore, greaterThanOrEqualTo(2));

      // Pause Flutter before the chain advances so no foreground coordinator
      // work can be mistaken for native background progress.
      await pauseFlutterAndQuiesceMigrationForNativeWakes(tester, container);
      final paused = await mobileRegtestMigrationStatus(accountUuid);
      expect(paused.pendingTxCount, started.pendingTxCount);
      expect(paused.signedChildPcztCount, started.signedChildPcztCount);
      expect(
        paused.broadcastedTxCount + paused.confirmedTxCount,
        submittedBefore,
      );
      // Make the denomination stage trusted and every regtest schedule offset
      // due while only the native background runner is allowed to advance.
      await postDriver('/mine', const {'blocks': 50});
      final firstProof = await _runNativeWakesUntilProofPersisted(
        accountUuid: accountUuid,
        initialStatus: paused,
      );
      final firstProofTxids = firstProof.scheduledBroadcasts
          .map((entry) => entry.txidHex)
          .toSet();
      expect(firstProofTxids, hasLength(1));

      await postDriver('/lightwalletd/stop', const {});
      final failedWake = await runNativeBackgroundMigrationWake();
      final whileOffline = await mobileRegtestMigrationStatus(accountUuid);
      expect(failedWake['outcome'], anyOf('waiting', 'failed'));
      expect(whileOffline.activeRunId, firstProof.activeRunId);
      expect(whileOffline.phase, kIronwoodMigrationFailedRecoverablePhase);
      expect(whileOffline.pendingTxCount, firstProof.pendingTxCount);
      expect(
        whileOffline.signedChildPcztCount,
        firstProof.signedChildPcztCount,
      );
      expect(
        whileOffline.broadcastedTxCount + whileOffline.confirmedTxCount,
        submittedBefore,
      );
      expect(
        whileOffline.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        firstProofTxids,
      );
      await waitForNativeBackgroundMempoolSize(0);

      await postDriver(
        '/lightwalletd/start',
        const {},
        timeout: const Duration(minutes: 5),
      );
      final recoveredWake = await runNativeBackgroundMigrationWake();
      final afterRecovery = await mobileRegtestMigrationStatus(accountUuid);
      expect(recoveredWake['outcome'], 'advanced');
      expect(afterRecovery.pendingTxCount, firstProof.pendingTxCount);
      expect(
        afterRecovery.signedChildPcztCount,
        firstProof.signedChildPcztCount,
      );
      expect(
        afterRecovery.broadcastedTxCount + afterRecovery.confirmedTxCount,
        submittedBefore + 1,
      );
      expect(
        afterRecovery.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        firstProofTxids,
      );
      await waitForNativeBackgroundMempoolTxid(firstProofTxids.single);

      final afterSecond = await runNativeDueWakesUntilSubmitted(
        accountUuid: accountUuid,
        initialStatus: afterRecovery,
        submittedTarget: submittedBefore + 2,
        minimumProofsCreated: 1,
      );

      expect(
        afterSecond.broadcastedTxCount + afterSecond.confirmedTxCount,
        submittedBefore + 2,
      );
      expect(afterSecond.activeRunId, started.activeRunId);
      expect(afterSecond.totalCount, started.totalCount);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<rust_sync.MigrationStatus> _runNativeWakesUntilProofPersisted({
  required String accountUuid,
  required rust_sync.MigrationStatus initialStatus,
}) async {
  var previous = initialStatus;
  final maxWakes = initialStatus.totalCount * 2 + 4;
  for (var wake = 0; wake < maxWakes; wake++) {
    final result = await runNativeBackgroundMigrationWake();
    final current = await mobileRegtestMigrationStatus(accountUuid);
    final previousSubmitted =
        previous.broadcastedTxCount + previous.confirmedTxCount;
    final currentSubmitted =
        current.broadcastedTxCount + current.confirmedTxCount;
    final proofDelta = current.pendingTxCount - previous.pendingTxCount;
    final signedChildDelta =
        previous.signedChildPcztCount - current.signedChildPcztCount;

    expect(proofDelta, inInclusiveRange(0, 1));
    expect(currentSubmitted, previousSubmitted);
    expect(signedChildDelta, proofDelta);
    expect(current.activeRunId, initialStatus.activeRunId);
    if (proofDelta == 1) {
      expect(result['outcome'], anyOf('preparing', 'waiting'));
      expect(current.pendingTxCount, initialStatus.pendingTxCount + 1);
      return current;
    }

    previous = current;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail('Native background wakes did not persist the first proof.');
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
    description: 'active Ironwood chain and completed mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
