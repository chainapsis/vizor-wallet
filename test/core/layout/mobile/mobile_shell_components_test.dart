@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await loader.load();
  });

  testWidgets('Checking label fits the mobile top nav at 320 pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(
        MobileTopNav.account(
          accountName: 'Account1',
          syncLabel: '99% checking',
          syncAnimated: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('99% checking'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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

  testWidgets('MobileTopNav.account keeps the synced label width for shorter '
      'labels and sets figures tabular', (tester) async {
    Future<Rect> slotFor(String label) async {
      await tester.pumpWidget(
        _harness(
          MobileTopNav.account(accountName: 'Account1', syncLabel: label),
        ),
      );
      return tester.getRect(
        find.byKey(const ValueKey('mobile_top_nav_sync_label_slot')),
      );
    }

    final synced = await slotFor('Vizor is synced');
    expect(await slotFor('Syncing\u2026'), synced);
    expect(await slotFor('45% Syncing\u2026'), synced);
    // The label sits at the slot's trailing edge, next to the bar.
    expect(tester.getTopRight(find.text('45% Syncing\u2026')).dx, synced.right);
    expect(
      tester.widget<Text>(find.text('45% Syncing\u2026')).style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    // A longer label still gets its full width.
    final failed = await slotFor('Syncing failed. Wallet data error...');
    expect(failed.width, greaterThan(synced.width));
  });

  testWidgets('MobileTopNav.account syncing shimmers the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MobileTopNav.account(
          accountName: 'Account1',
          syncLabel: '20% Syncing…',
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
    expect(find.text('20% Syncing…'), findsOneWidget);
    // The label is wrapped in a shimmer ShaderMask over a solid-color Text.
    expect(find.byType(ShaderMask), findsOneWidget);
    final label = tester.widget<Text>(find.text('20% Syncing…'));
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
              syncLabel: '20% Syncing…',
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
    final label = tester.widget<Text>(find.text('20% Syncing…'));
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

  testWidgets('MobileTopNav.back shows the inner-page title and fires onBack', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(
      _harness(MobileTopNav.back(title: 'Contacts', onBack: () => backs++)),
    );

    // Inner pages share the small title; only tab roots pass the serif.
    final title = tester.widget<Text>(find.text('Contacts'));
    expect(title.style?.fontFamily, AppTypography.headlineSmall.fontFamily);
    expect(title.style?.fontSize, AppTypography.headlineSmall.fontSize);

    await tester.tap(find.bySemanticsLabel('Back'));
    expect(backs, 1);
  });

  testWidgets('MobileTopNav.back accepts a title style override', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MobileTopNav.back(
          // Neutral sample text: a distinct style from the headlineSmall
          // default, purely to prove the override is applied. (Tab roots
          // pass headlineLarge for their serif title.)
          title: 'Custom title',
          titleStyle: AppTypography.headlineMedium,
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Custom title'));
    expect(title.style?.fontFamily, AppTypography.headlineMedium.fontFamily);
    expect(title.style?.fontSize, AppTypography.headlineMedium.fontSize);
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
    final pillDecoration = pillBox.decoration as BoxDecoration;
    expect(
      pillDecoration.color,
      AppThemeData.dark.colors.navPanel.tabBarActiveBg,
    );
    expect(pillDecoration.border, isNull);
    expect(
      icons()[0].color,
      AppThemeData.dark.colors.navPanel.tabBarActiveIcon,
    );
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
    expect(
      icons()[2].color,
      AppThemeData.dark.colors.navPanel.tabBarActiveIcon,
    );
  });

  testWidgets('dragging the pill selects the tab it is released over', (
    tester,
  ) async {
    final selected = <int>[];
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
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
    const items = [
      AppMobileTabItem(iconName: 'home', label: 'Home'),
      AppMobileTabItem(iconName: 'swap_arrows', label: 'Swap'),
      AppMobileTabItem(iconName: 'history', label: 'Activity'),
      AppMobileTabItem(iconName: 'cog', label: 'Settings'),
    ];
    await tester.pumpWidget(
      _harness(
        AppMobileTabBar(items: items, currentIndex: 0, onSelect: selected.add),
      ),
    );
    double pillX() =>
        (tester
                    .widget<AnimatedAlign>(
                      find.byKey(AppMobileTabBar.activePillKey),
                    )
                    .alignment
                as Alignment)
            .x;

    // Drag slowly two tabs to the right: the pill follows the finger and a
    // strong haptic marks each tab it crosses.
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Home')),
    );
    for (var i = 0; i < 18; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(pillX(), greaterThan(-1));
    expect(selected, isEmpty);
    // The tint follows the pill: the tab under it lights up and the one it
    // left goes grey before anything is selected.
    Color? iconColor(String name) => tester
        .widget<AppIcon>(
          find.byWidgetPredicate(
            (widget) => widget is AppIcon && widget.name == name,
          ),
        )
        .color;
    final colors = AppThemeData.dark.colors;
    expect(iconColor('history'), colors.navPanel.tabBarActiveIcon);
    expect(iconColor('home'), colors.icon.muted);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, [2]);
    expect(pillX(), closeTo(-1 + 2 * 2 / 3, 1e-9));
    expect(haptics, List.filled(2, 'HapticFeedbackType.mediumImpact'));

    // A tap selects with the same strong haptic.
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
    expect(selected, [2, 3]);
    expect(haptics, List.filled(3, 'HapticFeedbackType.mediumImpact'));
  });

  testWidgets('a newly active tab icon plays its flourish, then rests', (
    tester,
  ) async {
    const items = [
      AppMobileTabItem(iconName: 'home', label: 'Home'),
      AppMobileTabItem(iconName: 'history', label: 'Activity'),
    ];
    Widget bar(int index, {bool reduceMotion = false}) => _harness(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: SizedBox(
          width: 361,
          child: AppMobileTabBar(
            items: items,
            currentIndex: index,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    Finder historyIcons() => find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.name == 'history',
    );

    await tester.pumpWidget(bar(0));
    // At rest each tab draws its plain icon, with no flourish layers.
    expect(historyIcons(), findsOneWidget);

    await tester.pumpWidget(bar(1));
    await tester.pump(const Duration(milliseconds: 200));
    // Mid-flourish the clock's hand and ring turn as separate layers.
    expect(historyIcons(), findsNWidgets(2));

    await tester.pumpAndSettle();
    expect(historyIcons(), findsOneWidget);

    // Reduced motion switches instantly, with no flourish.
    await tester.pumpWidget(bar(0, reduceMotion: true));
    await tester.pumpWidget(bar(1, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 200));
    expect(historyIcons(), findsOneWidget);
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

  testWidgets('MobileModalScaffold preserves tall leading affordances', (
    tester,
  ) async {
    const leadingKey = ValueKey('modal_leading_affordance');
    await tester.pumpWidget(
      _harness(
        SizedBox(
          width: 361,
          child: MobileModalScaffold(
            title: 'Verify address',
            onClose: () {},
            leading: const SizedBox(key: leadingKey, width: 32, height: 32),
            child: const SizedBox(height: 24),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(leadingKey)), const Size(32, 32));
  });

  testWidgets('MobileModalCard uses the Figma modal base in both themes', (
    tester,
  ) async {
    Future<void> pumpCard(AppThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
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
    localizationsDelegates: appLocalizationsDelegates,
    // AppTheme wraps the navigator (like the real app's AppThemeHost in
    // MaterialApp.builder) so root-navigator overlays — modal sheets shown
    // with useRootNavigator — can resolve it too.
    builder: (context, navigator) =>
        AppTheme(data: AppThemeData.dark, child: navigator!),
    home: Center(child: child),
  );
}
