@Timeout(Duration(seconds: 15))
library;

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
  int historyReads = 0;
  int balanceReads = 0;
  bool unavailableFirstBalance = false;
  bool unavailable = false;
  bool failBalance = false;
  Future<void> Function()? beforeBalance;
  int gatedHistoryRead = 1;
  Completer<List<rust_sync.TransactionInfo>>? historyGate;
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
  }) async {
    balanceReads++;
    if (beforeBalance != null) await beforeBalance!();
    if (failBalance) throw StateError('balance read failed');
    final unavailable =
        this.unavailable || (unavailableFirstBalance && balanceReads == 1);
    final amount = unavailable ? BigInt.zero : BigInt.one;
    return rust_sync.WalletBalance(
      availability: unavailable
          ? rust_sync.WalletBalanceAvailability.summaryUnavailable
          : rust_sync.WalletBalanceAvailability.available,
      transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
      transparentPrivate: false,
      transparent: BigInt.zero,
      sapling: BigInt.zero,
      orchard: amount,
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
      spendable: amount,
      locked: BigInt.zero,
      total: amount,
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
    if (historyReads == gatedHistoryRead && historyGate != null) {
      return historyGate!.future;
    }
    return const [];
  }

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
  void activate(String uuid) =>
      state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
    ],
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

