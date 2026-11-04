import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/near_intents_service_notice_host.dart';
import 'support/service_notice_widget_checks.dart';
import 'support/service_status_fixture.dart';

void main() {
  serviceNoticeWidgetChecks();
  testWidgets(
    'desktop notice uses the pane scrim, standard card and Escape dismissal',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1080, 720);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nearIntentsServiceStatusProvider.overrideWith(
              () => FixtureServiceStatusNotifier(serviceStatusFixture()),
            ),
          ],
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Row(
                children: [
                  const SizedBox(width: 272),
                  Expanded(
                    child: NearIntentsServiceNoticeHost(
                      direction: SwapDirection.zecToExternal,
                      externalAsset: SwapAsset.usdc,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final overlay = tester.getRect(find.byType(AppPaneModalOverlay));
      final card = tester.getRect(find.byType(AppModalCard));
      expect(overlay, const Rect.fromLTWH(272, 0, 808, 720));
      expect(card.width, kAppModalCardWidth);
      expect(card.center, overlay.center);
      final scrim = find.descendant(
        of: find.byType(AppPaneModalOverlay),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  AppThemeData.dark.colors.background.neutralScrim,
        ),
      );
      expect(scrim, findsOneWidget);
      expect(
        tester.widget<AppModalCard>(find.byType(AppModalCard)).highlight,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('app_modal_inner_highlight')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AppPaneModalOverlay), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
