@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_passcode_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobilePasscodeScreen(
        args: SetPasswordScreenArgs.create(mnemonic: 'stub mnemonic words'),
      ),
    ),
  );
}

Future<void> _enter(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $d'));
    await tester.pump();
  }
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('six digits advance to the confirm phase', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Create Passcode'), findsOneWidget);
    final createTitle = tester.widget<Text>(find.text('Create Passcode'));
    expect(createTitle.style?.fontSize, AppTypography.displayLarge.fontSize);
    await _enter(tester, '12345');
    // Backspace removes a digit before completion.
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pump();
    await _enter(tester, '56');

    expect(find.text('Confirm Passcode'), findsOneWidget);
    final confirmTitle = tester.widget<Text>(find.text('Confirm Passcode'));
    expect(confirmTitle.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(find.text('Re-enter your passcode.'), findsOneWidget);
  });

  testWidgets('a mismatched confirmation restarts with an error', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await _enter(tester, '123456');
    expect(find.text('Confirm Passcode'), findsOneWidget);

    await _enter(tester, '654321');
    expect(find.text('Create Passcode'), findsOneWidget);
    expect(find.text("Passcodes didn't match. Try again."), findsOneWidget);
  });
}
