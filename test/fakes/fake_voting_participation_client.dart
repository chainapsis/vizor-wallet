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

  int localRefreshes = 0;
  int localWrites = 0;
  Completer<void>? localGate;
  Object? localError;
  void Function()? onLocalRefresh;
  Completer<void>? localWriteGate;
  final localContexts = <ApiVotingRoundContext>[];

  @override
  Future<void> refreshLocal(
    ApiVotingRoundContext context, {
    bool Function()? isCurrent,
  }) async {
    localRefreshes++;
    localContexts.add(context);
    await localGate?.future;
    if (isCurrent?.call() == false) return;
    if (localError case final error?) throw error;
    onLocalRefresh?.call();
    await localWriteGate?.future;
    localWrites++;
  }

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