rust_sync.ApiSyncProgressEvent _complete({
  rust_sync.ApiSyncEventKind kind = rust_sync.ApiSyncEventKind.completed,
}) => rust_sync.ApiSyncProgressEvent(
  kind: kind,
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
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.running = false;
    api.historyReads = 0;
    api.balanceReads = 0;
    api.unavailableFirstBalance = false;
    api.unavailable = false;
    api.failBalance = false;
    api.beforeBalance = null;
    api.gatedHistoryRead = 1;
    api.historyGate = Completer<List<rust_sync.TransactionInfo>>();
    api.syncs.clear();
  });

  Future<({ProviderContainer container, _Sync sync})> setup({
    bool finish = true,
  }) async {
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
    addTearDown(() async {
      api.beforeBalance = null;
      if (!api.historyGate!.isCompleted) api.historyGate!.complete([]);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      container.dispose();
    });
    container.listen(syncProvider, (_, _) {});
    await pumpEventQueue();
    sync.startSync();
    await pumpEventQueue();
    expect(api.syncs, hasLength(1));
    if (finish) {
      api.syncs.single.add(_complete());
      await pumpEventQueue();
      unawaited(api.finish(0));
      await pumpEventQueue();
    }
    return (container: container, sync: sync);
  }

  test(
    'completed native scan permits spending while history and sync display stay pending',
    () async {
      final (:sync, :container) = await setup();
      final before = container.read(syncProvider).requireValue;
      expect(before.isUsingCompletedSpendableSnapshot, isTrue);
      expect(before.isSyncing, isTrue);
      expect(api.running, isFalse);
      final reads = api.balanceReads;
      final result = await sync
          .runWithAuthoritativeSpendable(
            accountUuid: _accountUuid,
            operation: () async => 'native proposal',
          )
          .timeout(const Duration(seconds: 1));
      expect(result, 'native proposal');
      expect(
        api.balanceReads,
        reads + 2,
        reason: 'fresh read before and within the sync-start lease',
      );
      expect(container.read(syncProvider).requireValue, same(before));
      expect(api.historyGate!.isCompleted, isFalse);
      api.historyGate!.complete([]);
      await pumpEventQueue();
      expect(container.read(syncProvider).requireValue.isSyncedToTip, isTrue);
    },
  );

  test(
    'resume during pending completion does not make spending await its history chain',
    () async {
      final (:sync, :container) = await setup();
      api.gatedHistoryRead = 2;
      sync.handleAppHideForTesting();
      sync.handleAppResumeForTesting();
      await pumpEventQueue();
      final before = container.read(syncProvider).requireValue;
      await sync
          .runWithAuthoritativeSpendable(
            accountUuid: _accountUuid,
            operation: () async {},
          )
          .timeout(const Duration(seconds: 1));
      expect(container.read(syncProvider).requireValue, same(before));
      expect(api.historyGate!.isCompleted, isFalse);
    },
  );

  test('active native scan must finish before the operation runs', () async {
    final (:sync, :container) = await setup(finish: false);
    var called = false;
    final operation = sync.runWithAuthoritativeSpendable(
      accountUuid: _accountUuid,
      operation: () async {
        called = true;
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(called, isFalse);
    api.syncs.single.add(_complete());
    await pumpEventQueue();
    // Completion can precede native follow-up teardown.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(called, isFalse);
    unawaited(api.finish(0));
    await operation.timeout(const Duration(seconds: 1));
    expect(called, isTrue);
    expect(container.read(syncProvider).requireValue.isSyncing, isTrue);
  });

  test('unavailable balance cannot authorize a carried snapshot', () async {
    final (:sync, :container) = await setup();
    api.unavailable = true;
    final before = container.read(syncProvider).requireValue;
    await expectLater(
      sync.waitForAuthoritativeSpendable(
        accountUuid: _accountUuid,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsStateError,
    );
    expect(container.read(syncProvider).requireValue, same(before));
  });

  test(
    'balance read failure propagates without authorizing the operation',
    () async {
      final (:sync, :container) = await setup();
      api.failBalance = true;
      var called = false;
      await expectLater(
        sync.runWithAuthoritativeSpendable(
          accountUuid: _accountUuid,
          operation: () async {
            called = true;
          },
        ),
        throwsStateError,
      );
      expect(called, isFalse);
    },
  );

  test('stalled direct balance read is bounded by the deadline', () async {
    final (:sync, :container) = await setup();
    final gate = Completer<void>();
    api.beforeBalance = () => gate.future;
    await expectLater(
      sync.waitForAuthoritativeSpendable(
        accountUuid: _accountUuid,
        timeout: const Duration(milliseconds: 100),
      ),
      throwsStateError,
    );
    gate.complete();
    await pumpEventQueue();
    expect(
      container
          .read(syncProvider)
          .requireValue
          .isUsingCompletedSpendableSnapshot,
      isTrue,
    );
  });

  for (final change in ['account', 'lock']) {
    test('$change during a direct read rejects its result', () async {
      final (:sync, :container) = await setup();
      final gate = Completer<void>();
      api.beforeBalance = () => gate.future;
      var called = false;
      final result = sync.runWithAuthoritativeSpendable(
        accountUuid: _accountUuid,
        operation: () async {
          called = true;
        },
      );
      final expectation = expectLater(result, throwsStateError);
      await pumpEventQueue();
      if (change == 'lock') {
        await sync.clearSensitiveStateForLock();
      } else {
        final accounts = container.read(accountProvider.notifier) as _Account;
        accounts.activate('account-2');
        sync.handleAccountSwitchForTesting('account-2');
        if (change == 'account away and back') {
          accounts.activate(_accountUuid);
          sync.handleAccountSwitchForTesting(_accountUuid);
        }
      }
      gate.complete();
      await expectation;
      expect(called, isFalse);
    });
  }

  test(
    'operation keeps foreground starts deferred and releases its lease on error',
    () async {
      final (:sync, :container) = await setup();
      final started = Completer<void>();
      final release = Completer<void>();
      final result = sync.runWithAuthoritativeSpendable(
        accountUuid: _accountUuid,
        operation: () async {
          started.complete();
          await release.future;
          throw StateError('proposal rejected');
        },
      );
      final expectation = expectLater(result, throwsStateError);
      await started.future;
      sync.startSync(latestTipHeight: 101);
      await pumpEventQueue();
      expect(api.syncs, hasLength(1));
      release.complete();
      await expectation;
      // Completion publication still owns its original cleanup.
      api.historyGate!.complete([]);
      await pumpEventQueue();
      sync.startSync(latestTipHeight: 101);
      await pumpEventQueue();
      expect(api.syncs.length, greaterThan(1));
    },
  );

  test(
    'switching away and back requires a fresh read inside the operation lease',
    () async {
      final (:sync, :container) = await setup();
      final reads = api.balanceReads;
      final gate = Completer<void>();
      api.beforeBalance = () => gate.future;
      final result = sync.runWithAuthoritativeSpendable(
        accountUuid: _accountUuid,
        operation: () async => true,
      );
      await pumpEventQueue();
      final accounts = container.read(accountProvider.notifier) as _Account;
      accounts.activate('account-2');
      sync.handleAccountSwitchForTesting('account-2');
      accounts.activate(_accountUuid);
      sync.handleAccountSwitchForTesting(_accountUuid);
      api.beforeBalance = null;
      gate.complete();
      expect(await result, isTrue);
      expect(api.balanceReads, reads + 2);
    },
  );

  test(
    'a new native scan racing the direct read prevents authorization',
    () async {
      final (:sync, :container) = await setup();
      final gate = Completer<void>();
      api.beforeBalance = () => gate.future;
      var called = false;
      final result = sync.runWithAuthoritativeSpendable(
        accountUuid: _accountUuid,
        operation: () async {
          called = true;
        },
      );
      await pumpEventQueue();
      api.historyGate!.complete([]);
      await pumpEventQueue();
      sync.startSync(latestTipHeight: 101);
      await pumpEventQueue();
      expect(api.syncs, hasLength(2));
      api.beforeBalance = null;
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(called, isFalse);
      api.syncs.last.add(_complete());
      await pumpEventQueue();
      unawaited(api.finish(1));
      await result.timeout(const Duration(seconds: 1));
      expect(called, isTrue);
    },
  );

  test('ordinary completed state retains its fast path', () async {
    api.historyGate!.complete([]);
    final (:sync, :container) = await setup();
    expect(container.read(syncProvider).requireValue.isSyncedToTip, isTrue);
    final reads = api.balanceReads;
    await sync.runWithAuthoritativeSpendable(
      accountUuid: _accountUuid,
      operation: () async {},
    );
    expect(api.balanceReads, reads);
  });
}
