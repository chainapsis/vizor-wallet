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
import 'package:zcash_wallet/src/providers/sync_short_catch_up_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

// After an app-lock unlock, the resume's tip check can start the catch-up
// before the unlock screen's refresh restores the completed state the lock
// cleared. That sync must still start as a catch-up of a synced wallet.

const _accountUuid = 'account-1';
const _completedHeight = 3000000;

class _Api extends RustLibApi {
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];

  @override
  bool crateApiSyncIsSyncRunning() => false;

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
    final controller = StreamController<rust_sync.ApiSyncProgressEvent>();
    syncs.add(controller);
    return controller.stream;
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

/// Four blocks past the height the wallet completed at.
class _Tip extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  @override
  Future<BigInt> getLatestBlockHeight() async =>
      BigInt.from(_completedHeight + 4);
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

/// A synced wallet whose stored status says its last sync completed. The
/// balance read can be held open, as a slow wallet summary does.
class _Sync extends SyncNotifier {
  _Sync()
    : super(
        walletDbPathResolver: () async => 'wallet.db',
        excludeCompanionsFromBackup: (_) async {},
      );

  int statusReads = 0;
  final balanceRead = Completer<void>();
  final balanceReadStarted = Completer<void>();

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _accountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: _completedHeight,
    chainTipHeight: _completedHeight,
  );

  @override
  Future<rust_sync.SyncProgress> readSyncStatus({
    required String dbPath,
    required String network,
  }) async {
    statusReads++;
    return rust_sync.SyncProgress(
      scannedHeight: BigInt.from(_completedHeight),
      chainTipHeight: BigInt.from(_completedHeight),
      isSyncing: false,
      isComplete: true,
      syncJobId: '',
      syncJobFraction: 0,
    );
  }

  @override
  Future<rust_sync.WalletBalance> readWalletBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    if (!balanceReadStarted.isCompleted) balanceReadStarted.complete();
    await balanceRead.future;
    return _balance;
  }

  @override
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => const [];
}

final _balance = rust_sync.WalletBalance(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(api.syncs.clear);

  /// A synced wallet that was locked (its state cleared) and is unlocked
  /// again, before the unlock screen has refreshed anything.
  Future<(ProviderContainer, _Sync)> unlockedAfterLock() async {
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
      if (!sync.balanceRead.isCompleted) sync.balanceRead.complete();
      container.dispose();
    });
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    await sync.clearSensitiveStateForLock();
    final cleared = container.read(syncProvider).requireValue;
    expect(cleared.isSyncComplete, isFalse);
    expect(cleared.chainTipHeight, 0);
    return (container, sync);
  }

  void expectCatchUp(SyncState started) {
    expect(started.isSyncing, isTrue);
    expect(started.startedFromCompletedSync, isTrue);
    expect(started.scannedHeight, _completedHeight);
    expect(isShortSyncCatchUp(started, now: DateTime.now()), isTrue);
  }

  test(
    'a tip check that runs before the unlock refresh starts a catch-up',
    () async {
      final (container, sync) = await unlockedAfterLock();

      // The resume's tip check, then the unlock screen's refresh.
      final check = sync.checkTipForTesting();
      final unlock = sync.refreshAfterUnlock();
      await check;

      expectCatchUp(container.read(syncProvider).requireValue);
      expect(sync.statusReads, 1);
      sync.balanceRead.complete();
      await unlock;
      // Home opens on the account's balance, not the import screen.
      expect(
        container
            .read(syncProvider)
            .requireValue
            .hasDataForAccount(_accountUuid),
        isTrue,
      );
    },
  );

  test('a tip check during the unlock refresh starts a catch-up', () async {
    final (container, sync) = await unlockedAfterLock();

    final unlock = sync.refreshAfterUnlock();
    // The balance read is slow; the resume's tip check starts the sync.
    await sync.balanceReadStarted.future;
    await sync.checkTipForTesting();

    expectCatchUp(container.read(syncProvider).requireValue);
    expect(sync.statusReads, 1);
    sync.balanceRead.complete();
    await unlock;
    // Home opens on the account's balance, not the import screen.
    expect(
      container.read(syncProvider).requireValue.hasDataForAccount(_accountUuid),
      isTrue,
    );
  });
}
