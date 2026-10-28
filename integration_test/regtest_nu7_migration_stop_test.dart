import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/migration/models/ironwood_migration_phases.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39080',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets('stops a Private migration at NU7 and moves the rest under NU7', (
    tester,
  ) async {
    addTearDown(cleanupDesktopRegtestWallet);
    await cleanupDesktopRegtestWallet();

    final chain = await ironwoodDriverGet(_driverUrl, '/status');
    final nu7 = (chain['nu7ActivationHeight'] as num).toInt();
    expect(chain['nu7Active'], isFalse);

    await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
    await importDesktopRegtestWallet(tester);
    await _keepEndpointIfStallPromptShows(tester);

    await pumpUntil(
      tester,
      () => tester.any(
        find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
      ),
      description: 'Ironwood announcement for the Orchard balance',
      timeout: const Duration(minutes: 5),
    );
    await dismissIronwoodAnnouncement(tester);
    await openPrivateMigrationReview(tester);
    await startPrivateMigrationFromReview(tester);
    final accountUuid = await firstDesktopRegtestAccountUuid();
    final firstRun = await waitForDesktopRegtestMigrationStatus(
      tester,
      accountUuid,
      (status) => status.activeRunId != null,
      description: 'first migration run',
    );
    await waitForDesktopActiveMigrationStatus(tester);
    await leaveDesktopMigrationStatusForHome(tester);
    await prepareDesktopRegtestMigrationSchedule(
      tester,
      _driverUrl,
      accountUuid,
    );

    // Jump to the hold window, then let the app see each block before NU7.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp).first),
    );
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
      final mempool = await ironwoodDriverGet(_driverUrl, '/mempool');
      expect(
        mempool['size'],
        0,
        reason: 'no migration part may be broadcast at ${height + 1}',
      );
    }

    final stopped = await waitForDesktopRegtestMigrationStatus(
      tester,
      accountUuid,
      (status) => status.phase == 'stopped_by_upgrade',
      description: 'run stopped by the upgrade',
    );
    expect(stopped.activeRunId, isNull);
    await pumpUntil(
      tester,
      () => tester.any(
        find.byKey(
          const ValueKey('home_desktop_ironwood_migration_stopped_icon'),
        ),
      ),
      description: 'stopped migration on home',
    );

    e2eLog('activating NU7');
    await _mine(1);
    await _waitForScan(tester, container, nu7);
    expect(
      (await ironwoodDriverGet(_driverUrl, '/status'))['nu7Active'],
      isTrue,
    );

    await tapAppButton(
      tester,
      const ValueKey('home_desktop_ironwood_migration_cta_button'),
    );
    await tapAppButton(
      tester,
      const ValueKey('ironwood_upgrade_stop_move_remaining'),
    );
    await pumpUntil(
      tester,
      () => tester.any(
        find.byKey(const ValueKey('ironwood_migration_private_option')),
      ),
      description: 'migration options for the remainder',
    );
    expect(find.text('How to move the rest'), findsOneWidget);
    await tapAppWidget(
      tester,
      const ValueKey('ironwood_migration_private_option'),
    );
    await tapAppButton(
      tester,
      const ValueKey('ironwood_migration_select_review_button'),
    );
    await startPrivateMigrationFromReview(tester);
    final secondRun = await waitForDesktopRegtestMigrationStatus(
      tester,
      accountUuid,
      (status) =>
          status.activeRunId != null &&
          status.activeRunId != firstRun.activeRunId &&
          status.scheduledBroadcasts.isNotEmpty,
      description: 'second run scheduled under NU7',
    );
    for (final part in secondRun.scheduledBroadcasts) {
      final start = part.scheduleStartHeight;
      if (start == null) continue;
      expect(
        (part.scheduledHeight - start) % 3,
        0,
        reason: 'NU7 delays span whole 75-second reference blocks',
      );
    }
    await waitForDesktopActiveMigrationStatus(tester);
    await leaveDesktopMigrationStatusForHome(tester);

    await advanceDesktopRegtestMigrationSchedule(
      tester,
      _driverUrl,
      accountUuid,
    );
    await _mine(10);
    final complete = await waitForDesktopRegtestMigrationStatus(
      tester,
      accountUuid,
      (status) => status.phase == kIronwoodMigrationCompletePhase,
      description: 'completed second run',
    );
    expect(complete.confirmedTxCount, complete.totalCount);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// Zebra regtest reports a meaningless height estimate, so the custom E2E
/// endpoint looks stalled once; keep it, which also stops it being asked again.
Future<void> _keepEndpointIfStallPromptShows(WidgetTester tester) async {
  const keep = ValueKey('rpc_endpoint_stall_keep');
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (tester.any(find.byKey(keep))) {
      e2eLog('keeping the E2E endpoint the stall prompt flagged');
      await tapAppButton(tester, keep);
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  e2eLog('no stalled-endpoint prompt appeared');
}

Future<int> _tip() async =>
    ((await ironwoodDriverGet(_driverUrl, '/status'))['zcashdHeight'] as num)
        .toInt();

Future<void> _mine(int blocks) =>
    ironwoodDriverPost(_driverUrl, '/mine', payload: {'blocks': blocks});

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
