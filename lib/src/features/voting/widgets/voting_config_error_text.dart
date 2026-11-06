import '../../../core/l10n/l10n.dart';
import '../../../providers/voting/voting_config_source_provider.dart';
import '../../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../../services/voting/voting_config_loader.dart';
import '../../../services/voting/voting_models.dart';
import '../../../services/voting/voting_rust_exception.dart';

/// Copy for a refused static config source URL.
String staticVotingConfigSourceProblemText(
  AppLocalizations l10n,
  StaticVotingConfigSourceProblem problem,
) => switch (problem) {
  StaticVotingConfigSourceProblem.notHttps => l10n.votingConfigUrlNotHttps,
  StaticVotingConfigSourceProblem.userInfo => l10n.votingConfigUrlHasUserInfo,
  StaticVotingConfigSourceProblem.fragment => l10n.votingConfigUrlHasFragment,
  StaticVotingConfigSourceProblem.encodedChecksumKey =>
    l10n.votingConfigChecksumKeyEncoded,
  StaticVotingConfigSourceProblem.repeatedChecksum =>
    l10n.votingConfigChecksumRepeated,
  StaticVotingConfigSourceProblem.missingChecksum =>
    l10n.votingConfigChecksumRequired,
  StaticVotingConfigSourceProblem.checksumPrefix =>
    l10n.votingConfigChecksumPrefix,
  StaticVotingConfigSourceProblem.checksumFormat =>
    l10n.votingConfigChecksumFormat,
};

/// What the voting config settings show when adding, choosing or deleting a
/// source fails. [fallback] covers failures with no copy of their own.
String votingConfigSourceErrorText(
  AppLocalizations l10n,
  Object error, {
  required String fallback,
}) {
  if (error is StaticVotingConfigSourceMalformed) {
    return staticVotingConfigSourceProblemText(l10n, error.problem);
  }
  if (error is DuplicateVotingConfigSource) return l10n.votingConfigDuplicate;
  if (error is VotingHttpException) return l10n.votingConfigLoadFailed;
  // The SDK refused what the source served (a pin, signature or version);
  // its English says which.
  if (error is rust_wire.VotingErrorView || error is VotingRustException) {
    return l10n.commonErrorWithDetails(
      l10n.votingConfigLoadFailed,
      describeVotingConfigMirrorError(error),
    );
  }
  return fallback;
}
