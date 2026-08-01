// Desktop lane (untagged): `kAppFormFactor` resolves to desktop here.
//
// Measures how long `IronwoodMigrationCoordinator.stop` blocks its caller.
// The migration schedule screen awaits that future before it navigates
// (`schedule.dart` -> `await coordinator.stop(...)` then `context.go('/home')`),
// so every millisecond here is a millisecond of spinner after the user
// confirms the cancel.
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

const _uuid = 'software-account';
const _runId = 'run-1';
const _endpoint = RpcEndpointConfig(
  networkName: 'test',
  lightwalletdUrl: 'https://example.test:443',
);

/// Stand-ins for the post-commit work, sized from the figures in #420/#429 on
/// a 10-account mainnet wallet: a balance+history refresh and a wallet-snapshot
/// backed status sweep.
const _balanceRefreshCost = Duration(milliseconds: 150);
const _statusReadCost = Duration(milliseconds: 200);

/// The durable stop itself. Not deferrable - the user is waiting on this.
const _durableStopCost = Duration(milliseconds: 100);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('desktop: stop returns once the durable abandon commits', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.primeStatus();

    final stopwatch = Stopwatch()..start();
    await harness.coordinator.stop(accountUuid: _uuid, runId: _runId);
    stopwatch.stop();

    // The durable stop must be awaited. The post-commit refreshes must not be.
    expect(
      harness.stops,
      1,
      reason: 'the durable abandon still has to happen before we return',
    );
    expect(
      stopwatch.elapsed,
      lessThan(_balanceRefreshCost + _statusReadCost),
      reason:
          'stop() blocked for ${stopwatch.elapsedMilliseconds}ms; the '
          'post-commit balance refresh and status sweep should no longer be '
          'on the caller path',
    );
  });

  test('desktop: the post-commit refreshes still run', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.primeStatus();

    await harness.coordinator.stop(accountUuid: _uuid, runId: _runId);

    // Deferred, not dropped. Give the unawaited work time to land.
    await harness.settle();

    expect(
      harness.balanceRefreshes,
      greaterThanOrEqualTo(1),
      reason: 'balance must still refresh after a stop, just not inline',
    );
    expect(
      harness.statusReadsAfterStop,
      greaterThanOrEqualTo(1),
      reason: 'coordinator state must still be refreshed after a stop',
    );
  });

  test('desktop: a failing durable stop still surfaces as an error', () async {
    final harness = _Harness(stopFails: true);
    addTearDown(harness.dispose);
    await harness.primeStatus();

    await expectLater(
      harness.coordinator.stop(accountUuid: _uuid, runId: _runId),
      throwsA(isA<StateError>()),
    );

    expect(
      harness.container
          .read(ironwoodMigrationCoordinatorProvider)
          .errors[_uuid],
      isNotNull,
      reason: 'a real stop failure must still reach the screen',
    );
  });

  test('desktop: stop clears its stopping lease before returning', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.primeStatus();

    await harness.coordinator.stop(accountUuid: _uuid, runId: _runId);

    expect(
      harness.container
          .read(ironwoodMigrationCoordinatorProvider)
          .stoppingAccounts,
      isNot(contains(_uuid)),
      reason:
          'the screen navigates on this future; leaving the account marked '
          'stopping would strand its UI state',
    );
  });
}

class _Harness {
  _Harness({this.stopFails = false}) {
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async {
            await Future<void>.delayed(_statusReadCost);
            if (_stopped) statusReadsAfterStop++;
            return _stopped ? _status(activeRunId: null) : _status();
          },
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
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            await Future<void>.delayed(_durableStopCost);
            if (stopFails) throw StateError('durable stop failed');
            stops++;
            _stopped = true;
          },
    );

    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        syncProvider.overrideWith(() => _SlowSyncNotifier(this)),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_) async => BigInt.from(1000),
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

  final bool stopFails;
  late final ProviderContainer container;
  late final ProviderSubscription<IronwoodMigrationCoordinatorState>
  _subscription;

  int stops = 0;
  int balanceRefreshes = 0;
  int statusReadsAfterStop = 0;
  bool _stopped = false;

  IronwoodMigrationCoordinator get coordinator =>
      container.read(ironwoodMigrationCoordinatorProvider.notifier);

  /// Populate coordinator state so `stop` operates on a known active run.
  Future<void> primeStatus() async {
    await container.read(syncProvider.future);
    await coordinator.refreshNow();
  }

  /// Let unawaited post-commit work complete.
  Future<void> settle() async {
    await Future<void>.delayed(
      _balanceRefreshCost + _statusReadCost + const Duration(milliseconds: 200),
    );
  }

  void dispose() {
    _subscription.close();
    container.dispose();
  }
}

class _SlowSyncNotifier extends SyncNotifier {
  _SlowSyncNotifier(this._harness);

  final _Harness _harness;

  @override
  Future<SyncState> build() async =>
      SyncState(scannedHeight: 1000, chainTipHeight: 1000);

  @override
  Future<void> refreshAfterSend() async {
    await Future<void>.delayed(_balanceRefreshCost);
    _harness.balanceRefreshes++;
  }
}

rust_sync.MigrationStatus _status({String? activeRunId = _runId}) {
  return rust_sync.MigrationStatus(
    phase: activeRunId == null ? 'complete' : 'broadcast_scheduled',
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 1,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: true,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: const [],
    parts: const [],
  );
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(uuid: _uuid, name: 'Software', order: 0, isSeedAnchor: true),
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
