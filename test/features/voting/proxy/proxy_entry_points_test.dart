import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_round_delegation.dart';

import '../../../support/test_l10n.dart';
import 'support/proxy_test_harness.dart';

const _poll = '/voting/poll/$kProxyTestRoundId';

void main() {
  group('the round screen\'s delegation line', () {
    testWidgets('a round the wallet can no longer delegate in replaces the '
        'action with one line saying why', (tester) async {
      await pumpProxyRoute(
        tester,
        _poll,
        scenario: proxyTestScenario(
          availability: const ApiProxyAvailability(
            kind: ApiProxyAvailabilityKind.alreadyVoted,
            usedElsewhere: false,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('proxy_line_alreadyVoted')), findsOne);
      expect(find.text(testL10n.proxyAlreadyVoted), findsOne);
      expect(find.text(testL10n.proxyDelegateVoteTitle), findsNothing);
    });

    testWidgets('an available round offers to delegate the vote and opens '
        'the directory', (tester) async {
      final harness = await pumpProxyRoute(tester, _poll);
      expect(find.text(testL10n.proxyDelegateVoteTitle), findsOne);
      expect(find.text(testL10n.proxyDelegateVoteBody), findsOne);
      await tester.tap(find.byKey(const ValueKey('proxy_let_delegate_vote')));
      await settleProxy(tester);
      expect(harness.location, proxyDelegateDirectoryRoute(kProxyTestRoundId));
    });

    testWidgets('Unsupported hides the line', (tester) async {
      await pumpProxyRoute(
        tester,
        _poll,
        scenario: proxyTestScenario(
          availability: const ApiProxyAvailability(
            kind: ApiProxyAvailabilityKind.unsupported,
            usedElsewhere: false,
          ),
        ),
      );
      expect(find.text('poll $kProxyTestRoundId'), findsOne);
      expect(find.byType(ProxyVotingPowerLineContent), findsNothing);
    });

    testWidgets('a failed anchor says so and retries', (tester) async {
      final scenario = proxyTestScenario()..availabilityCannotVerify = true;
      final harness = await pumpProxyRoute(tester, _poll, scenario: scenario);
      expect(find.byKey(const ValueKey('proxy_line_cannotVerify')), findsOne);
      final calls = harness.repository.availabilityCalls;
      scenario.availabilityCannotVerify = false;
      await tester.tap(find.text(testL10n.commonTryAgain));
      await settleProxy(tester);
      expect(harness.repository.availabilityCalls, greaterThan(calls));
      expect(find.byKey(const ValueKey('proxy_let_delegate_vote')), findsOne);
    });

    testWidgets('a drafted split sums itself up, opens the split over '
        'delegate choice, and can be removed there', (tester) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(tester, _poll, scenario: scenario);
      final draft = harness.container.read(
        proxyAllocationDraftProvider(kProxyTestKey).notifier,
      );
      draft
        ..toggle(proxyEntry(scenario, 'alice_votes'))
        ..setPercent(0, 5000);
      await settleProxy(tester);

      expect(find.text('Delegating 25 of 50 ZEC'), findsOne);
      expect(
        find.text('25 ZEC to @alice_votes. You answer for the other 25 ZEC.'),
        findsOne,
      );
      await tester.tap(find.byKey(const ValueKey('proxy_line_edit')));
      await settleProxy(tester);
      expect(harness.location, proxyAllocationRoute(kProxyTestRoundId));
      harness.router.pop();
      await settleProxy(tester);
      expect(harness.location, proxyDelegateDirectoryRoute(kProxyTestRoundId));

      harness.router.push(proxyAllocationRoute(kProxyTestRoundId));
      await settleProxy(tester);
      await tester.tap(
        find.byKey(const ValueKey('proxy_allocation_remove_delegation')),
      );
      await settleProxy(tester);
      expect(
        harness.container
            .read(proxyAllocationDraftProvider(kProxyTestKey))
            .delegates,
        isEmpty,
      );
      expect(harness.location, _poll);
      expect(find.byKey(const ValueKey('proxy_let_delegate_vote')), findsOne);
    });

    testWidgets('a committed split shows without a way to change it', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      scenario.status = proxyStatus(scenario, ['alice_votes', 'bjorn_dev']);
      await pumpProxyRoute(tester, _poll, scenario: scenario);
      expect(find.text('Delegated 25 of 37.5 ZEC'), findsOne);
      expect(
        find.text(
          '12.5 ZEC to @alice_votes and 12.5 ZEC to @bjorn_dev. You answer '
          'for the other 12.5 ZEC.',
        ),
        findsOne,
      );
      expect(find.byKey(const ValueKey('proxy_line_edit')), findsNothing);
      expect(find.text(testL10n.proxyDelegateVoteTitle), findsNothing);
    });
  });
}
