import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/device_power.dart';

/// How long a sync job scans at full speed whatever the device's power state.
/// Heat builds up over minutes of scanning, and a catch-up that finishes
/// sooner would only show the balance later on fewer cores.
const kSyncScanSlowdownAfter = Duration(minutes: 3);

/// Why sync scans run on fewer cores right now, if they do: the device's
/// reason, once the sync job has run [kSyncScanSlowdownAfter]. The sync
/// notifier feeds it the device's power events and the running job, sets the
/// scan power from it, and the keep-awake screen says why sync is slower.
class SyncScanSlowdownNotifier extends Notifier<SyncScanSlowdown?> {
  SyncScanSlowdown? _reason;
  String _jobId = '';
  bool _jobRanLong = false;
  Timer? _jobTimer;

  @override
  SyncScanSlowdown? build() {
    ref.onDispose(() => _jobTimer?.cancel());
    return null;
  }

  /// The device's power state changed.
  void updateDevicePower(SyncScanSlowdown? reason) {
    _reason = reason;
    _apply();
  }

  /// The sync job of the latest sync state. The clock starts when a new job
  /// appears and stops when a sync completes; retries and endpoint fallbacks
  /// keep the job, so they do not restart it.
  void updateSyncJob(String jobId, {required bool complete}) {
    if (complete) {
      if (_jobId.isEmpty) return;
      _startJob('');
    } else if (jobId.isNotEmpty && jobId != _jobId) {
      _startJob(jobId);
      _jobTimer = Timer(kSyncScanSlowdownAfter, () {
        _jobRanLong = true;
        _apply();
      });
    }
    _apply();
  }

  void _startJob(String jobId) {
    _jobTimer?.cancel();
    _jobTimer = null;
    _jobId = jobId;
    _jobRanLong = false;
  }

  void _apply() => state = _jobRanLong ? _reason : null;
}

final syncScanSlowdownProvider =
    NotifierProvider<SyncScanSlowdownNotifier, SyncScanSlowdown?>(
      SyncScanSlowdownNotifier.new,
    );
