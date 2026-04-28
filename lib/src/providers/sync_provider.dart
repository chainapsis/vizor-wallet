import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/storage/wallet_paths.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/wallet.dart' as rust_wallet;
import '../services/background_sync_delegate.dart';
import 'account_provider.dart';
import 'app_security_provider.dart';

class SyncState {
  final bool isSyncing;
  final bool isBackgroundMode;
  final double percentage;
  final int scannedHeight;
  final int chainTipHeight;
  final BigInt transparentBalance;
  final BigInt saplingBalance;
  final BigInt orchardBalance;
  final BigInt transparentPendingBalance;
  final BigInt saplingPendingBalance;
  final BigInt orchardPendingBalance;
  final bool canShieldTransparentBalance;
  final BigInt shieldTransparentFee;
  final BigInt shieldTransparentAmount;

  /// Spendable shielded balance. Use for "available to send".
  final BigInt spendableBalance;

  /// Sum of spendable + pending balances across all pools. Use for "total holdings".
  final BigInt totalBalance;
  final String? error;
  final List<rust_sync.TransactionInfo> recentTransactions;
  final DateTime? lastSyncStartedAt;
  final DateTime? lastSyncCompletedAt;
  final DateTime? lastSyncFailedAt;

  /// Current sync phase: `"download"`, `"scan"`, `"enhance"`, or
  /// empty. Widgets can use this to show e.g. "Downloading..."
  /// instead of a bare percentage.
  final String phase;

  /// Amount waiting for confirmations (e.g. change from a recently sent tx).
  BigInt get pendingBalance =>
      transparentPendingBalance + saplingPendingBalance + orchardPendingBalance;

  SyncState({
    this.isSyncing = false,
    this.isBackgroundMode = false,
    this.percentage = 0,
    this.scannedHeight = 0,
    this.chainTipHeight = 0,
    BigInt? transparentBalance,
    BigInt? saplingBalance,
    BigInt? orchardBalance,
    BigInt? transparentPendingBalance,
    BigInt? saplingPendingBalance,
    BigInt? orchardPendingBalance,
    this.canShieldTransparentBalance = false,
    BigInt? shieldTransparentFee,
    BigInt? shieldTransparentAmount,
    BigInt? spendableBalance,
    BigInt? totalBalance,
    this.error,
    this.recentTransactions = const [],
    this.lastSyncStartedAt,
    this.lastSyncCompletedAt,
    this.lastSyncFailedAt,
    this.phase = '',
  }) : transparentBalance = transparentBalance ?? BigInt.zero,
       saplingBalance = saplingBalance ?? BigInt.zero,
       orchardBalance = orchardBalance ?? BigInt.zero,
       transparentPendingBalance = transparentPendingBalance ?? BigInt.zero,
       saplingPendingBalance = saplingPendingBalance ?? BigInt.zero,
       orchardPendingBalance = orchardPendingBalance ?? BigInt.zero,
       shieldTransparentFee = shieldTransparentFee ?? BigInt.zero,
       shieldTransparentAmount = shieldTransparentAmount ?? BigInt.zero,
       spendableBalance = spendableBalance ?? BigInt.zero,
       totalBalance = totalBalance ?? BigInt.zero;

  SyncState copyWith({
    bool? isSyncing,
    bool? isBackgroundMode,
    double? percentage,
    int? scannedHeight,
    int? chainTipHeight,
    BigInt? transparentBalance,
    BigInt? saplingBalance,
    BigInt? orchardBalance,
    BigInt? transparentPendingBalance,
    BigInt? saplingPendingBalance,
    BigInt? orchardPendingBalance,
    bool? canShieldTransparentBalance,
    BigInt? shieldTransparentFee,
    BigInt? shieldTransparentAmount,
    BigInt? spendableBalance,
    BigInt? totalBalance,
    String? error,
    List<rust_sync.TransactionInfo>? recentTransactions,
    DateTime? lastSyncStartedAt,
    DateTime? lastSyncCompletedAt,
    DateTime? lastSyncFailedAt,
    String? phase,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      isBackgroundMode: isBackgroundMode ?? this.isBackgroundMode,
      percentage: percentage ?? this.percentage,
      scannedHeight: scannedHeight ?? this.scannedHeight,
      chainTipHeight: chainTipHeight ?? this.chainTipHeight,
      transparentBalance: transparentBalance ?? this.transparentBalance,
      saplingBalance: saplingBalance ?? this.saplingBalance,
      orchardBalance: orchardBalance ?? this.orchardBalance,
      transparentPendingBalance:
          transparentPendingBalance ?? this.transparentPendingBalance,
      saplingPendingBalance:
          saplingPendingBalance ?? this.saplingPendingBalance,
      orchardPendingBalance:
          orchardPendingBalance ?? this.orchardPendingBalance,
      canShieldTransparentBalance:
          canShieldTransparentBalance ?? this.canShieldTransparentBalance,
      shieldTransparentFee: shieldTransparentFee ?? this.shieldTransparentFee,
      shieldTransparentAmount:
          shieldTransparentAmount ?? this.shieldTransparentAmount,
      spendableBalance: spendableBalance ?? this.spendableBalance,
      totalBalance: totalBalance ?? this.totalBalance,
      error: error ?? this.error,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      lastSyncStartedAt: lastSyncStartedAt ?? this.lastSyncStartedAt,
      lastSyncCompletedAt: lastSyncCompletedAt ?? this.lastSyncCompletedAt,
      lastSyncFailedAt: lastSyncFailedAt ?? this.lastSyncFailedAt,
      phase: phase ?? this.phase,
    );
  }
}

