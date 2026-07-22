@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _softwareUuid = 'software-account';
const _hardwareUuid = 'hardware-account';
const _endpoint = RpcEndpointConfig(
  networkName: 'test',
  lightwalletdUrl: 'https://example.test:443',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('advances software signing without a migration screen', () async {
    final statuses = {
      _softwareUuid: _status('ready_to_migrate'),
      _hardwareUuid: _status('ready_to_migrate'),
    };
    final softwareStarts = <String>[];
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: softwareStarts,
      broadcasts: broadcasts,
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow(forceAdvance: true);

    expect(softwareStarts, [_softwareUuid]);
    expect(broadcasts, [_softwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .statuses[_hardwareUuid]
          ?.phase,
      'ready_to_migrate',
    );
  });

  test('does not broadcast a scheduled migration before it is due', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final softwareStarts = <String>[];
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: softwareStarts,
      broadcasts: broadcasts,
      syncState: SyncState(scannedHeight: 999, chainTipHeight: 1_001),
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    await container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow(forceAdvance: true);

    expect(broadcasts, isEmpty);
    expect(softwareStarts, isEmpty);
  });

  test(
    'automatically broadcasts a due scheduled migration in foreground',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final broadcasts = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: broadcasts,
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      await container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();

      expect(broadcasts, [_softwareUuid]);
    },
  );

  test(
    'automatically broadcasts a due Keystone migration in foreground',
    () async {
      final statuses = {
        _softwareUuid: _status('complete', activeRunId: null),
        _hardwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      };
      final broadcasts = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: broadcasts,
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      await container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();

      expect(broadcasts, [_hardwareUuid]);
    },
  );

  test(
    'coalesces a refresh requested while status loading is active',
    () async {
      final statuses = {
        _softwareUuid: _status('complete', activeRunId: null),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final firstStatusStarted = Completer<void>();
      final releaseFirstStatus = Completer<void>();
      var statusCallCount = 0;
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        loadStatus: (accountUuid) async {
          statusCallCount += 1;
          if (statusCallCount == 1) {
            firstStatusStarted.complete();
            await releaseFirstStatus.future;
          }
          return statuses[accountUuid]!;
        },
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final firstRefresh = container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();
      await firstStatusStarted.future;
      await container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow(forceAdvance: true);
      releaseFirstStatus.complete();
      await firstRefresh;

      for (var attempt = 0; attempt < 20 && statusCallCount < 4; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(statusCallCount, 4);
    },
  );

  test('refreshes confirmation progress without broadcasting', () async {
    final statuses = {
      _softwareUuid: _status('waiting_migration_confirmations'),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: broadcasts,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    await coordinator.refreshNow(forceAdvance: true);
    statuses[_softwareUuid] = _status(
      'waiting_migration_confirmations',
      confirmedTxCount: 1,
    );
    await coordinator.refreshNow();

    expect(broadcasts, isEmpty);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .statuses[_softwareUuid]
          ?.confirmedTxCount,
      1,
    );
  });

  test('ignores a status result that completes after disposal', () async {
    final statuses = {
      _softwareUuid: _status('complete', activeRunId: null),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final statusStarted = Completer<void>();
    final releaseStatus = Completer<void>();
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      loadStatus: (accountUuid) async {
        if (!statusStarted.isCompleted) statusStarted.complete();
        await releaseStatus.future;
        return statuses[accountUuid]!;
      },
    );
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final refresh = container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow();
    await statusStarted.future;

    subscription.close();
    container.dispose();
    releaseStatus.complete();

    await expectLater(refresh, completes);
  });
}

ProviderContainer _container({
  required Map<String, rust_sync.MigrationStatus> statuses,
  required List<String> softwareStarts,
  required List<String> broadcasts,
  Future<rust_sync.MigrationStatus> Function(String accountUuid)? loadStatus,
  SyncState? syncState,
}) {
  final service = IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async {
          return loadStatus?.call(accountUuid) ?? statuses[accountUuid]!;
        },
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            null,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => _endpoint,
    getSessionPassword: () => 'test-password',
    isMacOS: () => true,
    isMobile: () => true,
    isHardwareAccount: (uuid) => uuid == _hardwareUuid,
    scheduleBackgroundMigration: () async => true,
    broadcastDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) async {
          broadcasts.add(accountUuid);
          final current = statuses[accountUuid]!;
          if (current.phase == 'broadcast_scheduled') {
            statuses[accountUuid] = _status('waiting_migration_confirmations');
            return _result('waiting_migration_confirmations');
          }
          return _result(current.phase);
        },
    startMacosSoftwareMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
          required approvedSchedule,
        }) async {
          softwareStarts.add(accountUuid);
          statuses[accountUuid] = _status('broadcast_scheduled');
          return _result('broadcast_scheduled');
        },
  );

  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      if (syncState != null)
        syncProvider.overrideWith(() => FakeSyncNotifier(syncState)),
      ironwoodMigrationServiceProvider.overrideWithValue(service),
    ],
  );
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(
          uuid: _softwareUuid,
          name: 'Software',
          order: 0,
          isSeedAnchor: true,
        ),
        AccountInfo(
          uuid: _hardwareUuid,
          name: 'Keystone',
          order: 1,
          isHardware: true,
        ),
      ],
      activeAccountUuid: _softwareUuid,
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

rust_sync.MigrationStatus _status(
  String phase, {
  String? activeRunId = 'run-1',
  int confirmedTxCount = 0,
  int? scheduledHeight,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 1,
    broadcastedTxCount: 0,
    confirmedTxCount: confirmedTxCount,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 50,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: scheduledHeight == null
        ? const []
        : [
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

rust_sync.IronwoodMigrationResult _result(String status) {
  return rust_sync.IronwoodMigrationResult(
    txids: '',
    status: status,
    broadcastedCount: 0,
    totalCount: 1,
    feeZatoshi: BigInt.zero,
    migratedZatoshi: BigInt.from(100000000),
  );
}
