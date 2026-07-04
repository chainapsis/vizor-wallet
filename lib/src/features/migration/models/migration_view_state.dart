import '../../../rust/api/sync.dart' as rust_sync;

/// Which migration phase the tab should render.
enum MigrationViewState {
  noOrchardFunds,
  waitingForSpendableOrchard,
  planningDenominations,
  preparingDenominations,
  waitingDenomConfirmations,
  readyToMigrate,
  buildingSigningBatch,
  signingBatch,
  broadcastScheduled,
  broadcasting,
  waitingMigrationConfirmations,
  complete,
  paused,
  failedRecoverable,
  failedTerminal,
  abandoned,
}

extension MigrationViewStateX on MigrationViewState {
  bool get hasActiveRun => switch (this) {
    MigrationViewState.preparingDenominations ||
    MigrationViewState.waitingDenomConfirmations ||
    MigrationViewState.readyToMigrate ||
    MigrationViewState.buildingSigningBatch ||
    MigrationViewState.signingBatch ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting ||
    MigrationViewState.waitingMigrationConfirmations ||
    MigrationViewState.paused ||
    MigrationViewState.failedRecoverable => true,
    _ => false,
  };

  bool get needsKeepOpenWarning => switch (this) {
    MigrationViewState.preparingDenominations ||
    MigrationViewState.waitingDenomConfirmations ||
    MigrationViewState.readyToMigrate ||
    MigrationViewState.buildingSigningBatch ||
    MigrationViewState.signingBatch ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting ||
    MigrationViewState.waitingMigrationConfirmations => true,
    _ => false,
  };

  bool get shouldPollProgress => switch (this) {
    MigrationViewState.waitingDenomConfirmations ||
    MigrationViewState.readyToMigrate ||
    MigrationViewState.buildingSigningBatch ||
    MigrationViewState.signingBatch ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting ||
    MigrationViewState.waitingMigrationConfirmations => true,
    _ => false,
  };
}

final _txidHexPattern = RegExp(r'^[0-9a-f]{64}$');

/// Pure selector for the tab state. Kept out of the widget so it is trivially
/// testable without stubbing the account/sync provider stack.
MigrationViewState migrationViewState({
  String? rustPhase,
  required bool hasPendingMigration,
  required bool hasCompletedMigration,
  required BigInt orchardBalance,
  required BigInt ironwoodBalance,
  bool preparingInFlight = false,
  bool migratingInFlight = false,
}) {
  final phaseState = migrationViewStateFromRustPhase(rustPhase);
  if (phaseState != null) return phaseState;
  if (preparingInFlight) return MigrationViewState.preparingDenominations;
  if (migratingInFlight) return MigrationViewState.buildingSigningBatch;
  if (hasPendingMigration) {
    return MigrationViewState.waitingMigrationConfirmations;
  }
  if (orchardBalance > BigInt.zero) {
    return MigrationViewState.planningDenominations;
  }
  if (hasCompletedMigration || ironwoodBalance > BigInt.zero) {
    return MigrationViewState.complete;
  }
  return MigrationViewState.noOrchardFunds;
}

MigrationViewState? migrationViewStateFromRustPhase(String? phase) {
  return switch (phase) {
    'no_orchard_funds' => MigrationViewState.noOrchardFunds,
    'waiting_for_spendable_orchard' =>
      MigrationViewState.waitingForSpendableOrchard,
    'ready_to_prepare' => MigrationViewState.planningDenominations,
    'planning_denominations' => MigrationViewState.planningDenominations,
    'preparing_denominations' => MigrationViewState.preparingDenominations,
    'waiting_denom_confirmations' =>
      MigrationViewState.waitingDenomConfirmations,
    'ready_to_migrate' => MigrationViewState.readyToMigrate,
    'building_signing_batch' => MigrationViewState.buildingSigningBatch,
    'signing_batch' => MigrationViewState.signingBatch,
    'broadcast_scheduled' => MigrationViewState.broadcastScheduled,
    'broadcasting' => MigrationViewState.broadcasting,
    'waiting_migration_confirmations' =>
      MigrationViewState.waitingMigrationConfirmations,
    'complete' => MigrationViewState.complete,
    'paused' => MigrationViewState.paused,
    'failed_recoverable' => MigrationViewState.failedRecoverable,
    'failed_terminal' => MigrationViewState.failedTerminal,
    'abandoned' => MigrationViewState.abandoned,
    _ => null,
  };
}

