import 'package:intl/intl.dart' show DateFormat;

import '../../../core/formatting/date_format.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/zcash/block_spacing.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import 'ironwood_migration_phases.dart';

const _preparationConfirmationBlocks = 3;
const _preparationBroadcastBufferBlocks = 1;

class MigrationNextActionPresentation {
  const MigrationNextActionPresentation({
    required this.label,
    required this.amountZatoshi,
    required this.detail,
    this.scheduledHeight,
  });

  final String label;
  final BigInt amountZatoshi;
  final String detail;
  final int? scheduledHeight;
}

BigInt migrationTargetTotal(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) {
    return status.parts.fold(
      BigInt.zero,
      (total, part) => total + part.valueZatoshi,
    );
  }
  final targetTotal = status.targetValuesZatoshi.fold(
    BigInt.zero,
    (total, value) => total + value,
  );
  return targetTotal;
}

bool migrationHasTransferProgress(rust_sync.MigrationStatus status) {
  return status.pendingTxCount > 0 ||
      status.broadcastedTxCount > 0 ||
      status.confirmedTxCount > 0 ||
      status.signedChildPcztCount > 0;
}

bool migrationRequiresKeystoneSignature(rust_sync.MigrationStatus status) {
  if (status.parts.any(
    (part) => part.state == rust_sync.MigrationPartState.needsInput,
  )) {
    return true;
  }
  if (status.phase != kIronwoodMigrationReadyToMigratePhase) return false;
  final signingPartIndices = status.currentSigningPartIndices;
  return signingPartIndices == null
      ? status.signedChildPcztCount <= 0
      : signingPartIndices.isNotEmpty;
}

BigInt migrationCompletedValue(rust_sync.MigrationStatus status) {
  // Rust reuses completed part rows for denomination preparation. Until the
  // first migration transaction exists, those rows are not migrated value.
  if (status.phase == kIronwoodMigrationReadyToMigratePhase &&
      !migrationHasTransferProgress(status)) {
    return BigInt.zero;
  }
  if (status.parts.isNotEmpty) {
    return status.parts
        .where((part) => part.state == rust_sync.MigrationPartState.completed)
        .fold(BigInt.zero, (total, part) => total + part.valueZatoshi);
  }
  var completed = BigInt.zero;
  final completedCount = status.confirmedTxCount.clamp(
    0,
    status.targetValuesZatoshi.length,
  );
  for (var index = 0; index < completedCount; index++) {
    completed += status.targetValuesZatoshi[index];
  }
  return completed;
}

int compareMigrationPartsByExpectedProcessingOrder(
  rust_sync.MigrationPartStatus left,
  rust_sync.MigrationPartStatus right,
) {
  // The approved schedule order is immutable, but an overdue transaction can
  // be assigned a new height while migration is running. Every surface must
  // follow the current expected chronology.
  final leftHeight = left.scheduledHeight;
  final rightHeight = right.scheduledHeight;
  if (leftHeight != null || rightHeight != null) {
    final comparison = (leftHeight ?? 1 << 30).compareTo(
      rightHeight ?? 1 << 30,
    );
    if (comparison != 0) return comparison;
  }

  final leftOrder = left.scheduleOrder;
  final rightOrder = right.scheduleOrder;
  if (leftOrder != null || rightOrder != null) {
    final comparison = (leftOrder ?? 1 << 30).compareTo(rightOrder ?? 1 << 30);
    if (comparison != 0) return comparison;
  }
  return left.partIndex.compareTo(right.partIndex);
}

List<rust_sync.MigrationPartStatus> orderedMigrationParts(
  Iterable<rust_sync.MigrationPartStatus> parts,
) => [...parts]..sort(compareMigrationPartsByExpectedProcessingOrder);

/// Returns the exact ZIP 318 window height while [part] is waiting for it.
///
/// A preparing part can also carry a projected broadcast height, so
/// `scheduledHeight` is not evidence that it is waiting for an anchor window.
/// Rust exposes that relationship explicitly through
/// `nextProofWindowPartIndices`; use only that authoritative mapping.
int? migrationPartWaitingWindowHeight({
  required rust_sync.MigrationStatus status,
  required rust_sync.MigrationPartStatus part,
}) {
  if (part.state != rust_sync.MigrationPartState.preparing ||
      status.proofReady != false) {
    return null;
  }
  final windowHeight = status.nextProofWindowHeight;
  final waitingPartIndices = status.nextProofWindowPartIndices;
  if (windowHeight == null ||
      waitingPartIndices == null ||
      !waitingPartIndices.contains(part.partIndex)) {
    return null;
  }
  return windowHeight;
}

