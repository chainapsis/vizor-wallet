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
      expect(find.text('Your voting power: 50 ZEC'), findsNothing);
      expect(find.text(testL10n.proxyLetDelegateVoteLabel), findsNothing);
    });

    testWidgets('an available round shows the voting power and opens the '
        'directory', (tester) async {
      final harness = await pumpProxyRoute(tester, _poll);
      expect(find.text('Your voting power: 50 ZEC'), findsOne);
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

    testWidgets('a drafted split shows each delegate and the kept share, '
        'and can be changed or removed', (tester) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(tester, _poll, scenario: scenario);
      final draft = harness.container.read(
        proxyAllocationDraftProvider(kProxyTestKey).notifier,
      );
      draft
        ..toggle(proxyEntry(scenario, 'alice_votes'))
        ..setPercent(0, 5000);
      await settleProxy(tester);

      expect(
        textForKey(tester, const ValueKey('proxy_line_split')),
        '25 ZEC to @alice_votes · 25 ZEC for you to answer',
      );
      await tester.tap(find.byKey(const ValueKey('proxy_line_change')));
      await settleProxy(tester);
      expect(harness.location, proxyDelegateDirectoryRoute(kProxyTestRoundId));

      harness.router.go(_poll);
      await settleProxy(tester);
      await tester.tap(find.byKey(const ValueKey('proxy_line_remove')));
      await settleProxy(tester);
      expect(
        harness.container
            .read(proxyAllocationDraftProvider(kProxyTestKey))
            .delegates,
        isEmpty,
      );
      expect(find.byKey(const ValueKey('proxy_let_delegate_vote')), findsOne);
    });

    testWidgets('a committed split shows without a way to change it', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      scenario.status = proxyStatus(scenario, ['alice_votes', 'bjorn_dev']);
      await pumpProxyRoute(tester, _poll, scenario: scenario);
      expect(find.text('Your voting power: 37.5 ZEC'), findsOne);
      expect(
        textForKey(tester, const ValueKey('proxy_line_split')),
        '12.5 ZEC to @alice_votes · 12.5 ZEC to @bjorn_dev · '
        '12.5 ZEC for you to answer',
      );
      expect(find.byKey(const ValueKey('proxy_line_change')), findsNothing);
      expect(find.byKey(const ValueKey('proxy_line_remove')), findsNothing);
      expect(find.text(testL10n.proxyLetDelegateVoteLabel), findsNothing);
    });
  });
}

/// The first text under the widget keyed [key].
String? textForKey(WidgetTester tester, Key key) {
  final texts = find.descendant(
    of: find.byKey(key),
    matching: find.byType(Text),
  );
  if (tester.any(find.byKey(key)) && tester.widget(find.byKey(key)) is Text) {
    return (tester.widget(find.byKey(key)) as Text).data;
  }
  if (!tester.any(texts)) return null;
  return tester.widget<Text>(texts.first).data;
}
