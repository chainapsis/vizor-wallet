@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sync_status.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

void main() {
  testWidgets(
    'sidebar mirrors bar and label, preserves motion and long accessible labels',
    (tester) async {
      const status = SyncStatusLabel(
        kind: SyncStatusKind.syncing,
        label: 'Syncing a very long account status that must wrap',
        semanticsLabel: 'Full sync status',
      );
      Future<void> pump(bool reduced, bool leading) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Center(
                  child: SizedBox(
                    width: 232,
                    child: Builder(
                      builder: (context) => MobileSyncStatus.fromStatus(
                        context: context,
                        status: status,
                        leading: leading,
                        wrapLabel: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
      }

      await pump(false, true);
      final bar = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 6 &&
            w.constraints?.maxHeight == 50,
      );
      expect(bar, findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(
        tester.getRect(bar).right,
        lessThan(tester.getRect(find.text(status.label)).left),
      );
      expect(
        tester.widget<Text>(find.text(status.label)).textAlign,
        TextAlign.left,
      );
      final leading = tester.widget<Container>(bar).decoration as BoxDecoration;
      expect(
        leading.borderRadius,
        const BorderRadius.horizontal(right: Radius.circular(3)),
      );
      expect(find.bySemanticsLabel(status.semanticsLabel), findsOneWidget);
      final firstGlow = leading.boxShadow!.single;
      await tester.pump(const Duration(milliseconds: 350));
      final laterGlow =
          (tester.widget<Container>(bar).decoration as BoxDecoration)
              .boxShadow!
              .single;
      expect(laterGlow, isNot(firstGlow));
      await pump(true, true);
      expect(find.byType(ShaderMask), findsNothing);
      expect(
        tester.widget<Text>(find.text(status.label)).style,
        AppTypography.labelMedium.copyWith(
          color: AppThemeData.light.colors.sync.textSyncing,
        ),
      );
      await pump(true, false);
      expect(
        tester.getRect(bar).left,
        greaterThan(tester.getRect(find.text(status.label)).right),
      );
      expect(
        (tester.widget<Container>(bar).decoration as BoxDecoration)
            .borderRadius,
        const BorderRadius.horizontal(left: Radius.circular(3)),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