List<rust_sync.MigrationPreparationTransactionStatus>
orderedMigrationPreparationTransactions(rust_sync.MigrationStatus status) {
  final transactions = [...?status.preparationTransactions];
  transactions.sort((left, right) {
    final roundComparison = left.round.compareTo(right.round);
    if (roundComparison != 0) return roundComparison;
    final heightComparison = left.projectedHeight.compareTo(
      right.projectedHeight,
    );
    return heightComparison != 0
        ? heightComparison
        : left.stageIndex.compareTo(right.stageIndex);
  });
  return transactions;
}

/// Projects the block height at which each not-yet-assigned migration part is
/// expected to run.
///
/// Rust assigns `scheduled_height` incrementally: a part only carries a height
/// once its child PCZT has been signed (the status builder copies the timing
/// projection onto `Preparing` parts) or once the row has been promoted into
/// the pending-transaction table as `scheduled`. Immediately after a run
/// starts, neither has happened for any part, so every row arrives with a null
/// height and the schedule surface has nothing chronological to show.
///
/// The projection continues the approved cadence from the last height Rust did
/// assign — or from [currentHeight] when nothing is assigned yet — one
/// [rust_sync.MigrationStatus.scheduleMeanDelayBlocks] step per remaining part.
/// That matches how Rust builds the real schedule: each gap is an exponential
/// draw whose mean is `scheduleMeanDelayBlocks`, so the mean is the correct
/// expectation for an unseen gap. When
/// [rust_sync.MigrationStatus.estimatedCompletionHeight] is known the stride is
/// compressed so the final part lands no later than the last broadcast that
/// estimate implies (the estimate itself includes
/// [rust_sync.MigrationStatus.denominationConfirmationTarget] confirmation
/// blocks past that broadcast).
///
/// Returns an empty map when there is not enough information to project, so
/// callers keep their existing "pending" copy instead of inventing a height.
/// Keys are `partIndex`. Values are strictly increasing in the order produced
/// by [orderedMigrationParts], which is the order the schedule surface renders.
Map<int, int> projectedMigrationPartHeights({
  required rust_sync.MigrationStatus status,
  required int currentHeight,
}) {
  final meanDelayBlocks = status.scheduleMeanDelayBlocks;
  if (meanDelayBlocks <= 0) return const <int, int>{};

  int? lastAssignedHeight;
  final unassigned = <rust_sync.MigrationPartStatus>[];
  for (final part in orderedMigrationParts(status.parts)) {
    final assigned = part.effectiveScheduledHeight ?? part.scheduledHeight;
    if (assigned == null) {
      unassigned.add(part);
      continue;
    }
    if (lastAssignedHeight == null || assigned > lastAssignedHeight) {
      lastAssignedHeight = assigned;
    }
  }
  if (unassigned.isEmpty) return const <int, int>{};

  // Projecting forward from a height the chain already passed would describe a
  // past the user can see is wrong, so the anchor never trails the tip.
  final anchorHeight = lastAssignedHeight == null
      ? currentHeight
      : (currentHeight > lastAssignedHeight
            ? currentHeight
            : lastAssignedHeight);
  if (anchorHeight <= 0) return const <int, int>{};

  var strideBlocks = meanDelayBlocks.toDouble();
  final estimatedCompletionHeight = status.estimatedCompletionHeight;
  if (estimatedCompletionHeight != null) {
    final lastBroadcastHeight =
        estimatedCompletionHeight - status.denominationConfirmationTarget;
    if (lastBroadcastHeight > anchorHeight) {
      final cappedStride =
          (lastBroadcastHeight - anchorHeight) / unassigned.length;
      if (cappedStride > 0 && cappedStride < strideBlocks) {
        strideBlocks = cappedStride;
      }
    }
  }

  final projected = <int, int>{};
  var previousHeight = anchorHeight;
  for (var index = 0; index < unassigned.length; index++) {
    final stepped = anchorHeight + (strideBlocks * (index + 1)).round();
    // The rows are read top to bottom as a chronology; a compressed stride
    // must never make two of them tie or go backwards.
    final height = stepped > previousHeight ? stepped : previousHeight + 1;
    projected[unassigned[index].partIndex] = height;
    previousHeight = height;
  }
  return projected;
}

