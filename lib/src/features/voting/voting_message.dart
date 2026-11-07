import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../../core/formatting/duration_format.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/untranslated_text_log.dart';
import '../../providers/account_models.dart';
import '../../rust/third_party/zcash_voting/wire.dart';
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_rust_exception.dart';
import '../ledger/widgets/ledger_device_app_prompt.dart';
import 'voting_error_messages.dart';
import 'voting_formatters.dart';

/// Default bundle weight the round requires when the SDK payload omits it.
const kMinimumVotingBundleWeightZatoshi = 12500000;

/// Fixed voting copy that providers keep in state.
enum VotingNoticeKind {
  sessionFailed,
  statusGeneric,
  votingPowerUnavailable,
  noActiveAccount,
  noVoteChosen,
  roundDetailsUnavailable,
  roundEndTimeUnavailable,
  softwareAccountRequired,
  softwareMnemonicRequired,
  immediateShareExpired,
  submissionInProgress,
  hotkeyMissing,
  pirEndpointUnresolved,
  pirEndpointResolveFailed,
  keystoneHardwareOnly,
  keystoneAccountOnly,
  keystoneNoSigningRequest,
  keystoneNoSignatures,
  keystoneSignatureMismatch,
  keystoneInvalidSignature,
  keystoneSignatureConflict,
  keystoneSignatureSaveFailed,
  keystoneResultMismatch,
  keystoneSkipNeedsSignature,
  ledgerCancelled,
  ledgerNoPendingBundle,
  ledgerSignatureMismatch,
  ledgerSignatureConflict,
  ledgerSignatureSaveFailed,
  chainRejected,
  chainSubmittedWithoutHash,
  chainNoUsableTransaction,
  chainRecoveryPending,
  chainCancelled,
}

/// A message voting state keeps. It records what happened; [text] builds the
/// copy in the display language.
sealed class VotingMessage {
  const VotingMessage();

  String text(AppLocalizations l10n);
}

/// Implemented by exceptions whose screen text is app copy rather than their
/// `toString()`, which stays English for logs.
abstract interface class VotingMessageSource {
  VotingMessage get votingMessage;
}

/// Carries a [VotingMessage] through code that reports failures by throwing;
/// screens show the message.
class VotingMessageException implements Exception, VotingMessageSource {
  const VotingMessageException(this.votingMessage);

  @override
  final VotingMessage votingMessage;

  @override
  String toString() => 'VotingMessageException($votingMessage)';
}

final class VotingNotice extends VotingMessage {
  const VotingNotice(this.kind);

  final VotingNoticeKind kind;

