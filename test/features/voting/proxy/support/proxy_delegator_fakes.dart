import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegator_client.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegator.dart' as rust;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

/// The account every fake round belongs to.
const kFakeDelegatorAccount = ProxyDelegatorAccount(
  dbPath: '/fake/wallet.db',
  accountUuid: 'account-1',
);

/// The fake round's ceremony start.
final kFakeCeremonyStart = DateTime.utc(2026, 10, 3);

/// The fake round's vote end.
final kFakeVoteEnd = DateTime.utc(2026, 10, 10);

/// zcash_voting's error of [kind].
rust_wire.ProxyDelegationError delegatorError(
  rust_wire.ProxyDelegationErrorKind kind, [
  String? detail,
]) => rust_wire.ProxyDelegationError(kind: kind, detail: detail);

/// A bridged availability of [kind].
rust.ApiProxyAvailability bridgedAvailability(
  rust.ApiProxyAvailabilityKind kind, {
  bool usedElsewhere = false,
}) => rust.ApiProxyAvailability(kind: kind, usedElsewhere: usedElsewhere);

/// A delegate ballot page whose `next_start_after` is [next].
Uint8List ballotPage(int next, {List<int> delegates = const []}) =>
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'ballots': [
            for (final index in delegates)
              {
                'delegate_index': index,
                'options': const [0],
              },
          ],
          'next_start_after': next,
        }),
      ),
    );

/// A fake of zcash_voting's delegator calls: it records what each call was
/// given and answers from fields tests set.
class FakeProxyDelegatorRust {
  /// Availability's answer for the proof it is given; throwing is allowed.
  rust.ApiProxyAvailability Function(rust.ApiGovNullifierProof proof)
  availabilityFor = (_) =>
      bridgedAvailability(rust.ApiProxyAvailabilityKind.available);

  /// What each availability call was given.
  final availabilityCalls =
      <
        ({
          rust.ApiProxyChainAnswers chain,
          rust.ApiGovNullifierProof proof,
          rust.ApiProxyRoundTiming timing,
        })
      >[];

  /// The wallet's ballots, which the plan splits.
  int walletBallots = 400;

  /// Every preview's request.
  final previews = <rust_wire.ProxyAllocationRequest>[];

  /// The committed request, with the confirmed preview, verdicts, timing
  /// and roster it came with.
  ({
    rust_wire.ProxyAllocationRequest request,
    rust_wire.ProxyAllocationPreview confirmed,
    List<rust_wire.DelegateCheck> checks,
    rust.ApiProxyRoundTiming timing,
    List<int> roster,
  })?
  committed;

  /// The pages and phase each status or progress call read.
  final reads = <({List<Uint8List> pages, rust.ApiProxyRoundPhase phase})>[];

  /// The current wallet's split of [request].
  rust_wire.ProxyAllocationPreview planFor(
    rust_wire.ProxyAllocationRequest request,
  ) => rust_wire.ProxyAllocationPreview(
    delegations: [
      for (final choice in request.choices)
        rust_wire.ProxyPreviewDelegation(
          delegateIndex: choice.delegateIndex,
          ballots: BigInt.from(walletBallots * choice.percentBps ~/ 10000),
        ),
    ],
    keptBallots: BigInt.from(
      walletBallots *
          (10000 - request.choices.fold(0, (sum, c) => sum + c.percentBps)) ~/
          10000,
    ),
    dcCount: request.choices.length,
    bundleCount: 1,
    singleShare: false,
  );

  Future<rust.ApiProxyAvailability> availability({
    required ProxyDelegatorAccount account,
    required String roundId,
    required rust.ApiProxyChainAnswers chain,
    required rust.ApiGovNullifierProof govNullifiers,
    required rust.ApiProxyRoundTiming timing,
  }) async {
    availabilityCalls.add((chain: chain, proof: govNullifiers, timing: timing));
    return availabilityFor(govNullifiers);
  }

  Future<rust_wire.ProxyAllocationPreview> preview({
    required ProxyDelegatorAccount account,
    required rust_wire.ProxyAllocationRequest request,
    required rust.ApiProxyRoundTiming timing,
  }) async {
    previews.add(request);
    return planFor(request);
  }

