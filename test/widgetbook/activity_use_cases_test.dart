import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/widgetbook/activity_use_cases.dart';

void main() {
  testWidgets(
    'activity page use case renders the activity feed in app chrome',
    (tester) async {
      await _pumpActivityUseCase(tester, AppThemeData.light);

      expect(tester.takeException(), isNull);
      expect(find.byType(ActivityFeed), findsOneWidget);
      expect(find.text('Activity'), findsWidgets);
      expect(find.text('Filter'), findsOneWidget);

      final filterLabel = tester.widget<Text>(
        find.byKey(const ValueKey('activity_screen_filter_label')),
      );
      expect(filterLabel.style?.color, AppThemeData.light.colors.text.disabled);

      final filterIcon = tester.widget<AppIcon>(
        find.byKey(const ValueKey('activity_screen_filter_icon')),
      );
      expect(filterIcon.name, AppIcons.filter);
      expect(filterIcon.size, 16);
      expect(filterIcon.color, AppThemeData.light.colors.icon.disabled);

      final paneBackground = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('activity_page_pane_background')),
      );
      expect(
        paneBackground.color,
        AppThemeData.light.colors.macosUtility.window,
      );

      final paneTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey('activity_page_pane_background')),
      );
      final backTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey('activity_page_back_button')),
      );
      expect(backTopLeft.dx, paneTopLeft.dx + AppSpacing.sm);
      expect(backTopLeft.dy, paneTopLeft.dy + AppSpacing.xs);

      expect(find.text('This week'), findsOneWidget);
      expect(find.text('April 2026'), findsOneWidget);
      expect(find.text('Swapping...'), findsOneWidget);
      expect(find.text('USDC on Optimism'), findsOneWidget);
      expect(find.text('Received ZEC'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('activity_feed_child_connector')),
        findsOneWidget,
      );

      final positiveAmount = tester.widget<Text>(find.text('+31.10 ZEC'));
      expect(
        positiveAmount.style?.color,
        AppThemeData.light.colors.text.positiveStrong,
      );

      final childAmount = tester.widget<Text>(find.text('+12.13 ZEC'));
      expect(childAmount.style?.color, AppThemeData.light.colors.text.primary);
    },
  );

  testWidgets('activity page use case renders in dark theme', (tester) async {
    await _pumpActivityUseCase(tester, AppThemeData.dark);

    expect(tester.takeException(), isNull);
    expect(find.byType(ActivityFeed), findsOneWidget);
    expect(find.text('Activity'), findsWidgets);
  });
}

Future<void> _pumpActivityUseCase(
  WidgetTester tester,
  AppThemeData theme,
) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: theme,
        child: Center(
          child: SizedBox(
            width: 1080,
            height: 720,
            child: Builder(builder: buildActivityPageUseCase),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
