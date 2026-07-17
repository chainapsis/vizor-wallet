import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39080',
);
final _fundedAmount = BigInt.from(1100000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'recovers denomination and Ironwood transactions across reorgs',
    (tester) async {
      addTearDown(cleanupDesktopRegtestWallet);
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      await pumpUntil(
        tester,
        () =>
            textForKey(
              tester,
              const ValueKey('home_desktop_balance_amount_text'),
            ) ==
            '0.011',
        description: 'pre-Ironwood Orchard balance',
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await firstDesktopRegtestAccountUuid();
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        initialChain['zcashdHeight'] as num,
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
      await _waitForIronwoodSync(tester, container);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'Ironwood announcement',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);
      final plan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: accountUuid,
      );
      expect(plan, isNotNull);
      await openPrivateMigrationReview(tester);
      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_authorize_start_button'),
      );

      final started = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == 'waiting_denom_confirmations' &&
            status.pendingSplitStageCount > 0,
        description: 'initial denomination broadcast',
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await prepareDesktopRegtestMigrationSchedule(tester, accountUuid);
      final firstChild = await advanceDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
        submittedTarget: 1,
      );
      expect(firstChild.activeRunId, runId);
      expect(
        firstChild.broadcastedTxCount + firstChild.confirmedTxCount,
        greaterThan(0),
      );
      expect(firstChild.totalCount, greaterThan(0));

      e2eLog('reorging the trusted denomination chain');
      final denominationReorg = await ironwoodDriverPost(
        _driverUrl,
        '/reorg',
        payload: const {'forkHeight': 500},
      );
      expect(
        denominationReorg['newTip'],
        (denominationReorg['oldTip'] as int) + 1,
      );
      expect(
        denominationReorg['newTipHash'],
        isNot(denominationReorg['oldTipHash']),
      );
      final heldAfterDenominationReorg = _txids(denominationReorg, 'heldTxids');
      final reintroducedDenominations = _txids(
        denominationReorg,
        'reintroducedTxids',
      );
      expect(reintroducedDenominations, isNotEmpty);

      final rolledBackDenomination = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.phase == 'waiting_denom_confirmations' &&
            status.pendingTxCount == 0 &&
            status.denominationSplitCompletedCount <
                status.denominationSplitTotalCount,
        description: 'denomination reorg rollback',
      );
      expect(rolledBackDenomination.activeRunId, runId);

      await _releaseTransactions(reintroducedDenominations);
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await prepareDesktopRegtestMigrationSchedule(tester, accountUuid);
      final rebuiltChild = await advanceDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
        submittedTarget: 1,
      );
      expect(rebuiltChild.activeRunId, runId);
      expect(
        rebuiltChild.broadcastedTxCount + rebuiltChild.confirmedTxCount,
        greaterThan(0),
      );
      expect(rebuiltChild.totalCount, firstChild.totalCount);

      // Release any pre-reorg child that was held. If rebuilding produced the
      // same effecting-data txid, this also releases the rebuilt transaction.
      await _releaseTransactions(heldAfterDenominationReorg);
      final beforeChildMine = await ironwoodDriverGet(_driverUrl, '/status');
      final childForkHeight = beforeChildMine['zcashdHeight'] as int;
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 1},
      );
      final minedChild = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.phase != 'complete' &&
            status.confirmedTxCount > 0,
        description: 'untrusted Ironwood child confirmation',
      );
      expect(minedChild.confirmedTxCount, greaterThan(0));

      e2eLog('reorging the untrusted Ironwood child transaction');
      final childReorg = await ironwoodDriverPost(
        _driverUrl,
        '/reorg',
        payload: {'forkHeight': childForkHeight},
      );
      final reintroducedChildren = _txids(childReorg, 'reintroducedTxids');
      expect(reintroducedChildren, isNotEmpty);
      final rolledBackChild = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.phase != 'complete' &&
            status.confirmedTxCount == 0,
        description: 'Ironwood child reorg rollback',
      );
      expect(
        rolledBackChild.phase,
        anyOf('broadcast_scheduled', 'waiting_migration_confirmations'),
      );

      await _releaseTransactions(_txids(childReorg, 'heldTxids'));
      await advanceDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
      );
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      final complete = await waitForDesktopRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) => status.activeRunId == null && status.phase == 'complete',
        description: 'completed migration after both reorgs',
      );
      expect(complete.confirmedTxCount, complete.totalCount);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: accountUuid,
      );
      final orchardResidual = balance.orchard + balance.uneconomicValue;
      expect(orchardResidual, plan!.orchardChangeZatoshi ?? BigInt.zero);
      expect(balance.ironwood, plan.totalMigratableZatoshi);
      expect(
        _fundedAmount - orchardResidual - balance.ironwood,
        plan.estimatedTotalFeeZatoshi,
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _waitForIdleSync(
  WidgetTester tester,
  ProviderContainer container,
  num targetHeight,
) {
  return pumpUntil(
    tester,
    () {
      final sync = container.read(syncProvider).value;
      return sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= targetHeight;
    },
    description: 'idle wallet sync at $targetHeight',
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
    description: 'active Ironwood chain sync',
    timeout: const Duration(minutes: 5),
  );
}

List<String> _txids(Map<String, Object?> payload, String key) {
  return (payload[key] as List<Object?>).cast<String>();
}

Future<void> _releaseTransactions(List<String> txids) async {
  if (txids.isEmpty) return;
  await ironwoodDriverPost(
    _driverUrl,
    '/reorg/release',
    payload: {'txids': txids},
  );
}
