@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';

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

  testWidgets('MobileTopNav.account syncing shimmers the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MobileTopNav.account(
          accountName: 'Account1',
          syncLabel: '20% Syncing...',
          syncLabelColor: AppThemeData.dark.colors.sync.textSyncing,
          syncIndicatorColor: AppThemeData.dark.colors.text.muted,
          syncHighlightColor: AppThemeData.dark.colors.sync.lightSuccess,
          syncAnimated: true,
        ),
      ),
    );
    // Let the looping controller advance a few frames (never pumpAndSettle:
    // the animation repeats forever and would time out).
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.text('20% Syncing...'), findsOneWidget);
    // The label is wrapped in a shimmer ShaderMask over a solid-color Text.
    expect(find.byType(ShaderMask), findsOneWidget);
    final label = tester.widget<Text>(find.text('20% Syncing...'));
    expect(label.style?.color, const Color(0xFFFFFFFF));

    // Unmount so the active ticker is disposed cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('MobileTopNav.account syncing is static under reduce-motion', (
    tester,
  ) async {
    final mutedGreen = AppThemeData.dark.colors.sync.textSyncing;
    final greyBar = AppThemeData.dark.colors.text.muted;
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: MobileTopNav.account(
              accountName: 'Account1',
              syncLabel: '20% Syncing...',
              syncLabelColor: mutedGreen,
              syncIndicatorColor: greyBar,
              syncHighlightColor: AppThemeData.dark.colors.sync.lightSuccess,
              syncAnimated: true,
            ),
          ),
        ),
      ),
    );

    // No shimmer mask; the label keeps its muted green base and the edge bar
    // is a neutral grey. The brighter shimmer peak only appears in the
    // animated state.
    expect(find.byType(ShaderMask), findsNothing);
    final label = tester.widget<Text>(find.text('20% Syncing...'));
    expect(label.style?.color, mutedGreen);

    final greyBars = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == greyBar,
        );
    expect(greyBars, isNotEmpty);
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

  testWidgets('MobileTopNav.back accepts a title style override', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MobileTopNav.back(
          title: 'Swap in progress...',
          titleStyle: AppTypography.headlineLarge,
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Swap in progress...'));
    expect(title.style?.fontFamily, AppTypography.headlineLarge.fontFamily);
    expect(title.style?.fontSize, AppTypography.headlineLarge.fontSize);
  });

  testWidgets('MobileTopNav.steps clamps and renders progress', (tester) async {
    await tester.pumpWidget(_harness(const MobileTopNav.steps(progress: 0.5)));

    final fill = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fill.widthFactor, 0.5);
  });

  testWidgets('AppMobileTabBar slides the pill and tints the active icon', (
    tester,
  ) async {
    final taps = <int>[];
    const items = [
      AppMobileTabItem(iconName: 'home', label: 'Home'),
      AppMobileTabItem(iconName: 'swap_arrows', label: 'Swap'),
      AppMobileTabItem(iconName: 'history', label: 'Activity'),
      AppMobileTabItem(iconName: 'cog', label: 'Settings'),
    ];
    Widget bar(int index) => _harness(
      SizedBox(
        width: 361,
        child: AppMobileTabBar(
          items: items,
          currentIndex: index,
          onSelect: taps.add,
        ),
      ),
    );
    Alignment pillAlignment() =>
        tester
                .widget<AnimatedAlign>(
                  find.byKey(AppMobileTabBar.activePillKey),
                )
                .alignment
            as Alignment;
    List<AppIcon> icons() =>
        tester.widgetList<AppIcon>(find.byType(AppIcon)).toList();

    await tester.pumpWidget(bar(0));

    // One shared pill carries the active decoration, parked on item 0.
    expect(pillAlignment(), const Alignment(-1, 0));
    final pillBox = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(AppMobileTabBar.activePillKey),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(
      (pillBox.decoration as BoxDecoration).color,
      AppThemeData.dark.colors.navPanel.activeBg,
    );
    expect(icons()[0].color, AppThemeData.dark.colors.navPanel.activeIcon);
    expect(icons()[2].color, AppThemeData.dark.colors.icon.muted);

    await tester.tap(find.bySemanticsLabel('Activity'));
    await tester.pumpAndSettle();
    expect(taps, [2]);

    // Selection is owned by the caller — rebuilding with the new index
    // slides the pill there and swaps the icon tints.
    await tester.pumpWidget(bar(2));
    await tester.pumpAndSettle();
    expect(pillAlignment().x, closeTo(-1 + 2 * 2 / 3, 1e-9));
    expect(icons()[0].color, AppThemeData.dark.colors.icon.muted);
    expect(icons()[2].color, AppThemeData.dark.colors.navPanel.activeIcon);
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

  testWidgets('MobileModalCard uses the Figma modal base in both themes', (
    tester,
  ) async {
    Future<void> pumpCard(AppThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, navigator) =>
              AppTheme(data: theme, child: navigator!),
          home: const Center(
            child: SizedBox(
              width: 393,
              height: 852,
              child: MobileModalCard(
                child: SizedBox(height: 200, child: Text('Modal content')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final theme in [AppThemeData.dark, AppThemeData.light]) {
      await pumpCard(theme);

      final cardFinder = find.byType(MobileModalCard);
      final decoratedBox = tester.widget<DecoratedBox>(
        find.descendant(of: cardFinder, matching: find.byType(DecoratedBox)),
      );
      final decoration = decoratedBox.decoration as BoxDecoration;
      expect(
        decoration.borderRadius,
        const BorderRadius.all(Radius.circular(AppRadii.xLarge)),
      );
      expect(decoration.boxShadow, const [
        BoxShadow(
          color: Color(0x14000000),
          offset: Offset(0, 14),
          blurRadius: 28,
        ),
        BoxShadow(
          color: Color(0x08000000),
          offset: Offset(0, -6),
          blurRadius: 12,
        ),
        BoxShadow(
          color: Color(0x0F000000),
          offset: Offset(0, 2),
          blurRadius: 8,
        ),
      ]);

      final material = tester.widget<Material>(
        find.descendant(of: cardFinder, matching: find.byType(Material)),
      );
      expect(material.color, theme.colors.background.base);
      expect(
        material.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.xLarge)),
        ),
      );

      final rim = tester.widget<CustomPaint>(
        find
            .descendant(of: cardFinder, matching: find.byType(CustomPaint))
            .first,
      );
      expect(rim.foregroundPainter, isNotNull);
    }
  });
}

Widget _harness(Widget child) {
  return MaterialApp(
    // AppTheme wraps the navigator (like the real app's AppThemeHost in
    // MaterialApp.builder) so root-navigator overlays — modal sheets shown
    // with useRootNavigator — can resolve it too.
    builder: (context, navigator) =>
        AppTheme(data: AppThemeData.dark, child: navigator!),
    home: Center(child: child),
  );
}
