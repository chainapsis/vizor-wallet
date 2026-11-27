import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_repository.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_copy.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/delegate_reauth_gate.dart';

import '../../../support/test_l10n.dart';
import 'support/delegate_mode_test_harness.dart';

/// The Retire button's handler, null while disabled.
VoidCallback? _retire(WidgetTester tester) => tester
    .widget<AppButton>(find.byKey(const ValueKey('delegate_retire_confirm')))
    .onPressed;

void main() {
  testWidgets('shows the Retire copy and the entry it retires', (tester) async {
    await pumpDelegateRoute(
      tester,
      kDelegateRetirePath,
      scenario: delegateRegisteredScenario(),
    );
    expect(find.text(testL10n.proxyRetire), findsOne);
    expect(find.text('#17 · ${kDelegateTestKey.fingerprint}'), findsOne);
    final button = tester.widget<AppButton>(
      find.byKey(const ValueKey('delegate_retire_confirm')),
    );
    expect(button.variant, AppButtonVariant.destructive);
    expect(find.text(testL10n.delegateRetireLabel), findsWidgets);
    expectNoDelegateTotals(tester);
  });

  testWidgets('pressing Retire still needs re-auth, and a dismissed one '
      'leaves Retire ready without an error', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRetirePath,
      scenario: delegateRegisteredScenario(),
      reauth: FakeDelegateReauth(allow: false),
    );
    await tapDelegateKey(tester, 'delegate_retire_confirm');
    expect(harness.reauth.prompts, [DelegateReauthPurpose.retire]);
    expect(harness.repository.retireCalls, 0);
    expect(find.text(testL10n.delegateRetireFailed), findsNothing);
    expect(_retire(tester), isNotNull);
  });

  testWidgets('confirmed Retire retires the entry, and the home then offers '
      'to start over', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRetirePath,
      scenario: delegateRegisteredScenario(),
    );
    await tapDelegateKey(tester, 'delegate_retire_confirm');
    expect(harness.repository.retireCalls, 1);
    expect(find.text(testL10n.delegateRetiredTitle), findsOne);
    expect(harness.scenario.status.retired, isTrue);
    await tapDelegateKey(tester, 'delegate_retired_back');
    expect(harness.location, kDelegateModePath);
    expect(find.byKey(const ValueKey('delegate_retired')), findsOne);
    expect(find.text(testL10n.delegateStartOverLabel), findsOne);
  });

  testWidgets('a suspended entry that cannot retire itself says so', (
    tester,
  ) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateRetirePath,
      scenario:
          delegateRegisteredScenario(entryStatus: DelegateEntryStatus.suspended)
            ..retireResults = [
              const DelegateRetireResult.rejected(
                codespace: 'vote',
                code: 54,
                reason: 'chain log',
              ),
            ],
    );
    await tapDelegateKey(tester, 'delegate_retire_confirm');
    expect(
      find.text(delegateRetireRejectionCopy(testL10n, 'vote', 54)),
      findsOne,
    );
    expect(harness.scenario.status.retired, isFalse);
    expect(_retire(tester), isNotNull);
  });

  testWidgets("a Retire that failed without the chain's verdict says it "
      'failed', (tester) async {
    await pumpDelegateRoute(
      tester,
      kDelegateRetirePath,
      scenario: delegateRegisteredScenario()
        ..retireError = const DelegateModeException(
          DelegateModeErrorKind.other,
        ),
    );
    await tapDelegateKey(tester, 'delegate_retire_confirm');
    expect(find.text(testL10n.delegateRetireFailed), findsOne);
  });

  testWidgets('a device with no entry, or a retired one, has nothing to '
      'retire', (tester) async {
    for (final scenario in [
      delegateFreshScenario(),
      delegateUnregisteredScenario(),
      delegateRegisteredScenario(entryStatus: DelegateEntryStatus.retired),
    ]) {
      await pumpDelegateRoute(tester, kDelegateRetirePath, scenario: scenario);
      expect(find.text(testL10n.delegateNothingToRetire), findsOne);
      expect(_retire(tester), isNull);
    }
  });
}
