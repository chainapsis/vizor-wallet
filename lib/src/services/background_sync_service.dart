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
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Task started — sync is already running in the main isolate
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Not used — we update notification manually via updateService()
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isAppTerminated) async {
    // Service being destroyed
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      // Send stop signal to main isolate
      FlutterForegroundTask.sendDataToMain('stop_sync');
      FlutterForegroundTask.stopService();
    }
  }
}

/// Checks if background sync is available on this platform/version.
Future<bool> isBackgroundSyncAvailable() async {
  if (Platform.isAndroid) {
    return true;
  }
  if (Platform.isIOS) {
    try {
      final available = await _iosChannel.invokeMethod<bool>('isAvailable');
      return available ?? false;
    } catch (_) {
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
      final success = await _iosChannel.invokeMethod<bool>('startBackgroundSync');
      log('BackgroundSync: iOS BGTask submitted: $success');
    } catch (e) {
      log('BackgroundSync: iOS BGTask failed: $e');
    }
  }
}

/// Update background sync notification with progress.
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
  }
}

/// Check if background sync is currently running.
Future<bool> isBackgroundSyncRunning() async {
  if (Platform.isAndroid) {
    return await FlutterForegroundTask.isRunningService;
  }
  return false;
}

// ======================== Android ========================

Future<void> _startAndroidForegroundService() async {
  // Request notification permission on Android 13+
  final notifPermission = await FlutterForegroundTask.checkNotificationPermission();
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
  final errorMsg = result is ServiceRequestFailure ? (result as ServiceRequestFailure).error : '';
  log('BackgroundSync: startService result: success=$success, error=$errorMsg');

  final isRunning = await FlutterForegroundTask.isRunningService;
  log('BackgroundSync: isRunningService=$isRunning');
}
