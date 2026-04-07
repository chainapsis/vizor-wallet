import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' show Platform;

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/wallet.dart' as rust_wallet;
import '../services/background_sync_delegate.dart';
import 'account_provider.dart';

class SyncState {
  final bool isSyncing;
  final bool isBackgroundMode;
  final double percentage;
  final int scannedHeight;
  final int chainTipHeight;
  final BigInt transparentBalance;
  final BigInt saplingBalance;
  final BigInt orchardBalance;
  final BigInt totalBalance;
  final String? error;
  final List<rust_sync.TransactionInfo> recentTransactions;

  SyncState({
    this.isSyncing = false,
    this.isBackgroundMode = false,
    this.percentage = 0,
    this.scannedHeight = 0,
    this.chainTipHeight = 0,
    BigInt? transparentBalance,
    BigInt? saplingBalance,
    BigInt? orchardBalance,
    BigInt? totalBalance,
    this.error,
    this.recentTransactions = const [],
  })  : transparentBalance = transparentBalance ?? BigInt.zero,
        saplingBalance = saplingBalance ?? BigInt.zero,
        orchardBalance = orchardBalance ?? BigInt.zero,
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
    BigInt? totalBalance,
    String? error,
    List<rust_sync.TransactionInfo>? recentTransactions,
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
      totalBalance: totalBalance ?? this.totalBalance,
      error: error ?? this.error,
      recentTransactions: recentTransactions ?? this.recentTransactions,
    );
  }
}

class SyncNotifier extends AsyncNotifier<SyncState> {
  late final BackgroundSyncDelegate _bgDelegate;
  bool _isSyncing = false;
  bool _isInForeground = true;
  int _lastLoggedHeight = 0;
  String? _cachedDbPath;
  StreamSubscription? _syncSub;
  Completer<void>? _syncCompleter;
  AppLifecycleListener? _lifecycleListener;
  Timer? _pollTimer;

