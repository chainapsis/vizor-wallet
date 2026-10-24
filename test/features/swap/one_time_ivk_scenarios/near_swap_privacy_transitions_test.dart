// Scenario tests for turning NEAR swap privacy on and off while one-time IVK
// recovery is scheduled: the settings provider's transition, the sync
// notifier's recovery rounds and Rust's switch, through the production
// `NearSwapPrivacyNotifier` and `SyncNotifier` over a fake Rust API. See
// docs/near-swap-receiving.md.
import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/app.dart' show applyEnhancePirPolicy;
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/swap_history_check_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart' as rust_swap;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _account = 'account-1';

/// How many times a poll read the chain tip.
var _tipReads = 0;

/// Rust as the settings toggle and the scheduler see it: ordinary sync streams
/// the test feeds, recovery rounds the test completes, and Rust's NEAR swap
/// privacy switch. Every call is logged in [events].
class _Api extends RustLibApi {
  bool running = false;
  bool swapPrivacy = false;

  /// Whether the wallet has an unfinished history check. Rust reports one only
  /// while the feature is on.
  bool checking = false;
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];
  final rounds = <Completer<bool>>[];
  final manual = <Completer<void>>[];
  final events = <String>[];

  /// Rounds started and not yet finished, and the most at once.
  int open = 0;
  int mostOpen = 0;

  /// Whether a cancellation ends every open round at once, as a stopped worker
  /// does. Off, the test ends them.
  bool drainOnCancel = true;

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

  /// Releases the sync guard, as Rust does once a cancelled sync stops.
  @override
  void crateApiSyncCancelFullSync() => running = false;

  @override
  void crateApiSyncStopMempoolObserver() {}

  @override
  Stream<rust_sync.ApiMempoolTxEvent> crateApiSyncStartMempoolObserver({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
  }) => const Stream.empty();

  /// Starts an ordinary sync whose batches the test adds.
  @override
  Stream<rust_sync.ApiSyncProgressEvent> crateApiSyncStartFullSync({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required int mode,
  }) {
    running = true;
    events.add('sync');
    final controller = StreamController<rust_sync.ApiSyncProgressEvent>();
    syncs.add(controller);
    return controller.stream;
  }

  /// Records the switch the app applies.
  @override
  void crateApiSyncSetNearSwapPrivacyEnabled({required bool enabled}) {
    swapPrivacy = enabled;
    events.add('swap:$enabled');
  }

  /// Starts a round that stays open until the test or a cancellation ends it.
  @override
  Future<bool> crateApiOneTimeIvkRunSwapRecovery({
    required String dbPath,
    required String networkName,
  }) {
    events.add('round');
    final round = Completer<bool>();
    rounds.add(round);
    open++;
    if (open > mostOpen) mostOpen = open;
    return round.future.whenComplete(() => open--);
  }

  /// Starts a held history check round.
  @override
  Future<void> crateApiOneTimeIvkCheckSwapHistory({
    required String dbPath,
    required String networkName,
  }) {
    events.add('check');
    final check = Completer<void>();
    manual.add(check);
    open++;
    if (open > mostOpen) mostOpen = open;
    return check.future.whenComplete(() => open--);
  }

  /// Records a cancellation and, with [drainOnCancel], ends every open round
  /// the way a cancelled worker does.
  @override
  void crateApiOneTimeIvkCancelSwapRecovery() {
    events.add('cancel');
    if (!drainOnCancel) return;
    for (final round in [...rounds, ...manual]) {
      if (!round.isCompleted) {
        round.completeError(
          const rust_swap.ReceiveError(
            message: 'Swap recovery was cancelled.',
            kind: rust_swap.ReceiveErrorKind.other,
          ),
        );
      }
    }
  }

  /// Records a paused history check.
  @override
  Future<void> crateApiOneTimeIvkCancelSwapHistory({
    required String dbPath,
    required String networkName,
  }) async => events.add('pause check');

  @override
  Future<rust_sync.WalletBalance> crateApiSyncGetBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    final zero = BigInt.zero;
    return rust_sync.WalletBalance(
      availability: rust_sync.WalletBalanceAvailability.available,
      transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
      transparentPrivate: false,
      transparent: zero,
      sapling: zero,
      orchard: zero,
      ironwood: zero,
      transparentLocked: zero,
      saplingLocked: zero,
      orchardLocked: zero,
      ironwoodLocked: zero,
      transparentPending: zero,
      saplingPending: zero,
      orchardPending: zero,
      ironwoodPending: zero,
      changePendingConfirmation: zero,
      valuePendingSpendability: zero,
      uneconomicValue: zero,
      spendable: zero,
      locked: zero,
      total: zero,
    );
  }

  @override
  Future<List<rust_sync.TransactionInfo>> crateApiSyncGetTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => const [];

  /// Fails any Rust call this fake does not expect.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The saved NEAR swap privacy preference, in memory.