MigrationNextActionPresentation migrationNextActionPresentation(
  AppLocalizations l10n, {
  required rust_sync.MigrationStatus status,
  required int currentHeight,
  bool requiresInput = false,
  bool waitingForAnchor = false,
}) {
  final parts = orderedMigrationParts(status.parts);
  final total = migrationTargetTotal(status);
  final fallbackAmount = total > BigInt.zero
      ? total
      : parts.fold(BigInt.zero, (sum, part) => sum + part.valueZatoshi);

  if (requiresInput) {
    final signingIndices =
        status.currentSigningPartIndices?.toSet() ?? const <int>{};
    rust_sync.MigrationPartStatus? selected;
    for (final part in parts) {
      if (signingIndices.contains(part.partIndex)) {
        selected = part;
        break;
      }
    }
    selected ??= _firstMigrationPart(
      parts,
      (part) => part.state == rust_sync.MigrationPartState.needsInput,
    );
    final nextActionPartIndex = status.nextActionPartIndex;
    if (selected == null && nextActionPartIndex != null) {
      selected = _firstMigrationPart(
        parts,
        (part) => part.partIndex == nextActionPartIndex,
      );
    }
    selected ??= _firstMigrationPart(
      parts,
      (part) => part.state != rust_sync.MigrationPartState.completed,
    );
    final scheduledHeight =
        selected?.scheduledHeight ?? status.nextActionHeight;
    return MigrationNextActionPresentation(
      label: l10n.migrationNextActionLabelNext,
      amountZatoshi: selected?.valueZatoshi ?? fallbackAmount,
      detail: scheduledHeight == null
          ? l10n.migrationNextActionDetailReadyToSign
          : l10n.migrationNextActionDetailAt,
      scheduledHeight: scheduledHeight,
    );
  }

  final nextProofWindowHeight = status.nextProofWindowHeight;
  final proofWindowPartIndices =
      status.nextProofWindowPartIndices?.toSet() ?? const <int>{};
  final earliestScheduledHeight = parts
      .where(
        (part) =>
            part.state == rust_sync.MigrationPartState.scheduled &&
            part.scheduledHeight != null,
      )
      .map((part) => part.scheduledHeight!)
      .fold<int?>(null, (earliest, height) {
        if (earliest == null || height < earliest) return height;
        return earliest;
      });
  final proofWindowIsNext =
      nextProofWindowHeight != null &&
      proofWindowPartIndices.isNotEmpty &&
      earliestScheduledHeight == null;
  if (proofWindowIsNext) {
    final windowAmount = parts
        .where((part) => proofWindowPartIndices.contains(part.partIndex))
        .fold(BigInt.zero, (sum, part) => sum + part.valueZatoshi);
    final displayAmount = windowAmount > BigInt.zero
        ? windowAmount
        : fallbackAmount;
    if (status.proofReady == false &&
        currentHeight > 0 &&
        currentHeight >= nextProofWindowHeight) {
      return MigrationNextActionPresentation(
        label: l10n.migrationNextActionLabelOpeningWindow,
        amountZatoshi: displayAmount,
        detail: l10n.migrationNextActionDetailWaitingForSync,
      );
    }
    if (status.proofReady == true) {
      return MigrationNextActionPresentation(
        label: l10n.migrationNextActionLabelWindowReady,
        amountZatoshi: displayAmount,
        detail: l10n.migrationNextActionDetailPreparing,
      );
    }
    return MigrationNextActionPresentation(
      label: l10n.migrationNextActionLabelNextWindow,
      amountZatoshi: displayAmount,
      detail: l10n.migrationNextActionDetailExpectedAt,
      scheduledHeight: nextProofWindowHeight,
    );
  }

  if (status.phase == kIronwoodMigrationReadyToMigratePhase &&
      !migrationHasTransferProgress(status)) {
    final nextPart = parts.isEmpty ? null : parts.first;
    final nextValue =
        nextPart?.valueZatoshi ??
        (status.targetValuesZatoshi.isEmpty
            ? fallbackAmount
            : status.targetValuesZatoshi.first);
    return MigrationNextActionPresentation(
      label: l10n.migrationNextActionLabelNext,
      amountZatoshi: nextValue,
      detail: nextPart?.scheduledHeight == null
          ? l10n.migrationSchedulePending
          : l10n.migrationNextActionDetailAt,
      scheduledHeight: nextPart?.scheduledHeight,
    );
  }

  final scheduled = _firstMigrationPart(
    parts,
    (part) => part.state == rust_sync.MigrationPartState.scheduled,
  );
  final legacyBroadcast = scheduled == null
      ? _nextScheduledMigrationBroadcast(status)
      : null;
  if (scheduled != null || legacyBroadcast != null) {
    final scheduledHeight =
        scheduled?.scheduledHeight ?? legacyBroadcast?.scheduledHeight;
    final isDue =
        scheduledHeight != null &&
        currentHeight > 0 &&
        scheduledHeight <= currentHeight;
    return MigrationNextActionPresentation(
      label: isDue
          ? l10n.migrationNextActionLabelSending
          : l10n.migrationNextActionLabelNext,
      amountZatoshi:
          scheduled?.valueZatoshi ??
          legacyBroadcast?.valueZatoshi ??
          fallbackAmount,
      detail: isDue
          ? l10n.migrationNextActionDetailSendingNow
          : scheduledHeight == null
          ? l10n.migrationSchedulePending
          : l10n.migrationNextActionDetailAt,
      scheduledHeight: isDue ? null : scheduledHeight,
    );
  }

  final preparing = _firstMigrationPart(
    parts,
    (part) => part.state == rust_sync.MigrationPartState.preparing,
  );
  if (preparing != null) {
    final scheduledHeight =
        preparing.effectiveScheduledHeight ??
        preparing.scheduledHeight ??
        status.nextActionHeight;
    return MigrationNextActionPresentation(
      label: l10n.migrationNextActionLabelNext,
      amountZatoshi: preparing.valueZatoshi,
      detail: scheduledHeight == null
          ? l10n.migrationSchedulePending
          : l10n.migrationNextActionDetailAt,
      scheduledHeight: scheduledHeight,
    );
  }

  final inFlight = parts
      .where(
        (part) =>
            part.state == rust_sync.MigrationPartState.migrating ||
            part.state == rust_sync.MigrationPartState.confirming,
      )
      .toList();
  if (inFlight.isNotEmpty) {
    final amount = inFlight.fold(
      BigInt.zero,
      (sum, part) => sum + part.valueZatoshi,
    );
    final migratingCount = inFlight
        .where((part) => part.state == rust_sync.MigrationPartState.migrating)
        .length;
    final confirmingCount = inFlight.length - migratingCount;
    if (migratingCount > 0 && confirmingCount == 0) {
      return MigrationNextActionPresentation(
        label: l10n.migrationNextActionLabelAwaitingMining,
        amountZatoshi: amount,
        detail: l10n.migrationNotesBroadcast(migratingCount),
      );
    }
    if (confirmingCount > 0 && migratingCount == 0) {
      return MigrationNextActionPresentation(
        label: l10n.migrationConfirming,
        amountZatoshi: amount,
        detail: l10n.migrationNotesAwaitingConfirmation(confirmingCount),
      );
    }
    return MigrationNextActionPresentation(
      label: l10n.migrationNextActionLabelFinalizing,
      amountZatoshi: amount,
      detail: l10n.migrationNotesRemaining(inFlight.length),
    );
  }

  if (parts.isEmpty &&
      status.phase != kIronwoodMigrationCompletePhase &&
      status.totalCount > 0) {
    final broadcasts = status.scheduledBroadcasts;
    if (broadcasts.length >= status.totalCount &&
        broadcasts.every(
          (broadcast) => broadcast.status.toLowerCase() == 'confirmed',
        )) {
      return MigrationNextActionPresentation(
        label: l10n.migrationNextActionLabelFinalizing,
        amountZatoshi: fallbackAmount,
        detail: l10n.migrationNextActionDetailWaitingForConfirmations,
      );
    }
    final values = status.targetValuesZatoshi;
    final confirmedCount = status.confirmedTxCount.clamp(0, status.totalCount);
    final broadcastedCount = status.broadcastedTxCount.clamp(
      confirmedCount,
      status.totalCount,
    );
    if (broadcastedCount > confirmedCount) {
      var amount = BigInt.zero;
      for (
        var index = confirmedCount;
        index < broadcastedCount && index < values.length;
        index++
      ) {
        amount += values[index];
      }
      return MigrationNextActionPresentation(
        label: l10n.migrationConfirming,
        amountZatoshi: amount > BigInt.zero ? amount : fallbackAmount,
        detail: l10n.migrationNotesAwaitingConfirmation(
          broadcastedCount - confirmedCount,
        ),
      );
    }
    if (confirmedCount < status.totalCount) {
      final amount = confirmedCount < values.length
          ? values[confirmedCount]
          : fallbackAmount;
      final nextHeight = status.nextActionHeight;
      return MigrationNextActionPresentation(
        label: l10n.migrationNextActionLabelNext,
        amountZatoshi: amount,
        detail: nextHeight == null
            ? l10n.migrationSchedulePending
            : l10n.migrationNextActionDetailAt,
        scheduledHeight: nextHeight,
      );
    }
    return MigrationNextActionPresentation(
      label: l10n.migrationNextActionLabelFinalizing,
      amountZatoshi: fallbackAmount,
      detail: l10n.migrationNextActionDetailWaitingForConfirmations,
    );
  }

  if (waitingForAnchor) {
    return MigrationNextActionPresentation(
      label: l10n.migrationNextActionLabelNext,
      amountZatoshi: fallbackAmount,
      detail: l10n.migrationSchedulePending,
    );
  }
  return MigrationNextActionPresentation(
    label: l10n.migrationNextActionLabelComplete,
    amountZatoshi: fallbackAmount,
    detail: l10n.migrationNextActionDetailAllNotesCompleted,
  );
}

