import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';
import 'app_security_provider.dart';
import 'sync_provider.dart';
import 'sync_short_catch_up_provider.dart';

const kSyncKeepAwakePromptEtaThreshold = Duration(minutes: 1);
const kSyncKeepAwakePrivacyIdleTimeout = Duration(minutes: 1);
const kSyncKeepAwakeNearTipBlockGap = 2;

class SyncKeepAwakeSettings {
  const SyncKeepAwakeSettings({
    required this.enabled,
    required this.promptSeen,
  });

  final bool enabled;
  final bool promptSeen;

  SyncKeepAwakeSettings copyWith({bool? enabled, bool? promptSeen}) {
    return SyncKeepAwakeSettings(
      enabled: enabled ?? this.enabled,
      promptSeen: promptSeen ?? this.promptSeen,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SyncKeepAwakeSettings &&
            other.enabled == enabled &&
            other.promptSeen == promptSeen;
  }

  @override
  int get hashCode => Object.hash(enabled, promptSeen);
}

class SyncKeepAwakeNotifier extends Notifier<SyncKeepAwakeSettings> {
  static final _store = AppSecureStore.instance;

  @override
  SyncKeepAwakeSettings build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return SyncKeepAwakeSettings(
      enabled: bootstrap.syncKeepAwakeEnabled,
      promptSeen: bootstrap.syncKeepAwakePromptSeen,
    );
  }

  Future<void> setEnabled(bool enabled, {bool markPromptSeen = true}) async {
    await _store.writePlain(
      kSyncKeepAwakeEnabledKey,
      enabled ? 'true' : 'false',
    );
    if (markPromptSeen) {
      await _store.writePlain(kSyncKeepAwakePromptSeenKey, 'true');
    }
    state = state.copyWith(
      enabled: enabled,
      promptSeen: markPromptSeen ? true : null,
    );
  }

  Future<void> markPromptSeen() async {
    await _store.writePlain(kSyncKeepAwakePromptSeenKey, 'true');
    state = state.copyWith(promptSeen: true);
  }
}

final syncKeepAwakeProvider =
    NotifierProvider<SyncKeepAwakeNotifier, SyncKeepAwakeSettings>(
      SyncKeepAwakeNotifier.new,
    );

class SyncKeepAwakeInteractionState {
  const SyncKeepAwakeInteractionState({
    required this.lastInteractionAt,
    this.revision = 0,
  });

  final DateTime lastInteractionAt;
  final int revision;

  Duration idleDuration(DateTime now) => now.difference(lastInteractionAt);
}

class SyncKeepAwakeInteractionNotifier
    extends Notifier<SyncKeepAwakeInteractionState> {
  @override
  SyncKeepAwakeInteractionState build() {
    return SyncKeepAwakeInteractionState(lastInteractionAt: DateTime.now());
  }

  void markInteraction({DateTime? at}) {
    state = SyncKeepAwakeInteractionState(
      lastInteractionAt: at ?? DateTime.now(),
      revision: state.revision + 1,
    );
  }
}

final syncKeepAwakeInteractionProvider =
    NotifierProvider<
      SyncKeepAwakeInteractionNotifier,
      SyncKeepAwakeInteractionState
    >(SyncKeepAwakeInteractionNotifier.new);

class SyncKeepAwakePrivacyLockState {
  const SyncKeepAwakePrivacyLockState({required this.isLocked, this.lockedAt});

  const SyncKeepAwakePrivacyLockState.unlocked()
    : isLocked = false,
      lockedAt = null;

  final bool isLocked;
  final DateTime? lockedAt;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SyncKeepAwakePrivacyLockState &&
            other.isLocked == isLocked &&
            other.lockedAt == lockedAt;
  }

  @override
  int get hashCode => Object.hash(isLocked, lockedAt);
}

