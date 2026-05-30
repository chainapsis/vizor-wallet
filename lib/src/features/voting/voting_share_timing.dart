import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import '../../providers/voting/voting_state.dart';

/// UI-side last-moment adaptation before calling Rust share planning.
abstract final class VotingShareTimingPolicy {
  static List<rust_voting.DraftVote> applyLastMomentMode(
    List<rust_voting.DraftVote> draftVotes,
    VotingRoundDetails round, {
    DateTime? now,
  }) {
    if (!round.isLastMoment(now)) return draftVotes;
    return [
      for (final draft in draftVotes)
        rust_voting.DraftVote(
          proposalId: draft.proposalId,
          choice: draft.choice,
          numOptions: draft.numOptions,
          vcTreePosition: draft.vcTreePosition,
          singleShare: true,
        ),
    ];
  }
}
