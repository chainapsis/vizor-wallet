import 'dart:math';

import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'mobile_regtest_flow.dart';

const _backgroundMigrationChannel = MethodChannel(
  'com.zcash.wallet/background_migration',
);

/// Runs production signed-byte transport, not BGManager or the OS scheduler.
/// Any proofReady metadata is only a candidate, never proof-generation credit.
Future<Map<String, Object?>> runNativeMigrationOutboxTick() async {
  final result = await _backgroundMigrationChannel
      .invokeMapMethod<String, Object?>('runOutboxOnceNow');
  if (result == null) {
    fail('Native migration outbox tick returned no result.');
  }
  return result;
}

/// Separately verifies the manager denial policy; this never credits transport.
Future<void> expectNativeBackgroundManagerDeniedWithoutNotifications() async {
  final authorization = await _backgroundMigrationChannel.invokeMethod<String>(
    'getNotificationAuthorizationStatus',
  );
  expect(authorization, anyOf('notDetermined', 'denied'));
  // The debug tick reads the manager epoch, not current OS authorization.
  // Exercise the production permission gate before asserting its denial state.
  final scheduled = await _backgroundMigrationChannel.invokeMethod<bool>(
    'schedule',
  );
  expect(scheduled, isFalse);
  final result = await _backgroundMigrationChannel
      .invokeMapMethod<String, Object?>('runOnceForTesting');
  expect(result, isNotNull);
  expect(result!['outcome'], 'cancelled');
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
    final lifecycle = IronwoodMigrationBackgroundLifecycle(
      channel: _backgroundMigrationChannel,
      isIOS: true,
    );
    await IronwoodMigrationBackgroundLifecycle.runWithNewQuiescenceLease(
      () async {
        try {
          await lifecycle.quiesce();
          await lifecycle.revokeAll();
        } finally {
          // Quiescence may acquire its lease before a channel reply fails.
          await lifecycle.resumeAfterMutation();
        }
      },
    );
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

Future<void> pauseFlutterAndQuiesceMigrationForNativeOutboxTicks(
  WidgetTester tester,
  ProviderContainer container,
) async {
  pauseFlutterForNativeBackgroundMigration(tester);
  await waitForNativeMigrationDrain(
    () {
      final coordinator = container.read(ironwoodMigrationCoordinatorProvider);
      final sync = container.read(syncProvider).value;
      return coordinator.advancingAccounts.isEmpty &&
          (sync == null || !sync.isSyncing);
    },
    description: 'foreground migration work to quiesce',
    timeout: const Duration(minutes: 2),
  );

  await withNativeMigrationTransportHeld(() async {});
}

/// Live binding pumps wait for a frame that a paused app cannot schedule.
/// Observe only already in-flight work here; do not resume or render Flutter.
Future<void> waitForNativeMigrationDrain(
  bool Function() isIdle, {
  required String description,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final idle = isIdle();
    if (!DateTime.now().isBefore(deadline)) break;
    if (idle) return;
    final remaining = deadline.difference(DateTime.now());
    await Future<void>.delayed(
      remaining < const Duration(milliseconds: 100)
          ? remaining
          : const Duration(milliseconds: 100),
    );
  }
  fail('Timed out waiting for $description while Flutter was paused.');
}

/// Holds a unique native transport lease, not a Zone inherited by UI actions.
/// The test-only release enables explicit ticks without scheduling OS tasks.
Future<T> withNativeMigrationTransportHeld<T>(
  Future<T> Function() action,
) async {
  final random = Random.secure();
  final leaseId =
      'e2e-native-outbox-tick:${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  try {
    final quiesced = await _backgroundMigrationChannel.invokeMethod<bool>(
      'quiesce',
      {'leaseId': leaseId},
    );
    if (quiesced != true) {
      fail('Native transport did not quiesce its own lease.');
    }
    return await action();
  } finally {
    final released = await _backgroundMigrationChannel.invokeMethod<bool>(
      'resume',
      {'leaseId': leaseId},
    );
    if (released == null ||
        (released == false && installedE2eRuntimeCaseManifest == null)) {
      fail('Native controlled-tick lease release returned an invalid result.');
    }
    // The production resume releases this exact admission lease first. In a
    // cohort Simulator its false reply can then describe an OS schedule that
    // the notification gate or BGTaskScheduler did not accept, not a failure
    // to release the admission gate. Clear the manager's mutation state
    // through its existing debug API; real subsequent outbox ticks must still
    // prove transport admission and bytes.
    final ready = await _backgroundMigrationChannel.invokeMethod<bool>(
      'resumeWithoutSchedulingForTesting',
    );
    if (ready != true) {
      fail('Native outbox controlled-tick state did not resume.');
    }
  }
}