  @override
  Future<SyncState> build() async {
    // Platform-specific background sync delegate
    _bgDelegate = BackgroundSyncDelegate.create();
    _bgDelegate.setupListeners(
      onStopRequested: () => stopSync(),
      onBackgroundProgress: (event) {
        _onSyncProgress(event).catchError((e, st) {
          log('SyncNotifier: background progress handling failed: $e');
        });
      },
    );

    // App lifecycle management
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _isInForeground = true;
        _refreshBalance();
        _bgDelegate.onResume();
        _checkAndSync(); // _checkAndSync calls _startPolling() on completion
      },
      onHide: () {
        _isInForeground = false;
        _stopPolling();
      },
    );

    ref.onDispose(() {
      _syncSub?.cancel();
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
    // 1. First account created (0→1): _autoSync starts sync + polling.
    // 2. Additional account added (N→N+1): startSync rescans from the new
    //    account's birthday height. Without this, the new account would show
    //    empty until a new block triggers polling, since _checkAndSync only
    //    compares chain tip (not account-level scan progress).
    ref.listen(accountProvider, (prev, next) {
      final prevCount = prev?.value?.accounts.length ?? 0;
      final nextCount = next.value?.accounts.length ?? 0;
      if (prevCount == 0 && nextCount > 0) {
        _autoSync();
      } else if (nextCount > prevCount) {
        startSync();
      }
    });

    // Initial check: if accounts already exist at build time
    final accountState = ref.read(accountProvider).value;
    if (accountState != null && accountState.hasAccounts) {
      Future.microtask(() => _autoSync());
    }

    return SyncState();
  }

  // ======================== Sync Control ========================

  Future<void> startSync() async {
    if (_isSyncing || rust_sync.isSyncRunning()) {
      log('Sync: already running, skipping');
      return;
    }
    _isSyncing = true;
    _lastLoggedHeight = 0;
    state = AsyncData(SyncState(isSyncing: true));

    try {
      final dbPath = await _getDbPath();
      final network = ZcashNetwork.mainnet;

      log('Sync: starting foreground sync');
      final stream = rust_sync.startFullSync(
        dbPath: dbPath,
        lightwalletdUrl: network.lightwalletdUrl,
        network: network.name,
        mode: 1, // foreground
      );

      _syncCompleter = Completer<void>();
      _syncSub = stream.listen(
        (event) => _onSyncProgress(SyncProgressEvent(
          scannedHeight: event.scannedHeight.toInt(),
          chainTipHeight: event.chainTipHeight.toInt(),
          percentage: event.percentage,
          isSyncing: event.isSyncing,
          isComplete: event.isComplete,
          hasNewTx: event.hasNewTx,
        )),
        onDone: () {
          log('Sync: stream ended');
          _isSyncing = false;
          _onSyncDone();
          if (_syncCompleter != null && !_syncCompleter!.isCompleted) _syncCompleter!.complete();
        },
        onError: (e) {
          log('Sync: stream error: $e');
          _isSyncing = false;
          state = AsyncData(SyncState(error: e.toString()));
          if (_syncCompleter != null && !_syncCompleter!.isCompleted) _syncCompleter!.completeError(e);
        },
      );

      await _syncCompleter!.future;
    } catch (e, st) {
      log('SyncNotifier: ERROR: $e\n$st');
      _isSyncing = false;
      state = AsyncData(SyncState(error: e.toString()));
    }
  }

  Future<void> stopSync() async {
    rust_sync.cancelFullSync();
    _syncSub?.cancel();
    _syncSub = null;
    _isSyncing = false;
    _stopPolling(); // user-initiated stop should also stop auto-retry polling
    if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
      _syncCompleter!.complete();
    }
    _syncCompleter = null;
    if (_bgDelegate.isActive) {
      await _bgDelegate.disable();
    }
    final prev = state.value;
    state = AsyncData(SyncState(
      isSyncing: false,
      isBackgroundMode: false,
      percentage: prev?.percentage ?? 0.0,
      scannedHeight: prev?.scannedHeight ?? 0,
      chainTipHeight: prev?.chainTipHeight ?? 0,
      transparentBalance: prev?.transparentBalance,
      saplingBalance: prev?.saplingBalance,
      orchardBalance: prev?.orchardBalance,
      totalBalance: prev?.totalBalance,
      recentTransactions: prev?.recentTransactions ?? const [],
    ));
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
      await startSync();
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

  // ======================== Auto-Sync & Polling ========================

  Future<void> _autoSync() async {
    try {
      await startSync();
    } catch (e, st) {
      log('SyncNotifier: autoSync failed: $e\n$st');
      state = AsyncData(SyncState(error: 'Auto-sync failed: $e'));
    }
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_isInForeground || _bgDelegate.shouldSuppressPolling) return;
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        try {
          await _checkAndSync();
        } catch (e) {
          log('AutoSync: polling error: $e');
        }
      },
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkAndSync() async {
    if (_isSyncing || _bgDelegate.shouldSuppressPolling || !_isInForeground) return;
    _stopPolling();
    try {
      final tip = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
      );
      final lastSynced = state.value?.chainTipHeight ?? 0;
      final syncComplete = (state.value?.percentage ?? 0) >= 1.0;
      if (!syncComplete || tip.toInt() > lastSynced) {
        log('AutoSync: needs sync (tip=$tip, last=$lastSynced, complete=$syncComplete)');
        await startSync();
      }
    } catch (e) {
      log('AutoSync: tip check failed: $e');
    }
    _startPolling();
  }

  // ======================== Progress Handling ========================

  void _onSyncDone() {
    _syncSub = null;
    _bgDelegate.onSyncDone();
    _refreshBalance();
    _startPolling();
  }

  Future<void> _onSyncProgress(SyncProgressEvent event) async {
    if (event.scannedHeight != _lastLoggedHeight) {
      log('Sync: ${(event.percentage * 100).toStringAsFixed(1)}% (${event.scannedHeight}/${event.chainTipHeight})');
      _lastLoggedHeight = event.scannedHeight;
    }

    final prev = state.value;
    final dbPath = await _getDbPath();
    final network = ZcashNetwork.mainnet.name;
    final accountUuid = _getActiveAccountUuid();
    if (accountUuid == null) { log('SyncNotifier: no active account, skipping refresh'); return; }

    BigInt? transparent, sapling, orchard, total;
    try {
      final balance = await rust_sync.getBalance(dbPath: dbPath, network: network, accountUuid: accountUuid);
      transparent = balance.transparent;
      sapling = balance.sapling;
      orchard = balance.orchard;
      total = balance.total;
    } catch (e) {
      log('SyncNotifier: balance fetch failed: $e');
    }

    var recentTxs = prev?.recentTransactions ?? const <rust_sync.TransactionInfo>[];
    if (event.hasNewTx || event.isComplete) {
      try {
        recentTxs = await rust_sync.getTransactionHistory(dbPath: dbPath, network: network, limit: 10, accountUuid: accountUuid);
      } catch (e) {
        log('SyncNotifier: tx history fetch failed: $e');
      }
    }

    // Update delegate BEFORE state so isActive reflects completion
    _bgDelegate.onProgress(event);

    state = AsyncData(SyncState(
      isSyncing: event.isSyncing && !event.isComplete,
      isBackgroundMode: event.isBackground || _bgDelegate.isActive,
      percentage: event.percentage,
      scannedHeight: event.scannedHeight,
      chainTipHeight: event.chainTipHeight,
      transparentBalance: transparent ?? prev?.transparentBalance,
      saplingBalance: sapling ?? prev?.saplingBalance,
      orchardBalance: orchard ?? prev?.orchardBalance,
      totalBalance: total ?? prev?.totalBalance,
      recentTransactions: recentTxs,
    ));

    // If background sync completed, start polling for next sync cycle
    if (event.isBackground && event.isComplete && !_bgDelegate.isActive) {
      _startPolling();
    }
  }

  // ======================== Balance Refresh ========================

  /// Public: refresh balance and recent transactions (e.g. after send).
  Future<void> refreshAfterSend() => _refreshBalance();

  Future<void> _refreshBalance() async {
    final prev = state.value;
    final dbPath = await _getDbPath();
    final network = ZcashNetwork.mainnet.name;
    final accountUuid = _getActiveAccountUuid();
    if (accountUuid == null) { log('SyncNotifier: no active account, skipping refresh'); return; }

    BigInt? transparent, sapling, orchard, total;
    try {
      final balance = await rust_sync.getBalance(dbPath: dbPath, network: network, accountUuid: accountUuid);
      transparent = balance.transparent;
      sapling = balance.sapling;
      orchard = balance.orchard;
      total = balance.total;
    } catch (e) {
      log('SyncNotifier: balance refresh failed: $e');
    }

    var recentTxs = prev?.recentTransactions ?? const <rust_sync.TransactionInfo>[];
    try {
      recentTxs = await rust_sync.getTransactionHistory(dbPath: dbPath, network: network, limit: 10, accountUuid: accountUuid);
    } catch (e) {
      log('SyncNotifier: tx history refresh failed: $e');
    }

    state = AsyncData(SyncState(
      isSyncing: prev?.isSyncing ?? false,
      isBackgroundMode: _bgDelegate.isActive,
      percentage: prev?.percentage ?? 0.0,
      scannedHeight: prev?.scannedHeight ?? 0,
      chainTipHeight: prev?.chainTipHeight ?? 0,
      transparentBalance: transparent ?? prev?.transparentBalance,
      saplingBalance: sapling ?? prev?.saplingBalance,
      orchardBalance: orchard ?? prev?.orchardBalance,
      totalBalance: total ?? prev?.totalBalance,
      recentTransactions: recentTxs,
    ));
  }

  String? _getActiveAccountUuid() {
    return ref.read(accountProvider).value?.activeAccountUuid;
  }

  Future<String> _getDbPath() async {
    if (_cachedDbPath != null) return _cachedDbPath!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedDbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
    return _cachedDbPath!;
  }
}

final syncProvider =
    AsyncNotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);
