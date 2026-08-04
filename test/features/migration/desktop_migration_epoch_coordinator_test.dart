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
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _accountUuid = 'software-account';
const _endpoint = RpcEndpointConfig(
  networkName: 'test',
  lightwalletdUrl: 'https://example.test:443',
);

/// Simulated desktop process clocks plus the observable epoch side effect.
///
/// `sleep` advances only the wall clock (the monotonic clock pauses across a
/// machine sleep); `run` advances both in step (awake time passing, including
/// a long-locked stretch or a slow sweep). `authoritativeHeightReads` counts
/// epoch entry-height fetches: exactly one per wallet-open epoch, so a second
/// read is the proof that the epoch restarted.
class _EpochHarness {
  _EpochHarness();

  DateTime wallNow = DateTime.utc(2026, 8, 4, 12);
  Duration monotonicNow = Duration.zero;
  int authoritativeHeightReads = 0;
  final walletOpenTipHeights = <int?>[];
  void Function()? onStatusSweep;
  late final IronwoodMigrationCoordinator coordinator;

  void sleep(Duration duration) {
    wallNow = wallNow.add(duration);
  }

  void run(Duration duration) {
    wallNow = wallNow.add(duration);
    monotonicNow += duration;
  }
}

Future<_EpochHarness> _startCoordinator({
  rust_sync.MigrationStatus? accountStatus,
}) async {
  final harness = _EpochHarness();
  final status = accountStatus ?? _completeStatus();
  final service = IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            status,
    getStatuses:
        ({required dbPath, required network, required accountUuids}) async {
          harness.onStatusSweep?.call();
          return [
            for (final accountUuid in accountUuids)
              rust_sync.MigrationStatusEntry(
                accountUuid: accountUuid,
                status: status,
              ),
          ];
        },
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            null,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => _endpoint,
    getSessionPassword: () => 'test-password',
    isMacOS: () => true,
    isMobile: () => false,
    isIOS: () => false,
    supportsBackgroundMigration: () => false,
    isHardwareAccount: (_) => false,
    broadcastDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
          int? walletOpenTipHeight,
        }) async {
          harness.walletOpenTipHeights.add(walletOpenTipHeight);
          return _migrationResult();
        },
  );
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      ironwoodMigrationServiceProvider.overrideWithValue(service),
      rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue((
        _,
      ) async {
        // Each epoch's entry read observes a fresh tip (1_000, 1_001, ...) so
        // tests can prove which epoch's height flowed into a broadcast.
        harness.authoritativeHeightReads++;
        return BigInt.from(999 + harness.authoritativeHeightReads);
      }),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => IronwoodMigrationCoordinator(
          now: () => harness.wallNow,
          monotonicNow: () => harness.monotonicNow,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(accountProvider.future);
  final subscription = container.listen(
    ironwoodMigrationCoordinatorProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  harness.coordinator = container.read(
    ironwoodMigrationCoordinatorProvider.notifier,
  );
  await harness.coordinator.refreshNow();
  expect(harness.authoritativeHeightReads, 1);
  return harness;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('desktop visibility changes preserve the epoch', () async {
    final harness = await _startCoordinator();

    harness.run(const Duration(minutes: 1));
    harness.coordinator.setForeground(false);
    await harness.coordinator.refreshNow();
    harness.run(const Duration(minutes: 1));
    harness.coordinator.setForeground(true);
    await harness.coordinator.refreshNow();

    expect(
      harness.authoritativeHeightReads,
      1,
      reason: 'hiding and re-showing the window must preserve the epoch',
    );
  });

  test('a machine sleep between sweeps restarts the epoch', () async {
    final harness = await _startCoordinator();

    harness.sleep(kDesktopMigrationEpochSuspensionGap);
    await harness.coordinator.refreshNow();

    expect(
      harness.authoritativeHeightReads,
      2,
      reason: 'a genuine sleep must recapture the epoch entry height',
    );
  });

  test('a machine sleep that begins mid-sweep restarts the epoch', () async {
    final harness = await _startCoordinator();

    harness.onStatusSweep = () {
      harness.sleep(kDesktopMigrationEpochSuspensionGap);
      harness.onStatusSweep = null;
    };
    await harness.coordinator.refreshNow();
    await harness.coordinator.refreshNow();

    expect(
      harness.authoritativeHeightReads,
      2,
      reason:
          'wall time outrunning the monotonic clock inside a sweep is a '
          'suspension and must recapture the epoch entry height',
    );
  });

  test('a long awake refresh gap (locked wallet) restarts the epoch', () async {
    final harness = await _startCoordinator();

    harness.run(kDesktopMigrationEpochSuspensionGap);
    await harness.coordinator.refreshNow();

    expect(
      harness.authoritativeHeightReads,
      2,
      reason:
          'refresh activity stopping for the threshold while the process '
          'stays awake means broadcasts could not run and must restart the '
          'epoch',
    );
  });

  test('threads each epoch\'s entry tip into the one-due broadcast', () async {
    // The Rust one-due endpoint floors its post-accept wallet-overdue redraw
    // at the epoch entry tip. Losing this argument would silently reintroduce
    // the sync-lag wedge, so pin the coordinator → service → broadcaster
    // threading end to end, across an epoch restart.
    final harness = await _startCoordinator(
      accountStatus: _scheduledStatus(scheduledHeight: 999),
    );

    expect(
      harness.walletOpenTipHeights,
      [1_000],
      reason: 'the broadcast must carry the first epoch\'s entry tip',
    );

    harness.sleep(kDesktopMigrationEpochSuspensionGap);
    await harness.coordinator.refreshNow(forceAdvance: true);

    expect(harness.authoritativeHeightReads, 2);
    expect(
      harness.walletOpenTipHeights,
      [1_000, 1_001],
      reason:
          'a restarted epoch must thread its freshly captured entry tip, '
          'not the pre-suspension one',
    );
  });

  test('a slow sweep does not restart the epoch', () async {
    final harness = await _startCoordinator();

    harness.onStatusSweep = () {
      harness.run(kDesktopMigrationEpochSuspensionGap * 2);
      harness.onStatusSweep = null;
    };
    await harness.coordinator.refreshNow();
    harness.run(const Duration(seconds: 15));
    await harness.coordinator.refreshNow();

    expect(
      harness.authoritativeHeightReads,
      1,
      reason:
          'a sweep running longer than the threshold is process activity, '
          'not suspension',
    );
  });
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(
          uuid: _accountUuid,
          name: 'Software',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: _accountUuid,
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

rust_sync.MigrationStatus _scheduledStatus({required int scheduledHeight}) {
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
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
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

rust_sync.IronwoodMigrationResult _migrationResult() {
  return rust_sync.IronwoodMigrationResult(
    txids: '',
    status: 'broadcast_scheduled',
    broadcastedCount: 0,
    totalCount: 1,
    feeZatoshi: BigInt.zero,
    migratedZatoshi: BigInt.from(100000000),
  );
}

rust_sync.MigrationStatus _completeStatus() {
  return rust_sync.MigrationStatus(
    phase: 'complete',
    targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 0,
    broadcastedTxCount: 1,
    confirmedTxCount: 1,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: const [],
    parts: const [],
  );
}
