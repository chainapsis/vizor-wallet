import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';

import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_values.dart';

const _key = DelegateKeyInfo(
  dk: 'zvdk1qqqs',
  fingerprint: 'qqqs-yqcy-q5rq-wzqf',
);

void main() {
  group('attester answers', () {
    test('a proof link must point at a post or gist', () {
      const x = ProxyDelegateProvider.x;
      const github = ProxyDelegateProvider.gitHub;
      expect(
        delegateProofUrlLooksRight(x, 'https://x.com/alice/status/1790'),
        isTrue,
      );
      expect(
        delegateProofUrlLooksRight(x, ' https://twitter.com/a/status/9 '),
        isTrue,
      );
      expect(delegateProofUrlLooksRight(x, 'https://x.com/alice'), isFalse);
      expect(delegateProofUrlLooksRight(x, 'http://x.com/a/status/1'), isFalse);
      expect(delegateProofUrlLooksRight(x, '@alice'), isFalse);
      expect(
        delegateProofUrlLooksRight(github, 'https://gist.github.com/a/f00'),
        isTrue,
      );
      expect(
        delegateProofUrlLooksRight(github, 'https://github.com/alice'),
        isFalse,
      );
    });
  });

  group('chain answers', () {
    test('only a refused attestation needs a new check', () {
      for (final code in [59, 60, 61, 62, 64, 65, 66, 6]) {
        expect(
          delegateRegisterNeedsNewAttestation(
            DelegateRegisterRejected(codespace: 'vote', code: code, reason: ''),
          ),
          const {64, 65}.contains(code),
        );
      }
    });
  });

  group('dashboard', () {
    test('the count is ceil(R / 16), never R itself', () {
      final cases = {0: 0, 1: 1, 15: 1, 16: 1, 17: 2, 32: 2, 33: 3, 160: 10};
      for (final MapEntry(key: shares, value: count) in cases.entries) {
        expect(
          delegateApproxCount(BigInt.from(shares)),
          BigInt.from(count),
          reason: 'R = $shares',
        );
      }
    });

    test('urgency runs reminder, final minutes, final seconds, closed', () {
      final end = DateTime(2026, 10, 7, 12);

      /// The urgency [before] the end.
      DelegateBallotUrgency at(Duration before, {bool onChain = false}) =>
          delegateBallotUrgency(
            now: end.subtract(before),
            voteEnd: end,
            ballotOnChain: onChain,
          );
      expect(at(const Duration(hours: 2)), DelegateBallotUrgency.reminder);
      expect(
        at(const Duration(minutes: 5)),
        DelegateBallotUrgency.finalMinutes,
      );
      expect(
        at(const Duration(seconds: 61)),
        DelegateBallotUrgency.finalMinutes,
      );
      expect(
        at(const Duration(seconds: 60)),
        DelegateBallotUrgency.finalSeconds,
      );
      expect(at(Duration.zero), DelegateBallotUrgency.closed);
      expect(
        at(const Duration(seconds: 30), onChain: true),
        DelegateBallotUrgency.done,
      );
      expect(
        delegateNextUrgencyChange(
          now: end.subtract(const Duration(hours: 1)),
          voteEnd: end,
        ),
        end.subtract(kDelegateFinalMinutesWindow),
      );
      expect(
        delegateNextUrgencyChange(
          now: end.subtract(const Duration(minutes: 2)),
          voteEnd: end,
        ),
        end.subtract(kDelegateFinalSecondsWindow),
      );
      expect(delegateNextUrgencyChange(now: end, voteEnd: end), isNull);
      expect(
        delegateMinutesLeft(
          now: end.subtract(const Duration(seconds: 61)),
          voteEnd: end,
        ),
        2,
      );
    });

    test('the home shows intro, registration, dashboard or retired', () {
      DelegateHomeStage stage({
        DelegateKeyInfo? key = _key,
        DelegateEntryStatus? entry,
      }) => delegateHomeStage(
        delegateModeView(
          key: key,
          delegateIndex: entry == null ? null : 3,
          entryStatus: entry ?? DelegateEntryStatus.active,
        ),
      );
      expect(stage(key: null), DelegateHomeStage.intro);
      expect(stage(), DelegateHomeStage.finishRegistering);
      expect(
        stage(entry: DelegateEntryStatus.active),
        DelegateHomeStage.dashboard,
      );
      expect(
        stage(entry: DelegateEntryStatus.suspended),
        DelegateHomeStage.dashboard,
      );
      expect(
        stage(entry: DelegateEntryStatus.retired),
        DelegateHomeStage.retired,
      );
    });
  });

  group('ballot', () {
    final proposals = ProxyMockScenario.development(
      now: DateTime(2026),
    ).round.proposals;

    test('options exist only once every question has an answer', () {
      expect(delegateBallotOptions(proposals, {}), isNull);
      expect(delegateBallotOptions(proposals, {1: 0, 2: 2}), isNull);
      expect(delegateBallotOptions(proposals, {1: 1, 2: 2, 3: 0}), [1, 2, 0]);
      expect(delegateBallotOptions(proposals, {3: 0, 1: 1, 2: 2}), [1, 2, 0]);
      // An option outside its question makes no ballot.
      expect(delegateBallotOptions(proposals, {1: 0, 2: 7, 3: 0}), isNull);
    });

    test('a stored ballot the list lacks is pending while voting is open', () {
      final now = DateTime.utc(2026, 10, 8, 12);
      DelegateRound round({
        List<int>? stored,
        ApiDelegateBallotView? ballot,
        DelegateBallotBlock? block,
      }) => DelegateRound(
        view: ApiDelegateRound(
          roundId: 'r',
          voteEndTime: proxyUnixSeconds(now.add(const Duration(hours: 1))),
          revealedShares: BigInt.zero,
          ballot: ballot ?? proxyBallot(ApiDelegateBallotKind.noBallotYet),
          ballotBlock: block,
          storedBallot: stored == null ? null : Uint32List.fromList(stored),
        ),
        title: 'R',
        proposals: const [],
      );
      expect(delegateBallotPending(round(), now), isFalse);
      expect(delegateBallotPending(round(stored: [0]), now), isTrue);
      expect(
        delegateBallotPending(
          round(stored: [0], block: DelegateBallotBlock.suspended),
          now,
        ),
        isTrue,
        reason: 'a suspension may lift before voting ends',
      );
      expect(
        delegateBallotPending(
          round(stored: [0], block: DelegateBallotBlock.retired),
          now,
        ),
        isFalse,
        reason: 'a retired entry never ballots again',
      );
      expect(
        delegateBallotPending(
          round(stored: [0]),
          now.add(const Duration(hours: 1)),
        ),
        isFalse,
        reason: 'voting ended',
      );
      expect(
        delegateBallotPending(
          round(
            stored: [0],
            ballot: proxyBallot(ApiDelegateBallotKind.submitted, [0]),
          ),
          now,
        ),
        isFalse,
        reason: 'listed',
      );
    });
  });
}
