import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;

const _shareTrackingRoundStatuses = {
  'active',
  'open',
  '1',
  'session_status_active',
};

/// Whether Vizor may still check or retry pending encrypted vote shares.
bool isVotingShareTrackingOpen({
  required String roundStatus,
  required DateTime? voteEndTime,
  required DateTime now,
}) {
  final status = roundStatus.trim().toLowerCase();
  return _shareTrackingRoundStatuses.contains(status) &&
      voteEndTime != null &&
      now.isBefore(voteEndTime);
}

/// A compact projection of the persisted encrypted-share submission state.
class VotingShareStatusSummary {
  const VotingShareStatusSummary({
    required this.totalCount,
    required this.confirmedCount,
    required this.latestPendingDueAtSeconds,
    required this.usesStaggeredSubmission,
  });

  /// Builds a summary without inventing state beyond the records persisted by
  /// `zcash_voting`.
  factory VotingShareStatusSummary.fromRecords(
    Iterable<rust_wire.ShareDelegationRecordView> records,
  ) {
    var totalCount = 0;
    var confirmedCount = 0;
    BigInt? latestPendingDueAtSeconds;
    var usesStaggeredSubmission = false;
    final submitTimesByVote =
        <({int bundleIndex, int proposalId}), Map<int, BigInt>>{};

    for (final record in records) {
      totalCount++;
      final dueAt = record.submitAt > BigInt.zero
          ? record.submitAt
          : record.createdAt;
      final voteKey = (
        bundleIndex: record.bundleIndex,
        proposalId: record.proposalId,
      );
      final submitTimes = submitTimesByVote.putIfAbsent(voteKey, () => {});
      if (!usesStaggeredSubmission &&
          submitTimes.entries.any(
            (entry) =>
                entry.key != record.shareIndex &&
                entry.value != record.submitAt,
          )) {
        usesStaggeredSubmission = true;
      }
      submitTimes[record.shareIndex] = record.submitAt;

      if (record.confirmed) {
        confirmedCount++;
      } else if (latestPendingDueAtSeconds == null ||
          dueAt > latestPendingDueAtSeconds) {
        latestPendingDueAtSeconds = dueAt;
      }
    }

    return VotingShareStatusSummary(
      totalCount: totalCount,
      confirmedCount: confirmedCount,
      latestPendingDueAtSeconds: latestPendingDueAtSeconds,
      usesStaggeredSubmission: usesStaggeredSubmission,
    );
  }

  final int totalCount;
  final int confirmedCount;

  /// Latest effective due time among shares that are not yet confirmed.
  ///
  /// Delayed shares use `submitAt`; immediate shares use `createdAt`.
  final BigInt? latestPendingDueAtSeconds;

  /// Whether at least one vote was split across planned submission times.
  ///
  /// Immediate shares all use `submitAt == 0`; their persistence timestamps do
  /// not imply staggering.
  final bool usesStaggeredSubmission;

  int get pendingCount => totalCount - confirmedCount;

  bool get allConfirmed => totalCount > 0 && pendingCount == 0;

  double get confirmedFraction =>
      totalCount == 0 ? 0 : (confirmedCount / totalCount).clamp(0.0, 1.0);
}

/// Formats the expected completion time from the last pending share due time.
///
/// The estimate intentionally uses only whole minutes, hours, or days. A due
/// time that has already passed is awaiting submission or confirmation, so it
/// is described as completing soon instead of showing a misleading zero
/// duration.
String? votingShareCompletionEstimateText(
  VotingShareStatusSummary summary, {
  required DateTime now,
}) {
  final latestDueAt = summary.latestPendingDueAtSeconds;
  if (latestDueAt == null) return null;

  final nowSeconds = BigInt.from(
    now.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond,
  );
  final remainingSeconds = latestDueAt - nowSeconds;
  if (remainingSeconds <= BigInt.zero) return 'Completing soon';

  final minutes = _roundedDurationUnits(
    remainingSeconds,
    Duration.secondsPerMinute,
  );
  if (minutes < BigInt.from(Duration.minutesPerHour)) {
    return 'Complete in about ${_durationUnit(minutes, 'minute')}';
  }

  final hours = _roundedDurationUnits(
    remainingSeconds,
    Duration.secondsPerMinute * Duration.minutesPerHour,
  );
  if (hours < BigInt.from(Duration.hoursPerDay)) {
    return 'Complete in about ${_durationUnit(hours, 'hour')}';
  }

  final days = _roundedDurationUnits(
    remainingSeconds,
    Duration.secondsPerMinute * Duration.minutesPerHour * Duration.hoursPerDay,
  );
  return 'Complete in about ${_durationUnit(days, 'day')}';
}

BigInt _roundedDurationUnits(BigInt seconds, int unitSeconds) {
  final unit = BigInt.from(unitSeconds);
  final rounded = (seconds + BigInt.from(unitSeconds ~/ 2)) ~/ unit;
  return rounded < BigInt.one ? BigInt.one : rounded;
}

String _durationUnit(BigInt count, String singular) {
  return '$count $singular${count == BigInt.one ? '' : 's'}';
}
