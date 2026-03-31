import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../services/background_sync_service.dart' as bg_sync;
import '../services/live_activity_service.dart';

const _pollIntervalMs = 2000;

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

  @override
  Future<SyncState> build() async {
    ref.onDispose(() {
      _pollTimer?.cancel();
      if (_backgroundMode) bg_sync.stopBackgroundSync();
    });

    // Listen for stop signal from Android foreground service notification
    FlutterForegroundTask.receivePort?.listen((message) {
      if (message == 'stop_sync') {
        log('SyncNotifier: received stop_sync from notification');
        stopSync();
      }
    });

    return SyncState();
  }

  Future<void> startSync() async {
    _backgroundMode = false;
    state = AsyncData(SyncState(isSyncing: true));

    // Start polling for progress
    _startProgressPolling();

    try {
      final dbPath = await _getDbPath();
      final cachePath = await _getCachePath();
      final network = ZcashNetwork.mainnet;

      log('Sync: starting full sync via Rust');
      await rust_sync.startFullSync(
        dbPath: dbPath,
        cachePath: cachePath,
        lightwalletdUrl: network.lightwalletdUrl,
        network: network.name,
      );
      log('Sync: full sync completed');
    } catch (e, st) {
      log('SyncNotifier: ERROR: $e\n$st');
      state = AsyncData(SyncState(error: e.toString()));
    } finally {
      _pollTimer?.cancel();
      if (_backgroundMode) {
        await bg_sync.stopBackgroundSync();
        await LiveActivityService.instance.stopSyncActivity();
        _backgroundMode = false;
      }
      // Final progress update
      await _updateProgress();
    }
  }

  void stopSync() {
    rust_sync.cancelFullSync();
    _pollTimer?.cancel();
    if (_backgroundMode) {
      bg_sync.stopBackgroundSync();
      LiveActivityService.instance.stopSyncActivity();
      _backgroundMode = false;
    }
  }

  Future<void> enableBackgroundSync() async {
    if (_backgroundMode) return;
    _backgroundMode = true;
    await bg_sync.startBackgroundSync();
    await LiveActivityService.instance.startSyncActivity();
    log('SyncNotifier: background sync enabled');
  }

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

      // Update background notification/Dynamic Island
      if (_backgroundMode) {
        bg_sync.updateBackgroundSyncProgress(
          percentage: pct,
          scannedHeight: scanned,
          chainTipHeight: tip,
        );
        await LiveActivityService.instance.updateProgress(
          percentage: pct,
          scannedHeight: scanned,
          chainTipHeight: tip,
        );
      }
    } catch (e) {
      // Polling error — ignore, will retry
    }
  }

  Future<String> _getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
  }

  Future<String> _getCachePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}${Platform.pathSeparator}zcash_cache';
    await Directory(path).create(recursive: true);
    return path;
  }
}

final syncProvider =
    AsyncNotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);
