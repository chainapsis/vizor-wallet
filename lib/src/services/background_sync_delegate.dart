import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../main.dart' show log;
import '../rust/api/sync.dart' as rust_sync;
import 'background_sync_service.dart' as bg_sync;

const _progressChannel = EventChannel('com.zcash.wallet/sync_progress');

/// Progress event DTO shared between FRB stream and EventChannel paths.
class SyncProgressEvent {
  final int scannedHeight;
  final int chainTipHeight;
  final double percentage;
  final bool isSyncing;
  final bool isComplete;
  final bool hasNewTx;
  final bool isBackground;

  const SyncProgressEvent({
    required this.scannedHeight,
    required this.chainTipHeight,
    required this.percentage,
    required this.isSyncing,
    required this.isComplete,
    required this.hasNewTx,
    this.isBackground = false,
  });
}

/// Abstract delegate for platform-specific background sync behavior.
abstract class BackgroundSyncDelegate {
  bool get isActive;

  void setupListeners({
    required void Function() onStopRequested,
    required void Function(SyncProgressEvent) onBackgroundProgress,
  });

  void disposeListeners();

  Future<void> enable();
  Future<void> disable();
  Future<bool> isAvailable();

  void onSyncDone();
  void onResume();
  void onProgress(SyncProgressEvent event);

  static BackgroundSyncDelegate create() {
    if (Platform.isAndroid) return AndroidBackgroundSyncDelegate();
    if (Platform.isIOS) return IOSBackgroundSyncDelegate();
    return NoOpBackgroundSyncDelegate();
  }
}

// ======================== Android ========================

class AndroidBackgroundSyncDelegate implements BackgroundSyncDelegate {
  bool _active = false;

  @override
  bool get isActive => _active;

  @override
  void setupListeners({
    required void Function() onStopRequested,
    required void Function(SyncProgressEvent) onBackgroundProgress,
  }) {
    FlutterForegroundTask.receivePort?.listen((message) {
      if (message == 'stop_sync') {
        log('BackgroundSyncDelegate(Android): stop requested from notification');
        onStopRequested();
      }
    });
  }

  @override
  void disposeListeners() {}

  @override
  Future<void> enable() async {
    _active = true;
    await bg_sync.startBackgroundSync();
    log('BackgroundSyncDelegate(Android): enabled');
  }

  @override
  Future<void> disable() async {
    _active = false;
    await bg_sync.stopBackgroundSync();
    log('BackgroundSyncDelegate(Android): disabled');
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  void onSyncDone() {
    if (_active) {
      _active = false;
      bg_sync.stopBackgroundSync().catchError((e) {
        log('BackgroundSyncDelegate(Android): failed to stop background service: $e');
      });
      log('BackgroundSyncDelegate(Android): sync completed, notification removed');
    }
  }

  @override
  void onResume() {}

  @override
  void onProgress(SyncProgressEvent event) {
    if (_active) {
      bg_sync.updateBackgroundSyncProgress(
        percentage: event.percentage,
        scannedHeight: event.scannedHeight,
        chainTipHeight: event.chainTipHeight,
      );
    }
  }
}

// ======================== iOS ========================

class IOSBackgroundSyncDelegate implements BackgroundSyncDelegate {
  bool _active = false;
  StreamSubscription? _eventChannelSub;

  @override
  bool get isActive => _active;

  @override
  void setupListeners({
    required void Function() onStopRequested,
    required void Function(SyncProgressEvent) onBackgroundProgress,
  }) {
    _eventChannelSub = _progressChannel.receiveBroadcastStream().listen(
      (event) {
        try {
          final map = event as Map;
          onBackgroundProgress(SyncProgressEvent(
            scannedHeight: (map['scannedHeight'] as num?)?.toInt() ?? 0,
            chainTipHeight: (map['chainTipHeight'] as num?)?.toInt() ?? 0,
            percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
            isSyncing: map['isSyncing'] as bool? ?? false,
            isComplete: map['isComplete'] as bool? ?? false,
            hasNewTx: map['hasNewTx'] as bool? ?? false,
            isBackground: true,
          ));
        } catch (e) {
          log('BackgroundSyncDelegate(iOS): failed to parse progress event: $e');
        }
      },
      onError: (e) {
        log('BackgroundSyncDelegate(iOS): EventChannel error: $e');
      },
    );
  }

  @override
  void disposeListeners() {
    _eventChannelSub?.cancel();
  }

  @override
  Future<void> enable() async {
    _active = true;
    rust_sync.setSyncMode(mode: 2);
    await bg_sync.startBackgroundSync();
    log('BackgroundSyncDelegate(iOS): enabled');
  }

  @override
  Future<void> disable() async {
    rust_sync.setSyncMode(mode: 1);
    await bg_sync.stopBackgroundSync();
    var waited = 0;
    while (rust_sync.isSyncRunning() && waited < 120000) {
      await Future.delayed(const Duration(milliseconds: 200));
      waited += 200;
    }
    if (rust_sync.isSyncRunning()) {
      log('BackgroundSyncDelegate(iOS): WARNING: timed out waiting for bg sync to stop');
    }
    _active = false;
    log('BackgroundSyncDelegate(iOS): disabled');
  }

  @override
  Future<bool> isAvailable() => bg_sync.isBackgroundSyncAvailable();

  @override
  void onSyncDone() {}

  @override
  void onResume() {
    if (_active) {
      if (!rust_sync.isSyncRunning()) {
        log('BackgroundSyncDelegate(iOS): bg sync finished while backgrounded');
        _active = false;
      } else if (rust_sync.getSyncMode() == 0) {
        log('BackgroundSyncDelegate(iOS): bg sync expired');
        _active = false;
      }
    }
  }

  @override
  void onProgress(SyncProgressEvent event) {
    if (event.isBackground && event.isComplete && _active) {
      log('BackgroundSyncDelegate(iOS): bg sync completed');
      _active = false;
    }
  }
}

// ======================== NoOp (macOS/desktop) ========================

class NoOpBackgroundSyncDelegate implements BackgroundSyncDelegate {
  @override
  bool get isActive => false;

  @override
  void setupListeners({
    required void Function() onStopRequested,
    required void Function(SyncProgressEvent) onBackgroundProgress,
  }) {}

  @override
  void disposeListeners() {}

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  Future<bool> isAvailable() async => false;

  @override
  void onSyncDone() {}

  @override
  void onResume() {}

  @override
  void onProgress(SyncProgressEvent event) {}
}
