import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_process_work_policy.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart' as rust_swap;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _first = 'account-1';
const _second = 'account-2';

/// How many times the idle poll read the chain tip.
var _tipReads = 0;

/// Rust as the scheduler sees it: ordinary sync streams that the test drives
/// block by block, and receiver recovery rounds that the test holds and
/// releases explicitly. Nothing here sleeps; every wait is a completer.
class _Api extends RustLibApi {
  bool running = false;
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];
  final recoveries = <Completer<bool>>[];
  final manual = <Completer<void>>[];
  final statusReads = <Completer<rust_swap.SwapRecoveryStatus>>[];
  final events = <String>[];
  final balanceReads = <String>[];
  int cancels = 0;

  /// The newest automatic round, which the test completes with whether it had
  /// work to release it.
  Completer<bool> get round => recoveries.last;

  /// Whether this fake's ordinary sync still holds the Rust guard.
  @override
  bool crateApiSyncIsSyncRunning() => running;

  /// Reports no pending cancellation, so stops complete at once.
  @override
  bool crateApiSyncIsSyncCancelRequested() => false;

  /// Reports no mempool observer, which these tests never start.
  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  /// Ignores the refresh order hint for the active account.
  @override
  void crateApiSyncSetActiveSyncAccount({String? accountUuid}) {}

  /// Ignores the foreground or background mode request.
  @override
  void crateApiSyncSetSyncMode({required int mode}) {}

  /// Releases the sync guard, as Rust does once a cancelled sync stops.
  @override
  void crateApiSyncCancelFullSync() {
    running = false;
  }

  /// Accepts the stop request for the observer that never runs.
  @override
  void crateApiSyncStopMempoolObserver() {}

  /// Starts no mempool observation and ends at once.
  @override
  Stream<rust_sync.ApiMempoolTxEvent> crateApiSyncStartMempoolObserver({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
  }) => const Stream.empty();

  /// Starts an ordinary sync whose batches the test adds to the returned stream.
  @override
  Stream<rust_sync.ApiSyncProgressEvent> crateApiSyncStartFullSync({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required int mode,
  }) {
    if (running) throw StateError('an unowned concurrent sync was spawned');
    running = true;
    events.add('sync');
    final controller = StreamController<rust_sync.ApiSyncProgressEvent>();
    syncs.add(controller);
    return controller.stream;
  }

  /// Starts a receiver round that stays pending until the test completes it.
  @override
  Future<bool> crateApiOneTimeIvkRunSwapRecovery({
    required String dbPath,
    required String networkName,
  }) {
    events.add('recover');
    final round = Completer<bool>();
    recoveries.add(round);
    return round.future;
  }

  /// Counts a cancellation; the held round ends only when the test completes it.
  @override
  void crateApiOneTimeIvkCancelSwapRecovery() {
    cancels++;
    events.add('cancel');
  }

  /// Starts a manual check, pending until the test completes it.
  @override
  Future<void> crateApiOneTimeIvkCheckSwapHistory({
    required String dbPath,
    required String networkName,
  }) {
    events.add('manual');
    final check = Completer<void>();
    manual.add(check);
    return check.future;
  }

  /// Reads the saved swap recovery state, pending until the test completes it.
  @override
  Future<rust_swap.SwapRecoveryStatus> crateApiOneTimeIvkGetSwapRecoveryStatus({
    required String dbPath,
    required String networkName,
  }) {
    final read = Completer<rust_swap.SwapRecoveryStatus>();
    statusReads.add(read);
    return read.future;
  }

  /// When set, the durable pause stays pending until the test completes it.
  Completer<void>? heldCancel;

  /// Records that the durable manual job was paused.
  @override
  Future<void> crateApiOneTimeIvkCancelSwapHistory({
    required String dbPath,
    required String networkName,
  }) async {
    events.add('cancel manual');
    await heldCancel?.future;
  }

  /// Records which account's balance was read and returns a fixed balance.
  @override
  Future<rust_sync.WalletBalance> crateApiSyncGetBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    balanceReads.add(accountUuid);
    return rust_sync.WalletBalance(
      availability: rust_sync.WalletBalanceAvailability.available,
      transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
      transparentPrivate: false,
      transparent: BigInt.zero,
      sapling: BigInt.zero,
      orchard: BigInt.zero,
      ironwood: BigInt.one,
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
  }

  /// Returns an empty history.
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

  /// Fails any Rust call this fake does not expect.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Account extends AccountNotifier {
  /// Two accounts with the first active.
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(uuid: _first, name: 'Account 1', order: 0),
      AccountInfo(uuid: _second, name: 'Account 2', order: 1),
    ],
    activeAccountUuid: _first,
  );

  /// Makes `uuid` the active account, as the account switcher does.
  void activate(String uuid) {
    state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
  }
}

