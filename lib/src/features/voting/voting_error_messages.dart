import '../../core/l10n/l10n.dart';
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

String friendlyVotingErrorText(AppLocalizations l10n, String text) =>
    votingTextMessage(text).text(l10n);
