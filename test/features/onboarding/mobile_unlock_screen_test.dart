@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_unlock_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobileUnlockScreen(),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('help opens the forgot-passcode reset sheet', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Passcode help'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot Passcode?'), findsOneWidget);
    expect(find.text('Continue to reset Vizor'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Passcode?'), findsNothing);
  });

  testWidgets('renders the numpad and fills dots while typing', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Digit 1'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Digit 2'));
    await tester.pump();

    final dots = tester.widget<PasscodeDots>(find.byType(PasscodeDots));
    expect(dots.filled, 2);

    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pump();
    final after = tester.widget<PasscodeDots>(find.byType(PasscodeDots));
    expect(after.filled, 1);

    // Delete hides again once the entry is cleared.
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pump();
    expect(find.bySemanticsLabel('Delete digit'), findsNothing);
  });
}
