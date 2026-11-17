import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';

var _nextDesktopOnboardingPointer = 9000;

/// Completes import personalisation, or observes creation reaching security/Home.
Future<void> finishDesktopAccountCustomisation(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  final finishButton = find.byKey(
    const ValueKey('customise_account_finish_button'),
  );
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    if (find
            .byKey(const ValueKey('set_password_password_field'))
            .hitTestable()
            .evaluate()
            .isNotEmpty ||
        find
            .byKey(const ValueKey('home_desktop_send_button'))
            .hitTestable()
            .evaluate()
            .isNotEmpty ||
        find
            .byKey(const ValueKey('home_desktop_receive_first_button'))
            .hitTestable()
            .evaluate()
            .isNotEmpty) {
      return;
    }
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
