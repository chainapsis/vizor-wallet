import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';

var _nextDesktopOnboardingPointer = 9000;

/// Opens ordinary creation through the Welcome accent button's actual action.
/// Its stable key belongs to a Semantics wrapper, not to the inner AppButton.
Future<void> openDesktopWalletCreation(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 20),
}) => _tapDesktopOnboardingAction(
  tester,
  find.descendant(
    of: find.byKey(const ValueKey('welcome_create_wallet_button')),
    matching: find.byType(AppButton),
  ),
  description: 'Welcome create action',
  timeout: timeout,
);

/// Opens software import from either Welcome or the additional-account entry.
///
/// Desktop now requires selecting an import method before the phrase fields
/// appear. Drive both production screens instead of bypassing the selector.
Future<void> openDesktopSecretPassphraseImport(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  for (final key in const [
    ValueKey('welcome_import_wallet_button'),
    ValueKey('desktop_import_secret_passphrase_card'),
  ]) {
    await _tapDesktopOnboardingAction(
      tester,
      find.byKey(key),
      description: 'desktop import action $key',
      timeout: timeout,
    );
  }
}

Future<void> _tapDesktopOnboardingAction(
  WidgetTester tester,
  Finder finder, {
  required String description,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!finder.evaluate().any(
    (element) =>
        element.widget is! AppButton ||
        (element.widget as AppButton).onPressed != null,
  )) {
    if (!DateTime.now().isBefore(deadline)) {
      fail('Timed out waiting for $description.');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder, pointer: _nextDesktopOnboardingPointer++);
  await tester.pump(const Duration(milliseconds: 250));
}

/// Completes the account name/profile step that finalizes desktop onboarding.
///
/// Password submission only routes to this screen; the wallet is not created
/// or imported until the user finishes account customisation.
Future<void> finishDesktopAccountCustomisation(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  final finishButton = find.byKey(
    const ValueKey('customise_account_finish_button'),
  );
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    final enabled = finishButton.evaluate().any(
      (element) =>
          element.widget is AppButton &&
          (element.widget as AppButton).onPressed != null,
    );
    if (enabled) {
      await tester.ensureVisible(finishButton);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finishButton, pointer: _nextDesktopOnboardingPointer++);
      await tester.pump(const Duration(milliseconds: 250));
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail('Timed out waiting for desktop account customisation to be enabled.');
}
