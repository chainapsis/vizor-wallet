import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

/// Public mode (private queries off): the Rust sync engine reports
/// `Completed`, then keeps its stream open for the transparent-details
/// follow-up (loop 4), which may emit `FollowupUpdated` before the stream
/// closes. With private queries off the wallet must behave as main did:
/// synced as soon as `Completed` arrives, one sync at a time, polling alive,
/// and nothing applied after a lock.

const _accountUuid = 'account-1';
const _tip = 100;

/// Rust as the foreground sync sees it: one guard, held from `startFullSync`
/// until the test closes that sync's stream, follow-ups included.
class _Api extends RustLibApi {
  bool running = false;
  int historyReads = 0;
  int balanceReads = 0;
  int cancels = 0;
  BigInt orchard = BigInt.one;
  List<rust_sync.TransactionInfo> history = const [];

  /// When set, balance reads wait for it.
  Completer<void>? balanceGate;
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

  /// Rust stops the run and releases the guard.
  @override
  void crateApiSyncCancelFullSync() {
    cancels++;
    running = false;
  }

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
  }) async {
    balanceReads++;
    final value = orchard;
    final gate = balanceGate;
    if (gate != null) await gate.future;
    return rust_sync.WalletBalance(
      availability: rust_sync.WalletBalanceAvailability.available,
      transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
      transparentPrivate: false,
      transparent: BigInt.zero,
      sapling: BigInt.zero,
      orchard: value,
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
      spendable: value,
      locked: BigInt.zero,
      total: value,
    );
  }

  @override
  Future<List<rust_sync.TransactionInfo>> crateApiSyncGetTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async {
    historyReads++;
    return history;
  }

  /// Ends the sync that holds the guard: Rust releases it, then the stream
  /// closes.
  Future<void> finish(int index) async {
    running = false;
    await syncs[index].close();
  }

  void reset() {
    running = false;
    historyReads = 0;
    balanceReads = 0;
    cancels = 0;
    orchard = BigInt.one;
    history = const [];
    balanceGate = null;
    syncs.clear();
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
  static int tip = _tip;
  static int calls = 0;

  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  @override
  Future<BigInt> getLatestBlockHeight() async {
    calls++;
    return BigInt.from(tip);
  }
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

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  void lock() => state = state.copyWith(isUnlocked: false);

  void unlockForTesting() => state = state.copyWith(isUnlocked: true);
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
    scannedHeight: _tip,
    chainTipHeight: _tip,
  );
}

rust_sync.ApiSyncProgressEvent _event(
  rust_sync.ApiSyncEventKind kind, {
  int height = _tip,
}) => rust_sync.ApiSyncProgressEvent(
  kind: kind,
  scannedHeight: BigInt.from(height),
  chainTipHeight: BigInt.from(height),
  percentage: 1,
  displayTargetPercentage: 1,
  displayTargetBlocks: BigInt.zero,
  isSyncing: false,
  hasNewTx: false,
  phaseCompletedUnits: BigInt.zero,
  phaseTotalUnits: BigInt.zero,
  phase: '',
);

final _completed = _event(rust_sync.ApiSyncEventKind.completed);
final _followup = _event(rust_sync.ApiSyncEventKind.followupUpdated);

