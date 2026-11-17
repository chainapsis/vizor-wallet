import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_provider.dart';

/// Most blocks a synced wallet's catch-up may scan before its progress
/// shows. Blocks are 75 seconds apart, so this is about 21 hours away from
/// the wallet; it is also one mobile scan batch.
const kSyncShortCatchUpMaxBlocks = 1000;

/// How long a synced wallet's catch-up may run before its progress shows.
const kSyncShortCatchUpMaxDuration = Duration(seconds: 10);

/// Whether [sync] is a synced wallet catching up to new blocks, and the
/// catch-up is still short at [now]: at most [kSyncShortCatchUpMaxBlocks]
/// blocks to scan and less than [kSyncShortCatchUpMaxDuration] running.
///
/// Only a sync that started from a completed one qualifies
/// ([SyncState.startedFromCompletedSync], which a catch-up's restart after a
/// failure, a stop or a lock keeps), so a wallet that never completed, a
/// restore (whose tip is scanned first) and a sync after an account was
/// added are never short. Checking, a failure and a background run are not
/// either.
bool isShortSyncCatchUp(SyncState sync, {required DateTime now}) {
  final startedAt = sync.lastSyncStartedAt;
  if (!sync.startedFromCompletedSync ||
      !sync.isSyncing ||
      sync.isBackgroundMode ||
      sync.isChecking ||
      sync.failure != null ||
      startedAt == null) {
    return false;
  }
  // The scan queue is unknown until the attempt enumerates it. Until then
  // the gap to the tip stands in: the attempt started at the height the
  // completed sync scanned to.
  final blocks =
      sync.remainingScanBlocks ?? sync.chainTipHeight - sync.scannedHeight;
  if (blocks > kSyncShortCatchUpMaxBlocks) return false;
  return now.difference(startedAt) < kSyncShortCatchUpMaxDuration;
}

/// Whether the sync status shows a synced wallet's catch-up without a
/// percentage ([isShortSyncCatchUp]). It turns false when the time limit
/// passes, and once a catch-up has shown its percentage it keeps showing it
/// for the rest of that attempt and for later attempts of the same sync job:
/// a restart after a failure, an endpoint fallback or a lock resumes the job
/// with fewer blocks left, which is not a new catch-up.
final syncShortCatchUpProvider =
    NotifierProvider<SyncShortCatchUpNotifier, bool>(
      SyncShortCatchUpNotifier.new,
    );

class SyncShortCatchUpNotifier extends Notifier<bool> {
  Timer? _timeLimit;

  /// The attempt, and the sync job once an event names it, of the catch-up
  /// that showed its percentage.
  DateTime? _progressShownFor;
  String _progressShownForJob = '';

  @override
  bool build() {
    final sync = ref.watch(syncProvider).asData?.value;
    ref.onDispose(_cancelTimeLimit);
    final startedAt = sync?.lastSyncStartedAt;
    if (sync == null || startedAt == null) return false;
    final jobId = sync.syncJobId;
    if (startedAt == _progressShownFor ||
        (jobId.isNotEmpty && jobId == _progressShownForJob)) {
      if (jobId.isNotEmpty) _progressShownForJob = jobId;
      return false;
    }
    final now = DateTime.now();
    if (!isShortSyncCatchUp(sync, now: now)) {
      if (sync.startedFromCompletedSync && sync.isSyncing) {
        _progressShownFor = startedAt;
        _progressShownForJob = jobId;
      }
      return false;
    }
    _timeLimit = Timer(
      startedAt.add(kSyncShortCatchUpMaxDuration).difference(now),
      ref.invalidateSelf,
    );
    return true;
  }

  void _cancelTimeLimit() {
    _timeLimit?.cancel();
    _timeLimit = null;
  }
}