void expectNativeOutboxTickDidNotCreateProofs(
  rust_sync.MigrationStatus before,
  rust_sync.MigrationStatus after,
) {
  expect(after.activeRunId, before.activeRunId);
  expect(after.totalCount, before.totalCount);
  expect(
    after.pendingTxCount,
    before.pendingTxCount,
    reason: 'iOS native ticks must not generate child proofs',
  );
  expect(after.signedChildPcztCount, before.signedChildPcztCount);
  expect(
    after.scheduledBroadcasts.map((part) => part.txidHex).toSet(),
    before.scheduledBroadcasts.map((part) => part.txidHex).toSet(),
  );
}

Future<List<Map<String, Object?>>> nativeMigrationReceipts(
  String accountUuid,
  String runId,
) async {
  final records = await _backgroundMigrationChannel.invokeListMethod<Object?>(
    'listOutboxReceipts',
  );
  if (records == null) fail('Native outbox returned no receipt list.');
  return records
      .map((record) {
        if (record is! Map) fail('Native outbox returned an invalid receipt.');
        return Map<String, Object?>.from(record);
      })
      .where(
        (record) =>
            record['network'] == mobileE2eNetwork &&
            record['accountUuid'] == accountUuid &&
            record['runId'] == runId,
      )
      .toList();
}

/// A native receipt, exact signed bytes and the owned node are independent
/// evidence; the wallet DB has not reconciled that receipt while Flutter pauses.
Future<void> expectAcceptedNativeMigrationReceipt(
  Map<String, Object?> receipt,
  Set<String> preparedTxids,
) async {
  expect(receipt['outcome'], anyOf('accepted', 'acceptedEquivalent'));
  final txid = receipt['txidHex'];
  expect(txid, isA<String>());
  expect(preparedTxids, contains(txid));
  final raw = receipt['rawTransaction'];
  expect(raw, isA<Uint8List>());
  expect((raw as Uint8List).isNotEmpty, isTrue);
  final observed = await zcashdRpc<String>('getrawtransaction', [
    txid as String,
    0,
  ]);
  expect(
    observed.toLowerCase(),
    raw.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
  );
}

/// This is foreground proof coverage, never background proof credit. Only an
/// actual Prepare batch tap grants the product's one-shot approval. Holding
/// transport across UI work prevents a foreground sender from taking credit.
Future<rust_sync.MigrationStatus> prepareForegroundProofsForNativeOutboxTicks(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid,
) async {
  final before = await mobileRegtestMigrationStatus(accountUuid);
  return withNativeMigrationTransportHeld(() async {
    resumeFlutterAfterNativeBackgroundMigration(tester);
    if (!tester.any(
      find.byKey(const ValueKey('mobile_ironwood_migration_back_scope')),
    )) {
      await tapWidget(
        tester,
        const ValueKey('mobile_home_ironwood_migration_banner'),
        timeout: const Duration(minutes: 2),
      );
    }
    await prepareMobilePrivateMigrationSchedule(
      tester,
      accountUuid,
      (status) =>
          status.activeRunId == before.activeRunId &&
          status.pendingTxCount > before.pendingTxCount,
      description: 'foreground-approved signed migration transactions',
    );
    pauseFlutterForNativeBackgroundMigration(tester);
    await waitForNativeMigrationDrain(
      () =>
          container
              .read(ironwoodMigrationCoordinatorProvider)
              .advancingAccounts
              .isEmpty &&
          container.read(syncProvider).value?.isSyncing != true,
      description:
          'approved foreground proof batch to drain before native ticks',
      timeout: const Duration(minutes: 2),
    );
    final prepared = await mobileRegtestMigrationStatus(accountUuid);
    expect(prepared.pendingTxCount, greaterThan(before.pendingTxCount));
    expect(
      before.signedChildPcztCount - prepared.signedChildPcztCount,
      prepared.pendingTxCount - before.pendingTxCount,
    );
    expect(
      prepared.broadcastedTxCount + prepared.confirmedTxCount,
      before.broadcastedTxCount + before.confirmedTxCount,
    );
    expect(prepared.activeRunId, before.activeRunId);
    return prepared;
  });
}

