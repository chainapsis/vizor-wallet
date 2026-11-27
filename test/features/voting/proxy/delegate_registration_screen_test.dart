import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
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

  testWidgets('a link that is not a post never reaches the verifier', (
    tester,
  ) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending(),
    );
    await _submit(tester, 'https://x.com/alice_votes');
    expect(find.text(testL10n.delegateProofLinkXInvalid), findsOne);
    expect(harness.repository.attestCalls, 0);

    await tapDelegateKey(tester, 'delegate_provider_github');
    expect(find.text(testL10n.delegateMarkerGitHub), findsOne);
    expect(find.text(testL10n.delegateProofLinkGitHubLabel), findsOne);
    await _submit(tester, 'https://x.com/alice_votes/status/1');
    expect(find.text(testL10n.delegateProofLinkGitHubInvalid), findsOne);
    await _submit(tester, 'https://gist.github.com/alice/0a1b');
    expect(harness.repository.attestCalls, 1);
    expect(
      harness.scenario.status.entry?.provider,
      ProxyDelegateProvider.gitHub,
    );
  });

  testWidgets('each attester answer shows its one message', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending(),
    );
    final retryAfter = proxyUnixSeconds(DateTime(2026, 10, 8));
    for (final error in [...DelegateVerifierError.values, null]) {
      final answer = error == null
          ? const DelegateModeException(DelegateModeErrorKind.unavailable)
          : DelegateVerifierRefusal(
              error: error,
              retryAfter: retryAfter,
              detail: 'server text that is never shown',
            );
      harness.scenario.verifierErrors = [answer];
      await _submit(tester);
      expect(
        find.text(
          answer is DelegateVerifierRefusal
              ? delegateVerifierErrorText(testL10n, answer)
              : delegateVerifierErrorCopy(testL10n, null),
        ),
        findsOne,
        reason: '$error',
      );
      expect(find.textContaining('server text'), findsNothing);
    }
    expect(harness.repository.registerCalls, 0);
    expect(harness.scenario.status.registered, isFalse);
  });

  testWidgets('every chain rejection of REGISTER maps to its copy', (
    tester,
  ) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: _pending(),
    );
    for (final code in [59, 60, 61, 62, 64, 65, 66, 6]) {
      harness.scenario.registerResults = [
        DelegateRegisterResult.rejected(
          codespace: 'vote',
          code: code,
          reason: 'chain log',
        ),
      ];
      await _submit(tester);
      expect(
        find.text(delegateRegisterRejectionCopy(testL10n, 'vote', code)),
        findsOne,
        reason: 'code $code',
      );
      // A refused attestation needs a fresh check.
      expect(
        find.text(testL10n.delegateVerifyAgainLabel),
        const {64, 65}.contains(code) ? findsOne : findsNothing,
        reason: 'code $code',
      );
    }
    // A handle that already has a live entry says how that is resolved.
    expect(
      delegateRegisterRejectionCopy(testL10n, 'vote', 62),
      testL10n.delegateHandleTaken,
    );
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

  testWidgets('a device with nothing to register says so', (tester) async {
    await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: delegateRegisteredScenario(),
    );
    expect(find.text(testL10n.delegateNothingToRegister), findsOne);
  });

  testWidgets('a failed status load offers a retry', (tester) async {
    final scenario = _pending()
      ..statusError = const DelegateModeException(
        DelegateModeErrorKind.cannotVerify,
      );
    await pumpDelegateRoute(
      tester,
      kDelegateRegistrationPath,
      scenario: scenario,
    );
    expect(find.text(testL10n.proxyCannotVerify), findsOne);
    scenario.statusError = null;
    await tester.tap(find.text(testL10n.commonTryAgain));
    await settleProxy(tester);
    expect(find.byKey(const ValueKey('delegate_marker_text')), findsOne);
  });
}
