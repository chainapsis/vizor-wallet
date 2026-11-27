import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';

import '../../../support/test_l10n.dart';
import 'support/delegate_mode_test_harness.dart';
import 'support/mock_delegate_mode_repository.dart';
import 'support/proxy_values.dart';

/// A device with no key, where [kDelegateTestSecret] imports [status].
DelegateModeMockScenario _importing(DelegateModeView status) =>
    delegateFreshScenario()..importable[kDelegateTestSecret] = status;

/// Types [text] into the key field and taps Import.
Future<void> _import(WidgetTester tester, String text) async {
  await tester.enterText(delegateField('delegate_import_key'), text);
  await settleProxy(tester);
  await tapDelegateKey(tester, 'delegate_import_submit');
}

void main() {
  testWidgets('text that is not an exported key is refused and stores '
      'nothing', (tester) async {
    final harness = await pumpDelegateRoute(tester, kDelegateKeyImportPath);
    expect(find.text(testL10n.delegateImport), findsOne);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('delegate_import_submit')),
          )
          .onPressed,
      isNull,
    );
    for (final text in [kDelegateTestKey.dk, 'abandon abandon about']) {
      await _import(tester, text);
      expect(find.text(testL10n.delegateImportInvalid), findsOne, reason: text);
    }
    expect(harness.repository.secret, isNull);
    expect(harness.scenario.status.key, isNull);
    expect(
      tester
          .widget<SensitivePrivacyOverlay>(find.byType(SensitivePrivacyOverlay))
          .sensitiveContentVisible,
      isTrue,
      reason: 'a typed key is covered when the app leaves the foreground',
    );
  });

  testWidgets('an exported key that is registered opens the dashboard', (
    tester,
  ) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateKeyImportPath,
      scenario: _importing(delegateRegisteredScenario().status),
    );
    await _import(tester, ' $kDelegateTestSecret ');
    expect(find.text(testL10n.delegateImportedTitle), findsOne);
    expect(find.text('#17 · ${kDelegateTestKey.fingerprint}'), findsOne);
    expect(find.text(kDelegateTestSecret), findsNothing);
    expect(harness.repository.secret, kDelegateTestSecret);
    await tapDelegateKey(tester, 'delegate_import_continue');
    expect(harness.location, kDelegateModePath);
    expect(find.byKey(const ValueKey('delegate_dashboard')), findsOne);
  });

  testWidgets('an exported key that is not registered continues to its '
      'registration', (tester) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateKeyImportPath,
      scenario: _importing(delegateModeView(key: kDelegateTestKey)),
    );
    await _import(tester, kDelegateTestSecret);
    expect(find.text(testL10n.delegateImportedUnregistered), findsOne);
    expect(find.text(kDelegateTestKey.fingerprint), findsOne);
    await tapDelegateKey(tester, 'delegate_import_continue');
    expect(harness.location, kDelegateRegistrationPath);
  });

  testWidgets('a retired entry imports back to the start-over state', (
    tester,
  ) async {
    final harness = await pumpDelegateRoute(
      tester,
      kDelegateKeyImportPath,
      scenario: _importing(
        delegateRegisteredScenario(
          entryStatus: DelegateEntryStatus.retired,
        ).status,
      ),
    );
    await _import(tester, kDelegateTestSecret);
    await tapDelegateKey(tester, 'delegate_import_continue');
    expect(harness.location, kDelegateModePath);
    expect(find.byKey(const ValueKey('delegate_retired')), findsOne);
  });
}
