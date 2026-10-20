import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/device_power.dart';

/// Why sync scans run on fewer cores right now, if they do. The sync notifier
/// sets it from the device's power events, and the keep-awake screen says why
/// sync is slower.
class SyncScanSlowdownNotifier extends Notifier<SyncScanSlowdown?> {
  @override
  SyncScanSlowdown? build() => null;

  void update(SyncScanSlowdown? slowdown) => state = slowdown;
}

final syncScanSlowdownProvider =
    NotifierProvider<SyncScanSlowdownNotifier, SyncScanSlowdown?>(
      SyncScanSlowdownNotifier.new,
    );
