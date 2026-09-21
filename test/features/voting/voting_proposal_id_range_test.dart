import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';

/// The Dart bounds mirror the SDK's `MIN_PROPOSAL_ID` / `MAX_PROPOSAL_ID`.
///
/// Unit tests fake the Rust API rather than loading the native library, so
/// they cannot read the SDK's constants directly. The mirror is pinned on both
/// sides instead: `voting_proposal_id_range_matches_the_sdk` in
/// `rust/src/api/voting.rs` pins the SDK half against these same literals and
/// fails the build if the SDK moves.
Map<String, dynamic> _round(List<int> proposalIds) => {
  'proposals': [
    for (final id in proposalIds)
      {'id': id, 'title': 'Question $id', 'options': <dynamic>[]},
  ],
};

void main() {
  test('the mirrored bounds are the values the SDK enforces', () {
    expect(kMinProposalId, 1);
    expect(kMaxProposalId, 50);
  });

  test('a proposal at either bound parses', () {
    final parsed = proposalsFromJson(_round([kMinProposalId, kMaxProposalId]));
    expect(parsed.map((proposal) => proposal.id), [
      kMinProposalId,
      kMaxProposalId,
    ]);
  });

  test('a proposal outside the bounds is refused with its id named', () {
    for (final id in [kMinProposalId - 1, kMaxProposalId + 1]) {
      expect(
        () => proposalsFromJson(_round([id])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('got $id'),
          ),
        ),
      );
    }
  });

  /// The regression: this parser held a maximum of 15 while the SDK allowed
  /// 50, so a 37-question round died at proposal 16 with a `FormatException`
  /// no voter could act on.
  test('a 37-question round parses end to end', () {
    final ids = [for (var id = 1; id <= 37; id++) id];
    final parsed = proposalsFromJson(_round(ids));
    expect(parsed.map((proposal) => proposal.id), ids);
  });
}
