import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/config/rpc_endpoint_config.dart';
import '../core/storage/wallet_paths.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../services/background_sync_delegate.dart';
import 'account_provider.dart';
import 'app_security_provider.dart';
import 'rpc_endpoint_failover_provider.dart';
import 'sync_failure.dart';

class SyncState {
  /// Account UUID that owns the balance, shield status, and recent transaction
  /// fields below. Sync progress itself is wallet-wide.
  final String? accountUuid;

  /// True after balance fields have been loaded for [accountUuid].
  final bool hasBalanceData;

  /// True after recent transaction history has been loaded for [accountUuid].
  final bool hasRecentTransactionsData;

  /// True only after both balance and history have been loaded for
  /// [accountUuid]. Activity UIs should use this instead of treating a scoped
  /// placeholder or partial refresh as renderable account data.
  bool get hasAccountScopedData => hasBalanceData && hasRecentTransactionsData;
  final bool isSyncing;
  final bool isBackgroundMode;
  final double percentage;
  final double displayPercentage;
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

  /// Structured sync failure used by UI to choose copy and recovery action.
  final SyncFailure? failure;

  /// Raw sync error retained for compatibility with existing failure checks.
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
    this.accountUuid,
    bool hasAccountScopedData = false,
    bool? hasBalanceData,
    bool? hasRecentTransactionsData,
    this.isSyncing = false,
    this.isBackgroundMode = false,
    this.percentage = 0,
    double? displayPercentage,
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
    this.failure,
    this.error,
    this.recentTransactions = const [],
    this.lastSyncStartedAt,
    this.lastSyncCompletedAt,
    this.lastSyncFailedAt,
    this.phase = '',
  }) : hasBalanceData = hasBalanceData ?? hasAccountScopedData,
       hasRecentTransactionsData =
           hasRecentTransactionsData ?? hasAccountScopedData,
       displayPercentage = displayPercentage ?? percentage,
       transparentBalance = transparentBalance ?? BigInt.zero,
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
    String? accountUuid,
    bool? hasAccountScopedData,
    bool? hasBalanceData,
    bool? hasRecentTransactionsData,
    bool? isSyncing,
    bool? isBackgroundMode,
    double? percentage,
    double? displayPercentage,
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
    SyncFailure? failure,
    bool clearFailure = false,
    String? error,
    bool clearError = false,
    List<rust_sync.TransactionInfo>? recentTransactions,
    DateTime? lastSyncStartedAt,
    DateTime? lastSyncCompletedAt,
    DateTime? lastSyncFailedAt,
    String? phase,
  }) {
    return SyncState(
      accountUuid: accountUuid ?? this.accountUuid,
      hasBalanceData:
          hasBalanceData ?? hasAccountScopedData ?? this.hasBalanceData,
      hasRecentTransactionsData:
          hasRecentTransactionsData ??
          hasAccountScopedData ??
          this.hasRecentTransactionsData,
      isSyncing: isSyncing ?? this.isSyncing,
      isBackgroundMode: isBackgroundMode ?? this.isBackgroundMode,
      percentage: percentage ?? this.percentage,
      displayPercentage: displayPercentage ?? this.displayPercentage,
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
      failure: clearFailure ? null : failure ?? this.failure,
      error: clearError ? null : error ?? this.error,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      lastSyncStartedAt: lastSyncStartedAt ?? this.lastSyncStartedAt,
      lastSyncCompletedAt: lastSyncCompletedAt ?? this.lastSyncCompletedAt,
      lastSyncFailedAt: lastSyncFailedAt ?? this.lastSyncFailedAt,
      phase: phase ?? this.phase,
    );
  }

  bool belongsToAccount(String? accountUuid) {
    return accountUuid != null && this.accountUuid == accountUuid;
  }

  bool hasDataForAccount(String? accountUuid) {
    return belongsToAccount(accountUuid) && hasAccountScopedData;
  }

  SyncState scopedToAccount(String? accountUuid) {
    if (belongsToAccount(accountUuid)) return this;
    return withoutAccountScopedData(accountUuid: accountUuid);
  }

  SyncState withoutAccountScopedData({String? accountUuid}) {
    return SyncState(
      accountUuid: accountUuid,
      hasBalanceData: false,
      hasRecentTransactionsData: false,
      isSyncing: isSyncing,
      isBackgroundMode: isBackgroundMode,
      percentage: percentage,
      displayPercentage: displayPercentage,
      scannedHeight: scannedHeight,
      chainTipHeight: chainTipHeight,
      failure: failure,
      error: error,
      lastSyncStartedAt: lastSyncStartedAt,
      lastSyncCompletedAt: lastSyncCompletedAt,
      lastSyncFailedAt: lastSyncFailedAt,
      phase: phase,
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
  static const _displayBlockDuration = Duration(milliseconds: 20);
  static const _maxIncompleteDisplayPercentage = 0.999;

  late final BackgroundSyncDelegate _bgDelegate;
  bool _isSyncing = false;
  bool _isInForeground = true;
  int _lastLoggedHeight = 0;
  SyncProgressEvent? _lastForegroundSyncProgress;
  int _syncGen = 0; // incremented by stopSync to invalidate pending startSync
  String? _cachedDbPath;
  StreamSubscription? _syncSub;
  Timer? _displayProgressTimer;
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
  bool _mempoolRefreshInFlight = false;
  bool _mempoolRefreshQueued = false;

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
      _displayProgressTimer?.cancel();
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
      final prevAccountUuid = prev?.value?.activeAccountUuid;
      final nextAccountUuid = next.value?.activeAccountUuid;
      if (prevAccountUuid != nextAccountUuid) {
        _clearAccountScopedStateFor(nextAccountUuid);
      }
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
    final initialAccountUuid = accountState?.activeAccountUuid;
    final initialBelongsToActiveAccount =
        initial.accountUuid != null &&
        initial.accountUuid == initialAccountUuid &&
        initial.hasAccountScopedData;
    return SyncState(
      accountUuid: initialAccountUuid,
      hasAccountScopedData: initialBelongsToActiveAccount,
      isSyncing: false,
      isBackgroundMode: false,
      percentage: initial.percentage,
      scannedHeight: initial.scannedHeight,
      chainTipHeight: initial.chainTipHeight,
      transparentBalance: initialBelongsToActiveAccount
          ? initial.transparentBalance
          : BigInt.zero,
      saplingBalance: initialBelongsToActiveAccount
          ? initial.saplingBalance
          : BigInt.zero,
      orchardBalance: initialBelongsToActiveAccount
          ? initial.orchardBalance
          : BigInt.zero,
      transparentPendingBalance: initialBelongsToActiveAccount
          ? initial.transparentPendingBalance
          : BigInt.zero,
      saplingPendingBalance: initialBelongsToActiveAccount
          ? initial.saplingPendingBalance
          : BigInt.zero,
      orchardPendingBalance: initialBelongsToActiveAccount
          ? initial.orchardPendingBalance
          : BigInt.zero,
      canShieldTransparentBalance: initialBelongsToActiveAccount
          ? initial.canShieldTransparentBalance
          : false,
      shieldTransparentFee: initialBelongsToActiveAccount
          ? initial.shieldTransparentFee
          : BigInt.zero,
      shieldTransparentAmount: initialBelongsToActiveAccount
          ? initial.shieldTransparentAmount
          : BigInt.zero,
      spendableBalance: initialBelongsToActiveAccount
          ? initial.spendableBalance
          : BigInt.zero,
      totalBalance: initialBelongsToActiveAccount
          ? initial.totalBalance
          : BigInt.zero,
      recentTransactions: initialBelongsToActiveAccount
          ? initial.recentTransactions
          : const [],
      phase: '',
    );
  }

  SyncState? _previousScopedState(SyncState? prev, String? accountUuid) {
    if (accountUuid == null || prev?.accountUuid != accountUuid) {
      return null;
    }
    return prev;
  }

  void _clearAccountScopedStateFor(String? accountUuid) {
    final prev = state.value;
    if (prev == null) return;
    state = AsyncData(prev.withoutAccountScopedData(accountUuid: accountUuid));
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
    _lastForegroundSyncProgress = null;
    _stopDisplayProgressTimer();
    final gen = ++_syncGen;
    final prev = state.value;
    final accountUuid = _getActiveAccountUuid();
    final scopedPrev = _previousScopedState(prev, accountUuid);
    final startedAt = DateTime.now();
    state = AsyncData(
      SyncState(
        accountUuid: accountUuid,
        hasBalanceData: scopedPrev?.hasBalanceData ?? false,
        hasRecentTransactionsData:
            scopedPrev?.hasRecentTransactionsData ?? false,
        isSyncing: true,
        isBackgroundMode: false,
        percentage: 0.0,
        scannedHeight: prev?.scannedHeight ?? 0,
        chainTipHeight: prev?.chainTipHeight ?? 0,
        transparentBalance: scopedPrev?.transparentBalance,
        saplingBalance: scopedPrev?.saplingBalance,
        orchardBalance: scopedPrev?.orchardBalance,
        transparentPendingBalance: scopedPrev?.transparentPendingBalance,
        saplingPendingBalance: scopedPrev?.saplingPendingBalance,
        orchardPendingBalance: scopedPrev?.orchardPendingBalance,
        canShieldTransparentBalance:
            scopedPrev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: scopedPrev?.shieldTransparentFee,
        shieldTransparentAmount: scopedPrev?.shieldTransparentAmount,
        spendableBalance: scopedPrev?.spendableBalance,
        totalBalance: scopedPrev?.totalBalance,
        recentTransactions: scopedPrev?.recentTransactions ?? const [],
        lastSyncStartedAt: startedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
        phase: '',
      ),
    );

    _getDbPath()
        .then((dbPath) async {
          if (gen != _syncGen) return; // stopSync was called, abort
          try {
            await ref
                .read(rpcEndpointFailoverProvider.notifier)
                .getLatestBlockHeight();
          } catch (e) {
            if (gen != _syncGen) return;
            log('Sync: endpoint preflight failed: $e');
            _isSyncing = false;
            _stopDisplayProgressTimer();
            _recordSyncFailure(e);
            return;
          }

          final endpoint = _endpointConfig;
          log('Sync: starting foreground sync via ${endpoint.hostPort}');
          // Fire up the mempool observer alongside the scan loop.
          // It has its own Rust cancel flag (MEMPOOL_CANCEL) and runs
          // on a separate tokio runtime, so it can accept events while
          // the scan loop is still catching up on old blocks.
          _startMempoolObserver(dbPath, endpoint);
          final stream = rust_sync.startFullSync(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            mode: 1,
          );
          _syncSub = stream.listen(
            (event) {
              if (gen != _syncGen) return;
              final progress = SyncProgressEvent(
                scannedHeight: event.scannedHeight.toInt(),
                chainTipHeight: event.chainTipHeight.toInt(),
                percentage: event.percentage,
                displayTargetPercentage: event.displayTargetPercentage,
                displayTargetBlocks: event.displayTargetBlocks.toInt(),
                isSyncing: event.isSyncing,
                isComplete: event.isComplete,
                hasNewTx: event.hasNewTx,
                phase: event.phase,
              );
              _lastForegroundSyncProgress = progress;
              unawaited(_onSyncProgress(progress));
            },
            onDone: () {
              if (gen != _syncGen) {
                log('Sync: ignoring stale stream end');
                return;
              }
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
                final current = state.value;
                final lastProgress = _lastForegroundSyncProgress;
                final endedAtTipFromState =
                    current != null &&
                    current.percentage >= 1.0 &&
                    current.chainTipHeight > 0 &&
                    current.scannedHeight >= current.chainTipHeight;
                final endedAtTipFromProgress =
                    lastProgress != null &&
                    lastProgress.percentage >= 1.0 &&
                    lastProgress.chainTipHeight > 0 &&
                    lastProgress.scannedHeight >= lastProgress.chainTipHeight;
                final endedAtTip =
                    rust_sync.getSyncMode() == 1 &&
                    (endedAtTipFromState || endedAtTipFromProgress);
                _isSyncing = false;
                _stopDisplayProgressTimer();
                if (endedAtTip) {
                  log(
                    'Sync: stream ended at tip without isComplete, treating as complete',
                  );
                  _finalizeEndedAtTipSyncState(lastProgress);
                  _bgDelegate.onSyncDone();
                  _startPolling();
                } else {
                  log('Sync: stream ended without isComplete, cleaning up');
                  _stopMempoolObserver();
                }
              }
            },
            onError: (e) {
              if (gen != _syncGen) return;
              log('Sync: stream error: $e');
              _isSyncing = false;
              _stopDisplayProgressTimer();
              // Sync died mid-stream: tear the mempool observer down
              // at the same time so a failed sync session can't leak
              // a lightwalletd stream that keeps firing
              // `_refreshBalance()` callbacks with no owning sync.
              _stopMempoolObserver();
              unawaited(
                _recoverSyncOnFallbackOrRecordFailure(
                  e,
                  gen,
                  endpoint: endpoint,
                ),
              );
            },
          );
        })
        .catchError((e, st) {
          if (gen != _syncGen) return;
          log('SyncNotifier: ERROR: $e\n$st');
          _isSyncing = false;
          _stopDisplayProgressTimer();
          // Sync setup threw before the stream was ever attached.
          // We may have already started the mempool observer
          // (happens on the main success path just before
          // `startFullSync`), so always call
          // `_stopMempoolObserver()` here; it is idempotent when
          // nothing is running.
          _stopMempoolObserver();
          unawaited(_recoverSyncOnFallbackOrRecordFailure(e, gen));
        });
  }

  Future<void> _recoverSyncOnFallbackOrRecordFailure(
    Object error,
    int gen, {
    RpcEndpointConfig? endpoint,
  }) async {
    final switched = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          error,
          endpoint: endpoint,
          operation: 'foreground sync',
        );
    if (gen != _syncGen || _requiresUnlock) return;
    if (switched) {
      log('Sync: retrying foreground sync with fallback endpoint');
      startSync();
      _startPolling();
      return;
    }
    _recordSyncFailure(error);
  }

  void _recordSyncFailure(Object error) {
    final failure = classifySyncFailure(error);
    final prev = state.value;
    final accountUuid = _getActiveAccountUuid();
    final scopedPrev = _previousScopedState(prev, accountUuid);
    state = AsyncData(
      SyncState(
        accountUuid: accountUuid,
        hasBalanceData: scopedPrev?.hasBalanceData ?? false,
        hasRecentTransactionsData:
            scopedPrev?.hasRecentTransactionsData ?? false,
        failure: failure,
        error: failure.rawMessage,
        transparentBalance: scopedPrev?.transparentBalance,
        saplingBalance: scopedPrev?.saplingBalance,
        orchardBalance: scopedPrev?.orchardBalance,
        transparentPendingBalance: scopedPrev?.transparentPendingBalance,
        saplingPendingBalance: scopedPrev?.saplingPendingBalance,
        orchardPendingBalance: scopedPrev?.orchardPendingBalance,
        canShieldTransparentBalance:
            scopedPrev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: scopedPrev?.shieldTransparentFee,
        shieldTransparentAmount: scopedPrev?.shieldTransparentAmount,
        spendableBalance: scopedPrev?.spendableBalance,
        totalBalance: scopedPrev?.totalBalance,
        recentTransactions: scopedPrev?.recentTransactions ?? const [],
        lastSyncStartedAt: prev?.lastSyncStartedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: DateTime.now(),
      ),
    );
    _startPolling();
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
    _stopDisplayProgressTimer();
    _stopPolling();
    if (_bgDelegate.isActive) {
      unawaited(_bgDelegate.disable());
    }
    final prev = state.value;
    final accountUuid = _getActiveAccountUuid();
    final scopedPrev = _previousScopedState(prev, accountUuid);
    state = AsyncData(
      SyncState(
        accountUuid: accountUuid,
        hasBalanceData: scopedPrev?.hasBalanceData ?? false,
        hasRecentTransactionsData:
            scopedPrev?.hasRecentTransactionsData ?? false,
        isSyncing: false,
        isBackgroundMode: false,
        percentage: prev?.percentage ?? 0.0,
        displayPercentage: prev?.displayPercentage ?? prev?.percentage ?? 0.0,
        scannedHeight: prev?.scannedHeight ?? 0,
        chainTipHeight: prev?.chainTipHeight ?? 0,
        transparentBalance: scopedPrev?.transparentBalance,
        saplingBalance: scopedPrev?.saplingBalance,
        orchardBalance: scopedPrev?.orchardBalance,
        transparentPendingBalance: scopedPrev?.transparentPendingBalance,
        saplingPendingBalance: scopedPrev?.saplingPendingBalance,
        orchardPendingBalance: scopedPrev?.orchardPendingBalance,
        canShieldTransparentBalance:
            scopedPrev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: scopedPrev?.shieldTransparentFee,
        shieldTransparentAmount: scopedPrev?.shieldTransparentAmount,
        spendableBalance: scopedPrev?.spendableBalance,
        totalBalance: scopedPrev?.totalBalance,
        recentTransactions: scopedPrev?.recentTransactions ?? const [],
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

  void clearCachedWalletDbPath() {
    _cachedDbPath = null;
  }

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
    _stopDisplayProgressTimer();
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
    _stopDisplayProgressTimer();
    _stopPolling();
    _syncSub?.cancel();
    _syncSub = null;
    _stopMempoolObserver();
    _mempoolRefreshInFlight = false;
    _mempoolRefreshQueued = false;
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
    await _bgDelegate.enable(endpoint: _endpointConfig);
    _stopDisplayProgressTimer();
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
    final hadBackgroundSync = _bgDelegate.isActive;
    ++_syncGen;
    rust_sync.cancelFullSync();
    await _syncSub?.cancel();
    _syncSub = null;
    _stopMempoolObserver();
    _isSyncing = false;
    _stopPolling();
    if (hadBackgroundSync) {
      try {
        await _bgDelegate.disable();
      } catch (e) {
        log('SyncNotifier: background disable before restart failed: $e');
      }
    }
    final prev = state.value;
    if (prev != null) {
      state = AsyncData(
        prev.copyWith(isSyncing: false, isBackgroundMode: false, phase: ''),
      );
    }
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
    if (hadBackgroundSync) {
      try {
        await _bgDelegate.enable(endpoint: _endpointConfig);
      } catch (e) {
        log('SyncNotifier: background re-enable after restart failed: $e');
      }
    }
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

  void _finalizeEndedAtTipSyncState(SyncProgressEvent? lastProgress) {
    final prev = state.value;
    final completedAt = DateTime.now();
    final chainTipHeight = math.max(
      prev?.chainTipHeight ?? 0,
      lastProgress?.chainTipHeight ?? 0,
    );
    final scannedHeight = chainTipHeight > 0
        ? chainTipHeight
        : math.max(prev?.scannedHeight ?? 0, lastProgress?.scannedHeight ?? 0);
    final base = prev ?? SyncState(accountUuid: _getActiveAccountUuid());

    state = AsyncData(
      base.copyWith(
        isSyncing: false,
        isBackgroundMode: _bgDelegate.isActive,
        percentage: 1.0,
        displayPercentage: 1.0,
        scannedHeight: scannedHeight,
        chainTipHeight: chainTipHeight,
        lastSyncStartedAt: prev?.lastSyncStartedAt ?? completedAt,
        lastSyncCompletedAt: completedAt,
        phase: '',
      ),
    );
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
      final tip = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .getLatestBlockHeight();
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
  ///   2. On each `matched=true` event for the active account, trigger
  ///      the same balance refresh path sync uses for `hasNewTx`
  ///      events. Already-known outbound txs refresh as before; new
  ///      inbound shielded txs are first stored by Rust as unmined
  ///      wallet transactions.
  ///   3. Skip refresh for inactive-account events. The wallet-wide
  ///      observer has already stored the tx, so switching accounts can
  ///      surface it through the normal account-scoped history read.
  ///
  /// Reuses [_mempoolSub] as the single subscription handle. The
  /// `startMempoolObserver` FRB call is guarded on the Rust side
  /// by the MEMPOOL_RUNNING atomic, so a double-call just logs
  /// and returns an error; we catch and ignore it.
  void _startMempoolObserver(String dbPath, RpcEndpointConfig endpoint) {
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
      network: endpoint.networkName,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );
    _mempoolSub = stream.listen(
      (event) {
        if (!event.matched) return;
        final activeAccountUuid = _getActiveAccountUuid();
        // Empty account scope means Rust knows the tx is wallet-relevant,
        // but cannot narrow it to an account yet; preserve the legacy
        // active-account refresh behavior in that case.
        if (event.accountUuids.isNotEmpty &&
            !event.accountUuids.contains(activeAccountUuid)) {
          log(
            'Mempool: matched ${event.txidHex} for inactive account, skipping active refresh',
          );
          return;
        }
        log('Mempool: matched ${event.txidHex}, refreshing balance');
        _scheduleMempoolRefresh();
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

  void _scheduleMempoolRefresh() {
    if (_mempoolRefreshInFlight) {
      _mempoolRefreshQueued = true;
      return;
    }

    _mempoolRefreshInFlight = true;
    unawaited(_runMempoolRefreshLoop());
  }

  Future<void> _runMempoolRefreshLoop() async {
    try {
      do {
        _mempoolRefreshQueued = false;
        try {
          await _refreshBalance();
        } catch (e, st) {
          log('Mempool: refresh failed: $e\n$st');
        }
      } while (_mempoolRefreshQueued && !_requiresUnlock);
    } finally {
      _mempoolRefreshInFlight = false;
      _mempoolRefreshQueued = false;
    }
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

  double _clampProgress(double value) => value.clamp(0.0, 1.0).toDouble();

  void _stopDisplayProgressTimer() {
    _displayProgressTimer?.cancel();
    _displayProgressTimer = null;
  }

  void _startDisplayProgressSmoothing({
    required double basePercentage,
    required double targetPercentage,
    required int targetBlocks,
  }) {
    _stopDisplayProgressTimer();

    final base = math.min(
      _clampProgress(basePercentage),
      _maxIncompleteDisplayPercentage,
    );
    final target = math.min(
      _clampProgress(targetPercentage),
      _maxIncompleteDisplayPercentage,
    );
    if (targetBlocks <= 0 || target <= base) {
      return;
    }

    _displayProgressTimer = Timer.periodic(_displayBlockDuration, (timer) {
      final current = state.value;
      if (current == null ||
          _bgDelegate.isActive ||
          (!current.isSyncing && !current.isBackgroundMode)) {
        _stopDisplayProgressTimer();
        return;
      }

      final virtualBlocks = math.min(timer.tick, targetBlocks);
      final next = _clampProgress(
        math.min(
          target,
          base + ((target - base) * virtualBlocks / targetBlocks),
        ),
      );
      if (next > current.displayPercentage) {
        state = AsyncData(current.copyWith(displayPercentage: next));
      }
      if (virtualBlocks >= targetBlocks || next >= target) {
        _stopDisplayProgressTimer();
      }
    });
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
    final network = _endpointConfig.networkName;
    final accountUuid = _getActiveAccountUuid();
    if (accountUuid == null) {
      log('SyncNotifier: no active account, skipping refresh');
      return;
    }
    final scopedPrev = _previousScopedState(prev, accountUuid);

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
    var didFetchBalance = false;
    var didFetchRecentTxs = false;
    var recentTxs =
        scopedPrev?.recentTransactions ?? const <rust_sync.TransactionInfo>[];
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
        didFetchBalance = true;
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
        didFetchRecentTxs = true;
      } catch (e) {
        log('SyncNotifier: tx history fetch failed: $e');
      }
      final shieldStatus = await _getShieldTransparentStatus(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
        transparentBalance:
            transparent ?? scopedPrev?.transparentBalance ?? BigInt.zero,
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
    final stateAccountUuid = _getActiveAccountUuid();
    final useFetchedAccountData = accountUuid == stateAccountUuid;
    final stateScopedPrev = _previousScopedState(state.value, stateAccountUuid);
    final hasBalanceData = useFetchedAccountData
        ? didFetchBalance || (stateScopedPrev?.hasBalanceData ?? false)
        : stateScopedPrev?.hasBalanceData ?? false;
    final hasRecentTransactionsData = useFetchedAccountData
        ? didFetchRecentTxs ||
              (stateScopedPrev?.hasRecentTransactionsData ?? false)
        : stateScopedPrev?.hasRecentTransactionsData ?? false;
    if (!useFetchedAccountData) {
      log(
        'SyncNotifier: discarding account-scoped sync data after account transition',
      );
    }

    // Update delegate BEFORE state so isActive reflects completion
    _bgDelegate.onProgress(event);

    final syncStartedAt =
        prev?.lastSyncStartedAt ??
        (event.isSyncing || event.isComplete ? DateTime.now() : null);
    final syncCompletedAt = event.isComplete
        ? DateTime.now()
        : prev?.lastSyncCompletedAt;
    final actualPercentage = _clampProgress(event.percentage);
    final maxDisplayPercentage = event.isComplete
        ? 1.0
        : _maxIncompleteDisplayPercentage;
    final displayPercentage = event.isComplete
        ? 1.0
        : math.min(actualPercentage, maxDisplayPercentage);

    state = AsyncData(
      SyncState(
        accountUuid: stateAccountUuid,
        hasBalanceData: hasBalanceData,
        hasRecentTransactionsData: hasRecentTransactionsData,
        isSyncing: event.isSyncing && !event.isComplete,
        isBackgroundMode: event.isBackground || _bgDelegate.isActive,
        percentage: actualPercentage,
        displayPercentage: displayPercentage,
        scannedHeight: event.scannedHeight,
        chainTipHeight: event.chainTipHeight,
        transparentBalance: useFetchedAccountData
            ? transparent ?? stateScopedPrev?.transparentBalance
            : stateScopedPrev?.transparentBalance,
        saplingBalance: useFetchedAccountData
            ? sapling ?? stateScopedPrev?.saplingBalance
            : stateScopedPrev?.saplingBalance,
        orchardBalance: useFetchedAccountData
            ? orchard ?? stateScopedPrev?.orchardBalance
            : stateScopedPrev?.orchardBalance,
        transparentPendingBalance: useFetchedAccountData
            ? transparentPending ?? stateScopedPrev?.transparentPendingBalance
            : stateScopedPrev?.transparentPendingBalance,
        saplingPendingBalance: useFetchedAccountData
            ? saplingPending ?? stateScopedPrev?.saplingPendingBalance
            : stateScopedPrev?.saplingPendingBalance,
        orchardPendingBalance: useFetchedAccountData
            ? orchardPending ?? stateScopedPrev?.orchardPendingBalance
            : stateScopedPrev?.orchardPendingBalance,
        canShieldTransparentBalance: useFetchedAccountData
            ? canShieldTransparentBalance ??
                  stateScopedPrev?.canShieldTransparentBalance ??
                  false
            : stateScopedPrev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: useFetchedAccountData
            ? shieldTransparentFee ?? stateScopedPrev?.shieldTransparentFee
            : stateScopedPrev?.shieldTransparentFee,
        shieldTransparentAmount: useFetchedAccountData
            ? shieldTransparentAmount ??
                  stateScopedPrev?.shieldTransparentAmount
            : stateScopedPrev?.shieldTransparentAmount,
        spendableBalance: useFetchedAccountData
            ? spendable ?? stateScopedPrev?.spendableBalance
            : stateScopedPrev?.spendableBalance,
        totalBalance: useFetchedAccountData
            ? total ?? stateScopedPrev?.totalBalance
            : stateScopedPrev?.totalBalance,
        recentTransactions: useFetchedAccountData
            ? recentTxs
            : stateScopedPrev?.recentTransactions ?? const [],
        lastSyncStartedAt: syncStartedAt,
        lastSyncCompletedAt: syncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
        phase: event.phase,
      ),
    );

    if (event.isComplete || !event.isSyncing || _bgDelegate.isActive) {
      _stopDisplayProgressTimer();
    } else {
      _startDisplayProgressSmoothing(
        basePercentage: displayPercentage,
        targetPercentage: event.displayTargetPercentage,
        targetBlocks: event.displayTargetBlocks,
      );
    }

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
      _stopDisplayProgressTimer();
      state = AsyncData(SyncState());
      return;
    }
    final epoch = _sensitiveStateEpoch;
    final prev = state.value;
    final dbPath = await _getDbPath();
    final network = _endpointConfig.networkName;
    final accountUuid = _getActiveAccountUuid();
    if (accountUuid == null) {
      log('SyncNotifier: no active account, skipping refresh');
      return;
    }
    final scopedPrev = _previousScopedState(prev, accountUuid);

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
    var didFetchBalance = false;
    var didFetchRecentTxs = false;
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
      didFetchBalance = true;
    } catch (e) {
      _logRefreshReadError(
        label: 'balance',
        fallback: 'keeping previous value',
        error: e,
      );
    }

    var recentTxs =
        scopedPrev?.recentTransactions ?? const <rust_sync.TransactionInfo>[];
    try {
      recentTxs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: network,
        limit: 10,
        accountUuid: accountUuid,
      );
      didFetchRecentTxs = true;
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
          transparent ?? scopedPrev?.transparentBalance ?? BigInt.zero,
    );
    if (shieldStatus != null) {
      canShieldTransparentBalance = shieldStatus.canShield;
      shieldTransparentFee = shieldStatus.fee;
      shieldTransparentAmount = shieldStatus.amount;
    }

    if (epoch != _sensitiveStateEpoch ||
        _requiresUnlock ||
        accountUuid != _getActiveAccountUuid()) {
      log(
        'SyncNotifier: discarding balance refresh after account or lock transition',
      );
      return;
    }

    // Commit against the latest state so a slow balance/history refresh
    // cannot roll sync progress or completion metadata back to the snapshot
    // captured before the awaits above.
    final current = state.value;
    final currentScoped = _previousScopedState(current, accountUuid);
    final accountFallback = currentScoped ?? scopedPrev;

    state = AsyncData(
      SyncState(
        accountUuid: accountUuid,
        hasBalanceData:
            didFetchBalance || (accountFallback?.hasBalanceData ?? false),
        hasRecentTransactionsData:
            didFetchRecentTxs ||
            (accountFallback?.hasRecentTransactionsData ?? false),
        isSyncing: current?.isSyncing ?? false,
        isBackgroundMode: current?.isBackgroundMode ?? _bgDelegate.isActive,
        percentage: current?.percentage ?? 0.0,
        displayPercentage:
            current?.displayPercentage ?? current?.percentage ?? 0.0,
        scannedHeight: current?.scannedHeight ?? 0,
        chainTipHeight: current?.chainTipHeight ?? 0,
        transparentBalance: transparent ?? accountFallback?.transparentBalance,
        saplingBalance: sapling ?? accountFallback?.saplingBalance,
        orchardBalance: orchard ?? accountFallback?.orchardBalance,
        transparentPendingBalance:
            transparentPending ?? accountFallback?.transparentPendingBalance,
        saplingPendingBalance:
            saplingPending ?? accountFallback?.saplingPendingBalance,
        orchardPendingBalance:
            orchardPending ?? accountFallback?.orchardPendingBalance,
        canShieldTransparentBalance:
            canShieldTransparentBalance ??
            accountFallback?.canShieldTransparentBalance ??
            false,
        shieldTransparentFee:
            shieldTransparentFee ?? accountFallback?.shieldTransparentFee,
        shieldTransparentAmount:
            shieldTransparentAmount ?? accountFallback?.shieldTransparentAmount,
        spendableBalance: spendable ?? accountFallback?.spendableBalance,
        totalBalance: total ?? accountFallback?.totalBalance,
        failure: current?.failure,
        error: current?.error,
        recentTransactions: didFetchRecentTxs
            ? recentTxs
            : accountFallback?.recentTransactions ?? const [],
        lastSyncStartedAt: current?.lastSyncStartedAt,
        lastSyncCompletedAt: current?.lastSyncCompletedAt,
        lastSyncFailedAt: current?.lastSyncFailedAt,
        phase: current?.phase ?? '',
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

  RpcEndpointConfig get _endpointConfig =>
      ref.read(rpcEndpointFailoverProvider).current;
}

final syncProvider = AsyncNotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
