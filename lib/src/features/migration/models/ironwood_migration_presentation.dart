import '../../../rust/api/sync.dart' as rust_sync;
import 'ironwood_migration_phases.dart';

const _estimatedSecondsPerBlock = 75;
const _preparationConfirmationBlocks = 3;
const _preparationBroadcastBufferBlocks = 1;

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
) => plan.denominationSplitStageCount <= 0
    ? 0
    : plan.denominationSplitStageCount * _preparationConfirmationBlocks +
          _preparationBroadcastBufferBlocks +
          plan.proofReadinessDelayBlocks;

int migrationPlanPartDelayBlocks({
  required int preparationDelayBlocks,
  required int scheduleOffsetBlocks,
}) => preparationDelayBlocks + scheduleOffsetBlocks;

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
  final blocksUntilNext = nextHeight > currentHeight
      ? nextHeight - currentHeight
      : 0;
  final remainingGaps = remainingPartCount > 1 ? remainingPartCount - 1 : 0;
  final estimatedBlocks =
      blocksUntilNext +
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
  if (targetHeight <= currentHeight) return 'soon';

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
  if (targetHeight <= currentHeight) return 'soon';
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
  if (completed >= total) {
    return '$completed of $total split transactions confirmed';
  }

  final current = (completed + 1).clamp(1, total);
  final confirmationTarget = status.denominationConfirmationTarget;
  if (confirmationTarget <= 0) return 'Preparing split $current of $total';
  final confirmations = status.denominationConfirmationCount.clamp(
    0,
    confirmationTarget,
  );
  return 'Split $current of $total, $confirmations of $confirmationTarget '
      'confirmations';
}

String _counted(int count, String singular, String plural) =>
    '$count ${_pluralized(count, singular, plural)}';

String _pluralized(int count, String singular, String plural) =>
    count == 1 ? singular : plural;
