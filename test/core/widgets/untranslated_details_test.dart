import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/content_overlay_inset.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/untranslated_details.dart';

import '../../support/test_l10n.dart';
import 'untranslated_details_test_support.dart';

void main() {
  runUntranslatedDetailsTests();

  testWidgets('dims only the content pane beside the sidebar', (tester) async {
    tester.view.physicalSize = const Size(1080, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
        home: ContentOverlayInset(
          leftInset: 272,
          rightInset: 8,
          child: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: untranslatedDetailsButton('tcp connect error'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(testL10n.commonShowDetails));
    await tester.pumpAndSettle();

    final scrim = tester.getRect(
      find.byKey(const ValueKey('untranslated_details_scrim')),
    );
    expect(scrim, const Rect.fromLTRB(272, 8, 1072, 712));
    final card = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('untranslated_details_dialog')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.center.dx, closeTo(scrim.center.dx, 0.5));
    expect(card.left, greaterThan(scrim.left));

    // The sidebar stays visible; clicking it closes the dialog.
    await tester.tapAt(const Offset(120, 360));
    await tester.pumpAndSettle();
    expect(find.text(testL10n.commonErrorDetailsTitle), findsNothing);

    // Release the published inset before the next test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