rust_sync.MigrationPartStatus? _firstMigrationPart(
  Iterable<rust_sync.MigrationPartStatus> parts,
  bool Function(rust_sync.MigrationPartStatus part) matches,
) {
  for (final part in parts) {
    if (matches(part)) return part;
  }
  return null;
}

rust_sync.MigrationScheduledBroadcast? _nextScheduledMigrationBroadcast(
  rust_sync.MigrationStatus status,
) {
  rust_sync.MigrationScheduledBroadcast? earliest;
  for (final broadcast in status.scheduledBroadcasts) {
    if (broadcast.status.toLowerCase() != 'scheduled') continue;
    if (earliest == null ||
        broadcast.scheduledHeight < earliest.scheduledHeight) {
      earliest = broadcast;
    }
  }
  return earliest;
}

bool migrationHasDueScheduledBroadcast(
  rust_sync.MigrationStatus status, {
  required int currentHeight,
}) {
  if (currentHeight <= 0) return false;
  return status.scheduledBroadcasts.any(
    (broadcast) =>
        broadcast.status.toLowerCase() == 'scheduled' &&
        broadcast.scheduledHeight > 0 &&
        broadcast.scheduledHeight <= currentHeight,
  );
}

bool migrationHasDueProofBatch(
  rust_sync.MigrationStatus status, {
  required int currentHeight,
}) {
  final nextActionHeight = status.nextActionHeight;
  if (status.phase != kIronwoodMigrationBroadcastScheduledPhase ||
      status.signedChildPcztCount <= 0 ||
      status.proofReady != true ||
      nextActionHeight == null ||
      currentHeight <= 0 ||
      nextActionHeight > currentHeight) {
    return false;
  }

  int? earliestScheduledHeight;
  for (final broadcast in status.scheduledBroadcasts) {
    if (broadcast.status.toLowerCase() != 'scheduled' ||
        broadcast.scheduledHeight <= 0) {
      continue;
    }
    if (earliestScheduledHeight == null ||
        broadcast.scheduledHeight < earliestScheduledHeight) {
      earliestScheduledHeight = broadcast.scheduledHeight;
    }
  }

  return earliestScheduledHeight == null ||
      nextActionHeight < earliestScheduledHeight;
}

