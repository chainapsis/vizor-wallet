import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/wallet.dart' as rust_wallet;
import 'account_provider.dart';
import '../services/background_sync_service.dart' as bg_sync;

const _progressChannel = EventChannel('com.zcash.wallet/sync_progress');

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
  bool _backgroundMode = false;
  bool _isSyncing = false;
  bool _isInForeground = true;
  int _lastLoggedHeight = 0;
  String? _cachedDbPath;
  StreamSubscription? _syncSub;
  StreamSubscription? _eventChannelSub;
  AppLifecycleListener? _lifecycleListener;
  Timer? _pollTimer;

  @override
  Future<SyncState> build() async {
    // Listen for iOS background sync progress via EventChannel
    if (Platform.isIOS) {
      _eventChannelSub = _progressChannel.receiveBroadcastStream().listen(
        (event) {
          final map = event as Map;
          _onSyncProgress(
            scannedHeight: (map['scannedHeight'] as num).toInt(),
            chainTipHeight: (map['chainTipHeight'] as num).toInt(),
            percentage: (map['percentage'] as num).toDouble(),
            isBackground: true,
            isSyncing: map['isSyncing'] as bool,
            isComplete: map['isComplete'] as bool,
            hasNewTx: map['hasNewTx'] as bool,
          );
        },
        onError: (e) { log('SyncNotifier: EventChannel error: $e'); },
      );
    }

    // Listen for Android foreground service stop signal
    FlutterForegroundTask.receivePort?.listen((message) {
      if (message == 'stop_sync') {
        log('SyncNotifier: received stop_sync from notification');
        stopSync();
      }
    });

    // App lifecycle management
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _isInForeground = true;
        _refreshBalance();
        if (_backgroundMode) {
          if (!rust_sync.isSyncRunning()) {
            log('SyncNotifier: background sync finished while backgrounded');
            _backgroundMode = false;
          } else if (rust_sync.getSyncMode() == 0) {
            log('SyncNotifier: background sync expired');
            _backgroundMode = false;
          }
        }
        _checkAndSync();
        _startPolling();
      },
      onHide: () {
        _isInForeground = false;
        _stopPolling();
      },
    );

    ref.onDispose(() {
      _syncSub?.cancel();
      _eventChannelSub?.cancel();
      _lifecycleListener?.dispose();
      _pollTimer?.cancel();
    });

    // Auto-start sync when accounts become available (without triggering rebuild)
    ref.listen(accountProvider, (prev, next) {
      final hadAccounts = prev?.value?.hasAccounts ?? false;
      final hasAccounts = next.value?.hasAccounts ?? false;
      if (!hadAccounts && hasAccounts) {
        _autoSync();
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
    _backgroundMode = false;
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

      final completer = Completer<void>();
      _syncSub = stream.listen(
        (event) => _onSyncProgress(
          scannedHeight: event.scannedHeight.toInt(),
          chainTipHeight: event.chainTipHeight.toInt(),
          percentage: event.percentage,
          isBackground: false,
          isSyncing: event.isSyncing,
          isComplete: event.isComplete,
          hasNewTx: event.hasNewTx,
        ),
        onDone: () {
          log('Sync: stream ended');
          _isSyncing = false;
          _onSyncDone();
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          log('Sync: stream error: $e');
          _isSyncing = false;
          state = AsyncData(SyncState(error: e.toString()));
          if (!completer.isCompleted) completer.completeError(e);
        },
      );

      await completer.future;
    } catch (e, st) {
      log('SyncNotifier: ERROR: $e\n$st');
      _isSyncing = false;
      state = AsyncData(SyncState(error: e.toString()));
    }
  }

  void stopSync() {
    rust_sync.cancelFullSync();
    _syncSub?.cancel();
    _syncSub = null;
    _isSyncing = false;
    if (_backgroundMode) {
      bg_sync.stopBackgroundSync();
      _backgroundMode = false;
    }
    // Stream is cancelled — no more events will arrive.
    // Update UI immediately to reflect stopped state.
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
    if (_backgroundMode) return;
    _backgroundMode = true;

    if (Platform.isAndroid) {
      // Android: just add notification, sync continues via same FRB stream
      await bg_sync.startBackgroundSync();
    } else if (Platform.isIOS) {
      // iOS: switch mode → Rust foreground sync exits → BGTask takes over
      rust_sync.setSyncMode(mode: 2);
      await bg_sync.startBackgroundSync();
    }

    log('SyncNotifier: background sync enabled');
  }

  Future<void> disableBackgroundSync() async {
    if (!_backgroundMode) return;
    _backgroundMode = false;

    if (Platform.isAndroid) {
      // Android: just remove notification, sync continues
      await bg_sync.stopBackgroundSync();
    } else if (Platform.isIOS) {
      // iOS: switch mode → Rust background sync exits at next batch
      rust_sync.setSyncMode(mode: 1);
      await bg_sync.stopBackgroundSync();
      // Wait for background sync to stop (max 120 seconds)
      var waited = 0;
      while (rust_sync.isSyncRunning() && waited < 120000) {
        await Future.delayed(const Duration(milliseconds: 200));
        waited += 200;
      }
      if (rust_sync.isSyncRunning()) {
        log('SyncNotifier: WARNING: timed out waiting for bg sync to stop');
      }
      startSync();
    }

    log('SyncNotifier: background sync disabled');
  }

  static Future<bool> isBackgroundSyncAvailable() async {
    return bg_sync.isBackgroundSyncAvailable();
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
    if (!_isInForeground || _backgroundMode) return;
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
    if (_isSyncing || _backgroundMode || !_isInForeground) return;
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
    // Android background sync uses the same FRB stream (isBackground is always false),
    // so the EventChannel-based completion check doesn't apply. Reset here instead.
    if (_backgroundMode && Platform.isAndroid) {
      log('SyncNotifier: Android background sync completed, switching to foreground mode');
      _backgroundMode = false;
    }
    _refreshBalance();
  }

  Future<void> _onSyncProgress({
    required int scannedHeight,
    required int chainTipHeight,
    required double percentage,
    required bool isBackground,
    required bool isSyncing,
    required bool isComplete,
    required bool hasNewTx,
  }) async {
    if (scannedHeight != _lastLoggedHeight) {
      log('Sync: ${(percentage * 100).toStringAsFixed(1)}% ($scannedHeight/$chainTipHeight)');
      _lastLoggedHeight = scannedHeight;
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
    if (hasNewTx || isComplete) {
      try {
        recentTxs = await rust_sync.getTransactionHistory(dbPath: dbPath, network: network, limit: 10, accountUuid: accountUuid);
      } catch (e) {
        log('SyncNotifier: tx history fetch failed: $e');
      }
    }

    state = AsyncData(SyncState(
      isSyncing: isSyncing && !isComplete,
      isBackgroundMode: isBackground || _backgroundMode,
      percentage: percentage,
      scannedHeight: scannedHeight,
      chainTipHeight: chainTipHeight,
      transparentBalance: transparent ?? prev?.transparentBalance,
      saplingBalance: sapling ?? prev?.saplingBalance,
      orchardBalance: orchard ?? prev?.orchardBalance,
      totalBalance: total ?? prev?.totalBalance,
      recentTransactions: recentTxs,
    ));

    // Background sync completed → switch back to foreground mode
    if (isBackground && isComplete && _backgroundMode) {
      log('SyncNotifier: background sync completed, switching to foreground mode');
      _backgroundMode = false;
      _startPolling();
    }

    // Update Android notification
    if (_backgroundMode && Platform.isAndroid) {
      bg_sync.updateBackgroundSyncProgress(
        percentage: percentage,
        scannedHeight: scannedHeight,
        chainTipHeight: chainTipHeight,
      );
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
      isBackgroundMode: _backgroundMode,
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
