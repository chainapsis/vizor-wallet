// Scenario tests for when the sync notifier schedules one-time IVK recovery
// rounds, complementing sync_swap_recovery_test.dart. See
// `SyncNotifier._startSwapRecovery` and docs/near-swap-receiving.md.
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
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart' as rust_swap;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _account = 'account-1';

/// Rust as the scheduler sees it: a sync stream the test feeds batch by batch
/// and recovery rounds the test holds and then completes.
class _Api extends RustLibApi {
  bool running = false;
  final syncs = <StreamController<rust_sync.ApiSyncProgressEvent>>[];
  final rounds = <Completer<bool>>[];
  final balanceReads = <String>[];

  /// Whether the fake's sync holds the Rust guard.
  @override
  bool crateApiSyncIsSyncRunning() => running;

  /// Reports no pending cancellation.
  @override
  bool crateApiSyncIsSyncCancelRequested() => false;

  /// Reports no mempool observer.
  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;

  /// Ignores the active account hint.
  @override
  void crateApiSyncSetActiveSyncAccount({String? accountUuid}) {}

  /// Ignores the sync mode.
  @override
  void crateApiSyncSetSyncMode({required int mode}) {}

  /// Releases the sync guard.
  @override
  void crateApiSyncCancelFullSync() => running = false;

  /// Accepts the stop of an observer that never runs.
  @override
  void crateApiSyncStopMempoolObserver() {}

  /// Observes nothing.
  @override
  Stream<rust_sync.ApiMempoolTxEvent> crateApiSyncStartMempoolObserver({
    required String dbPath,
    required String network,
    required String lightwalletdUrl,
  }) => const Stream.empty();

  /// Starts a sync whose batches the test adds.
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

  /// Starts a held recovery round.
  @override
  Future<bool> crateApiOneTimeIvkRunSwapRecovery({
    required String dbPath,
    required String networkName,
  }) {
    final round = Completer<bool>();
    rounds.add(round);
    return round.future;
  }

  /// Accepts a cancellation; the held round ends when the test completes it.
  @override
  void crateApiOneTimeIvkCancelSwapRecovery() {}

  /// Records which account's balance was read.
  @override
  Future<rust_sync.WalletBalance> crateApiSyncGetBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    balanceReads.add(accountUuid);
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

  /// Returns an empty history.
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

  /// The tip the initial state already scanned.
  @override
  Future<BigInt> getLatestBlockHeight() async => BigInt.from(100);
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

class _NoPrivateQueries extends EnhancePirNotifier {
  /// Private queries off.
  @override
  bool build() => false;
}

class _Privacy extends NearSwapPrivacyNotifier {
  /// NEAR swap privacy off until [turn] changes it.
  @override
  bool build() => false;

  /// Changes the setting without the settings store or native calls.
  void turn(bool on) => state = on;
}

class _Sync extends SyncNotifier {
  _Sync()
    : super(
        walletDbPathResolver: () async => 'wallet.db',
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
    api.running = false;
    api.syncs.clear();
    api.rounds.clear();
    api.balanceReads.clear();
  });

  late ProviderContainer container;
  late _Sync sync;

  /// Starts a sync whose first batch, block 101, starts a held round.
  Future<void> recovering() async {
    sync = _Sync();
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Accounts.new),
        appSecurityProvider.overrideWith(_Security.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        nearSwapPrivacyProvider.overrideWith(_Privacy.new),
        swapRecoveryStatusReaderProvider.overrideWithValue(() async => null),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    container.listen(swapRecoveryUpdateRequiredProvider, (_, _) {});
    await container.read(syncProvider.future);
    sync.stopTipChecksForTesting();
    sync.startSync();
    await pumpEventQueue();
    api.syncs[0].add(_scanned(101));
    await pumpEventQueue();
    expect(api.rounds, hasLength(1));
  }

  /// Feeds one more batch through `height` and returns the round count.
  Future<int> batch(int height) async {
    api.syncs[0].add(_scanned(height));
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    return api.rounds.length;
  }

  /// Stops the sync before the container goes.
  Future<void> settle() async {
    await pumpEventQueue();
    sync.stopTipChecksForTesting();
    sync.stopSync();
    await pumpEventQueue();
  }

  /// A round that reports the service needs a newer app raises the update
  /// request, refreshes nothing, and a later successful round clears it.
  test(
    'an outdated service asks for an update until a round succeeds',
    () async {
      await recovering();
      final followups = container.read(syncFollowupProvider);
      api.rounds.last.completeError(
        const rust_swap.ReceiveError(
          message:
              'Update Vizor to keep checking private swap addresses. '
              'Your saved progress is kept.',
          kind: rust_swap.ReceiveErrorKind.upgradeRequired,
        ),
      );
      await pumpEventQueue();
      expect(container.read(swapRecoveryUpdateRequiredProvider), isTrue);
      expect(container.read(syncFollowupProvider), followups);

      expect(await batch(102), 2, reason: 'a failed round is not idle');
      api.rounds.last.complete(false);
      await pumpEventQueue();
      expect(container.read(swapRecoveryUpdateRequiredProvider), isFalse);
      await settle();
    },
  );

  /// Turning NEAR swap privacy on while the wallet is idle resumes rounds on
  /// the next batch, and turning it back off lets an idle wallet skip them.
  test('rounds follow NEAR swap privacy changes while idle', () async {
    await recovering();
    api.rounds.last.complete(false);
    await pumpEventQueue();
    expect(await batch(102), 1, reason: 'idle and off');

    final privacy =
        container.read(nearSwapPrivacyProvider.notifier) as _Privacy;
    privacy.turn(true);
    expect(await batch(103), 2, reason: 'on: every batch asks Rust');
    api.rounds.last.complete(false);
    await pumpEventQueue();
    expect(await batch(104), 3);
    api.rounds.last.complete(false);
    await pumpEventQueue();

    privacy.turn(false);
    expect(await batch(105), 3, reason: 'off and the last round was idle');
    await settle();
  });

  /// With NEAR swap privacy off, a round that fails leaves the wallet's work
  /// unknown, so the next batch asks Rust again rather than going idle.
  /// Documents current behavior: a persistently failing feature-off round
  /// costs one Rust call per batch and idle poll, with no follow-up refresh.
  test('a failed round with the feature off is retried per batch', () async {
    await recovering();
    final reads = api.balanceReads.length;
    for (var height = 102; height <= 104; height++) {
      api.rounds.last.completeError(StateError('database is locked'));
      await pumpEventQueue();
      expect(await batch(height), height - 100);
    }
    expect(api.balanceReads.length, reads, reason: 'no follow-up refresh');
    api.rounds.last.complete(false);
    await pumpEventQueue();
    expect(await batch(105), 4, reason: 'an idle answer stops the retries');
    await settle();
  });
}
