import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_carousel.dart';
import 'package:zcash_wallet/src/features/home/screens/home_screen.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_seed_phrase_screen.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

import '../support/payment_links_screen_support.dart'
    show loadPaymentLinksTestFonts;

void main() {
  setUpAll(loadPaymentLinksTestFonts);
  testWidgets('Home actions defer backup and finish education independently', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(builder: buildDesktopHomeSetupUseCase),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app_carousel_card_0')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSeedPhraseScreen), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('desktop_seed_backup_remind_later')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    final remaining = tester.widget<AppCarousel>(find.byType(AppCarousel));
    expect(remaining.items, hasLength(1));
    expect(remaining.items.single.message, contains('Learn how Zcash'));
    await tester.tap(find.byKey(const ValueKey('app_carousel_card_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop_education_skip')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AppCarousel), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final importing in [false, true]) {
    testWidgets(
      'desktop Home setup actions fit before scrolling, importing=$importing',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1080, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Builder(
                builder: importing
                    ? buildDesktopHomeSetupImportingUseCase
                    : buildDesktopHomeSetupUseCase,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppCarousel), findsOneWidget);
        final bounds = tester.getRect(find.byType(AppCarousel));
        expect(bounds.bottom, lessThanOrEqualTo(720));
        expect(
          tester.widget<AppCarousel>(find.byType(AppCarousel)).autoplay,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
