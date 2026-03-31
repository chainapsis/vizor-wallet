import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../rust/api/sync.dart' as rust_sync;

const _pollIntervalMs = 2000;
const _iosBackgroundSyncChannel =
    MethodChannel('com.zcash.wallet/background_sync');

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

  @override
  Future<SyncState> build() async {
    ref.onDispose(() {
      _pollTimer?.cancel();
    });
    return SyncState();
  }

  Future<void> startSync() async {
    _backgroundMode = false;
    state = AsyncData(SyncState(isSyncing: true));

    _startProgressPolling();

    try {
      final dbPath = await _getDbPath();
      final network = ZcashNetwork.mainnet;

      log('Sync: starting full sync via Rust');
      await rust_sync.startFullSync(
        dbPath: dbPath,
        lightwalletdUrl: network.lightwalletdUrl,
        network: network.name,
      );
      log('Sync: full sync completed');
    } catch (e, st) {
      log('SyncNotifier: ERROR: $e\n$st');
      state = AsyncData(SyncState(error: e.toString()));
    } finally {
      _pollTimer?.cancel();
      _backgroundMode = false;
      await _updateProgress();
    }
  }

  void stopSync() {
    rust_sync.cancelFullSync();
    _pollTimer?.cancel();
    _backgroundMode = false;
  }

  /// Enable background sync (iOS 26+ only via BGContinuedProcessingTask).
  Future<void> enableBackgroundSync() async {
    if (_backgroundMode) return;
    if (!Platform.isIOS) return;

    try {
      final success = await _iosBackgroundSyncChannel
          .invokeMethod<bool>('startBackgroundSync');
      if (success == true) {
        _backgroundMode = true;
        log('SyncNotifier: iOS background sync submitted');
      }
    } catch (e) {
      log('SyncNotifier: background sync failed: $e');
    }
  }

  /// Check if background sync is available on this device.
  static Future<bool> isBackgroundSyncAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      final available = await _iosBackgroundSyncChannel
          .invokeMethod<bool>('isAvailable');
      return available ?? false;
    } catch (_) {
      return false;
    }
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

      if (scanned != _lastLoggedHeight) {
        log('Sync: ${(pct * 100).toStringAsFixed(1)}% ($scanned/$tip)');
        _lastLoggedHeight = scanned;
      }

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
