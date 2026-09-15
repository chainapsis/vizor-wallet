/// Keep active rounds in the future, stable throughout one preview session.
final wbVotingActiveEndDate = DateTime.now().add(const Duration(days: 7));

final wbVotingActiveEndTime = wbVotingActiveEndDate.toUtc().toIso8601String();
