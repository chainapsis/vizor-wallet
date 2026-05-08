import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../main.dart' show log;
import '../core/config/rpc_endpoint_config.dart';
import '../rust/api/sync.dart' as rust_sync;
import 'background_sync_service.dart' as bg_sync;

const _progressChannel = EventChannel('com.zcash.wallet/sync_progress');
const syncEventKindProgress = 1;
const syncEventKindCompleted = 2;
const syncEventKindStopped = 3;

/// Native sync event DTO shared between FRB stream and EventChannel paths.
class NativeSyncEventV2 {
  final int kind;
  final BigInt runId;
  final BigInt sequence;
  final int scannedHeight;
  final int chainTipHeight;
  final double percentage;
  final double displayTargetPercentage;
  final int displayTargetBlocks;
  final bool hasNewTx;
  final bool isBackground;

  /// Current sync phase from Rust: `"download"`, `"scan"`,
  /// `"enhance"`, or `""` (unspecified / completion).
  final String phase;

  const NativeSyncEventV2({
    required this.kind,
    required this.runId,
    required this.sequence,
    required this.scannedHeight,
    required this.chainTipHeight,
    required this.percentage,
    required this.displayTargetPercentage,
    required this.displayTargetBlocks,
    required this.hasNewTx,
    this.isBackground = false,
    this.phase = '',
  });

  bool get isProgress => kind == syncEventKindProgress;
  bool get isCompleted => kind == syncEventKindCompleted;
  bool get isStopped => kind == syncEventKindStopped;
}

/// Abstract delegate for platform-specific background sync behavior.
abstract class BackgroundSyncDelegate {
  bool get isActive;

  /// Whether auto-sync polling should be suppressed while background mode is active.
  /// iOS: true (BGTask manages sync, polling would interfere).
  /// Android: false (background mode is just a notification, polling still needed).
  bool get shouldSuppressPolling;

  void setupListeners({
    required void Function() onStopRequested,
    required void Function(NativeSyncEventV2) onBackgroundEvent,
  });

  void disposeListeners();

  Future<void> enable({required RpcEndpointConfig endpoint});

  /// Returns true if foreground sync needs to be restarted after disabling.
  Future<bool> disable();

  /// Tear background-sync bookkeeping down for a lock/sign-out transition.
  /// Unlike [disable], this must not request a foreground handoff.
  Future<void> shutdownForLock();
  Future<bool> isAvailable();

  void onSyncDone();
  void onResume();
  void onEvent(NativeSyncEventV2 event);

  static BackgroundSyncDelegate create() {
    if (Platform.isAndroid) return AndroidBackgroundSyncDelegate();
    if (Platform.isIOS) return IOSBackgroundSyncDelegate();
    return NoOpBackgroundSyncDelegate();
  }
}

// ======================== Android ========================

class AndroidBackgroundSyncDelegate implements BackgroundSyncDelegate {
  bool _active = false;
  DataCallback? _taskDataCallback;

  @override
  bool get isActive => _active;

  @override
  bool get shouldSuppressPolling => false; // notification only, polling still needed

  @override
  void setupListeners({
    required void Function() onStopRequested,
    required void Function(NativeSyncEventV2) onBackgroundEvent,
  }) {
    disposeListeners();
    _taskDataCallback = (data) {
      if (data == 'stop_sync') {
        log(
          'BackgroundSyncDelegate(Android): stop requested from notification',
        );
        onStopRequested();
      }
    };
    FlutterForegroundTask.addTaskDataCallback(_taskDataCallback!);
  }

  @override
  void disposeListeners() {
    final callback = _taskDataCallback;
    if (callback == null) return;
    FlutterForegroundTask.removeTaskDataCallback(callback);
    _taskDataCallback = null;
  }

  @override
  Future<void> enable({required RpcEndpointConfig endpoint}) async {
    _active = true;
    await bg_sync.startBackgroundSync();
    log('BackgroundSyncDelegate(Android): enabled');
  }

  @override
  Future<bool> disable() async {
    _active = false;
    await bg_sync.stopBackgroundSync();
    log('BackgroundSyncDelegate(Android): disabled');
    return false; // sync never stopped, no restart needed
  }