class _Security extends AppSecurityNotifier {
  /// An unlocked wallet with a password.
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  /// Locks or unlocks the wallet session.
  void setUnlocked(bool unlocked) {
    state = state.copyWith(isUnlocked: unlocked);
  }
}

class _Tip extends RpcEndpointFailoverNotifier {
  /// The default Mainnet endpoint without fallbacks.
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  /// Reports the chain tip the initial state already scanned, counting reads.
  @override
  Future<BigInt> getLatestBlockHeight() async {
    _tipReads++;
    return BigInt.from(100);
  }
}

class _Upgrade extends ChainUpgradeStatusNotifier {
  /// Treats the chain upgrade as active.
  @override
  Future<ChainUpgradeStatusState> build() async =>
      ChainUpgradeStatusState.cachedActive(defaultRpcEndpointConfig('main'));

  /// Skips the upgrade refresh.
  @override
  Future<void> refreshAtTip(BigInt tipHeight) async {}
}

class _NoPrivateQueries extends EnhancePirNotifier {
  /// Keeps Private queries off, which these scheduling tests do not need.
  @override
  bool build() => false;
}

class _PrivacyOn extends NearSwapPrivacyNotifier {
  /// Keeps NEAR swap privacy on without a private service or wallet.
  @override
  bool build() => true;
}

class _Sync extends SyncNotifier {
  _Sync()
    : super(
        walletDbPathResolver: () async => 'wallet.db',
        existingWalletDbPathResolver: () async => 'wallet.db',
        excludeCompanionsFromBackup: (_) async {},
      );

  /// A completed sync of the first account at height 100.
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _first,
    hasAccountScopedData: true,
    isSyncComplete: true,
    scannedHeight: 100,
    chainTipHeight: 100,
  );
}