  Future<void> commit({
    required ProxyDelegatorAccount account,
    required rust_wire.ProxyAllocationRequest request,
    required rust_wire.ProxyAllocationPreview confirmed,
    required List<rust_wire.DelegateCheck> checks,
    required rust.ApiProxyRoundTiming timing,
    required List<int> roster,
  }) async {
    committed = (
      request: request,
      confirmed: confirmed,
      checks: checks,
      timing: timing,
      roster: roster,
    );
  }

  Future<int?> ballotsNextStartAfter({
    required String roundId,
    required int startAfter,
    required Uint8List page,
  }) async {
    final next =
        (jsonDecode(utf8.decode(page)) as Map)['next_start_after'] as int;
    return next == 0 ? null : next;
  }

  Future<rust.ApiProxyAllocationStatus?> status({
    required ProxyDelegatorAccount account,
    required String roundId,
    required List<Uint8List> ballotPages,
    required rust.ApiProxyRoundPhase phase,
  }) async {
    reads.add((pages: ballotPages, phase: phase));
    return null;
  }

  Future<rust.ApiProxyDelegationProgress?> progress({
    required ProxyDelegatorAccount account,
    required String roundId,
    required List<Uint8List> ballotPages,
    required rust.ApiProxyRoundPhase phase,
  }) async {
    reads.add((pages: ballotPages, phase: phase));
    return null;
  }
}

/// A fake vote chain: fixed answers, every read recorded in order.
class FakeProxyDelegatorChain implements ProxyDelegatorChain {
  /// The reads made, in order.
  final reads = <String>[];

  /// Ballot pages by the `start_after` they answer.
  Map<int, Uint8List> ballotPages = {0: ballotPage(0)};

  @override
  Future<Uint8List> protocolCapabilities() async {
    reads.add('protocol-capabilities');
    return Uint8List.fromList(utf8.encode('{"proxy_delegation_version":1}'));
  }

  @override
  Future<Uint8List> round(String roundId) async {
    reads.add('round/$roundId');
    return Uint8List.fromList(utf8.encode('{"round":{}}'));
  }

  @override
  Future<Uint8List?> proxyDelegationParams() async {
    reads.add('proxy-delegation-params');
    return Uint8List.fromList(utf8.encode('{"params":{}}'));
  }

  @override
  Future<Uint8List> delegateBallotsPage(String roundId, int startAfter) async {
    reads.add('delegate-ballots/$roundId?start_after=$startAfter');
    return ballotPages[startAfter]!;
  }
}

/// A fake app host: one round, its facts settable, every call counted.
class FakeProxyDelegatorHost implements ProxyDelegatorHost {
  /// Creates the host over [chainReader].
  FakeProxyDelegatorHost(this.chainReader);

  /// The vote chain the host hands out.
  final FakeProxyDelegatorChain chainReader;

  /// The round status the vote server reports.
  String status = 'SESSION_STATUS_ACTIVE';

  /// The authenticated vote end; null when the round has none.
  DateTime? voteEnd = kFakeVoteEnd;

  /// The ceremony start the vote server reports.
  DateTime? ceremonyStart = kFakeCeremonyStart;

  /// The participation reader's verdict.
  rust.ApiGovNullifierProof govProof = rust.ApiGovNullifierProof.unspent;

  /// The account's voting power.
  BigInt ballots = BigInt.from(400);

  /// How often the reader ran.
  int govProofs = 0;

  /// How often bundle setup ran.
  int bundleSetups = 0;

  @override
  Future<ProxyDelegatorRound> round(String roundId) async =>
      ProxyDelegatorRound(
        account: kFakeDelegatorAccount,
        title: 'Fake round',
        proposals: const [
          VotingProposalView(
            id: 1,
            title: 'First question',
            description: '',
            options: [
              VotingOptionView(index: 0, label: 'Yes'),
              VotingOptionView(index: 1, label: 'No'),
            ],
          ),
        ],
        status: status,
        ceremonyStart: ceremonyStart,
        voteEnd: voteEnd,
      );

  @override
  Future<BigInt> eligibleBallots(String roundId) async => ballots;

  @override
  Future<rust.ApiGovNullifierProof> govNullifiers(String roundId) async {
    govProofs++;
    return govProof;
  }

  @override
  Future<void> ensureBundles(String roundId) async => bundleSetups++;

  @override
  Future<ProxyDelegatorChain> chain() async => chainReader;
}
