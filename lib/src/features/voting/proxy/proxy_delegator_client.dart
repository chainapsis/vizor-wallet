import 'package:flutter/foundation.dart';

import '../../../rust/api/proxy_delegate.dart' as rust_delegate;
import '../../../rust/api/proxy_delegator.dart' as rust;
import '../../../services/voting/voting_api_client.dart';
import '../voting_flow_models.dart';
import 'delegate_ballot_pager.dart';
import 'proxy_delegation_repository.dart';

/// The vote chain reads the delegator calls take, as the bytes the chain
/// answered: zcash_voting parses and checks every one.
abstract interface class ProxyDelegatorChain {
  /// The body of `GET /protocol-capabilities`.
  Future<Uint8List> protocolCapabilities();

  /// The body of `GET /round/{roundId}`.
  Future<Uint8List> round(String roundId);

  /// The body of `GET /proxy-delegation-params`, or null on a 404.
  Future<Uint8List?> proxyDelegationParams();

  /// The page of the round's delegate ballot list after [startAfter].
  Future<Uint8List> delegateBallotsPage(String roundId, int startAfter);
}

/// [ProxyDelegatorChain] over the configured vote servers, with their
/// failover and read retries.
class VotingApiProxyDelegatorChain implements ProxyDelegatorChain {
  /// Creates the chain reader.
  const VotingApiProxyDelegatorChain(this.api);

  /// The vote server client.
  final VotingApiClient api;

  @override
  Future<Uint8List> protocolCapabilities() => api.getProtocolCapabilitiesBody();

  @override
  Future<Uint8List> round(String roundId) => api.getRoundBody(roundId);

  @override
  Future<Uint8List?> proxyDelegationParams() =>
      api.getProxyDelegationParamsBody();

  @override
  Future<Uint8List> delegateBallotsPage(String roundId, int startAfter) =>
      api.getDelegateBallotsPageBody(roundId, startAfter: startAfter);
}

/// The voting sidecar a delegator call reads: the wallet database beside it
/// and the account it is scoped to.
class ProxyDelegatorAccount {
  /// Creates the reference.
  const ProxyDelegatorAccount({
    required this.dbPath,
    required this.accountUuid,
  });

  /// The main wallet database path.
  final String dbPath;

  /// The account whose sidecar scope the call uses.
  final String accountUuid;
}

/// The round and account facts the delegator calls read, from the voting
/// session's authenticated round.
@immutable
class ProxyDelegatorRound {
  /// Creates the facts.
  const ProxyDelegatorRound({
    required this.account,
    required this.title,
    required this.proposals,
    required this.status,
    this.ceremonyStart,
    this.voteEnd,
  });

  /// The account's voting sidecar.
  final ProxyDelegatorAccount account;

  /// The round title.
  final String title;

  /// Proposals in id order.
  final List<VotingProposalView> proposals;

  /// The round status as the vote server reports it.
  final String status;

  /// The ceremony start as the vote server reports it, if known.
  final DateTime? ceremonyStart;

  /// The vote end as the vote server reports it, if known.
  final DateTime? voteEnd;
}

/// The app state the delegator client reads: the voting session for round
/// facts and voting power, the participation reader, bundle setup and the
/// vote chain.
abstract interface class ProxyDelegatorHost {
  /// The round and the active account.
  Future<ProxyDelegatorRound> round(String roundId);

  /// Voting power the account can allocate in the round, in ballots.
  Future<BigInt> eligibleBallots(String roundId);

  /// The participation reader's verdict on the account's governance
  /// nullifiers in the round.
  Future<rust.ApiGovNullifierProof> govNullifiers(String roundId);

  /// Persists the round's bundle plan when the account has none yet, so the
  /// planner has bundles to pack.
  Future<void> ensureBundles(String roundId);

  /// The vote chain reader for the current voting config.
  Future<ProxyDelegatorChain> chain();
}