String migrationPlanCompletionDurationLabel(
  AppLocalizations l10n,
  rust_sync.OrchardMigrationPrivatePlan plan, {
  required BlockTimeEstimate blockTimes,
}) {
  final blocks = _migrationPlanCompletionBlocks(plan);
  if (blocks <= 0) return l10n.migrationNotScheduled;
  return _formatMigrationDuration(l10n, blockTimes.secondsForBlocks(blocks));
}

String migrationPlanCompletionTimingLabel(
  AppLocalizations l10n,
  rust_sync.OrchardMigrationPrivatePlan plan, {
  required BlockTimeEstimate blockTimes,
  DateTime? now,
  bool abbreviateMonth = true,
}) {
  final blocks = _migrationPlanCompletionBlocks(plan);
  if (blocks <= 0) return l10n.migrationSchedulePending;
  return _estimatedLocalCompletionTime(
    l10n,
    blockTimes.secondsForBlocks(blocks),
    now: now,
    abbreviateMonth: abbreviateMonth,
  );
}

int _migrationPlanCompletionBlocks(rust_sync.OrchardMigrationPrivatePlan plan) {
  var scheduledBlocks = 0;
  for (final transfer in plan.scheduledTransfers) {
    if (transfer.blockOffset > scheduledBlocks) {
      scheduledBlocks = transfer.blockOffset;
    }
  }
  if (plan.scheduledTransfers.isEmpty) {
    final batchCount = plan.plannedBatchCount < 1 ? 1 : plan.plannedBatchCount;
    scheduledBlocks = plan.scheduleMeanDelayBlocks * batchCount;
  }

  return migrationPlanPartDelayBlocks(
        preparationDelayBlocks: migrationPlanPreparationDelayBlocks(plan),
        scheduleOffsetBlocks: scheduledBlocks,
      ) +
      _preparationConfirmationBlocks;
}

int migrationPlanPreparationDelayBlocks(
  rust_sync.OrchardMigrationPrivatePlan plan,
) => migrationPlanNoteSplitDelayBlocks(plan) + plan.proofReadinessDelayBlocks;

