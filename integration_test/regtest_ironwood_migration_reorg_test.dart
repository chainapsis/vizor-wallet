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
        spacePreparationBroadcasts: true,
      );
      expect(plan, isNotNull);
      await openPrivateMigrationReview(tester);
      await startPrivateMigrationFromReview(tester);

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
      final denominationTxids = await _broadcastDenominationSplit(
        tester,
        accountUuid,
      );
      expect(denominationTxids, hasLength(1));

      await prepareDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
      );
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
      // The child spends against the mined split's anchor, which the fork
      // removes, so only the split can return to the mempool.
      final denominationReorg = await _reorg(500, denominationTxids);
      expect(
        denominationReorg['new_tip_height'],
        (denominationReorg['old_tip_height'] as int) + 1,
      );
      expect(
        denominationReorg['new_tip_hash'],
        isNot(denominationReorg['old_tip_hash']),
      );
      final heldAfterDenominationReorg = _txids(
        denominationReorg,
        'held_txids',
      );
      final reintroducedDenominations = _txids(
        denominationReorg,
        'reintroduced_txids',
      );
      expect(reintroducedDenominations, containsAll(denominationTxids));

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
      // Confirm the released split in one call. Once the split is mined again
      // the app resends the reorged child, which must stay unmined until the
      // child reorg below mines it in a block of its own.
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await prepareDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        accountUuid,
      );
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
      await _waitForSubmittedChildInMempool(rebuiltChild);

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
      final childReorg = await _reorg(
        childForkHeight,
        _broadcastTxids(minedChild, 'confirmed'),
      );
      final reintroducedChildren = _txids(childReorg, 'reintroduced_txids');
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

      await _releaseTransactions(_txids(childReorg, 'held_txids'));
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

/// The txids of the run's scheduled broadcasts in [state].
List<String> _broadcastTxids(rust_sync.MigrationStatus status, String state) {
  return status.scheduledBroadcasts
      .where((broadcast) => broadcast.status == state)
      .map((broadcast) => broadcast.txidHex)
      .toList();
}

/// Returns the txids of the run's denomination split from the mempool.
/// Desktop may schedule the split a few blocks ahead, so this mines up to its
/// scheduled height first.
Future<List<String>> _broadcastDenominationSplit(
  WidgetTester tester,
  String accountUuid,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final txids = _txids(
      await ironwoodDriverGet(_driverUrl, '/mempool'),
      'txids',
    );
    if (txids.isNotEmpty) return txids;
    final status = await desktopRegtestMigrationStatus(accountUuid);
    final scheduled = [
      for (final stage in status.preparationTransactions ?? const [])
        if (stage.state ==
            rust_sync.MigrationPreparationTransactionState.scheduled)
          stage.scheduledHeight ?? stage.plannedHeight,
    ]..sort();
    final tip =
        (await ironwoodDriverGet(_driverUrl, '/status'))['zcashdHeight'] as int;
    if (scheduled.isNotEmpty && scheduled.first > tip) {
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: {'blocks': scheduled.first - tip},
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  fail('The denomination split did not reach the mempool.');
}

/// Waits until the app has resent the run's submitted child to the mempool.
Future<void> _waitForSubmittedChildInMempool(
  rust_sync.MigrationStatus status,
) async {
  final submitted = _broadcastTxids(status, 'broadcasted').toSet();
  expect(submitted, isNotEmpty);
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final mempool = await ironwoodDriverGet(_driverUrl, '/mempool');
    final txids = (mempool['txids'] as List<Object?>).cast<String>();
    if (txids.any(submitted.contains)) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  fail('The submitted Ironwood child did not return to the mempool.');
}

/// Replaces the chain above [forkHeight] with a branch one block longer. The
/// fixture returns [required] to the mempool and keeps the mempool's
/// transactions out of blocks until they are released.
Future<Map<String, Object?>> _reorg(int forkHeight, List<String> required) {
  return ironwoodDriverPost(
    _driverUrl,
    '/reorg-hold-fork',
    payload: {'fork_height': forkHeight, 'required_txids': required},
  );
}

Future<void> _releaseTransactions(List<String> txids) async {
  if (txids.isEmpty) return;
  await ironwoodDriverPost(
    _driverUrl,
    '/release-held',
    payload: {'txids': txids},
  );
}
