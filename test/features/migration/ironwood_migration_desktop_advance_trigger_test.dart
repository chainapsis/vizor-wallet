// Desktop lane (untagged): `kAppFormFactor` resolves to desktop here, which is
// what selects the desktop branches of `_shouldAdvance` / `_advance`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _uuid = 'software-account';
const _endpoint = RpcEndpointConfig(
  networkName: 'test',
  lightwalletdUrl: 'https://example.test:443',
);

/// Height the transfer is scheduled for, and the tip before/after it is due.
const _scheduledHeight = 1100;
const _beforeDueHeight = 1099;
const _secondScheduledHeight = 1150;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('desktop: crossing a scheduled height advances immediately', () async {
    final broadcasts = <String>[];
    final harness = _Harness(broadcasts: broadcasts);
    addTearDown(harness.dispose);

    // Poll 1, tip below the scheduled height: the first advance always runs
    // because there is no previous advance to rate-limit against.
    await harness.pump(tipHeight: _beforeDueHeight);
    expect(
      broadcasts.length,
      1,
      reason: 'first poll should advance (no prior advance to gate on)',
    );

    // Poll 2, tip has now crossed the scheduled height. Nothing else about the
    // status changed, so before this fix the transfer waited out the 30s
    // `_migrationAdvanceInterval` (measured: 15s mean, 30s worst case).
    await harness.pump(tipHeight: _scheduledHeight);

    expect(
      broadcasts.length,
      2,
      reason: 'becoming due must trigger the broadcast attempt immediately',
    );
  });

  test('desktop: a due transfer does not re-advance every poll', () async {
    final broadcasts = <String>[];
    final harness = _Harness(broadcasts: broadcasts);
    addTearDown(harness.dispose);

    await harness.pump(tipHeight: _beforeDueHeight);
    await harness.pump(tipHeight: _scheduledHeight);
    expect(broadcasts.length, 2);

    // The transfer is still due and still un-broadcast (the fake keeps the run
    // in `broadcast_scheduled`). The due count is unchanged, so the key is
    // unchanged and retries fall back to the ordinary interval rather than
    // firing on every poll.
    await harness.pump(tipHeight: _scheduledHeight);
    await harness.pump(tipHeight: _scheduledHeight + 1);

    expect(
      broadcasts.length,
      2,
      reason: 'a still-due transfer must not hot-loop the advance path',
    );
  });

  test('desktop: a second transfer coming due advances again', () async {
    final broadcasts = <String>[];
    final harness = _Harness(broadcasts: broadcasts);
    addTearDown(harness.dispose);

    harness.setStatus(_statusWithTwoTransfers());
    await harness.pump(tipHeight: _beforeDueHeight);
    expect(broadcasts.length, 1);

    // First transfer becomes due.
    await harness.pump(tipHeight: _scheduledHeight);
    expect(broadcasts.length, 2);

    // Second transfer becomes due: the due count goes 1 -> 2, so this is a
    // fresh key and fires immediately rather than waiting out the interval.
    await harness.pump(tipHeight: _secondScheduledHeight);
    expect(
      broadcasts.length,
      3,
      reason: 'each transfer coming due is its own trigger',
    );
  });

  test(
    'desktop: an unrelated status change still re-triggers advance',
    () async {
      final broadcasts = <String>[];
      final harness = _Harness(broadcasts: broadcasts);
      addTearDown(harness.dispose);

      await harness.pump(tipHeight: _beforeDueHeight);
      expect(broadcasts.length, 1);

      // Control: the pre-existing progress-key mechanism is unchanged.
      harness.setStatus(_status(broadcastedTxCount: 1));
      await harness.pump(tipHeight: _beforeDueHeight);

      expect(broadcasts.length, 2);
    },
  );
}

rust_sync.MigrationStatus _status({
  int broadcastedTxCount = 0,
  int scheduledHeight = _scheduledHeight,
}) {
  return rust_sync.MigrationStatus(
    phase: 'broadcast_scheduled',
    activeRunId: 'run-1',
    targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 1,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: 0,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: true,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: [
      rust_sync.MigrationScheduledBroadcast(
        txidHex: 'scheduled-tx',
        valueZatoshi: BigInt.from(100000000),
        scheduledAtMs: 0,
        scheduledHeight: scheduledHeight,
        status: 'scheduled',
      ),
    ],
    parts: const [],
  );
}