class SyncKeepAwakePrivacyLockNotifier
    extends Notifier<SyncKeepAwakePrivacyLockState> {
  @override
  SyncKeepAwakePrivacyLockState build() {
    return const SyncKeepAwakePrivacyLockState.unlocked();
  }

  void lock({DateTime? at}) {
    if (state.isLocked) return;
    state = SyncKeepAwakePrivacyLockState(
      isLocked: true,
      lockedAt: at ?? DateTime.now(),
    );
  }

  void unlock({DateTime? at}) {
    ref.read(syncKeepAwakeInteractionProvider.notifier).markInteraction(at: at);
    clear();
  }

  void clear() {
    if (!state.isLocked) return;
    state = const SyncKeepAwakePrivacyLockState.unlocked();
  }
}

final syncKeepAwakePrivacyLockProvider =
    NotifierProvider<
      SyncKeepAwakePrivacyLockNotifier,
      SyncKeepAwakePrivacyLockState
    >(SyncKeepAwakePrivacyLockNotifier.new);

enum SyncKeepAwakePrivacyLockMode { hidden, syncing, done, interrupted }

final syncKeepAwakeActiveProvider = Provider<bool>((ref) {
  if (ref.watch(appSecurityProvider).requiresUnlock) return false;
  final settings = ref.watch(syncKeepAwakeProvider);
  final sync = ref.watch(syncProvider).asData?.value;
  if (sync == null) return false;
  // A synced wallet's short catch-up runs on each new block; it keeps
  // neither the screen nor the privacy lock up. Past its limits, or for a
  // restore or a wallet that never completed, the usual rule applies.
  if (ref.watch(syncShortCatchUpProvider)) return false;
  return shouldKeepScreenAwakeForSync(settings: settings, sync: sync);
});

final syncKeepAwakePrivacyLockModeProvider =
    Provider<SyncKeepAwakePrivacyLockMode>((ref) {
      if (ref.watch(appSecurityProvider).requiresUnlock) {
        return SyncKeepAwakePrivacyLockMode.hidden;
      }
      if (!ref.watch(syncKeepAwakePrivacyLockProvider).isLocked) {
        return SyncKeepAwakePrivacyLockMode.hidden;
      }
      final sync = ref.watch(syncProvider).asData?.value;
      if (sync != null && isSyncKeepAwakeCompletedSync(sync)) {
        return SyncKeepAwakePrivacyLockMode.done;
      }
      if (ref.watch(syncKeepAwakeCompleteThroughCatchUpProvider)) {
        return SyncKeepAwakePrivacyLockMode.done;
      }
      if (sync?.isSyncing == true && sync?.isBackgroundMode != true) {
        return SyncKeepAwakePrivacyLockMode.syncing;
      }
      return SyncKeepAwakePrivacyLockMode.interrupted;
    });

/// Whether the locked screen keeps "Sync Complete" through a synced wallet's
/// catch-up. A short catch-up (`syncShortCatchUpProvider`) does not bring
/// the progress ring back over "Sync Complete"; the sync status reads
/// "Syncing…" in its synced look meanwhile. Once a catch-up has run under
/// "Sync Complete", the screen keeps it until that attempt ends, even when
/// the catch-up outgrows the short limits, rather than flash to the ring
/// and back. While it holds, the screen says new blocks are syncing.
final syncKeepAwakeCompleteThroughCatchUpProvider =
    NotifierProvider<_SyncKeepAwakeCompleteThroughCatchUpNotifier, bool>(
      _SyncKeepAwakeCompleteThroughCatchUpNotifier.new,
    );

class _SyncKeepAwakeCompleteThroughCatchUpNotifier extends Notifier<bool> {
  /// The start of the catch-up attempt that ran under "Sync Complete".
  DateTime? _attempt;

  @override
  bool build() {
    final locked =
        !ref.watch(appSecurityProvider).requiresUnlock &&
        ref.watch(syncKeepAwakePrivacyLockProvider).isLocked;
    final sync = ref.watch(syncProvider).asData?.value;
    final startedAt = sync?.lastSyncStartedAt;
    final shortCatchUp = ref.watch(syncShortCatchUpProvider);
    if (!locked || sync == null || startedAt == null) {
      _attempt = null;
      return false;
    }
    if (shortCatchUp) {
      _attempt = startedAt;
      return true;
    }
    final sameAttemptRunning =
        startedAt == _attempt &&
        sync.isSyncing &&
        !sync.isBackgroundMode &&
        sync.failure == null;
    if (!sameAttemptRunning) _attempt = null;
    return sameAttemptRunning;
  }
}

