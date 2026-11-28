@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_route_table.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/delegate_reauth_gate.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';

import '../../../figma_compare/figma_compare_font_loader.dart';
import '../../../support/test_l10n.dart';
import 'support/delegate_mode_fakes.dart';
import 'support/delegate_mode_test_harness.dart';
import 'support/mock_delegate_mode_repository.dart';

const _phone = Size(393, 852);

/// The production mobile route table plus a voting page.
List<RouteBase> _mobileRoutes() => [
  GoRoute(
    path: '/voting',
    builder: (_, _) => const Scaffold(body: Text('voting')),
  ),
  ...delegateModeMobileRoutes(guard: (child) => child),
];

/// Pumps [location] through the production mobile route table on a phone.
Future<DelegateTestHarness> _pumpMobile(
  WidgetTester tester,
  String location, {
  DelegateModeMockScenario? scenario,
  double textScale = 1,
}) => pumpDelegateRoute(
  tester,
  location,
  scenario: scenario,
  size: _phone,
  routes: _mobileRoutes(),
  textScale: textScale,
);

/// Biometrics off, so the gate offers only the numpad.
class _NoBiometrics extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async => BiometricUnlockState.initial;
}

void main() {
  setUpAll(loadFigmaCompareFonts);

  test('runs with mobile tokens', () {
    expect(kAppFormFactor, AppFormFactor.mobile);
  });

  testWidgets('DG-9 and the DG-10 sheet on a phone', (tester) async {
    final harness = await _pumpMobile(
      tester,
      delegateBallotRoute(kDelegateTestRoundId),
      scenario: delegateRegisteredScenario(),
    );
    expect(
      find.widgetWithText(MobileTopNav, testL10n.delegateBallotTitle),
      findsOne,
    );
    final submit = find.byKey(const ValueKey('delegate_ballot_submit'));
    expect(tester.widget<AppButton>(submit).onPressed, isNull);
    for (final MapEntry(key: id, value: option) in {1: 1, 2: 2}.entries) {
      await tapDelegateKey(tester, 'voting_proposal_${id}_option_$option');
    }
    expect(tester.widget<AppButton>(submit).onPressed, isNull);
    await tapDelegateKey(tester, 'voting_proposal_3_option_0');
    expect(tester.widget<AppButton>(submit).onPressed, isNotNull);
    await tapDelegateKey(tester, 'delegate_ballot_submit');

    expect(find.byKey(const ValueKey('delegate_ballot_confirm')), findsOne);
    expect(find.text(testL10n.delegateBallotConfirmTitle), findsOne);
    expect(find.text(testL10n.proxyBallotConfirm(3)), findsOne);
    await tapDelegateKey(tester, 'delegate_confirm_submit');
    expect(harness.reauth.prompts, [DelegateReauthPurpose.signBallot]);
    expect(harness.repository.submitted, [
      [1, 2, 0],
    ]);
    expect(find.byKey(const ValueKey('delegate_ballot_confirm')), findsNothing);
    expect(find.text(testL10n.delegateBallotSubmittedTitle), findsOne);
    await tapDelegateKey(tester, 'delegate_ballot_done');
    expect(harness.location, kDelegateModePath);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the delegate screens fit a phone at 200% text', (tester) async {
    for (final location in [
      kDelegateModePath,
      delegateBallotRoute(kDelegateTestRoundId),
      kDelegateRetirePath,
    ]) {
      await _pumpMobile(
        tester,
        location,
        scenario: delegateRegisteredScenario(),
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: location);
    }
    // The key's export, with its QR code, and the start-over confirmation.
    await tapDelegateKey(tester, 'delegate_retire_confirm');
    await tapDelegateKey(tester, 'delegate_retired_back');
    await tapDelegateKey(tester, 'delegate_export_key');
    expect(find.byKey(const ValueKey('delegate_key_export')), findsOne);
    expect(tester.takeException(), isNull);
    await tapDelegateKey(tester, 'delegate_start_over');
    expect(find.byKey(const ValueKey('delegate_start_over_confirm')), findsOne);
    expect(tester.takeException(), isNull);

    for (final location in [kDelegateModePath, kDelegateRegistrationPath]) {
      await _pumpMobile(
        tester,
        location,
        scenario: delegateUnregisteredScenario(registrationPending: true),
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: location);
    }
    for (final location in [kDelegateModePath, kDelegateKeyImportPath]) {
      await _pumpMobile(
        tester,
        location,
        scenario: delegateFreshScenario(),
        textScale: 2,
      );
      expect(tester.takeException(), isNull, reason: location);
    }
  });

  testWidgets('the production gate takes the passcode on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _phone;
    addTearDown(tester.view.reset);
    final results = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSecurityProvider.overrideWith(
            () => FakeDelegateSecurity(password: '123456'),
          ),
          biometricUnlockProvider.overrideWith(_NoBiometrics.new),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          builder: (context, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async => results.add(
                  await ref.read(delegateReauthProvider)(
                    context,
                    DelegateReauthPurpose.signBallot,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(testL10n.settingsEnterPasscodeTitle), findsOne);
    expect(
      find.text(DelegateReauthPurpose.signBallot.subtitle(testL10n)),
      findsOne,
    );

    /// Taps each of [digits] on the numpad.
    Future<void> type(String digits) async {
      for (final digit in digits.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await type('111111');
    expect(find.text(testL10n.settingsIncorrectPasscode), findsOne);
    expect(results, isEmpty);
    await type('123456');
    expect(results, [true]);
    expect(find.text(testL10n.settingsEnterPasscodeTitle), findsNothing);
  });
}