/// zcash_voting's delegator calls (contracts-v1 §15.1) for the active
/// account: availability, preview, commit, status and progress, with the
/// chain reads and session facts each takes.
class ProxyDelegatorClient {
  /// Creates the client.
  ProxyDelegatorClient({
    required ProxyDelegatorHost host,
    DateTime Function()? clock,
    this.ballotListMaxAge = const Duration(seconds: 15),
  }) : _host = host,
       _clock = clock ?? DateTime.now {
    _ballots = DelegateBallotPager(
      maxAge: ballotListMaxAge,
      clock: _clock,
      nextStartAfter: (roundId, startAfter, page) async {
        try {
          final search = await rust_delegate.delegateBallotPage(
            roundId: roundId,
            startAfter: startAfter,
            page: page,
          );
          return search.nextStartAfter;
        } on rust_delegate.ApiDelegateModeError catch (error) {
          throw ProxyDelegationError(
            kind: ProxyDelegationErrorKind.other,
            detail: error.message,
          );
        }
      },
      tooManyPages: () => const ProxyDelegationError(
        kind: ProxyDelegationErrorKind.other,
        detail:
            'the delegate ballot list has too many pages', // l10n-ignore: error detail for logs
      ),
    );
  }

  final ProxyDelegatorHost _host;
  final DateTime Function() _clock;

  /// How long a fetched delegate ballot list serves status and progress
  /// reads before the next read fetches it again.
  final Duration ballotListMaxAge;

  late final DelegateBallotPager _ballots;

  /// The round's title, proposals, vote end and the account's voting power.
  ///
  /// Throws [ProxyDelegationError] when the vote server reports no vote
  /// end.
  Future<ProxyRoundContext> roundContext(String roundId) async {
    final round = await _host.round(roundId);
    final voteEnd = round.voteEnd;
    if (voteEnd == null) {
      throw const ProxyDelegationError(
        kind: ProxyDelegationErrorKind.other,
        detail: 'the round has no vote end',
      );
    }
    return ProxyRoundContext(
      roundId: roundId,
      title: round.title,
      proposals: round.proposals,
      voteEndTime: voteEnd,
      eligibleBallots: await _host.eligibleBallots(roundId),
    );
  }

  /// The first availability result that applies (contracts-v1 §11.4),
  /// decided by zcash_voting from the chain's answers fetched in the order
  /// it reads them: protocol capabilities, the round, then the proxy params.
  ///
  /// The participation reader runs only when zcash_voting needs its proof:
  /// the first evaluation says the proof is unavailable, which zcash_voting
  /// reads only after every earlier gate passed and no local cast settled
  /// it.
  Future<ApiProxyAvailability> availability(String roundId) async {
    final chain = await _host.chain();
    final answers = rust.ApiProxyChainAnswers(
      protocolCapabilities: await chain.protocolCapabilities(),
      voteRound: await chain.round(roundId),
      proxyDelegationParams: await chain.proxyDelegationParams(),
    );
    final round = await _host.round(roundId);
    Future<rust.ApiProxyAvailability> evaluate(
      rust.ApiGovNullifierProof proof,
    ) => rust.proxyDelegationAvailability(
      dbPath: round.account.dbPath,
      accountUuid: round.account.accountUuid,
      roundId: roundId,
      chain: answers,
      govNullifiers: proof,
      timing: _timing(round),
    );
    try {
      return await evaluate(rust.ApiGovNullifierProof.unavailable);
    } on ProxyDelegationError catch (error) {
      if (error.kind != ProxyDelegationErrorKind.cannotVerify) rethrow;
    }
    final proof = await _host.govNullifiers(roundId);
    if (proof == rust.ApiGovNullifierProof.unavailable) {
      throw const ProxyDelegationError(
        kind: ProxyDelegationErrorKind.cannotVerify,
        detail:
            "the account's governance nullifiers could not be proven unspent",
      );
    }
    return evaluate(proof);
  }

  /// The planner's exact split of [request], after persisting the round's
  /// bundle plan when the account has none yet. Nothing is recorded.
  Future<ProxyAllocationPreview> preview(ProxyAllocationRequest request) async {
    await _host.ensureBundles(request.roundId);
    final round = await _host.round(request.roundId);
    return rust.previewProxyAllocation(
      dbPath: round.account.dbPath,
      accountUuid: round.account.accountUuid,
      request: request,
      timing: _timing(round),
    );
  }

