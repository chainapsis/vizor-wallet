import 'dart:async';

import 'package:zcash_wallet/src/rust/api/voting.dart';
import 'package:zcash_wallet/src/services/voting/voting_participation_client.dart';

import '../services/voting/fake_voting_http.dart';

class FakeVotingParticipationClient extends VotingParticipationClient {
  FakeVotingParticipationClient()
    : super(FakeVotingHttpClient(), const VotingParticipationBridge());
  int calls = 0;
  Completer<void>? gate;
  VotingParticipationResult? result;

  @override
  Future<VotingParticipationResult> check(
    ApiVotingRoundContext context,
    DateTime Function() clock,
    bool Function() isCurrent,
  ) async {
    calls++;
    await gate?.future;
    if (!isCurrent() || result == null) throw StateError('Unavailable');
    return result!;
  }
}
