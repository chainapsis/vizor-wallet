import '../../../rust/api/sync.dart' as rust_sync;
import 'ironwood_migration_phases.dart';

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
  return 'Vizor will prepare your $amountText ZEC in $splitTransactions, '
      'then migrate it in $migrationBatches.';
}

String privateMigrationMethodDescription(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  if (plan.plannedBatchCount <= 1) {
    return 'Uses one migration transaction after preparation. No timing '
        'separation is added.';
  }
  return 'Spreads ${migrationBatchesLabel(plan.plannedBatchCount)} over '
      '${migrationPlanCompletionLabel(plan)} '
      'instead of sending them all at once.';
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

String migrationBlockOffsetLabel(int blocks) =>
    blocks > 0 ? '~$blocks blocks' : 'Schedule pending';

String migrationScheduledBroadcastLabel(
  rust_sync.MigrationScheduledBroadcast broadcast, {
  DateTime? now,
}) {
  if (broadcast.status == 'confirmed') return 'Confirmed';
  if (broadcast.status == 'broadcasted') return 'Submitted';
  if (broadcast.status != 'scheduled') return 'Pending';

  final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
    broadcast.scheduledAtMs,
  );
  final remaining = scheduledAt.difference(now ?? DateTime.now());
  if (remaining <= Duration.zero) return 'Due now';

  final minutes = (remaining.inSeconds + 59) ~/ 60;
  if (minutes < 60) return 'in $minutes min';
  final hours = (minutes + 59) ~/ 60;
  return 'in $hours ${_pluralized(hours, 'hr', 'hrs')}';
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

  return _shortMigrationDateTime(
    DateTime.fromMillisecondsSinceEpoch(latest.scheduledAtMs).toLocal(),
  );
}

String _shortMigrationDateTime(DateTime dateTime) {
  const months = [
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
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${months[dateTime.month - 1]} ${dateTime.day}, $hour:$minute';
}

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