/// One ordinary sync batch that scanned through `height`.
rust_sync.ApiSyncProgressEvent _scanned(
  int height, {
  rust_sync.ApiSyncEventKind kind = rust_sync.ApiSyncEventKind.progress,
}) => rust_sync.ApiSyncProgressEvent(
  kind: kind,
  scannedHeight: BigInt.from(height),
  chainTipHeight: BigInt.from(height),
  percentage: 1,
  displayTargetPercentage: 1,
  displayTargetBlocks: BigInt.zero,
  isSyncing: kind == rust_sync.ApiSyncEventKind.progress,
  hasNewTx: false,
  phaseCompletedUnits: BigInt.zero,
  phaseTotalUnits: BigInt.zero,
  phase: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  setUpAll(() {
    api = _Api();
    RustLib.initMock(api: api);
  });
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.running = false;
    api.syncs.clear();
    api.recoveries.clear();
    api.manual.clear();
    api.statusReads.clear();
    api.heldCancel = null;
    api.events.clear();
    api.balanceReads.clear();
    api.cancels = 0;
    _tipReads = 0;
  });

  late ProviderContainer container;

  /// A notifier whose first ordinary sync has scanned block 101, which starts a
  /// receiver round the test holds. NEAR swap privacy is off unless `privacy`.
  Future<_Sync> recovering({bool privacy = false}) async {
    final sync = _Sync();
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        appSecurityProvider.overrideWith(_Security.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        if (privacy) nearSwapPrivacyProvider.overrideWith(_PrivacyOn.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    sync.stopTipChecksForTesting();
    sync.startSync();
    await pumpEventQueue();
    api.syncs[0].add(_scanned(101));
    await pumpEventQueue();
    expect(
      api.recoveries,
      hasLength(1),
      reason: 'sync progress starts a round',
    );
    return sync;
  }

  /// Lets queued sync work finish, then stops it before the container goes.
  Future<void> settle(_Sync sync) async {
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    sync.stopSync();
    await pumpEventQueue();
  }

  /// Releases the held round, as Rust does once it stops, reporting whether
  /// any account had recovery work.
  Future<void> releaseRound({bool work = true}) async {
    api.round.complete(work);
    await pumpEventQueue();
  }

  test(
    'ordinary sync scans more than three blocks and starts again while a '
    'receiver round is held, and the release needs no further block',
    () async {
      final sync = await recovering();

      for (final height in [102, 103, 104, 105]) {
        api.syncs[0].add(_scanned(height));
        await pumpEventQueue();
        expect(sync.state.requireValue.scannedHeight, height);
      }
      api.syncs[0].add(
        _scanned(105, kind: rust_sync.ApiSyncEventKind.completed),
      );
      await pumpEventQueue();
      await api.finish(0);
      await pumpEventQueue();
      expect(sync.state.requireValue.isSyncComplete, isTrue);

      // A new tip starts the next ordinary sync while the round is still held.
      sync.startSync(latestTipHeight: 109);
      await pumpEventQueue();
      expect(api.syncs, hasLength(2));
      for (final height in [106, 107, 108, 109]) {
        api.syncs[1].add(_scanned(height));
        await pumpEventQueue();
      }
      sync.stopTipChecksForTesting();
      expect(sync.state.requireValue.scannedHeight, 109);
      expect(api.recoveries, hasLength(1), reason: 'one round at a time');
      expect(api.cancels, 0, reason: 'sync never cancels or waits for it');
      expect(api.round.isCompleted, isFalse);

      final reads = api.balanceReads.length;
      final followups = container.read(syncFollowupProvider);
      await releaseRound();
      expect(container.read(syncFollowupProvider), followups + 1);
      expect(api.balanceReads.length, greaterThan(reads));
      expect(api.syncs, hasLength(2), reason: 'no new sync was needed');
      expect(api.manual, isEmpty, reason: 'no manual action was needed');

      // The next batch starts the next round of durable work.
      api.syncs[1].add(_scanned(110));
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      expect(api.recoveries, hasLength(2));
    },
  );

  test('with NEAR swap privacy off, a round without work skips the refresh '
      'and stops batch and poll rounds until a sync completes', () async {
    final sync = await recovering();
    final reads = api.balanceReads.length;
    final followups = container.read(syncFollowupProvider);
    await releaseRound(work: false);
    expect(container.read(syncFollowupProvider), followups);
    expect(api.balanceReads.length, reads);

    for (final height in [102, 103]) {
      api.syncs[0].add(_scanned(height));
      await pumpEventQueue();
    }
    sync.stopTipChecksForTesting();
    expect(api.recoveries, hasLength(1), reason: 'nothing is due');

    // A completed sync may have queued repair, so Rust is asked once more.
    api.syncs[0].add(_scanned(103, kind: rust_sync.ApiSyncEventKind.completed));
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(api.recoveries, hasLength(2));
    await releaseRound(work: false);

    // With the sync finished, an idle poll reads the tip but starts no round.
    await api.finish(0);
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    final rounds = api.recoveries.length;
    final tipReads = _tipReads;
    await sync.checkTipForTesting();
    sync.stopTipChecksForTesting();
    expect(_tipReads, tipReads + 1, reason: 'the poll ran');
    expect(
      api.recoveries,
      hasLength(rounds),
      reason: 'the idle poll asks nothing',
    );

    // Callers waiting on recovery still start a round.
    sync.continueSwapRecovery();
    await pumpEventQueue();
    expect(api.recoveries, hasLength(rounds + 1));
    await releaseRound(work: false);
    await settle(sync);
  });

  test(
    'with NEAR swap privacy on, rounds keep following sync batches',
    () async {
      final sync = await recovering(privacy: true);
      await releaseRound(work: false);
      api.syncs[0].add(_scanned(102));
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      expect(api.recoveries, hasLength(2));
      await releaseRound();
      await settle(sync);
    },
  );

  test('locking cancels the held round and waits for it to drain; unlock '
      'resumes pending work', () async {
    final sync = await recovering();
    final security = container.read(appSecurityProvider.notifier) as _Security;
    security.setUnlocked(false);
    var locked = false;
    unawaited(sync.clearSensitiveStateForLock().then((_) => locked = true));
    await pumpEventQueue();
    expect(api.cancels, 1);
    expect(locked, isFalse, reason: 'lock waits for the worker to stop');

    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(locked, isTrue);

    // A late tip check while locked starts nothing.
    await sync.checkTipForTesting();
    expect(api.recoveries, hasLength(1));

    security.setUnlocked(true);
    await sync.checkTipForTesting();
    await settle(sync);
    expect(api.recoveries, hasLength(2), reason: 'saved work resumes');
  });

  test('waiting on a round returns its failure, or nothing once it succeeds '
      'or was cancelled', () async {
    final sync = await recovering(privacy: true);
    const outage = rust_swap.ReceiveError(
      message: 'HTTP 503',
      kind: rust_swap.ReceiveErrorKind.other,
    );
    final failed = sync.awaitSwapRecovery();
    api.round.completeError(outage);
    expect(await failed, same(outage), reason: 'it waited on the held round');

    final succeeded = sync.awaitSwapRecovery();
    await pumpEventQueue();
    expect(api.recoveries, hasLength(2), reason: 'it started a new round');
    await releaseRound();
    expect(await succeeded, isNull);

    final cancelled = sync.awaitSwapRecovery();
    await pumpEventQueue();
    final security = container.read(appSecurityProvider.notifier) as _Security;
    security.setUnlocked(false);
    unawaited(sync.clearSensitiveStateForLock());
    await pumpEventQueue();
    api.round.completeError(outage);
    expect(await cancelled, isNull, reason: 'locking cancelled the round');
    await settle(sync);
  });

  test('backgrounding cancels the round where process work must stop; '
      'otherwise the round keeps running', () async {
    final sync = await recovering();
    sync.handleAppHideForTesting();
    // Desktop keeps process work alive while hidden. Mobile hands it to the
    // platform and must stop the round.
    final keepsRunning = canRunAppProcessWork(isInForeground: false);
    expect(api.cancels, keepsRunning ? 0 : 1);
    await releaseRound();

    sync.handleAppResumeForTesting();
    api.syncs[0].add(_scanned(102));
    await settle(sync);
    expect(api.recoveries, hasLength(2), reason: 'returning resumes the work');
  });

  test('a transport change stops and drains the round before switching '
      'routes', () async {
    final sync = await recovering();
    final order = <String>[];
    final restarting = sync.restartSyncAfterTransportChange(
      () async => order.add('route changed'),
      failIfNotQuiescent: false,
    );
    await pumpEventQueue();
    expect(api.cancels, 1);
    expect(order, isEmpty, reason: 'the old route is still in use');

    order.add('round drained');
    api.round.completeError('Swap recovery was cancelled.');
    await restarting;
    await settle(sync);
    expect(order, ['round drained', 'route changed']);
  });

  test('a wallet mutation drains the round first and blocks new rounds until '
      'it ends', () async {
    final sync = await recovering();
    var paused = false;
    late WalletMutationSyncPause pause;
    unawaited(
      sync.pauseForWalletMutation().then((value) {
        pause = value;
        paused = true;
      }),
    );
    await pumpEventQueue();
    expect(api.cancels, 1);
    expect(paused, isFalse, reason: 'mutation waits for the worker');
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(paused, isTrue);

    await sync.checkTipForTesting();
    sync.continueSwapRecovery();
    await pumpEventQueue();
    expect(api.recoveries, hasLength(1), reason: 'no round during a mutation');

    sync.resumeAfterWalletMutation(pause);
    await pumpEventQueue();
    sync.continueSwapRecovery();
    await settle(sync);
    expect(api.recoveries, hasLength(2));
  });

  test('a wallet mutation waits for a swap status read, and none starts while '
      'it runs', () async {
    final sync = await recovering();
    await releaseRound(work: false);
    const idle = rust_swap.SwapRecoveryStatus(
      checkingHistory: false,
      manualCheckActive: false,
      upgradeRequired: false,
    );
    // The round's answer starts the saved-state read.
    for (final read in api.statusReads) {
      read.complete(idle);
    }
    await pumpEventQueue();
    api.statusReads.clear();

    final read = sync.swapRecoveryStatus();
    await pumpEventQueue();
    expect(api.statusReads, hasLength(1));
    var paused = false;
    late WalletMutationSyncPause pause;
    unawaited(
      sync.pauseForWalletMutation().then((value) {
        pause = value;
        paused = true;
      }),
    );
    await pumpEventQueue();
    expect(paused, isFalse, reason: 'the native read is still active');
    api.statusReads.single.complete(idle);
    expect(await read, idle);
    await pumpEventQueue();
    expect(paused, isTrue);

    await expectLater(sync.swapRecoveryStatus(), throwsStateError);
    expect(api.statusReads, hasLength(1), reason: 'no read during a mutation');
    sync.resumeAfterWalletMutation(pause);
    await settle(sync);
  });

  test('a wallet mutation waits for a held history pause write, and none '
      'starts while it runs', () async {
    final sync = await recovering();
    await releaseRound(work: false);
    // The round's answer starts the saved-state read.
    for (final read in api.statusReads) {
      read.complete(
        const rust_swap.SwapRecoveryStatus(
          checkingHistory: false,
          manualCheckActive: false,
          upgradeRequired: false,
        ),
      );
    }
    await pumpEventQueue();
    api.heldCancel = Completer<void>();
    final cancel = sync.cancelSwapHistory();
    await pumpEventQueue();
    expect(api.events.last, 'cancel manual');

    var paused = false;
    late WalletMutationSyncPause pause;
    unawaited(
      sync.pauseForWalletMutation().then((value) {
        pause = value;
        paused = true;
      }),
    );
    await pumpEventQueue();
    expect(paused, isFalse, reason: 'the pause write is still open');
    api.heldCancel!.complete();
    await cancel;
    await pumpEventQueue();
    expect(paused, isTrue);

    api.heldCancel = null;
    final writes = api.events.where((e) => e == 'cancel manual').length;
    await expectLater(sync.cancelSwapHistory(), throwsStateError);
    expect(
      api.events.where((e) => e == 'cancel manual').length,
      writes,
      reason: 'no pause write during a mutation',
    );
    sync.resumeAfterWalletMutation(pause);
    await settle(sync);
  });

  test('switching accounts keeps the account-agnostic round, and its result '
      'refreshes the newly active account', () async {
    final sync = await recovering();
    final accounts = container.read(accountProvider.notifier) as _Account;
    accounts.activate(_second);
    sync.handleAccountSwitchForTesting(_second);
    await pumpEventQueue();
    expect(api.cancels, 0);
    expect(api.recoveries, hasLength(1));

    api.balanceReads.clear();
    await releaseRound();
    expect(api.balanceReads, isNotEmpty);
    expect(api.balanceReads.toSet(), {_second});
  });

  test('a manual check stops the automatic round first and pauses through '
      'Rust after draining', () async {
    final sync = await recovering();
    final checking = sync.checkSwapHistory();
    await pumpEventQueue();
    expect(api.cancels, 1);
    expect(api.manual, isEmpty, reason: 'the automatic round still runs');
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(api.manual, hasLength(1));

    // Pausing cancels the manual round, waits for it, then records the pause.
    final pausing = sync.cancelSwapHistory();
    await pumpEventQueue();
    expect(api.cancels, 2);
    expect(api.events.last, 'cancel');
    api.manual.single.completeError('Swap recovery was cancelled.');
    await expectLater(checking, throwsA(isA<Object>()));
    await pausing;
    expect(api.events.last, 'cancel manual');
    sync.stopTipChecksForTesting();
  });

  test('a manual check cancelled under it reports the cancellation, not the '
      'round error', () async {
    final sync = await recovering();
    final checking = sync.checkSwapHistory();
    await pumpEventQueue();
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(api.manual, hasLength(1));

    final security = container.read(appSecurityProvider.notifier) as _Security;
    security.setUnlocked(false);
    unawaited(sync.clearSensitiveStateForLock());
    await pumpEventQueue();
    api.manual.single.completeError(
      const rust_swap.ReceiveError(
        message: 'Swap recovery was cancelled.',
        kind: rust_swap.ReceiveErrorKind.other,
      ),
    );
    await expectLater(checking, throwsA(isA<StateError>()));
    await settle(sync);
  });
}
