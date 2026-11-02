import 'package:zcash_wallet/src/core/storage/wallet_balance_cache.dart';
import 'package:zcash_wallet/src/providers/wallet_balance_cache_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/lifecycle/app_shutdown_signal.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/pending_activity_evidence_provider.dart';
import 'package:zcash_wallet/src/features/activity/activity_eta_provider.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  test(
    'unlock restores only selected cached balance without live reads',
    () async {
      final cached = CachedWalletBalance(
        _availableBalance(BigInt.from(75)),
        DateTime.utc(2026),
      );
      final cache = _TestBalanceCacheStore()..cached = cached;
      final notifier = _BalanceRefreshTestSyncNotifier(() async => 'wallet.db');
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => notifier),
          walletBalanceCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      await notifier.refreshAfterUnlock();
      final state = container.read(syncProvider).requireValue;
      expect(cache.loadedAccounts, [_accountUuid]);
      expect(notifier.balanceReadCount, 0);
      expect(state.hasDisplayBalance, isTrue);
      expect(state.hasBalanceData, isFalse);
      expect(state.hasRecentTransactionsData, isFalse);
      expect(state.displayShieldedBalance, BigInt.from(75));
      expect(state.spendableBalance, BigInt.zero);
      expect(state.orchardBalance, BigInt.zero);
      expect(state.isSyncComplete, isFalse);
      expect(state.hasSettledSpendableBalance, isFalse);
      expect(cache.saved, isEmpty);
    },
  );

  testWidgets(
    'cached snapshot survives a live read and Send waits for sync completion',
    (tester) async {
      final nativeSync = _SpendReadinessRustApiFake();
      RustLib.initMock(api: nativeSync);
      addTearDown(RustLib.dispose);
      final cached =
          SyncState(
            accountUuid: _accountUuid,
            isSyncing: true,
            scannedHeight: 50,
            chainTipHeight: 100,
          ).withCachedBalance(
            CachedWalletBalance(
              _availableBalance(BigInt.from(75)),
              DateTime.utc(2026),
            ),
          );
      final cache = _TestBalanceCacheStore();
      final notifier = _BalanceRefreshTestSyncNotifier(
        () async => 'wallet.db',
        initialState: cached,
      )..balance = _availableBalance(BigInt.zero);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => notifier),
          walletBalanceCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);

      notifier.refreshHomeInBackground();
      await tester.pump();
      final syncing = container.read(syncProvider).requireValue;
      expect(syncing.spendableBalance, BigInt.zero);
      expect(syncing.displaySpendableBalance, BigInt.from(75));
      expect(syncing.isUsingCompletedSpendableSnapshot, isTrue);
      expect(cache.saved, isEmpty);

      var operations = 0;
      final send = notifier.runWithAuthoritativeSpendable(
        accountUuid: _accountUuid,
        operation: () async {
          operations++;
          return container.read(syncProvider).requireValue.spendableBalance;
        },
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(operations, 0);

      nativeSync.running = false;
      notifier.replaceState(
        syncing.copyWith(
          isSyncing: false,
          isSyncComplete: true,
          scannedHeight: 100,
        ),
      );
      notifier.balance = _availableBalance(BigInt.from(100));
      final history = Completer<List<rust_sync.TransactionInfo>>();
      notifier.historyGate = history;
      notifier.refreshHomeInBackground();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(await send, BigInt.from(100));
      expect(operations, 1);
      final completed = container.read(syncProvider).requireValue;
      expect(completed.displaySpendableBalance, BigInt.from(100));
      expect(completed.hasSettledSpendableBalance, isTrue);
      expect(cache.saved.single.spendable, BigInt.from(100));
      expect(history.isCompleted, isFalse);
      history.complete([]);
      await tester.pump();
    },
  );

  for (final trigger in ['send', 'proposal release', 'account switch']) {
    test('cached snapshot honors explicit $trigger refresh', () async {
      final cached = SyncState(accountUuid: _accountUuid, isSyncing: true)
          .withCachedBalance(
            CachedWalletBalance(
              _availableBalance(BigInt.from(75)),
              DateTime.utc(2026),
            ),
          );
      final cache = _TestBalanceCacheStore();
      final notifier = _BalanceRefreshTestSyncNotifier(
        () async => 'wallet.db',
        initialState: cached,
      )..balance = _availableBalance(BigInt.from(25));
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => notifier),
          walletBalanceCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      await switch (trigger) {
        'send' => notifier.refreshAfterSend(),
        'proposal release' => notifier.refreshAfterProposalRelease(
          _accountUuid,
        ),
        _ => notifier.refreshAfterAccountSwitch(),
      };
      final current = container.read(syncProvider).requireValue;
      expect(current.isSyncing, isTrue);
      expect(current.spendableBalance, BigInt.from(25));
      expect(current.displaySpendableBalance, BigInt.from(25));
      expect(current.isUsingCompletedSpendableSnapshot, isFalse);
      expect(cache.saved.single.spendable, BigInt.from(25));
    });
  }

  testWidgets('interrupted refresh restores the previous disk snapshot', (
    tester,
  ) async {
    final savedBalance = _availableBalance(
      BigInt.from(75),
      orchardPending: BigInt.from(20),
    );
    final cache = _TestBalanceCacheStore()
      ..cached = CachedWalletBalance(savedBalance, DateTime.utc(2026));
    final notifier = _BalanceRefreshTestSyncNotifier(
      () async => 'wallet.db',
      initialState: SyncState(accountUuid: _accountUuid, isSyncing: true),
    )..balance = _availableBalance(BigInt.zero);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(() => notifier),
        walletBalanceCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    await container.read(syncProvider.future);
    await notifier.refreshAfterUnlock();
    notifier.refreshHomeInBackground();
    await tester.pump();
    expect(container.read(syncProvider).requireValue.totalBalance, BigInt.zero);
    expect(cache.saved, isEmpty);

    // Drop all in-memory balances, as lock/restart does, then restore from disk.
    notifier.replaceState(SyncState(accountUuid: _accountUuid));
    await notifier.refreshAfterUnlock();
    final restored = container.read(syncProvider).requireValue;
    expect(restored.displaySpendableBalance, BigInt.from(75));
    expect(restored.displayOrchardPendingBalance, BigInt.from(20));
    expect(restored.displayShieldedBalance, BigInt.from(95));
    expect(restored.displayTotalBalance, BigInt.from(95));
    expect(restored.hasBalanceData, isFalse);
  });

  for (final superseded in [false, true]) {
    for (final complete in [false, true]) {
      test(
        'progress cache write follows current completion (complete=$complete, superseded=$superseded)',
        () async {
          final cache = _TestBalanceCacheStore();
          final notifier = _BalanceRefreshTestSyncNotifier(
            () async => 'wallet.db',
            initialState:
                SyncState(
                  accountUuid: _accountUuid,
                  isSyncing: true,
                  scannedHeight: 50,
                  chainTipHeight: 100,
                ).withCachedBalance(
                  CachedWalletBalance(
                    _availableBalance(BigInt.from(75)),
                    DateTime.utc(2026),
                  ),
                ),
          )..balance = _availableBalance(BigInt.zero);
          final container = ProviderContainer(
            overrides: [
              appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
              accountProvider.overrideWith(_ExistingAccountNotifier.new),
              syncProvider.overrideWith(() => notifier),
              walletBalanceCacheProvider.overrideWithValue(cache),
            ],
          );
          addTearDown(container.dispose);
          addTearDown(notifier.stopTipChecksForTesting);
          await container.read(accountProvider.future);
          await container.read(syncProvider.future);
          if (superseded) notifier.gateFirstBalanceRead();
          final handling = notifier.handleSyncProgressForTesting(
            SyncProgressEvent(
              scannedHeight: complete ? 100 : 60,
              chainTipHeight: 100,
              percentage: complete ? 1 : 0.6,
              displayTargetPercentage: complete ? 1 : 0.6,
              displayTargetBlocks: 100,
              isSyncing: !complete,
              isComplete: complete,
              hasNewTx: true,
            ),
          );
          if (superseded) {
            await notifier.firstBalanceReadStarted;
            // A newer scan event wins over the older handler's metadata.
            await notifier.handleSyncProgressForTesting(
              const SyncProgressEvent(
                scannedHeight: 70,
                chainTipHeight: 110,
                percentage: 0.7,
                displayTargetPercentage: 0.7,
                displayTargetBlocks: 110,
                isSyncing: true,
                isComplete: false,
                hasNewTx: false,
              ),
            );
            notifier.releaseFirstBalanceRead();
          }
          await handling;
          final current = container.read(syncProvider).requireValue;
          expect(current.spendableBalance, BigInt.zero);
          if (complete && !superseded) {
            // A completed balance of zero is real and must replace the cache.
            expect(current.displaySpendableBalance, BigInt.zero);
            expect(cache.saved.single.spendable, BigInt.zero);
          } else {
            expect(current.displaySpendableBalance, BigInt.from(75));
            expect(cache.saved, isEmpty);
          }
        },
      );
    }
  }

  testWidgets('initial scan does not persist intermediate balances', (
    tester,
  ) async {
    final cache = _TestBalanceCacheStore();
    final notifier = _BalanceRefreshTestSyncNotifier(
      () async => 'wallet.db',
      initialState: SyncState(accountUuid: _accountUuid, isSyncing: true),
    )..balance = _availableBalance(BigInt.from(25));
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(() => notifier),
        walletBalanceCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    await container.read(syncProvider.future);
    notifier.refreshHomeInBackground();
    await tester.pump();
    expect(
      container.read(syncProvider).requireValue.displaySpendableBalance,
      BigInt.from(25),
    );
    expect(cache.saved, isEmpty);
  });

  for (final unavailable in [false, true]) {
    test(
      'live refresh publishes balance before history (unavailable=$unavailable)',
      () async {
        final history = Completer<List<rust_sync.TransactionInfo>>();
        final cache = _TestBalanceCacheStore();
        final cached = SyncState(accountUuid: _accountUuid).withCachedBalance(
          CachedWalletBalance(
            _availableBalance(BigInt.from(75)),
            DateTime.utc(2026),
          ),
        );
        final notifier =
            _BalanceRefreshTestSyncNotifier(
                () async => 'wallet.db',
                initialState: cached,
              )
              ..balance = unavailable
                  ? _unavailableBalance
                  : _availableBalance(BigInt.from(90));
        notifier.historyGate = history;
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            accountProvider.overrideWith(_ExistingAccountNotifier.new),
            syncProvider.overrideWith(() => notifier),
            walletBalanceCacheProvider.overrideWithValue(cache),
          ],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        await container.read(syncProvider.future);
        final refresh = notifier.refreshAfterSend();
        // Drain microtasks, leaving the deliberately blocked history unfinished.
        await Future<void>.delayed(Duration.zero);
        final state = container.read(syncProvider).requireValue;
        expect(state.hasRecentTransactionsData, isFalse);
        expect(
          state.displayShieldedBalance,
          BigInt.from(unavailable ? 75 : 90),
        );
        expect(state.hasCachedBalance, unavailable);
        expect(state.hasBalanceData, !unavailable);
        expect(cache.saved.length, unavailable ? 0 : 1);
        history.complete([]);
        await refresh;
        expect(
          container.read(syncProvider).requireValue.hasRecentTransactionsData,
          isTrue,
        );
      },
    );
  }

  for (final liveFinishesFirst in [false, true]) {
    test(
      'cache restore competes with a live read (live first=$liveFinishesFirst)',
      () async {
        final cache = _TestBalanceCacheStore()
          ..loadGate = Completer<CachedWalletBalance?>();
        final notifier = _BalanceRefreshTestSyncNotifier(
          () async => 'wallet.db',
        )..balance = _availableBalance(BigInt.from(90));
        if (!liveFinishesFirst) notifier.gateFirstBalanceRead();
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            accountProvider.overrideWith(_ExistingAccountNotifier.new),
            syncProvider.overrideWith(() => notifier),
            walletBalanceCacheProvider.overrideWithValue(cache),
          ],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        await container.read(syncProvider.future);
        final restore = notifier.refreshAfterUnlock();
        await Future<void>.delayed(Duration.zero);
        final refresh = notifier.refreshAfterSend();
        if (liveFinishesFirst) {
          await refresh;
        } else {
          await notifier.firstBalanceReadStarted;
        }
        cache.loadGate!.complete(
          CachedWalletBalance(
            _availableBalance(BigInt.from(75)),
            DateTime.utc(2026),
          ),
        );
        await restore;
        var state = container.read(syncProvider).requireValue;
        expect(
          state.displayShieldedBalance,
          BigInt.from(liveFinishesFirst ? 90 : 75),
        );
        expect(state.hasCachedBalance, !liveFinishesFirst);
        if (!liveFinishesFirst) {
          notifier.releaseFirstBalanceRead();
          await refresh;
        }
        state = container.read(syncProvider).requireValue;
        expect(state.hasCachedBalance, isFalse);
        expect(state.displayShieldedBalance, BigInt.from(90));
      },
    );
  }

  test('late disk cache cannot cross an account switch', () async {
    final cache = _TestBalanceCacheStore()
      ..loadGate = Completer<CachedWalletBalance?>();
    final notifier = _BalanceRefreshTestSyncNotifier(() async => 'wallet.db');
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(() => notifier),
        walletBalanceCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    await container.read(syncProvider.future);
    final restore = notifier.refreshAfterUnlock();
    await Future<void>.delayed(Duration.zero);
    (container.read(accountProvider.notifier) as _ExistingAccountNotifier)
        .activateForTest(_otherAccountUuid);
    cache.loadGate!.complete(
      CachedWalletBalance(
        _availableBalance(BigInt.from(75)),
        DateTime.utc(2026),
      ),
    );
    await restore;
    expect(
      container.read(syncProvider).requireValue.hasDisplayBalance,
      isFalse,
    );
  });

  test('cache writes coalesce and reset drains accepted I/O', () async {
    final cache = _WritingBalanceCacheStore();
    void accept(int amount) => cache.accept(
      dbPath: 'wallet.db',
      network: 'main',
      accountUuid: _accountUuid,
      balance: _availableBalance(BigInt.from(amount)),
    );
    accept(1);
    await cache.started.future;
    accept(2);
    accept(3);
    var drained = false;
    final drain = cache.suspendAndDrain().then((_) => drained = true);
    accept(4); // A reset has already suspended new work.
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    cache.release.complete();
    await drain;
    expect(cache.amounts, [BigInt.one]);
    cache.resume();
    accept(5);
    accept(6); // The not-yet-dispatched snapshot is replaced, in order.
    await Future<void>.delayed(Duration.zero);
    await cache.suspendAndDrain();
    cache.resume();
    expect(cache.amounts, [BigInt.one, BigInt.from(6)]);
  });

  test('cached balance decode tolerates damaged and future rows', () {
    expect(CachedWalletBalance.decode('{"version":2}'), isNull);
    expect(CachedWalletBalance.decode('broken'), isNull);
    final value = CachedWalletBalance(
      _availableBalance(BigInt.from(75)),
      DateTime.utc(2026),
    );
    final decoded = CachedWalletBalance.decode(value.encode())!;
    expect(decoded.balance, value.balance);
    expect(decoded.savedAt, value.savedAt);
    expect(
      CachedWalletBalance.decode(
        value.encode().replaceFirst('"orchard":"75"', '"orchard":"-1"'),
      ),
      isNull,
    );
  });

  test('checking belongs to global sync state across account carries', () {
    const checking = SyncCheckingProgress(
      cycle: 2,
      percentage: 0.25,
      displayTargetPercentage: 0.5,
    );
    final cached = SyncState(checking: checking);
    final normal = SyncState(isSyncing: true, percentage: 0.8);
    expect(cached.withGlobalSyncFieldsFrom(normal).checking, isNull);
    final current = normal.copyWith(checking: checking);
    expect(normal.withGlobalSyncFieldsFrom(current).checking, same(checking));
    expect(current.withoutAccountScopedData().checking, same(checking));
    expect(current.copyWith(clearChecking: true).isChecking, isFalse);
  });

  for (final fails in [false, true]) {
    testWidgets('resume coalesces an in-flight tip check (failure: $fails)', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 10, 6);
      final tipRead = Completer<BigInt>();
      var reads = 0;
      final rpc = _TipTestNotifier(() {
        reads++;
        return reads == 1 ? tipRead.future : Future.value(BigInt.from(100));
      });
      final sync = _PollingTestSyncNotifier();
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => sync),
          rpcEndpointFailoverProvider.overrideWith(() => rpc),
          chainUpgradeStatusProvider.overrideWith(_TipUpgradeNotifier.new),
          enhancePirProvider.overrideWith(_NoPrivateQueries.new),
          activityEtaClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      final evidence = container.read(pendingActivityEvidenceProvider.notifier);
      evidence.observe(accountUuid: _accountUuid, txids: ['pending']);
      evidence.networkChecked(100);
      final first = sync.checkTipForTesting();
      await tester.pump();
      expect(reads, 1);
      sync.handleAppHideForTesting();
      now = now.add(const Duration(seconds: 5));
      sync.handleAppResumeForTesting();
      sync.handleAppResumeForTesting();
      expect(
        container
            .read(pendingActivityEvidenceProvider)
            .labelFor(_accountUuid, 'pending', 100),
        'Est. 1–3 min',
      );
      if (fails) {
        tipRead.completeError(StateError('network connection refused'));
      } else {
        tipRead.complete(BigInt.from(100));
      }
      await first;
      await tester.pump();
      // Desktop can accept the ongoing request. Mobile must immediately
      // replace the read that crossed its background boundary, without 10s delay.
      expect(reads, fails || kAppFormFactor == AppFormFactor.mobile ? 2 : 1);
      expect(
        container
            .read(pendingActivityEvidenceProvider)
            .labelFor(_accountUuid, 'pending', 100),
        'Est. 1–3 min',
      );
      expect(
        container.read(pendingActivityEvidenceProvider).connectionFailed,
        isFalse,
      );
      expect(sync.startSyncs, 0);
      evidence.clear();
      sync.stopTipChecksForTesting();
    });
  }

  for (final forceRestart in [false, true]) {
    for (final resetBeforeResume in [false, true]) {
      testWidgets(
        'wallet mutation restart waits for foreground (forced: $forceRestart, reset: $resetBeforeResume)',
        (tester) async {
          final sync = _PollingTestSyncNotifier();
          final container = ProviderContainer(
            overrides: [
              appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
              accountProvider.overrideWith(_ExistingAccountNotifier.new),
              syncProvider.overrideWith(() => sync),
              rpcEndpointFailoverProvider.overrideWith(
                () => _TipTestNotifier(() async => BigInt.from(100)),
              ),
              chainUpgradeStatusProvider.overrideWith(_TipUpgradeNotifier.new),
              enhancePirProvider.overrideWith(_NoPrivateQueries.new),
            ],
          );
          addTearDown(container.dispose);
          await container.read(accountProvider.future);
          await container.read(syncProvider.future);
          sync.handleAppHideForTesting();
          // Model the last pause exiting after a configuration refresh. The
          // wallet was idle for a forced restart, or had work to resume.
          sync.resumeAfterWalletMutation(
            WalletMutationSyncPause(
              hadActiveSync: !forceRestart,
              hadPolling: false,
              hadMempoolObserver: false,
              resetEpoch: 0,
            ),
            forceRestart: forceRestart,
          );
          final mobile = kAppFormFactor == AppFormFactor.mobile;
          expect(sync.startSyncs, mobile ? 0 : 1);
          if (resetBeforeResume) sync.endWalletMutationPause();
          sync.handleAppResumeForTesting();
          await tester.pump();
          final expected = mobile && resetBeforeResume ? 0 : 1;
          expect(sync.startSyncs, expected);
          sync.handleAppResumeForTesting();
          await tester.pump();
          expect(
            sync.startSyncs,
            expected,
            reason: 'a deferred restart is consumed once',
          );
          sync.stopTipChecksForTesting();
        },
      );
    }
  }

  testWidgets('a resumed tip check discovers a new block and withdraws ETA', (
    tester,
  ) async {
    final sync = _PollingTestSyncNotifier();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(() => sync),
        rpcEndpointFailoverProvider.overrideWith(
          () => _TipTestNotifier(() async => BigInt.from(101)),
        ),
        chainUpgradeStatusProvider.overrideWith(_TipUpgradeNotifier.new),
        enhancePirProvider.overrideWith(_NoPrivateQueries.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    await container.read(syncProvider.future);
    final evidence = container.read(pendingActivityEvidenceProvider.notifier);
    evidence.observe(accountUuid: _accountUuid, txids: ['pending']);
    evidence.networkChecked(100);
    sync.handleAppHideForTesting();
    sync.handleAppResumeForTesting();
    await tester.pump();
    expect(sync.startSyncs, 1);
    expect(
      container
          .read(pendingActivityEvidenceProvider)
          .labelFor(_accountUuid, 'pending', 100),
      isNull,
    );
    evidence.clear();
    sync.stopTipChecksForTesting();
  });

  testWidgets(
    'desktop background tip checks can refresh evidence; mobile does no background query',
    (tester) async {
      var reads = 0;
      final sync = _PollingTestSyncNotifier();
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => sync),
          rpcEndpointFailoverProvider.overrideWith(
            () => _TipTestNotifier(() async {
              reads++;
              return BigInt.from(100);
            }),
          ),
          chainUpgradeStatusProvider.overrideWith(_TipUpgradeNotifier.new),
          enhancePirProvider.overrideWith(_NoPrivateQueries.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      final evidence = container.read(pendingActivityEvidenceProvider.notifier);
      evidence.observe(accountUuid: _accountUuid, txids: ['pending']);
      sync.handleAppHideForTesting();
      await sync.checkTipForTesting();
      expect(reads, kAppFormFactor == AppFormFactor.mobile ? 0 : 1);
      expect(
        container.read(pendingActivityEvidenceProvider).foreground,
        isFalse,
      );
      expect(
        container.read(pendingActivityEvidenceProvider).checkedTip,
        kAppFormFactor == AppFormFactor.mobile ? isNull : 100,
      );
      evidence.clear();
      sync.stopTipChecksForTesting();
    },
  );

  test(
    'history read failure suppresses ETA until history recovers even when tip polling succeeds',
    () async {
      final now = DateTime.utc(2026, 10, 6);
      final initial = SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        isSyncComplete: true,
        scannedHeight: 100,
        chainTipHeight: 100,
      );
      final sync = _BalanceRefreshTestSyncNotifier(
        () async => 'wallet.db',
        initialState: initial,
      )..balance = _availableBalance(BigInt.from(100));
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => sync),
          activityEtaClockProvider.overrideWithValue(() => now),
          giftCardActivityIndexProvider(
            _accountUuid,
          ).overrideWith((ref) async => GiftCardActivityIndex.empty),
          swapActivityRecordsProvider(
            _accountUuid,
          ).overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      await container.read(giftCardActivityIndexProvider(_accountUuid).future);
      await container.read(swapActivityRecordsProvider(_accountUuid).future);
      final evidence = container.read(pendingActivityEvidenceProvider.notifier);
      evidence.observe(accountUuid: _accountUuid, txids: ['pending']);
      evidence.networkChecked(100);
      expect(
        container.read(activityEtaLabelsProvider)['pending'],
        'Est. 1–3 min',
      );
      sync.failHistory = true;
      await sync.refreshAfterSend();
      evidence.networkChecked(100);
      expect(container.read(activityEtaLabelsProvider), isEmpty);
      sync.failHistory = false;
      await sync.refreshAfterSend();
      expect(
        container.read(activityEtaLabelsProvider)['pending'],
        'Est. 1–3 min',
      );
    },
  );

  test(
    'private status coverage pauses sync only while private queries stay on',
    () {
      final failure = classifySyncFailure('private status coverage incomplete');

      expect(
        shouldPauseSyncForPrivateStatusCoverage(
          failure: failure,
          privateQueriesEnabled: true,
        ),
        isTrue,
      );
      expect(
        shouldPauseSyncForPrivateStatusCoverage(
          failure: failure,
          privateQueriesEnabled: false,
        ),
        isFalse,
      );
      expect(
        shouldPauseSyncForPrivateStatusCoverage(
          failure: classifySyncFailure('network: unavailable'),
          privateQueriesEnabled: true,
        ),
        isFalse,
      );
    },
  );

  test(
    'exit gate rejects normal and forced sync starts before Rust dispatch',
    () async {
      final shutdown = AppShutdownSignal()..begin();
      final container = ProviderContainer(
        overrides: [
          appShutdownSignalProvider.overrideWithValue(shutdown),
          syncProvider.overrideWith(
            () => _LifecycleTestSyncNotifier(
              () async => throw StateError('must not resolve a DB during exit'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(shutdown.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      final notifier = container.read(syncProvider.notifier);
      notifier.startSync();
      await notifier.startSyncAnyway();
      expect(container.read(syncProvider).value!.isSyncing, isFalse);
    },
  );
  test('a busy network only aborts a restart that changes the route', () {
    // Switching to Tor with a direct channel still up would leak.
    expect(
      shouldAbortRestartForBusyNetwork(
        quiescent: false,
        changesTransport: true,
      ),
      isTrue,
    );
    // An endpoint change or post-broadcast refresh keeps the same transport,
    // so a slow teardown must not cost the session its sync and polling.
    expect(
      shouldAbortRestartForBusyNetwork(
        quiescent: false,
        changesTransport: false,
      ),
      isFalse,
    );
    expect(
      shouldAbortRestartForBusyNetwork(quiescent: true, changesTransport: true),
      isFalse,
    );
  });

  test('migration entry restarts a sync from an older foreground epoch', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: true,
        activeSyncForegroundEpoch: 2,
        currentForegroundEpoch: 3,
      ),
      isTrue,
    );
  });

  test('migration entry joins a sync started in the current foreground', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: true,
        activeSyncForegroundEpoch: 3,
        currentForegroundEpoch: 3,
      ),
      isFalse,
    );
  });

  test('migration entry restarts a sync that began in background', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: false,
        activeSyncForegroundEpoch: 3,
        currentForegroundEpoch: 3,
      ),
      isTrue,
    );
  });

  test(
    'clearCachedWalletDbPath forces the next DB path lookup to refresh',
    () async {
      final resolvedPaths = ['old-wallet.db', 'new-wallet.db'];
      var resolveCount = 0;
      final notifier = SyncNotifier(
        walletDbPathResolver: () async => resolvedPaths[resolveCount++],
      );

      expect(await notifier.resolveWalletDbPathForTesting(), 'old-wallet.db');
      expect(await notifier.resolveWalletDbPathForTesting(), 'old-wallet.db');
      expect(resolveCount, 1);

      notifier.clearCachedWalletDbPath();

      expect(await notifier.resolveWalletDbPathForTesting(), 'new-wallet.db');
      expect(resolveCount, 2);
    },
  );

  test('refreshAfterSend propagates DB path resolution failures', () async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => _BalanceRefreshTestSyncNotifier(
            () async => throw StateError('wallet path unavailable'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    await expectLater(
      container.read(syncProvider.notifier).refreshAfterSend(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'wallet path unavailable',
        ),
      ),
    );
  });

  test('successful queued refresh recovers an earlier pass failure', () async {
    final firstPathResolution = Completer<String>();
    var pathResolutionCount = 0;
    late _BalanceRefreshTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _BalanceRefreshTestSyncNotifier(() {
            pathResolutionCount++;
            if (pathResolutionCount == 1) return firstPathResolution.future;
            return Future.value('wallet.db');
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final firstRefresh = notifier.refreshAfterSend();
    final queuedRefresh = notifier.refreshAfterSend();
    firstPathResolution.completeError(StateError('temporary path failure'));

    await expectLater(Future.wait([firstRefresh, queuedRefresh]), completes);
    expect(pathResolutionCount, 2);
    expect(notifier.balanceReadCount, 1);
  });

  test('proposal release rejects an unavailable balance instead of accepting '
      'the locked snapshot', () async {
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => _BalanceRefreshTestSyncNotifier(() async => 'wallet.db'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    await expectLater(
      container
          .read(syncProvider.notifier)
          .refreshAfterProposalRelease(_accountUuid),
      throwsStateError,
    );
  });

  test(
    'release for an inactive account never reads the active account balance',
    () async {
      late _BalanceRefreshTestSyncNotifier notifier;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      await notifier.refreshAfterProposalRelease(_otherAccountUuid);
      expect(notifier.balanceReadCount, 0);
    },
  );

  test(
    'an ordinary queued refresh cannot hide an unavailable release balance',
    () async {
      late _BalanceRefreshTestSyncNotifier notifier;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      notifier.gateFirstBalanceRead();
      final release = notifier.refreshAfterProposalRelease(_accountUuid);
      final releaseExpectation = expectLater(release, throwsStateError);
      await notifier.firstBalanceReadStarted;
      final queued = notifier.refreshAfterSend();
      final queuedExpectation = expectLater(queued, throwsStateError);
      notifier.releaseFirstBalanceRead();
      await Future.wait([releaseExpectation, queuedExpectation]);
      expect(notifier.balanceReadCount, 2);
    },
  );

  test(
    'release queues a fresh balance read behind an older locked read',
    () async {
      late _BalanceRefreshTestSyncNotifier notifier;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      notifier.balance = _availableBalance(BigInt.zero);
      notifier.gateFirstBalanceRead();
      final stale = notifier.refreshAfterSend();
      await notifier.firstBalanceReadStarted;
      notifier.balance = _availableBalance(BigInt.from(160000));
      final released = notifier.refreshAfterProposalRelease(_accountUuid);
      notifier.releaseFirstBalanceRead();
      await Future.wait([stale, released]);

      expect(notifier.balanceReadCount, 2);
      final state = container.read(syncProvider).requireValue;
      expect(state.accountUuid, _accountUuid);
      expect(state.spendableBalance, BigInt.from(160000));
      expect(state.displaySpendableBalance, BigInt.from(160000));
      expect(
        state.displaySpendableFreshness,
        SpendableBalanceFreshness.authoritative,
      );
    },
  );

  test(
    'a successful ordinary trailing refresh releases the cancelled snapshot',
    () async {
      late _BalanceRefreshTestSyncNotifier notifier;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
              initialState: SyncState(
                accountUuid: _accountUuid,
                hasAccountScopedData: true,
                isSyncing: true,
                spendableBalance: BigInt.zero,
                displaySpendableBalance: BigInt.from(40),
                displaySpendableFreshness:
                    SpendableBalanceFreshness.lastCompletedSync,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      notifier.gateFirstBalanceRead();
      final release = notifier.refreshAfterProposalRelease(_accountUuid);
      await notifier.firstBalanceReadStarted;
      // The release's first read was unavailable. A normal resume refresh
      // queues behind it and obtains the authoritative post-unlock balance.
      notifier.balance = _availableBalance(BigInt.from(160000));
      final queued = notifier.refreshAfterSend();
      notifier.releaseFirstBalanceRead();
      await Future.wait([release, queued]);
      expect(notifier.balanceReadCount, 2);
      final state = container.read(syncProvider).requireValue;
      expect(state.spendableBalance, BigInt.from(160000));
      expect(state.displaySpendableBalance, BigInt.from(160000));
      expect(
        state.displaySpendableFreshness,
        SpendableBalanceFreshness.authoritative,
      );
    },
  );

  test(
    'an account switch during release refresh cannot publish the old balance',
    () async {
      late _BalanceRefreshTestSyncNotifier notifier;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      notifier.balance = _availableBalance(BigInt.from(160000));
      notifier.gateFirstBalanceRead();
      final released = notifier.refreshAfterProposalRelease(_accountUuid);
      await notifier.firstBalanceReadStarted;
      (container.read(accountProvider.notifier) as _ExistingAccountNotifier)
          .activateForTest(_otherAccountUuid);
      notifier.replaceState(
        SyncState(
          accountUuid: _otherAccountUuid,
          spendableBalance: BigInt.from(90),
        ),
      );
      notifier.releaseFirstBalanceRead();
      await released;

      final state = container.read(syncProvider).requireValue;
      expect(state.accountUuid, _otherAccountUuid);
      expect(state.spendableBalance, BigInt.from(90));
    },
  );

  test('in-flight progress exits quietly after notifier disposal', () async {
    final resolverStarted = Completer<void>();
    final dbPath = Completer<String>();
    late _LifecycleTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        syncProvider.overrideWith(
          () => notifier = _LifecycleTestSyncNotifier(() async {
            resolverStarted.complete();
            return dbPath.future;
          }),
        ),
      ],
    );
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final handling = notifier.handleSyncProgressForTesting(
      const SyncProgressEvent(
        scannedHeight: 10,
        chainTipHeight: 20,
        percentage: 0.5,
        displayTargetPercentage: 0.5,
        displayTargetBlocks: 0,
        isSyncing: true,
        isComplete: false,
        hasNewTx: false,
      ),
    );
    await resolverStarted.future;

    container.dispose();
    dbPath.complete('wallet.db');

    await expectLater(handling, completes);
  });

  test(
    'account-scoped state follows current pending work including unknown and empty',
    () {
      final cached = SyncState(
        accountUuid: _accountUuid,
        remainingScanBlocks: 2,
        pendingScanStartHeight: 99,
      );
      final active = SyncState(
        accountUuid: _otherAccountUuid,
        remainingScanBlocks: 102,
        pendingScanStartHeight: 1700,
      );
      final restored = cached.withGlobalSyncFieldsFrom(active);
      expect(restored.remainingScanBlocks, 102);
      expect(restored.pendingScanStartHeight, 1700);
      final scoped = restored.withoutAccountScopedData(
        accountUuid: _otherAccountUuid,
      );
      expect(scoped.remainingScanBlocks, 102);
      expect(scoped.pendingScanStartHeight, 1700);
      final unknown = restored.withGlobalSyncFieldsFrom(SyncState());
      expect(unknown.remainingScanBlocks, isNull);
      expect(unknown.pendingScanStartHeight, isNull);
      final empty = restored.withGlobalSyncFieldsFrom(
        SyncState(remainingScanBlocks: 0),
      );
      expect(empty.remainingScanBlocks, 0);
      expect(empty.pendingScanStartHeight, isNull);
    },
  );

  test('balance refresh preserves current pending scan work', () async {
    final notifier = _BalanceRefreshTestSyncNotifier(
      () async => 'wallet.db',
      initialState: SyncState(
        accountUuid: _accountUuid,
        isSyncing: true,
        remainingScanBlocks: 102,
        pendingScanStartHeight: 1700,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    await container.read(syncProvider.future);
    await notifier.refreshAfterSend();
    final current = container.read(syncProvider).requireValue;
    expect(current.remainingScanBlocks, 102);
    expect(current.pendingScanStartHeight, 1700);
  });

  test(
    'Checking retry preparation uses its own batch target and keeps stage during balance refresh',
    () async {
      final notifier = _BalanceRefreshTestSyncNotifier(
        () async => 'wallet.db',
        initialState: SyncState(
          accountUuid: _accountUuid,
          isSyncing: true,
          percentage: 1,
          scannedHeight: 150,
          chainTipHeight: 200,
          displayTargetBlocks: 100,
          checking: const SyncCheckingProgress(
            cycle: 1,
            percentage: 0.25,
            displayTargetPercentage: 0.5,
          ),
        ),
      )..balance = _availableBalance(BigInt.zero);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      await notifier.handleSyncProgressForTesting(
        const SyncProgressEvent(
          scannedHeight: 0,
          chainTipHeight: 200,
          percentage: 1,
          displayTargetPercentage: 1,
          displayTargetBlocks: 0,
          checking: SyncCheckingProgress(
            cycle: 1,
            percentage: 0.25,
            displayTargetPercentage: 0.25,
          ),
          isSyncing: true,
          isComplete: false,
          hasNewTx: false,
          phase: kSyncPhaseChainPrepare,
        ),
      );
      var current = container.read(syncProvider).requireValue;
      expect(current.checking!.cycle, 1);
      expect(current.scannedHeight, 150);
      expect(current.percentage, 1);
      expect(current.displayTargetBlocks, 0);
      await notifier.refreshAfterSend();
      current = container.read(syncProvider).requireValue;
      expect(current.checking!.percentage, 0.25);
    },
  );

  test('batch progress publishes one authoritative state', () async {
    late _LifecycleTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _LifecycleTestSyncNotifier(() async => 'wallet.db'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    var updates = 0;
    container.listen(syncProvider, (_, _) => updates++);

    await notifier.handleSyncProgressForTesting(
      const SyncProgressEvent(
        scannedHeight: 10,
        chainTipHeight: 100,
        percentage: 0.1,
        displayTargetPercentage: 0.2,
        displayTargetBlocks: 100,
        remainingScanBlocks: 90,
        pendingScanStartHeight: 11,
        isSyncing: true,
        isComplete: false,
        hasNewTx: false,
      ),
    );
    expect(updates, 1);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(updates, 1);
    final progress = container.read(syncProvider).requireValue;
    expect(progress.percentage, 0.1);
    expect(progress.remainingScanBlocks, 90);
    expect(progress.pendingScanStartHeight, 11);
  });

  test(
    'preparation progress preserves authoritative scan state on retry',
    () async {
      late _LifecycleTestSyncNotifier notifier;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () =>
                notifier = _LifecycleTestSyncNotifier(() async => 'wallet.db'),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      notifier.replaceState(
        SyncState(
          accountUuid: _accountUuid,
          isSyncing: true,
          percentage: 0.5,
          displayTargetPercentage: 0.6,
          displayTargetBlocks: 100,
          remainingScanBlocks: 2,
          pendingScanStartHeight: 99,
          scannedHeight: 50,
          chainTipHeight: 100,
        ),
      );

      await notifier.handleSyncProgressForTesting(
        const SyncProgressEvent(
          scannedHeight: 0,
          chainTipHeight: 120,
          percentage: 0,
          displayTargetPercentage: 0,
          displayTargetBlocks: 0,
          isSyncing: true,
          isComplete: false,
          hasNewTx: false,
          phaseCompletedUnits: 2,
          phaseTotalUnits: 4,
          phase: kSyncPhaseActiveUtxo,
        ),
      );

      final current = container.read(syncProvider).requireValue;
      expect(current.percentage, 0.5);
      expect(current.displayTargetPercentage, 0.6);
      expect(current.displayTargetBlocks, 100);
      expect(current.scannedHeight, 50);
      expect(current.chainTipHeight, 120);
      expect(current.phaseCompletedUnits, 2);
      expect(current.phaseTotalUnits, 4);
      expect(current.remainingScanBlocks, isNull);
      expect(current.pendingScanStartHeight, isNull);

      await notifier.handleSyncProgressForTesting(
        const SyncProgressEvent(
          scannedHeight: 0,
          chainTipHeight: 120,
          percentage: 0,
          displayTargetPercentage: 0,
          displayTargetBlocks: 0,
          isSyncing: true,
          isComplete: false,
          hasNewTx: false,
          phase: kSyncPhaseChainPrepare,
          remainingScanBlocks: 100,
          pendingScanStartHeight: 21,
        ),
      );
      final discovered = container.read(syncProvider).requireValue;
      expect(discovered.remainingScanBlocks, 100);
      expect(discovered.pendingScanStartHeight, 21);
    },
  );

  test('in-flight progress cannot replace a newer sync failure', () async {
    final resolverStarted = Completer<void>();
    final dbPath = Completer<String>();
    late _LifecycleTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _LifecycleTestSyncNotifier(() async {
            resolverStarted.complete();
            return dbPath.future;
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final handling = notifier.handleSyncProgressForTesting(
      const SyncProgressEvent(
        scannedHeight: 10,
        chainTipHeight: 100,
        percentage: 0,
        displayTargetPercentage: 0,
        displayTargetBlocks: 0,
        isSyncing: true,
        isComplete: false,
        hasNewTx: false,
      ),
    );
    await resolverStarted.future;

    final failure = classifySyncFailure(StateError('sync failed'));
    notifier.replaceState(
      SyncState(
        accountUuid: _accountUuid,
        failure: failure,
        error: failure.rawMessage,
        lastSyncFailedAt: DateTime.utc(2026, 7, 29),
      ),
    );
    dbPath.complete('wallet.db');
    await handling;

    final current = container.read(syncProvider).requireValue;
    expect(
      SyncStatusLabel.from(current).label,
      'Syncing failed. Unknown error...',
    );
    expect(current.failure, same(failure));
    expect(current.isSyncing, isFalse);
  });

  test(
    'unavailable switch balance clears balances but keeps fetched history',
    () async {
      final fetchedTx = _transaction('b' * 64);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => _UnavailableSwitchBalanceNotifier(fetchedTx),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);

      await container.read(syncProvider.notifier).refreshAfterAccountSwitch();

      final current = container.read(syncProvider).requireValue;
      expect(current.accountUuid, _accountUuid);
      expect(current.hasBalanceData, isFalse);
      expect(current.displaySpendableBalance, BigInt.zero);
      expect(current.displayOrchardBalance, BigInt.zero);
      expect(current.displayTotalBalance, BigInt.zero);
      expect(current.hasRecentTransactionsData, isTrue);
      expect(current.recentTransactions, [fetchedTx]);
    },
  );

  test(
    'unavailable switch balance evicts the restored account snapshot',
    () async {
      late _BalanceRefreshTestSyncNotifier notifier;
      final initial = SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        orchardBalance: BigInt.from(40),
        displayOrchardBalance: BigInt.from(40),
        spendableBalance: BigInt.from(40),
        displaySpendableBalance: BigInt.from(40),
        totalBalance: BigInt.from(40),
        displayTotalBalance: BigInt.from(40),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
              initialState: initial,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);

      // Cache account 1, then switch back to restore that cached snapshot.
      notifier.handleAccountSwitchForTesting(_otherAccountUuid);
      notifier.handleAccountSwitchForTesting(_accountUuid);
      expect(
        container.read(syncProvider).requireValue.displaySpendableBalance,
        BigInt.from(40),
      );

      await notifier.refreshAfterAccountSwitch();
      expect(
        container.read(syncProvider).requireValue.displaySpendableBalance,
        BigInt.zero,
      );

      // The cleared, incomplete state cannot overwrite the cache when leaving.
      // Switching back must therefore remain blank rather than restoring 40.
      notifier.handleAccountSwitchForTesting(_otherAccountUuid);
      notifier.handleAccountSwitchForTesting(_accountUuid);

      final current = container.read(syncProvider).requireValue;
      expect(current.accountUuid, _accountUuid);
      expect(current.hasBalanceData, isFalse);
      expect(current.displaySpendableBalance, BigInt.zero);
      expect(current.displayOrchardBalance, BigInt.zero);
      expect(current.displayTotalBalance, BigInt.zero);
    },
  );

  test('concurrent refresh triggers coalesce into one trailing pass', () async {
    // The defect this pins: switch, unlock, resume, mempool and recovery
    // each called `_refreshBalance` directly, so overlapping triggers ran
    // concurrent passes contending on the wallet DB. Behaviour assertions
    // pass either way — only the read count catches a regression.
    late _BalanceRefreshTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _BalanceRefreshTestSyncNotifier(
            () async => 'wallet.db',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);
    notifier.gateFirstBalanceRead();

    final inFlight = notifier.refreshAfterSend();
    await notifier.firstBalanceReadStarted;

    // Three more triggers arrive while that pass is still reading.
    final queued = [
      notifier.refreshAfterSend(),
      notifier.refreshAfterSend(),
      notifier.refreshAfterSend(),
    ];
    notifier.releaseFirstBalanceRead();
    await Future.wait([inFlight, ...queued]);

    expect(
      notifier.balanceReadCount,
      2,
      reason:
          'the in-flight pass plus one trailing pass covering all three '
          'queued triggers; without coalescing this is 4',
    );
  });

  test(
    'a switch refresh queued mid-flight still clears the restored snapshot',
    () async {
      // Queued triggers are collapsed into one trailing pass, so that
      // pass must carry every requesting caller's flags. If the switch's
      // clear-on-unavailable request is dropped by the queue, the stale
      // restored balance stays pinned on screen.
      final fetchedTx = _transaction('c' * 64);
      late _BalanceRefreshTestSyncNotifier notifier;
      final restored = SyncState(
        accountUuid: _accountUuid,
        hasAccountScopedData: true,
        orchardBalance: BigInt.from(40),
        displayOrchardBalance: BigInt.from(40),
        spendableBalance: BigInt.from(40),
        displaySpendableBalance: BigInt.from(40),
        displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
        totalBalance: BigInt.from(40),
        displayTotalBalance: BigInt.from(40),
        recentTransactions: [_transaction('a' * 64)],
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(_ExistingAccountNotifier.new),
          syncProvider.overrideWith(
            () => notifier = _BalanceRefreshTestSyncNotifier(
              () async => 'wallet.db',
              initialState: restored,
              history: [fetchedTx],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncProvider, (_, _) {});
      await container.read(syncProvider.future);
      notifier.gateFirstBalanceRead();

      // An unrelated refresh occupies the single-flight slot first.
      final inFlight = notifier.refreshAfterSend();
      await notifier.firstBalanceReadStarted;
      final switchRefresh = notifier.refreshAfterAccountSwitch();
      notifier.releaseFirstBalanceRead();
      await Future.wait([inFlight, switchRefresh]);

      final current = container.read(syncProvider).requireValue;
      expect(current.hasBalanceData, isFalse);
      expect(current.displaySpendableBalance, BigInt.zero);
      expect(current.displayOrchardBalance, BigInt.zero);
      expect(current.displayTotalBalance, BigInt.zero);
      expect(current.recentTransactions, [fetchedTx]);
    },
  );
}

class _SpendReadinessRustApiFake implements RustLibApi {
  bool running = true;

  @override
  bool crateApiSyncIsSyncRunning() => running;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LifecycleTestSyncNotifier extends SyncNotifier {
  _LifecycleTestSyncNotifier(Future<String> Function() walletDbPathResolver)
    : super(walletDbPathResolver: walletDbPathResolver);

  @override
  Future<SyncState> build() async => SyncState();

  void replaceState(SyncState next) {
    state = AsyncData(next);
  }
}

class _BalanceRefreshTestSyncNotifier extends SyncNotifier {
  _BalanceRefreshTestSyncNotifier(
    Future<String> Function() walletDbPathResolver, {
    this.initialState,
    this.history = const [],
  }) : super(walletDbPathResolver: walletDbPathResolver);

  final SyncState? initialState;
  final List<rust_sync.TransactionInfo> history;

  Completer<List<rust_sync.TransactionInfo>>? historyGate;
  bool failHistory = false;
  var balanceReadCount = 0;
  rust_sync.WalletBalance? balance;

  void replaceState(SyncState next) => state = AsyncData(next);

  var _gateFirstBalanceRead = false;
  final _firstBalanceReadStarted = Completer<void>();
  final _firstBalanceReadReleased = Completer<void>();

  /// Hold the next balance read open so further refresh triggers arrive
  /// while a pass is genuinely in flight.
  void gateFirstBalanceRead() => _gateFirstBalanceRead = true;

  Future<void> get firstBalanceReadStarted => _firstBalanceReadStarted.future;

  void releaseFirstBalanceRead() => _firstBalanceReadReleased.complete();

  @override
  Future<SyncState> build() async => initialState ?? SyncState();

  @override
  Future<rust_sync.WalletBalance> readWalletBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    balanceReadCount++;
    final result = balance ?? _unavailableBalance;
    if (_gateFirstBalanceRead && !_firstBalanceReadStarted.isCompleted) {
      _firstBalanceReadStarted.complete();
      await _firstBalanceReadReleased.future;
    }
    return result;
  }

  @override
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async {
    if (failHistory) throw StateError('history read unavailable');
    return historyGate?.future ?? Future.value(history);
  }
}

class _UnavailableSwitchBalanceNotifier extends SyncNotifier {
  _UnavailableSwitchBalanceNotifier(this.fetchedTx)
    : super(walletDbPathResolver: () async => 'wallet.db');

  final rust_sync.TransactionInfo fetchedTx;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _accountUuid,
    hasAccountScopedData: true,
    orchardBalance: BigInt.from(40),
    displayOrchardBalance: BigInt.from(40),
    spendableBalance: BigInt.from(40),
    displaySpendableBalance: BigInt.from(40),
    displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
    totalBalance: BigInt.from(40),
    displayTotalBalance: BigInt.from(40),
    recentTransactions: [_transaction('a' * 64)],
  );

  @override
  Future<rust_sync.WalletBalance> readWalletBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async => _unavailableBalance;

  @override
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) async => [fetchedTx];
}

const _accountUuid = 'account-1';
const _otherAccountUuid = 'account-2';

class _ExistingAccountNotifier extends AccountNotifier {
  void activateForTest(String accountUuid) {
    state = AsyncData(
      state.requireValue.copyWith(activeAccountUuid: accountUuid),
    );
  }

  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
  );
}

rust_sync.WalletBalance _availableBalance(
  BigInt amount, {
  BigInt? orchardPending,
}) => rust_sync.WalletBalance(
  availability: rust_sync.WalletBalanceAvailability.available,
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
  orchardPending: orchardPending ?? BigInt.zero,
  ironwoodPending: BigInt.zero,
  changePendingConfirmation: BigInt.zero,
  valuePendingSpendability: BigInt.zero,
  uneconomicValue: BigInt.zero,
  spendable: amount,
  locked: BigInt.zero,
  total: amount + (orchardPending ?? BigInt.zero),
);

final _unavailableBalance = rust_sync.WalletBalance(
  availability: rust_sync.WalletBalanceAvailability.summaryUnavailable,
  transparentAuthority: rust_sync.TransparentBalanceAuthority.current,
  transparentPrivate: false,
  transparent: BigInt.zero,
  sapling: BigInt.zero,
  orchard: BigInt.zero,
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
  spendable: BigInt.zero,
  locked: BigInt.zero,
  total: BigInt.zero,
);

rust_sync.TransactionInfo _transaction(String txidHex) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.one,
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    feeState: rust_sync.TransactionFeeState.notApplicable,
    detailsComplete: true,
    provisional: false,
    amountIncludesFee: false,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.one,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

class _TipTestNotifier extends RpcEndpointFailoverNotifier {
  _TipTestNotifier(this.readTip);
  final Future<BigInt> Function() readTip;
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );
  @override
  Future<BigInt> getLatestBlockHeight() => readTip();
}

class _TipUpgradeNotifier extends ChainUpgradeStatusNotifier {
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

class _PollingTestSyncNotifier extends _BalanceRefreshTestSyncNotifier {
  _PollingTestSyncNotifier()
    : super(
        () async => 'wallet.db',
        initialState: SyncState(
          accountUuid: _accountUuid,
          hasAccountScopedData: true,
          isSyncComplete: true,
          scannedHeight: 100,
          chainTipHeight: 100,
        ),
      );
  @override
  Future<SyncState> build() async {
    ref.onDispose(stopTipChecksForTesting);
    return super.build();
  }

  int startSyncs = 0;
  @override
  void startSync({int? latestTipHeight}) {
    startSyncs++;
  }
}

class _TestBalanceCacheStore extends WalletBalanceCacheStore {
  CachedWalletBalance? cached;
  Completer<CachedWalletBalance?>? loadGate;
  final loadedAccounts = <String>[];
  final saved = <rust_sync.WalletBalance>[];

  @override
  Future<CachedWalletBalance?> load({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) async {
    loadedAccounts.add(accountUuid);
    return loadGate?.future ?? Future.value(cached);
  }

  @override
  void accept({
    required String dbPath,
    required String network,
    required String accountUuid,
    required rust_sync.WalletBalance balance,
  }) {
    saved.add(balance);
    cached = CachedWalletBalance.decode(
      CachedWalletBalance(balance, DateTime.utc(2026)).encode(),
    );
  }
}

class _WritingBalanceCacheStore extends WalletBalanceCacheStore {
  final started = Completer<void>();
  final release = Completer<void>();
  final amounts = <BigInt>[];

  @override
  Future<void> write(
    String dbPath,
    String network,
    String uuid,
    String payload,
  ) async {
    amounts.add(CachedWalletBalance.decode(payload)!.balance.total);
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
  }
}
