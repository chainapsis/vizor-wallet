import 'dart:io';

import 'package:flutter/services.dart';

import '../../main.dart' show log;
import '../core/config/rpc_endpoint_config.dart';

const _iosChannel = MethodChannel('com.zcash.wallet/background_sync');

/// Checks if background sync is available on this platform/version.
Future<bool> isBackgroundSyncAvailable() async {
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

/// Start background sync with the native iOS BGTask scheduler.
Future<void> startBackgroundSync({RpcEndpointConfig? endpoint}) async {
  if (Platform.isIOS) {
    try {
      final success = await _iosChannel.invokeMethod<bool>(
        'startBackgroundSync',
        endpoint == null
            ? null
            : {
                'lightwalletdUrl': endpoint.normalizedLightwalletdUrl,
                'network': endpoint.networkName,
                'presetId': endpoint.effectivePresetId,
              },
      );
      log('BackgroundSync: iOS BGTask submitted: $success');
    } catch (e) {
      log('BackgroundSync: iOS BGTask failed: $e');
    }
  }
}

/// Mirror the Dart endpoint setting into native storage used by iOS BGTasks.
Future<void> updateBackgroundSyncEndpoint({
  required RpcEndpointConfig endpoint,
}) async {
  if (!Platform.isIOS) return;
  final success = await _iosChannel.invokeMethod<bool>('updateEndpoint', {
    'lightwalletdUrl': endpoint.normalizedLightwalletdUrl,
    'network': endpoint.networkName,
    'presetId': endpoint.effectivePresetId,
  });
  if (success != true) {
    throw StateError('iOS endpoint mirror update failed.');
  }
}

/// Stop background sync service.
Future<void> stopBackgroundSync() async {
  if (Platform.isIOS) {
    try {
      final success = await _iosChannel.invokeMethod<bool>(
        'stopBackgroundSync',
      );
      log('BackgroundSync: iOS BGTask cancel requested: $success');
    } catch (e) {
      log('BackgroundSync: iOS BGTask cancel failed: $e');
    }
  }
}
