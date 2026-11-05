import 'dart:ui' show Locale;

import '../../core/l10n/l10n.dart';
import '../../services/voting/voting_rust_exception.dart';
import '../ledger/services/ledger_failure_guidance.dart';
import 'voting_formatters.dart';
import '../../rust/third_party/zcash_voting/wire.dart';

/// English strings for the voting providers, which keep display text in their
/// state and have no widget context to localize with.
final AppLocalizations votingProviderL10n = lookupAppLocalizations(
  const Locale('en'),
);

/// Default bundle weight the round requires when the SDK payload omits it.
const kMinimumVotingBundleWeightZatoshi = 12500000;

/// English copy kept for provider state, which has no localization context.
const kLedgerVotingCancelledMessage =
    'Ledger voting approval was cancelled.'; // l10n-ignore: stored by the submission provider

/// Every stable `ledger_*:` code Rust prefixes an error with, including ones
/// added after this file, so none of them can reach the screen.
final _ledgerCodePrefix = RegExp(r'ledger_[a-z0-9_]+:\s*');

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
            error,
            requestKind: LedgerRequestKind.voting,
          )?.message ??
          friendlyVotingErrorMessage(l10n, error),
  };
}

String friendlyVotingErrorMessage(AppLocalizations l10n, Object error) {
  final rustError = votingRustExceptionOf(error);
  if (rustError != null) return friendlyVotingRustError(l10n, rustError);
  return friendlyVotingErrorText(l10n, error.toString());
}

/// User-facing text for a typed bridge failure, keyed by its kind.
String friendlyVotingRustError(
  AppLocalizations l10n,
  VotingRustException error,
) {
  return switch (error.kind) {
    VotingErrorKindView.noSpendableNotes => l10n.votingErrorNoSpendableNotes(
      _snapshotText(l10n, error.snapshotHeight),
    ),
    VotingErrorKindView.insufficientEligibility =>
      minimumVotingEligibilityMessage(
        l10n,
        snapshotHeight: error.snapshotHeight?.toInt(),
        requiredWeightZatoshi: error.requiredWeightZatoshi,
      ),
    _ => friendlyVotingErrorText(l10n, error.message),
  };
}

/// The message shown when the account's eligible weight is below the round's
/// minimum bundle weight.
String minimumVotingEligibilityMessage(
  AppLocalizations l10n, {
  required int? snapshotHeight,
  BigInt? requiredWeightZatoshi,
}) {
  final required =
      requiredWeightZatoshi ?? BigInt.from(kMinimumVotingBundleWeightZatoshi);
  return l10n.votingErrorMinimumWeight(
    _formatZec(required),
    _snapshotText(
      l10n,
      snapshotHeight == null ? null : BigInt.from(snapshotHeight),
    ),
  );
}

String friendlyVotingErrorText(AppLocalizations l10n, String text) {
  final message = _normalizedVotingErrorText(text);
  return message.isEmpty ? l10n.votingErrorSessionFailed : message;
}

String _snapshotText(AppLocalizations l10n, BigInt? height) {
  return height == null
      ? l10n.votingSnapshotUnknown
      : l10n.votingSnapshotBlock(formatBlockHeight(height.toInt()));
}

String _formatZec(BigInt zatoshi) {
  final whole = zatoshi ~/ BigInt.from(100000000);
  final fraction = (zatoshi % BigInt.from(100000000))
      .toString()
      .padLeft(8, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty
      ? '$whole ZEC' // l10n-ignore: amount format
      : '$whole.$fraction ZEC'; // l10n-ignore: amount format
}

String _normalizedVotingErrorText(String text) {
  var message = text.replaceAll(_ledgerCodePrefix, '').trim();
  for (final prefix in const [
    'Exception: ', // l10n-ignore: matched error prefix
    'StateError: ', // l10n-ignore: matched error prefix
    'Bad state: ', // l10n-ignore: matched error prefix
    'VotingHotkeyUnavailable: ', // l10n-ignore: matched error prefix
    'Invalid input: ', // l10n-ignore: matched error prefix
  ]) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
      break;
    }
  }
  return message;
}
