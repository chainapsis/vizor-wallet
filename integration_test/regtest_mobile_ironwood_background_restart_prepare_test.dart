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
    'persists one proof without broadcasting before process restart',
    (tester) async {
      tolerateRenderOverflows();
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
        description: 'proof-restart denomination run',
      );
      expect(started.activeRunId, isNotNull);
      expect(started.pendingTxCount, 0);
      expect(started.signedChildPcztCount, greaterThanOrEqualTo(2));

      await pauseFlutterAndQuiesceMigrationForNativeWakes(tester, container);
      final paused = await mobileRegtestMigrationStatus(accountUuid);
      expect(paused.pendingTxCount, started.pendingTxCount);
      expect(paused.signedChildPcztCount, started.signedChildPcztCount);
      expect(
        paused.broadcastedTxCount + paused.confirmedTxCount,
        started.broadcastedTxCount + started.confirmedTxCount,
      );
      await postDriver('/mine', const {'blocks': 50});
      final proofed = await _runUntilOneProofIsPersisted(
        accountUuid: accountUuid,
        initialStatus: paused,
      );

      expect(proofed.activeRunId, paused.activeRunId);
      expect(proofed.pendingTxCount, 1);
      expect(proofed.signedChildPcztCount, paused.signedChildPcztCount - 1);
      expect(proofed.broadcastedTxCount + proofed.confirmedTxCount, 0);
      expect(proofed.scheduledBroadcasts, hasLength(1));
      final chain = await getDriver('/status');
      expect(
        proofed.scheduledBroadcasts.single.scheduledHeight,
        lessThanOrEqualTo((chain['zcashdHeight'] as num).toInt()),
      );
      await waitForNativeBackgroundMempoolSize(0);

      await snapshotWalletDbToDriver();
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<rust_sync.MigrationStatus> _runUntilOneProofIsPersisted({
  required String accountUuid,
  required rust_sync.MigrationStatus initialStatus,
}) async {
  var previous = initialStatus;
  final maxWakes = initialStatus.totalCount * 2 + 4;
  for (var wake = 0; wake < maxWakes; wake++) {
    final result = await runNativeBackgroundMigrationWake();
    final current = await mobileRegtestMigrationStatus(accountUuid);
    final proofDelta = current.pendingTxCount - previous.pendingTxCount;
    final signedChildDelta =
        previous.signedChildPcztCount - current.signedChildPcztCount;
    final submitted = current.broadcastedTxCount + current.confirmedTxCount;

    expect(proofDelta, inInclusiveRange(0, 1));
    expect(signedChildDelta, proofDelta);
    expect(submitted, 0);
    expect(current.activeRunId, initialStatus.activeRunId);
    if (proofDelta == 1) {
      expect(result['outcome'], anyOf('preparing', 'waiting'));
      return current;
    }

    previous = current;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail('Native background wakes did not persist a proof before restart.');
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
    description: 'idle mobile wallet sync before proof restart',
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
    description: 'active Ironwood chain before proof restart',
    timeout: const Duration(minutes: 5),
  );
}
