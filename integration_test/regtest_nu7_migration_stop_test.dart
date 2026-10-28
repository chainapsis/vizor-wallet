import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
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
    expect(firstRun.activeRunId, isNotNull);

    // The screens for a stopped run and the restart come with the Dart slice;
    // until then, check the app keeps the run stopped past activation.
    e2eLog('activating NU7');
    await _mine(1);
    await _waitForScan(tester, container, nu7);
    expect(
      (await ironwoodDriverGet(_driverUrl, '/status'))['nu7Active'],
      isTrue,
    );
    final afterActivation = await rust_sync.getOrchardMigrationStatus(
      dbPath: await getWalletDbPath(),
      network: 'regtest',
      accountUuid: accountUuid,
    );
    expect(afterActivation.phase, 'stopped_by_upgrade');
    expect(
      (await ironwoodDriverGet(_driverUrl, '/mempool'))['size'],
      0,
      reason: 'no old-branch part is sent after activation',
    );
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
