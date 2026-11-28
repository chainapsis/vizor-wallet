import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/delegate_reauth_gate.dart';

import '../../../support/test_l10n.dart';
import 'support/delegate_mode_test_harness.dart';
import 'support/mock_delegate_mode_repository.dart';

/// The key every registration test registers.
final _newKey = kDelegateTestKey;

/// A device whose key awaits its registration.
DelegateModeMockScenario _pending() => delegateUnregisteredScenario();

/// The marker on screen.
String _marker(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('delegate_marker_text')))
    .data!;

/// Types [link] and taps "Verify and register".
Future<void> _submit(
  WidgetTester tester, [
  String link = 'https://x.com/alice_votes/status/1790',
]) async {
  await tester.enterText(delegateField('delegate_proof_link'), link);
  await settleProxy(tester);
  await tapDelegateKey(tester, 'delegate_register_submit');
}

void main() {
  testWidgets('a registration posts the one marker and gets #17', (
    tester,
  ) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending(),
    );
    expect(_marker(tester), 'zcash-vote-delegate v1 ${_newKey.dk}');
    expect(find.text(testL10n.delegateMarkerX), findsOne);
    expect(find.text(testL10n.delegateKeepPost), findsOne);
    expect(find.text(_newKey.fingerprint), findsOne);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('delegate_register_submit')),
          )
          .onPressed,
      isNull,
    );

    await _submit(tester);
    expect(harness.repository.attestCalls, 1);
    expect(harness.repository.registerCalls, 1);
    expect(harness.repository.proofUrls, [
      'https://x.com/alice_votes/status/1790',
    ]);
    expect(find.text(testL10n.delegateRegisteredTitle), findsOne);
    expect(find.text('#17 · ${_newKey.fingerprint}'), findsOne);
    expect(find.text(testL10n.delegateRegistered('alice_votes')), findsOne);
    expect(find.text(testL10n.delegateHowPeopleFindYou), findsOne);
    expectNoDelegateTotals(tester);

    await tapDelegateKey(tester, 'delegate_registered_open');
    expect(harness.location, kDelegateModePath);
  });

  testWidgets("an attester refusal shows its message, never the attester's "
      'own text', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending(),
    );
    const refusal = DelegateVerifierRefusal(
      error: DelegateVerifierError.markerMismatch,
      detail: 'server text that is never shown',
    );
    harness.scenario.verifierErrors = [refusal];
    await _submit(tester);
    expect(find.text(delegateVerifierErrorText(testL10n, refusal)), findsOne);
    expect(find.textContaining('server text'), findsNothing);
    expect(harness.repository.registerCalls, 0);
    expect(harness.scenario.status.registered, isFalse);
  });

  testWidgets('a chain rejection of REGISTER shows its copy, and a refused '
      'attestation asks for a new check', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending(),
    );
    harness.scenario.registerResults = [
      const DelegateRegisterResult.rejected(
        codespace: 'vote',
        code: 64,
        reason: 'chain log',
      ),
    ];
    await _submit(tester);
    expect(
      find.text(delegateRegisterRejectionCopy(testL10n, 'vote', 64)),
      findsOne,
    );
    expect(find.text(testL10n.delegateVerifyAgainLabel), findsOne);
    expect(harness.scenario.status.registered, isFalse);
    await _submit(tester);
    expect(find.text('#17 · ${_newKey.fingerprint}'), findsOne);
  });

  testWidgets("a registration that failed without the chain's verdict is "
      'not shown as its rejection', (tester) async {
    await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending()
        ..registerError = const DelegateModeException(
          DelegateModeErrorKind.other,
        ),
    );
    await _submit(tester);
    expect(find.text(testL10n.delegateRegisterFailed), findsOne);
    expect(find.text(testL10n.delegateRegisterRejected), findsNothing);
  });

  testWidgets("registering signs after the app's re-auth, and a dismissed "
      're-auth is not an error', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending(),
    );
    harness.reauth.allow = false;
    await _submit(tester);
    expect(harness.reauth.prompts, [DelegateReauthPurpose.register]);
    expect(harness.repository.registerCalls, 0);
    expect(find.byKey(const ValueKey('delegate_register_error')), findsNothing);

    harness.reauth.allow = true;
    await _submit(tester);
    expect(harness.reauth.prompts, hasLength(2));
    expect(find.text('#17 · ${_newKey.fingerprint}'), findsOne);
  });
}