final syncKeepAwakePrivacyLockVisibleProvider = Provider<bool>((ref) {
  return ref.watch(syncKeepAwakePrivacyLockModeProvider) !=
      SyncKeepAwakePrivacyLockMode.hidden;
});

/// Gives the above-router lock first refusal of system Back, even before its
/// screen has mounted. A route-level PopScope cannot protect this app layer.
class SyncKeepAwakePrivacyLockBackController {
  SyncKeepAwakePrivacyLockBackController(this._isVisible);

  final bool Function() _isVisible;
  Object? _owner;
  VoidCallback? _onBack;

  VoidCallback attach(VoidCallback onBack) {
    final owner = Object();
    _owner = owner;
    _onBack = onBack;
    return () {
      if (!identical(_owner, owner)) return;
      _owner = null;
      _onBack = null;
    };
  }

  bool handleBack() {
    if (!_isVisible()) return false;
    _onBack?.call();
    return true;
  }
}

final syncKeepAwakePrivacyLockBackProvider =
    Provider<SyncKeepAwakePrivacyLockBackController>((ref) {
      return SyncKeepAwakePrivacyLockBackController(
        () => ref.read(syncKeepAwakePrivacyLockVisibleProvider),
      );
    });

class SyncKeepAwakeEtaSample {
  const SyncKeepAwakeEtaSample({
    required this.syncStartedAt,
    required this.measuredAt,
    required this.remainingFraction,
  });

  final DateTime syncStartedAt;
  final DateTime measuredAt;

  /// Share of the sync job's work left, `1 - percentage`.
  final double remainingFraction;
}

class SyncKeepAwakeEtaEstimate {
  const SyncKeepAwakeEtaEstimate({
    required this.remaining,
    required this.sample,
  });

  const SyncKeepAwakeEtaEstimate.none() : remaining = null, sample = null;

  final Duration? remaining;
  final SyncKeepAwakeEtaSample? sample;
}

bool isNearTipCatchUp(SyncState sync) {
  final remaining = sync.remainingScanBlocks;
  if (remaining == null || remaining > kSyncKeepAwakeNearTipBlockGap) {
    return false;
  }
  if (remaining == 0) return true;
  final start = sync.pendingScanStartHeight;
  if (start == null || start <= 0 || sync.chainTipHeight < start) return false;
  // Scan ranges start inclusively. A range starting at tip is one block,
  // whereas scannedHeight is the current batch's exclusive end.
  return sync.chainTipHeight - start + 1 <= kSyncKeepAwakeNearTipBlockGap;
}

bool isSyncKeepAwakeEligibleSync(SyncState sync) {
  return sync.isSyncing &&
      !sync.isBackgroundMode &&
      sync.percentage > 0 &&
      sync.percentage < 1 &&
      sync.lastSyncStartedAt != null &&
      sync.chainTipHeight > 0 &&
      sync.scannedHeight > 0 &&
      !isNearTipCatchUp(sync);
}

bool isSyncKeepAwakeActiveSync(SyncState sync) {
  if (!sync.isSyncing ||
      sync.isBackgroundMode ||
      sync.percentage >= 1 ||
      sync.lastSyncStartedAt == null) {
    return false;
  }

  // Until this run's scan queue is known, old heights and the next batch
  // size cannot prove this is a small catch-up. This also covers preparation
  // after retries and importing an account into a previously synced wallet.
  return !isNearTipCatchUp(sync);
}

bool isSyncKeepAwakeCompletedSync(SyncState sync) {
  if (sync.isBackgroundMode) return false;
  // A failed sync keeps its progress for the retry, 100% included when it
  // failed after the main scan; it is not complete.
  if (sync.failure != null) return false;
  // Keep-awake covers the main scan only. Final Checking work does not delay
  // its completion screen or reactivate the native screen-awake setting.
  if (sync.percentage >= 1) return true;
  if (sync.isSyncing) return false;
  if (sync.isSyncComplete) return true;
  return sync.chainTipHeight > 0 && sync.scannedHeight >= sync.chainTipHeight;
}

