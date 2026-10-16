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

const _accountUuid = 'account-1';
const _otherAccountUuid = 'account-2';

/// Rust as the sync loop sees it: one guard, held from `startFullSync` until
/// the test ends that sync's stream.
class _Api extends RustLibApi {
  bool running = false;
  int historyReads = 0;
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
  }) async {
    historyReads++;
    return const [];
  }

  /// Ends sync [index]: Rust releases the guard, then the stream closes.
  Future<void> finish(int index) async {
    running = false;
    await syncs[index].close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Starts with no wallet, so the test decides when an account appears.
class _Account extends AccountNotifier {
  @override
  AccountState build() => const AccountState(accounts: []);

  /// Adds the imported or created account and makes it active, as both
  /// import and create do.
  void add() => state = const AsyncData(
    AccountState(
      accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
      activeAccountUuid: _accountUuid,
    ),
  );

  void activate(String uuid) => state = AsyncData(
    AccountState(
      accounts: const [
        AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0),
        AccountInfo(uuid: _otherAccountUuid, name: 'Account 2', order: 1),
      ],
      activeAccountUuid: uuid,
    ),
  );
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  void lockForTest() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
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

rust_sync.ApiSyncProgressEvent _event(rust_sync.ApiSyncEventKind kind) =>
    rust_sync.ApiSyncProgressEvent(
      kind: kind,
      scannedHeight: BigInt.from(
        kind == rust_sync.ApiSyncEventKind.progress ? 50 : 100,
      ),
      chainTipHeight: BigInt.from(100),
      percentage: kind == rust_sync.ApiSyncEventKind.progress ? 0.5 : 1,
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
  final api = _Api();
  // When set, marking companions out of backups waits for it.
  Completer<void>? backupGate;
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    api.running = false;
    api.historyReads = 0;
    api.syncs.clear();
    backupGate = null;
  });

  late ProviderContainer container;
  late SyncNotifier sync;
  late _Account account;
  late _Security security;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
  }

  /// Adds the wallet's account, which starts its first sync, and records a
  /// seed import when [imported].
  Future<void> addAccount(WidgetTester tester, {required bool imported}) async {
    sync = SyncNotifier(
      walletDbPathResolver: () async => 'wallet.db',
      excludeCompanionsFromBackup: (_) => backupGate?.future ?? Future.value(),
    );
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_Account.new),
        appSecurityProvider.overrideWith(_Security.new),
        rpcEndpointFailoverProvider.overrideWith(_Tip.new),
        chainUpgradeStatusProvider.overrideWith(_Upgrade.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        syncProvider.overrideWith(() => sync),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    account = container.read(accountProvider.notifier) as _Account;
    security = container.read(appSecurityProvider.notifier) as _Security;
    account.add();
    if (imported) container.read(seedImportProvider.notifier).imported();
    await settle(tester);
    expect(api.syncs, hasLength(1), reason: 'the new account starts a sync');
  }

  /// Disposes the wallet before the test ends, so no timer outlives it.
  Future<void> done(WidgetTester tester) async {
    sync.stopTipChecksForTesting();
    container.dispose();
    await settle(tester);
  }

  /// Ends the first sync after the account appeared, completed.
  Future<void> endFirstSync(WidgetTester tester) async {
    api.syncs[0].add(_event(rust_sync.ApiSyncEventKind.completed));
    await settle(tester);
    await api.finish(0);
    await settle(tester);
    sync.stopTipChecksForTesting();
  }

  testWidgets('a seed import opens the window when its first sync ends', (
    tester,
  ) async {
    await addAccount(tester, imported: true);
    expect(sync.seedImportSyncWindowArmedForTesting, isTrue);
    expect(sync.seedImportSyncWindowOpenForTesting, isFalse);
    // Ticks would be wasted while the first restore scan runs.
    await tester.pump(kSeedImportSyncInterval * 3);
    await settle(tester);
    expect(api.syncs, hasLength(1));

    await endFirstSync(tester);
    expect(sync.seedImportSyncWindowOpenForTesting, isTrue);
    await tester.pump(kSeedImportSyncInterval);
    await settle(tester);
    expect(api.syncs, hasLength(2));
    await api.finish(1);
    await settle(tester);
    await done(tester);
  });

  testWidgets('a failed first sync opens the window too', (tester) async {
    await addAccount(tester, imported: true);
    api.running = false;
    api.syncs[0].addError(StateError('connection refused'));
    await settle(tester);
    sync.stopTipChecksForTesting();
    expect(sync.seedImportSyncWindowOpenForTesting, isTrue);
    await done(tester);
  });

  testWidgets('creating a wallet opens no window', (tester) async {
    await addAccount(tester, imported: false);
    await endFirstSync(tester);
    expect(sync.seedImportSyncWindowArmedForTesting, isFalse);
    expect(sync.seedImportSyncWindowOpenForTesting, isFalse);
    await tester.pump(kSeedImportSyncInterval * 6);
    await settle(tester);
    expect(api.syncs, hasLength(1));
    await done(tester);
  });

  testWidgets('quiet syncs run every interval whatever they report, skip a '
      'tick while one runs, and stop after the window', (tester) async {
    await addAccount(tester, imported: true);
    await endFirstSync(tester);
    final completed = sync.state.requireValue;
    final ticks =
        kSeedImportSyncWindow.inMicroseconds ~/
        kSeedImportSyncInterval.inMicroseconds;
    final outcomes = [
      rust_sync.ApiSyncEventKind.completed,
      rust_sync.ApiSyncEventKind.followupUpdated,
      null,
    ];
    var quiet = 0;
    for (var tick = 1; tick <= ticks; tick++) {
      await tester.pump(kSeedImportSyncInterval);
      await settle(tester);
      if (tick == 2) {
        // The quiet sync from tick 1 still runs: this tick is skipped.
        expect(api.syncs, hasLength(1 + quiet));
        await api.finish(quiet);
        await settle(tester);
        continue;
      }
      quiet++;
      expect(api.syncs, hasLength(1 + quiet), reason: 'tick $tick');
      final index = quiet;
      final controller = api.syncs[index];
      controller.add(_event(rust_sync.ApiSyncEventKind.progress));
      await settle(tester);
      // Progress never reaches the syncing state.
      final during = sync.state.requireValue;
      expect(during.isSyncing, isFalse);
      expect(during.percentage, completed.percentage);
      expect(during.scannedHeight, completed.scannedHeight);
      if (tick == 1) continue; // left running across tick 2
      final outcome = outcomes[tick % outcomes.length];
      final reads = api.historyReads;
      if (outcome != null) controller.add(_event(outcome));
      await settle(tester);
      expect(sync.state.requireValue.isSyncing, isFalse);
      if (outcome != null) {
        expect(api.historyReads, greaterThan(reads), reason: 'refreshed');
      }
      await api.finish(index);
      await settle(tester);
    }
    expect(quiet, ticks - 1);
    expect(sync.seedImportSyncWindowOpenForTesting, isFalse);
    await tester.pump(kSeedImportSyncInterval * 3);
    await settle(tester);
    expect(api.syncs, hasLength(1 + quiet));
    await done(tester);
  });

  testWidgets('a lock ends the window', (tester) async {
    await addAccount(tester, imported: true);
    await endFirstSync(tester);
    security.lockForTest();
    await tester.pump(kSeedImportSyncInterval);
    await settle(tester);
    expect(api.syncs, hasLength(1));
    expect(sync.seedImportSyncWindowOpenForTesting, isFalse);
    await done(tester);
  });

  testWidgets('hiding the app ends the window', (tester) async {
    await addAccount(tester, imported: true);
    await endFirstSync(tester);
    sync.handleAppHideForTesting();
    expect(sync.seedImportSyncWindowOpenForTesting, isFalse);
    await tester.pump(kSeedImportSyncInterval);
    await settle(tester);
    expect(api.syncs, hasLength(1));
    await done(tester);
  });

  testWidgets('hiding the app while a quiet sync prepares starts no sync', (
    tester,
  ) async {
    await addAccount(tester, imported: true);
    await endFirstSync(tester);
    backupGate = Completer<void>();
    await tester.pump(kSeedImportSyncInterval);
    await settle(tester);
    expect(api.syncs, hasLength(1), reason: 'waiting on the backup marking');
    sync.handleAppHideForTesting();
    backupGate!.complete();
    await settle(tester);
    expect(api.syncs, hasLength(1));
    await done(tester);
  });

  testWidgets('another active account ends the window', (tester) async {
    await addAccount(tester, imported: true);
    await endFirstSync(tester);
    account.activate(_otherAccountUuid);
    await settle(tester);
    expect(sync.seedImportSyncWindowOpenForTesting, isFalse);
    await done(tester);
  });
}