  /// Records [request] as the round's one allocation. [confirmed] is the
  /// preview the delegator confirmed, and [checks] are the pre-proving
  /// verdicts made right before, one per choice in order. The round's
  /// timing is the one ordinary votes use.
  ///
  /// The round's proposals are the roster: a plan that keeps ballots needs
  /// the ballot intents for every one recorded first.
  ///
  /// Throws [ProxyDelegationError] with
  /// [ProxyDelegationErrorKind.planChanged] when the plan no longer splits
  /// as [confirmed] does, and with
  /// [ProxyDelegationErrorKind.keptShareUnanswered] when a kept share's
  /// answers are missing.
  Future<void> commit(
    ProxyAllocationRequest request, {
    required ProxyAllocationPreview confirmed,
    required List<DelegateCheck> checks,
  }) async {
    final round = await _host.round(request.roundId);
    await rust.commitProxyAllocation(
      dbPath: round.account.dbPath,
      accountUuid: round.account.accountUuid,
      request: request,
      confirmed: confirmed,
      checks: checks,
      timing: _timing(round),
      roster: [for (final proposal in round.proposals) proposal.id],
    );
    _ballots.forget(request.roundId);
  }

  /// The committed allocation, or null before the account delegates.
  Future<ApiProxyAllocationStatus?> status(String roundId) async {
    final round = await _host.round(roundId);
    final pages = await _ballotPages(roundId);
    return rust.proxyAllocationStatus(
      dbPath: round.account.dbPath,
      accountUuid: round.account.accountUuid,
      roundId: roundId,
      ballotPages: pages,
      phase: proxyRoundPhaseForStatus(round.status),
    );
  }

  /// The delegation job's view of the committed allocation, or null before
  /// the account delegates.
  Future<ApiProxyDelegationProgress?> progress(String roundId) async {
    final round = await _host.round(roundId);
    final pages = await _ballotPages(roundId);
    return rust.proxyDelegationProgress(
      dbPath: round.account.dbPath,
      accountUuid: round.account.accountUuid,
      roundId: roundId,
      ballotPages: pages,
      phase: proxyRoundPhaseForStatus(round.status),
    );
  }

  /// The round's whole delegate ballot list, page by page, fetched again
  /// once older than [ballotListMaxAge].
  Future<List<Uint8List>> _ballotPages(String roundId) => _ballots.pages(
    roundId,
    open: () async {
      final chain = await _host.chain();
      return (startAfter) => chain.delegateBallotsPage(roundId, startAfter);
    },
  );

  /// [round]'s timing at the client's clock.
  rust.ApiProxyRoundTiming _timing(ProxyDelegatorRound round) =>
      rust.ApiProxyRoundTiming(
        nowSeconds: proxyUnixSeconds(_clock()),
        ceremonyStartSeconds: switch (round.ceremonyStart) {
          final start? => proxyUnixSeconds(start),
          null => null,
        },
        voteEndTimeSeconds: switch (round.voteEnd) {
          final end? => proxyUnixSeconds(end),
          null => null,
        },
      );
}

/// zcash_voting's round phase for a vote server [status]: `PENDING` and
/// `ACTIVE` are active, `TALLYING` and `FINALIZED` closed. Statuses arrive as
/// enum names or numbers; anything else reads as active, so no delegation
/// is reported "Not counted" before the round closes.
rust.ApiProxyRoundPhase proxyRoundPhaseForStatus(String status) {
  final value = status.trim().toUpperCase();
  const closed = {
    '2',
    '3',
    'SESSION_STATUS_TALLYING',
    'SESSION_STATUS_FINALIZED',
    'TALLYING', // l10n-ignore: protocol status
    'FINALIZED', // l10n-ignore: protocol status
  };
  return closed.contains(value)
      ? rust.ApiProxyRoundPhase.closed
      : rust.ApiProxyRoundPhase.active;
}
