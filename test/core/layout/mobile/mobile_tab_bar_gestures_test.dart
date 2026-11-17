@Tags(['mobile'])
library;

import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';

const _items = [
  AppMobileTabItem(iconName: 'home', label: 'Home'),
  AppMobileTabItem(iconName: 'swap_arrows', label: 'Swap'),
  AppMobileTabItem(iconName: 'history', label: 'Activity'),
  AppMobileTabItem(iconName: 'cog', label: 'Settings'),
];

void main() {
  late ValueNotifier<int> selection;
  late List<int> selected;
  late List<Object?> haptics;

  setUp(() {
    selection = ValueNotifier(0);
    selected = [];
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
  });

  tearDown(() {
    selection.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    bool reducedMotion = false,
    Axis axis = Axis.horizontal,
    bool acceptSelection = true,
    List<AppMobileTabItem> items = _items,
  }) => tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Center(
            child: ValueListenableBuilder(
              valueListenable: selection,
              builder: (_, index, _) => AppMobileTabBar(
                items: items,
                axis: axis,
                currentIndex: index,
                onSelect: (target) {
                  selected.add(target);
                  if (acceptSelection) selection.value = target;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Offset tab(WidgetTester tester, int index) =>
      tester.getCenter(find.bySemanticsLabel(_items[index].label));

  // Inspect the painted pill, not AnimatedAlign's destination. This catches
  // discontinuities and unintended restarts during an in-flight arrival.
  Rect pill(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byKey(AppMobileTabBar.activePillKey),
      matching: find.byType(DecoratedBox),
    ),
  );

  Color? iconColor(WidgetTester tester, String name) => tester
      .widget<AppIcon>(
        find.byWidgetPredicate((w) => w is AppIcon && w.name == name).first,
      )
      .color;

  testWidgets(
    'touch-down previews another tab before any movement or selection',
    (tester) async {
      await pumpBar(tester);
      final start = pill(tester).center.dx;
      final gesture = await tester.startGesture(tab(tester, 2));
      await tester.pump();
      expect(pill(tester).center.dx, closeTo(start, 0.01));
      await tester.pump(const Duration(milliseconds: 40));
      expect(pill(tester).center.dx, greaterThan(start));
      expect(pill(tester).center.dx, lessThan(tab(tester, 2).dx));
      await tester.pump(const Duration(milliseconds: 60));
      expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
      expect(selected, isEmpty);
      expect(haptics, isEmpty);
      expect(selection.value, 0);
      expect(
        iconColor(tester, 'history'),
        AppThemeData.dark.colors.navPanel.tabBarActiveIcon,
      );
      final semantics = tester.getSemantics(find.bySemanticsLabel('Home'));
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, [2]);
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
    },
  );

  testWidgets('a quick tap finishes its 100ms arrival without restarting', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final beforeRelease = pill(tester).center.dx;
    await gesture.up();
    await tester.pump();
    expect(pill(tester).center.dx, closeTo(beforeRelease, 0.01));
    await tester.pump(const Duration(milliseconds: 80));
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
    expect(selected, [2]);
    expect(haptics, hasLength(1));
    await tester.pumpAndSettle();
  });

  for (final (from, to) in [(2, 3), (2, 1), (3, 0)]) {
    testWidgets('drag starts at touched tab $from and lands on $to', (
      tester,
    ) async {
      await pumpBar(tester);
      final gesture = await tester.startGesture(tab(tester, from));
      await tester.pumpAndSettle();
      final distance = tab(tester, to) - tab(tester, from);
      for (var step = 0; step < 18; step++) {
        await gesture.moveBy(distance / 18);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(pill(tester).center.dx, closeTo(tab(tester, to).dx, 0.01));
      expect(selected, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      // Returning to the already selected tab is not a new navigation.
      expect(selected, to == 0 ? isEmpty : [to]);
      expect(selection.value, to);
    });
  }

  testWidgets(
    'movement during arrival adds delta without restarting animation',
    (tester) async {
      await pumpBar(tester);
      final gesture = await tester.startGesture(tab(tester, 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final beforeMove = pill(tester).center.dx;
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      expect(pill(tester).center.dx, closeTo(beforeMove + 24, 0.01));
      await tester.pump(const Duration(milliseconds: 70));
      expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx + 24, 0.01));
      expect(selected, isEmpty);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(pill(tester).center.dx, closeTo(tab(tester, 0).dx, 0.01));
      expect(selected, isEmpty);
    },
  );

  testWidgets('release during arrival settles from the painted position', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 20));
    final beforeRelease = pill(tester).center.dx;
    // No meaningful flick velocity: this short, single move tests the drop.
    await gesture.up();
    await tester.pump();
    expect(pill(tester).center.dx, closeTo(beforeRelease, 0.01));
    await tester.pumpAndSettle();
    expect(selected, [2]);
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
  });

  testWidgets('selected-tab touch preserves the grab point', (tester) async {
    selection.value = 1;
    await pumpBar(tester);
    final gesture = await tester.startGesture(
      tab(tester, 1) + const Offset(20, 0),
    );
    await tester.pumpAndSettle();
    expect(pill(tester).center.dx, closeTo(tab(tester, 1).dx, 0.01));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(pill(tester).center.dx, closeTo(tab(tester, 1).dx + 24, 0.01));
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('touch cancellation restores selection without navigating', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 3));
    await tester.pumpAndSettle();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(pill(tester).center.dx, closeTo(tab(tester, 0).dx, 0.01));
    expect(selected, isEmpty);
    expect(haptics, isEmpty);
  });

  testWidgets('re-grabbing an animation starts from its painted position', (
    tester,
  ) async {
    await pumpBar(tester);
    selection.value = 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final beforeTouch = pill(tester).center.dx;
    final gesture = await tester.startGesture(tab(tester, 1));
    await tester.pump();
    expect(pill(tester).center.dx, closeTo(beforeTouch, 0.01));
    await tester.pumpAndSettle();
    expect(pill(tester).center.dx, closeTo(tab(tester, 1).dx, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [1]);
  });

  testWidgets('external selection invalidates an outstanding touch', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pumpAndSettle();
    selection.value = 1;
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(pill(tester).center.dx, closeTo(tab(tester, 1).dx, 0.01));
  });

  testWidgets('unrelated parent rebuild leaves an active preview intact', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pumpAndSettle();
    await pumpBar(tester);
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [2]);
  });

  testWidgets('a changed destination list cancels the touch', (tester) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pumpAndSettle();
    await pumpBar(tester, items: [_items[0], _items[2], _items[3]]);
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(pill(tester).center.dx, closeTo(tab(tester, 0).dx, 0.01));
  });

  testWidgets('a second finger cannot move or select the first touch', (
    tester,
  ) async {
    await pumpBar(tester);
    final first = await tester.startGesture(tab(tester, 2), pointer: 1);
    await tester.pumpAndSettle();
    final second = await tester.startGesture(tab(tester, 0), pointer: 2);
    await second.moveBy(const Offset(100, 0));
    await tester.pump();
    await second.up();
    await tester.pump();
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
    expect(selected, isEmpty);
    for (var i = 0; i < 9; i++) {
      await first.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await first.up();
    await tester.pumpAndSettle();
    expect(selected, [3]);
  });

  testWidgets('a second finger tap cannot select its destination', (
    tester,
  ) async {
    await pumpBar(tester);
    final first = await tester.startGesture(tab(tester, 2), pointer: 1);
    await tester.pumpAndSettle();
    final second = await tester.startGesture(tab(tester, 0), pointer: 2);
    await second.up();
    await tester.pump();
    expect(selected, isEmpty);
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
    await first.up();
    await tester.pumpAndSettle();
    expect(selected, [2]);
    expect(haptics, hasLength(1));
  });

  testWidgets('reduced motion previews instantly and commits on release', (
    tester,
  ) async {
    await pumpBar(tester, reducedMotion: true);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pump();
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
    expect(selected, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [2]);
  });

  testWidgets('semantics activation selects without needing a pointer', (
    tester,
  ) async {
    await pumpBar(tester);
    final semantics = tester.ensureSemantics();
    final node = tester.getSemantics(find.bySemanticsLabel('Activity'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(selected, [2]);
    expect(haptics, hasLength(1));
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
    semantics.dispose();
  });

  testWidgets('reselecting the current tab still notifies the caller once', (
    tester,
  ) async {
    await pumpBar(tester);
    await tester.tap(find.bySemanticsLabel('Home'));
    await tester.pumpAndSettle();
    expect(selected, [0]);
    expect(haptics, hasLength(1));
  });

  testWidgets('flick momentum still carries the pill to a further tab', (
    tester,
  ) async {
    await pumpBar(tester);
    await tester.fling(
      find.bySemanticsLabel('Activity'),
      const Offset(40, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(selected, [3]);
    expect(pill(tester).center.dx, closeTo(tab(tester, 3).dx, 0.01));
    // Touching Activity ticks once on drag recognition, then the projected
    // landing ticks once for Settings; the initial animation adds no ticks.
    expect(haptics, List.filled(2, 'HapticFeedbackType.mediumImpact'));
  });

  testWidgets('drag remains clamped when the finger leaves the bar', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pumpAndSettle();
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump();
    expect(pill(tester).center.dx, closeTo(tab(tester, 3).dx, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [3]);
  });

  testWidgets('caller rejection rolls the pill back on its next update', (
    tester,
  ) async {
    await pumpBar(tester, acceptSelection: false);
    await tester.tap(find.bySemanticsLabel('Activity'));
    await tester.pumpAndSettle();
    expect(selected, [2]);
    await pumpBar(tester, acceptSelection: false);
    await tester.pumpAndSettle();
    expect(pill(tester).center.dx, closeTo(tab(tester, 0).dx, 0.01));
  });

  testWidgets('disposing during arrival leaves no late callbacks', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpWidget(const SizedBox());
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion enabled during arrival snaps immediately', (
    tester,
  ) async {
    await pumpBar(tester);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await pumpBar(tester, reducedMotion: true);
    expect(pill(tester).center.dx, closeTo(tab(tester, 2).dx, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
  });
  testWidgets('constrained tabs use their actual hit geometry', (tester) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpBar(tester);
    final activityRect = tester.getRect(find.bySemanticsLabel('Activity'));
    final gesture = await tester.startGesture(
      activityRect.centerLeft + const Offset(2, 0),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [2]);
  });

  testWidgets('vertical bar keeps its original selected-tab drag origin', (
    tester,
  ) async {
    await pumpBar(tester, axis: Axis.vertical);
    final gesture = await tester.startGesture(tab(tester, 2));
    await tester.pumpAndSettle();
    expect(pill(tester).center.dy, closeTo(tab(tester, 0).dy, 0.01));
    for (var i = 0; i < 13; i++) {
      await gesture.moveBy(const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, [1]);
  });
}
