import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegator_client.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegator.dart' as rust;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import 'support/proxy_delegator_fakes.dart';
import 'support/proxy_values.dart';
import 'support/proxy_rust_fake.dart';

const _roundId =
    '0101010101010101010101010101010101010101010101010101010101010101';

void main() {
  useProxyRustFake();
  late FakeProxyDelegatorRust bridge;
  late FakeProxyDelegatorChain chain;
  late FakeProxyDelegatorHost host;
  late DateTime now;
  late ProxyDelegatorClient client;
  setUp(() {
    bridge = proxyRust.delegator = FakeProxyDelegatorRust();
    chain = FakeProxyDelegatorChain();
    host = FakeProxyDelegatorHost(chain);
    now = DateTime.utc(2026, 10, 7, 12);
    client = ProxyDelegatorClient(host: host, clock: () => now);
  });

  /// A request to [indices], 25% each, keeping the rest.
  ProxyAllocationRequest request(List<int> indices) => ProxyAllocationRequest(
    roundId: _roundId,
    choices: [
      for (final index in indices)
        ProxyDelegateChoice(
          delegateIndex: index,
          percentBps: 2500,
          provider: ProxyDelegateProvider.gitHub,
          handle: 'delegate$index',
          dk: 'zvdk1key$index',
        ),
    ],
  );

  group('availability', () {
    test('reads the chain in the order zcash_voting reads it and runs no '
        'proof when an earlier gate answers', () async {
      bridge.availabilityFor = (_) =>
          bridgedAvailability(rust.ApiProxyAvailabilityKind.unsupported);

      expect(
        await client.availability(_roundId),
        const ApiProxyAvailability(
          kind: ApiProxyAvailabilityKind.unsupported,
          usedElsewhere: false,
        ),
      );

      expect(chain.reads, [
        'protocol-capabilities',
        'round/$_roundId',
        'proxy-delegation-params',
      ]);
      expect(host.govProofs, 0, reason: 'no gov nullifier proof was needed');
      final call = bridge.availabilityCalls.single;
      expect(call.proof, rust.ApiGovNullifierProof.unavailable);
      expect(call.chain.proxyDelegationParams, isNotNull);
      expect(
        call.timing.nowSeconds,
        BigInt.from(now.millisecondsSinceEpoch ~/ 1000),
      );
      expect(
        call.timing.ceremonyStartSeconds,
        BigInt.from(kFakeCeremonyStart.millisecondsSinceEpoch ~/ 1000),
      );
      expect(
        call.timing.voteEndTimeSeconds,
        BigInt.from(kFakeVoteEnd.millisecondsSinceEpoch ~/ 1000),
      );
    });

    test(
      'proves the gov nullifiers only once zcash_voting asks for them',
      () async {
        bridge.availabilityFor = (proof) => switch (proof) {
          rust.ApiGovNullifierProof.unavailable => throw delegatorError(
            rust_wire.ProxyDelegationErrorKind.cannotVerify,
          ),
          rust.ApiGovNullifierProof.unspent => bridgedAvailability(
            rust.ApiProxyAvailabilityKind.available,
          ),
          rust.ApiGovNullifierProof.spent => bridgedAvailability(
            rust.ApiProxyAvailabilityKind.alreadyVoted,
            usedElsewhere: true,
          ),
        };

        expect(
          await client.availability(_roundId),
          const ApiProxyAvailability(
            kind: ApiProxyAvailabilityKind.available,
            usedElsewhere: false,
          ),
        );
        expect(host.govProofs, 1);
        expect(bridge.availabilityCalls.map((call) => call.proof), [
          rust.ApiGovNullifierProof.unavailable,
          rust.ApiGovNullifierProof.unspent,
        ]);

        host.govProof = rust.ApiGovNullifierProof.spent;
        expect(
          await client.availability(_roundId),
          const ApiProxyAvailability(
            kind: ApiProxyAvailabilityKind.alreadyVoted,
            usedElsewhere: true,
          ),
        );

        host.govProof = rust.ApiGovNullifierProof.unavailable;
        await expectLater(
          client.availability(_roundId),
          throwsA(
            isA<ProxyDelegationError>().having(
              (error) => error.kind,
              'kind',
              ProxyDelegationErrorKind.cannotVerify,
            ),
          ),
        );
      },
    );

    test('a chain without proxy params passes none', () async {
      chain.params = null;
      await client.availability(_roundId);
      expect(
        bridge.availabilityCalls.single.chain.proxyDelegationParams,
        isNull,
      );
    });

    test('maps every result zcash_voting gives', () async {
      final expected = {
        rust.ApiProxyAvailabilityKind.available: const ApiProxyAvailability(
          kind: ApiProxyAvailabilityKind.available,
          usedElsewhere: false,
        ),
        rust.ApiProxyAvailabilityKind.unsupported: const ApiProxyAvailability(
          kind: ApiProxyAvailabilityKind.unsupported,
          usedElsewhere: false,
        ),
        rust.ApiProxyAvailabilityKind.paused: const ApiProxyAvailability(
          kind: ApiProxyAvailabilityKind.paused,
          usedElsewhere: false,
        ),
        rust.ApiProxyAvailabilityKind.alreadyVoted: const ApiProxyAvailability(
          kind: ApiProxyAvailabilityKind.alreadyVoted,
          usedElsewhere: false,
        ),
        rust.ApiProxyAvailabilityKind.timingUnavailable:
            const ApiProxyAvailability(
              kind: ApiProxyAvailabilityKind.timingUnavailable,
              usedElsewhere: false,
            ),
        rust.ApiProxyAvailabilityKind.voteEnded: const ApiProxyAvailability(
          kind: ApiProxyAvailabilityKind.voteEnded,
          usedElsewhere: false,
        ),
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        bridge.availabilityFor = (_) => bridgedAvailability(key);
        expect(await client.availability(_roundId), value, reason: '$key');
      }
    });
  });

  test('preview sets the round\'s bundles up first and keeps the planner\'s '
      'split', () async {
    final preview = await client.preview(request([3, 4]));

    expect(host.bundleSetups, 1);
    expect(bridge.previews.single.choices.map((c) => c.delegateIndex), [3, 4]);
    expect(preview.delegations.map((d) => d.ballots), [
      BigInt.from(100),
      BigInt.from(100),
    ]);
    expect(preview.keptBallots, BigInt.from(200));
  });

  test('commit passes the confirmed preview, the verdicts, the picked '
      "delegates' identity and the round's timing, and refuses a plan that "
      'moved since its preview', () async {
    final preview = await client.preview(request([3, 4]));
    const checks = [DelegateCheck.ok, DelegateCheck.ok];

    bridge.walletBallots = 300;
    await expectLater(
      client.commit(request([3, 4]), confirmed: preview, checks: checks),
      throwsA(
        isA<ProxyDelegationError>().having(
          (error) => error.kind,
          'kind',
          ProxyDelegationErrorKind.planChanged,
        ),
      ),
    );
    expect(bridge.committed, isNull);

    final again = await client.preview(request([3, 4]));
    await client.commit(request([3, 4]), confirmed: again, checks: checks);
    final committed = bridge.committed!;
    expect(committed.confirmed.keptBallots, BigInt.from(150));
    expect(committed.confirmed.delegations.map((d) => d.ballots), [
      BigInt.from(75),
      BigInt.from(75),
    ]);
    expect(committed.checks, checks);
    expect(
      committed.timing.nowSeconds,
      BigInt.from(now.millisecondsSinceEpoch ~/ 1000),
    );
    expect(
      committed.timing.voteEndTimeSeconds,
      BigInt.from(kFakeVoteEnd.millisecondsSinceEpoch ~/ 1000),
      reason: 'the timing ordinary votes use',
    );
    expect(
      committed.timing.ceremonyStartSeconds,
      BigInt.from(kFakeCeremonyStart.millisecondsSinceEpoch ~/ 1000),
    );
    expect(committed.roster, [1], reason: "the round's proposals");
    final choice = committed.request.choices.first;
    expect(
      (choice.delegateIndex, choice.provider, choice.handle, choice.dk),
      (3, rust_wire.ProxyDelegateProvider.gitHub, 'delegate3', 'zvdk1key3'),
    );
  });

  group('status and progress', () {
    test(
      'read every ballot page in order, once per freshness window',
      () async {
        chain.ballotPages = {
          0: ballotPage(5, delegates: [2, 5]),
          5: ballotPage(0, delegates: [9]),
        };
        bridge.statusAnswer = rust.ApiProxyAllocationStatus(
          delegations: [bridgedView(3)],
          keptBallots: BigInt.from(37),
        );

        await client.status(_roundId);
        await client.progress(_roundId);

        expect(
          chain.reads.where((read) => read.startsWith('delegate-ballots')),
          [
            'delegate-ballots/$_roundId?start_after=0',
            'delegate-ballots/$_roundId?start_after=5',
          ],
        );
        expect(bridge.reads.map((read) => read.pages.length), [2, 2]);

        now = now.add(client.ballotListMaxAge);
        await client.status(_roundId);
        expect(
          chain.reads.where((read) => read.startsWith('delegate-ballots')),
          hasLength(4),
        );
      },
    );

    test('read the round as active or closed from its status', () async {
      final phases = {
        'SESSION_STATUS_ACTIVE': rust.ApiProxyRoundPhase.active,
        'SESSION_STATUS_PENDING': rust.ApiProxyRoundPhase.active,
        '1': rust.ApiProxyRoundPhase.active,
        '4': rust.ApiProxyRoundPhase.active,
        'SESSION_STATUS_TALLYING': rust.ApiProxyRoundPhase.closed,
        'SESSION_STATUS_FINALIZED': rust.ApiProxyRoundPhase.closed,
        '2': rust.ApiProxyRoundPhase.closed,
        '3': rust.ApiProxyRoundPhase.closed,
        'something new': rust.ApiProxyRoundPhase.active,
      };
      for (final MapEntry(:key, :value) in phases.entries) {
        expect(proxyRoundPhaseForStatus(key), value, reason: key);
      }
      host.status = 'SESSION_STATUS_TALLYING';
      await client.status(_roundId);
      expect(bridge.reads.single.phase, rust.ApiProxyRoundPhase.closed);
    });

    test('map every stage and ballot zcash_voting reports', () async {
      bridge.statusAnswer = rust.ApiProxyAllocationStatus(
        delegations: [
          bridgedView(1, stage: rust_wire.ProxyDelegationStage.preparing),
          bridgedView(
            2,
            stage: rust_wire.ProxyDelegationStage.submitting,
            ballot: rust.ApiDelegateBallotKind.submitted,
            options: [1, 0],
          ),
          bridgedView(3, stage: rust_wire.ProxyDelegationStage.included),
          bridgedView(
            4,
            stage: rust_wire.ProxyDelegationStage.handedOff,
            ballot: rust.ApiDelegateBallotKind.counted,
            options: [0, 2],
          ),
          bridgedView(
            5,
            stage: rust_wire.ProxyDelegationStage.notCounted,
            ballot: rust.ApiDelegateBallotKind.notCounted,
          ),
        ],
        keptBallots: BigInt.from(100),
      );

      final status = (await client.status(_roundId))!;

      expect(status.keptBallots, BigInt.from(100));
      expect(status.delegations.map((view) => view.stage), [
        ProxyDelegationStage.preparing,
        ProxyDelegationStage.submitting,
        ProxyDelegationStage.included,
        ProxyDelegationStage.handedOff,
        ProxyDelegationStage.notCounted,
      ]);
      expect(status.delegations.map((view) => view.ballot), [
        isProxyBallot(ApiDelegateBallotKind.noBallotYet),
        isProxyBallot(ApiDelegateBallotKind.submitted, [1, 0]),
        isProxyBallot(ApiDelegateBallotKind.noBallotYet),
        isProxyBallot(ApiDelegateBallotKind.counted, [0, 2]),
        isProxyBallot(ApiDelegateBallotKind.notCounted),
      ]);
      expect(status.delegations.first.handle, 'delegate1');
    });

    test('progress carries every flag of zcash_voting\'s view', () async {
      bridge.progressAnswers.add(
        bridgedProgress(
          [bridgedView(3, stage: rust_wire.ProxyDelegationStage.submitting)],
          plannedImmediate: true,
          immediateRevealConfirmed: true,
          refusedByChain: true,
        ),
      );
      final progress = (await client.progress(_roundId))!;
      expect(progress.plannedImmediate, isTrue);
      expect(progress.immediateRevealConfirmed, isTrue);
      expect(progress.refusedByChain, isTrue);
      expect(
        progress.delegations.single.stage,
        ProxyDelegationStage.submitting,
      );
    });

    test('a round the account never delegated in reads as none', () async {
      expect(await client.status(_roundId), isNull);
      expect(await client.progress(_roundId), isNull);
    });
  });

  test('round facts need the round\'s authenticated vote end', () async {
    final context = await client.roundContext(_roundId);
    expect(context.roundId, _roundId);
    expect(context.title, 'Fake round');
    expect(context.voteEndTime, kFakeVoteEnd);
    expect(context.eligibleBallots, BigInt.from(400));
    expect(context.proposals.single.id, 1);

    host.voteEnd = null;
    await expectLater(
      client.roundContext(_roundId),
      throwsA(isA<ProxyDelegationError>()),
    );
  });

  test('a wallet with less weight than delegates cannot preview', () async {
    bridge.walletBallots = 1;
    await expectLater(
      client.preview(request([3, 4])),
      throwsA(
        isA<ProxyDelegationError>().having(
          (error) => error.kind,
          'kind',
          ProxyDelegationErrorKind.notEnoughVotingPower,
        ),
      ),
    );
  });
}