  @override
  String text(AppLocalizations l10n) => switch (kind) {
    VotingNoticeKind.sessionFailed => l10n.votingErrorSessionFailed,
    VotingNoticeKind.statusGeneric => l10n.votingStatusGenericError,
    VotingNoticeKind.votingPowerUnavailable =>
      l10n.votingPowerUnavailableSentence,
    VotingNoticeKind.noActiveAccount => l10n.votingErrorNoActiveAccount,
    VotingNoticeKind.noVoteChosen => l10n.votingErrorNoVoteChosen,
    VotingNoticeKind.roundDetailsUnavailable =>
      l10n.votingErrorRoundDetailsUnavailable,
    VotingNoticeKind.roundEndTimeUnavailable =>
      l10n.votingErrorRoundEndTimeUnavailable,
    VotingNoticeKind.softwareAccountRequired => l10n.votingSoftwareRequiredBody,
    VotingNoticeKind.softwareMnemonicRequired =>
      l10n.votingErrorSoftwareMnemonicRequired,
    VotingNoticeKind.immediateShareExpired =>
      l10n.votingErrorImmediateShareExpired,
    VotingNoticeKind.submissionInProgress => l10n.votingSubmissionInProgress,
    VotingNoticeKind.hotkeyMissing => l10n.votingErrorHotkeyMissing,
    VotingNoticeKind.pirEndpointUnresolved =>
      l10n.votingErrorPirEndpointUnresolved,
    VotingNoticeKind.pirEndpointResolveFailed =>
      l10n.votingErrorPirEndpointResolveFailed,
    VotingNoticeKind.keystoneHardwareOnly =>
      l10n.votingErrorKeystoneHardwareOnly,
    VotingNoticeKind.keystoneAccountOnly => l10n.votingErrorKeystoneAccountOnly,
    VotingNoticeKind.keystoneNoSigningRequest =>
      l10n.votingErrorKeystoneNoSigningRequest,
    VotingNoticeKind.keystoneNoSignatures =>
      l10n.votingErrorKeystoneNoSignatures,
    VotingNoticeKind.keystoneSignatureMismatch =>
      l10n.votingErrorKeystoneSignatureMismatch,
    VotingNoticeKind.keystoneInvalidSignature =>
      l10n.votingErrorKeystoneInvalidSignature,
    VotingNoticeKind.keystoneSignatureConflict =>
      l10n.votingErrorKeystoneSignatureConflict,
    VotingNoticeKind.keystoneSignatureSaveFailed =>
      l10n.votingErrorKeystoneSignatureSaveFailed,
    VotingNoticeKind.keystoneResultMismatch =>
      l10n.votingErrorKeystoneResultMismatch,
    VotingNoticeKind.keystoneSkipNeedsSignature =>
      l10n.votingErrorKeystoneSkipNeedsSignature,
    VotingNoticeKind.ledgerCancelled => l10n.votingErrorLedgerCancelled,
    VotingNoticeKind.ledgerNoPendingBundle =>
      l10n.votingErrorLedgerNoPendingBundle,
    VotingNoticeKind.ledgerSignatureMismatch =>
      l10n.votingErrorLedgerSignatureMismatch,
    VotingNoticeKind.ledgerSignatureConflict =>
      l10n.votingErrorLedgerSignatureConflict,
    VotingNoticeKind.ledgerSignatureSaveFailed =>
      l10n.votingErrorLedgerSignatureSaveFailed,
    VotingNoticeKind.chainRejected => l10n.votingErrorChainRejected,
    VotingNoticeKind.chainSubmittedWithoutHash =>
      l10n.votingErrorChainSubmittedWithoutHash,
    VotingNoticeKind.chainNoUsableTransaction =>
      l10n.votingErrorChainNoUsableTransaction,
    VotingNoticeKind.chainRecoveryPending =>
      l10n.votingErrorChainRecoveryPending,
    VotingNoticeKind.chainCancelled => l10n.votingErrorChainCancelled,
  };

  @override
  bool operator ==(Object other) => other is VotingNotice && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'VotingNotice(${kind.name})';
}

enum VotingSignerNoticeKind {
  /// Delegation bundles still need the device's signatures.
  signBundles,

  /// One delegation bundle still needs the device's signature.
  signBundle,

  /// The account is not the hardware signer this action needs.
  matchingAccountOnly,
}

/// Copy that names a hardware signer, and a bundle for [signBundle].
final class VotingSignerNotice extends VotingMessage {
  const VotingSignerNotice(this.kind, this.signer, {this.bundleNumber});

  final VotingSignerNoticeKind kind;
  final HardwareSignerKind signer;

  /// One-based bundle number for [VotingSignerNoticeKind.signBundle].
  final int? bundleNumber;

