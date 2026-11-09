import '../../core/l10n/l10n.dart';
import '../../core/l10n/untranslated_text_log.dart';
import '../ledger/services/ledger_failure_guidance.dart';
import 'voting_message.dart';

/// Copy for a failed Ledger vote approval, chosen by failure kind so codes
/// such as `ledger_status_6985:` never reach the screen.
String ledgerVotingErrorMessage(
  AppLocalizations l10n,
  Object error, {
  required String appInstruction,
}) {
  return switch (LedgerRequestFailure.fromError(error)) {
    LedgerRequestFailure.declined => l10n.votingErrorLedgerRejected,
    LedgerRequestFailure.cancelled => l10n.votingErrorLedgerCancelled,
    LedgerRequestFailure.deviceLocked => l10n.votingErrorLedgerLocked(
      appInstruction,
    ),
    LedgerRequestFailure.wrongApp => l10n.votingErrorLedgerWrongApp(
      appInstruction,
    ),
    _ =>
      ledgerFailureGuidance(
            l10n,
            error,
            requestKind: LedgerRequestKind.voting,
          )?.message ??
          friendlyVotingErrorMessage(l10n, error),
  };
}

String friendlyVotingErrorMessage(AppLocalizations l10n, Object error) =>
    votingMessageForError(error).text(l10n);

/// The untranslated text behind [error], for a "Show details" button.
String? friendlyVotingErrorDetails(Object error) =>
    votingMessageDetails(votingMessageForError(error));

/// Copy for a voting screen that failed to load: the error's own copy, or a
/// retry hint where the error is untranslated text with no copy of its own.
String friendlyVotingLoadErrorMessage(AppLocalizations l10n, Object error) {
  final details = friendlyVotingErrorDetails(error);
  if (details == null) return friendlyVotingErrorMessage(l10n, error);
  logUntranslatedText(details);
  return l10n.votingLoadFailedRetry;
}

String friendlyVotingErrorText(AppLocalizations l10n, String text) =>
    votingTextMessage(text).text(l10n);