int migrationPlanNoteSplitDelayBlocks(
  rust_sync.OrchardMigrationPrivatePlan plan,
) => plan.denominationSplitLayerCount <= 0
    ? 0
    : plan.denominationSplitLayerCount * _preparationConfirmationBlocks +
          _preparationBroadcastBufferBlocks;

String migrationPlanNoteSplitDurationLabel(
  AppLocalizations l10n,
  rust_sync.OrchardMigrationPrivatePlan plan, {
  required BlockTimeEstimate blockTimes,
}) => _formatMigrationDuration(
  l10n,
  blockTimes.secondsForBlocks(migrationPlanNoteSplitDelayBlocks(plan)),
);

int migrationPlanPartDelayBlocks({
  required int preparationDelayBlocks,
  required int scheduleOffsetBlocks,
}) => preparationDelayBlocks + scheduleOffsetBlocks;

/// An Immediate migration completes once its transaction and two more blocks
/// are mined.
const kIronwoodImmediateMigrationConfirmationBlocks = 3;

String ironwoodImmediateMigrationCompletionEstimate(
  AppLocalizations l10n,
  BlockTimeEstimate blockTimes,
) => _formatMigrationDuration(
  l10n,
  blockTimes.secondsForBlocks(kIronwoodImmediateMigrationConfirmationBlocks),
);

String _formatMigrationDuration(AppLocalizations l10n, int seconds) {
  final minutes = (seconds / Duration.secondsPerMinute).ceil();
  if (minutes < 60) return l10n.migrationDurationMinutes(minutes);

  final hours = (seconds / Duration.secondsPerHour).ceil();
  if (hours < 48) return l10n.migrationDurationHours(hours);

  final days = (seconds / Duration.secondsPerDay).ceil();
  return l10n.migrationDurationDays(days);
}

String migrationBlockOffsetLabel(AppLocalizations l10n, int blocks) =>
    blocks > 0
    ? l10n.migrationBlocksEstimate(blocks.toString())
    : l10n.migrationSchedulePending;

String migrationBlockOffsetDurationLabel(
  AppLocalizations l10n,
  int blocks, {
  required BlockTimeEstimate blockTimes,
}) => blocks > 0
    ? _formatMigrationDuration(l10n, blockTimes.secondsForBlocks(blocks))
    : l10n.migrationSchedulePending;

String migrationScheduledBroadcastLabel(
  AppLocalizations l10n,
  rust_sync.MigrationScheduledBroadcast broadcast, {
  DateTime? now,
  bool approximate = false,
}) {
  if (broadcast.status == 'confirmed') return l10n.migrationBroadcastConfirmed;
  if (broadcast.status == 'broadcasted') {
    return l10n.migrationBroadcastSubmitted;
  }
  if (broadcast.status != 'scheduled') return l10n.migrationBroadcastPending;

  final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
    broadcast.scheduledAtMs,
    isUtc: true,
  );
  final remaining = scheduledAt.difference((now ?? DateTime.now()).toUtc());
  if (remaining <= Duration.zero) return l10n.migrationBroadcastDueNow;

  final minutes = (remaining.inSeconds + 59) ~/ 60;
  if (minutes < 60) {
    return approximate
        ? l10n.migrationBroadcastApproxInMinutes(minutes)
        : l10n.migrationBroadcastInMinutes(minutes);
  }
  final hours = (minutes + 59) ~/ 60;
  return approximate
      ? l10n.migrationBroadcastApproxInHours(hours)
      : l10n.migrationBroadcastInHours(hours);
}

String migrationDispatchTimingLabel(
  AppLocalizations l10n,
  rust_sync.MigrationStatus status, {
  DateTime? now,
}) {
  if (status.phase == kIronwoodMigrationWaitingConfirmationsPhase) {
    return l10n.migrationConfirming;
  }

  rust_sync.MigrationScheduledBroadcast? latest;
  for (final broadcast in status.scheduledBroadcasts) {
    if (latest == null || broadcast.scheduledAtMs > latest.scheduledAtMs) {
      latest = broadcast;
    }
  }
  if (latest == null) {
    return migrationBlockOffsetLabel(l10n, status.scheduleMeanDelayBlocks);
  }

  return _migrationDateTime(
    l10n,
    DateTime.fromMillisecondsSinceEpoch(
      latest.scheduledAtMs,
      isUtc: true,
    ).toLocal(),
  );
}

String migrationCompletionTimingLabel(
  AppLocalizations l10n,
  rust_sync.MigrationStatus status, {
  required BlockTimeEstimate blockTimes,
  DateTime? now,
  int? currentHeight,
  bool abbreviateMonth = true,
}) =>
    _migrationCompletionTiming(
      l10n,
      status,
      blockTimes: blockTimes,
      now: now,
      currentHeight: currentHeight,
      abbreviateMonth: abbreviateMonth,
    ) ??
    l10n.migrationSchedulePending;