  @override
  String text(AppLocalizations l10n) {
    final name = votingHardwareSignerName(signer);
    return switch (kind) {
      VotingSignerNoticeKind.signBundles => l10n.votingErrorSignBundlesFirst(
        name,
      ),
      VotingSignerNoticeKind.signBundle => l10n.votingErrorSignBundleFirst(
        bundleNumber ?? 1,
        name,
      ),
      VotingSignerNoticeKind.matchingAccountOnly =>
        l10n.votingErrorSignerAccountOnly(name),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is VotingSignerNotice &&
      other.kind == kind &&
      other.signer == signer &&
      other.bundleNumber == bundleNumber;

  @override
  int get hashCode => Object.hash(kind, signer, bundleNumber);

  @override
  String toString() =>
      'VotingSignerNotice(${kind.name}, ${signer.name}, $bundleNumber)';
}

String votingHardwareSignerName(HardwareSignerKind signer) =>
    signer == HardwareSignerKind.ledger
    ? 'Ledger' // l10n-ignore: product name
    : 'Keystone'; // l10n-ignore: product name

enum VotingEligibilityFailureKind { noSpendableNotes, minimumWeight }

/// The account cannot vote in the round. Both messages end with
/// `votingSwitchEligibleGuidance`; [reasonText] is the part before it.
final class VotingEligibilityFailure extends VotingMessage {
  const VotingEligibilityFailure(
    this.kind, {
    this.snapshotHeight,
    this.requiredWeightZatoshi,
  });

  final VotingEligibilityFailureKind kind;
  final int? snapshotHeight;

  /// The round's minimum bundle weight for
  /// [VotingEligibilityFailureKind.minimumWeight]; null uses the default.
  final BigInt? requiredWeightZatoshi;

  @override
  String text(AppLocalizations l10n) => switch (kind) {
    VotingEligibilityFailureKind.noSpendableNotes =>
      l10n.votingErrorNoSpendableNotes(_snapshotText(l10n)),
    VotingEligibilityFailureKind.minimumWeight => l10n.votingErrorMinimumWeight(
      _requiredWeight,
      _snapshotText(l10n),
    ),
  };

  /// The reason without the closing switch-account guidance or its period.
  String reasonText(AppLocalizations l10n) => switch (kind) {
    VotingEligibilityFailureKind.noSpendableNotes =>
      l10n.votingErrorNoSpendableNotesReason(_snapshotText(l10n)),
    VotingEligibilityFailureKind.minimumWeight =>
      l10n.votingErrorMinimumWeightReason(_requiredWeight, _snapshotText(l10n)),
  };

  String get _requiredWeight => _formatZec(
    requiredWeightZatoshi ?? BigInt.from(kMinimumVotingBundleWeightZatoshi),
  );

  String _snapshotText(AppLocalizations l10n) => snapshotHeight == null
      ? l10n.votingSnapshotUnknown
      : l10n.votingSnapshotBlock(formatBlockHeight(snapshotHeight!));

  @override
  bool operator ==(Object other) =>
      other is VotingEligibilityFailure &&
      other.kind == kind &&
      other.snapshotHeight == snapshotHeight &&
      other.requiredWeightZatoshi == requiredWeightZatoshi;

  @override
  int get hashCode => Object.hash(kind, snapshotHeight, requiredWeightZatoshi);

  @override
  String toString() => 'VotingEligibilityFailure(${kind.name})';
}

/// Wallet sync did not reach the round snapshot in time.
final class VotingWalletSyncTimeout extends VotingMessage {
  const VotingWalletSyncTimeout({
    required this.maxWait,
    required this.scannedHeight,
    required this.snapshotHeight,
  });

  final Duration maxWait;
  final int scannedHeight;
  final int snapshotHeight;

  @override
  String text(AppLocalizations l10n) => l10n.votingErrorWalletSyncTimeout(
    formatElapsedSeconds(maxWait),
    formatBlockHeight(scannedHeight),
    formatBlockHeight(snapshotHeight),
  );

  @override
  bool operator ==(Object other) =>
      other is VotingWalletSyncTimeout &&
      other.maxWait == maxWait &&
      other.scannedHeight == scannedHeight &&
      other.snapshotHeight == snapshotHeight;

  @override
  int get hashCode => Object.hash(maxWait, scannedHeight, snapshotHeight);

  @override
  String toString() =>
      'VotingWalletSyncTimeout($maxWait, $scannedHeight, $snapshotHeight)';
}

/// No PIR endpoint served the round's snapshot; worded with the diagnostics.
final class VotingPirMismatch extends VotingMessage {
  const VotingPirMismatch({
    required this.expectedSnapshotHeight,
    required this.diagnostics,
  });

  final int expectedSnapshotHeight;
  final List<PirSnapshotEndpointDiagnostic> diagnostics;

  @override
  String text(AppLocalizations l10n) => pirSnapshotMismatchMessage(
    l10n,
    expectedSnapshotHeight: expectedSnapshotHeight,
    diagnostics: diagnostics,
    includeDiagnostics: true,
  );

  @override
  bool operator ==(Object other) =>
      other is VotingPirMismatch &&
      other.expectedSnapshotHeight == expectedSnapshotHeight &&
      listEquals(other.diagnostics, diagnostics);

  @override
  int get hashCode =>
      Object.hash(expectedSnapshotHeight, Object.hashAll(diagnostics));

  @override
  String toString() => 'VotingPirMismatch($expectedSnapshotHeight)';
}

/// One bundle whose delegation ended without confirming.
@immutable
class VotingTerminalBundle {
  const VotingTerminalBundle({required this.bundleNumber, this.diagnostic});

  /// One-based bundle number.
  final int bundleNumber;

  /// The SDK's account of what happened, shown as it is.
  final String? diagnostic;

  @override
  bool operator ==(Object other) =>
      other is VotingTerminalBundle &&
      other.bundleNumber == bundleNumber &&
      other.diagnostic == diagnostic;

  @override
  int get hashCode => Object.hash(bundleNumber, diagnostic);
}

/// Every bundle whose delegation ended without confirming. A hashless
/// dispatch may already be on the chain, so the copy does not invite a retry.
final class VotingTerminalDelegation extends VotingMessage {
  const VotingTerminalDelegation(this.bundles);

  final List<VotingTerminalBundle> bundles;

  @override
  String text(AppLocalizations l10n) {
    final reasons = [
      for (final bundle in bundles)
        l10n.votingTerminalBundle(
          bundle.bundleNumber,
          bundle.diagnostic ?? l10n.votingTerminalReasonDefault,
        ),
    ];
    return reasons.length == 1
        ? l10n.votingTerminalSingle(reasons.single)
        : l10n.votingTerminalMultiple(reasons.join(', '));
  }

  @override
  bool operator ==(Object other) =>
      other is VotingTerminalDelegation && listEquals(other.bundles, bundles);

  @override
  int get hashCode => Object.hashAll(bundles);

  @override
  String toString() =>
      'VotingTerminalDelegation(${bundles.map((b) => b.bundleNumber)})';
}

enum VotingBatchFailureKind { voteCasting, delegation }

/// Several bundle failures from one round run. [details] lists them in SDK
/// text and is shown as it is.
final class VotingBatchFailure extends VotingMessage {
  const VotingBatchFailure(this.kind, this.details);

  final VotingBatchFailureKind kind;
  final String details;

  @override
  String text(AppLocalizations l10n) {
    final details = _normalizedVotingErrorText(this.details);
    return switch (kind) {
      VotingBatchFailureKind.voteCasting => l10n.votingErrorVoteCastingFailed(
        details,
      ),
      VotingBatchFailureKind.delegation => l10n.votingErrorDelegationFailed(
        details,
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is VotingBatchFailure &&
      other.kind == kind &&
      other.details == details;

  @override
  int get hashCode => Object.hash(kind, details);

  @override
  String toString() => 'VotingBatchFailure(${kind.name}, $details)';
}

/// The Keystone voting QR could not be prepared, with the reason.
final class VotingKeystoneQrFailure extends VotingMessage {
  const VotingKeystoneQrFailure(this.reason);

  final VotingMessage reason;

  @override
  String text(AppLocalizations l10n) {
    final reason = this.reason;
    return l10n.votingErrorKeystoneQrPrepareFailed(
      reason is VotingLiteralMessage ? reason.value : reason.text(l10n),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VotingKeystoneQrFailure && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'VotingKeystoneQrFailure($reason)';
}

/// A failed Ledger vote approval, worded by failure kind at display time.
final class VotingLedgerFailure extends VotingMessage {
  const VotingLedgerFailure(this.error, {required this.networkName});

  final Object error;

  /// Names the Zcash app the device must open.
  final String networkName;

  @override
  String text(AppLocalizations l10n) => ledgerVotingErrorMessage(
    l10n,
    error,
    appInstruction: ledgerZcashAppOpenErrorInstruction(l10n, networkName),
  );

  @override
  bool operator ==(Object other) =>
      other is VotingLedgerFailure &&
      identical(other.error, error) &&
      other.networkName == networkName;

  @override
  int get hashCode => Object.hash(identityHashCode(error), networkName);

  @override
  String toString() => 'VotingLedgerFailure($error)';
}

/// Voting power the privacy trim withholds from the round.
final class VotingPrivacyTrimNotice extends VotingMessage {
  const VotingPrivacyTrimNotice(this.droppedValueZatoshi);

  final BigInt droppedValueZatoshi;

  @override
  String text(AppLocalizations l10n) =>
      l10n.votingPrivacyTrimNotice(formatVotingPower(droppedValueZatoshi));

  @override
  bool operator ==(Object other) =>
      other is VotingPrivacyTrimNotice &&
      other.droppedValueZatoshi == droppedValueZatoshi;

  @override
  int get hashCode => droppedValueZatoshi.hashCode;

  @override
  String toString() => 'VotingPrivacyTrimNotice($droppedValueZatoshi)';
}

/// Rust and SDK error text no code describes. Screens show the [summary]
/// copy and log the untranslated [value].
final class VotingLiteralMessage extends VotingMessage {
  const VotingLiteralMessage(
    this.value, {
    this.summary = VotingNoticeKind.sessionFailed,
  });

  final String value;
  final VotingNoticeKind summary;

  @override
  String text(AppLocalizations l10n) {
    logUntranslatedText(value);
    return VotingNotice(summary).text(l10n);
  }

  @override
  bool operator ==(Object other) =>
      other is VotingLiteralMessage &&
      other.value == value &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(value, summary);

  @override
  String toString() => 'VotingLiteralMessage($value)';
}

/// The message for a caught error: a typed bridge failure by kind, an app
/// exception by its own code, anything else by its cleaned-up text.
VotingMessage votingMessageForError(Object error) {
  final rustError = votingRustExceptionOf(error);
  if (rustError != null) return votingMessageForRustError(rustError);
  if (error is VotingMessageSource) {
    return normalizedVotingMessage(error.votingMessage);
  }
  return votingTextMessage(error.toString());
}

/// The message for a typed bridge failure, keyed by its kind.
VotingMessage votingMessageForRustError(VotingRustException error) {
  return switch (error.kind) {
    VotingErrorKindView.noSpendableNotes => VotingEligibilityFailure(
      VotingEligibilityFailureKind.noSpendableNotes,
      snapshotHeight: error.snapshotHeight?.toInt(),
    ),
    VotingErrorKindView.insufficientEligibility => VotingEligibilityFailure(
      VotingEligibilityFailureKind.minimumWeight,
      snapshotHeight: error.snapshotHeight?.toInt(),
      requiredWeightZatoshi: error.requiredWeightZatoshi,
    ),
    _ => votingTextMessage(error.message),
  };
}

/// Error text with Ledger status codes and exception prefixes removed; empty
/// text becomes the generic session failure.
VotingMessage votingTextMessage(String text) {
  final message = _normalizedVotingErrorText(text);
  return message.isEmpty
      ? const VotingNotice(VotingNoticeKind.sessionFailed)
      : VotingLiteralMessage(message);
}

/// Cleans up a literal [message] the way [votingTextMessage] does; app copy
/// passes through unchanged.
VotingMessage normalizedVotingMessage(VotingMessage message) =>
    message is VotingLiteralMessage
    ? _withSummary(votingTextMessage(message.value), message.summary)
    : message;

/// The untranslated text behind [message], for a "Show details" button, or
/// null when the message is the app's own copy.
String? votingMessageDetails(VotingMessage? message) {
  final normalized = message == null ? null : normalizedVotingMessage(message);
  return normalized is VotingLiteralMessage ? normalized.value : null;
}

VotingMessage _withSummary(VotingMessage message, VotingNoticeKind summary) =>
    message is VotingLiteralMessage
    ? VotingLiteralMessage(message.value, summary: summary)
    : message;

/// Every stable `ledger_*:` code Rust prefixes an error with, including ones
/// added after this file, so none of them can reach the screen.
final _ledgerCodePrefix = RegExp(r'ledger_[a-z0-9_]+:\s*');

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
