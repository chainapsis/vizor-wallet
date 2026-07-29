import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'mobile_regtest_flow.dart';

const _backgroundMigrationChannel = MethodChannel(
  'com.zcash.wallet/background_migration',
);

Future<Map<String, Object?>> runNativeBackgroundMigrationWake() async {
  final result = await _backgroundMigrationChannel
      .invokeMapMethod<String, Object?>('runOnceForTesting');
  if (result == null) {
    fail('Native background migration wake returned no result.');
  }
  return result;
}

Future<Map<String, Object?>> waitForNativeBackgroundMempoolSize(
  int expected, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  Map<String, Object?>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await getDriver('/mempool');
    if (last['size'] == expected) return last;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for mempool size $expected. Last: $last');
}

Future<Map<String, Object?>> waitForNativeBackgroundMempoolTxid(
  String expectedTxid, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  final acceptedTxids = {
    expectedTxid.toLowerCase(),
    reverseTxidHex(expectedTxid).toLowerCase(),
  };
  Map<String, Object?>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await getDriver('/mempool');
    final txids = (last['txids'] as List<Object?>? ?? const <Object?>[])
        .whereType<String>()
        .map((txid) => txid.toLowerCase())
        .toList();
    if (last['size'] == 1 &&
        txids.length == 1 &&
        acceptedTxids.contains(txids.single)) {
      return last;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for migration txid $expectedTxid in the mempool. '
    'Last: $last',
  );
}

Future<void> revokeAllBackgroundMigrationAuthorization({
  bool ignoreErrors = false,
}) async {
  try {
    final revoked = await _backgroundMigrationChannel.invokeMethod<bool>(
      'revokeAll',
    );
    if (revoked != true && !ignoreErrors) {
      fail('Failed to clear native background migration authorization.');
    }
    final resumed = await _backgroundMigrationChannel.invokeMethod<bool>(
      'resume',
    );
    if (resumed != true && !ignoreErrors) {
      fail('Failed to resume native background migration after cleanup.');
    }
  } catch (_) {
    if (!ignoreErrors) rethrow;
  }
}

void pauseFlutterForNativeBackgroundMigration(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void resumeFlutterAfterNativeBackgroundMigration(WidgetTester tester) {
  if (tester.binding.lifecycleState != AppLifecycleState.paused) return;
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

Future<void> pauseFlutterAndQuiesceMigrationForNativeWakes(
  WidgetTester tester,
  ProviderContainer container,
) async {
  pauseFlutterForNativeBackgroundMigration(tester);
  await pumpUntil(
    tester,
    () {
      final coordinator = container.read(ironwoodMigrationCoordinatorProvider);
      final sync = container.read(syncProvider).value;
      return coordinator.advancingAccounts.isEmpty &&
          (sync == null || !sync.isSyncing);
    },
    description: 'foreground migration work to quiesce',
    timeout: const Duration(minutes: 2),
  );

  final quiesced = await _backgroundMigrationChannel.invokeMethod<bool>(
    'quiesce',
  );
  if (quiesced != true) {
    fail('Failed to quiesce native background migration for E2E control.');
  }
  final resumed = await _backgroundMigrationChannel.invokeMethod<bool>(
    'resumeWithoutSchedulingForTesting',
  );
  if (resumed != true) {
    fail('Failed to resume test-controlled native migration wakes.');
  }
}

Future<rust_sync.MigrationStatus> runNativeDueWakesUntilSubmitted({
  required String accountUuid,
  required rust_sync.MigrationStatus initialStatus,
  required int submittedTarget,
  int minimumProofsCreated = 0,
}) async {
  var previous = initialStatus;
  var backgroundProofsCreated = 0;
  var expectDueBroadcast = false;
  final maxWakes = initialStatus.totalCount * 4 + 4;

  for (var wake = 0; wake < maxWakes; wake++) {
    final result = await runNativeBackgroundMigrationWake();
    final current = await mobileRegtestMigrationStatus(accountUuid);
    final previousSubmitted =
        previous.broadcastedTxCount + previous.confirmedTxCount;
    final currentSubmitted =
        current.broadcastedTxCount + current.confirmedTxCount;
    final proofDelta = current.pendingTxCount - previous.pendingTxCount;
    final submittedDelta = currentSubmitted - previousSubmitted;
    final signedChildDelta =
        previous.signedChildPcztCount - current.signedChildPcztCount;

    expect(
      proofDelta,
      inInclusiveRange(0, 1),
      reason: 'one background wake must create at most one proof',
    );
    expect(
      submittedDelta,
      inInclusiveRange(0, 1),
      reason: 'one background wake must broadcast at most one child',
    );
    expect(
      proofDelta + submittedDelta,
      lessThanOrEqualTo(1),
      reason: 'a background wake must not both prove and broadcast',
    );
    expect(
      signedChildDelta,
      proofDelta,
      reason: 'persisting one proof must consume one unpromoted signed child',
    );
    if (expectDueBroadcast) {
      expect(
        submittedDelta,
        1,
        reason: 'an already-due child must be sent before another proof',
      );
    }
    if (proofDelta == 1) {
      expect(
        result['outcome'],
        anyOf('preparing', 'waiting'),
        reason: 'a persisted proof must not be reported as a failed wake',
      );
    }
    if (submittedDelta == 1) {
      expect(result['outcome'], 'advanced');
    }

    backgroundProofsCreated += proofDelta;
    expectDueBroadcast = proofDelta == 1;
    expect(current.activeRunId, initialStatus.activeRunId);
    expect(current.totalCount, initialStatus.totalCount);
    if (currentSubmitted >= submittedTarget) {
      expect(
        backgroundProofsCreated,
        greaterThanOrEqualTo(minimumProofsCreated),
        reason: 'the native background runner must persist the new proof',
      );
      return current;
    }

    previous = current;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail('Native background wakes did not submit $submittedTarget children.');
}
