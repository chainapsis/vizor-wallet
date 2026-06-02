String _roundSegment(String roundId) => Uri.encodeComponent(roundId);

String votingPollRoute(String roundId) =>
    '/voting/poll/${_roundSegment(roundId)}';

String votingReviewRoute(String roundId) =>
    '${votingPollRoute(roundId)}/review';

String votingStatusRoute(String roundId, {String? accountUuid}) {
  final base = '${votingPollRoute(roundId)}/status';
  if (accountUuid == null || accountUuid.isEmpty) return base;
  final query = Uri(queryParameters: {'account': accountUuid}).query;
  return '$base?$query';
}

String votingSubmissionConfirmedRoute(String roundId, {String? accountUuid}) {
  final base = '${votingPollRoute(roundId)}/submitted';
  if (accountUuid == null || accountUuid.isEmpty) return base;
  final query = Uri(queryParameters: {'account': accountUuid}).query;
  return '$base?$query';
}

String votingResultsRoute(String roundId) =>
    '${votingPollRoute(roundId)}/results';
