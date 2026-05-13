import '../../rust/api/voting.dart' as rust_voting;
import '../../providers/voting/voting_state.dart';

const Duration kVotingShareStatusCheckGrace = Duration(seconds: 10);
const Duration kVotingShareMinOverdueThreshold = Duration(seconds: 30);
const Duration kVotingShareMaxOverdueThreshold = Duration(hours: 1);
const Duration kVotingShareResubmitCutoff = Duration(seconds: 10);

/// Pure timing policy for helper-share scheduling and recovery.
///
/// This mirrors zodl iOS: initial shares may be delayed until before the
/// last-moment buffer, while overdue recovery retries are submitted immediately.
abstract final class VotingShareTimingPolicy {
  static List<rust_voting.ApiDraftVote> applyLastMomentMode(
    List<rust_voting.ApiDraftVote> draftVotes,
    VotingRoundDetails round, {
    DateTime? now,
  }) {
    if (!round.isLastMoment(now)) return draftVotes;
    return [
      for (final draft in draftVotes)
        rust_voting.ApiDraftVote(
          proposalId: draft.proposalId,
          choice: draft.choice,
          numOptions: draft.numOptions,
          vcTreePosition: draft.vcTreePosition,
          singleShare: true,
        ),
    ];
  }

  static int scheduledShareSubmitAt(
    VotingRoundDetails round, {
    DateTime? now,
    double Function()? randomDouble,
  }) {
    final end = round.voteEndTime;
    final buffer = round.lastMomentBuffer;
    final current = (now ?? DateTime.now()).toUtc();
    if (end == null || buffer == null || round.isLastMoment(current)) return 0;

    final deadline = end.subtract(buffer);
    if (!deadline.isAfter(current)) return 0;

    final windowSeconds = deadline.difference(current).inSeconds;
    if (windowSeconds <= 0) return 0;
    final sample = randomDouble?.call() ?? 0;
    final clamped = sample.clamp(0.0, 0.999999999).toDouble();
    final delaySeconds = (clamped * windowSeconds).floor();
    return current.millisecondsSinceEpoch ~/ 1000 + delaySeconds;
  }

  static int shareRecoveryBaseTime(rust_voting.ApiShareDelegationRecord share) {
    final submitAt = _secondsFromBigInt(share.submitAt);
    if (submitAt > 0) return submitAt;
    return _secondsFromBigInt(share.createdAt);
  }

  static bool isShareReadyForStatusCheck(
    rust_voting.ApiShareDelegationRecord share, {
    required int nowSeconds,
    Duration checkGrace = kVotingShareStatusCheckGrace,
  }) {
    return nowSeconds >= shareRecoveryBaseTime(share) + checkGrace.inSeconds;
  }

  static Duration overdueThreshold(
    rust_voting.ApiShareDelegationRecord share, {
    required int voteEndTimeSeconds,
  }) {
    final baseTime = shareRecoveryBaseTime(share);
    final remainingWindow = voteEndTimeSeconds > baseTime
        ? voteEndTimeSeconds - baseTime
        : 0;
    final thresholdSeconds = remainingWindow ~/ 4;
    final bounded = thresholdSeconds.clamp(
      kVotingShareMinOverdueThreshold.inSeconds,
      kVotingShareMaxOverdueThreshold.inSeconds,
    );
    return Duration(seconds: bounded);
  }

  static bool shouldResubmitShare(
    rust_voting.ApiShareDelegationRecord share, {
    required int nowSeconds,
    required int voteEndTimeSeconds,
    Duration resubmitCutoff = kVotingShareResubmitCutoff,
  }) {
    final baseTime = shareRecoveryBaseTime(share);
    final threshold = overdueThreshold(
      share,
      voteEndTimeSeconds: voteEndTimeSeconds,
    );
    return nowSeconds >= baseTime + threshold.inSeconds &&
        voteEndTimeSeconds > nowSeconds + resubmitCutoff.inSeconds;
  }

  static Duration? nextTrackingDelay(
    Iterable<rust_voting.ApiShareDelegationRecord> shares,
    VotingRoundDetails round, {
    DateTime? now,
    Duration checkGrace = kVotingShareStatusCheckGrace,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    final nowSeconds = current.millisecondsSinceEpoch ~/ 1000;
    final voteEndSeconds = round.voteEndTime == null
        ? null
        : round.voteEndTime!.millisecondsSinceEpoch ~/ 1000;
    int? nextSecond;

    for (final share in shares.where((share) => !share.confirmed)) {
      final baseTime = shareRecoveryBaseTime(share);
      final checkAt = baseTime + checkGrace.inSeconds;
      nextSecond = _minSecond(nextSecond, checkAt);
      if (voteEndSeconds != null) {
        final retryAt =
            baseTime +
            overdueThreshold(
              share,
              voteEndTimeSeconds: voteEndSeconds,
            ).inSeconds;
        if (voteEndSeconds > retryAt + kVotingShareResubmitCutoff.inSeconds) {
          nextSecond = _minSecond(nextSecond, retryAt);
        }
      }
    }

    if (nextSecond == null) return null;
    final delaySeconds = nextSecond - nowSeconds;
    if (delaySeconds <= 0) return Duration.zero;
    return Duration(seconds: delaySeconds);
  }
}

class VotingShareTrackingSummary {
  final int total;
  final int confirmed;
  final int waiting;
  final int ready;
  final int overdue;

  const VotingShareTrackingSummary({
    required this.total,
    required this.confirmed,
    required this.waiting,
    required this.ready,
    required this.overdue,
  });

  factory VotingShareTrackingSummary.fromShares(
    Iterable<rust_voting.ApiShareDelegationRecord> shares,
    VotingRoundDetails round, {
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    final nowSeconds = current.millisecondsSinceEpoch ~/ 1000;
    final voteEndSeconds = round.voteEndTime?.millisecondsSinceEpoch;
    var confirmed = 0;
    var waiting = 0;
    var ready = 0;
    var overdue = 0;
    var total = 0;

    for (final share in shares) {
      total++;
      if (share.confirmed) {
        confirmed++;
        continue;
      }
      final endSeconds = voteEndSeconds == null ? null : voteEndSeconds ~/ 1000;
      if (endSeconds != null &&
          VotingShareTimingPolicy.shouldResubmitShare(
            share,
            nowSeconds: nowSeconds,
            voteEndTimeSeconds: endSeconds,
          )) {
        overdue++;
      } else if (VotingShareTimingPolicy.isShareReadyForStatusCheck(
        share,
        nowSeconds: nowSeconds,
      )) {
        ready++;
      } else {
        waiting++;
      }
    }

    return VotingShareTrackingSummary(
      total: total,
      confirmed: confirmed,
      waiting: waiting,
      ready: ready,
      overdue: overdue,
    );
  }

  bool get hasShares => total > 0;
}

int _secondsFromBigInt(BigInt value) {
  if (value <= BigInt.zero) return 0;
  final max = BigInt.from(0x7fffffff);
  if (value > max) return max.toInt();
  return value.toInt();
}

int _minSecond(int? current, int candidate) {
  if (current == null || candidate < current) return candidate;
  return current;
}
