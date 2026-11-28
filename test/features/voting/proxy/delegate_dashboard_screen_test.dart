import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/delegate_reauth_gate.dart';

import '../../../support/test_l10n.dart';
import 'support/delegate_mode_test_harness.dart';
import 'support/proxy_values.dart';

const _round = kDelegateTestRoundId;

/// Inside the final-minutes window, where an unsubmitted ballot is warned.
const _threeMinutes = Duration(minutes: 3);

/// The text keyed [key].
String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// Whether the privacy overlay currently guards a shown export.
bool _exportGuarded(WidgetTester tester) => tester
    .widget<SensitivePrivacyOverlay>(find.byType(SensitivePrivacyOverlay))
    .sensitiveContentVisible;

void main() {
  group('DG-1 intro', () {
    testWidgets('Create stores a new key and opens its registration', (
      tester,
    ) async {
      final harness = await pumpDelegateRoute(tester, kDelegateModePath);
      await tapDelegateKey(tester, 'delegate_intro_create');
      expect(harness.scenario.status.key, isNotNull);
      expect(harness.repository.secret, startsWith('zvdsk1'));
      expect(harness.location, kDelegateRegistrationPath);
    });

    testWidgets('a key that cannot be created says so and stays on the '
        'intro', (tester) async {
      final harness = await pumpDelegateRoute(
        tester,
        kDelegateModePath,
        scenario: delegateFreshScenario()..createError = StateError('disk'),
      );
      await tapDelegateKey(tester, 'delegate_intro_create');
      expect(find.text(testL10n.delegateCreateKeyError), findsOne);
      expect(harness.location, kDelegateModePath);
    });

    testWidgets('a key awaiting registration continues there, and says when '
        'its registration was already sent', (tester) async {
      final harness = await pumpDelegateRoute(
        tester,
        kDelegateModePath,
        scenario: delegateUnregisteredScenario(registrationPending: true),
      );
      expect(
        find.byKey(const ValueKey('delegate_finish_registering')),
        findsOne,
      );
      expect(find.text(testL10n.delegateRegistrationPending), findsOne);
      await tapDelegateKey(tester, 'delegate_continue_registration');
      expect(harness.location, kDelegateRegistrationPath);
    });

    testWidgets('an unregistered key is removed only after its export shows, '
        'behind re-auth, and the user says it is saved', (tester) async {
      final harness = await pumpDelegateRoute(
        tester,
        kDelegateModePath,
        scenario: delegateUnregisteredScenario(),
      );
      expect(find.text(testL10n.delegateUseDifferentKeyLabel), findsOne);
      harness.reauth.allow = false;
      await tapDelegateKey(tester, 'delegate_start_over');
      expect(find.text(testL10n.delegateStartOverSaveKey), findsNothing);
      expect(harness.repository.exportCalls, 0);

      harness.reauth.allow = true;
      await tapDelegateKey(tester, 'delegate_start_over');
      expect(harness.reauth.prompts.last, DelegateReauthPurpose.exportKey);
      expect(find.text(testL10n.delegateStartOverSaveKey), findsOne);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('delegate_start_over_confirm')),
          matching: find.text(harness.repository.secret!),
        ),
        findsOne,
      );
      expect(_exportGuarded(tester), isTrue);
      final remove = find.byKey(const ValueKey('delegate_start_over_remove'));
      await tester.tap(remove);
      await settleProxy(tester);
      expect(harness.repository.startOverCalls, 0, reason: 'not saved yet');

      await tapDelegateKey(tester, 'delegate_start_over_saved');
      await tapDelegateKey(tester, 'delegate_start_over_remove');
      expect(harness.repository.startOverCalls, 1);
      expect(_exportGuarded(tester), isFalse);
      expect(find.byKey(const ValueKey('delegate_intro')), findsOne);
    });
  });

  group('DG-8 dashboard', () {
    testWidgets('shows "at least N" and whether the ballot is on chain', (
      tester,
    ) async {
      final harness = await pumpDelegateRoute(
        tester,
        kDelegateModePath,
        scenario: delegateRegisteredScenario(),
      );
      expect(find.byKey(const ValueKey('delegate_dashboard')), findsOne);
      expect(find.text('@alice_votes'), findsOne);
      expect(find.text('#17 · ${kDelegateTestKey.fingerprint}'), findsWidgets);
      expect(
        _text(tester, 'delegate_round_count_$_round'),
        'At least 3 delegations',
      );
      expect(
        _text(tester, 'delegate_round_ballot_$_round'),
        testL10n.proxyNoBallotYetLabel,
      );
      final voteEnd = harness.scenario.rounds.first.voteEndTime;
      expect(
        find.text(
          testL10n.delegateBallotReminder(
            formatProxyVoteEnd(testL10n, voteEnd),
          ),
        ),
        findsOne,
      );
      expectNoDelegateTotals(tester, countAllowed: true);
      await tapDelegateKey(tester, 'delegate_round_open_$_round');
      expect(harness.location, delegateBallotRoute(_round));
    });

    testWidgets('a submitted ballot reads as confirming while the app '
        'resends it, then as submitted', (tester) async {
      final scenario = delegateRegisteredScenario(
        rounds: [delegateTestRound(voteEnd: kProxyTestNow.add(_threeMinutes))],
      )..submitUnavailable = 1;
      scenario.rounds.first.storedBallot = [1, 2, 0];
      final harness = await pumpDelegateRoute(
        tester,
        kDelegateModePath,
        scenario: scenario,
      );
      expect(
        _text(tester, 'delegate_round_ballot_$_round'),
        testL10n.delegateBallotPendingLabel,
      );
      for (final key in [
        'delegate_round_reminder_$_round',
        'delegate_round_final_minutes_$_round',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
      }
      expect(find.text(testL10n.delegateViewBallotLabel), findsOne);

      // The first resend gets no answer; the next one lands.
      await tester.pump(kDelegateBallotResendInterval);
      await settleProxy(tester);
      expect(harness.repository.resent, hasLength(1));
      expect(
        _text(tester, 'delegate_round_ballot_$_round'),
        testL10n.delegateBallotPendingLabel,
      );
      await tester.pump(kDelegateBallotResendInterval);
      await settleProxy(tester);
      expect(harness.repository.resent, hasLength(2));
      expect(
        _text(tester, 'delegate_round_ballot_$_round'),
        testL10n.delegateBallotSubmittedLabel,
      );
      expect(harness.repository.submitted, isEmpty);
    });

    testWidgets("the chain's rejection of a resent ballot shows on its "
        'round', (tester) async {
      final scenario = delegateRegisteredScenario()
        ..submitResults = [ballotRejected(55, reason: 'chain log')];
      scenario.rounds.first.storedBallot = [1, 2, 0];
      final harness = await pumpDelegateRoute(
        tester,
        kDelegateModePath,
        scenario: scenario,
      );
      await tester.pump(kDelegateBallotResendInterval);
      await settleProxy(tester);
      expect(harness.repository.resent, hasLength(1));
      expect(
        find.byKey(const ValueKey('delegate_round_rejected_$_round')),
        findsOne,
      );
      expect(
        find.text(delegateBallotRejectionCopy(testL10n, 'vote', 55)),
        findsOne,
      );
      expect(find.text(testL10n.delegateBallotPendingLabel), findsNothing);
      await tester.pump(kDelegateBallotResendInterval);
      await settleProxy(tester);
      expect(harness.repository.resent, hasLength(1));
    });
  });

  group('the key', () {
    testWidgets('its export shows as text and a QR code only after '
        're-auth, and hides again', (tester) async {
      final harness = await pumpDelegateRoute(
        tester,
        kDelegateModePath,
        scenario: delegateRegisteredScenario(),
      );
      final export = find.byKey(const ValueKey('delegate_key_export'));
      expect(find.text(testL10n.delegateKeyBackup), findsOne);
      expect(export, findsNothing);

      harness.reauth.allow = false;
      await tapDelegateKey(tester, 'delegate_export_key');
      expect(harness.reauth.prompts, [DelegateReauthPurpose.exportKey]);
      expect(harness.repository.exportCalls, 0);
      expect(export, findsNothing);

      harness.reauth.allow = true;
      await tapDelegateKey(tester, 'delegate_export_key');
      expect(harness.repository.exportCalls, 1);
      expect(find.text(kDelegateTestSecret), findsOne);
      expect(
        // The package does not export its data view's type.
        (tester.widget(find.byKey(const ValueKey('delegate_key_export_qr')))
                as dynamic)
            .data,
        kDelegateTestSecret,
        reason: 'the QR code holds exactly the export',
      );
      expect(_exportGuarded(tester), isTrue);

      await tapDelegateKey(tester, 'delegate_hide_key');
      expect(find.text(kDelegateTestSecret), findsNothing);
      expect(_exportGuarded(tester), isFalse);

      // Leaving the dashboard hides a shown export.
      await tapDelegateKey(tester, 'delegate_export_key');
      expect(_exportGuarded(tester), isTrue);
      await tapDelegateKey(tester, 'delegate_round_open_$_round');
      harness.router.pop();
      await settleProxy(tester);
      expect(find.text(kDelegateTestSecret), findsNothing);
    });
  });

  testWidgets('a device whose entry is retired can start over with a new '
      'key', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateModePath,
      scenario: delegateRegisteredScenario(
        entryStatus: DelegateEntryStatus.retired,
      ),
    );
    expect(find.byKey(const ValueKey('delegate_retired')), findsOne);
    expect(find.text(testL10n.delegateRetired), findsOne);
    expect(find.text(testL10n.delegateStartOverLabel), findsOne);
    await tapDelegateKey(tester, 'delegate_start_over');
    expect(find.text(testL10n.delegateStartOver), findsOne);
    expect(harness.reauth.prompts, isEmpty, reason: 'no export step');
    await tapDelegateKey(tester, 'delegate_start_over_remove');
    expect(harness.repository.startOverCalls, 1);
    expect(find.byKey(const ValueKey('delegate_intro')), findsOne);
    await tapDelegateKey(tester, 'delegate_intro_create');
    expect(harness.location, kDelegateRegistrationPath);
  });
}
