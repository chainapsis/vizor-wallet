import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/proxy/proxy_delegation_models.dart';

import '../../features/voting/proxy/proxy_delegator_client.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import 'voting_config_provider.dart';
import 'voting_participation_provider.dart';
import 'voting_service_providers.dart';
import 'voting_session_provider.dart';

/// [ProxyDelegatorHost] over [key]'s submission session: the voting
/// session pinned to one round and account, whichever account is active.
class SessionProxyDelegatorHost implements ProxyDelegatorHost {
  /// Creates the host.
  SessionProxyDelegatorHost(
    this._ref, {
    required this.key,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _clock;

  /// The round and account the calls read.
  final VotingSessionKey key;

  /// Keeps the session loaded from the first call for as long as the
  /// host's provider lives.
  ProviderSubscription<Object?>? _held;

  /// The session notifier the calls read.
  VotingSessionNotifier _session(String roundId) {
    assert(key.roundId == roundId, 'a pinned host serves its own round');
    final session = votingSubmissionSessionProvider(key);
    _held ??= _ref.listen(session, (_, _) {});
    return _ref.read(session.notifier);
  }

  @override
  Future<ProxyDelegatorRound> round(String roundId) async {
    final access = await _session(roundId).proxyRoundAccess();
    final context = access.apiContext;
    return ProxyDelegatorRound(
      account: ProxyDelegatorAccount(
        dbPath: context.dbPath,
        accountUuid: context.accountUuid,
      ),
      title: access.round.title,
      proposals: proposalsFromRound(access.round),
      status: access.round.status,
      ceremonyStart: access.round.ceremonyStart,
      voteEnd: access.round.voteEndTime,
    );
  }

  /// The session's eligible weight in whole ballots, as the vote flow
  /// reports it; zero when the account holds none.
  @override
  Future<BigInt> eligibleBallots(String roundId) async {
    final weight = await _session(roundId).refreshEligibleWeight();
    return (weight ?? BigInt.zero) ~/ kProxyZatoshiPerBallot;
  }

  /// The participation reader's check of the account's notes: any proven or
  /// locally confirmed use is spent; a check that could not finish, or
  /// failed, is unavailable.
  @override
  Future<ApiGovNullifierProof> govNullifiers(String roundId) async {
    try {
      final access = await _session(roundId).proxyRoundAccess();
      final result = await _ref
          .read(votingParticipationClientProvider)
          .check(access.apiContext, _clock, () => _ref.mounted);
      if (result.usedCount > 0) return ApiGovNullifierProof.spent;
      return result.complete
          ? ApiGovNullifierProof.unspent
          : ApiGovNullifierProof.unavailable;
    } catch (_) {
      // The reader's errors may name queried keys; never log them.
      return ApiGovNullifierProof.unavailable;
    }
  }

  @override
  Future<void> ensureBundles(String roundId) =>
      _session(roundId).ensureProxyBundleSetup();

  @override
  Future<ProxyDelegatorChain> chain() async {
    final config = await _ref.read(votingConfigProvider.future);
    return VotingApiProxyDelegatorChain(
      _ref.read(votingApiClientProvider(config.apiServers)),
    );
  }
}
