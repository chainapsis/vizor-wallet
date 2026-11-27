import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/date_format.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';

import '../../../support/test_l10n.dart';
import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_values.dart';

const _key = DelegateKeyInfo(
  dk: 'zvdk1qqqs',
  fingerprint: 'qqqs-yqcy-q5rq-wzqf',
);

void main() {
  group('attester answers', () {
    test('each of the five errors, an unknown answer and no answer has its '
        'own copy', () {
      final copies = {
        for (final error in DelegateVerifierError.values)
          error: delegateVerifierErrorText(
            testL10n,
            DelegateVerifierRefusal(error: error),
          ),
        null: delegateVerifierErrorCopy(testL10n, null),
      };
      expect(copies, hasLength(7));
      expect(copies.values.toSet(), hasLength(copies.length));
    });

    test('a retry time is shown wherever the attester gives one', () {
      final retryAfter = DateTime(2026, 10, 8, 2);
      final time = formatDayMonthTime(retryAfter, testL10n.localeName);
      for (final error in const [
        DelegateVerifierError.rateLimited,
        DelegateVerifierError.providerUnavailable,
      ]) {
        final copy = delegateVerifierErrorText(
          testL10n,
          DelegateVerifierRefusal(
            error: error,
            retryAfter: proxyUnixSeconds(retryAfter),
          ),
        );
        expect(copy, endsWith('Try again after $time.'), reason: '$error');
        expect(
          delegateVerifierErrorText(
            testL10n,
            DelegateVerifierRefusal(error: error),
          ),
          endsWith('Try again later.'),
        );
      }
    });

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
    test('each REGISTER rejection has its own copy', () {
      final copies = {
        for (final code in [59, 60, 61, 62, 64, 66])
          code: delegateRegisterRejectionCopy(testL10n, 'vote', code),
      };
      expect(copies.values.toSet(), hasLength(copies.length));
      expect(copies.values, isNot(contains(testL10n.delegateRegisterRejected)));
      // A taken handle says how it gets resolved.
      expect(copies[62], allOf(contains('Retire'), contains('coordinators')));
      expect(delegateRegisterRejectionCopy(testL10n, 'vote', 65), copies[64]);
      expect(
        delegateRegisterRejectionCopy(testL10n, 'vote', 6),
        testL10n.delegateRegisterRejected,
      );
      expect(
        delegateRegisterRejectionCopy(testL10n, 'sdk', 62),
        testL10n.delegateRegisterRejected,
      );
    });

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

    test('each ballot rejection has its own copy', () {
      final copies = {
        for (final code in [3, 4, 50, 53, 54, 55, 57, 58])
          code: delegateBallotRejectionCopy(testL10n, 'vote', code),
      };
      expect(copies.values.toSet(), hasLength(copies.length));
      expect(copies[57], testL10n.delegateDifferentBallotOnChain);
      expect(copies[54], testL10n.delegateSuspended);
      expect(
        delegateBallotRejectionCopy(testL10n, 'vote', 6),
        testL10n.delegateBallotRejected,
      );
      expect(
        delegateBallotRejectionCopy(testL10n, 'sdk', 4),
        testL10n.delegateBallotRejected,
      );
    });

    test('a refused Retire explains itself', () {
      expect({
        delegateRetireRejectionCopy(testL10n, 'vote', 54),
        delegateRetireRejectionCopy(testL10n, 'vote', 53),
        testL10n.delegateRetireFailed,
      }, hasLength(3));
      expect(
        delegateRetireRejectionCopy(testL10n, 'vote', 6),
        testL10n.delegateRetireFailed,
      );
    });
  });

  group('key', () {
    test('the key shows as "#17 · fingerprint" once it has an index', () {
      expect(formatDelegateKey(_key), 'qqqs-yqcy-q5rq-wzqf');
      expect(
        formatDelegateKey(_key, delegateIndex: 17),
        '#17 · qqqs-yqcy-q5rq-wzqf',
      );
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

    test('the count reads "at least N"', () {
      expect(
        delegateCountText(testL10n, BigInt.zero),
        'No delegations revealed yet',
      );
      expect(
        delegateCountText(testL10n, BigInt.from(9)),
        'At least 1 delegation',
      );
      expect(
        delegateCountText(testL10n, BigInt.from(37)),
        'At least 3 delegations',
      );
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
    });

    test('an option outside a question has no ballot', () {
      expect(delegateBallotOptions(proposals, {1: 0, 2: 7, 3: 0}), isNull);
      expect(delegateBallotOptions(const [], const {}), isNull);
    });

    test('choices round-trip and label every question', () {
      expect(delegateBallotChoices([1, 2, 0]), {1: 1, 2: 2, 3: 0});
      final labels = delegateBallotChoiceLabels(testL10n, proposals, [1, 2, 0]);
      expect(labels.map((choice) => choice.option), [
        'No',
        "Don't fund",
        'Yes',
      ]);
      expect(labels.first.proposal, proposals.first.title);
    });

    test('an unregistered, suspended or retired entry blocks Submit', () {
      expect(delegateBallotBlockCopy(testL10n, null), isNull);
      expect({
        for (final block in DelegateBallotBlock.values)
          delegateBallotBlockCopy(testL10n, block),
      }, hasLength(DelegateBallotBlock.values.length));
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

    test('the dashboard names each ballot state', () {
      expect(
        delegateBallotStatusLabel(
          testL10n,
          proxyBallot(ApiDelegateBallotKind.noBallotYet),
        ),
        testL10n.proxyNoBallotYetLabel,
      );
      expect(
        delegateBallotStatusLabel(
          testL10n,
          proxyBallot(ApiDelegateBallotKind.submitted, [0]),
        ),
        testL10n.delegateBallotSubmittedLabel,
        reason: 'counted only at close',
      );
      expect(
        delegateBallotStatusLabel(
          testL10n,
          proxyBallot(ApiDelegateBallotKind.counted, [0]),
        ),
        testL10n.proxyCountedLabel,
      );
      expect(
        delegateBallotStatusLabel(
          testL10n,
          proxyBallot(ApiDelegateBallotKind.notCounted),
        ),
        testL10n.proxyNoBallotNotCountedLabel,
      );
    });
  });

  test('load failures name their cause', () {
    expect(
      delegateModeErrorCopy(
        testL10n,
        const DelegateModeException(DelegateModeErrorKind.cannotVerify),
      ),
      testL10n.proxyCannotVerify,
    );
    expect(
      delegateModeErrorCopy(
        testL10n,
        const DelegateModeException(DelegateModeErrorKind.unavailable),
      ),
      testL10n.delegateUnavailable,
    );
    expect(
      delegateModeErrorCopy(testL10n, StateError('x')),
      testL10n.delegateLoadError,
    );
  });
}
