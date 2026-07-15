import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import '../../fakes/fake_sync_notifier.dart';

const _accountUuid = '550e8400-e29b-41d4-a716-446655440000';
const _dbPath = '/tmp/ironwood-announcement-test-wallet.db';
const _endpoint = RpcEndpointConfig(
  networkName: 'main',
  lightwalletdUrl: 'https://zec.example:443',
  presetId: kCustomRpcEndpointPresetId,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('resolves hidden while chain upgrade status is still loading', () async {
    final chainStatus = Completer<rust_wallet.ChainUpgradeStatus>();
    final container = _container(
      getChainUpgradeStatus: ({required lightwalletdUrl, required network}) =>
          chainStatus.future,
    );
    addTearDown(container.dispose);

    final state = await container.read(
      ironwoodMigrationAnnouncementProvider.future,
    );

    expect(state.visible, isFalse);

    chainStatus.complete(
      _chainStatus(
        network: 'main',
        tipHeight: 3_400_000,
        ironwoodActiveAtTip: false,
      ),
    );
  });

  test('stays hidden before Ironwood is active', () async {
    final migrationStatusCalls = <String>[];
    final container = _container(
      ironwoodActiveAtTip: false,
      migrationStatusCalls: migrationStatusCalls,
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final state = await container.read(
      ironwoodMigrationAnnouncementProvider.future,
    );

    expect(state.visible, isFalse);
    expect(migrationStatusCalls, isEmpty);
  });

  test('shows when Ironwood is active and migration status is ready', () async {
    final migrationStatusCalls = <String>[];
    final container = _container(
      ironwoodActiveAtTip: true,
      migrationStatusCalls: migrationStatusCalls,
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final state = await container.read(
      ironwoodMigrationAnnouncementProvider.future,
    );

    expect(state.visible, isTrue);
    expect(state.network, 'main');
    expect(state.accountUuid, _accountUuid);
    expect(state.status?.phase, kIronwoodMigrationReadyPhase);
    expect(migrationStatusCalls, ['$_dbPath|main|$_accountUuid']);
  });

  test('stays hidden when the migration state is not ready', () async {
    final container = _container(
      ironwoodActiveAtTip: true,
      migrationPhase: 'complete',
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final state = await container.read(
      ironwoodMigrationAnnouncementProvider.future,
    );

    expect(state.visible, isFalse);
  });

  test('seen account and network suppress the ready modal', () async {
    final migrationStatusCalls = <String>[];
    final announcementStore = _FakeAnnouncementStore(
      seenKeys: {_seenKey('main', _accountUuid)},
    );
    final container = _container(
      ironwoodActiveAtTip: true,
      announcementStore: announcementStore,
      migrationStatusCalls: migrationStatusCalls,
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final state = await container.read(
      ironwoodMigrationAnnouncementProvider.future,
    );

    expect(state.visible, isFalse);
    expect(migrationStatusCalls, isEmpty);
  });

  test(
    'home CTA shows start even after the announcement has been seen',
    () async {
      final announcementStore = _FakeAnnouncementStore(
        seenKeys: {_seenKey('main', _accountUuid)},
      );
      final container = _container(
        ironwoodActiveAtTip: true,
        announcementStore: announcementStore,
      );
      addTearDown(container.dispose);

      await _settleCoreProviders(container);
      final state = await container.read(
        ironwoodHomeMigrationCtaProvider.future,
      );

      expect(state.mode, IronwoodHomeMigrationCtaMode.start);
      expect(state.visible, isTrue);
      expect(state.buttonLabel, 'Migrate to Ironwood Pool');
    },
  );

  test('home CTA shows continue for an active migration run', () async {
    final container = _container(
      ironwoodActiveAtTip: true,
      migrationPhase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      migrationActiveRunId: 'run-1',
      syncState: SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        isSyncComplete: true,
        scannedHeight: 3_500_000,
        chainTipHeight: 3_500_000,
      ),
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final state = await container.read(ironwoodHomeMigrationCtaProvider.future);

    expect(state.mode, IronwoodHomeMigrationCtaMode.resume);
    expect(state.visible, isTrue);
    expect(state.buttonLabel, 'Continue migration');
  });

  test(
    'post migration state waits for externally migrated pending Ironwood',
    () async {
      final container = _container(
        ironwoodActiveAtTip: true,
        migrationPhase: kIronwoodMigrationWaitingForIronwoodSpendabilityPhase,
        syncState: SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          isSyncComplete: true,
          scannedHeight: 3_500_000,
          chainTipHeight: 3_500_000,
          ironwoodPendingBalance: BigInt.from(1_000_000),
          totalBalance: BigInt.from(1_000_000),
        ),
      );
      addTearDown(container.dispose);

      await _settleCoreProviders(container);
      final state = await container.read(
        ironwoodPostMigrationStateProvider.future,
      );
      final homeCta = await container.read(
        ironwoodHomeMigrationCtaProvider.future,
      );
      final routeCta = await container.read(
        ironwoodMigrationRouteCtaProvider.future,
      );

      expect(state.mode, IronwoodPostMigrationMode.pendingIronwoodSpendability);
      expect(state.locksNavigation, isFalse);
      expect(homeCta.mode, IronwoodHomeMigrationCtaMode.hidden);
      expect(routeCta.mode, IronwoodHomeMigrationCtaMode.hidden);
    },
  );

  test(
    'post migration state treats external Ironwood spendable as complete',
    () async {
      final container = _container(
        ironwoodActiveAtTip: true,
        migrationPhase: kIronwoodMigrationCompletePhase,
        syncState: SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          isSyncComplete: true,
          scannedHeight: 3_500_000,
          chainTipHeight: 3_500_000,
          ironwoodBalance: BigInt.from(1_000_000),
          spendableBalance: BigInt.from(1_000_000),
          totalBalance: BigInt.from(1_000_000),
        ),
      );
      addTearDown(container.dispose);

      await _settleCoreProviders(container);
      final state = await container.read(
        ironwoodPostMigrationStateProvider.future,
      );
      final homeCta = await container.read(
        ironwoodHomeMigrationCtaProvider.future,
      );
      final routeCta = await container.read(
        ironwoodMigrationRouteCtaProvider.future,
      );

      expect(state.mode, IronwoodPostMigrationMode.complete);
      expect(state.locksNavigation, isFalse);
      expect(homeCta.mode, IronwoodHomeMigrationCtaMode.hidden);
      expect(routeCta.mode, IronwoodHomeMigrationCtaMode.resume);
    },
  );

  test(
    'post migration state falls back to Ironwood balance when status fails',
    () async {
      final container = _container(
        ironwoodActiveAtTip: true,
        migrationStatusError: Exception('status unavailable'),
        syncState: SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          isSyncComplete: true,
          scannedHeight: 3_500_000,
          chainTipHeight: 3_500_000,
          ironwoodBalance: BigInt.from(1_000_000),
          spendableBalance: BigInt.from(1_000_000),
          totalBalance: BigInt.from(1_000_000),
        ),
      );
      addTearDown(container.dispose);

      await _settleCoreProviders(container);
      final state = await container.read(
        ironwoodPostMigrationStateProvider.future,
      );
      final homeCta = await container.read(
        ironwoodHomeMigrationCtaProvider.future,
      );

      expect(state.mode, IronwoodPostMigrationMode.complete);
      expect(state.locksNavigation, isFalse);
      expect(homeCta.mode, IronwoodHomeMigrationCtaMode.hidden);
    },
  );

  test(
    'post migration state keeps migratable Orchard required after Ironwood exists',
    () async {
      final container = _container(
        ironwoodActiveAtTip: true,
        migrationPhase: kIronwoodMigrationReadyPhase,
        syncState: SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          isSyncComplete: true,
          scannedHeight: 3_500_000,
          chainTipHeight: 3_500_000,
          orchardBalance: BigInt.from(1_000_000),
          ironwoodBalance: BigInt.from(1_000_000),
          spendableBalance: BigInt.from(2_000_000),
          totalBalance: BigInt.from(2_000_000),
        ),
      );
      addTearDown(container.dispose);

      await _settleCoreProviders(container);
      final state = await container.read(
        ironwoodPostMigrationStateProvider.future,
      );
      final homeCta = await container.read(
        ironwoodHomeMigrationCtaProvider.future,
      );

      expect(state.mode, IronwoodPostMigrationMode.required);
      expect(state.locksNavigation, isTrue);
      expect(homeCta.mode, IronwoodHomeMigrationCtaMode.start);
    },
  );

  test('route CTA resumes active run before requiring sync data', () async {
    final migrationStatusCalls = <String>[];
    final container = _container(
      ironwoodActiveAtTip: true,
      migrationPhase: kIronwoodMigrationWaitingDenomConfirmationsPhase,
      migrationActiveRunId: 'run-1',
      migrationStatusCalls: migrationStatusCalls,
      syncState: SyncState(
        accountUuid: _accountUuid,
        error: 'sync failed before account data refreshed',
      ),
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final state = await container.read(
      ironwoodMigrationRouteCtaProvider.future,
    );

    expect(state.mode, IronwoodHomeMigrationCtaMode.resume);
    expect(state.status?.activeRunId, 'run-1');
    expect(migrationStatusCalls, ['$_dbPath|main|$_accountUuid']);
  });

  test('home CTA stays hidden before Ironwood is active', () async {
    final migrationStatusCalls = <String>[];
    final container = _container(
      ironwoodActiveAtTip: false,
      migrationStatusCalls: migrationStatusCalls,
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final state = await container.read(ironwoodHomeMigrationCtaProvider.future);

    expect(state.visible, isFalse);
    expect(migrationStatusCalls, isEmpty);
  });

  test('home CTA ignores sync progress-only updates', () async {
    final migrationStatusCalls = <String>[];
    final syncState = _syncingReadyState();
    final container = _container(
      ironwoodActiveAtTip: true,
      syncState: syncState,
      migrationStatusCalls: migrationStatusCalls,
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final initial = await container.read(
      ironwoodHomeMigrationCtaProvider.future,
    );
    expect(initial.mode, IronwoodHomeMigrationCtaMode.start);
    expect(migrationStatusCalls, ['$_dbPath|main|$_accountUuid']);

    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      syncState.copyWith(
        percentage: 0.35,
        displayPercentage: 0.35,
        displayTargetPercentage: 0.36,
        displayTargetBlocks: 25,
        scannedHeight: 3_499_800,
        chainTipHeight: 3_500_000,
        phase: 'scan',
      ),
    );
    await container.pump();

    final afterProgressTick = await container.read(
      ironwoodHomeMigrationCtaProvider.future,
    );
    expect(afterProgressTick.mode, IronwoodHomeMigrationCtaMode.start);
    expect(migrationStatusCalls, ['$_dbPath|main|$_accountUuid']);
  });

  test('migration flow data ignores sync progress-only updates', () async {
    final migrationStatusCalls = <String>[];
    final syncState = _syncingReadyState();
    final container = _container(
      ironwoodActiveAtTip: true,
      syncState: syncState,
      migrationStatusCalls: migrationStatusCalls,
    );
    addTearDown(container.dispose);

    await _settleCoreProviders(container);
    final flowEvents = <AsyncValue<IronwoodMigrationFlowData?>>[];
    final subscription = container
        .listen<AsyncValue<IronwoodMigrationFlowData?>>(
          ironwoodMigrationFlowDataProvider,
          (_, next) => flowEvents.add(next),
          fireImmediately: true,
        );
    addTearDown(subscription.close);

    final initial = await container.read(
      ironwoodMigrationFlowDataProvider.future,
    );
    expect(initial?.amountZatoshi, syncState.orchardBalance);
    expect(migrationStatusCalls, ['$_dbPath|main|$_accountUuid']);
    flowEvents.clear();

    final syncNotifier =
        container.read(syncProvider.notifier) as FakeSyncNotifier;
    syncNotifier.emit(
      syncState.copyWith(
        percentage: 0.35,
        displayPercentage: 0.35,
        displayTargetPercentage: 0.36,
        displayTargetBlocks: 25,
        scannedHeight: 3_499_800,
        chainTipHeight: 3_500_000,
        phase: 'scan',
      ),
    );
    await container.pump();

    final afterProgressTick = await container.read(
      ironwoodMigrationFlowDataProvider.future,
    );
    expect(afterProgressTick?.amountZatoshi, syncState.orchardBalance);
    expect(flowEvents, isEmpty);
    expect(migrationStatusCalls, ['$_dbPath|main|$_accountUuid']);
  });
}

ProviderContainer _container({
  bool ironwoodActiveAtTip = true,
  String migrationPhase = kIronwoodMigrationReadyPhase,
  String? migrationActiveRunId,
  ChainUpgradeStatusGetter? getChainUpgradeStatus,
  _FakeAnnouncementStore? announcementStore,
  List<String>? migrationStatusCalls,
  SyncState? syncState,
  Object? migrationStatusError,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      chainUpgradeStatusGetterProvider.overrideWithValue(
        getChainUpgradeStatus ??
            ({required lightwalletdUrl, required network}) async =>
                _chainStatus(
                  network: network,
                  tipHeight: ironwoodActiveAtTip ? 3_500_000 : 3_400_000,
                  ironwoodActiveAtTip: ironwoodActiveAtTip,
                ),
      ),
      chainUpgradeStatusAtHeightGetterProvider.overrideWithValue(
        ({required network, required tipHeight}) async =>
            rust_wallet.ChainUpgradeActivationStatus(
              network: network,
              tipHeight: tipHeight,
              nu63ActivationHeight: BigInt.from(3_428_143),
              ironwoodActiveAtTip: ironwoodActiveAtTip,
            ),
      ),
      ironwoodActivationStoreProvider.overrideWithValue(
        _FakeIronwoodActivationStore(),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(syncState ?? _readySyncState()),
      ),
      ironwoodMigrationAnnouncementStoreProvider.overrideWithValue(
        announcementStore ?? _FakeAnnouncementStore(),
      ),
      walletDbPathGetterProvider.overrideWithValue(() async => _dbPath),
      orchardMigrationStatusGetterProvider.overrideWithValue(({
        required dbPath,
        required network,
        required accountUuid,
      }) async {
        migrationStatusCalls?.add('$dbPath|$network|$accountUuid');
        final error = migrationStatusError;
        if (error != null) {
          throw error;
        }
        return _migrationStatus(
          migrationPhase,
          activeRunId: migrationActiveRunId,
        );
      }),
    ],
  );
}

Future<void> _settleCoreProviders(ProviderContainer container) async {
  await container.read(chainUpgradeStatusProvider.future);
  await container.read(accountProvider.future);
  await container.read(syncProvider.future);
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(
          uuid: _accountUuid,
          name: 'Account 1',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: _accountUuid,
      activeAddress: 'u1testaddress',
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

SyncState _readySyncState() {
  return SyncState(
    accountUuid: _accountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    scannedHeight: 3_500_000,
    chainTipHeight: 3_500_000,
    orchardBalance: BigInt.from(1_000_000),
    spendableBalance: BigInt.from(1_000_000),
    totalBalance: BigInt.from(1_000_000),
  );
}

SyncState _syncingReadyState() {
  return SyncState(
    accountUuid: _accountUuid,
    hasAccountScopedData: true,
    isSyncing: true,
    percentage: 0.34,
    displayPercentage: 0.34,
    displayTargetPercentage: 0.34,
    scannedHeight: 3_499_700,
    chainTipHeight: 3_500_000,
    orchardBalance: BigInt.from(1_000_000),
    spendableBalance: BigInt.from(1_000_000),
    totalBalance: BigInt.from(1_000_000),
    phase: 'scan',
  );
}

rust_wallet.ChainUpgradeStatus _chainStatus({
  required String network,
  required int tipHeight,
  required bool ironwoodActiveAtTip,
}) {
  return rust_wallet.ChainUpgradeStatus(
    network: network,
    lightwalletdChainName: network,
    tipHeight: BigInt.from(tipHeight),
    lightwalletdReportedHeight: BigInt.from(tipHeight),
    lightwalletdEstimatedHeight: BigInt.from(tipHeight),
    lightwalletdConsensusBranchId: ironwoodActiveAtTip
        ? '37a5165b'
        : 'c8e71055',
    lightwalletdUpgradeName: '',
    lightwalletdUpgradeHeight: BigInt.zero,
    nu63ActivationHeight: BigInt.from(3_428_143),
    ironwoodActiveAtTip: ironwoodActiveAtTip,
    endpointMatchesNetwork: true,
  );
}

rust_sync.MigrationStatus _migrationStatus(
  String phase, {
  String? activeRunId,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 0,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 0,
    broadcastWindowSeconds: BigInt.zero,
    maxPreparedNotesPerRun: 0,
    scheduledBroadcasts: const [],
  );
}

class _FakeIronwoodActivationStore implements IronwoodActivationStore {
  final _activeNetworks = <String>{};

  @override
  Future<bool> isActiveSeen(String network) async {
    return _activeNetworks.contains(network);
  }

  @override
  Future<void> markActiveSeen(String network) async {
    _activeNetworks.add(network);
  }
}

class _FakeAnnouncementStore implements IronwoodMigrationAnnouncementStore {
  _FakeAnnouncementStore({Set<String>? seenKeys})
    : _seenKeys = seenKeys ?? <String>{};

  final Set<String> _seenKeys;

  @override
  Future<bool> isSeen({
    required String network,
    required String accountUuid,
  }) async {
    return _seenKeys.contains(_seenKey(network, accountUuid));
  }

  @override
  Future<void> markSeen({
    required String network,
    required String accountUuid,
  }) async {
    _seenKeys.add(_seenKey(network, accountUuid));
  }
}

String _seenKey(String network, String accountUuid) => '$network|$accountUuid';
