import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show immutable, kIsWeb;
import 'package:flutter/services.dart';

const _channel = EventChannel('com.zcash.wallet/device_power');

/// The device's thermal state and power saving, as the OS reports them.
@immutable
class DevicePower {
  const DevicePower({required this.thermal, required this.lowPower});

  /// 0 nominal, 1 fair, 2 serious, 3 critical: iOS `ProcessInfo.ThermalState`
  /// values, with Android's thermal status and headroom mapped onto them.
  final int thermal;

  /// Low Power Mode on iOS, Battery Saver on Android.
  final bool lowPower;

  static DevicePower? fromEvent(Object? event) {
    if (event is! Map) return null;
    final thermal = event['thermal'];
    final lowPower = event['lowPower'];
    if (thermal is! int || lowPower is! bool) return null;
    return DevicePower(thermal: thermal, lowPower: lowPower);
  }

  @override
  bool operator ==(Object other) =>
      other is DevicePower &&
      other.thermal == thermal &&
      other.lowPower == lowPower;

  @override
  int get hashCode => Object.hash(thermal, lowPower);
}

/// The device's power state now and on every change, on iOS and Android.
/// Other platforms (desktop, tests) emit nothing, and errors from a missing
/// host handler are swallowed.
Stream<DevicePower> devicePowerEvents() {
  if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
    return const Stream.empty();
  }
  return _channel
      .receiveBroadcastStream()
      .map(DevicePower.fromEvent)
      .where((power) => power != null)
      .cast<DevicePower>()
      .handleError((Object _) {});
}

/// How much of the CPU sync scans may use (`set_sync_scan_power`): 0 every
/// core, 1 half the cores at a lower priority. Full speed up to serious, the
/// efficiency cores at critical or in power saving. Three phones reached
/// serious 1.5 to 7.5 minutes into a restore, where the OS already throttles,
/// so lowering there ran almost the whole restore at level 1 (about 1.8 times
/// as long) and, on Android, kept about as many cores busy.
int syncScanPowerFor(DevicePower power) {
  if (power.thermal >= 3 || power.lowPower) return 1;
  return 0;
}
