// Wire shapes the scripted voting fakes still produce.
//
// The SDK round session keeps signed vote commitments inside the crate, so
// the bridge no longer exposes these views. Test files import this barrel as
// `rust_wire` so the production wire types stay reachable under the same
// prefix.

export 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart';

class SignedVoteCommitmentView {
  final int proposalId;
  final VoteCommitmentWire wire;

  const SignedVoteCommitmentView({
    required this.proposalId,
    required this.wire,
  });

  @override
  int get hashCode => proposalId.hashCode ^ wire.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignedVoteCommitmentView &&
          runtimeType == other.runtimeType &&
          proposalId == other.proposalId &&
          wire == other.wire;
}

class VoteCommitmentWire {
  final String vanNullifier;
  final String voteAuthorityNoteNew;
  final String voteCommitment;
  final int proposalId;
  final String proof;
  final String voteRoundId;
  final int anchorHeight;
  final String rVpk;
  final String voteAuthSig;

  const VoteCommitmentWire({
    required this.vanNullifier,
    required this.voteAuthorityNoteNew,
    required this.voteCommitment,
    required this.proposalId,
    required this.proof,
    required this.voteRoundId,
    required this.anchorHeight,
    required this.rVpk,
    required this.voteAuthSig,
  });

  @override
  int get hashCode =>
      vanNullifier.hashCode ^
      voteAuthorityNoteNew.hashCode ^
      voteCommitment.hashCode ^
      proposalId.hashCode ^
      proof.hashCode ^
      voteRoundId.hashCode ^
      anchorHeight.hashCode ^
      rVpk.hashCode ^
      voteAuthSig.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoteCommitmentWire &&
          runtimeType == other.runtimeType &&
          vanNullifier == other.vanNullifier &&
          voteAuthorityNoteNew == other.voteAuthorityNoteNew &&
          voteCommitment == other.voteCommitment &&
          proposalId == other.proposalId &&
          proof == other.proof &&
          voteRoundId == other.voteRoundId &&
          anchorHeight == other.anchorHeight &&
          rVpk == other.rVpk &&
          voteAuthSig == other.voteAuthSig;
}
