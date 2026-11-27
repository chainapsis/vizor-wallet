@Tags(['mobile'])
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_route_table.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_round_delegation.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_screens.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';

import '../../../figma_compare/figma_compare_font_loader.dart';
import '../../../support/test_l10n.dart';
import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_test_harness.dart';
import 'support/proxy_values.dart';

const _phone = Size(393, 852);

/// The production mobile route table plus a poll page hosting the round's
/// delegation line, the vote review and a stand-in progress screen.
List<RouteBase> _mobileRoutes() => [
  GoRoute(
    path: '/voting/poll/:roundId',
    pageBuilder: (_, state) => CupertinoPage(
      key: state.pageKey,
      child: MobileVotingScaffold(
        title: 'Coinholder voting',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ProxyVotingPowerLine(
            roundId: state.pathParameters['roundId']!,
          ),
        ),
      ),
    ),
  ),
  GoRoute(
    path: '/voting/poll/:roundId/review',
    pageBuilder: (_, state) => CupertinoPage(
      key: state.pageKey,
      child: MobileVotingReviewScreen(
        roundId: state.pathParameters['roundId']!,
      ),
    ),
  ),
  GoRoute(
    path: '/voting/poll/:roundId/status',
    builder: (_, _) => const Text('progress'),
  ),
  ...proxyDelegationMobileRoutes(guard: (child) => child),
];

/// Pumps [location] through the production mobile route table on a phone.
Future<ProxyTestHarness> _pumpMobile(
  WidgetTester tester,
  String location, {
  ProxyMockScenario? scenario,
  double textScale = 1,
  Size size = _phone,
}) => pumpProxyRoute(
  tester,
  location,
  scenario: scenario,
  size: size,
  routes: _mobileRoutes(),
  textScale: textScale,
);

void main() {
  setUpAll(loadFigmaCompareFonts);

  test('runs with mobile tokens', () {
    expect(kAppFormFactor, AppFormFactor.mobile);
  });

  testWidgets('the densest screens fit a phone at 200% text', (tester) async {
    final scenario = proxyTestScenario();
    scenario.status = proxyStatus(scenario, [
      'alice_votes',
      'dana_research',
    ], ballot: proxyBallot(ApiDelegateBallotKind.counted, [0, 2, 1]));
    for (final location in [
      '/voting/poll/$kProxyTestRoundId',
      proxyDelegateProfileRoute(kProxyTestRoundId, 4),
    ]) {
      await _pumpMobile(tester, location, scenario: scenario, textScale: 2);
      expect(tester.takeException(), isNull, reason: location);
    }
  });

  testWidgets('the picker, editor and review fit a phone at 200% text', (
    tester,
  ) async {
    final scenario = proxyTestScenario();
    final harness = await _pumpMobile(
      tester,
      proxyDelegateDirectoryRoute(kProxyTestRoundId),
      scenario: scenario,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final draft = harness.container.read(
      proxyAllocationDraftProvider(kProxyTestKey).notifier,
    );
    draft.toggle(proxyEntry(scenario, 'alice_votes'));
    draft.toggle(proxyEntry(scenario, 'dana_research'));
    draft.splitEvenly();
    harness.router.push(proxyAllocationRoute(kProxyTestRoundId));
    await settleProxy(tester);
    expect(tester.takeException(), isNull);
    harness.router.push(votingReviewRoute(kProxyTestRoundId));
    await settleProxy(tester);
    expect(tester.takeException(), isNull);
  });

  // A small phone and a large one, at normal and 200% text.
  for (final size in const [Size(320, 568), _phone]) {
    for (final textScale in const [1.0, 2.0]) {
      testWidgets('the review keeps the finality checkbox above the button '
          'on screen at $size and ${textScale}x text', (tester) async {
        final scenario = proxyTestScenario();
        final harness = await _pumpMobile(
          tester,
          '/voting/poll/$kProxyTestRoundId',
          scenario: scenario,
          textScale: textScale,
          size: size,
        );
        final draft = harness.container.read(
          proxyAllocationDraftProvider(kProxyTestKey).notifier,
        );
        draft.toggle(proxyEntry(scenario, 'alice_votes'));
        draft.toggle(proxyEntry(scenario, 'dana_research'));
        draft.splitEvenly();
        harness.router.push(votingReviewRoute(kProxyTestRoundId));
        await settleProxy(tester);
        expect(tester.takeException(), isNull);

        final footer = find.byKey(const ValueKey('proxy_confirm_footer'));
        final checkbox = find.byKey(const ValueKey('proxy_finality_checkbox'));
        final delegate = find.byKey(
          const ValueKey('voting_confirm_submit_button'),
        );
        for (final part in [
          checkbox,
          find.byKey(const ValueKey('proxy_counts_only_with_ballot')),
          delegate,
        ]) {
          expect(find.descendant(of: footer, matching: part), findsOne);
        }
        final box = tester.getRect(checkbox);
        final cta = tester.getRect(delegate);
        final area = tester.getRect(
          find.descendant(of: footer, matching: find.byType(Scrollable)),
        );
        expect(box.top, greaterThanOrEqualTo(0));
        expect(box.bottom, lessThanOrEqualTo(area.top));
        expect(area.bottom, lessThanOrEqualTo(cta.top));
        expect(cta.bottom, lessThanOrEqualTo(size.height));

        expect(tester.widget<AppButton>(delegate).onPressed, isNull);
        expect(find.text(testL10n.proxyConfirmCheckboxHint), findsOne);
        await tester.tap(checkbox);
        await settleProxy(tester);
        expect(tester.widget<AppButton>(delegate).onPressed, isNotNull);
        expect(find.text(testL10n.proxyConfirmCheckboxHint), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
