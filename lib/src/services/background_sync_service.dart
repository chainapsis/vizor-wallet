import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../main.dart' show log;

const _iosChannel = MethodChannel('com.zcash.wallet/background_sync');

// Top-level callback required by flutter_foreground_task
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_SyncTaskHandler());
}

class _SyncTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isAppTerminated) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      FlutterForegroundTask.sendDataToMain('stop_sync');
      FlutterForegroundTask.stopService();
    }
  }
}

/// Checks if background sync is available on this platform/version.
Future<bool> isBackgroundSyncAvailable() async {
  if (Platform.isAndroid) return true;
  if (Platform.isIOS) {
    try {
      final available = await _iosChannel.invokeMethod<bool>('isAvailable');
      return available ?? false;
    } catch (e) {
      log('BackgroundSync: isAvailable check failed: $e');
      return false;
    }
  }
  return false;
}

/// Start background sync with platform notification.
Future<void> startBackgroundSync() async {
  if (Platform.isAndroid) {
    await _startAndroidForegroundService();
  } else if (Platform.isIOS) {
    try {
      final success =
          await _iosChannel.invokeMethod<bool>('startBackgroundSync');
      log('BackgroundSync: iOS BGTask submitted: $success');
    } catch (e) {
      log('BackgroundSync: iOS BGTask failed: $e');
    }
  }
}

/// Update background sync notification with progress (Android only).
Future<void> updateBackgroundSyncProgress({
  required double percentage,
  required int scannedHeight,
  required int chainTipHeight,
}) async {
  if (Platform.isAndroid) {
    final pct = (percentage * 100).toStringAsFixed(1);
    FlutterForegroundTask.updateService(
      notificationTitle: 'Zcash Wallet — Syncing $pct%',
      notificationText: 'Block $scannedHeight / $chainTipHeight',
    );
  }
}

/// Stop background sync service.
Future<void> stopBackgroundSync() async {
  if (Platform.isAndroid) {
    await FlutterForegroundTask.stopService();
  } else if (Platform.isIOS) {
    try {
      final success =
          await _iosChannel.invokeMethod<bool>('stopBackgroundSync');
      log('BackgroundSync: iOS BGTask cancel requested: $success');
    } catch (e) {
      log('BackgroundSync: iOS BGTask cancel failed: $e');
    }
  }
}

// ======================== Android ========================

Future<void> _startAndroidForegroundService() async {
  final notifPermission =
      await FlutterForegroundTask.checkNotificationPermission();
  log('BackgroundSync: notification permission=$notifPermission');
  if (notifPermission != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'zcash_sync',
      channelName: 'Zcash Sync',
      channelDescription: 'Blockchain synchronization progress',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      playSound: false,
      showBadge: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  final result = await FlutterForegroundTask.startService(
    notificationTitle: 'Zcash Wallet',
    notificationText: 'Syncing blockchain...',
    serviceId: 1001,
    callback: _foregroundTaskCallback,
    notificationButtons: [
      const NotificationButton(id: 'stop', text: 'Stop Sync'),
    ],
  );

  final success = result is ServiceRequestSuccess;
  log('BackgroundSync: startService result: success=$success');
}
