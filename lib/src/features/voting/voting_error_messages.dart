import '../../services/voting/voting_rust_exception.dart';
import 'voting_formatters.dart';
import '../../rust/third_party/zcash_voting/wire.dart';

/// Default bundle weight the round requires when the SDK payload omits it.
const kMinimumVotingBundleWeightZatoshi = 12500000;

String friendlyVotingErrorMessage(Object error) {
  final rustError = votingRustExceptionOf(error);
  if (rustError != null) return friendlyVotingRustError(rustError);
  return friendlyVotingErrorText(error.toString());
}

/// User-facing text for a typed bridge failure, keyed by its kind.
String friendlyVotingRustError(VotingRustException error) {
  return switch (error.kind) {
    VotingErrorKindView.noSpendableNotes =>
      'This account is not eligible for this voting round. It had no eligible '
          'shielded funds at ${_snapshotText(error.snapshotHeight)}. Switch to '
          'an eligible account to vote.',
    VotingErrorKindView.insufficientEligibility =>
      minimumVotingEligibilityMessage(
        snapshotHeight: error.snapshotHeight?.toInt(),
        requiredWeightZatoshi: error.requiredWeightZatoshi,
      ),
    _ => friendlyVotingErrorText(error.message),
  };
}

/// The message shown when the account's eligible weight is below the round's
/// minimum bundle weight.
String minimumVotingEligibilityMessage({
  required int? snapshotHeight,
  BigInt? requiredWeightZatoshi,
}) {
  final required =
      requiredWeightZatoshi ?? BigInt.from(kMinimumVotingBundleWeightZatoshi);
  return 'Voting requires at least one eligible shielded note bundle with '
      '${_formatZec(required)} '
      'at ${_snapshotText(snapshotHeight == null ? null : BigInt.from(snapshotHeight))}. '
      'Switch to an eligible account to vote.';
}

String friendlyVotingErrorText(String text) {
  final message = _normalizedVotingErrorText(text);
  return message.isEmpty ? 'Voting session action failed.' : message;
}

String _snapshotText(BigInt? height) {
  return height == null
      ? 'the voting round snapshot block'
      : 'snapshot block ${formatBlockHeight(height.toInt())}';
}

String _formatZec(BigInt zatoshi) {
  final whole = zatoshi ~/ BigInt.from(100000000);
  final fraction = (zatoshi % BigInt.from(100000000))
      .toString()
      .padLeft(8, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole ZEC' : '$whole.$fraction ZEC';
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
