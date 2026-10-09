import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _accountUuid = 'account-1';

/// Rust as the sync loop sees it: one guard, held from `startFullSync` until
/// the test closes that sync's stream, follow-ups included.
class _Api extends RustLibApi {
  bool running = false;
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];

  @override
  bool crateApiSyncIsSyncRunning() => running;

  @override
  bool crateApiSyncIsSyncCancelRequested() => false;

  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  @override
  void crateApiSyncSetActiveSyncAccount({String? accountUuid}) {}

  @override
  void crateApiSyncSetSyncMode({required int mode}) {}

  @override
  void crateApiSyncCancelFullSync() {}

  @override
  void crateApiSyncStopMempoolObserver() {}

  @override
  Stream<rust_sync.ApiMempoolTxEvent> crateApiSyncStartMempoolObserver({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
  }) => const Stream.empty();

  @override
  Stream<rust_sync.ApiSyncProgressEvent> crateApiSyncStartFullSync({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required int mode,
  }) {
    if (running) throw StateError('an unowned concurrent sync was spawned');
    running = true;
    final controller = StreamController<rust_sync.ApiSyncProgressEvent>();
    syncs.add(controller);
    return controller.stream;
  }

  @override
  Future<rust_sync.WalletBalance> crateApiSyncGetBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => rust_sync.WalletBalance(
    availability: rust_sync.WalletBalanceAvailability.available,
    transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
    transparentPrivate: false,
    transparent: BigInt.zero,
    sapling: BigInt.zero,
    orchard: BigInt.one,
    ironwood: BigInt.zero,
    transparentLocked: BigInt.zero,
    saplingLocked: BigInt.zero,
    orchardLocked: BigInt.zero,
    ironwoodLocked: BigInt.zero,
    transparentPending: BigInt.zero,
    saplingPending: BigInt.zero,
    orchardPending: BigInt.zero,
    ironwoodPending: BigInt.zero,
    changePendingConfirmation: BigInt.zero,
    valuePendingSpendability: BigInt.zero,
    uneconomicValue: BigInt.zero,
    spendable: BigInt.one,
    locked: BigInt.zero,
    total: BigInt.one,
  );

  @override
  Future<List<rust_sync.TransactionInfo>> crateApiSyncGetTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => const [];

  /// Ends the sync that holds the guard: Rust releases it, then the stream
  /// closes.
  Future<void> finish(int index) async {
    running = false;
    await syncs[index].close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
  );
}

class _Tip extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  @override
  Future<BigInt> getLatestBlockHeight() async => BigInt.from(100);
}

class _Upgrade extends ChainUpgradeStatusNotifier {
  @override
  Future<ChainUpgradeStatusState> build() async =>
      ChainUpgradeStatusState.cachedActive(defaultRpcEndpointConfig('main'));

  @override
  Future<void> refreshAtTip(BigInt tipHeight) async {}
}

class _NoPrivateQueries extends EnhancePirNotifier {
  @override
  bool build() => false;
}

class _Sync extends SyncNotifier {
  _Sync()
    : super(
        walletDbPathResolver: () async => 'wallet.db',
        excludeCompanionsFromBackup: (_) async {},
      );

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _accountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    scannedHeight: 100,
    chainTipHeight: 100,
  );
}

rust_sync.ApiSyncProgressEvent _complete() => rust_sync.ApiSyncProgressEvent(
  scannedHeight: BigInt.from(100),
  chainTipHeight: BigInt.from(100),
  percentage: 1,
  displayTargetPercentage: 1,
  displayTargetBlocks: BigInt.zero,
  isSyncing: false,
  isComplete: true,
  hasNewTx: false,
  phaseCompletedUnits: BigInt.zero,
  phaseTotalUnits: BigInt.zero,
  phase: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.running = false;
    api.syncs.clear();
  });

  /// A foreground sync that has reported completion and is now running its
  /// post-sync follow-ups: Dart no longer counts it as syncing, but its
  /// stream is open and Rust still holds the guard.
  Future<_Sync> inFollowUp() async {
    final sync = _Sync();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    sync.stopTipChecksForTesting();

    sync.startSync();
    await pumpEventQueue();
    expect(api.syncs, hasLength(1));
    api.syncs[0].add(_complete());
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    final completed = container.read(syncProvider).requireValue;
    expect(completed.isSyncing, isFalse);
    expect(completed.isSyncComplete, isTrue);
    expect(api.running, isTrue, reason: 'the follow-ups hold the guard');
    return sync;
  }

  test('a foreground start during the follow-up is queued, then started '
      'once the stream ends', () async {
    final sync = await inFollowUp();

    // Before, this start was dropped: "Sync: already running, skipping".
    sync.startSync(latestTipHeight: 101);
    await pumpEventQueue();
    expect(api.syncs, hasLength(1), reason: 'no concurrent sync');
    expect(sync.queuedSyncStartForTesting, (
      forced: false,
      latestTipHeight: 101,
    ));

    await api.finish(0);
    await pumpEventQueue();

    expect(api.syncs, hasLength(2), reason: 'the queued start ran');
    expect(sync.queuedSyncStartForTesting, isNull);
  });

  test('repeated requests coalesce into one queued start', () async {
    final sync = await inFollowUp();

    sync.startSync(latestTipHeight: 101);
    sync.startSync();
    sync.startSync(latestTipHeight: 103);
    sync.startSync(latestTipHeight: 102);
    expect(sync.queuedSyncStartForTesting, (
      forced: false,
      latestTipHeight: 103,
    ));

    await api.finish(0);
    await pumpEventQueue();
    expect(api.syncs, hasLength(2));

    // The second sync then ends without anything queued behind it.
    api.syncs[1].add(_complete());
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    await api.finish(1);
    await pumpEventQueue();
    expect(api.syncs, hasLength(2));
  });

  test('a forced request upgrades a queued plain one', () async {
    final sync = await inFollowUp();

    sync.startSync(latestTipHeight: 101);
    await sync.startSyncAnyway();
    sync.startSync();
    expect(sync.queuedSyncStartForTesting, (
      forced: true,
      latestTipHeight: 101,
    ));
    expect(api.syncs, hasLength(1));

    await api.finish(0);
    await pumpEventQueue();
    expect(api.syncs, hasLength(2));
  });

  test('stopping sync discards the queued start', () async {
    final sync = await inFollowUp();
    sync.startSync();
    sync.stopSync();
    expect(sync.queuedSyncStartForTesting, isNull);

    await api.finish(0);
    await pumpEventQueue();
    expect(api.syncs, hasLength(1));
  });

  test('a sync this notifier does not own is still never joined', () async {
    final sync = _Sync();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    sync.stopTipChecksForTesting();
    // Native background preparation holds the guard.
    api.running = true;

    sync.startSync();
    await pumpEventQueue();

    expect(api.syncs, isEmpty);
    expect(sync.queuedSyncStartForTesting, isNull);
  });
}