/// The completion estimate, or null while the schedule is still pending.
String? _migrationCompletionTiming(
  AppLocalizations l10n,
  rust_sync.MigrationStatus status, {
  required BlockTimeEstimate blockTimes,
  DateTime? now,
  int? currentHeight,
  bool abbreviateMonth = true,
}) {
  final useScheduledHeight = currentHeight != null && currentHeight > 0;
  final fromHeight = currentHeight != null && currentHeight > 0
      ? currentHeight
      : blockTimes.tipHeight;
  int secondsFor(int blocks) =>
      blockTimes.secondsBetween(fromHeight, fromHeight + blocks);
  final estimatedCompletionHeight = status.estimatedCompletionHeight;
  if (useScheduledHeight && status.activeRunId != null) {
    final overdueScheduledCount = status.scheduledBroadcasts
        .where(
          (broadcast) =>
              broadcast.status == 'scheduled' &&
              broadcast.scheduledHeight <= currentHeight,
        )
        .length;
    if (overdueScheduledCount > 1 || estimatedCompletionHeight == null) {
      return null;
    }
  }
  if (useScheduledHeight && estimatedCompletionHeight != null) {
    var remainingBlocks = estimatedCompletionHeight > currentHeight
        ? estimatedCompletionHeight - currentHeight
        : 0;
    if (remainingBlocks == 0 &&
        status.phase != kIronwoodMigrationCompletePhase) {
      // An overdue or just-submitted transaction still needs a block to be
      // mined and then to reach trusted depth.
      remainingBlocks = status.denominationConfirmationTarget;
    }
    return _estimatedLocalCompletionTime(
      l10n,
      secondsFor(remainingBlocks),
      now: now,
      abbreviateMonth: abbreviateMonth,
    );
  }

  rust_sync.MigrationScheduledBroadcast? latest;
  for (final broadcast in status.scheduledBroadcasts) {
    if (latest == null ||
        (useScheduledHeight
            ? broadcast.scheduledHeight > latest.scheduledHeight
            : broadcast.scheduledAtMs > latest.scheduledAtMs)) {
      latest = broadcast;
    }
  }
  if (latest == null) {
    final batchCount = status.totalCount < 1 ? 1 : status.totalCount;
    final estimatedBlocks = status.scheduleMeanDelayBlocks * batchCount;
    if (estimatedBlocks <= 0) return null;
    return _estimatedLocalCompletionTime(
      l10n,
      secondsFor(estimatedBlocks),
      now: now,
      abbreviateMonth: abbreviateMonth,
    );
  }

  if (useScheduledHeight && latest.scheduledHeight > 0) {
    final remainingBlocks = latest.scheduledHeight > currentHeight
        ? latest.scheduledHeight - currentHeight
        : 0;
    return _estimatedLocalCompletionTime(
      l10n,
      secondsFor(remainingBlocks),
      now: now,
      abbreviateMonth: abbreviateMonth,
    );
  }

  return _migrationDateTime(
    l10n,
    DateTime.fromMillisecondsSinceEpoch(
      latest.scheduledAtMs,
      isUtc: true,
    ).toLocal(),
    abbreviateMonth: abbreviateMonth,
  );
}

/// Returns a local completion estimate when the persisted schedule is being
/// recalculated and cannot yet provide an exact final height.
///
/// This is intended for progress UI only. Scheduling and broadcast decisions
/// continue to use the persisted Rust state.
String migrationApproximateCompletionTimingLabel(
  AppLocalizations l10n,
  rust_sync.MigrationStatus status, {
  required BlockTimeEstimate blockTimes,
  DateTime? now,
  required int currentHeight,
  bool abbreviateMonth = true,
}) {
  final exact = _migrationCompletionTiming(
    l10n,
    status,
    blockTimes: blockTimes,
    now: now,
    currentHeight: currentHeight,
    abbreviateMonth: abbreviateMonth,
  );
  if (exact != null) return exact;
  if (currentHeight <= 0) return l10n.migrationSchedulePending;

  final remainingPartCount = status.parts.isNotEmpty
      ? status.parts
            .where(
              (part) => part.state != rust_sync.MigrationPartState.completed,
            )
            .length
      : (status.totalCount - status.confirmedTxCount).clamp(
          0,
          status.totalCount,
        );
  if (remainingPartCount <= 0) return l10n.migrationSchedulePending;

  final nextHeight = status.nextActionHeight ?? currentHeight;
  final blocksUntilNext = nextHeight > currentHeight
      ? nextHeight - currentHeight
      : 0;
  final remainingGaps = remainingPartCount > 1 ? remainingPartCount - 1 : 0;
  final estimatedBlocks =
      blocksUntilNext +
      status.scheduleMeanDelayBlocks * remainingGaps +
      status.denominationConfirmationTarget;
  if (estimatedBlocks <= 0) return l10n.migrationSchedulePending;

  return _estimatedLocalCompletionTime(
    l10n,
    blockTimes.secondsBetween(currentHeight, currentHeight + estimatedBlocks),
    now: now,
    abbreviateMonth: abbreviateMonth,
  );
}

