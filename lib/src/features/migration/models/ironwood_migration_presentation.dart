import '../../../rust/api/sync.dart' as rust_sync;
import 'ironwood_migration_phases.dart';

const _estimatedSecondsPerBlock = 75;
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
) =>
    [...parts]..sort(compareMigrationPartsByExpectedProcessingOrder);

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

MigrationNextActionPresentation migrationNextActionPresentation({
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
      label: 'Next migration',
      amountZatoshi: selected?.valueZatoshi ?? fallbackAmount,
      detail: scheduledHeight == null ? 'Ready to sign' : 'at',
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
  final proofWindowIsNext = nextProofWindowHeight != null &&
      proofWindowPartIndices.isNotEmpty &&
      (earliestScheduledHeight == null ||
          nextProofWindowHeight < earliestScheduledHeight);
  if (proofWindowIsNext) {
    final windowAmount = parts
        .where((part) => proofWindowPartIndices.contains(part.partIndex))
        .fold(BigInt.zero, (sum, part) => sum + part.valueZatoshi);
    final displayAmount =
        windowAmount > BigInt.zero ? windowAmount : fallbackAmount;
    if (status.proofReady == false &&
        currentHeight > 0 &&
        currentHeight >= nextProofWindowHeight) {
      return MigrationNextActionPresentation(
        label: 'Opening migration window',
        amountZatoshi: displayAmount,
        detail: 'Waiting for wallet sync',
      );
    }
    if (status.proofReady == true) {
      return MigrationNextActionPresentation(
        label: 'Migration window ready',
        amountZatoshi: displayAmount,
        detail: 'Preparing migration',
      );
    }
    return MigrationNextActionPresentation(
      label: 'Next migration window',
      amountZatoshi: displayAmount,
      detail: 'Expected at',
      scheduledHeight: nextProofWindowHeight,
    );
  }

  if (status.phase == kIronwoodMigrationReadyToMigratePhase &&
      !migrationHasTransferProgress(status)) {
    final nextPart = parts.isEmpty ? null : parts.first;
    final nextValue = nextPart?.valueZatoshi ??
        (status.targetValuesZatoshi.isEmpty
            ? fallbackAmount
            : status.targetValuesZatoshi.first);
    return MigrationNextActionPresentation(
      label: 'Next migration',
      amountZatoshi: nextValue,
      detail: nextPart?.scheduledHeight == null ? 'Schedule pending' : 'at',
      scheduledHeight: nextPart?.scheduledHeight,
    );
  }

  final scheduled = _firstMigrationPart(
    parts,
    (part) => part.state == rust_sync.MigrationPartState.scheduled,
  );
  final legacyBroadcast =
      scheduled == null ? _nextScheduledMigrationBroadcast(status) : null;
  if (scheduled != null || legacyBroadcast != null) {
    final scheduledHeight =
        scheduled?.scheduledHeight ?? legacyBroadcast?.scheduledHeight;
    final isDue = scheduledHeight != null &&
        currentHeight > 0 &&
        scheduledHeight <= currentHeight;
    return MigrationNextActionPresentation(
      label: isDue ? 'Sending migration' : 'Next migration',
      amountZatoshi: scheduled?.valueZatoshi ??
          legacyBroadcast?.valueZatoshi ??
          fallbackAmount,
      detail: isDue
          ? 'Sending now'
          : scheduledHeight == null
              ? 'Schedule pending'
              : 'at',
      scheduledHeight: isDue ? null : scheduledHeight,
    );
  }

  final preparing = _firstMigrationPart(
    parts,
    (part) => part.state == rust_sync.MigrationPartState.preparing,
  );
  if (preparing != null) {
    return MigrationNextActionPresentation(
      label: 'Next migration',
      amountZatoshi: preparing.valueZatoshi,
      detail: 'Schedule pending',
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
        .where(
          (part) => part.state == rust_sync.MigrationPartState.migrating,
        )
        .length;
    final confirmingCount = inFlight.length - migratingCount;
    if (migratingCount > 0 && confirmingCount == 0) {
      return MigrationNextActionPresentation(
        label: 'Awaiting mining',
        amountZatoshi: amount,
        detail: _migrationNoteCountLabel(migratingCount, 'broadcast'),
      );
    }
    if (confirmingCount > 0 && migratingCount == 0) {
      return MigrationNextActionPresentation(
        label: 'Confirming',
        amountZatoshi: amount,
        detail: _migrationNoteCountLabel(
          confirmingCount,
          'awaiting confirmation',
        ),
      );
    }
    return MigrationNextActionPresentation(
      label: 'Finalizing migration',
      amountZatoshi: amount,
      detail: _migrationNoteCountLabel(inFlight.length, 'remaining'),
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
        label: 'Finalizing migration',
        amountZatoshi: fallbackAmount,
        detail: 'Waiting for confirmations',
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
      for (var index = confirmedCount;
          index < broadcastedCount && index < values.length;
          index++) {
        amount += values[index];
      }
      return MigrationNextActionPresentation(
        label: 'Confirming',
        amountZatoshi: amount > BigInt.zero ? amount : fallbackAmount,
        detail: _migrationNoteCountLabel(
          broadcastedCount - confirmedCount,
          'awaiting confirmation',
        ),
      );
    }
    if (confirmedCount < status.totalCount) {
      final amount = confirmedCount < values.length
          ? values[confirmedCount]
          : fallbackAmount;
      final nextHeight = status.nextActionHeight;
      return MigrationNextActionPresentation(
        label: 'Next migration',
        amountZatoshi: amount,
        detail: nextHeight == null ? 'Schedule pending' : 'at',
        scheduledHeight: nextHeight,
      );
    }
    return MigrationNextActionPresentation(
      label: 'Finalizing migration',
      amountZatoshi: fallbackAmount,
      detail: 'Waiting for confirmations',
    );
  }

  if (waitingForAnchor) {
    return MigrationNextActionPresentation(
      label: 'Next migration',
      amountZatoshi: fallbackAmount,
      detail: 'Schedule pending',
    );
  }
  return MigrationNextActionPresentation(
    label: 'Migration complete',
    amountZatoshi: fallbackAmount,
    detail: 'All notes completed',
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

String _migrationNoteCountLabel(int count, String state) =>
    '$count ${count == 1 ? 'note' : 'notes'} $state';

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

String plannedMigrationBatchesLabel(int count) =>
    '$count planned ${_pluralized(count, 'batch', 'batches')}';

String migrationBatchesLabel(int count) =>
    '$count ${_pluralized(count, 'batch', 'batches')}';

String migrationPlanPreparationDescription({
  required rust_sync.OrchardMigrationPrivatePlan plan,
  required String amountText,
}) {
  final splitTransactions = _counted(
    plan.denominationSplitStageCount,
    'split transaction',
    'split transactions',
  );
  final migrationBatches = _counted(
    plan.plannedBatchCount,
    'migration batch',
    'migration batches',
  );
  return 'Your $amountText ZEC balance is prepared in $splitTransactions, '
      'then moved in $migrationBatches. Common-sized parts make each '
      'transfer less distinctive.';
}

String privateMigrationMethodDescription(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  if (plan.plannedBatchCount <= 1) {
    return 'Sends one migration part after preparation. No timing '
        'separation is added.';
  }
  return 'Sends '
      '${_counted(plan.plannedBatchCount, 'independent part', 'independent parts')} '
      'over ${migrationPlanCompletionLabel(plan)}. Slower, harder to '
      'associate.';
}

String migrationPlanCompletionLabel(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  var finalBlockOffset = 0;
  for (final transfer in plan.scheduledTransfers) {
    if (transfer.blockOffset > finalBlockOffset) {
      finalBlockOffset = transfer.blockOffset;
    }
  }
  return migrationBlockOffsetLabel(finalBlockOffset);
}

String migrationPlanCompletionDurationLabel(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final blocks = _migrationPlanCompletionBlocks(plan);
  if (blocks <= 0) return 'Not scheduled';
  return _formatMigrationDuration(blocks);
}

String migrationPlanCompletionTimingLabel(
  rust_sync.OrchardMigrationPrivatePlan plan, {
  DateTime? now,
  bool abbreviateMonth = true,
}) {
  final blocks = _migrationPlanCompletionBlocks(plan);
  if (blocks <= 0) return 'Schedule pending';
  return _estimatedLocalCompletionTime(
    blocks,
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
) =>
    migrationPlanNoteSplitDelayBlocks(plan) + plan.proofReadinessDelayBlocks;

int migrationPlanNoteSplitDelayBlocks(
  rust_sync.OrchardMigrationPrivatePlan plan,
) =>
    plan.denominationSplitLayerCount <= 0
        ? 0
        : plan.denominationSplitLayerCount * _preparationConfirmationBlocks +
            _preparationBroadcastBufferBlocks;

String migrationPlanNoteSplitDurationLabel(
  rust_sync.OrchardMigrationPrivatePlan plan,
) =>
    _formatMigrationDuration(migrationPlanNoteSplitDelayBlocks(plan));

int migrationPlanPartDelayBlocks({
  required int preparationDelayBlocks,
  required int scheduleOffsetBlocks,
}) =>
    preparationDelayBlocks + scheduleOffsetBlocks;

String _formatMigrationDuration(int blocks) {
  final seconds = blocks * _estimatedSecondsPerBlock;
  final minutes = (seconds / Duration.secondsPerMinute).ceil();
  if (minutes < 60) return minutes == 1 ? '~1 min' : '~$minutes mins';

  final hours = (seconds / Duration.secondsPerHour).ceil();
  if (hours < 48) return hours == 1 ? '~1 hr' : '~$hours hrs';

  final days = (seconds / Duration.secondsPerDay).ceil();
  return days == 1 ? '~1 day' : '~$days days';
}

String migrationBlockOffsetLabel(int blocks) =>
    blocks > 0 ? '~$blocks blocks' : 'Schedule pending';

String migrationBlockOffsetDurationLabel(int blocks) =>
    blocks > 0 ? _formatMigrationDuration(blocks) : 'Schedule pending';

String migrationScheduledBroadcastLabel(
  rust_sync.MigrationScheduledBroadcast broadcast, {
  DateTime? now,
  bool approximate = false,
}) {
  if (broadcast.status == 'confirmed') return 'Confirmed';
  if (broadcast.status == 'broadcasted') return 'Submitted';
  if (broadcast.status != 'scheduled') return 'Pending';

  final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
    broadcast.scheduledAtMs,
    isUtc: true,
  );
  final remaining = scheduledAt.difference((now ?? DateTime.now()).toUtc());
  if (remaining <= Duration.zero) return 'Due now';

  final minutes = (remaining.inSeconds + 59) ~/ 60;
  final prefix = approximate ? '~' : '';
  if (minutes < 60) return '${prefix}in $minutes min';
  final hours = (minutes + 59) ~/ 60;
  return '${prefix}in $hours ${_pluralized(hours, 'hr', 'hrs')}';
}

String migrationDispatchTimingLabel(
  rust_sync.MigrationStatus status, {
  DateTime? now,
}) {
  if (status.phase == kIronwoodMigrationWaitingConfirmationsPhase) {
    return 'Confirming';
  }

  rust_sync.MigrationScheduledBroadcast? latest;
  for (final broadcast in status.scheduledBroadcasts) {
    if (latest == null || broadcast.scheduledAtMs > latest.scheduledAtMs) {
      latest = broadcast;
    }
  }
  if (latest == null) {
    return migrationBlockOffsetLabel(status.scheduleMeanDelayBlocks);
  }

  return _migrationDateTime(
    DateTime.fromMillisecondsSinceEpoch(
      latest.scheduledAtMs,
      isUtc: true,
    ).toLocal(),
  );
}

String migrationCompletionTimingLabel(
  rust_sync.MigrationStatus status, {
  DateTime? now,
  int? currentHeight,
  bool abbreviateMonth = true,
}) {
  final useScheduledHeight = currentHeight != null && currentHeight > 0;
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
      return 'Schedule pending';
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
      remainingBlocks,
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
    if (estimatedBlocks <= 0) return 'Schedule pending';
    return _estimatedLocalCompletionTime(
      estimatedBlocks,
      now: now,
      abbreviateMonth: abbreviateMonth,
    );
  }

  if (useScheduledHeight && latest.scheduledHeight > 0) {
    final remainingBlocks = latest.scheduledHeight > currentHeight
        ? latest.scheduledHeight - currentHeight
        : 0;
    return _estimatedLocalCompletionTime(
      remainingBlocks,
      now: now,
      abbreviateMonth: abbreviateMonth,
    );
  }

  return _migrationDateTime(
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
  rust_sync.MigrationStatus status, {
  DateTime? now,
  required int currentHeight,
  bool abbreviateMonth = true,
}) {
  final exact = migrationCompletionTimingLabel(
    status,
    now: now,
    currentHeight: currentHeight,
    abbreviateMonth: abbreviateMonth,
  );
  if (exact != 'Schedule pending' || currentHeight <= 0) return exact;

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
  if (remainingPartCount <= 0) return exact;

  final nextHeight = status.nextActionHeight ?? currentHeight;
  final blocksUntilNext =
      nextHeight > currentHeight ? nextHeight - currentHeight : 0;
  final remainingGaps = remainingPartCount > 1 ? remainingPartCount - 1 : 0;
  final estimatedBlocks = blocksUntilNext +
      status.scheduleMeanDelayBlocks * remainingGaps +
      status.denominationConfirmationTarget;
  if (estimatedBlocks <= 0) return exact;

  return _estimatedLocalCompletionTime(
    estimatedBlocks,
    now: now,
    abbreviateMonth: abbreviateMonth,
  );
}

String? migrationNextActionTimingLabel(
  rust_sync.MigrationStatus status, {
  required int? currentHeight,
  DateTime? now,
}) {
  final nextHeight = status.nextActionHeight;
  if (nextHeight == null || currentHeight == null || currentHeight <= 0) {
    return null;
  }
  return migrationHeightTimingLabel(
    nextHeight,
    currentHeight: currentHeight,
    now: now,
  );
}

String migrationHeightTimingLabel(
  int targetHeight, {
  required int currentHeight,
  DateTime? now,
}) {
  if (targetHeight <= currentHeight) return 'ready now';

  final localNow = (now ?? DateTime.now()).toLocal();
  final nextTime = localNow.add(
    Duration(
      seconds: (targetHeight - currentHeight) * _estimatedSecondsPerBlock,
    ),
  );
  final time = '${_twoDigits(nextTime.hour)}:${_twoDigits(nextTime.minute)}';
  if (nextTime.year == localNow.year &&
      nextTime.month == localNow.month &&
      nextTime.day == localNow.day) {
    return '~$time';
  }
  return '~${_shortMonth(nextTime.month)} ${nextTime.day}';
}

String migrationHeightRemainingDurationLabel(
  int targetHeight, {
  required int currentHeight,
}) {
  if (targetHeight <= currentHeight) return 'ready now';
  final remainingBlocks = targetHeight - currentHeight;
  final seconds = remainingBlocks * _estimatedSecondsPerBlock;
  final minutes = (seconds / Duration.secondsPerMinute).ceil();
  if (minutes < 60) {
    return minutes == 1 ? '~in 1 minute' : '~in $minutes minutes';
  }
  return _formatMigrationDuration(remainingBlocks);
}

String _estimatedLocalCompletionTime(
  int blocks, {
  DateTime? now,
  required bool abbreviateMonth,
}) {
  final utcNow = (now ?? DateTime.now()).toUtc();
  final completionUtc = utcNow.add(
    Duration(seconds: blocks * _estimatedSecondsPerBlock),
  );
  return _migrationDateTime(
    completionUtc.toLocal(),
    abbreviateMonth: abbreviateMonth,
  );
}

String _migrationDateTime(DateTime dateTime, {bool abbreviateMonth = true}) {
  const shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const longMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final month = abbreviateMonth
      ? shortMonths[dateTime.month - 1]
      : longMonths[dateTime.month - 1];
  return '$month ${dateTime.day}, $hour:$minute';
}

String _shortMonth(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String migrationPreparationProgressLabel(rust_sync.MigrationStatus status) {
  final total = status.denominationSplitTotalCount;
  final completed = status.denominationSplitCompletedCount.clamp(0, total);
  if (total <= 0) return 'Preparing split transactions';

  final confirmationTarget = status.denominationConfirmationTarget;
  final current = (completed + 1).clamp(1, total);
  if (confirmationTarget <= 0) return 'Preparing split $current of $total';
  final confirmations = status.denominationConfirmationCount.clamp(
    0,
    confirmationTarget,
  );
  if (confirmations > 0 || completed >= total) {
    final visibleConfirmations =
        completed >= total ? confirmationTarget : confirmations;
    return '$visibleConfirmations of $confirmationTarget confirmations';
  }
  return 'Split $current of $total';
}

String _counted(int count, String singular, String plural) =>
    '$count ${_pluralized(count, singular, plural)}';

String _pluralized(int count, String singular, String plural) =>
    count == 1 ? singular : plural;
