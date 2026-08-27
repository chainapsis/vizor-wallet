import 'dart:io' show Platform;

import 'package:flutter/services.dart';

const _deviceBackupChannel = MethodChannel('com.zcash.wallet/network_privacy');

/// Keeps Arti guard state out of device backups where the platform supports
/// an explicit per-path exclusion.
Future<void> excludeTorDirectoryFromDeviceBackup(String directory) async {
  // Android has no runtime equivalent. `android:allowBackup="false"` in the
  // manifest covers cloud backup on older targets; device-transfer exclusions
  // are handled by native data-extraction rules rather than this channel.
  if (!Platform.isIOS) return;
  try {
    await _deviceBackupChannel.invokeMethod<void>('excludeFromBackup', {
      'path': directory,
    });
  } on MissingPluginException {
    // Test hosts and older builds have no native side to ask.
  }
}
