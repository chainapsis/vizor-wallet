@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/migration/models/ironwood_migration_phases.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/mobile_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'stops a mobile Private migration at NU7 and moves the rest under NU7',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(cleanupE2eWalletState);
      await cleanupE2eWalletState();

      final chain = await getDriver('/status');
      final nu7 = (chain['nu7ActivationHeight'] as num).toInt();
      expect(chain['nu7Active'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await openMobilePrivateMigrationOptions(tester);
      await startMobilePrivateMigration(tester);
      final accountUuid = await accountUuidAtOrder(0);
      final firstRun = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId != null,
        description: 'first mobile migration run',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp).first),
      );
      await _prepareSchedule(
        tester,
        container,
        accountUuid,
        mineBelow: nu7 - 11,
      );
      await leaveMobilePrivateMigrationStatusForHome(tester);

      // Jump to the hold window, then let the app see each block before NU7.
      final tip = await _tip();
      final window = rust_wallet.getNetworkUpgradeWindow(
        network: 'regtest',
        tipHeight: BigInt.from(tip),
      )!;
      expect(window.nextActivationHeight.toInt(), nu7);
      // Migrations hold from the tip 11 blocks before activation.
      final holdStarts = nu7 - 11;
      if (tip < holdStarts) {
        await _mine(holdStarts - tip);
      }
      await _waitForScan(tester, container, holdStarts);
      for (var height = holdStarts; height < nu7 - 1; height++) {
        await _mine(1);
        await _waitForScan(tester, container, height + 1);
        final mempool = await getDriver('/mempool');
        expect(
          mempool['size'],
          0,
          reason: 'no migration part may be broadcast at ${height + 1}',
        );
      }

      final stopped = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.phase == kIronwoodMigrationStoppedByUpgradePhase,
        description: 'run stopped by the upgrade',
      );
      expect(stopped.activeRunId, isNull);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_home_ironwood_migration_stopped_icon'),
          ),
        ),
        description: 'stopped migration on the mobile home banner',
      );

      logE2e('activating NU7');
      await _mine(1);
      await _waitForScan(tester, container, nu7);
      expect((await getDriver('/status'))['nu7Active'], isTrue);

      await tapWidget(
        tester,
        const ValueKey('mobile_home_ironwood_migration_banner'),
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_upgrade_stop_move_remaining'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_ironwood_options_continue_button')),
        ),
        description: 'migration options for the remainder',
      );
      expect(find.text('How to Move the Rest'), findsOneWidget);
      await startMobilePrivateMigration(tester);
      final secondRun = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null &&
            status.activeRunId != firstRun.activeRunId,
        description: 'second run under NU7',
      );
      expect(secondRun.activeRunId, isNot(firstRun.activeRunId));
      // The rest reuses prepared notes and needs no preparation, so the start
      // screen would only hand over to the status screen mid-broadcast. Open
      // the status screen from home before advancing the schedule.
      await leaveMobilePrivateMigrationStatusForHome(tester);
      await tapWidget(
        tester,
        const ValueKey('mobile_home_ironwood_migration_banner'),
      );
      await pumpUntil(
        tester,
        () =>
            find
                .byKey(const ValueKey('mobile_ironwood_migration_back_scope'))
                .evaluate()
                .length ==
            1,
        description: 'second run status screen',
        timeout: const Duration(seconds: 30),
      );

      final scheduled = await _prepareSchedule(tester, container, accountUuid);
      for (final part in scheduled.scheduledBroadcasts) {
        final start = part.scheduleStartHeight;
        if (start == null) continue;
        expect(
          (part.scheduledHeight - start) % 3,
          0,
          reason: 'NU7 delays span whole 75-second reference blocks',
        );
      }
      await advanceMobileRegtestMigrationSchedule(tester, accountUuid);
      await _mine(10);
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.phase == kIronwoodMigrationCompletePhase,
        description: 'completed second run',
        timeout: const Duration(minutes: 5),
      );
      expect(complete.confirmedTxCount, complete.totalCount);
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

/// Mines through denomination preparation one block at a time and lets the
/// status screen approve proofs, until the run has a broadcast schedule.
Future<rust_sync.MigrationStatus> _prepareSchedule(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid, {
  int? mineBelow,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 12));
  bool preparing(rust_sync.MigrationStatus status) =>
      status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase;
  while (DateTime.now().isBefore(deadline)) {
    final status = await mobileRegtestMigrationStatus(accountUuid);
    if (!preparing(status) && status.scheduledBroadcasts.isNotEmpty) {
      return status;
    }
    final tip = await _tip();
    if (mineBelow != null && tip + 1 >= mineBelow) {
      fail('Preparation reached $tip, too close to the upgrade hold.');
    }
    logE2e(
      'schedule prep: phase=${status.phase} proofReady=${status.proofReady} '
      'proofWindow=${status.nextProofWindowHeight} tip=$tip',
    );
    // A proof needs the prepared notes deep enough to anchor it.
    if (preparing(status) ||
        (status.phase == kIronwoodMigrationReadyToMigratePhase &&
            status.proofReady != true)) {
      await _mine(1);
      await _waitForScan(tester, container, tip + 1);
      continue;
    }
    final proofWindow = status.nextProofWindowHeight;
    if (proofWindow != null && proofWindow > tip) {
      await _mine(proofWindow - tip);
      await _waitForScan(tester, container, proofWindow);
      continue;
    }
    // Returns as soon as the next preparation layer needs blocks again.
    await prepareMobilePrivateMigrationSchedule(
      tester,
      accountUuid,
      (status) =>
          preparing(status) ||
          status.scheduledBroadcasts.isNotEmpty ||
          (status.phase == kIronwoodMigrationReadyToMigratePhase &&
              status.proofReady != true),
      description: 'mobile migration broadcast schedule',
      timeout: deadline.difference(DateTime.now()),
    );
  }
  fail('Timed out mining through mobile migration preparation.');
}

Future<int> _tip() async =>
    ((await getDriver('/status'))['zcashdHeight'] as num).toInt();

Future<void> _mine(int blocks) => postDriver('/mine', {'blocks': blocks});

/// Waits until sync has scanned [height] and the app has had a pass to act on it.
Future<void> _waitForScan(
  WidgetTester tester,
  ProviderContainer container,
  int height,
) async {
  await pumpUntil(
    tester,
    () {
      final sync = container.read(syncProvider).value;
      return sync != null &&
          !sync.isSyncing &&
          sync.isSyncComplete &&
          sync.scannedHeight >= height;
    },
    description: 'wallet scan through $height',
    timeout: const Duration(minutes: 3),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}
