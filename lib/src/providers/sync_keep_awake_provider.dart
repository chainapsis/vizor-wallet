import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';
import 'app_security_provider.dart';
import 'sync_provider.dart';

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
      if (sync?.isSyncing == true && sync?.isBackgroundMode != true) {
        return SyncKeepAwakePrivacyLockMode.syncing;
      }
      if (sync != null && isSyncKeepAwakeCompletedSync(sync)) {
        return SyncKeepAwakePrivacyLockMode.done;
      }
      return SyncKeepAwakePrivacyLockMode.interrupted;
    });

final syncKeepAwakePrivacyLockVisibleProvider = Provider<bool>((ref) {
  return ref.watch(syncKeepAwakePrivacyLockModeProvider) !=
      SyncKeepAwakePrivacyLockMode.hidden;
});

class SyncKeepAwakeEtaSample {
  const SyncKeepAwakeEtaSample({
    required this.syncStartedAt,
    required this.measuredAt,
    required this.estimatedRemainingBlocks,
  });

  final DateTime syncStartedAt;
  final DateTime measuredAt;
  final double estimatedRemainingBlocks;
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
  if (sync.chainTipHeight <= 0 || sync.scannedHeight <= 0) return false;
  return sync.chainTipHeight - sync.scannedHeight <=
      kSyncKeepAwakeNearTipBlockGap;
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

  final hasKnownHeights = sync.chainTipHeight > 0 && sync.scannedHeight > 0;
  if (hasKnownHeights) {
    return !isNearTipCatchUp(sync);
  }

  return sync.displayTargetBlocks > kSyncKeepAwakeNearTipBlockGap;
}

bool isSyncKeepAwakeCompletedSync(SyncState sync) {
  if (sync.isSyncing || sync.isBackgroundMode) return false;
  if (sync.percentage >= 1 || sync.displayPercentage >= 1) return true;
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

  final estimatedRemainingBlocks = _estimatedRemainingBlocks(sync);
  final sample = estimatedRemainingBlocks == null
      ? null
      : SyncKeepAwakeEtaSample(
          syncStartedAt: startedAt,
          measuredAt: now,
          estimatedRemainingBlocks: estimatedRemainingBlocks,
        );

  final observedEta = sample == null
      ? null
      : _estimateFromObservedBlockRate(
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

double? _estimatedRemainingBlocks(SyncState sync) {
  final targetDelta = sync.displayTargetPercentage - sync.percentage;
  if (sync.displayTargetBlocks > 0 && targetDelta > 0) {
    final totalBlocks = sync.displayTargetBlocks / targetDelta;
    if (totalBlocks.isFinite && totalBlocks > 0) {
      return math.max(0.0, totalBlocks * (1 - sync.percentage));
    }
  }
  return null;
}

Duration? _estimateFromObservedBlockRate({
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

  final processedBlocks =
      previousSample.estimatedRemainingBlocks - sample.estimatedRemainingBlocks;
  if (processedBlocks <= 0 || !processedBlocks.isFinite) return null;

  final blocksPerMicrosecond = processedBlocks / elapsedMicros;
  if (blocksPerMicrosecond <= 0 || !blocksPerMicrosecond.isFinite) return null;

  final remainingMicros =
      sample.estimatedRemainingBlocks / blocksPerMicrosecond;
  if (!remainingMicros.isFinite || remainingMicros < 0) return null;
  return Duration(microseconds: remainingMicros.round());
}

Duration? _estimateFromRunPercentage(SyncState sync, Duration elapsed) {
  final percentage = sync.percentage;
  if (percentage <= 0 || percentage >= 1 || elapsed <= Duration.zero) {
    return null;
  }
  final remainingMicros =
      elapsed.inMicroseconds * (1 - percentage) / percentage;
  if (!remainingMicros.isFinite || remainingMicros < 0) return null;
  return Duration(microseconds: remainingMicros.round());
}
