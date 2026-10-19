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

/// Rust with a mempool observer the test drives: each start returns the same
/// stream, on which the test pushes the observer's events.
class _Api extends RustLibApi {
  bool running = false;
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];
  var mempool = StreamController<rust_sync.ApiMempoolTxEvent>.broadcast();

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
  }) => mempool.stream;

  @override
  Stream<rust_sync.ApiSyncProgressEvent> crateApiSyncStartFullSync({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required int mode,
  }) {
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

  void newBlock() => mempool.add(
    const rust_sync.ApiMempoolTxEvent(
      txidHex: '',
      accountUuids: [],
      matched: false,
      newBlock: true,
    ),
  );

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

/// The served tip, counting how often the app asks for it.
class _Tip extends RpcEndpointFailoverNotifier {
  static int height = 100;
  static int checks = 0;

  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  @override
  Future<BigInt> getLatestBlockHeight() async {
    checks++;
    return BigInt.from(height);
  }
}

class _Upgrade extends ChainUpgradeStatusNotifier {
  /// When set, a tip check waits here after reading the tip.
  static Completer<void>? hold;

  @override
  Future<ChainUpgradeStatusState> build() async =>
      ChainUpgradeStatusState.cachedActive(defaultRpcEndpointConfig('main'));

  @override
  Future<void> refreshAtTip(BigInt tipHeight) async {
    final wait = hold;
    if (wait != null) await wait.future;
  }
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
  kind: rust_sync.ApiSyncEventKind.completed,
  scannedHeight: BigInt.from(100),
  chainTipHeight: BigInt.from(100),
  percentage: 1,
  displayTargetPercentage: 1,
  displayTargetBlocks: BigInt.zero,
  isSyncing: false,
  hasNewTx: false,
  phaseCompletedUnits: BigInt.zero,
  phaseTotalUnits: BigInt.zero,
  phase: '',
  syncJobId: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.running = false;
    api.syncs.clear();
    api.mempool = StreamController<rust_sync.ApiMempoolTxEvent>.broadcast();
    _Tip.height = 100;
    _Tip.checks = 0;
    _Upgrade.hold = null;
  });

  /// A notifier whose first sync is running, with the mempool observer up.
  /// The poll timer is stopped, so only the observer can trigger a check.
  Future<_Sync> syncing() async {
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
    addTearDown(() {
      sync.stopTipChecksForTesting();
      container.dispose();
    });
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    sync.stopTipChecksForTesting();
    sync.startSync();
    await pumpEventQueue();
    expect(api.syncs, hasLength(1));
    return sync;
  }

  /// The first sync has completed and ended; the observer keeps running.
  Future<_Sync> idle() async {
    final sync = await syncing();
    api.syncs[0].add(_complete());
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    await api.finish(0);
    await pumpEventQueue();
    _Tip.checks = 0;
    return sync;
  }

  test('a new block from the mempool observer checks the tip at once and '
      'syncs to it', () async {
    await idle();
    _Tip.height = 101;

    api.newBlock();
    await pumpEventQueue();

    expect(api.syncs, hasLength(2), reason: 'the new tip started a sync');
    expect(_Tip.checks, 2, reason: "the check, then the sync's preflight");
  });

  test('a burst of new-block events checks the tip once', () async {
    await idle();

    api.newBlock();
    api.newBlock();
    api.newBlock();
    await pumpEventQueue();

    expect(_Tip.checks, 1);
    expect(api.syncs, hasLength(1), reason: 'the tip did not move');
  });

  test('a new block during a sync is checked as soon as the sync '
      'completes', () async {
    await syncing();
    _Tip.height = 101;
    _Tip.checks = 0; // the sync's own preflight

    api.newBlock();
    await pumpEventQueue();
    expect(_Tip.checks, 0, reason: 'a running sync defers the check');

    api.syncs[0].add(_complete());
    await pumpEventQueue();
    expect(_Tip.checks, 1);
  });

  test('a new block during a tip check is checked again when that check '
      'ends', () async {
    final sync = await idle();
    // A poll's check reads the old tip and is still finishing when the block
    // lands.
    final hold = Completer<void>();
    _Upgrade.hold = hold;
    final check = sync.checkTipForTesting();
    await pumpEventQueue();
    expect(_Tip.checks, 1);
    _Upgrade.hold = null;
    _Tip.height = 101;

    api.newBlock();
    await pumpEventQueue();
    expect(_Tip.checks, 1, reason: 'the check in flight defers the new one');

    hold.complete();
    await check;
    await pumpEventQueue();
    expect(
      _Tip.checks,
      3,
      reason:
          "the held check, the new block's check, then the sync's preflight",
    );
    expect(api.syncs, hasLength(2), reason: 'the new tip started a sync');
  });
}