  @override
  Future<void> shutdownForLock() async {
    _active = false;
    await bg_sync.stopBackgroundSync();
    log('BackgroundSyncDelegate(Android): shut down for lock');
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  void onSyncDone() {
    // Android background mode = notification only. Keep it active across
    // sync cycles until the user explicitly disables it.
  }

  @override
  void onResume() {}

  @override
  void onEvent(NativeSyncEventV2 event) {
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
  bool get shouldSuppressPolling => _active; // BGTask manages sync

  @override
  void setupListeners({
    required void Function() onStopRequested,
    required void Function(NativeSyncEventV2) onBackgroundEvent,
  }) {
    _eventChannelSub = _progressChannel.receiveBroadcastStream().listen(
      (event) {
        try {
          final map = event as Map;
          onBackgroundEvent(
            NativeSyncEventV2(
              kind: (map['kind'] as num?)?.toInt() ?? syncEventKindProgress,
              runId: _bigIntFromEventValue(map['runId']),
              sequence: _bigIntFromEventValue(map['sequence']),
              scannedHeight: (map['scannedHeight'] as num?)?.toInt() ?? 0,
              chainTipHeight: (map['chainTipHeight'] as num?)?.toInt() ?? 0,
              percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
              displayTargetPercentage:
                  (map['displayTargetPercentage'] as num?)?.toDouble() ??
                  (map['percentage'] as num?)?.toDouble() ??
                  0.0,
              displayTargetBlocks:
                  (map['displayTargetBlocks'] as num?)?.toInt() ?? 0,
              hasNewTx: map['hasNewTx'] as bool? ?? false,
              isBackground: true,
              phase: map['phase'] as String? ?? '',
            ),
          );
        } catch (e) {
          log(
            'BackgroundSyncDelegate(iOS): failed to parse progress event: $e',
          );
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
  Future<void> enable({required RpcEndpointConfig endpoint}) async {
    _active = true;
    rust_sync.setSyncMode(mode: 2);
    await bg_sync.startBackgroundSync(endpoint: endpoint);
    log('BackgroundSyncDelegate(iOS): enabled');
  }

  @override
  Future<bool> disable() async {
    rust_sync.setSyncMode(mode: 1);
    await bg_sync.stopBackgroundSync();
    var waited = 0;
    while (rust_sync.isSyncRunning() && waited < 120000) {
      await Future.delayed(const Duration(milliseconds: 200));
      waited += 200;
    }
    if (rust_sync.isSyncRunning()) {
      log(
        'BackgroundSyncDelegate(iOS): WARNING: timed out waiting for bg sync to stop',
      );
    }
    _active = false;
    log('BackgroundSyncDelegate(iOS): disabled');
    return true; // bg sync stopped, foreground restart needed
  }

  @override
  Future<void> shutdownForLock() async {
    _active = false;
    await bg_sync.stopBackgroundSync();
    log('BackgroundSyncDelegate(iOS): shut down for lock');
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
  void onEvent(NativeSyncEventV2 event) {
    if (event.isBackground && event.isCompleted && _active) {
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
  bool get shouldSuppressPolling => false;

  @override
  void setupListeners({
    required void Function() onStopRequested,
    required void Function(NativeSyncEventV2) onBackgroundEvent,
  }) {}

  @override
  void disposeListeners() {}

  @override
  Future<void> enable({required RpcEndpointConfig endpoint}) async {}

  @override
  Future<bool> disable() async => false;

  @override
  Future<void> shutdownForLock() async {}

  @override
  Future<bool> isAvailable() async => false;

  @override
  void onSyncDone() {}

  @override
  void onResume() {}

  @override
  void onEvent(NativeSyncEventV2 event) {}
}

BigInt _bigIntFromEventValue(Object? value) {
  if (value is BigInt) return value;
  if (value is int) return BigInt.from(value);
  if (value is num) return BigInt.from(value.toInt());
  if (value is String) return BigInt.tryParse(value) ?? BigInt.zero;
  return BigInt.zero;
}