int migrationFirstTransactionIndex({
  required Iterable<String> transactionTxids,
  required String firstTxid,
}) {
  var index = 0;
  for (final txid in transactionTxids) {
    if (migrationTxidsMatch(txid, firstTxid)) return index;
    index += 1;
  }
  return -1;
}

bool migrationTxidsMatch(String left, String right) {
  final normalizedLeft = _normalizeTxid(left);
  final normalizedRight = _normalizeTxid(right);
  if (normalizedLeft == null || normalizedRight == null) return false;
  if (normalizedLeft == normalizedRight) return true;
  return _reverseTxidByteOrder(normalizedLeft) == normalizedRight;
}

bool migrationHasScheduledPendingBroadcasts(rust_sync.MigrationStatus? status) {
  return status?.scheduledBroadcasts.any(
        (broadcast) => broadcast.status == 'scheduled',
      ) ??
      false;
}

bool migrationHasDueScheduledBroadcast(
  rust_sync.MigrationStatus? status,
  DateTime now,
) {
  final nowMs = now.millisecondsSinceEpoch;
  return status?.scheduledBroadcasts.any(
        (broadcast) =>
            broadcast.status == 'scheduled' &&
            broadcast.scheduledAtMs.toInt() <= nowMs,
      ) ??
      false;
}

bool migrationHasBroadcastedUnconfirmedTransactions(
  rust_sync.MigrationStatus? status,
) {
  return (status?.broadcastedTxCount ?? 0) > 0;
}

bool migrationHasPendingPrepBroadcast(rust_sync.MigrationStatus? status) {
  return (status?.pendingPrepTxCount ?? 0) > 0;
}

bool migrationHasSignedChildPczts(rust_sync.MigrationStatus? status) {
  return (status?.signedChildPcztCount ?? 0) > 0;
}

bool migrationSignedChildrenMayFinalize(rust_sync.MigrationStatus? status) {
  if (!migrationHasSignedChildPczts(status)) return false;
  return status?.phase == 'ready_to_migrate';
}

bool migrationShouldRunBroadcastTick(
  rust_sync.MigrationStatus? status,
  DateTime now,
) {
  return migrationHasPendingPrepBroadcast(status) ||
      migrationHasDueScheduledBroadcast(status, now) ||
      migrationSignedChildrenMayFinalize(status);
}

bool migrationShouldWarnBeforeClose(rust_sync.MigrationStatus? status) {
  return (migrationViewStateFromRustPhase(
            status?.phase,
          )?.needsKeepOpenWarning ??
          false) ||
      migrationHasScheduledPendingBroadcasts(status) ||
      migrationHasPendingPrepBroadcast(status) ||
      migrationHasBroadcastedUnconfirmedTransactions(status) ||
      migrationHasSignedChildPczts(status);
}

bool migrationShouldWarnBeforeCloseRead({
  required bool statusKnown,
  required rust_sync.MigrationStatus? status,
}) {
  if (!statusKnown) return true;
  return migrationShouldWarnBeforeClose(status);
}

bool migrationShouldWarnBeforeCloseSnapshot({
  required bool statusKnown,
  required rust_sync.MigrationStatus? status,
  required bool keepsProgressVisible,
}) {
  if (keepsProgressVisible) return true;
  return migrationShouldWarnBeforeCloseRead(
    statusKnown: statusKnown,
    status: status,
  );
}

bool migrationShouldShowGlobalWarning(rust_sync.MigrationStatus? status) {
  return migrationShouldWarnBeforeClose(status);
}