class _Store implements EnhancePirPreferenceStore {
  _Store(this.value);
  bool? value;
  final writes = <bool>[];

  @override
  Future<bool?> readEnabled() async => value;

  @override
  Future<void> writeEnabled(bool enabled) async {
    writes.add(enabled);
    value = enabled;
  }
}

/// The private queries opt-out marker, never pending in these launches.
class _OptOut implements TransparentOptOutStore {
  @override
  Future<bool> readPending() async => false;

  @override
  Future<void> writePending(bool pending) async {}
}

/// Reconciles the transparent policy as the setting asks, without a wallet.
Future<rust_sync.ApiAppliedTransparentPolicy?> _reconcile(
  bool privateQueries,
) async => rust_sync.ApiAppliedTransparentPolicy(
  mode: privateQueries
      ? rust_sync.ApiTransparentLedgerMode.privateRequired
      : rust_sync.ApiTransparentLedgerMode.public,
  generation: BigInt.one,
);

class _Accounts extends AccountNotifier {
  /// One active software account.
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _account, name: 'Account 1', order: 0)],
    activeAccountUuid: _account,
  );
}

class _Security extends AppSecurityNotifier {
  /// An unlocked wallet.
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _Tip extends RpcEndpointFailoverNotifier {
  /// The default Mainnet endpoint.
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );

  /// The tip the initial state already scanned, counting reads.
  @override
  Future<BigInt> getLatestBlockHeight() async {
    _tipReads++;
    return BigInt.from(100);
  }
}

class _Upgrade extends ChainUpgradeStatusNotifier {
  /// An active chain upgrade.
  @override
  Future<ChainUpgradeStatusState> build() async =>
      ChainUpgradeStatusState.cachedActive(defaultRpcEndpointConfig('main'));

  /// Skips the refresh.
  @override
  Future<void> refreshAtTip(BigInt tipHeight) async {}
}

class _PrivateQueriesOn extends EnhancePirNotifier {
  /// Private queries on, which NEAR swap privacy needs.
  @override
  bool build() => true;
}

class _Sync extends SyncNotifier {
  /// A notifier whose wallet path comes from `path`, so a test can hold a round
  /// while it is starting.
  _Sync(Future<String> Function() path)
    : super(
        walletDbPathResolver: path,
        excludeCompanionsFromBackup: (_) async {},
      );

  /// A completed sync at height 100.
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _account,
    hasAccountScopedData: true,
    isSyncComplete: true,
    scannedHeight: 100,
    chainTipHeight: 100,
  );
}