rust_sync.TransactionInfo _shieldedReceive() => rust_sync.TransactionInfo(
  txidHex: 'ab' * 32,
  minedHeight: BigInt.from(_tip),
  expiredUnmined: false,
  accountBalanceDelta: 4,
  fee: BigInt.zero,
  feeState: rust_sync.TransactionFeeState.notApplicable,
  detailsComplete: true,
  provisional: false,
  amountIncludesFee: false,
  blockTime: BigInt.from(1764150000),
  isTransparent: false,
  txKind: 'received',
  displayAmount: BigInt.from(4),
  displayPool: 'shielded',
  createdTime: BigInt.from(1764150000),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.reset();
    _Tip.tip = _tip;
    _Tip.calls = 0;
  });

  late ProviderContainer container;
  late _Security security;

  Future<_Sync> start() async {
    final sync = _Sync();
    security = _Security();
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        appSecurityProvider.overrideWith(() => security),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    container.listen(syncProvider, (_, _) {});
    container.listen(syncFollowupProvider, (_, _) {});
    await container.read(syncProvider.future);
    sync.stopTipChecksForTesting();
    expect(container.read(enhancePirProvider), isFalse);
    sync.startSync();
    return sync;
  }

  group('public mode, stream open after Completed', () {
    test('Completed reports synced before the stream ends, and the stream end '
        'does not regress it', () async {
      final sync = await start();
      addTearDown(container.dispose);
      await pumpEventQueue();
      expect(api.syncs, hasLength(1));
      expect(sync.state.requireValue.isSyncing, isTrue);

      api.syncs[0].add(_completed);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();

      final completed = sync.state.requireValue;
      expect(completed.isSyncing, isFalse);
      expect(completed.isSyncComplete, isTrue);
      expect(completed.percentage, 1.0);
      expect(completed.scannedHeight, _tip);
      expect(completed.chainTipHeight, _tip);
      expect(completed.hasAccountScopedData, isTrue);
      expect(completed.lastSyncCompletedAt, isNotNull);
      expect(completed.transparentPrivate, isFalse);
      expect(api.running, isTrue, reason: 'the follow-up holds the guard');

      await api.finish(0);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();

      final ended = sync.state.requireValue;
      expect(ended.isSyncing, isFalse);
      expect(ended.isSyncComplete, isTrue);
      expect(ended.percentage, 1.0);
      expect(ended.lastSyncCompletedAt, completed.lastSyncCompletedAt);
      expect(api.syncs, hasLength(1), reason: 'no restart on a clean end');
    });

    test('a late FollowupUpdated refreshes balances and history without '
        'completing again or regressing state', () async {
      final sync = await start();
      addTearDown(container.dispose);
      await pumpEventQueue();
      api.syncs[0].add(_completed);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      final completed = sync.state.requireValue;
      expect(completed.orchardBalance, BigInt.one);
      expect(completed.recentTransactions, isEmpty);
      final historyReads = api.historyReads;
      final balanceReads = api.balanceReads;

      // The follow-up stored new wallet data.
      api.orchard = BigInt.from(5);
      api.history = [_shieldedReceive()];
      api.syncs[0].add(_followup);
      await pumpEventQueue();

      expect(container.read(syncFollowupProvider), 1);
      expect(api.historyReads, historyReads + 1);
      expect(api.balanceReads, balanceReads + 1);
      final updated = sync.state.requireValue;
      expect(updated.orchardBalance, BigInt.from(5));
      expect(updated.spendableBalance, BigInt.from(5));
      expect(updated.recentTransactions.map((tx) => tx.txidHex), ['ab' * 32]);
      expect(updated.isSyncing, isFalse);
      expect(updated.isSyncComplete, isTrue);
      expect(updated.percentage, 1.0);
      expect(updated.scannedHeight, _tip);
      expect(updated.chainTipHeight, _tip);
      expect(updated.lastSyncCompletedAt, completed.lastSyncCompletedAt);
      expect(updated.failure, isNull);
      expect(updated.error, isNull);
      expect(api.syncs, hasLength(1));

      await api.finish(0);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      final ended = sync.state.requireValue;
      expect(ended.orchardBalance, BigInt.from(5));
      expect(ended.recentTransactions, hasLength(1));
      expect(ended.isSyncComplete, isTrue);
    });

    testWidgets('a poll tick during the follow-up starts no second sync, and '
        'polling continues after the stream ends', (tester) async {
      final sync = await start();
      await tester.pump();
      expect(api.syncs, hasLength(1));
      api.syncs[0].add(_completed);
      await tester.pump();
      expect(sync.state.requireValue.isSyncComplete, isTrue);
      expect(api.running, isTrue);
      final tipCalls = _Tip.calls;

      // Completion started polling. Same tip: the tick checks and does
      // nothing.
      await tester.pump(const Duration(seconds: 10));
      expect(_Tip.calls, tipCalls + 1, reason: 'polling runs after Completed');
      expect(api.syncs, hasLength(1));
      expect(sync.queuedSyncStartForTesting, isNull);

      // A new block while the follow-up still holds the guard: the start is
      // queued behind the open stream, never run concurrently.
      _Tip.tip = _tip + 1;
      await tester.pump(const Duration(seconds: 10));
      expect(_Tip.calls, tipCalls + 2);
      expect(api.syncs, hasLength(1), reason: 'no concurrent sync');
      expect(sync.queuedSyncStartForTesting, (
        forced: false,
        latestTipHeight: _tip + 1,
      ));
      // A direct start in the same window is coalesced too.
      sync.startSync();
      await tester.pump();
      expect(api.syncs, hasLength(1));

      // The stream ends: the queued start runs once.
      await api.finish(0);
      await tester.pump();
      expect(api.syncs, hasLength(2));
      expect(sync.queuedSyncStartForTesting, isNull);
      expect(sync.state.requireValue.isSyncing, isTrue);

      // The second sync completes and its stream ends straight away.
      api.syncs[1].add(
        _event(rust_sync.ApiSyncEventKind.completed, height: _tip + 1),
      );
      await tester.pump();
      await api.finish(1);
      await tester.pump();
      expect(sync.state.requireValue.isSyncComplete, isTrue);
      expect(sync.state.requireValue.chainTipHeight, _tip + 1);

      // Polling is still alive after the stream ended.
      final afterEnd = _Tip.calls;
      await tester.pump(const Duration(seconds: 10));
      expect(_Tip.calls, afterEnd + 1, reason: 'polling continues');
      await tester.pump(const Duration(seconds: 10));
      expect(_Tip.calls, afterEnd + 2);
      expect(api.syncs, hasLength(2), reason: 'tip unchanged, no restart');

      sync.stopTipChecksForTesting();
      container.dispose();
    });

    test(
      'locking during the follow-up discards a late FollowupUpdated',
      () async {
        final sync = await start();
        addTearDown(container.dispose);
        await pumpEventQueue();
        api.syncs[0].add(_completed);
        await pumpEventQueue();
        sync.stopTipChecksForTesting();
        final historyReads = api.historyReads;
        final balanceReads = api.balanceReads;

        security.lock();
        await sync.clearSensitiveStateForLock();
        expect(api.cancels, greaterThan(0));
        final locked = sync.state.requireValue;
        expect(locked.hasBalanceData, isFalse);
        expect(locked.recentTransactions, isEmpty);

        // The follow-up's update arrives after the lock.
        api.orchard = BigInt.from(5);
        api.history = [_shieldedReceive()];
        api.syncs[0].add(_followup);
        await pumpEventQueue();

        expect(container.read(syncFollowupProvider), 0);
        expect(api.historyReads, historyReads);
        expect(api.balanceReads, balanceReads);
        expect(sync.state.requireValue.hasBalanceData, isFalse);
        expect(sync.state.requireValue.recentTransactions, isEmpty);

        // Unlocking does not resurrect the stale event either.
        security.unlockForTesting();
        api.syncs[0].add(_followup);
        await pumpEventQueue();
        expect(container.read(syncFollowupProvider), 0);
        expect(api.historyReads, historyReads);
        expect(sync.state.requireValue.hasBalanceData, isFalse);
      },
    );

    test('locking while a FollowupUpdated refresh is in flight discards its '
        'result', () async {
      final sync = await start();
      addTearDown(container.dispose);
      await pumpEventQueue();
      api.syncs[0].add(_completed);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();

      final gate = Completer<void>();
      api.balanceGate = gate;
      api.orchard = BigInt.from(5);
      api.history = [_shieldedReceive()];
      final balanceReads = api.balanceReads;
      api.syncs[0].add(_followup);
      await pumpEventQueue();
      expect(api.balanceReads, balanceReads + 1, reason: 'refresh in flight');

      security.lock();
      await sync.clearSensitiveStateForLock();
      gate.complete();
      await pumpEventQueue();

      final locked = sync.state.requireValue;
      expect(locked.hasBalanceData, isFalse);
      expect(locked.orchardBalance, BigInt.zero);
      expect(locked.recentTransactions, isEmpty);
      expect(locked.isSyncComplete, isFalse);
    });
  });
}