Future<rust_sync.MigrationStatus> reconcileNativeMigrationReceipts(
  WidgetTester tester,
  ProviderContainer container,
  String accountUuid,
) async => withNativeMigrationTransportHeld(() async {
  // Public foreground recovery commits receipts. The held transport lease
  // ensures its runOutboxOnceNow cannot perform an additional SendTransaction.
  resumeFlutterAfterNativeBackgroundMigration(tester);
  final result = await container
      .read(ironwoodMigrationServiceProvider)
      .recoverDueMigrationOutbox(
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
  expect(
    result.outcome,
    IronwoodMigrationOutboxRunOutcome.temporarilyUnavailable,
  );
  final status = await mobileRegtestMigrationStatus(accountUuid);
  expect(status.activeRunId, isNotNull);
  expect(
    await nativeMigrationReceipts(accountUuid, status.activeRunId!),
    isEmpty,
  );
  pauseFlutterForNativeBackgroundMigration(tester);
  await waitForNativeMigrationDrain(
    () =>
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .advancingAccounts
            .isEmpty &&
        container.read(syncProvider).value?.isSyncing != true,
    description: 'foreground receipt reconciliation to drain',
    timeout: const Duration(minutes: 2),
  );
  return mobileRegtestMigrationStatus(accountUuid);
});

Future<rust_sync.MigrationStatus> runNativeDueOutboxTicksUntilSubmitted({
  required WidgetTester tester,
  required ProviderContainer container,
  required String accountUuid,
  required rust_sync.MigrationStatus initialStatus,
  required int submittedTarget,
}) async {
  var previous = initialStatus;
  final maxTicks = initialStatus.totalCount * 4 + 4;
  for (var tick = 0; tick < maxTicks; tick++) {
    var submitted = previous.broadcastedTxCount + previous.confirmedTxCount;
    if (submitted >= submittedTarget) return previous;
    if (previous.scheduledBroadcasts
        .where((part) => part.status == 'scheduled')
        .isEmpty) {
      previous = await prepareForegroundProofsForNativeOutboxTicks(
        tester,
        container,
        accountUuid,
      );
      submitted = previous.broadcastedTxCount + previous.confirmedTxCount;
    }
    final scheduled =
        previous.scheduledBroadcasts
            .where((part) => part.status == 'scheduled')
            .toList()
          ..sort((a, b) => a.scheduledHeight.compareTo(b.scheduledHeight));
    expect(scheduled, isNotEmpty);
    final tip = (await getDriver('/status'))['zcashdHeight'] as num;
    if (scheduled.first.scheduledHeight > tip.toInt()) {
      await postDriver('/mine', {
        'blocks': scheduled.first.scheduledHeight - tip.toInt(),
      });
    }
    expect(
      await nativeMigrationReceipts(accountUuid, previous.activeRunId!),
      isEmpty,
    );
    final result = await runNativeMigrationOutboxTick();
    expect(result['outcome'], 'accepted');
    final receipts = await nativeMigrationReceipts(
      accountUuid,
      previous.activeRunId!,
    );
    expect(
      receipts,
      hasLength(1),
      reason: 'one native tick sends at most one prepared child',
    );
    await expectAcceptedNativeMigrationReceipt(
      receipts.single,
      previous.scheduledBroadcasts.map((part) => part.txidHex).toSet(),
    );
    final paused = await mobileRegtestMigrationStatus(accountUuid);
    expectNativeOutboxTickDidNotCreateProofs(previous, paused);
    expect(
      paused.broadcastedTxCount + paused.confirmedTxCount,
      submitted,
      reason: 'native transport receipts are not foreground DB reconciliation',
    );
    final reconciled = await reconcileNativeMigrationReceipts(
      tester,
      container,
      accountUuid,
    );
    expectNativeOutboxTickDidNotCreateProofs(previous, reconciled);
    expect(
      reconciled.broadcastedTxCount + reconciled.confirmedTxCount,
      submitted + 1,
    );
    previous = reconciled;
  }
  fail('Native outbox ticks did not submit $submittedTarget children.');
}
