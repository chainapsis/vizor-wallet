@Tags(['mobile'])
library;

import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';

const _items = [
  AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
  AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
  AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
  AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
];

void main() {
  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    final dark = theme == AppThemeData.dark;
    _iosTestWidgets(
      'iOS bottom tabs preserve geometry and ${dark ? 'dark' : 'light'} '
      'app colors when OS appearance differs',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            theme: theme,
            platformBrightness: dark ? Brightness.light : Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();

        final bar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
        final colors = theme.colors;
        expect(
          tester.getSize(find.byType(AppMobileTabBar)),
          const Size(361, 64),
        );
        expect(bar.horizontalPadding, 0);
        expect(bar.verticalPadding, 0);
        expect(bar.selectedIconColor, colors.navPanel.activeIcon);
        expect(bar.unselectedIconColor, colors.icon.muted);
        expect(bar.indicatorColor, colors.navPanel.activeBg);
        expect(bar.settings!.glassColor, colors.macosUtility.navPanel);
        expect(
          tester.widget<GlassTheme>(find.byType(GlassTheme)).data.brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        // Labels stay available to VoiceOver without adding visible text.
        for (final item in _items) {
          expect(find.text(item.label), findsNothing);
          expect(find.bySemanticsLabel(item.label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  _iosTestWidgets(
    'iOS touch, drag and VoiceOver select the caller-owned branch',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final selections = <int>[];
      await tester.pumpWidget(_harness(onSelect: selections.add));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('Home')),
        matchesSemantics(
          label: 'Home',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.bySemanticsLabel('Activity'));
      await tester.pumpAndSettle();
      expect(selections, [2]);
      expect(
        tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
        2,
      );

      final settings = tester.getSemantics(find.bySemanticsLabel('Settings'));
      tester.binding.platformDispatcher.onSemanticsActionEvent!(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          viewId: tester.view.viewId,
          nodeId: settings.id,
        ),
      );
      await tester.pumpAndSettle();
      expect(selections, [2, 3]);
      expect(
        tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
        3,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Settings')),
      );
      await gesture.moveTo(tester.getCenter(find.bySemanticsLabel('Home')));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selections, [2, 3, 0]);
      expect(
        tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
        0,
      );
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  _iosTestWidgets('iOS previews a held tab and commits once on release', (
    tester,
  ) async {
    final selections = <int>[];
    var haptics = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_harness(onSelect: selections.add));
    await tester.pumpAndSettle();

    final touch = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Activity')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Screen 0'), findsOneWidget);
    expect(selections, isEmpty);
    expect(haptics, 0);
    expect(
      tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
      2,
    );

    await touch.up();
    await tester.pumpAndSettle();
    expect(find.text('Screen 2'), findsOneWidget);
    expect(selections, [2]);
    expect(haptics, 1);
  });

  _iosTestWidgets(
    'iOS drag changes no screen until the final tab is released',
    (tester) async {
      final selections = <int>[];
      await tester.pumpWidget(_harness(onSelect: selections.add));
      await tester.pumpAndSettle();
      final touch = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Swap')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      for (final label in ['Activity', 'Settings']) {
        await touch.moveTo(tester.getCenter(find.bySemanticsLabel(label)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Screen 0'), findsOneWidget);
        expect(selections, isEmpty);
      }
      await touch.up();
      await tester.pumpAndSettle();
      expect(find.text('Screen 3'), findsOneWidget);
      expect(selections, [3]);
    },
  );

  for (final drag in [false, true]) {
    _iosTestWidgets(
      'iOS cancelled ${drag ? 'drag' : 'tap'} restores the current '
      'tab without navigation',
      (tester) async {
        final selections = <int>[];
        await tester.pumpWidget(_harness(onSelect: selections.add));
        await tester.pumpAndSettle();
        final touch = await tester.startGesture(
          tester.getCenter(find.bySemanticsLabel('Activity')),
        );
        await tester.pump(const Duration(milliseconds: 200));
        if (drag) {
          await touch.moveTo(
            tester.getCenter(find.bySemanticsLabel('Settings')),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await touch.cancel();
        await tester.pumpAndSettle();
        expect(selections, isEmpty);
        expect(find.text('Screen 0'), findsOneWidget);
        expect(
          tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
          0,
        );
        await tester.tap(find.bySemanticsLabel('Swap'));
        await tester.pumpAndSettle();
        expect(selections, [1]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _iosTestWidgets('iOS discards a held preview after external navigation', (
    tester,
  ) async {
    final selections = <int>[];
    final index = ValueNotifier(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(_harness(onSelect: selections.add, index: index));
    await tester.pumpAndSettle();
    final touch = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Activity')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    index.value = 3;
    await tester.pump();
    await touch.up();
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(find.text('Screen 3'), findsOneWidget);
    expect(
      tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
      3,
    );
    await tester.tap(find.bySemanticsLabel('Swap'));
    await tester.pumpAndSettle();
    expect(selections, [1]);
  });

  _iosTestWidgets('iOS consecutive taps before a frame each commit once', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(_harness(onSelect: selections.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Activity'));
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(selections, [2, 3]);
    expect(find.text('Screen 3'), findsOneWidget);
  });

  _iosTestWidgets('iOS retapping the active tab emits one activation', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(_harness(onSelect: selections.add));
    await tester.pumpAndSettle();
    final touch = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Home')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(selections, isEmpty);
    await touch.up();
    await tester.pumpAndSettle();
    expect(selections, [0]);
  });

  _iosTestWidgets('iOS disposes a pending release without late navigation', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(_harness(onSelect: selections.add));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Activity'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(tester.takeException(), isNull);
  });

  _iosTestWidgets(
    'iOS rejected selection does not hide later external navigation',
    (tester) async {
      final selections = <int>[];
      final index = ValueNotifier(0);
      addTearDown(index.dispose);
      await tester.pumpWidget(
        _harness(onSelect: selections.add, index: index, adoptSelection: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Activity'));
      await tester.pumpAndSettle();
      expect(selections, [2]);
      expect(find.text('Screen 0'), findsOneWidget);
      expect(
        tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
        0,
      );

      final touch = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Swap')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      index.value = 2;
      await tester.pump();
      await touch.up();
      await tester.pumpAndSettle();
      expect(selections, [2]);
      expect(find.text('Screen 2'), findsOneWidget);
      expect(
        tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
        2,
      );
    },
  );

  _iosTestWidgets('iOS overlapping touches cancel selection and recover', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(_harness(onSelect: selections.add));
    await tester.pumpAndSettle();
    final first = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Activity')),
      pointer: 1,
    );
    await tester.pump(const Duration(milliseconds: 200));
    final second = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Settings')),
      pointer: 2,
    );
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(find.text('Screen 0'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Swap'));
    await tester.pumpAndSettle();
    expect(selections, [1]);
  });

  _iosTestWidgets('iOS keyboard activation commits without a pointer release', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(_harness(onSelect: selections.add));
    await tester.pumpAndSettle();
    final focus = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: find.bySemanticsLabel('Swap'),
        matching: find.byType(FocusableActionDetector),
      ),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selections, [1]);
    expect(find.text('Screen 1'), findsOneWidget);
  });

  _iosTestWidgets(
    'iOS reduced motion keeps instant selection without glass springs',
    (tester) async {
      await tester.pumpWidget(_harness(disableAnimations: true));
      expect(find.byType(GlassTabBar), findsNothing);
      await tester.tap(find.bySemanticsLabel('Activity'));
      await tester.pump();
      final pill = tester.widget<AnimatedAlign>(
        find.byKey(AppMobileTabBar.activePillKey),
      );
      expect(pill.duration, Duration.zero);
      expect((pill.alignment as Alignment).x, closeTo(1 / 3, 1e-9));
      expect(tester.takeException(), isNull);
    },
  );

  _iosTestWidgets(
    'iOS side tabs and Android tabs retain their original surface',
    (tester) async {
      await tester.pumpWidget(_harness(axis: Axis.vertical));
      expect(find.byType(GlassTabBar), findsNothing);
      expect(tester.getSize(find.byType(AppMobileTabBar)), const Size(64, 232));

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(_harness());
      expect(find.byType(GlassTabBar), findsNothing);
      expect(tester.getSize(find.byType(AppMobileTabBar)), const Size(361, 64));
    },
  );
}

void _iosTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _harness({
  AppThemeData theme = AppThemeData.dark,
  Brightness platformBrightness = Brightness.light,
  bool disableAnimations = false,
  Axis axis = Axis.horizontal,
  ValueChanged<int>? onSelect,
  ValueNotifier<int>? index,
  bool adoptSelection = true,
}) {
  var currentIndex = 0;
  Widget shell(int selected, ValueChanged<int> select) => AppMobileShell(
    body: Center(child: Text('Screen $selected')),
    tabBar: Align(
      heightFactor: 1,
      child: AppMobileTabBar(
        axis: axis,
        items: _items,
        currentIndex: selected,
        onSelect: select,
      ),
    ),
  );
  return MaterialApp(
    builder: (context, child) => AppTheme(
      data: theme,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: platformBrightness,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
    ),
    home: Center(
      child: SizedBox(
        width: 393,
        height: 852,
        child: index == null
            ? StatefulBuilder(
                builder: (context, setState) => shell(currentIndex, (next) {
                  onSelect?.call(next);
                  if (adoptSelection) setState(() => currentIndex = next);
                }),
              )
            : ValueListenableBuilder<int>(
                valueListenable: index,
                builder: (context, selected, _) => shell(selected, (next) {
                  onSelect?.call(next);
                  if (adoptSelection) index.value = next;
                }),
              ),
      ),
    ),
  );
}
