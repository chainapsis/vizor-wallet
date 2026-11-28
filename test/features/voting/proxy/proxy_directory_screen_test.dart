import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/proxy_delegate_directory_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/proxy_delegate_widgets.dart';

import '../../../support/test_l10n.dart';
import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_test_harness.dart';

final _directory = proxyDelegateDirectoryRoute(kProxyTestRoundId);

/// The directory row of delegate [index].
Finder _row(int index) => find.byKey(ValueKey('proxy_delegate_row_$index'));

/// The add button of delegate [index].
Finder _pick(int index) => find.byKey(ValueKey('proxy_pick_$index'));

/// Types [query] into search and submits it.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('proxy_directory_search')),
      matching: find.byType(EditableText),
    ),
    query,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await settleProxy(tester);
}

/// Types [text] into the paste field and submits it.
Future<void> _paste(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('proxy_directory_paste')),
      matching: find.byType(EditableText),
    ),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await settleProxy(tester);
}

void main() {
  group('PD-2 browse', () {
    testWidgets("shows Vizor's list in list order", (tester) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      final listed = scenario.delegates
          .where((e) => scenario.listed.contains(e.index))
          .toList();
      for (final entry in scenario.delegates) {
        expect(
          _row(entry.index),
          listed.contains(entry) ? findsOne : findsNothing,
        );
      }
      final tops = [
        for (final entry in listed.take(4))
          tester.getTopLeft(_row(entry.index)).dy,
      ];
      expect(tops, [...tops]..sort(), reason: 'rows follow the list order');
    });

    testWidgets('a retired delegate on the list is not reviewed and cannot '
        'be added', (tester) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      final lena = proxyEntry(scenario, 'lena_old');
      await tester.ensureVisible(_row(lena.index));
      expect(
        find.descendant(
          of: _row(lena.index),
          matching: find.text(testL10n.proxyNotReviewedLabel),
        ),
        findsOne,
      );
      expect(tester.widget<AppButton>(_pick(lena.index)).onPressed, isNull);
      expect(
        find.text(proxyBlockedCopy(testL10n, '@lena_old', retired: true)),
        findsOne,
      );
    });

    testWidgets('without a verified list browse says so and search still '
        'works', (tester) async {
      final scenario = proxyTestScenario()..listUnavailable = true;
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      expect(find.byKey(const ValueKey('proxy_list_unavailable')), findsOne);
      expect(find.byType(ProxyDelegateRow), findsNothing);
      await _search(tester, 'alice_votes');
      expect(_row(proxyEntry(scenario, 'alice_votes').index), findsOne);
    });
  });

  group('PD-2 search', () {
    testWidgets('shows a match outside the list as Not reviewed', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      await _search(tester, '@kofi_m');
      final kofi = proxyEntry(scenario, 'kofi_m');
      expect(_row(kofi.index), findsOne);
      expect(
        find.descendant(of: _row(kofi.index), matching: find.text('@kofi_m')),
        findsOne,
      );
      expect(
        find.text(formatProxyDelegateId(kofi.index, kofi.key.fingerprint)),
        findsOne,
      );
      expect(find.text(testL10n.proxyNotReviewedLabel), findsOne);
      expect(find.text(testL10n.proxyNotReviewed), findsOne);
      expect(
        find.descendant(
          of: _row(kofi.index),
          matching: find.byType(ProxyIdenticon),
        ),
        findsOne,
      );
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('warns about lookalikes', (tester) async {
      final scenario = proxyTestScenario();
      await pumpProxyRoute(tester, _directory, scenario: scenario);
      final lookalike = proxyEntry(scenario, 'a1ice_votes');
      await _search(tester, 'a1ice_votes');
      expect(_row(lookalike.index), findsOne);
      expect(find.text(testL10n.proxyLookalike('alice_votes')), findsOne);
      expect(find.text(testL10n.proxyNewThisRoundLabel), findsOne);
    });
  });

  group('PD-2 paste or scan', () {
    testWidgets('a pasted key finds its delegate, who can be added', (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(
        tester,
        _directory,
        scenario: scenario,
      );
      final kofi = proxyEntry(scenario, 'kofi_m');
      await _paste(tester, mockProxyDelegateKey('kofi_m').dk);
      expect(_row(kofi.index), findsOne);
      await tester.tap(_pick(kofi.index));
      await settleProxy(tester);
      final draft = harness.container.read(
        proxyAllocationDraftProvider(kProxyTestKey),
      );
      expect(draft.contains(kofi.index), isTrue);
      expect(
        draft.toRequest(kProxyTestRoundId).choices.single,
        ProxyDelegateChoice(
          delegateIndex: kofi.index,
          percentBps: 0,
          provider: kofi.provider,
          handle: 'kofi_m',
          dk: kofi.key.dk,
        ),
        reason: 'the choice carries what the listing showed',
      );
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
      final listed = scenario.delegates
          .where((e) => scenario.listed.contains(e.index) && !e.blocked)
          .toList();
      for (final entry in listed.take(8)) {
        await tester.ensureVisible(_pick(entry.index));
        await tester.tap(_pick(entry.index));
        await settleProxy(tester);
      }
      expect(
        find.text(
          '${testL10n.proxyPickerCount(8)}. ${testL10n.proxyPickerFull}',
        ),
        findsOne,
      );
      for (final entry in listed.skip(8)) {
        expect(tester.widget<AppButton>(_pick(entry.index)).onPressed, isNull);
      }
      final notifier = harness.container.read(
        proxyAllocationDraftProvider(kProxyTestKey).notifier,
      );
      expect(notifier.toggle(listed.last), isFalse);
      expect(
        harness.container
            .read(proxyAllocationDraftProvider(kProxyTestKey))
            .delegates,
        hasLength(8),
      );
      final first = listed.first;
      await tester.ensureVisible(_pick(first.index));
      await tester.tap(_pick(first.index));
      await settleProxy(tester);
      expect(find.text(testL10n.proxyPickerCount(7)), findsOne);
      expect(
        tester.widget<AppButton>(_pick(listed.last.index)).onPressed,
        isNotNull,
      );
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
      await tester.tap(_pick(proxyEntry(scenario, 'alice_votes').index));
      await settleProxy(tester);
      await tester.tap(continueButton);
      await settleProxy(tester);
      expect(harness.location, proxyAllocationRoute(kProxyTestRoundId));
    });
  });

  group('PD-3 profile', () {
    testWidgets("shows Vizor's name, statement, handle and fingerprint", (
      tester,
    ) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(
        tester,
        _directory,
        scenario: scenario,
      );
      final alice = proxyEntry(scenario, 'alice_votes');
      await tester.tap(find.text('@alice_votes'));
      await settleProxy(tester);
      expect(
        harness.location,
        proxyDelegateProfileRoute(kProxyTestRoundId, alice.index),
      );
      expect(find.text('Alice Moreau'), findsOne);
      expect(find.text(alice.statement!), findsOne);
      expect(
        find.text(formatProxyDelegateId(alice.index, alice.key.fingerprint)),
        findsOne,
      );
      expect(find.text(testL10n.proxyProviderXLabel), findsOne);
      await tester.tap(find.byKey(const ValueKey('proxy_profile_toggle')));
      await settleProxy(tester);
      expect(find.text(testL10n.proxyRemoveFromDelegationLabel), findsOne);
      expect(
        harness.container
            .read(proxyAllocationDraftProvider(kProxyTestKey))
            .contains(alice.index),
        isTrue,
      );
    });
  });
}
