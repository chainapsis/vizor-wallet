import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/covered_route_keyboard_hold.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_keyboard_aware_height.dart';

void main() {
  group('CoveredRouteKeyboardHold', () {
    final navigator = GlobalKey<NavigatorState>();
    var builds = 0;
    double? inset;

    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: CoveredRouteKeyboardHold(
            child: Builder(
              builder: (context) {
                builds++;
                inset = MediaQuery.viewInsetsOf(context).bottom;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
    }

    Future<void> keyboard(WidgetTester tester, double height) async {
      tester.view.viewInsets = FakeViewPadding(bottom: height);
      await tester.pump();
    }

    Future<void> pushSheet(WidgetTester tester) async {
      unawaited(
        navigator.currentState!.push(
          PageRouteBuilder<void>(
            opaque: false,
            pageBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a covered screen ignores a sheet keyboard', (tester) async {
      await pumpScreen(tester);
      await pushSheet(tester);
      final before = builds;

      for (final height in [60.0, 180.0, 300.0]) {
        await keyboard(tester, height);
      }
      expect(builds, before);
      expect(inset, 0);

      // Uncovered while that keyboard goes down: still no keyboard.
      navigator.currentState!.pop();
      await tester.pump();
      for (final height in [200.0, 90.0, 0.0]) {
        await keyboard(tester, height);
        expect(inset, 0);
      }

      // Its own keyboard is followed again.
      await keyboard(tester, 120);
      expect(inset, 120);
    });

    testWidgets('a keyboard rising while uncovered is followed at once', (
      tester,
    ) async {
      await pumpScreen(tester);
      await pushSheet(tester);
      await keyboard(tester, 300);

      navigator.currentState!.pop();
      await tester.pump();
      await keyboard(tester, 200);
      expect(inset, 0);
      // Rising again, for a field on this screen.
      await keyboard(tester, 260);
      expect(inset, 260);
    });

    testWidgets('a screen covered with its keyboard up keeps following it', (
      tester,
    ) async {
      await pumpScreen(tester);
      await keyboard(tester, 300);
      await pushSheet(tester);

      await keyboard(tester, 150);
      expect(inset, 150);
    });
  });

  testWidgets('MobileKeyboardAwareHeight rebuilds only the sizing', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    var bodyBuilds = 0;
    double? height;
    await tester.pumpWidget(
      MaterialApp(
        home: MobileKeyboardAwareHeight(
          reserved: 100,
          min: 120,
          max: 500,
          builder: (context, value, child) {
            height = value;
            return SizedBox(height: value, child: child);
          },
          child: Builder(
            builder: (context) {
              bodyBuilds++;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(height, 500);
    final before = bodyBuilds;

    tester.view.viewInsets = const FakeViewPadding(bottom: 450);
    await tester.pump();
    expect(height, 250);
    tester.view.viewInsets = const FakeViewPadding(bottom: 700);
    await tester.pump();
    expect(height, 120);
    expect(bodyBuilds, before);
  });
}
