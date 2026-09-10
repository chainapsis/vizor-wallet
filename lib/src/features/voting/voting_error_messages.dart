import 'voting_eligibility_explanation.dart';

String friendlyVotingErrorMessage(Object error) {
  return friendlyVotingErrorText(error.toString());
}

bool isVotingEligibilityErrorText(String text) {
  final message = _normalizedVotingErrorText(text);
  final lowerMessage = message.toLowerCase();
  return _noSpendableNotesPattern.firstMatch(message) != null ||
      _minimumVotingEligibilityPattern.firstMatch(message) != null ||
      lowerMessage.contains('no eligible ironwood notes') ||
      lowerMessage.contains('no eligible shielded funds') ||
      lowerMessage.startsWith('this account is not eligible for this ') ||
      lowerMessage.startsWith('only ironwood notes this account held') ||
      lowerMessage.startsWith('voting needs at least 0.125 zec') ||
      lowerMessage.startsWith(
        'voting requires at least one eligible shielded note bundle with 0.125 zec',
      ) ||
      lowerMessage.startsWith(
        'voting requires at least 0.125 zec in eligible shielded funds',
      ) ||
      lowerMessage.startsWith(
        'voting requires at least 5 eligible shielded notes totaling 0.125 zec',
      );
}

String friendlyVotingErrorText(String text) {
  final message = _normalizedVotingErrorText(text);
  final noSpendableNotes = _noSpendableNotesPattern.firstMatch(message);
  if (noSpendableNotes != null) {
    return VotingEligibilityExplanation(
      reason: VotingEligibilityExclusionReason.noNotesAtSnapshot,
      snapshotHeight: int.tryParse(noSpendableNotes.group(1) ?? ''),
    ).combinedMessage;
  }

  final minimumVotingEligibility = _minimumVotingEligibilityPattern.firstMatch(
    message,
  );
  if (minimumVotingEligibility != null) {
    return VotingEligibilityExplanation(
      reason: VotingEligibilityExclusionReason.belowMinimum,
      snapshotHeight: int.tryParse(minimumVotingEligibility.group(1) ?? ''),
    ).combinedMessage;
  }

  return message.isEmpty ? 'Voting session action failed.' : message;
}

String _normalizedVotingErrorText(String text) {
  var message = text.trim();
  for (final prefix in const [
    'Exception: ',
    'StateError: ',
    'Bad state: ',
    'VotingHotkeyUnavailable: ',
    'Invalid input: ',
  ]) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
      break;
    }
  }
  return message;
}

final _noSpendableNotesPattern = RegExp(
  r'no spendable voting notes at snapshot height (\d+)',
  caseSensitive: false,
);

final _minimumVotingEligibilityPattern = RegExp(
  r'minimum voting eligibility requires (?:(?:at least 5 eligible notes and )?12500000 zatoshi voting weight|at least one eligible voting bundle with 12500000 zatoshi voting weight); selected (?:(?:\d+ distinct eligible notes with )?\d+ zatoshi voting weight|\d+ distinct notes across eligible bundles with \d+ zatoshi eligible bundle weight|\d+ persisted bundles with \d+ zatoshi eligible bundle weight)(?: at snapshot height (\d+))?',
  caseSensitive: false,
);
