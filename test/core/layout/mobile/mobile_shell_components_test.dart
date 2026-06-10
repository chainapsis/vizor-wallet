@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

void main() {
  testWidgets('MobileTopNav.account shows name, balance, and sync label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MobileTopNav.account(
          accountName: 'Account1',
          balanceLabel: '140.12 ZEC',
          syncLabel: 'Vizor is synced',
        ),
      ),
    );

    expect(find.text('Account1'), findsOneWidget);
    expect(find.text('140.12 ZEC'), findsOneWidget);
    expect(find.text('Vizor is synced'), findsOneWidget);

    final name = tester.widget<Text>(find.text('Account1'));
    expect(name.style?.color, AppThemeData.dark.colors.text.accent);
    final sync = tester.widget<Text>(find.text('Vizor is synced'));
    expect(sync.style?.color, AppThemeData.dark.colors.sync.text);
  });

  testWidgets('MobileTopNav.back shows serif title and fires onBack', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(
      _harness(MobileTopNav.back(title: 'Activity', onBack: () => backs++)),
    );

    final title = tester.widget<Text>(find.text('Activity'));
    expect(title.style?.fontFamily, AppTypography.headlineMedium.fontFamily);
    expect(title.style?.fontSize, AppTypography.headlineMedium.fontSize);

    await tester.tap(find.bySemanticsLabel('Back'));
    expect(backs, 1);
  });

  testWidgets('MobileTopNav.steps clamps and renders progress', (tester) async {
    await tester.pumpWidget(_harness(const MobileTopNav.steps(progress: 0.5)));

    final fill = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fill.widthFactor, 0.5);
  });

  testWidgets('AppMobileTabBar highlights current item and reports taps', (
    tester,
  ) async {
    final taps = <int>[];
    const items = [
      AppMobileTabItem(iconName: 'home', label: 'Home'),
      AppMobileTabItem(iconName: 'swap_arrows', label: 'Swap'),
      AppMobileTabItem(iconName: 'history', label: 'Activity'),
      AppMobileTabItem(iconName: 'cog', label: 'Settings'),
    ];
    await tester.pumpWidget(
      _harness(
        SizedBox(
          width: 361,
          child: AppMobileTabBar(
            items: items,
            currentIndex: 0,
            onSelect: taps.add,
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Activity'));
    expect(taps, [2]);

    final containers = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .toList();
    expect(containers, hasLength(4));
    final activeDecoration =
        (containers.first.decoration ?? const BoxDecoration()) as BoxDecoration;
    expect(activeDecoration.color, AppThemeData.dark.colors.navPanel.activeBg);
    final inactiveDecoration =
        (containers.last.decoration ?? const BoxDecoration()) as BoxDecoration;
    expect(inactiveDecoration.color, isNull);
  });

  testWidgets('AppMobileShell extends body behind the floating tab bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        AppMobileShell(
          body: const SizedBox.expand(),
          tabBar: AppMobileTabBar(
            items: const [
              AppMobileTabItem(iconName: 'home', label: 'Home'),
              AppMobileTabItem(iconName: 'cog', label: 'Settings'),
            ],
            currentIndex: 0,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBody, isTrue);
    expect(find.byType(AppMobileTabBar), findsOneWidget);
  });

  testWidgets('showAppMobileSheet presents and dismisses content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => GestureDetector(
            onTap: () => showAppMobileSheet<void>(
              context: context,
              builder: (_) => const SizedBox(
                height: 200,
                child: Center(child: Text('Sheet content')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Sheet content'), findsOneWidget);

    // Dismiss by tapping the barrier above the sheet.
    await tester.tapAt(const Offset(200, 50));
    await tester.pumpAndSettle();
    expect(find.text('Sheet content'), findsNothing);
  });
}

Widget _harness(Widget child) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.dark,
      child: Center(child: child),
    ),
  );
}
