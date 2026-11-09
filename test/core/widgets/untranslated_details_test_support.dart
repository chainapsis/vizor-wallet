import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/untranslated_details.dart';

import '../../support/test_l10n.dart';

/// Runs in both lanes: the desktop lane opens a dialog, the mobile lane a sheet.
void runUntranslatedDetailsTests() {
  const details = 'status: Unavailable, message: "tcp connect error"';

  Widget harness(Widget child) => MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('shows the untranslated text and copies it', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      harness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: untranslatedDetailsButton(details),
        ),
      ),
    );
    expect(find.text(details), findsNothing);

    await tester.tap(find.text(testL10n.commonShowDetails));
    await tester.pumpAndSettle();
    expect(find.text(testL10n.commonErrorDetailsTitle), findsOneWidget);
    expect(find.text(details), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('untranslated_details_copy')));
    await tester.pump();
    expect(copied, [details]);
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.byKey(const ValueKey('untranslated_details_close')));
    await tester.pumpAndSettle();
    expect(find.text(details), findsNothing);
  });

  testWidgets('adds nothing when there is no text', (tester) async {
    await tester.pumpWidget(
      harness(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...untranslatedDetailsButton(null),
            ...untranslatedDetailsButton('  '),
          ],
        ),
      ),
    );
    expect(find.byType(UntranslatedDetailsButton), findsNothing);
  });
}
