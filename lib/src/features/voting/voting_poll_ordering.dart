import '../../core/formatting/date_format.dart';
import '../../providers/voting/voting_state.dart';

enum VotingPollListStatus { active, tallying, closed }

enum VotingPollOrderingState { inProgress, active, voted, closed }

List<VotingRoundView> sortVotingRoundsForPollList(
  List<VotingRoundView> rounds,
) {
  final indexedRounds = rounds.asMap().entries.toList();
  indexedRounds.sort((a, b) {
    final aState = votingPollOrderingState(a.value);
    final bState = votingPollOrderingState(b.value);
    final rankCompare = _orderingRank(aState).compareTo(_orderingRank(bState));
    if (rankCompare != 0) return rankCompare;

    final dateCompare = _compareDates(
      votingRoundEndDate(a.value.rawJson),
      votingRoundEndDate(b.value.rawJson),
      ascending: aState != VotingPollOrderingState.closed,
    );
    if (dateCompare != 0) return dateCompare;

    return a.key.compareTo(b.key);
  });
  return [for (final entry in indexedRounds) entry.value];
}

VotingPollOrderingState votingPollOrderingState(VotingRoundView round) {
  return switch (votingPollListStatus(round.status)) {
    VotingPollListStatus.active =>
      round.inProgress
          ? VotingPollOrderingState.inProgress
          : round.voted
          ? VotingPollOrderingState.voted
          : VotingPollOrderingState.active,
    VotingPollListStatus.tallying ||
    VotingPollListStatus.closed => VotingPollOrderingState.closed,
  };
}

VotingPollListStatus votingPollListStatus(String value) {
  final status = value.trim().toLowerCase();
  if (status == '1') return VotingPollListStatus.active;
  if (status == '2') return VotingPollListStatus.tallying;
  if (status == '3') return VotingPollListStatus.closed;
  if (status.contains('tally')) return VotingPollListStatus.tallying;
  if (status.contains('closed') ||
      status.contains('complete') ||
      status.contains('done') ||
      status.contains('ended') ||
      status.contains('final') ||
      status.contains('result')) {
    return VotingPollListStatus.closed;
  }
  return VotingPollListStatus.active;
}

DateTime? votingRoundStartDate(Map<String, dynamic> json) {
  return _dateFromJson(json, const [
    'start_date',
    'startDate',
    'starts_at',
    'startsAt',
    'open_date',
    'openDate',
    'opens_at',
    'opensAt',
    'start_time',
    'startTime',
    'starts',
    'start',
    'voting_start',
    'votingStart',
    'poll_start',
    'pollStart',
    'vote_start_time',
    'voteStartTime',
    'ceremony_phase_start',
    'ceremonyPhaseStart',
    'created_at',
    'createdAt',
    'published_at',
    'publishedAt',
  ]);
}

DateTime? votingRoundEndDate(Map<String, dynamic> json) {
  return _dateFromJson(json, const [
    'end_date',
    'endDate',
    'ends_at',
    'endsAt',
    'close_date',
    'closeDate',
    'closes_at',
    'closesAt',
    'end_time',
    'endTime',
    'ends',
    'end',
    'deadline',
    'voting_end',
    'votingEnd',
    'poll_end',
    'pollEnd',
    'vote_end_time',
    'voteEndTime',
  ]);
}

int _orderingRank(VotingPollOrderingState state) {
  return switch (state) {
    VotingPollOrderingState.inProgress => 0,
    VotingPollOrderingState.active => 1,
    VotingPollOrderingState.voted => 2,
    VotingPollOrderingState.closed => 3,
  };
}

int _compareDates(DateTime? a, DateTime? b, {required bool ascending}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final comparison = a.compareTo(b);
  return ascending ? comparison : -comparison;
}

DateTime? _dateFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _valueFromJson(json, key);
    final date = parseFlexibleDate(value);
    if (date != null) return date;
  }
  return null;
}

Object? _valueFromJson(Object? value, String key) {
  if (value is! Map) return null;
  if (value.containsKey(key)) return value[key];
  for (final entry in value.entries) {
    if (entry.key.toString() == key) return entry.value;
  }
  for (final entry in value.entries) {
    final nested = entry.value;
    if (nested is Map) {
      final match = _valueFromJson(nested, key);
      if (match != null) return match;
    }
  }
  return null;
}