/// One sync batch that scanned through `height`.
rust_sync.ApiSyncProgressEvent _scanned(int height) =>
    rust_sync.ApiSyncProgressEvent(
      kind: rust_sync.ApiSyncEventKind.progress,
      scannedHeight: BigInt.from(height),
      chainTipHeight: BigInt.from(height),
      percentage: 1,
      displayTargetPercentage: 1,
      displayTargetBlocks: BigInt.zero,
      isSyncing: true,
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
    api
      ..running = false
      ..swapPrivacy = false
      ..checking = false
      ..open = 0
      ..mostOpen = 0
      ..drainOnCancel = true;
    _tipReads = 0;
    api.syncs.clear();
    api.rounds.clear();
    api.manual.clear();
    api.events.clear();
  });

  /// A running app with the saved setting `saved`, whose wallet path takes
  /// `path`. Startup applies the saved switch to Rust, as `app.dart` does, and
  /// sync is started and stopped so its batches are fed by hand.
  Future<(ProviderContainer, _Sync, _Store)> app(
    bool saved, {
    Future<String> Function()? path,
    _Store? store,
    bool launch = false,
  }) async {
    final sync = _Sync(path ?? () async => 'wallet.db');
    final preference = store ?? _Store(saved);
    // A launch reads the saved setting from its production store, as startup
    // does, and starts from a process that has not applied it yet.
    if (launch) api.swapPrivacy = false;
    final savedSwapPrivacy = launch
        ? await readNearSwapPrivacyPreference()
        : preference.value ?? false;
    final bootstrap = AppBootstrapState(
      initialLocation: '/settings',
      initialAccountState: const AccountState(
        accounts: [AccountInfo(uuid: _account, name: 'Account 1', order: 0)],
        activeAccountUuid: _account,
      ),
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      themeMode: ThemeMode.system,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
      enhancePirEnabled: true,
      nearSwapPrivacyEnabled: savedSwapPrivacy,
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(bootstrap),
        accountProvider.overrideWith(_Accounts.new),
        appSecurityProvider.overrideWith(_Security.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_PrivateQueriesOn.new),
        if (!launch)
          nearSwapPrivacyPreferenceStoreProvider.overrideWithValue(preference),
        swapRecoveryReconcilerProvider.overrideWithValue(() async {
          api.events.add('reconcile:${api.swapPrivacy}');
        }),
        syncProvider.overrideWith(() => sync),
        // The wallet's saved state, which the check reads to follow the job.
        swapRecoveryStatusReaderProvider.overrideWithValue(
          () async => rust_swap.SwapRecoveryStatus(
            checkingHistory: api.checking && api.swapPrivacy,
            manualCheckActive: api.checking && api.swapPrivacy,
            upgradeRequired: false,
          ),
        ),
        // The production calls behind Check swap history, polled quickly.
        swapHistoryApiProvider.overrideWith(
          (ref) => SwapHistoryApi(
            begin: () => ref.read(syncProvider.notifier).checkSwapHistory(),
            cancel: () => ref.read(syncProvider.notifier).cancelSwapHistory(),
            status: () async => rust_swap.SwapRecoveryStatus(
              checkingHistory: api.checking && api.swapPrivacy,
              manualCheckActive: api.checking && api.swapPrivacy,
              upgradeRequired: false,
            ),
            pollInterval: const Duration(milliseconds: 1),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(swapHistoryCheckProvider, (_, _) {});
    container.listen(syncProvider, (_, _) {});
    container.listen(nearSwapPrivacyProvider, (_, _) {});
    if (launch) {
      // The production startup policy, which applies the saved setting to Rust.
      await applyEnhancePirPolicy(
        bootstrap,
        setRustEnabled: (_) {},
        setPreferenceConfirmed: (_) {},
        reconcileTransparentPolicy: _reconcile,
        readTransparentPolicy: () async => null,
        optOutStore: _OptOut(),
        setNativePrivateRecovery: (_) async {},
        prepareCompanions: () async {},
      );
    } else {
      rust_sync.setNearSwapPrivacyEnabled(
        enabled: container.read(nearSwapPrivacyProvider),
      );
    }
    await container.read(syncProvider.future);
    sync.stopTipChecksForTesting();
    sync.startSync();
    await pumpEventQueue();
    api.events.clear();
    return (container, sync, preference);
  }

  /// Feeds the newest sync a batch through `height` and returns how many rounds
  /// have started.
  Future<int> batch(_Sync sync, int height) async {
    api.syncs.last.add(_scanned(height));
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    return api.rounds.length;
  }

  /// Ends the newest round, reporting whether the wallet had work.
  Future<void> finish({bool work = true}) async {
    api.rounds.last.complete(work);
    await pumpEventQueue();
  }

  /// Stops sync before the container goes.
  Future<void> settle(_Sync sync) async {
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    sync.stopSync();
    await pumpEventQueue();
  }

  /// Waits in real time, for at most five seconds, until `done` holds, and
  /// fails with `what` if it never does. Unlike a fixed delay, this does not
  /// depend on how soon a loaded machine runs the history check's 1 ms poll.
  Future<void> until(bool Function() done, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (!DateTime.now().isBefore(deadline)) fail('Timed out waiting: $what');
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Off to on with work pending: an idle wallet with the setting off starts no
  /// round per batch. Turning it on saves the setting, applies it to Rust, then
  /// reconciles the wallet, and the next batch starts a round with no manual
  /// step. Rounds then follow every batch.
  test('turning on resumes rounds on the next batch', () async {
    final (container, sync, store) = await app(false);
    expect(await batch(sync, 101), 1, reason: 'the first batch asks Rust');
    await finish(work: false);
    expect(await batch(sync, 102), 1, reason: 'off and idle');

    await container.read(nearSwapPrivacyProvider.notifier).set(true);
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(store.value, isTrue);
    expect(
      api.events.where(
        (e) => e.startsWith('swap:') || e.startsWith('reconcile'),
      ),
      ['swap:true', 'reconcile:true'],
    );
    expect(container.read(enhancePirTransitionProvider), isNull);
    final before = api.rounds.length;
    expect(await batch(sync, 103), before + 1, reason: 'on: the batch asks');
    await finish();
    expect(await batch(sync, 104), before + 2, reason: 'and the next one');
    await finish(work: false);
    await settle(sync);
  });

  /// On to off mid-round: the toggle cancels the open round and waits for it to
  /// end before it saves or applies anything. Afterwards the setting is off in
  /// the store, in Rust and in the wallet, and once Rust reports no work no
  /// batch or poll starts a round.
  test('turning off mid-round drains it first, then the wallet idles', () async {
    final (container, sync, store) = await app(true);
    expect(await batch(sync, 101), 1);
    api.drainOnCancel = false;
    final off = container.read(nearSwapPrivacyProvider.notifier).set(false);
    await pumpEventQueue();
    expect(api.events, contains('cancel'));
    expect(store.writes, isEmpty, reason: 'waits for the round to end');
    expect(api.swapPrivacy, isTrue);

    api.rounds.last.completeError(
      const rust_swap.ReceiveError(
        message: 'Swap recovery was cancelled.',
        kind: rust_swap.ReceiveErrorKind.other,
      ),
    );
    await off;
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(store.value, isFalse);
    expect(container.read(nearSwapPrivacyProvider), isFalse);
    final order = api.events
        .where(
          (e) =>
              e == 'cancel' ||
              e.startsWith('swap:') ||
              e.startsWith('reconcile'),
        )
        .toList();
    expect(order, ['cancel', 'swap:false', 'reconcile:false']);

    // The toggle restarted sync. Its first batch asks Rust once, which reports
    // no work, and then nothing more starts.
    final asked = await batch(sync, 102);
    await finish(work: false);
    for (final height in [103, 104, 105]) {
      expect(await batch(sync, height), asked, reason: 'inert at $height');
    }
    // With that sync finished, an idle poll reads the tip and starts nothing.
    api.running = false;
    await api.syncs.last.close();
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    final rounds = api.rounds.length;
    final reads = _tipReads;
    await sync.checkTipForTesting();
    sync.stopTipChecksForTesting();
    expect(_tipReads, reads + 1, reason: 'the poll ran');
    expect(api.rounds.length, rounds, reason: 'an idle poll starts nothing');
    await settle(sync);
  });

  /// On, off, on: each change goes to the store, then Rust, then the wallet,
  /// and rounds stop and resume with it.
  test('on, off and on again apply each setting in order', () async {
    final (container, sync, store) = await app(true);
    final notifier = container.read(nearSwapPrivacyProvider.notifier);
    for (final on in [false, true, false, true]) {
      await notifier.set(on);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      expect(container.read(nearSwapPrivacyProvider), on);
      expect(store.value, on);
      expect(api.swapPrivacy, on);
      expect(
        api.events.lastWhere((e) => e.startsWith('reconcile')),
        'reconcile:$on',
      );
      final asked = await batch(sync, 100 + api.syncs.length);
      if (api.rounds.isNotEmpty && !api.rounds.last.isCompleted) {
        await finish(work: false);
      }
      final next = await batch(sync, 200 + api.syncs.length);
      expect(next > asked, on, reason: 'on $on: rounds follow batches');
      if (api.rounds.isNotEmpty && !api.rounds.last.isCompleted) {
        await finish(work: false);
      }
    }
    expect(store.writes, [false, true, false, true]);
    expect(api.mostOpen, 1, reason: 'one round at a time');
    await settle(sync);
  });

  /// The setting survives a restart in both directions. Each launch reads the
  /// saved value from its production store and applies it to a fresh Rust
  /// through the production startup policy, and reconciles nothing until a
  /// round does. With the setting off, the first batch after the restart still
  /// asks Rust once, since the wallet may still say on or hold repair work, and
  /// an idle answer then stops the rounds.
  test('a restart keeps the saved setting either way', () async {
    SharedPreferences.setMockInitialValues({});
    await const SharedPreferencesEnhancePirStore(
      key: kNearSwapPrivacyPreferenceKey,
    ).writeEnabled(true);
    var (container, sync, _) = await app(true, launch: true);
    expect(container.read(nearSwapPrivacyProvider), isTrue);
    expect(api.swapPrivacy, isTrue, reason: 'startup applied the saved on');
    await container.read(nearSwapPrivacyProvider.notifier).set(false);
    await settle(sync);
    container.dispose();

    (container, sync, _) = await app(false, launch: true);
    expect(container.read(nearSwapPrivacyProvider), isFalse);
    expect(api.swapPrivacy, isFalse);
    expect(api.events.where((e) => e.startsWith('reconcile')), isEmpty);
    expect(await batch(sync, 101), 1, reason: 'the first round reconciles');
    await finish(work: false);
    expect(await batch(sync, 102), 1, reason: 'then the wallet idles');
    await container.read(nearSwapPrivacyProvider.notifier).set(true);
    await settle(sync);
    container.dispose();

    api.rounds.clear();
    (container, sync, _) = await app(true, launch: true);
    expect(container.read(nearSwapPrivacyProvider), isTrue);
    expect(api.swapPrivacy, isTrue, reason: 'startup applied the saved on');
    expect(await batch(sync, 101), 1);
    await finish(work: false);
    expect(await batch(sync, 102), 2, reason: 'on: rounds follow batches');
    await finish(work: false);
    await settle(sync);
  });

  /// Rapid toggling: a second and third tap while a change is still applying
  /// are dropped rather than queued or interleaved, and quick taps that each
  /// wait for the last end on the last setting. Rounds never overlap, every
  /// change leaves no transition message behind, and the store, Rust and the
  /// last reconcile always agree.
  test(
    'rapid toggles never overlap rounds and end on the last setting',
    () async {
      final (container, sync, store) = await app(false);
      final notifier = container.read(nearSwapPrivacyProvider.notifier);
      expect(await batch(sync, 101), 1);
      final first = notifier.set(true);
      final second = notifier.set(false);
      final third = notifier.set(true);
      await Future.wait([first, second, third]);
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      expect(store.writes, [
        true,
      ], reason: 'taps during the change are dropped');
      expect(container.read(nearSwapPrivacyProvider), isTrue);

      for (var i = 0; i < 6; i++) {
        await notifier.toggle();
        await batch(sync, 110 + i);
      }
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      final on = container.read(nearSwapPrivacyProvider);
      expect(on, isTrue, reason: 'six flips from on');
      expect(store.value, on);
      expect(api.swapPrivacy, on);
      expect(
        api.events.lastWhere((e) => e.startsWith('reconcile')),
        'reconcile:$on',
      );
      expect(container.read(enhancePirTransitionProvider), isNull);
      expect(api.mostOpen, 1, reason: 'rounds never overlap');
      for (final round in api.rounds.where((r) => !r.isCompleted)) {
        round.complete(false);
      }
      await settle(sync);
    },
  );

  /// A toggle while a round is still starting, before it reached Rust, cancels
  /// that round: once its wallet path resolves it does not run, and only a
  /// round started after the change reaches Rust.
  test('a toggle while a round is starting drops that round', () async {
    Completer<String>? held;
    final (container, sync, _) = await app(
      true,
      path: () => held?.future ?? Future.value('wallet.db'),
    );
    held = Completer<String>();
    sync.clearCachedWalletDbPath();
    api.syncs.last.add(_scanned(101));
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(api.rounds, isEmpty, reason: 'the round is resolving its path');

    final off = container.read(nearSwapPrivacyProvider.notifier).set(false);
    await pumpEventQueue();
    final starting = held;
    held = null;
    starting.complete('wallet.db');
    await off;
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(api.rounds, isEmpty, reason: 'the stale round never ran');
    expect(api.events, containsAllInOrder(['cancel', 'swap:false']));
    expect(await batch(sync, 102), 1, reason: 'a later batch asks Rust');
    await finish(work: false);
    await settle(sync);
  });

  /// Turning the setting off while Check swap history is starting cancels its
  /// round, and the check ends paused, not failed or done. The wallet keeps the
  /// saved job, so turning the setting back on watches it again until the
  /// wallet reports it done.
  test('turning off while a history check starts ends it paused', () async {
    final (container, sync, _) = await app(true);
    final history = container.read(swapHistoryCheckProvider.notifier);
    api.checking = true;
    final running = history.check();
    await pumpEventQueue();
    expect(api.manual, hasLength(1), reason: 'the check round is held');
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.checking);

    await container.read(nearSwapPrivacyProvider.notifier).set(false);
    await running;
    expect(api.manual.single.isCompleted, isTrue, reason: 'its round drained');
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);

    await container.read(nearSwapPrivacyProvider.notifier).set(true);
    await until(
      () => container.read(swapHistoryCheckProvider) != SwapHistoryCheck.paused,
      'the check leaves paused',
    );
    expect(
      container.read(swapHistoryCheckProvider),
      SwapHistoryCheck.checking,
      reason: 'the saved job is watched again',
    );
    expect(api.manual, hasLength(1), reason: 'no new check was started');
    api.checking = false;
    await until(
      () =>
          container.read(swapHistoryCheckProvider) != SwapHistoryCheck.checking,
      'the watched check ends',
    );
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
    for (final round in api.rounds.where((r) => !r.isCompleted)) {
      round.complete(false);
    }
    await settle(sync);
  });

  /// Turning the setting off while a running check polls for completion ends
  /// it paused, although the wallet then reports no unfinished check, and the
  /// check drives no more rounds while the setting stays off. Turning it back
  /// on watches the saved job again until the wallet reports it done.
  test('turning off while a history check polls ends it paused', () async {
    final (container, sync, _) = await app(true);
    final history = container.read(swapHistoryCheckProvider.notifier);
    api.checking = true;
    final running = history.check();
    await pumpEventQueue();
    api.manual.single.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.checking);

    await container.read(nearSwapPrivacyProvider.notifier).set(false);
    await running;
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.paused);
    final rounds = api.rounds.length;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.rounds.length, rounds, reason: 'the check stopped polling');

    // Back on, the saved job is watched again until the wallet finishes it.
    await container.read(nearSwapPrivacyProvider.notifier).set(true);
    await until(
      () => container.read(swapHistoryCheckProvider) != SwapHistoryCheck.paused,
      'the check leaves paused',
    );
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.checking);
    expect(api.manual, hasLength(1), reason: 'no new check was started');
    api.checking = false;
    await until(
      () =>
          container.read(swapHistoryCheckProvider) != SwapHistoryCheck.checking,
      'the watched check ends',
    );
    expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
    for (final round in api.rounds.where((r) => !r.isCompleted)) {
      round.complete(false);
    }
    await settle(sync);
  });
}
