import 'voting_formatters.dart';

String friendlyVotingErrorMessage(Object error) {
  return friendlyVotingErrorText(error.toString());
}

String friendlyVotingErrorText(String text) {
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

  final noSpendableNotes = RegExp(
    r'no spendable voting notes at snapshot height (\d+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (noSpendableNotes != null) {
    final heightText = noSpendableNotes.group(1);
    final snapshot = heightText == null
        ? 'the poll snapshot block'
        : 'snapshot block ${formatBlockHeight(int.parse(heightText))}';
    return 'This account is not eligible for this poll. It had no eligible '
        'shielded funds at $snapshot. Switch to an eligible account to vote.';
  }

  final minimumVotingEligibility = RegExp(
    r'minimum voting eligibility requires at least 5 eligible notes and 12500000 zatoshi voting weight; selected \d+ distinct eligible notes with \d+ zatoshi voting weight(?: at snapshot height (\d+))?',
    caseSensitive: false,
  ).firstMatch(message);
  if (minimumVotingEligibility != null) {
    final heightText = minimumVotingEligibility.group(1);
    final snapshot = heightText == null
        ? 'the poll snapshot block'
        : 'snapshot block ${formatBlockHeight(int.parse(heightText))}';
    return 'Voting requires at least 5 eligible shielded notes totaling '
        '0.125 ZEC at $snapshot. Switch to an eligible account to vote.';
  }

  return message.isEmpty ? 'Voting session action failed.' : message;
}
