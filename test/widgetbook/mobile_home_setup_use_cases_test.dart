@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/widgetbook/screen_use_cases.dart';

Widget _app(WidgetBuilder builder) => MaterialApp(
  home: AppTheme(
    data: AppThemeData.dark,
    child: Builder(builder: builder),
  ),
);

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(393, 852);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'manual Home carousel opens real Zcash pages and keeps backup after Skip',
    (tester) async {
      await tester.pumpWidget(_app(buildMobileHomeBackupAndEducationUseCase));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(
        find.byKey(const ValueKey('mobile_home_zcash_education')),
        findsNothing,
      );
      await tester.fling(
        find.byKey(const ValueKey('mobile_home_backup')),
        const Offset(-100, 0),
        500,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_home_zcash_education')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileOnboardingIntroScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile_intro_skip')));
      await tester.pumpAndSettle();
      expect(find.byType(MobileHomeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile_home_carousel_indicator_1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile_home_zcash_education')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'snoozing backup returns Home with the education entry still available',
    (tester) async {
      await tester.pumpWidget(_app(buildMobileHomeBackupAndEducationUseCase));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile_home_backup')));
      await tester.pumpAndSettle();
      expect(find.byType(MobileSeedPhraseScreen), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('mobile_seed_backup_remind_later')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileHomeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile_home_zcash_education')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile_home_carousel_indicator_1')),
        findsNothing,
      );
    },
  );

  testWidgets('one remaining education card has no carousel controls', (
    tester,
  ) async {
    await tester.pumpWidget(_app(buildMobileHomeEducationOnlyUseCase));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_home_zcash_education')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile_home_backup')), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_home_carousel_indicator_0')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