class WalletMutationSyncPause {
  final bool hadActiveSync;
  final bool hadPolling;
  final bool hadBackgroundSync;
  final bool hadMempoolObserver;

  const WalletMutationSyncPause({
    required this.hadActiveSync,
    required this.hadPolling,
    required this.hadBackgroundSync,
    required this.hadMempoolObserver,
  });

  bool get hadWorkToPause =>
      hadActiveSync || hadPolling || hadBackgroundSync || hadMempoolObserver;
}

class SyncNotifier extends AsyncNotifier<SyncState> {
  late final BackgroundSyncDelegate _bgDelegate;
  bool _isSyncing = false;
  bool _isInForeground = true;
  int _lastLoggedHeight = 0;
  int _syncGen = 0; // incremented by stopSync to invalidate pending startSync
  String? _cachedDbPath;
  StreamSubscription? _syncSub;
  AppLifecycleListener? _lifecycleListener;
  Timer? _pollTimer;
  bool _pollCheckInFlight = false;
  int _sensitiveStateEpoch = 0;
  // Mempool observer subscription. Started in `startSync` and
  // cancelled in `stopSync`, so its lifetime matches the
  // foreground-sync lifetime even though the Rust side manages
  // the two cancel flags independently. A dedicated generation
  // counter isn't needed because the observer keeps running until
  // we explicitly cancel it — the Rust `MEMPOOL_CANCEL` flag is
  // what actually stops it, and `_mempoolSub` is just the Dart
  // side of the corresponding stream.
  StreamSubscription? _mempoolSub;

