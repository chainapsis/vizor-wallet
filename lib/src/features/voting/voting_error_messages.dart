import '../../../l10n/app_localizations.dart';
import 'voting_formatters.dart';

String friendlyVotingErrorMessage(Object error, AppLocalizations l10n) {
  return friendlyVotingErrorText(error.toString(), l10n);
}

bool isVotingEligibilityErrorText(String text) {
  final message = _normalizedVotingErrorText(text);
  final lowerMessage = message.toLowerCase();
  return _noSpendableNotesPattern.firstMatch(message) != null ||
      _minimumVotingEligibilityPattern.firstMatch(message) != null ||
      lowerMessage.startsWith('this account is not eligible for this ') ||
      _matchesLocalizedEligibilityMessage(lowerMessage) ||
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

String friendlyVotingErrorText(String text, AppLocalizations l10n) {
  final message = _normalizedVotingErrorText(text);
  final noSpendableNotes = _noSpendableNotesPattern.firstMatch(message);
  if (noSpendableNotes != null) {
    return l10n.votingNotEligibleNoFunds(
      _snapshotLabel(l10n, noSpendableNotes.group(1)),
    );
  }

  final minimumVotingEligibility = _minimumVotingEligibilityPattern.firstMatch(
    message,
  );
  if (minimumVotingEligibility != null) {
    return l10n.votingRequiresMinimumBundle(
      _snapshotLabel(l10n, minimumVotingEligibility.group(1)),
    );
  }

  return message.isEmpty ? l10n.votingSessionActionFailed : message;
}

String _snapshotLabel(AppLocalizations l10n, String? heightText) {
  return heightText == null
      ? l10n.votingSnapshotBlockFallback
      : l10n.votingSnapshotBlock(formatBlockHeight(int.parse(heightText)));
}

/// Friendly eligibility messages are localized, and screens re-check stored
/// message text; recognize the message prefix in every supported locale.
bool _matchesLocalizedEligibilityMessage(String lowerMessage) {
  const sentinel = '\u0000';
  for (final locale in AppLocalizations.supportedLocales) {
    final l10n = lookupAppLocalizations(locale);
    for (final template in [
      l10n.votingNotEligibleNoFunds(sentinel),
      l10n.votingRequiresMinimumBundle(sentinel),
    ]) {
      final prefix = template.split(sentinel).first.trim().toLowerCase();
      if (prefix.isNotEmpty && lowerMessage.startsWith(prefix)) {
        return true;
      }
    }
  }
  return false;
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