rust_sync.MigrationStatus _statusWithTwoTransfers() {
  final base = _status();
  return rust_sync.MigrationStatus(
    phase: base.phase,
    activeRunId: base.activeRunId,
    targetValuesZatoshi: base.targetValuesZatoshi,
    preparedNoteCount: base.preparedNoteCount,
    denominationConfirmationCount: base.denominationConfirmationCount,
    denominationConfirmationTarget: base.denominationConfirmationTarget,
    denominationSplitCompletedCount: base.denominationSplitCompletedCount,
    denominationSplitTotalCount: base.denominationSplitTotalCount,
    pendingTxCount: 2,
    broadcastedTxCount: base.broadcastedTxCount,
    confirmedTxCount: base.confirmedTxCount,
    totalCount: 2,
    signedChildPcztCount: base.signedChildPcztCount,
    pendingSplitStageCount: base.pendingSplitStageCount,
    canAbandon: base.canAbandon,
    signingBatchLimit: base.signingBatchLimit,
    scheduleMeanDelayBlocks: base.scheduleMeanDelayBlocks,
    scheduleMaxDelayBlocks: base.scheduleMaxDelayBlocks,
    scheduledBroadcasts: [
      ...base.scheduledBroadcasts,
      rust_sync.MigrationScheduledBroadcast(
        txidHex: 'scheduled-tx-2',
        valueZatoshi: BigInt.from(100000000),
        scheduledAtMs: 0,
        scheduledHeight: _secondScheduledHeight,
        status: 'scheduled',
      ),
    ],
    parts: const [],
  );
}

/// Drives the real coordinator through repeated `refreshNow()` passes with a
/// controllable chain tip, counting how many times a broadcast is attempted.
class _Harness {
  _Harness({required this.broadcasts}) {
    _current = _status();
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _current,
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => _endpoint,
      getSessionPassword: () => 'test-password',
      isMacOS: () => true,
      isMobile: () => false,
      isIOS: () => false,
      supportsBackgroundMigration: () => false,
      isHardwareAccount: (uuid) => false,
      scheduleBackgroundMigration: () async => false,
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required managedSubmissionRouting,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async {
            broadcasts.add(accountUuid);
            // Hold the run in `broadcast_scheduled` so the status -- and
            // therefore the progress key -- is identical across polls. Only
            // the chain tip moves.
            return rust_sync.IronwoodMigrationResult(
              txids: '',
              status: 'broadcast_scheduled',
              broadcastedCount: 0,
              totalCount: 1,
              feeZatoshi: BigInt.zero,
              migratedZatoshi: BigInt.from(100000000),
            );
          },
    );

    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        syncProvider.overrideWith(() => _sync),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_) async => BigInt.from(_tipHeight),
        ),
        ironwoodMigrationServiceProvider.overrideWithValue(service),
      ],
    );
    _subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
  }

  final List<String> broadcasts;
  late final ProviderContainer container;
  late final ProviderSubscription<IronwoodMigrationCoordinatorState>
  _subscription;
  final FakeSyncNotifier _sync = FakeSyncNotifier(SyncState());
  late rust_sync.MigrationStatus _current;
  int _tipHeight = _beforeDueHeight;

  void setStatus(rust_sync.MigrationStatus status) => _current = status;

  /// One coordinator poll at the given chain tip.
  Future<void> pump({required int tipHeight}) async {
    _tipHeight = tipHeight;
    // `FakeSyncNotifier.build` is async; the notifier cannot take a new state
    // until the provider has been read at least once and built.
    await container.read(syncProvider.future);
    _sync.emit(SyncState(scannedHeight: tipHeight, chainTipHeight: tipHeight));
    await container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow();
  }

  void dispose() {
    _subscription.close();
    container.dispose();
  }
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(
          uuid: _uuid,
          name: 'Software',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: _uuid,
      activeAddress: 'u1test',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: _endpoint.networkName,
    rpcEndpointConfig: _endpoint,
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}
