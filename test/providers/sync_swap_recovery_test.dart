import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_process_work_policy.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/swap_history_check_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_pir_server_provider.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart' as rust_swap;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _first = 'account-1';
const _second = 'account-2';

/// The time the notifier's swap recovery deadlines read.
var _clock = DateTime(2026);

/// A round that committed results the wallet shows.
final _changed = rust_swap.SwapRecoveryRound(
  changed: true,
  checked: true,
  more: false,
  rescan: false,
);

/// A round that reached a compatible service and found nothing new.
final _quiet = rust_swap.SwapRecoveryRound(
  changed: false,
  checked: true,
  more: false,
  rescan: false,
);

/// A round that contacted no service and left nothing to do.
final _idle = rust_swap.SwapRecoveryRound(
  changed: false,
  checked: false,
  more: false,
  rescan: false,
);

/// A round that ran out of time with work left it can run right away.
final _more = rust_swap.SwapRecoveryRound(
  changed: true,
  checked: true,
  more: true,
  rescan: false,
);

/// A round whose remaining work waits for `wait`.
rust_swap.SwapRecoveryRound _waiting(rust_swap.SwapRecoveryWait wait) =>
    rust_swap.SwapRecoveryRound(
      changed: false,
      checked: wait != rust_swap.SwapRecoveryWait.server,
      more: false,
      rescan: false,
      wait: wait,
    );

/// The wallet's recovery work with a round due.
final _due = rust_swap.SwapRecoveryStatus(
  roundDue: true,
  awaitingAdmission: false,
  checkingHistory: false,
  manualCheckActive: false,
  upgradeRequired: false,
);

/// The wallet's recovery work with nothing due.
final _settled = rust_swap.SwapRecoveryStatus(
  roundDue: false,
  awaitingAdmission: false,
  checkingHistory: false,
  manualCheckActive: false,
  upgradeRequired: false,
);

/// An account with nothing holding back issuance.
const _ready = rust_swap.SwapAccountReadiness(
  seedWalk: false,
  lookups: false,
  awaitingAdmission: false,
);

/// An account whose found payment waits for sync to admit it.
const _admitting = rust_swap.SwapAccountReadiness(
  seedWalk: false,
  lookups: false,
  awaitingAdmission: true,
);

/// An account whose queued lookups hold back issuance.
const _busy = rust_swap.SwapAccountReadiness(
  seedWalk: false,
  lookups: true,
  awaitingAdmission: false,
);

/// A receiver outage.
const _outage = rust_swap.ReceiveError(
  message: 'HTTP 503',
  kind: rust_swap.ReceiveErrorKind.other,
);