bool migrationShouldShowEntry({
  required MigrationViewState viewState,
  required bool keepsProgressVisible,
}) {
  if (keepsProgressVisible) return false;
  return switch (viewState) {
    MigrationViewState.noOrchardFunds ||
    MigrationViewState.waitingForSpendableOrchard ||
    MigrationViewState.planningDenominations => true,
    _ => false,
  };
}

bool migrationCanStartFromEntry(MigrationViewState viewState) {
  return viewState == MigrationViewState.planningDenominations;
}

BigInt migrationDisplayAmount({
  required MigrationViewState viewState,
  required BigInt orchardAmount,
  required Iterable<BigInt> migrationTransactionAmounts,
}) {
  if (migrationShouldShowEntry(
    viewState: viewState,
    keepsProgressVisible: false,
  )) {
    return orchardAmount;
  }

  final txAmount = migrationTransactionAmounts.fold<BigInt>(
    BigInt.zero,
    (sum, amount) => sum + amount,
  );
  if (txAmount > BigInt.zero) return txAmount;
  return orchardAmount;
}

Duration? migrationRemainingScheduledSubmissionTime(
  rust_sync.MigrationStatus? status,
  DateTime now,
) {
  final scheduledBroadcasts = status?.scheduledBroadcasts.where(
    (broadcast) => broadcast.status == 'scheduled',
  );
  if (scheduledBroadcasts == null || scheduledBroadcasts.isEmpty) return null;

  final latestScheduledAtMs = scheduledBroadcasts
      .map((broadcast) => broadcast.scheduledAtMs.toInt())
      .reduce((a, b) => a > b ? a : b);
  final latestScheduledAt = DateTime.fromMillisecondsSinceEpoch(
    latestScheduledAtMs,
  );
  final remaining = latestScheduledAt.difference(now);
  return remaining.isNegative ? Duration.zero : remaining;
}

String migrationCountdownLabel(Duration remaining) {
  if (remaining.inSeconds <= 0) return '0s';

  final totalSeconds = remaining.inSeconds;
  final days = totalSeconds ~/ Duration.secondsPerDay;
  final hours =
      (totalSeconds % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;

  if (days > 0) return '${days}d ${hours}h ${minutes}m ${seconds}s';
  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String? _normalizeTxid(String txid) {
  final normalized = txid.trim().toLowerCase();
  if (!_txidHexPattern.hasMatch(normalized)) return null;
  return normalized;
}

String _reverseTxidByteOrder(String txid) {
  final reversed = StringBuffer();
  for (var i = txid.length; i > 0; i -= 2) {
    reversed.write(txid.substring(i - 2, i));
  }
  return reversed.toString();
}

/// Whether the global migration tick should auto-fire software stage 2. Software
/// reaches `ready_to_migrate` with no presigned children (those are a hardware
/// concept), so the second stage must be kicked off for it. Hardware is excluded
/// — its children are already presigned and promoted by the tick.
bool migrationShouldAutoAdvanceSoftware({
  required rust_sync.MigrationStatus? status,
  required bool isHardware,
  required bool runInFlight,
  required bool alreadyAttempted,
}) {
  if (status == null || isHardware || runInFlight || alreadyAttempted) {
    return false;
  }
  return status.phase == 'ready_to_migrate' && status.signedChildPcztCount == 0;
}

/// True when a single-QR Keystone signing request was rejected purely because
/// the migration has more notes than one QR can carry. Used to fall back to the
/// staged (denominations-only → batch) multi-QR flow.
bool migrationIsSingleQrTooLargeError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('single keystone migration signing supports at most') ||
      (lower.contains('migration notes') && lower.contains('at most'));
}

/// Whether the staged Keystone fallback's Send stage is waiting on the user to
/// scan the batch QR. The denomination split has confirmed (run reached
/// `ready_to_migrate`) but no presigned children exist yet.
bool timelineSendIsAwaitingScan(
  MigrationViewState viewState,
  rust_sync.MigrationStatus? status,
) {
  final atSend = viewState == MigrationViewState.readyToMigrate;
  return atSend && (status?.signedChildPcztCount ?? 0) == 0;
}