String? migrationNextActionTimingLabel(
  AppLocalizations l10n,
  rust_sync.MigrationStatus status, {
  required BlockTimeEstimate blockTimes,
  required int? currentHeight,
  DateTime? now,
}) {
  final nextHeight = status.nextActionHeight;
  if (nextHeight == null || currentHeight == null || currentHeight <= 0) {
    return null;
  }
  return migrationHeightTimingLabel(
    l10n,
    nextHeight,
    blockTimes: blockTimes,
    currentHeight: currentHeight,
    now: now,
  );
}

String migrationHeightTimingLabel(
  AppLocalizations l10n,
  int targetHeight, {
  required BlockTimeEstimate blockTimes,
  required int currentHeight,
  DateTime? now,
}) {
  if (targetHeight <= currentHeight) return l10n.migrationReadyNow;

  final localNow = (now ?? DateTime.now()).toLocal();
  final nextTime = localNow.add(
    Duration(seconds: blockTimes.secondsBetween(currentHeight, targetHeight)),
  );
  final time = '${_twoDigits(nextTime.hour)}:${_twoDigits(nextTime.minute)}';
  if (nextTime.year == localNow.year &&
      nextTime.month == localNow.month &&
      nextTime.day == localNow.day) {
    return '~$time';
  }
  return '~${formatMonthDay(nextTime, l10n.localeName)}';
}

String migrationHeightRemainingDurationLabel(
  AppLocalizations l10n,
  int targetHeight, {
  required BlockTimeEstimate blockTimes,
  required int currentHeight,
}) {
  if (targetHeight <= currentHeight) return l10n.migrationReadyNow;
  final seconds = blockTimes.secondsBetween(currentHeight, targetHeight);
  final minutes = (seconds / Duration.secondsPerMinute).ceil();
  if (minutes < 60) return l10n.migrationInMinutes(minutes);
  return _formatMigrationDuration(l10n, seconds);
}

String _estimatedLocalCompletionTime(
  AppLocalizations l10n,
  int seconds, {
  DateTime? now,
  required bool abbreviateMonth,
}) {
  final utcNow = (now ?? DateTime.now()).toUtc();
  final completionUtc = utcNow.add(Duration(seconds: seconds));
  return _migrationDateTime(
    l10n,
    completionUtc.toLocal(),
    abbreviateMonth: abbreviateMonth,
  );
}

String _migrationDateTime(
  AppLocalizations l10n,
  DateTime dateTime, {
  bool abbreviateMonth = true,
}) {
  // English keeps the comma that the CLDR pattern omits.
  final format = l10n.localeName == 'en'
      ? DateFormat(
          abbreviateMonth
              ? 'MMM d, HH:mm'
              : 'MMMM d, HH:mm', // l10n-ignore: date pattern
          'en',
        )
      : (abbreviateMonth
                ? DateFormat.MMMd(l10n.localeName)
                : DateFormat.MMMMd(l10n.localeName))
            .add_Hm();
  return format.format(dateTime);
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String migrationPreparationProgressLabel(
  AppLocalizations l10n,
  rust_sync.MigrationStatus status,
) {
  final total = status.denominationSplitTotalCount;
  final completed = status.denominationSplitCompletedCount.clamp(0, total);
  if (total <= 0) return l10n.migrationPreparationSplitTransactions;

  final confirmationTarget = status.denominationConfirmationTarget;
  final current = (completed + 1).clamp(1, total);
  if (confirmationTarget <= 0) {
    return l10n.migrationPreparationSplitProgress(
      current.toString(),
      total.toString(),
    );
  }
  final confirmations = status.denominationConfirmationCount.clamp(
    0,
    confirmationTarget,
  );
  if (confirmations > 0 || completed >= total) {
    final visibleConfirmations = completed >= total
        ? confirmationTarget
        : confirmations;
    return l10n.migrationPreparationConfirmations(
      visibleConfirmations.toString(),
      confirmationTarget.toString(),
    );
  }
  return l10n.migrationPreparationSplitStep(
    current.toString(),
    total.toString(),
  );
}