/// Rust as the scheduler sees it: ordinary sync streams that the test drives
/// block by block, and receiver recovery rounds that the test holds and
/// releases explicitly. Nothing here sleeps; every wait is a completer.
class _Api extends RustLibApi {
  bool running = false;
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];
  final recoveries = <Completer<rust_swap.SwapRecoveryRound>>[];
  final manual = <Completer<rust_swap.SwapRecoveryRound>>[];
  final steps = <Completer<rust_swap.SwapFilterStep>>[];

  /// Whether filter steps wait for the test, instead of ending at once with
  /// nothing left for a round.
  bool holdSteps = false;
  final statusReads = <Completer<rust_swap.SwapRecoveryStatus>>[];
  final events = <String>[];
  final balanceReads = <String>[];
  final readinessReads = <String>[];
  final activeAccounts = <String?>[];
  final appliedServers = <String?>[];
  int cancels = 0;

  /// What the next readiness read reports for any account.
  rust_swap.SwapAccountReadiness readiness = _ready;

  /// The newest automatic round, which the test completes with what it did to
  /// release it.
  Completer<rust_swap.SwapRecoveryRound> get round => recoveries.last;

  /// Whether this fake's ordinary sync still holds the Rust guard.
  @override
  bool crateApiSyncIsSyncRunning() => running;

  /// Reports no pending cancellation, so stops complete at once.
  @override
  bool crateApiSyncIsSyncCancelRequested() => false;

  /// Reports no mempool observer, which these tests never start.
  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  /// Records the active account Rust would order work by.
  @override
  void crateApiSyncSetActiveSyncAccount({String? accountUuid}) {
    activeAccounts.add(accountUuid);
    events.add('active $accountUuid');
  }

  /// Reports [readiness] for `accountUuid` and records which account was read.
  @override
  Future<rust_swap.SwapAccountReadiness>
  crateApiOneTimeIvkGetSwapAccountReadiness({
    required String dbPath,
    required String networkName,
    required String accountUuid,
  }) async {
    readinessReads.add(accountUuid);
    return readiness;
  }

  /// No server is selected before the test chooses one.
  @override
  String? crateApiPirConfigSelectedWalletPirServer() =>
      appliedServers.isEmpty ? null : appliedServers.last;

  /// Accepts the NEAR swap privacy setting.
  @override
  void crateApiSyncSetNearSwapPrivacyEnabled({required bool enabled}) {}

  /// Records the chosen server.
  @override
  Future<bool> crateApiPirConfigApplyWalletPirServer({String? baseUrl}) async {
    appliedServers.add(baseUrl);
    return true;
  }

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

  /// Fails as Rust's single admission does while a round, manual check or
  /// filter step is in flight.
  void admit() {
    if ([...recoveries, ...manual, ...steps].any((c) => !c.isCompleted)) {
      throw StateError('Swap recovery is already running.');
    }
  }

  /// Starts a filter step, which ends at once unless [holdSteps].
  @override
  Future<rust_swap.SwapFilterStep> crateApiOneTimeIvkRunSwapFilterStep({
    required String dbPath,
    required String networkName,
  }) async {
    admit();
    events.add('step');
    final step = Completer<rust_swap.SwapFilterStep>();
    steps.add(step);
    if (!holdSteps) {
      step.complete(const rust_swap.SwapFilterStep(needsRound: false));
    }
    return step.future;
  }

  /// Starts a receiver round that stays pending until the test completes it.
  @override
  Future<rust_swap.SwapRecoveryRound> crateApiOneTimeIvkRunSwapRecovery({
    required String dbPath,
    required String networkName,
  }) async {
    admit();
    events.add('recover');
    final round = Completer<rust_swap.SwapRecoveryRound>();
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
  Future<rust_swap.SwapRecoveryRound> crateApiOneTimeIvkCheckSwapHistory({
    required String dbPath,
    required String networkName,
  }) async {
    admit();
    events.add('manual');
    final check = Completer<rust_swap.SwapRecoveryRound>();
    manual.add(check);
    return check.future;
  }

  /// What the wallet's recovery work read reports.
  var work = _settled;

  /// When set, the next status read waits for the test to complete it.
  Completer<rust_swap.SwapRecoveryStatus>? heldWork;

  /// Whether status reads wait in [statusReads] for the test to complete them.
  bool holdStatus = false;

  /// Reports [work], or what the test completes [heldWork] with. With
  /// [holdStatus], the read waits in [statusReads] instead.
  @override
  Future<rust_swap.SwapRecoveryStatus> crateApiOneTimeIvkGetSwapRecoveryStatus({
    required String dbPath,
    required String networkName,
  }) async {
    if (holdStatus) {
      final read = Completer<rust_swap.SwapRecoveryStatus>();
      statusReads.add(read);
      return read.future;
    }
    events.add('work');
    final held = heldWork;
    heldWork = null;
    return held == null ? work : held.future;
  }

  /// When set, the durable pause stays pending until the test completes it.
  Completer<void>? heldCancel;

  /// When set, the durable pause write fails with this error.
  Object? cancelFailure;

  /// Records that the durable manual job was paused.
  @override
  Future<void> crateApiOneTimeIvkCancelSwapHistory({
    required String dbPath,
    required String networkName,
  }) async {
    events.add('cancel manual');
    await heldCancel?.future;
    final failure = cancelFailure;
    if (failure != null) throw failure;
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
  _Account({this.empty = false});

  /// Whether the wallet starts with no accounts, as before onboarding.
  final bool empty;

  /// Two accounts with the first active, unless [empty].
  @override
  AccountState build() => empty ? const AccountState() : _accounts;

  static const _accounts = AccountState(
    accounts: [
      AccountInfo(uuid: _first, name: 'Account 1', order: 0),
      AccountInfo(uuid: _second, name: 'Account 2', order: 1),
    ],
    activeAccountUuid: _first,
  );

  /// Creates the two accounts, as onboarding does for the first.
  void create() => state = const AsyncData(_accounts);

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

  /// Reports the chain tip the initial state already scanned.
  @override
  Future<BigInt> getLatestBlockHeight() async => BigInt.from(100);
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
        now: () => _clock,
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
    api.steps.clear();
    api.holdSteps = false;
    api.statusReads.clear();
    api.holdStatus = false;
    api.heldCancel = null;
    api.cancelFailure = null;
    api.events.clear();
    api.balanceReads.clear();
    api.readinessReads.clear();
    api.activeAccounts.clear();
    api.appliedServers.clear();
    api.readiness = _ready;
    api.work = _settled;
    api.heldWork = null;
    api.cancels = 0;
    _clock = DateTime(2026);
  });

  late ProviderContainer container;

  /// A notifier built with two accounts, the first active, whose state is a
  /// completed sync at height 100, launched as a cold start does: its first
  /// sync runs and the home refresh has started. NEAR swap privacy is off
  /// unless `privacy`. `overrides` add to the container's.
  Future<_Sync> start({
    bool privacy = false,
    List<Override> overrides = const [],
    bool empty = false,
  }) async {
    final sync = _Sync();
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(() => _Account(empty: empty)),
        appSecurityProvider.overrideWith(_Security.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        if (privacy) nearSwapPrivacyProvider.overrideWith(_PrivacyOn.new),
        syncProvider.overrideWith(() => sync),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    if (!empty) {
      sync.startSync();
      sync.refreshHomeInBackground();
    }
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    return sync;
  }

  /// Ends the sync at `index` at `height`, so the wallet is at the tip.
  Future<void> complete(_Sync sync, int index, {int height = 101}) async {
    api.syncs[index].add(
      _scanned(height, kind: rust_sync.ApiSyncEventKind.completed),
    );
    await pumpEventQueue();
    await api.finish(index);
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
  }

  /// Releases the held round, as Rust does once it stops, reporting what it
  /// did.
  Future<void> releaseRound([rust_swap.SwapRecoveryRound? round]) async {
    api.round.complete(round ?? _changed);
    await pumpEventQueue();
  }

  /// Fails the held round with a receiver outage.
  Future<void> failRound() async {
    api.round.completeError(_outage);
    await pumpEventQueue();
  }

  /// A notifier past its cold start: the first sync completed and the round
  /// launch owed has run quietly, so nothing is owed. `start` arguments pass
  /// through.
  Future<_Sync> atTip({
    bool privacy = false,
    List<Override> overrides = const [],
  }) async {
    final sync = await start(privacy: privacy, overrides: overrides);
    expect(api.syncs, hasLength(1), reason: 'launch starts a sync');
    expect(api.recoveries, isEmpty, reason: 'its round waits for the tip');
    await complete(sync, 0);
    expect(api.recoveries, hasLength(1), reason: 'launch owed one round');
    await releaseRound(_quiet);
    // The round's answer starts the update request's saved-state read, which
    // wallet changes wait for.
    for (final read in api.statusReads) {
      read.complete(
        const rust_swap.SwapRecoveryStatus(
          roundDue: false,
          awaitingAdmission: false,
          checkingHistory: false,
          manualCheckActive: false,
          upgradeRequired: false,
        ),
      );
    }
    await pumpEventQueue();
    api.statusReads.clear();
    return sync;
  }

  /// A notifier past its cold start whose second ordinary sync has scanned
  /// block 102 while a forced receiver round the test holds runs beside it.
  Future<_Sync> recovering({
    bool privacy = false,
    List<Override> overrides = const [],
  }) async {
    final sync = await atTip(privacy: privacy, overrides: overrides);
    sync.continueSwapRecovery();
    await pumpEventQueue();
    expect(api.recoveries, hasLength(2));
    sync.startSync();
    await pumpEventQueue();
    api.syncs[1].add(_scanned(102));
    await pumpEventQueue();
    expect(api.syncs, hasLength(2));
    return sync;
  }

  /// Lets queued sync work finish, then stops it before the container goes.
  Future<void> settle(_Sync sync) async {
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    sync.stopSync();
    await pumpEventQueue();
  }

  /// Runs one tip check, which finds the wallet at the tip, and reports
  /// whether it started a round.
  Future<bool> pollStartsRound(_Sync sync) async {
    final rounds = api.recoveries.length;
    await sync.checkTipForTesting();
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    return api.recoveries.length > rounds;
  }

  /// Runs one more ordinary sync to completion, a block past the last.
  Future<void> syncOnce(_Sync sync) async {
    final height = sync.state.requireValue.scannedHeight + 1;
    sync.startSync(latestTipHeight: height);
    await pumpEventQueue();
    await complete(sync, api.syncs.length - 1, height: height);
  }

  /// Makes `uuid` the active account as the account listener does: Rust's
  /// priority first, then the notifier's account-scoped state.
  Future<void> switchTo(_Sync sync, String uuid) async {
    (container.read(accountProvider.notifier) as _Account).activate(uuid);
    rust_sync.setActiveSyncAccount(accountUuid: uuid);
    sync.handleAccountSwitchForTesting(uuid);
    await pumpEventQueue();
  }

  group('when rounds run', () {
    test('a bare poll and a completed sync start no round when none is '
        'owed', () async {
      final sync = await atTip();
      expect(await pollStartsRound(sync), isFalse);
      sync.startSync(latestTipHeight: 102);
      await pumpEventQueue();
      await complete(sync, 1, height: 102);
      expect(api.recoveries, hasLength(1));
      expect(await pollStartsRound(sync), isFalse);
      await settle(sync);
    });

    test('a cold start owes one round, which runs once the first sync '
        'completes, not on its batches', () async {
      final sync = await start();
      expect(api.syncs, hasLength(1));
      api.syncs[0].add(_scanned(101));
      await pumpEventQueue();
      expect(api.recoveries, isEmpty);
      await complete(sync, 0);
      expect(api.recoveries, hasLength(1));
      await releaseRound(_quiet);
      expect(await pollStartsRound(sync), isFalse, reason: 'it was served');
      await settle(sync);
    });

    test('unlocking owes one round, which runs after the sync it starts '
        'completes', () async {
      final sync = await atTip();
      final security =
          container.read(appSecurityProvider.notifier) as _Security;
      security.setUnlocked(false);
      await sync.clearSensitiveStateForLock();
      security.setUnlocked(true);
      await sync.refreshAfterUnlock();
      sync.startSync();
      sync.refreshHomeInBackground();
      await pumpEventQueue();
      expect(api.recoveries, hasLength(1));
      await complete(sync, 1);
      expect(api.recoveries, hasLength(2));
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('returning to the app owes one round, which the tip check starts '
        'at the tip', () async {
      final sync = await atTip();
      sync.handleAppResumeForTesting();
      await pumpEventQueue();
      sync.stopTipChecksForTesting();
      expect(api.recoveries, hasLength(2));
      await releaseRound(_quiet);
      expect(await pollStartsRound(sync), isFalse);
      await settle(sync);
    });

    test('an account switch owes a round, and cancels a running one so it '
        'restarts with the new account first', () async {
      final sync = await atTip();
      await switchTo(sync, _second);
      expect(api.activeAccounts.last, _second);
      expect(api.recoveries, hasLength(2), reason: 'at the tip it runs now');
      expect(api.cancels, 0);

      await switchTo(sync, _first);
      expect(api.cancels, 1, reason: 'the running round restarts');
      expect(api.recoveries, hasLength(2), reason: 'once it has stopped');
      api.round.completeError('Swap recovery was cancelled.');
      await pumpEventQueue();
      expect(api.recoveries, hasLength(3));
      expect(
        api.events.lastIndexOf('active $_first'),
        lessThan(api.events.lastIndexOf('recover')),
        reason: 'Rust orders it by the new account',
      );
      await releaseRound(_quiet);
      expect(await pollStartsRound(sync), isFalse);
      await settle(sync);
    });

    test('choosing a private query server owes one round, which runs after '
        'the sync it restarts completes', () async {
      final sync = await atTip();
      await container.read(walletPirServerApplierProvider)(
        'https://pir.example',
      );
      await pumpEventQueue();
      expect(api.appliedServers, ['https://pir.example']);
      expect(api.recoveries, hasLength(1));
      expect(api.syncs, hasLength(2), reason: 'the change restarts sync');
      await complete(sync, 1);
      expect(api.recoveries, hasLength(2));
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('a requested round, as a NEAR payout or refund owes, runs at once '
        'at the tip', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      expect(api.recoveries, hasLength(2));
      await releaseRound(_quiet);
      expect(await pollStartsRound(sync), isFalse);
      await settle(sync);
    });

    for (final wait in [
      rust_swap.SwapRecoveryWait.publication,
      rust_swap.SwapRecoveryWait.sync_,
    ]) {
      test('a round waiting on ${wait.name} stays owed: a bare poll leaves it, '
          'and the next completed sync runs it', () async {
        final sync = await atTip();
        sync.requestSwapRecovery();
        await pumpEventQueue();
        await releaseRound(_waiting(wait));
        expect(await pollStartsRound(sync), isFalse);

        sync.startSync(latestTipHeight: 102);
        await pumpEventQueue();
        await complete(sync, 1, height: 102);
        expect(api.recoveries, hasLength(3));
        await releaseRound(_quiet);
        expect(
          await pollStartsRound(sync),
          isFalse,
          reason: 'now it was served',
        );
        await settle(sync);
      });
    }

    test(
      'a round that finishes does not clear work owed after it started',
      () async {
        final sync = await atTip();
        sync.requestSwapRecovery();
        await pumpEventQueue();
        expect(api.recoveries, hasLength(2));
        sync.requestSwapRecovery();
        await pumpEventQueue();
        expect(api.recoveries, hasLength(2), reason: 'one round at a time');
        await releaseRound(_quiet);
        expect(api.recoveries, hasLength(3), reason: 'the later request');
        await releaseRound(_quiet);
        expect(await pollStartsRound(sync), isFalse);
        await settle(sync);
      },
    );

    test('a sync that completes while a round runs is not lost when that '
        'round waits for sync', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      expect(api.recoveries, hasLength(2));
      sync.startSync(latestTipHeight: 102);
      await pumpEventQueue();
      await complete(sync, 1, height: 102);
      expect(api.recoveries, hasLength(2), reason: 'one round at a time');
      await releaseRound(_waiting(rust_swap.SwapRecoveryWait.sync_));
      expect(api.recoveries, hasLength(3), reason: 'it runs again at once');
      await releaseRound(_quiet);
      expect(await pollStartsRound(sync), isFalse);
      await settle(sync);
    });

    test(
      'a wait for a newer publication retries after a bounded delay with '
      'the tip unchanged, and one for a server when a server is chosen',
      () async {
        final sync = await atTip();
        sync.requestSwapRecovery();
        await pumpEventQueue();
        await releaseRound(_waiting(rust_swap.SwapRecoveryWait.publication));
        _clock = _clock.add(const Duration(seconds: 9));
        expect(await pollStartsRound(sync), isFalse);
        _clock = _clock.add(const Duration(seconds: 1));
        expect(
          await pollStartsRound(sync),
          isTrue,
          reason: 'the receiver may have caught up without a new block',
        );
        await releaseRound(_waiting(rust_swap.SwapRecoveryWait.server));
        expect(await pollStartsRound(sync), isFalse);
        sync.requestSwapRecovery();
        await pumpEventQueue();
        expect(api.recoveries, hasLength(4), reason: 'a server was chosen');
        await releaseRound(_quiet);
        await settle(sync);
      },
    );

    test('a round that queued a rescan starts sync, and runs again once it '
        'completes', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      await releaseRound(
        rust_swap.SwapRecoveryRound(
          changed: false,
          checked: true,
          more: false,
          wait: rust_swap.SwapRecoveryWait.sync_,
          rescan: true,
        ),
      );
      expect(api.syncs, hasLength(2), reason: 'sync started at once');
      expect(api.recoveries, hasLength(2));
      await complete(sync, 1);
      expect(api.recoveries, hasLength(3));
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('a history poll during the last round joins it, while a new request '
        'then still owes another', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      sync.pollSwapRecovery();
      await releaseRound(_quiet);
      expect(api.recoveries, hasLength(2), reason: 'no trailing round');

      sync.requestSwapRecovery();
      await pumpEventQueue();
      sync.requestSwapRecovery();
      await releaseRound(_quiet);
      expect(api.recoveries, hasLength(4), reason: 'the later request');
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('onboarding the first account owes a round', () async {
      final sync = await start(empty: true);
      expect(api.syncs, isEmpty);
      (container.read(accountProvider.notifier) as _Account).create();
      rust_sync.setActiveSyncAccount(accountUuid: _first);
      sync.handleAccountSwitchForTesting(_first);
      await pumpEventQueue();
      expect(api.recoveries, hasLength(1), reason: 'the new account owes one');
      await releaseRound(_quiet);
      await settle(sync);
    });

    test(
      'a sync after which the wallet reports a round due owes one round',
      () async {
        final sync = await atTip();
        sync.startSync(latestTipHeight: 102);
        await pumpEventQueue();
        await complete(sync, 1, height: 102);
        expect(api.recoveries, hasLength(1), reason: 'nothing is due');

        // Sync learned a refund funding memo, say.
        api.work = _due;
        sync.startSync(latestTipHeight: 103);
        await pumpEventQueue();
        await complete(sync, 2, height: 103);
        expect(api.recoveries, hasLength(2));
        api.work = _settled;
        await releaseRound(_quiet);
        sync.startSync(latestTipHeight: 104);
        await pumpEventQueue();
        await complete(sync, 3, height: 104);
        expect(api.recoveries, hasLength(2), reason: 'the round settled it');
        await settle(sync);
      },
    );

    test(
      'a due work read that lands after a round ended still owes a round',
      () async {
        final sync = await atTip();
        final read = Completer<rust_swap.SwapRecoveryStatus>();
        api.heldWork = read;
        sync.startSync(latestTipHeight: 102);
        await pumpEventQueue();
        await complete(sync, 1, height: 102);

        // A round ends while the read is held.
        sync.requestSwapRecovery();
        await pumpEventQueue();
        await releaseRound(_quiet);
        expect(api.recoveries, hasLength(2));
        read.complete(_due);
        await pumpEventQueue();
        expect(
          api.recoveries,
          hasLength(3),
          reason: 'the read says one is due',
        );
        await releaseRound(_quiet);
        await settle(sync);
      },
    );

    test('a due round that keeps failing keeps growing the retry delay across '
        'completed syncs', () async {
      final sync = await atTip();
      // Sync learned a refund funding memo, say, while the receiver is down.
      api.work = _due;
      await syncOnce(sync);
      expect(api.recoveries, hasLength(2));
      await failRound();
      for (final step in const [
        Duration(seconds: 10),
        Duration(seconds: 10),
        Duration(seconds: 30),
        Duration(minutes: 1),
      ]) {
        final rounds = api.recoveries.length;
        for (var syncs = 0; syncs < 3; syncs++) {
          await syncOnce(sync);
        }
        expect(api.recoveries, hasLength(rounds), reason: 'within $step');
        _clock = _clock.add(step - const Duration(seconds: 1));
        expect(await pollStartsRound(sync), isFalse, reason: 'within $step');
        _clock = _clock.add(const Duration(seconds: 1));
        expect(await pollStartsRound(sync), isTrue, reason: 'after $step');
        await failRound();
      }
      await settle(sync);
    });

    for (final late in [false, true]) {
      test('a 16th round that leaves a round due still pauses when the sync '
          'that sees it lands ${late ? 'after' : 'before'} the round '
          'ends', () async {
        final sync = await atTip();
        sync.requestSwapRecovery();
        await pumpEventQueue();
        for (var rounds = 1; rounds < 16; rounds++) {
          await releaseRound(_more);
        }
        expect(api.recoveries, hasLength(17));
        // The 16th round's seed walk registers keys.
        api.work = _due;
        if (!late) await syncOnce(sync);
        await releaseRound(_more);
        if (late) await syncOnce(sync);
        expect(api.recoveries, hasLength(17), reason: 'the chain limit holds');
        _clock = _clock.add(const Duration(seconds: 10));
        expect(await pollStartsRound(sync), isTrue);
        api.work = _settled;
        await releaseRound(_quiet);
        expect(await pollStartsRound(sync), isFalse, reason: 'one round');
        await settle(sync);
      });
    }

    test('new work seen during a retry delay runs one round when the delay '
        'ends', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      await failRound();
      api.work = _due;
      await syncOnce(sync);
      expect(api.recoveries, hasLength(2), reason: 'it waits out the delay');
      _clock = _clock.add(const Duration(seconds: 10));
      expect(await pollStartsRound(sync), isTrue);
      api.work = _settled;
      await releaseRound(_quiet);
      expect(await pollStartsRound(sync), isFalse, reason: 'it served both');
      await syncOnce(sync);
      expect(api.recoveries, hasLength(3));
      await settle(sync);
    });

    final triggers = <String, Future<void> Function(_Sync)>{
      'turning NEAR swap privacy on': (_) =>
          container.read(nearSwapPrivacyProvider.notifier).set(true),
      'choosing a private query server': (sync) async {
        await container.read(walletPirServerApplierProvider)(
          'https://pir.example',
        );
        await pumpEventQueue();
        await complete(sync, 1);
      },
      'a NEAR status': (sync) async => sync.requestSwapRecovery(),
    };
    for (final MapEntry(key: name, value: trigger) in triggers.entries) {
      test('$name during a retry delay runs one round without waiting it '
          'out', () async {
        SharedPreferences.setMockInitialValues({});
        final sync = await atTip(
          overrides: [enhancePirAvailableProvider.overrideWithValue(true)],
        );
        sync.requestSwapRecovery();
        await pumpEventQueue();
        await failRound();
        await trigger(sync);
        await pumpEventQueue();
        expect(api.recoveries, hasLength(3));
        await releaseRound(_quiet);
        expect(await pollStartsRound(sync), isFalse);
        await settle(sync);
      });
    }

    test(
      'an old wallet\'s due work read that lands after a reset is dropped',
      () async {
        final sync = await atTip();
        final read = Completer<rust_swap.SwapRecoveryStatus>();
        api.heldWork = read;
        await syncOnce(sync);
        // A reset's pause drains wallet reads first, so this ends one without it
        // to model a read the reset overtakes.
        sync.endWalletMutationPause();
        read.complete(_due);
        await pumpEventQueue();
        await syncOnce(sync);
        expect(
          api.recoveries,
          hasLength(1),
          reason: 'the old read owes nothing',
        );
        // The replacement wallet's first funding memo.
        api.work = _due;
        await syncOnce(sync);
        expect(api.recoveries, hasLength(2));
        api.work = _settled;
        await releaseRound(_quiet);
        await settle(sync);
      },
    );

    test('new work a sync sees during a history check runs once the check '
        'ends, with no further sync or tip check', () async {
      final sync = await atTip();
      final checking = sync.checkSwapHistory();
      await pumpEventQueue();
      api.work = _due;
      await syncOnce(sync);
      expect(api.recoveries, hasLength(1), reason: 'the check holds the slot');
      api.manual.single.complete(_quiet);
      await checking;
      await pumpEventQueue();
      expect(api.recoveries, hasLength(2));
      api.work = _settled;
      await releaseRound(_quiet);
      await settle(sync);
    });

    for (final (left, round) in [
      ('work Rust can run now', _more),
      ('a job the check keeps polling', _quiet),
    ]) {
      test('a history check ends a long retry delay, so $left carries on at '
          'once', () async {
        final sync = await atTip();
        sync.requestSwapRecovery();
        await pumpEventQueue();
        await failRound();
        for (final step in const [
          Duration(seconds: 10),
          Duration(seconds: 10),
          Duration(seconds: 30),
          Duration(minutes: 1),
          Duration(minutes: 2),
        ]) {
          _clock = _clock.add(step);
          expect(await pollStartsRound(sync), isTrue);
          await failRound();
        }
        final rounds = api.recoveries.length;
        final checking = sync.checkSwapHistory();
        await pumpEventQueue();
        api.manual.single.complete(round);
        await checking;
        sync.pollSwapRecovery();
        await pumpEventQueue();
        expect(api.recoveries, hasLength(rounds + 1), reason: 'no delay left');
        await releaseRound(_quiet);
        await settle(sync);
      });
    }

    test('a history check that fails before its jobs stays failed, while the '
        'scheduler carries an earlier check\'s saved job on after the retry '
        'delay', () async {
      final sync = await atTip();
      const saved = rust_swap.SwapRecoveryStatus(
        roundDue: false,
        awaitingAdmission: false,
        checkingHistory: true,
        manualCheckActive: true,
        upgradeRequired: false,
      );
      Future<void> answerReads() async {
        for (final read in api.statusReads) {
          if (!read.isCompleted) read.complete(saved);
        }
        await pumpEventQueue();
      }

      final history = container.read(swapHistoryCheckProvider.notifier);
      final checking = history.check();
      await pumpEventQueue();
      api.manual.single.completeError(
        const rust_swap.ReceiveError(
          message: 'HTTP 503',
          kind: rust_swap.ReceiveErrorKind.other,
          historyStarted: false,
        ),
      );
      await checking;
      await answerReads();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.failed);
      expect(api.recoveries, hasLength(1), reason: 'within the retry delay');

      _clock = _clock.add(const Duration(seconds: 10));
      expect(await pollStartsRound(sync), isTrue, reason: 'the jobs resume');
      await releaseRound(_quiet);
      await answerReads();
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.failed);
      await settle(sync);
    });

    test('payments awaiting admission start sync after a history check or a '
        'failed round', () async {
      final sync = await atTip();
      final checking = sync.checkSwapHistory();
      await pumpEventQueue();
      api.manual.single.complete(
        rust_swap.SwapRecoveryRound(
          changed: true,
          checked: true,
          more: false,
          rescan: true,
        ),
      );
      await checking;
      await pumpEventQueue();
      expect(api.syncs, hasLength(2), reason: 'the history check needs sync');
      await complete(sync, 1);

      api.work = rust_swap.SwapRecoveryStatus(
        roundDue: false,
        awaitingAdmission: true,
        checkingHistory: false,
        manualCheckActive: false,
        upgradeRequired: false,
      );
      sync.requestSwapRecovery();
      await pumpEventQueue();
      await failRound();
      await pumpEventQueue();
      expect(api.syncs, hasLength(3), reason: 'a failed round can leave one');
      await settle(sync);
    });

    test('rounds chain while Rust reports more work it can run now', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      await releaseRound(_more);
      expect(api.recoveries, hasLength(3));
      await releaseRound(_more);
      expect(api.recoveries, hasLength(4));
      await releaseRound(_quiet);
      expect(api.recoveries, hasLength(4));
      expect(await pollStartsRound(sync), isFalse);
      await settle(sync);
    });

    test(
      'a failed round, or a lookup waiting out its retry delay, delays '
      'the request: tip checks and completed syncs wait, then run it',
      () async {
        final sync = await atTip();
        sync.requestSwapRecovery();
        await pumpEventQueue();
        await failRound();
        expect(await pollStartsRound(sync), isFalse);
        sync.startSync(latestTipHeight: 102);
        await pumpEventQueue();
        await complete(sync, 1, height: 102);
        expect(api.recoveries, hasLength(2), reason: 'within the retry delay');
        _clock = _clock.add(const Duration(seconds: 10));
        expect(await pollStartsRound(sync), isTrue);

        await releaseRound(_waiting(rust_swap.SwapRecoveryWait.backoff));
        _clock = _clock.add(const Duration(seconds: 9));
        expect(await pollStartsRound(sync), isFalse);
        _clock = _clock.add(const Duration(seconds: 1));
        expect(await pollStartsRound(sync), isTrue);
        await releaseRound(_quiet);
        expect(await pollStartsRound(sync), isFalse, reason: 'it was served');
        await settle(sync);
      },
    );

    test('retry delays grow to half an hour, and a round that succeeds starts '
        'them over', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      await failRound();
      const steps = [
        Duration(seconds: 10),
        Duration(seconds: 10),
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 5),
        Duration(minutes: 15),
        Duration(minutes: 30),
        Duration(minutes: 30),
      ];
      for (final step in steps) {
        _clock = _clock.add(step - const Duration(seconds: 1));
        expect(await pollStartsRound(sync), isFalse, reason: 'within $step');
        _clock = _clock.add(const Duration(seconds: 1));
        expect(await pollStartsRound(sync), isTrue, reason: 'after $step');
        await failRound();
      }
      _clock = _clock.add(const Duration(minutes: 30));
      expect(await pollStartsRound(sync), isTrue);
      await releaseRound(_waiting(rust_swap.SwapRecoveryWait.backoff));
      _clock = _clock.add(const Duration(minutes: 30));
      expect(await pollStartsRound(sync), isTrue);
      await releaseRound(_quiet);

      sync.requestSwapRecovery();
      await pumpEventQueue();
      await failRound();
      _clock = _clock.add(const Duration(seconds: 10));
      expect(await pollStartsRound(sync), isTrue, reason: 'the first step');
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('a new request or a forced start runs at once despite a retry '
        'delay', () async {
      final sync = await atTip();
      sync.requestSwapRecovery();
      await pumpEventQueue();
      await failRound();
      expect(await pollStartsRound(sync), isFalse);

      sync.requestSwapRecovery();
      await pumpEventQueue();
      expect(api.recoveries, hasLength(3));
      await failRound();

      sync.continueSwapRecovery();
      await pumpEventQueue();
      expect(api.recoveries, hasLength(4), reason: 'a caller waits on it');
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('a watched history check keeps polling rounds, waiting out a retry '
        'delay instead of starting it over', () async {
      final reads = <Completer<rust_swap.SwapRecoveryStatus>>[];
      const checking = rust_swap.SwapRecoveryStatus(
        roundDue: false,
        awaitingAdmission: false,
        checkingHistory: true,
        manualCheckActive: true,
        upgradeRequired: false,
      );
      final sync = await atTip(
        overrides: [
          swapHistoryApiProvider.overrideWithValue(
            SwapHistoryApi(
              begin: () async {},
              cancel: () async {},
              status: () {
                final read = Completer<rust_swap.SwapRecoveryStatus>();
                reads.add(read);
                return read.future;
              },
              pollInterval: Duration.zero,
            ),
          ),
        ],
      );
      final history = container.read(swapHistoryCheckProvider.notifier);
      final watching = history.check();
      await pumpEventQueue();
      expect(api.recoveries, hasLength(2), reason: 'the check polls a round');
      await failRound();

      reads.last.complete(checking);
      await pumpEventQueue();
      expect(api.recoveries, hasLength(2), reason: 'within the retry delay');

      _clock = _clock.add(const Duration(seconds: 10));
      reads.last.complete(checking);
      await pumpEventQueue();
      expect(api.recoveries, hasLength(3));
      await releaseRound(_quiet);

      reads.last.complete(
        const rust_swap.SwapRecoveryStatus(
          roundDue: false,
          awaitingAdmission: false,
          checkingHistory: false,
          manualCheckActive: false,
          upgradeRequired: false,
        ),
      );
      await watching;
      expect(container.read(swapHistoryCheckProvider), SwapHistoryCheck.done);
      await settle(sync);
    });
  });

  group('filter steps', () {
    /// Ends the held step, reporting whether it left work only a round can do.
    Future<void> releaseStep({bool needsRound = false}) async {
      api.steps.last.complete(rust_swap.SwapFilterStep(needsRound: needsRound));
      await pumpEventQueue();
    }

    /// A notifier past its cold start whose step after the sync to block 102
    /// the test holds.
    Future<_Sync> stepping() async {
      final sync = await atTip();
      api.holdSteps = true;
      await syncOnce(sync);
      expect(api.steps, hasLength(1));
      return sync;
    }

    test('one follows a completed sync that moved the scanned tip, only when '
        'no round is owed or running', () async {
      final sync = await atTip();
      expect(api.steps, isEmpty, reason: 'the launch round was owed');
      await syncOnce(sync);
      expect(api.steps, hasLength(1));
      sync.startSync(latestTipHeight: 102);
      await pumpEventQueue();
      await complete(sync, api.syncs.length - 1, height: 102);
      expect(api.steps, hasLength(1), reason: 'the tip did not move');

      sync.requestSwapRecovery();
      await pumpEventQueue();
      await syncOnce(sync);
      expect(api.steps, hasLength(1), reason: 'a round is running');
      await failRound();
      await syncOnce(sync);
      expect(api.steps, hasLength(1), reason: 'a round is owed');
      _clock = _clock.add(const Duration(seconds: 10));
      expect(await pollStartsRound(sync), isTrue);
      await releaseRound(_quiet);
      await syncOnce(sync);
      expect(api.steps, hasLength(2));
      expect(api.recoveries, hasLength(3));
      await settle(sync);
    });

    /// Hiding cancels a step only where process work must stop.
    Future<void> hiding() async {
      final sync = await stepping();
      sync.handleAppHideForTesting();
      expect(api.cancels, canRunAppProcessWork(isInForeground: false) ? 0 : 1);
      await releaseStep();
      await settle(sync);
    }

    test('hiding the app cancels it where process work must stop', hiding);
    test(
      'hiding the app cancels it where process work must stop (mobile)',
      hiding,
      tags: ['mobile'],
    );

    final cancellers = <String, Future<void> Function(_Sync)>{
      'locking': (sync) {
        (container.read(appSecurityProvider.notifier) as _Security).setUnlocked(
          false,
        );
        return sync.clearSensitiveStateForLock();
      },
      'a manual check': (sync) => sync.checkSwapHistory(),
      'choosing a private query server': (_) =>
          container.read(walletPirServerApplierProvider)('https://pir.example'),
    };
    for (final MapEntry(key: name, value: canceller) in cancellers.entries) {
      test('$name cancels it and waits for it to stop', () async {
        final sync = await stepping();
        var done = false;
        unawaited(canceller(sync).then((_) => done = true));
        await pumpEventQueue();
        expect(api.cancels, 1);
        expect(done, isFalse, reason: 'it waits for the step');
        expect(api.manual, isEmpty);
        api.steps.last.completeError('Swap recovery was cancelled.');
        await pumpEventQueue();
        // Rust admits the manual check once the step has stopped.
        if (name == 'a manual check') {
          expect(api.manual, hasLength(1));
          api.manual.single.complete(_quiet);
        }
        await pumpEventQueue();
        expect(done, isTrue);
        await settle(sync);
      });
    }

    for (final end in ['ends', 'fails', 'is cancelled']) {
      test('a round requested while one runs starts once it $end', () async {
        final sync = await stepping();
        sync.requestSwapRecovery();
        await pumpEventQueue();
        expect(api.recoveries, hasLength(1), reason: 'the step holds the slot');
        switch (end) {
          case 'ends':
            await releaseStep();
          case 'fails':
            api.steps.last.completeError(_outage);
          default:
            await switchTo(sync, _second);
            expect(api.cancels, 1);
            api.steps.last.completeError('Swap recovery was cancelled.');
        }
        await pumpEventQueue();
        expect(api.recoveries, hasLength(2), reason: 'Rust admitted it');
        await releaseRound(_quiet);
        expect(await pollStartsRound(sync), isFalse);
        await settle(sync);
      });
    }

    test('needsRound, which a failed filter request reports, owes one round '
        'after it, as new work does, so that '
        'round keeps its retry delay', () async {
      final sync = await stepping();
      await releaseStep(needsRound: true);
      expect(api.recoveries, hasLength(2));
      await failRound();
      await syncOnce(sync);
      expect(api.steps, hasLength(1), reason: 'a round is owed');
      expect(api.recoveries, hasLength(2), reason: 'within the retry delay');
      _clock = _clock.add(const Duration(seconds: 10));
      expect(await pollStartsRound(sync), isTrue);
      await releaseRound(_quiet);
      await settle(sync);
    });

    for (final failing in [false, true]) {
      test('a wait for recovery that joins one waits for the round it owes '
          '${failing ? 'to fail' : 'to finish'}', () async {
        final sync = await stepping();
        Object? result = 'pending';
        unawaited(sync.awaitSwapRecovery().then((value) => result = value));
        await pumpEventQueue();
        await releaseStep();
        expect(api.recoveries, hasLength(2));
        expect(result, 'pending', reason: 'the round is still running');
        expect(api.readinessReads, isEmpty);
        if (failing) {
          await failRound();
        } else {
          await releaseRound(_quiet);
        }
        await pumpEventQueue();
        expect(result, failing ? _outage : isNull);
        await settle(sync);
      });
    }

    test('a step that fails owes one round', () async {
      final sync = await stepping();
      api.steps.last.completeError(StateError('wallet locked'));
      await pumpEventQueue();
      expect(api.recoveries, hasLength(2));
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('a hit that makes a round due owes one once the step ends', () async {
      final sync = await stepping();
      api.work = _due;
      await releaseStep();
      expect(api.recoveries, hasLength(2));
      api.work = _settled;
      await releaseRound(_quiet);
      await settle(sync);
    });
  });

  group('waiting on recovery', () {
    test('returns a round\'s failure, or nothing once it succeeds or was '
        'cancelled', () async {
      final sync = await atTip(privacy: true);
      final failed = sync.awaitSwapRecovery();
      await pumpEventQueue();
      api.round.completeError(_outage);
      expect(await failed, same(_outage), reason: 'it waited on the round');

      final succeeded = sync.awaitSwapRecovery();
      await pumpEventQueue();
      expect(api.recoveries, hasLength(3), reason: 'it started a new round');
      await releaseRound();
      expect(await succeeded, isNull);

      final cancelled = sync.awaitSwapRecovery();
      await pumpEventQueue();
      final security =
          container.read(appSecurityProvider.notifier) as _Security;
      security.setUnlocked(false);
      unawaited(sync.clearSensitiveStateForLock());
      await pumpEventQueue();
      api.round.completeError(_outage);
      expect(await cancelled, isNull, reason: 'locking cancelled the round');
      await settle(sync);
    });

    test('follows chained rounds until the active account is ready, '
        'whatever other accounts still need', () async {
      final sync = await atTip(privacy: true);
      await switchTo(sync, _second);
      await releaseRound(_quiet);
      api.readinessReads.clear();

      api.readiness = _admitting;
      var done = false;
      final waiting = sync.awaitSwapRecovery().then((failure) {
        done = true;
        return failure;
      });
      await pumpEventQueue();
      await releaseRound(_more);
      expect(done, isFalse, reason: 'a payment still waits for admission');
      expect(api.recoveries, hasLength(4), reason: 'the rounds chain');

      api.readiness = _ready;
      await releaseRound(_more);
      expect(await waiting, isNull);
      expect(api.recoveries, hasLength(5), reason: 'the chain goes on');
      expect(api.readinessReads.toSet(), {_second}, reason: 'only active');
      await releaseRound(_quiet);
      await settle(sync);
    });

    test('ends when the rest of the work waits', () async {
      final sync = await atTip(privacy: true);
      api.readiness = _busy;
      final waiting = sync.awaitSwapRecovery();
      await pumpEventQueue();
      await releaseRound(_waiting(rust_swap.SwapRecoveryWait.publication));
      expect(await waiting, isNull);
      await settle(sync);
    });
  });

  test(
    'ordinary sync scans more than three blocks and starts again while a '
    'receiver round is held, and the release needs no further block',
    () async {
      final sync = await recovering();

      for (final height in [103, 104, 105]) {
        api.syncs[1].add(_scanned(height));
        await pumpEventQueue();
        expect(sync.state.requireValue.scannedHeight, height);
      }
      await complete(sync, 1, height: 105);
      expect(sync.state.requireValue.isSyncComplete, isTrue);

      // A new tip starts the next ordinary sync while the round is still held.
      sync.startSync(latestTipHeight: 109);
      await pumpEventQueue();
      expect(api.syncs, hasLength(3));
      for (final height in [106, 107, 108, 109]) {
        api.syncs[2].add(_scanned(height));
        await pumpEventQueue();
      }
      sync.stopTipChecksForTesting();
      expect(sync.state.requireValue.scannedHeight, 109);
      expect(api.recoveries, hasLength(2), reason: 'one round at a time');
      expect(api.cancels, 0, reason: 'sync never cancels or waits for it');
      expect(api.round.isCompleted, isFalse);

      final reads = api.balanceReads.length;
      final followups = container.read(syncFollowupProvider);
      await releaseRound();
      expect(container.read(syncFollowupProvider), followups + 1);
      expect(api.balanceReads.length, greaterThan(reads));
      expect(api.syncs, hasLength(3), reason: 'no new sync was needed');
      expect(api.manual, isEmpty, reason: 'no manual action was needed');
      await settle(sync);
    },
  );

  test('a round that changed nothing reloads nothing, and one that changed '
      'something reloads Activity and the balance', () async {
    final sync = await recovering(privacy: true);
    final reads = api.balanceReads.length;
    final followups = container.read(syncFollowupProvider);
    await releaseRound(_quiet);
    expect(container.read(syncFollowupProvider), followups);
    expect(api.balanceReads.length, reads);

    sync.continueSwapRecovery();
    await pumpEventQueue();
    expect(api.recoveries, hasLength(3));
    await releaseRound();
    expect(container.read(syncFollowupProvider), followups + 1);
    expect(api.balanceReads.length, greaterThan(reads));
    await settle(sync);
  });

  test('a failed round reloads Activity and the balance, since it may have '
      'committed results first', () async {
    final sync = await recovering(privacy: true);
    final reads = api.balanceReads.length;
    final followups = container.read(syncFollowupProvider);
    await failRound();
    expect(container.read(syncFollowupProvider), followups + 1);
    expect(api.balanceReads.length, greaterThan(reads));
    await settle(sync);
  });

  test('a cancelled round leaves its work owed for the next completed sync, '
      'without a retry delay', () async {
    final sync = await recovering(privacy: true);
    final restarting = sync.restartSyncAfterTransportChange(
      () async {},
      failIfNotQuiescent: false,
    );
    await pumpEventQueue();
    expect(api.cancels, 1);
    api.round.completeError(_outage);
    await restarting;
    await pumpEventQueue();
    sync.stopTipChecksForTesting();

    expect(api.syncs, hasLength(3));
    await complete(sync, 2);
    expect(api.recoveries, hasLength(3));
    await releaseRound(_quiet);
    await settle(sync);
  });

  test('the update request follows the wallet\'s saved state after each '
      'round', () async {
    final sync = await recovering(privacy: true);
    api.work = rust_swap.SwapRecoveryStatus(
      roundDue: false,
      awaitingAdmission: false,
      checkingHistory: false,
      manualCheckActive: false,
      upgradeRequired: true,
    );
    await releaseRound(_idle);
    expect(
      await container.read(swapRecoveryUpdateRequiredProvider.future),
      isTrue,
    );

    // A round that reached a compatible service clears the saved request.
    api.work = _settled;
    sync.continueSwapRecovery();
    await pumpEventQueue();
    await releaseRound(_quiet);
    expect(
      await container.read(swapRecoveryUpdateRequiredProvider.future),
      isFalse,
    );
    await settle(sync);
  });

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
    expect(api.recoveries, hasLength(2));

    security.setUnlocked(true);
    sync.refreshHomeInBackground();
    await sync.checkTipForTesting();
    await pumpEventQueue();
    expect(api.syncs, hasLength(3), reason: 'unlock syncs first');
    expect(api.recoveries, hasLength(2), reason: 'not before it completes');
    await complete(sync, 2);
    expect(api.recoveries, hasLength(3), reason: 'saved work resumes');
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
    api.syncs[1].add(_scanned(102, kind: rust_sync.ApiSyncEventKind.completed));
    await settle(sync);
    expect(api.recoveries, hasLength(3), reason: 'returning owes a round');
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
    expect(api.recoveries, hasLength(2), reason: 'no round during a mutation');

    sync.resumeAfterWalletMutation(pause);
    await pumpEventQueue();
    sync.continueSwapRecovery();
    await settle(sync);
    expect(api.recoveries, hasLength(3));
  });

  test('a wallet mutation waits for a swap status read, and none starts while '
      'it runs', () async {
    final sync = await recovering();
    await releaseRound(_idle);
    const idle = rust_swap.SwapRecoveryStatus(
      roundDue: false,
      awaitingAdmission: false,
      checkingHistory: false,
      manualCheckActive: false,
      upgradeRequired: false,
    );
    api.holdStatus = true;
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
    await releaseRound(_idle);
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

  test('an account switch restarts the automatic round once sync completes, '
      'and its result refreshes the newly active account', () async {
    final sync = await recovering();
    await switchTo(sync, _second);
    expect(api.cancels, 1);
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(api.recoveries, hasLength(2), reason: 'sync is still running');
    await complete(sync, 1, height: 102);
    expect(api.recoveries, hasLength(3), reason: 'restarted at the tip');

    api.balanceReads.clear();
    await releaseRound();
    expect(api.balanceReads, isNotEmpty);
    expect(api.balanceReads.toSet(), {_second});
    await settle(sync);
  });

  test('an account switch leaves a running history check alone', () async {
    final sync = await recovering();
    final checking = sync.checkSwapHistory();
    await pumpEventQueue();
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(api.manual, hasLength(1));
    final cancels = api.cancels;

    await switchTo(sync, _second);
    expect(api.cancels, cancels);
    api.manual.single.complete(_changed);
    await checking;
    await settle(sync);
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

  test('a failed manual check reloads Activity and the balance before it '
      'reports the failure', () async {
    final sync = await recovering();
    final checking = sync.checkSwapHistory();
    await pumpEventQueue();
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(api.manual, hasLength(1));

    final followups = container.read(syncFollowupProvider);
    api.manual.single.completeError(_outage);
    await expectLater(checking, throwsA(same(_outage)));
    expect(container.read(syncFollowupProvider), followups + 1);
    await settle(sync);
  });

  test('pausing a check reloads Activity and the balance for the round it '
      'stopped', () async {
    final sync = await recovering();
    final checking = sync.checkSwapHistory();
    await pumpEventQueue();
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();

    final followups = container.read(syncFollowupProvider);
    final pausing = sync.cancelSwapHistory();
    await pumpEventQueue();
    api.manual.single.completeError('Swap recovery was cancelled.');
    await expectLater(checking, throwsStateError);
    await pausing;
    expect(container.read(syncFollowupProvider), followups + 1);
    await settle(sync);
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

  test('a round cancelled after it reached the wallet leaves its refresh to '
      'the next round, even a quiet one', () async {
    final sync = await recovering(privacy: true);
    final followups = container.read(syncFollowupProvider);
    final restarting = sync.restartSyncAfterTransportChange(
      () async {},
      failIfNotQuiescent: false,
    );
    await pumpEventQueue();
    api.round.completeError('Swap recovery was cancelled.');
    await restarting;
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(container.read(syncFollowupProvider), followups);

    await complete(sync, 2);
    expect(api.recoveries, hasLength(3));
    await releaseRound(_quiet);
    expect(container.read(syncFollowupProvider), followups + 1);

    // The refresh was paid, so the next quiet round reloads nothing.
    sync.continueSwapRecovery();
    await pumpEventQueue();
    await releaseRound(_quiet);
    expect(container.read(syncFollowupProvider), followups + 1);
    await settle(sync);
  });

  test('returning to the app reloads Activity for a round backgrounding '
      'cancelled', () async {
    final sync = await recovering(privacy: true);
    final followups = container.read(syncFollowupProvider);
    sync.handleAppHideForTesting();
    expect(api.cancels, 1);
    api.round.completeError('Swap recovery was cancelled.');
    await pumpEventQueue();
    expect(container.read(syncFollowupProvider), followups);

    sync.handleAppResumeForTesting();
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(container.read(syncFollowupProvider), followups + 1);
    await settle(sync);
  }, tags: ['mobile']);

  test('pausing reloads Activity for the stopped round even when saving the '
      'pause fails, and still reports the failure', () async {
    final sync = await recovering(privacy: true);
    final followups = container.read(syncFollowupProvider);
    api.cancelFailure = _outage;
    final pausing = sync.cancelSwapHistory();
    await pumpEventQueue();
    api.round.completeError('Swap recovery was cancelled.');
    await expectLater(pausing, throwsA(same(_outage)));
    expect(container.read(syncFollowupProvider), followups + 1);
    await settle(sync);
  });

  test('a round cancelled by locking refreshes nothing while locked, and '
      'unlocking pays the refresh it owes', () async {
    final sync = await recovering(privacy: true);
    final followups = container.read(syncFollowupProvider);
    final security = container.read(appSecurityProvider.notifier) as _Security;
    security.setUnlocked(false);
    final locking = sync.clearSensitiveStateForLock();
    await pumpEventQueue();
    api.round.completeError('Swap recovery was cancelled.');
    await locking;
    sync.handleAppResumeForTesting();
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    expect(container.read(syncFollowupProvider), followups);

    security.setUnlocked(true);
    await sync.refreshAfterUnlock();
    sync.refreshHomeInBackground();
    await pumpEventQueue();
    expect(container.read(syncFollowupProvider), followups + 1);
    await settle(sync);
  });
}
