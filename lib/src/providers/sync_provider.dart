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
import '../services/background_sync_service.dart' as bg_sync;

const _pollIntervalMs = 10000;
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
  })  : transparentBalance = transparentBalance ?? BigInt.zero,
        saplingBalance = saplingBalance ?? BigInt.zero,
        orchardBalance = orchardBalance ?? BigInt.zero,
        totalBalance = totalBalance ?? BigInt.zero;
}

class SyncNotifier extends AsyncNotifier<SyncState> {
  bool _backgroundMode = false;
  Timer? _pollTimer;
  int _lastLoggedHeight = 0;
  String? _cachedDbPath;
  StreamSubscription? _syncSub;
  StreamSubscription? _eventChannelSub;
  AppLifecycleListener? _lifecycleListener;

  @override
  Future<SyncState> build() async {
    // Listen for iOS background sync progress via EventChannel
    _eventChannelSub = _progressChannel.receiveBroadcastStream().listen(
      (event) {
        final map = event as Map;
        _onSyncProgress(
          scannedHeight: (map['scannedHeight'] as num).toInt(),
          chainTipHeight: (map['chainTipHeight'] as num).toInt(),
          percentage: (map['percentage'] as num).toDouble(),
          isBackground: true,
        );
      },
      onError: (_) {},
    );

    // Listen for Android foreground service stop signal
    FlutterForegroundTask.receivePort?.listen((message) {
      if (message == 'stop_sync') {
        log('SyncNotifier: received stop_sync from notification');
        stopSync();
      }
    });

    // Refresh progress when app returns to foreground
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _updateProgress(),
    );

    ref.onDispose(() {
      _pollTimer?.cancel();
      _syncSub?.cancel();
      _eventChannelSub?.cancel();
      _lifecycleListener?.dispose();
    });

    return SyncState();
  }

  // ======================== Sync Control ========================

  Future<void> startSync() async {
    _backgroundMode = false;
    _lastLoggedHeight = 0;
    state = AsyncData(SyncState(isSyncing: true));

    _startProgressPolling();

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
        ),
        onDone: () {
          log('Sync: stream ended');
          _onSyncDone();
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          log('Sync: stream error: $e');
          state = AsyncData(SyncState(error: e.toString()));
          if (!completer.isCompleted) completer.completeError(e);
        },
      );

      await completer.future;
    } catch (e, st) {
      log('SyncNotifier: ERROR: $e\n$st');
      state = AsyncData(SyncState(error: e.toString()));
    }
  }

  void stopSync() {
    rust_sync.cancelFullSync();
    _syncSub?.cancel();
    _syncSub = null;
    _pollTimer?.cancel();
    if (_backgroundMode) {
      bg_sync.stopBackgroundSync();
      _backgroundMode = false;
    }
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
      // Keep polling for progress (EventChannel + fallback)
      _startProgressPolling();
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
      // Wait for background sync to actually stop before starting foreground
      while (rust_sync.isSyncRunning()) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      startSync();
    }

    log('SyncNotifier: background sync disabled');
  }

  static Future<bool> isBackgroundSyncAvailable() async {
    return bg_sync.isBackgroundSyncAvailable();
  }

  // ======================== Progress Handling ========================

  void _onSyncDone() {
    _pollTimer?.cancel();
    _syncSub = null;
    _updateProgress();

    // If mode switched to background, keep polling for updates
    if (_backgroundMode) {
      _startProgressPolling();
    }
  }

  Future<void> _onSyncProgress({
    required int scannedHeight,
    required int chainTipHeight,
    required double percentage,
    required bool isBackground,
    bool isSyncing = true,
    bool isComplete = false,
  }) async {
    if (scannedHeight != _lastLoggedHeight) {
      log('Sync: ${(percentage * 100).toStringAsFixed(1)}% ($scannedHeight/$chainTipHeight)');
      _lastLoggedHeight = scannedHeight;
    }

    try {
      final dbPath = await _getDbPath();
      final balance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: ZcashNetwork.mainnet.name,
      );

      state = AsyncData(SyncState(
        isSyncing: isSyncing && !isComplete,
        isBackgroundMode: isBackground || _backgroundMode,
        percentage: percentage,
        scannedHeight: scannedHeight,
        chainTipHeight: chainTipHeight,
        transparentBalance: balance.transparent,
        saplingBalance: balance.sapling,
        orchardBalance: balance.orchard,
        totalBalance: balance.total,
      ));
    } catch (_) {
      state = AsyncData(SyncState(
        isSyncing: isSyncing && !isComplete,
        isBackgroundMode: isBackground || _backgroundMode,
        percentage: percentage,
        scannedHeight: scannedHeight,
        chainTipHeight: chainTipHeight,
      ));
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

  // ======================== Polling Fallback ========================

  void _startProgressPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: _pollIntervalMs),
      (_) => _updateProgress(),
    );
  }

  Future<void> _updateProgress() async {
    try {
      final dbPath = await _getDbPath();
      final network = ZcashNetwork.mainnet;

      final progress = await rust_sync.getSyncStatus(
        dbPath: dbPath,
        network: network.name,
      );
      final balance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: network.name,
      );

      final scanned = progress.scannedHeight.toInt();
      final tip = progress.chainTipHeight.toInt();
      final pct = tip > 0 ? scanned / tip : 0.0;

      state = AsyncData(SyncState(
        isSyncing: progress.isSyncing,
        isBackgroundMode: _backgroundMode,
        percentage: pct,
        scannedHeight: scanned,
        chainTipHeight: tip,
        transparentBalance: balance.transparent,
        saplingBalance: balance.sapling,
        orchardBalance: balance.orchard,
        totalBalance: balance.total,
      ));
    } catch (e) {
      // Polling error — ignore, will retry
    }
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