bool canEstimateSyncKeepAwakeEta(SyncState sync) {
  return isSyncKeepAwakeEligibleSync(sync);
}

bool shouldKeepScreenAwakeForSync({
  required SyncKeepAwakeSettings settings,
  required SyncState sync,
}) {
  return settings.enabled && isSyncKeepAwakeActiveSync(sync);
}

SyncKeepAwakeEtaEstimate estimateSyncKeepAwakeEta(
  SyncState sync, {
  required DateTime now,
  SyncKeepAwakeEtaSample? previousSample,
}) {
  final startedAt = sync.lastSyncStartedAt;
  if (!canEstimateSyncKeepAwakeEta(sync) || startedAt == null) {
    return const SyncKeepAwakeEtaEstimate.none();
  }

  final elapsed = now.difference(startedAt);
  if (elapsed <= Duration.zero) {
    return const SyncKeepAwakeEtaEstimate.none();
  }

  final sample = _isScanningBatch(sync)
      ? SyncKeepAwakeEtaSample(
          syncStartedAt: startedAt,
          measuredAt: now,
          remainingFraction: 1 - sync.percentage.clamp(0.0, 1.0),
        )
      : null;

  final observedEta = sample == null
      ? null
      : _estimateFromObservedRate(
          sample: sample,
          previousSample: previousSample,
        );
  if (observedEta != null) {
    return SyncKeepAwakeEtaEstimate(remaining: observedEta, sample: sample);
  }

  final fallbackEta = _estimateFromRunPercentage(sync, elapsed);
  return SyncKeepAwakeEtaEstimate(remaining: fallbackEta, sample: sample);
}

bool shouldShowSyncKeepAwakePrompt({
  required SyncState sync,
  required SyncKeepAwakeSettings settings,
  required DateTime now,
  SyncKeepAwakeEtaSample? previousSample,
  Duration threshold = kSyncKeepAwakePromptEtaThreshold,
}) {
  if (settings.promptSeen) return false;
  final remaining = estimateSyncKeepAwakeEta(
    sync,
    now: now,
    previousSample: previousSample,
  ).remaining;
  return remaining != null && remaining >= threshold;
}

/// Whether [sync] reports a batch in flight, so its percentage is a point on
/// the job's work scale rather than a preparation placeholder.
bool _isScanningBatch(SyncState sync) =>
    sync.displayTargetBlocks > 0 &&
    sync.displayTargetPercentage > sync.percentage;

/// ETA from the rate between two samples. The percentage is the job's share
/// of estimated scan work, which tracks scan time, so the rate needs no
/// conversion to blocks.
Duration? _estimateFromObservedRate({
  required SyncKeepAwakeEtaSample sample,
  SyncKeepAwakeEtaSample? previousSample,
}) {
  if (previousSample == null ||
      previousSample.syncStartedAt != sample.syncStartedAt) {
    return null;
  }
  final elapsedMicros = sample.measuredAt
      .difference(previousSample.measuredAt)
      .inMicroseconds;
  if (elapsedMicros <= 0) return null;

  final processed = previousSample.remainingFraction - sample.remainingFraction;
  if (processed <= 0 || !processed.isFinite) return null;

  final remainingMicros = elapsedMicros * sample.remainingFraction / processed;
  if (!remainingMicros.isFinite || remainingMicros < 0) return null;
  return Duration(microseconds: remainingMicros.round());
}

Duration? _estimateFromRunPercentage(SyncState sync, Duration elapsed) {
  final percentage = sync.percentage;
  // A resumed job starts the session above zero; only this session's
  // progress was made in `elapsed`.
  final sessionProgress = percentage - sync.sessionStartPercentage;
  if (sessionProgress <= 0 || percentage >= 1 || elapsed <= Duration.zero) {
    return null;
  }
  final remainingMicros =
      elapsed.inMicroseconds * (1 - percentage) / sessionProgress;
  if (!remainingMicros.isFinite || remainingMicros < 0) return null;
  return Duration(microseconds: remainingMicros.round());
}
