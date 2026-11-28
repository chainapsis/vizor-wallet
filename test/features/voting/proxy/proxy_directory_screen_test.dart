import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/proxy_delegate_widgets.dart';

import '../../../support/test_l10n.dart';
import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_test_harness.dart';

final _directory = proxyDelegateDirectoryRoute(kProxyTestRoundId);

/// The row of delegate [index], in the list or the add dialog.
Finder _row(int index) => find.byKey(ValueKey('proxy_delegate_row_$index'));

/// Whether delegate [index]'s row can be tapped.
bool _enabled(WidgetTester tester, int index) => tester
    .widget<ProxyCheckCircle>(
      find.descendant(of: _row(index), matching: find.byType(ProxyCheckCircle)),
    )
    .enabled;

/// Taps delegate [index]'s row.
Future<void> _toggle(WidgetTester tester, int index) async {
  await tester.ensureVisible(_row(index));
  await tester.tap(_row(index));
  await settleProxy(tester);
}

/// Types [query] into the list's search.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('proxy_directory_search')),
      matching: find.byType(EditableText),
    ),
    query,
  );
  await settleProxy(tester);
}

/// Opens the add dialog and submits [text] in its field.
Future<void> _add(WidgetTester tester, String text) async {
  final link = find.byKey(const ValueKey('proxy_directory_add_unlisted'));
  await tester.ensureVisible(link);
  await tester.tap(link);
  await settleProxy(tester);
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('proxy_add_field')),
      matching: find.byType(EditableText),
    ),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await settleProxy(tester);
}

/// Vizor's reviewed delegates, in list order.
List<ProxyDelegateListing> _choosable(ProxyMockScenario scenario) => [
  for (final entry in scenario.delegates)
    if (scenario.listed.contains(entry.index) && entry.reviewed) entry,
];

void main() {
  group('PD-2 list', () {
    testWidgets("shows Vizor's reviewed delegates in list order", (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      final shown = _choosable(scenario);
      for (final entry in scenario.delegates) {
        expect(
          _row(entry.index),
          shown.contains(entry) ? findsOne : findsNothing,
          reason: entry.handle,
        );
      }
      final tops = [
        for (final entry in shown.take(4))
          tester.getTopLeft(_row(entry.index)).dy,
      ];
      expect(tops, [...tops]..sort(), reason: 'rows follow the list order');
      expect(find.text(testL10n.proxyListCount(shown.length)), findsOne);
    });

    testWidgets('search filters by name or handle as you type', (tester) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      final total = _choosable(scenario).length;
      await _search(tester, 'moreau');
      expect(_row(proxyEntry(scenario, 'alice_votes').index), findsOne);
      expect(_row(proxyEntry(scenario, 'bjorn_dev').index), findsNothing);
      expect(find.text(testL10n.proxyListMatches(1, total)), findsOne);
      await _search(tester, '@BJORN');
      expect(_row(proxyEntry(scenario, 'bjorn_dev').index), findsOne);
      await _search(tester, 'nobody');
      expect(find.text(testL10n.proxyNoListMatches('nobody')), findsOne);
    });

    testWidgets('without a verified list it says so and the add dialog '
        'still finds a handle', (tester) async {
      final scenario = proxyTestScenario()..listUnavailable = true;
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      expect(find.byKey(const ValueKey('proxy_list_unavailable')), findsOne);
      expect(find.byType(ProxyDelegateListRow), findsNothing);
      await _add(tester, 'alice_votes');
      expect(_row(proxyEntry(scenario, 'alice_votes').index), findsOne);
    });
  });

  group('PD-2 picker', () {
    testWidgets('stops at 8 delegates', (tester) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(
        tester,
        _directory,
        scenario: scenario,
      );
      final listed = _choosable(scenario);
      for (final entry in listed.take(8)) {
        await _toggle(tester, entry.index);
      }
      expect(find.text(testL10n.proxyChosenFull(8)), findsOne);
      for (final entry in listed.skip(8)) {
        expect(_enabled(tester, entry.index), isFalse, reason: entry.handle);
      }
      final notifier = harness.container.read(
        proxyAllocationDraftProvider(kProxyTestKey).notifier,
      );
      expect(notifier.toggle(listed.last), isFalse);
      await _toggle(tester, listed.first.index);
      expect(find.text(testL10n.proxyChosenCount(7)), findsOne);
      expect(_enabled(tester, listed.last.index), isTrue);
    });

    testWidgets('Continue opens the allocation editor', (tester) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(
        tester,
        _directory,
        scenario: scenario,
      );
      final continueButton = find.byKey(
        const ValueKey('proxy_picker_continue'),
      );
      expect(tester.widget<AppButton>(continueButton).onPressed, isNull);
      await _toggle(tester, proxyEntry(scenario, 'alice_votes').index);
      await tester.tap(continueButton);
      await settleProxy(tester);
      expect(harness.location, proxyAllocationRoute(kProxyTestRoundId));
    });
  });

  group('PD-2 add someone not on the list', () {
    testWidgets('a handle finds an unlisted delegate with its fingerprint '
        'and a not-reviewed warning, and checking adds them', (tester) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(
        tester,
        _directory,
        scenario: scenario,
      );
      final kofi = proxyEntry(scenario, 'kofi_m');
      await _add(tester, '@kofi_m');
      expect(
        find.text(formatProxyDelegateId(kofi.index, kofi.key.fingerprint)),
        findsOne,
      );
      expect(find.text(testL10n.proxyNotReviewed), findsOne);
      expect(
        find.descendant(
          of: _row(kofi.index),
          matching: find.byType(ProxyIdenticon),
        ),
        findsOne,
      );
      await _toggle(tester, kofi.index);
      final draft = harness.container.read(
        proxyAllocationDraftProvider(kProxyTestKey),
      );
      expect(
        draft.toRequest(kProxyTestRoundId).choices.single,
        ProxyDelegateChoice(
          delegateIndex: kofi.index,
          percentBps: 0,
          provider: kofi.provider,
          handle: 'kofi_m',
          dk: kofi.key.dk,
        ),
        reason: 'the choice carries what the dialog showed',
      );
    });

    testWidgets('a pasted key finds its delegate', (tester) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      await _add(tester, mockProxyDelegateKey('kofi_m').dk);
      expect(_row(proxyEntry(scenario, 'kofi_m').index), findsOne);
    });

    testWidgets('warns about lookalikes and new registrations', (tester) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      await _add(tester, 'a1ice_votes');
      expect(_row(proxyEntry(scenario, 'a1ice_votes').index), findsOne);
      expect(find.text(testL10n.proxyLookalike('alice_votes')), findsOne);
      expect(find.text(testL10n.proxyNewThisRound), findsOne);
    });

    testWidgets('an unknown handle says so', (tester) async {
      await pumpProxyRoute(tester, _directory, scenario: proxyTestScenario());
      await _add(tester, 'nobody_here');
      expect(find.text(testL10n.proxyNoSearchResults('nobody_here')), findsOne);
    });
  });
}