  @override
  Future<SyncState> build() async {
    final bootstrap = ref.watch(appBootstrapProvider);
    _bgDelegate = BackgroundSyncDelegate.create();
    _bgDelegate.setupListeners(
      onStopRequested: () => stopSync(),
      onBackgroundProgress: (event) {
        _onSyncProgress(event).catchError((e, st) {
          log('SyncNotifier: background progress handling failed: $e');
        });
      },
    );

    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _isInForeground = true;
        _refreshBalance();
        _bgDelegate.onResume();
        _checkAndSync();
      },
      onHide: () {
        _isInForeground = false;
        _stopPolling();
      },
    );

    ref.onDispose(() {
      rust_sync.cancelFullSync();
      _syncSub?.cancel();
      _mempoolSub?.cancel();
      // Cancel the Rust-side observer too; cancelling the Dart
      // subscription alone leaves the tonic stream task alive
      // until the Rust isolate pool tears it down.
      rust_sync.stopMempoolObserver();
      _bgDelegate.disposeListeners();
      _lifecycleListener?.dispose();
      _pollTimer?.cancel();
    });

    // Auto-start sync on account changes.
    // Uses ref.listen (not ref.watch) to avoid rebuilding SyncNotifier on every
    // account state change (switch, rename), which would cancel active sync and
    // reset UI state.
    //
    // Two cases:
    // 1. First account created (0→1): start sync + polling.
    // 2. Additional account added (N→N+1): start sync to rescan from new
    //    account's birthday height. Rust sync loop picks up new ranges via
    //    suggest_scan_ranges() even mid-sync; _isSyncing guard prevents duplicates.
    ref.listen(accountProvider, (prev, next) {
      final prevCount = prev?.value?.accounts.length ?? 0;
      final nextCount = next.value?.accounts.length ?? 0;
      if (nextCount > prevCount) {
        startSync();
        _startPolling();
      }
    });

    // Initial check: if accounts already exist at build time
    final accountState = ref.read(accountProvider).value;
    if (accountState != null && accountState.hasAccounts) {
      Future(() {
        unawaited(_startInitialSync());
      });
    }

    final initial = bootstrap.initialSyncSnapshot;
    return SyncState(
      isSyncing: false,
      isBackgroundMode: false,
      percentage: initial.percentage,
      scannedHeight: initial.scannedHeight,
      chainTipHeight: initial.chainTipHeight,
      transparentBalance: initial.transparentBalance,
      saplingBalance: initial.saplingBalance,
      orchardBalance: initial.orchardBalance,
      transparentPendingBalance: initial.transparentPendingBalance,
      saplingPendingBalance: initial.saplingPendingBalance,
      orchardPendingBalance: initial.orchardPendingBalance,
      canShieldTransparentBalance: initial.canShieldTransparentBalance,
      shieldTransparentFee: initial.shieldTransparentFee,
      shieldTransparentAmount: initial.shieldTransparentAmount,
      spendableBalance: initial.spendableBalance,
      totalBalance: initial.totalBalance,
      recentTransactions: initial.recentTransactions,
      phase: '',
    );
  }

  // ======================== Sync Control ========================

  Future<void> _startInitialSync() async {
    final epoch = _sensitiveStateEpoch;
    final staleSyncRunning = _syncSub == null && rust_sync.isSyncRunning();
    final staleMempoolRunning =
        _mempoolSub == null && rust_sync.isMempoolObserverRunning();

    if (staleSyncRunning || staleMempoolRunning) {
      if (staleSyncRunning) {
        log('Sync: cancelling stale Rust sync before startup');
        rust_sync.cancelFullSync();
      }
      if (staleMempoolRunning) {
        log('Mempool: stopping stale observer before startup');
        rust_sync.stopMempoolObserver();
      }

      var waited = 0;
      while ((rust_sync.isSyncRunning() ||
              rust_sync.isMempoolObserverRunning()) &&
          waited < 30000) {
        await Future.delayed(const Duration(milliseconds: 100));
        waited += 100;
      }
      if (rust_sync.isSyncRunning()) {
        log(
          'Sync: timed out waiting for stale Rust sync to stop after 30s; '
          'startup sync will rely on running-guard recovery',
        );
      }
      if (rust_sync.isMempoolObserverRunning()) {
        log(
          'Mempool: timed out waiting for stale observer to stop after 30s; '
          'startup observer will rely on running-guard recovery',
        );
      }
    }

    if (epoch != _sensitiveStateEpoch || _requiresUnlock) {
      log('Sync: skipping initial sync after lock transition');
      return;
    }
    startSync();
    _startPolling();
  }

  /// Fire-and-forget: sets up FRB stream and returns immediately.
  /// Stream events update state via _onSyncProgress. Completion handled by _onSyncDone.
  void startSync() {
    if (_requiresUnlock) {
      log('Sync: locked, skipping foreground sync start');
      return;
    }
    if (_isSyncing || rust_sync.isSyncRunning()) {
      log('Sync: already running, skipping');
      return;
    }
    _isSyncing = true;
    _lastLoggedHeight = 0;
    final gen = ++_syncGen;
    final prev = state.value;
    final startedAt = DateTime.now();
    state = AsyncData(
      SyncState(
        isSyncing: true,
        isBackgroundMode: false,
        percentage: 0.0,
        scannedHeight: prev?.scannedHeight ?? 0,
        chainTipHeight: prev?.chainTipHeight ?? 0,
        transparentBalance: prev?.transparentBalance,
        saplingBalance: prev?.saplingBalance,
        orchardBalance: prev?.orchardBalance,
        transparentPendingBalance: prev?.transparentPendingBalance,
        saplingPendingBalance: prev?.saplingPendingBalance,
        orchardPendingBalance: prev?.orchardPendingBalance,
        canShieldTransparentBalance: prev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: prev?.shieldTransparentFee,
        shieldTransparentAmount: prev?.shieldTransparentAmount,
        spendableBalance: prev?.spendableBalance,
        totalBalance: prev?.totalBalance,
        recentTransactions: prev?.recentTransactions ?? const [],
        lastSyncStartedAt: startedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
        phase: '',
      ),
    );

    _getDbPath()
        .then((dbPath) {
          if (gen != _syncGen) return; // stopSync was called, abort
          final network = ZcashNetwork.mainnet;
          log('Sync: starting foreground sync');
          // Fire up the mempool observer alongside the scan loop.
          // It has its own Rust cancel flag (MEMPOOL_CANCEL) and runs
          // on a separate tokio runtime, so it can accept events while
          // the scan loop is still catching up on old blocks.
          _startMempoolObserver(dbPath, network);
          final stream = rust_sync.startFullSync(
            dbPath: dbPath,
            lightwalletdUrl: network.lightwalletdUrl,
            network: network.name,
            mode: 1,
          );
          _syncSub = stream.listen(
            (event) => _onSyncProgress(
              SyncProgressEvent(
                scannedHeight: event.scannedHeight.toInt(),
                chainTipHeight: event.chainTipHeight.toInt(),
                percentage: event.percentage,
                isSyncing: event.isSyncing,
                isComplete: event.isComplete,
                hasNewTx: event.hasNewTx,
                phase: event.phase,
              ),
            ),
            onDone: () {
              log('Sync: stream ended');
              _syncSub = null;
              // Normal completion (isComplete=true) is handled inside
              // _onSyncProgress, which clears _isSyncing and starts
              // polling. But the stream can also end WITHOUT an
              // isComplete event — specifically when Rust exits because
              // DESIRED_SYNC_MODE changed (foreground→background
              // handoff via enableBackgroundSync). In that case
              // _isSyncing is still true and the mempool observer is
              // still running, both of which block future startSync()
              // calls. Clean up unconditionally here; if isComplete
              // already ran, these are no-ops.
              if (_isSyncing) {
                log('Sync: stream ended without isComplete, cleaning up');
                _isSyncing = false;
                _stopMempoolObserver();
              }
            },
            onError: (e) {
              if (gen != _syncGen) return;
              log('Sync: stream error: $e');
              _isSyncing = false;
              // Sync died mid-stream: tear the mempool observer down
              // at the same time so a failed sync session can't leak
              // a lightwalletd stream that keeps firing
              // `_refreshBalance()` callbacks with no owning sync.
              _stopMempoolObserver();
              final prev = state.value;
              state = AsyncData(
                SyncState(
                  error: e.toString(),
                  transparentBalance: prev?.transparentBalance,
                  saplingBalance: prev?.saplingBalance,
                  orchardBalance: prev?.orchardBalance,
                  transparentPendingBalance: prev?.transparentPendingBalance,
                  saplingPendingBalance: prev?.saplingPendingBalance,
                  orchardPendingBalance: prev?.orchardPendingBalance,
                  canShieldTransparentBalance:
                      prev?.canShieldTransparentBalance ?? false,
                  shieldTransparentFee: prev?.shieldTransparentFee,
                  shieldTransparentAmount: prev?.shieldTransparentAmount,
                  spendableBalance: prev?.spendableBalance,
                  totalBalance: prev?.totalBalance,
                  recentTransactions: prev?.recentTransactions ?? const [],
                  lastSyncStartedAt: prev?.lastSyncStartedAt,
                  lastSyncCompletedAt: prev?.lastSyncCompletedAt,
                  lastSyncFailedAt: DateTime.now(),
                ),
              );
              _startPolling();
            },
          );
        })
        .catchError((e, st) {
          if (gen != _syncGen) return;
          log('SyncNotifier: ERROR: $e\n$st');
          _isSyncing = false;
          // Sync setup threw before the stream was ever attached.
          // We may have already started the mempool observer
          // (happens on the main success path just before
          // `startFullSync`), so always call
          // `_stopMempoolObserver()` here; it is idempotent when
          // nothing is running.
          _stopMempoolObserver();
          final prev = state.value;
          state = AsyncData(
            SyncState(
              error: e.toString(),
              transparentBalance: prev?.transparentBalance,
              saplingBalance: prev?.saplingBalance,
              orchardBalance: prev?.orchardBalance,
              transparentPendingBalance: prev?.transparentPendingBalance,
              saplingPendingBalance: prev?.saplingPendingBalance,
              orchardPendingBalance: prev?.orchardPendingBalance,
              canShieldTransparentBalance:
                  prev?.canShieldTransparentBalance ?? false,
              shieldTransparentFee: prev?.shieldTransparentFee,
              shieldTransparentAmount: prev?.shieldTransparentAmount,
              spendableBalance: prev?.spendableBalance,
              totalBalance: prev?.totalBalance,
              recentTransactions: prev?.recentTransactions ?? const [],
              lastSyncStartedAt: prev?.lastSyncStartedAt,
              lastSyncCompletedAt: prev?.lastSyncCompletedAt,
              lastSyncFailedAt: DateTime.now(),
            ),
          );
          _startPolling();
        });
  }

  /// Recovery path for cases like unlock-after-sign-out where a previous
  /// sync has already been cancelled, but Rust is still unwinding.
  Future<void> startSyncAnyway() async {
    if (_requiresUnlock) {
      log('Sync: locked, skipping forced foreground sync start');
      return;
    }
    if (_syncSub != null || _isSyncing) {
      log('Sync: foreground sync already attached, skipping forced start');
      return;
    }

    final rustRunning = rust_sync.isSyncRunning();
    final cancelRequested = rust_sync.isSyncCancelRequested();
    final staleMempoolRunning =
        _mempoolSub == null && rust_sync.isMempoolObserverRunning();
    if (staleMempoolRunning) {
      log(
        'Mempool: stale observer still running, stopping before foreground restart',
      );
      rust_sync.stopMempoolObserver();
    }
    if ((rustRunning && cancelRequested) || staleMempoolRunning) {
      log(
        'Sync: cancelled Rust tasks still running, waiting before foreground '
        'restart',
      );
      final stopped = await _waitForRustTasksToStop(
        timeoutMs: 5000,
        onSyncTimeout:
            'SyncNotifier: startSyncAnyway timed out waiting for cancelled '
            'Rust sync to stop after 5s; keeping polling active for retry',
        onMempoolTimeout:
            'SyncNotifier: startSyncAnyway timed out waiting for mempool '
            'observer to stop after 5s; keeping polling active for retry',
      );
      if (!stopped) {
        _startPolling();
        return;
      }
    } else if (rustRunning) {
      log('Sync: already running, skipping forced foreground restart');
      return;
    }

    startSync();
    _startPolling();
  }

  void stopSync() {
    ++_syncGen; // invalidate pending startSync callbacks
    rust_sync.cancelFullSync();
    _syncSub?.cancel();
    _syncSub = null;
    // Tear the mempool observer down at the same time. The sync
    // loop and the observer have independent Rust cancel flags
    // (SYNC_CANCEL / MEMPOOL_CANCEL), but Dart pairs them so the
    // UX invariant "no sync running → no mempool stream running"
    // holds, which is what the iOS background-sync / battery
    // budget story expects.
    _stopMempoolObserver();
    _isSyncing = false;
    _stopPolling();
    if (_bgDelegate.isActive) {
      _bgDelegate.disable();
    }
    final prev = state.value;
    state = AsyncData(
      SyncState(
        isSyncing: false,
        isBackgroundMode: false,
        percentage: prev?.percentage ?? 0.0,
        scannedHeight: prev?.scannedHeight ?? 0,
        chainTipHeight: prev?.chainTipHeight ?? 0,
        transparentBalance: prev?.transparentBalance,
        saplingBalance: prev?.saplingBalance,
        orchardBalance: prev?.orchardBalance,
        transparentPendingBalance: prev?.transparentPendingBalance,
        saplingPendingBalance: prev?.saplingPendingBalance,
        orchardPendingBalance: prev?.orchardPendingBalance,
        canShieldTransparentBalance: prev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: prev?.shieldTransparentFee,
        shieldTransparentAmount: prev?.shieldTransparentAmount,
        spendableBalance: prev?.spendableBalance,
        totalBalance: prev?.totalBalance,
        recentTransactions: prev?.recentTransactions ?? const [],
        lastSyncStartedAt: prev?.lastSyncStartedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
      ),
    );
  }

  WalletMutationSyncPause _walletMutationSyncPauseSnapshot() {
    return WalletMutationSyncPause(
      hadActiveSync: _isSyncing || rust_sync.isSyncRunning(),
      hadPolling: _pollTimer != null || _pollCheckInFlight,
      hadBackgroundSync: _bgDelegate.isActive,
      hadMempoolObserver: rust_sync.isMempoolObserverRunning(),
    );
  }

  bool needsPauseForWalletMutation() =>
      _walletMutationSyncPauseSnapshot().hadWorkToPause;

  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    final pause = _walletMutationSyncPauseSnapshot();

    if (!pause.hadWorkToPause) {
      return pause;
    }

    ++_syncGen;
    _stopPolling();
    await onStoppingSync?.call();
    log('SyncNotifier: pausing sync for wallet DB mutation');
    _isSyncing = false;
    rust_sync.setSyncMode(mode: 0);
    rust_sync.cancelFullSync();
    _stopMempoolObserver();
    await _syncSub?.cancel();
    _syncSub = null;

    if (_bgDelegate.isActive) {
      try {
        await _bgDelegate.shutdownForLock();
      } catch (e) {
        log(
          'SyncNotifier: background shutdown before wallet mutation failed: $e',
        );
      }
    }

    final prev = state.value;
    if (prev != null) {
      state = AsyncData(
        prev.copyWith(isSyncing: false, isBackgroundMode: false, phase: ''),
      );
    }

    final stopped = await _waitForRustTasksToStop(
      timeoutMs: 120000,
      onSyncTimeout:
          'SyncNotifier: timed out waiting for Rust sync to stop before wallet '
          'mutation',
      onMempoolTimeout:
          'SyncNotifier: timed out waiting for mempool observer to stop before '
          'wallet mutation',
    );
    if (!stopped) {
      resumeAfterWalletMutation(pause);
      throw StateError('Sync did not stop before wallet database mutation.');
    }

    return pause;
  }

  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {
    if (_requiresUnlock) return;

    if (pause.hadActiveSync || pause.hadBackgroundSync) {
      log('SyncNotifier: resuming sync after wallet DB mutation');
      startSync();
    }
    if (pause.hadPolling || pause.hadActiveSync || pause.hadBackgroundSync) {
      _startPolling();
    }
  }

  Future<void> clearSensitiveStateForLock() async {
    ++_syncGen;
    ++_sensitiveStateEpoch;
    _isSyncing = false;
    _stopPolling();
    _syncSub?.cancel();
    _syncSub = null;
    _stopMempoolObserver();
    state = AsyncData(SyncState());

    // Sign-out should cancel the current Rust run immediately.
    // Waiting for the iOS background delegate's normal
    // foreground-handoff path (`setSyncMode(1)`) leaves a window
    // where unlock can race with a still-running old sync.
    rust_sync.setSyncMode(mode: 0);
    rust_sync.cancelFullSync();

    if (_bgDelegate.isActive) {
      try {
        await _bgDelegate.shutdownForLock();
      } catch (e) {
        log('SyncNotifier: background shutdown during sign-out failed: $e');
      }
    }

    await _waitForRustTasksToStop(
      timeoutMs: 5000,
      onSyncTimeout:
          'SyncNotifier: timed out waiting for Rust sync to stop during sign-out',
      onMempoolTimeout:
          'SyncNotifier: timed out waiting for mempool observer to stop during '
          'sign-out',
    );
  }

  Future<void> enableBackgroundSync() async {
    if (_bgDelegate.isActive) return;
    await _bgDelegate.enable();
    log('SyncNotifier: background sync enabled');
  }

  Future<void> disableBackgroundSync() async {
    if (!_bgDelegate.isActive) return;
    final needsResync = await _bgDelegate.disable();
    log('SyncNotifier: background sync disabled');
    if (needsResync) {
      startSync();
    }
  }

  /// Cancels the current sync (if any), waits for the Rust loop to
  /// finish its teardown so `isSyncRunning()` returns `false`, then
  /// starts a fresh sync and restarts the polling loop. This is the
  /// right entry point for settings that change the underlying
  /// transport (e.g. the Tor toggle) and need the next run to use
  /// the new value — a plain `stopSync()` alone leaves the wallet
  /// silent for the rest of the session if the toggle fires while
  /// sync is already idle.
  Future<void> restartSync() async {
    stopSync();
    // `cancelFullSync` / `stopMempoolObserver` set atomics that
    // the Rust loop and the mempool observer check at their own
    // cadence (batch boundaries for sync, the 100ms cancel-aware
    // sleep for the observer), so they take up to one batch /
    // one message worth of work to actually stop. We must wait
    // for BOTH of them to clear before starting a fresh session:
    //
    //   * `isSyncRunning()` — the next `startFullSync` will
    //     reject until the old single-run lock drops.
    //   * `isMempoolObserverRunning()` — the next
    //     `_startMempoolObserver` will log "already running" and
    //     skip without retry if the old observer is still
    //     winding down. Without waiting here the new sync
    //     session would silently lose mempool streaming for
    //     its entire run (Codex adversarial-review finding 1).
    //
    // 5s ceiling matches the original `restartSync` behaviour
    // and the `_resetWallet` path in `home_screen.dart`. Neither
    // the sync loop's post-batch cancel check nor the observer's
    // 100ms cancel slice should take anywhere near that long,
    // but a network stall mid-broadcast can extend it.
    await _waitForRustTasksToStop(
      timeoutMs: 5000,
      onSyncTimeout:
          'SyncNotifier: restartSync timed out waiting for Rust sync loop to '
          'stop after 5s; starting anyway (the startSync guard will log if '
          'the old run is still around)',
      onMempoolTimeout:
          'SyncNotifier: restartSync timed out waiting for mempool observer to '
          'stop after 5s; the new observer start will skip and the new '
          'session runs without streaming',
    );
    startSync();
    _startPolling();
  }

  static Future<bool> isBackgroundSyncAvailable() async {
    try {
      return await BackgroundSyncDelegate.create().isAvailable();
    } catch (e) {
      log('SyncNotifier: background sync availability check failed: $e');
      return false;
    }
  }

  // ======================== Polling ========================

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_isInForeground || _bgDelegate.shouldSuppressPolling) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        await _checkAndSync();
      } catch (e) {
        log('AutoSync: polling error: $e');
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkAndSync() async {
    final gen = _syncGen;
    final epoch = _sensitiveStateEpoch;
    final hasAccounts = ref.read(accountProvider).value?.hasAccounts ?? false;
    if (_pollCheckInFlight ||
        _isSyncing ||
        _requiresUnlock ||
        _bgDelegate.shouldSuppressPolling ||
        !_isInForeground ||
        !hasAccounts) {
      return;
    }
    _pollCheckInFlight = true;
    _stopPolling();
    try {
      final tip = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
      );
      final lastSynced = state.value?.chainTipHeight ?? 0;
      final syncComplete = (state.value?.percentage ?? 0) >= 1.0;
      if (gen != _syncGen || epoch != _sensitiveStateEpoch || _requiresUnlock) {
        log('AutoSync: skipping restart after lock transition');
        return;
      }
      if (!syncComplete || tip.toInt() > lastSynced) {
        log(
          'AutoSync: needs sync (tip=$tip, last=$lastSynced, complete=$syncComplete)',
        );
        startSync();
      }
    } catch (e) {
      log('AutoSync: tip check failed: $e');
    } finally {
      _pollCheckInFlight = false;
    }
    if (gen != _syncGen || _requiresUnlock) {
      return;
    }
    _startPolling();
  }

  Future<bool> _waitForRustTasksToStop({
    required int timeoutMs,
    required String onSyncTimeout,
    required String onMempoolTimeout,
  }) async {
    var waited = 0;
    while ((rust_sync.isSyncRunning() ||
            rust_sync.isMempoolObserverRunning()) &&
        waited < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    final syncRunning = rust_sync.isSyncRunning();
    final mempoolRunning = rust_sync.isMempoolObserverRunning();
    if (syncRunning) {
      log(onSyncTimeout);
    }
    if (mempoolRunning) {
      log(onMempoolTimeout);
    }
    return !syncRunning && !mempoolRunning;
  }

  // ======================== Mempool Observer ========================

  /// Fire up the Rust mempool observer for this sync session.
  ///
  /// Runs in parallel with the scan loop — matches
  /// zcash-android-wallet-sdk's `startObservingMempool` coroutine.
  /// The Rust side has its own reconnect loop with 1s / 30s
  /// backoff, so the Dart side only needs to:
  ///
  ///   1. Subscribe to the emitted stream.
  ///   2. On each `matched=true` event, trigger the same balance
  ///      refresh path sync uses for `hasNewTx` events. (When an
  ///      outbound send first lands in lightwalletd's mempool the
  ///      wallet hasn't seen the tx mined yet, but the relayed
  ///      bytes are enough for us to flip the UI from "broadcast
  ///      pending" to "propagating" sooner than the next block
  ///      scan would.)
  ///   3. Silently ignore `matched=false` events — they're other
  ///      people's transactions, used only for future mempool-side
  ///      inbound discovery (not in scope for v1).
  ///
  /// Reuses [_mempoolSub] as the single subscription handle. The
  /// `startMempoolObserver` FRB call is guarded on the Rust side
  /// by the MEMPOOL_RUNNING atomic, so a double-call just logs
  /// and returns an error; we catch and ignore it.
  void _startMempoolObserver(String dbPath, ZcashNetwork network) {
    if (rust_sync.isMempoolObserverRunning()) {
      // Already up — happens if startSync fires while a previous
      // observer is still winding down. The Rust side will
      // reject the second start, so skip rather than racing it.
      log('Mempool: observer already running, skipping start');
      return;
    }
    _mempoolSub?.cancel();
    final stream = rust_sync.startMempoolObserver(
      dbPath: dbPath,
      network: network.name,
      lightwalletdUrl: network.lightwalletdUrl,
    );
    _mempoolSub = stream.listen(
      (event) {
        if (!event.matched) return;
        log('Mempool: matched ${event.txidHex}, refreshing balance');
        // Fire-and-forget: _refreshBalance rebuilds state and
        // logs its own errors. We don't await because the
        // mempool stream callback should stay non-blocking so
        // the next incoming tx isn't delayed.
        _refreshBalance();
      },
      onDone: () {
        log('Mempool: stream ended');
        _mempoolSub = null;
      },
      onError: (e) {
        // Observer-side errors are logged from the Rust side in
        // detail; here we just track that the Dart subscription
        // closed so a restart at the next startSync is safe.
        log('Mempool: stream error: $e');
        _mempoolSub = null;
      },
    );
  }

  /// Cancel the running mempool observer (if any) and tear down
  /// the Dart subscription. Symmetric with [_startMempoolObserver]
  /// and called from [stopSync] as well as on dispose.
  void _stopMempoolObserver() {
    if (rust_sync.isMempoolObserverRunning()) {
      rust_sync.stopMempoolObserver();
    }
    _mempoolSub?.cancel();
    _mempoolSub = null;
  }

  // ======================== Progress Handling ========================

  Future<void> _onSyncProgress(SyncProgressEvent event) async {
    if (_requiresUnlock) {
      return;
    }
    final epoch = _sensitiveStateEpoch;
    if (event.scannedHeight != _lastLoggedHeight) {
      log(
        'Sync: ${(event.percentage * 100).toStringAsFixed(1)}% (${event.scannedHeight}/${event.chainTipHeight})',
      );
      _lastLoggedHeight = event.scannedHeight;
    }

    final prev = state.value;
    final dbPath = await _getDbPath();
    final network = ZcashNetwork.mainnet.name;
    final accountUuid = _getActiveAccountUuid();
    if (accountUuid == null) {
      log('SyncNotifier: no active account, skipping refresh');
      return;
    }

    // Only fetch balance/history when there are new transactions or sync is complete.
    // Skipping intermediate batches avoids opening a new DB connection per batch.
    BigInt? transparent;
    BigInt? sapling;
    BigInt? orchard;
    BigInt? transparentPending;
    BigInt? saplingPending;
    BigInt? orchardPending;
    BigInt? spendable;
    BigInt? total;
    bool? canShieldTransparentBalance;
    BigInt? shieldTransparentFee;
    BigInt? shieldTransparentAmount;
    var recentTxs =
        prev?.recentTransactions ?? const <rust_sync.TransactionInfo>[];
    if (event.hasNewTx || event.isComplete) {
      try {
        final balance = await rust_sync.getBalance(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        );
        transparent = balance.transparent;
        sapling = balance.sapling;
        orchard = balance.orchard;
        transparentPending = balance.transparentPending;
        saplingPending = balance.saplingPending;
        orchardPending = balance.orchardPending;
        spendable = balance.spendable;
        total = balance.total;
      } catch (e) {
        log('SyncNotifier: balance fetch failed: $e');
      }
      try {
        recentTxs = await rust_sync.getTransactionHistory(
          dbPath: dbPath,
          network: network,
          limit: 10,
          accountUuid: accountUuid,
        );
      } catch (e) {
        log('SyncNotifier: tx history fetch failed: $e');
      }
      final shieldStatus = await _getShieldTransparentStatus(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
        transparentBalance:
            transparent ?? prev?.transparentBalance ?? BigInt.zero,
      );
      if (shieldStatus != null) {
        canShieldTransparentBalance = shieldStatus.canShield;
        shieldTransparentFee = shieldStatus.fee;
        shieldTransparentAmount = shieldStatus.amount;
      }
    }

    if (epoch != _sensitiveStateEpoch || _requiresUnlock) {
      log(
        'SyncNotifier: discarding sync progress update after lock transition',
      );
      return;
    }

    // Update delegate BEFORE state so isActive reflects completion
    _bgDelegate.onProgress(event);

    final syncStartedAt =
        prev?.lastSyncStartedAt ??
        (event.isSyncing || event.isComplete ? DateTime.now() : null);
    final syncCompletedAt = event.isComplete
        ? DateTime.now()
        : prev?.lastSyncCompletedAt;

    state = AsyncData(
      SyncState(
        isSyncing: event.isSyncing && !event.isComplete,
        isBackgroundMode: event.isBackground || _bgDelegate.isActive,
        percentage: event.percentage,
        scannedHeight: event.scannedHeight,
        chainTipHeight: event.chainTipHeight,
        transparentBalance: transparent ?? prev?.transparentBalance,
        saplingBalance: sapling ?? prev?.saplingBalance,
        orchardBalance: orchard ?? prev?.orchardBalance,
        transparentPendingBalance:
            transparentPending ?? prev?.transparentPendingBalance,
        saplingPendingBalance: saplingPending ?? prev?.saplingPendingBalance,
        orchardPendingBalance: orchardPending ?? prev?.orchardPendingBalance,
        canShieldTransparentBalance:
            canShieldTransparentBalance ??
            prev?.canShieldTransparentBalance ??
            false,
        shieldTransparentFee:
            shieldTransparentFee ?? prev?.shieldTransparentFee,
        shieldTransparentAmount:
            shieldTransparentAmount ?? prev?.shieldTransparentAmount,
        spendableBalance: spendable ?? prev?.spendableBalance,
        totalBalance: total ?? prev?.totalBalance,
        recentTransactions: recentTxs,
        lastSyncStartedAt: syncStartedAt,
        lastSyncCompletedAt: syncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
        phase: event.phase,
      ),
    );

    // Handle sync completion here (not in onDone) to avoid race with async state update.
    if (event.isComplete) {
      _isSyncing = false;
      _bgDelegate.onSyncDone();
      _startPolling();
    }
  }

  // ======================== Balance Refresh ========================

  /// Public: refresh balance and recent transactions (e.g. after send).
  Future<void> refreshAfterSend() => _refreshBalance();

  Future<void> refreshAfterUnlock() => _refreshBalance();

  Future<void> _refreshBalance() async {
    if (_requiresUnlock) {
      state = AsyncData(SyncState());
      return;
    }
    final epoch = _sensitiveStateEpoch;
    final prev = state.value;
    final dbPath = await _getDbPath();
    final network = ZcashNetwork.mainnet.name;
    final accountUuid = _getActiveAccountUuid();
    if (accountUuid == null) {
      log('SyncNotifier: no active account, skipping refresh');
      return;
    }

    BigInt? transparent;
    BigInt? sapling;
    BigInt? orchard;
    BigInt? transparentPending;
    BigInt? saplingPending;
    BigInt? orchardPending;
    BigInt? spendable;
    BigInt? total;
    bool? canShieldTransparentBalance;
    BigInt? shieldTransparentFee;
    BigInt? shieldTransparentAmount;
    try {
      final balance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      );
      transparent = balance.transparent;
      sapling = balance.sapling;
      orchard = balance.orchard;
      transparentPending = balance.transparentPending;
      saplingPending = balance.saplingPending;
      orchardPending = balance.orchardPending;
      spendable = balance.spendable;
      total = balance.total;
    } catch (e) {
      _logRefreshReadError(
        label: 'balance',
        fallback: 'keeping previous value',
        error: e,
      );
    }

    var recentTxs =
        prev?.recentTransactions ?? const <rust_sync.TransactionInfo>[];
    try {
      recentTxs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: network,
        limit: 10,
        accountUuid: accountUuid,
      );
    } catch (e) {
      _logRefreshReadError(
        label: 'tx history',
        fallback: 'keeping previous list',
        error: e,
      );
    }

    final shieldStatus = await _getShieldTransparentStatus(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
      transparentBalance:
          transparent ?? prev?.transparentBalance ?? BigInt.zero,
    );
    if (shieldStatus != null) {
      canShieldTransparentBalance = shieldStatus.canShield;
      shieldTransparentFee = shieldStatus.fee;
      shieldTransparentAmount = shieldStatus.amount;
    }

    if (epoch != _sensitiveStateEpoch || _requiresUnlock) {
      log('SyncNotifier: discarding balance refresh after lock transition');
      return;
    }

    state = AsyncData(
      SyncState(
        isSyncing: prev?.isSyncing ?? false,
        isBackgroundMode: _bgDelegate.isActive,
        percentage: prev?.percentage ?? 0.0,
        scannedHeight: prev?.scannedHeight ?? 0,
        chainTipHeight: prev?.chainTipHeight ?? 0,
        transparentBalance: transparent ?? prev?.transparentBalance,
        saplingBalance: sapling ?? prev?.saplingBalance,
        orchardBalance: orchard ?? prev?.orchardBalance,
        transparentPendingBalance:
            transparentPending ?? prev?.transparentPendingBalance,
        saplingPendingBalance: saplingPending ?? prev?.saplingPendingBalance,
        orchardPendingBalance: orchardPending ?? prev?.orchardPendingBalance,
        canShieldTransparentBalance:
            canShieldTransparentBalance ??
            prev?.canShieldTransparentBalance ??
            false,
        shieldTransparentFee:
            shieldTransparentFee ?? prev?.shieldTransparentFee,
        shieldTransparentAmount:
            shieldTransparentAmount ?? prev?.shieldTransparentAmount,
        spendableBalance: spendable ?? prev?.spendableBalance,
        totalBalance: total ?? prev?.totalBalance,
        recentTransactions: recentTxs,
        lastSyncStartedAt: prev?.lastSyncStartedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
      ),
    );
  }

  String? _getActiveAccountUuid() {
    return ref.read(accountProvider).value?.activeAccountUuid;
  }

  Future<({bool canShield, BigInt fee, BigInt amount})?>
  _getShieldTransparentStatus({
    required String dbPath,
    required String network,
    required String accountUuid,
    required BigInt transparentBalance,
  }) async {
    final isHardware =
        ref.read(accountProvider).value?.activeAccount?.isHardware ?? false;
    if (isHardware || transparentBalance <= BigInt.zero) {
      return (canShield: false, fee: BigInt.zero, amount: BigInt.zero);
    }

    try {
      final status = await rust_sync.getShieldTransparentStatus(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      );
      return (
        canShield: status.canShield,
        fee: status.feeZatoshi,
        amount: status.shieldedZatoshi,
      );
    } catch (e) {
      _logRefreshReadError(
        label: 'shield transparent status',
        fallback: 'keeping previous value',
        error: e,
      );
      return null;
    }
  }

  void _logRefreshReadError({
    required String label,
    required String fallback,
    required Object error,
  }) {
    if (_isDatabaseLockedError(error)) {
      log(
        'SyncNotifier: $label refresh skipped due to temporary DB lock; '
        '$fallback',
      );
      return;
    }
    log('SyncNotifier: $label refresh failed: $error');
  }

  bool _isDatabaseLockedError(Object error) {
    return error.toString().contains('database is locked');
  }

  Future<String> _getDbPath() async {
    if (_cachedDbPath != null) return _cachedDbPath!;
    _cachedDbPath = await getWalletDbPath();
    return _cachedDbPath!;
  }

  bool get _requiresUnlock {
    return ref.read(appSecurityProvider).requiresUnlock;
  }
}

final syncProvider = AsyncNotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
