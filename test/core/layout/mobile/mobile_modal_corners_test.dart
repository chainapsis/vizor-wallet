@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/services/native_modal_corners.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  void iosTest(String name, WidgetTesterCallback body) => testWidgets(
    name,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall)? reply;

  setUp(() {
    calls.clear();
    reply = (_) async => {'bottomLeft': 46.0, 'bottomRight': 48.0};
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeModalCorners.channel,
      (call) {
        calls.add(call);
        return reply!(call);
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeModalCorners.channel,
      null,
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    bool centered = false,
    bool transparent = false,
    Widget? child,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1206, 2622);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, navigator) =>
            AppTheme(data: AppThemeData.dark, child: navigator!),
        home: Align(
          alignment: centered ? Alignment.center : Alignment.bottomCenter,
          child: MobileModalCard(
            followsScreenCorners: !centered,
            margin: centered ? EdgeInsets.zero : null,
            transparentBackground: transparent,
            child: child ?? const SizedBox(height: 240, width: double.infinity),
          ),
        ),
      ),
    );
  }

  BorderRadius radius(WidgetTester tester) {
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(MobileModalCard),
        matching: find.byType(Material),
      ),
    );
    return (material.shape! as RoundedSuperellipseBorder).borderRadius
        as BorderRadius;
  }

  iosTest('native radius drives the same surface, shadow and clip shape', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    final r = radius(tester);
    expect(r.topLeft.x, 32);
    expect(r.bottomLeft.x, 46);
    expect(r.bottomRight.x, 48);
    expect(calls, hasLength(1));
    expect(calls.single.arguments, containsPair('y', 618.0));
    expect(calls.single.arguments, containsPair('width', 370.0));
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(MobileModalCard),
        matching: find.byType(Material),
      ),
    );
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(MobileModalCard),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as ShapeDecoration;
    expect(decoration.shape, material.shape);
    expect(material.clipBehavior, Clip.antiAlias);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, hasLength(1));
  });

  iosTest('keyboard retargets current radius and restores cached geometry', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 1005);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final intermediate = radius(tester).bottomLeft.x;
    expect(intermediate, greaterThan(32));
    expect(intermediate, lessThan(46));
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    expect(radius(tester).bottomLeft.x, closeTo(intermediate, 0.001));
    await tester.pumpAndSettle();
    expect(radius(tester).bottomLeft.x, 46);
    expect(calls, hasLength(1));
    tester.view.viewInsets = const FakeViewPadding(bottom: 1005);
    await tester.pumpAndSettle();
    expect(radius(tester).bottomLeft.x, 32);
    expect(radius(tester).topLeft.x, 32);
  });

  iosTest('late responses cannot restore corners while keyboard is open', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    reply = (_) => pending.future;
    await pump(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 1005);
    await tester.pump();
    pending.complete({'bottomLeft': 62.0, 'bottomRight': 62.0});
    await tester.pumpAndSettle();
    expect(radius(tester).bottomLeft.x, 32);
  });

  iosTest('unavailable, malformed and timed-out native calls retain 32', (
    tester,
  ) async {
    reply = (_) async => throw PlatformException(code: 'unavailable');
    await pump(tester);
    await tester.pumpAndSettle();
    expect(radius(tester).bottomLeft.x, 32);
    for (final bad in [
      null,
      'bad',
      {'bottomLeft': -1, 'bottomRight': 46},
      {'bottomLeft': double.nan, 'bottomRight': 46},
      {'bottomLeft': 1000, 'bottomRight': 46},
    ]) {
      reply = (_) async => bad;
      final future = NativeModalCorners.resolve(
        rect: const Rect.fromLTWH(16, 618, 370, 240),
        viewSize: const Size(402, 874),
        scale: 3,
      );
      await tester.pump();
      expect(await future, isNull);
    }
    final pending = Completer<Object?>();
    reply = (_) => pending.future;
    final future = NativeModalCorners.resolve(
      rect: const Rect.fromLTWH(16, 618, 370, 240),
      viewSize: const Size(402, 874),
      scale: 3,
    );
    await tester.pump(NativeModalCorners.timeout);
    expect(await future, isNull);
    pending.complete(null);
  });

  iosTest('centered dialog is a fixed squircle without native queries', (
    tester,
  ) async {
    await pump(tester, centered: true);
    await tester.pumpAndSettle();
    expect(radius(tester), const BorderRadius.all(Radius.circular(32)));
    expect(calls, isEmpty);
  });

  iosTest('transparent content owns its surface without native queries', (
    tester,
  ) async {
    await pump(tester, transparent: true);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  iosTest('rotation and foreground recovery invalidate geometry', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(2622, 1206);
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    expect(calls.last.arguments, containsPair('viewWidth', 874.0));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(radius(tester).bottomLeft.x, 32);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.length, 3);
    expect(radius(tester).bottomLeft.x, 46);
  });

  iosTest(
    'route entrance waits for layout and dismissal rejects late results',
    (tester) async {
      final pending = Completer<Object?>();
      reply = (_) => pending.future;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppMobileSheet<void>(
                context: context,
                builder: (_) =>
                    const SizedBox(height: 240, width: double.infinity),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(calls, hasLength(1));
      navigator.currentState!.pop();
      await tester.pump();
      pending.complete({'bottomLeft': 62, 'bottomRight': 62});
      await tester.pump(const Duration(milliseconds: 100));
      expect(radius(tester).bottomLeft.x, 32);
      await tester.pumpAndSettle();
      expect(find.byType(MobileModalCard), findsNothing);
    },
  );

  iosTest('content growth remeasures the actual surface', (tester) async {
    final height = ValueNotifier(240.0);
    addTearDown(height.dispose);
    await pump(
      tester,
      child: ValueListenableBuilder<double>(
        valueListenable: height,
        builder: (_, value, child) =>
            SizedBox(height: value, width: double.infinity),
      ),
    );
    await tester.pumpAndSettle();
    height.value = 320;
    await tester.pumpAndSettle();
    expect(calls, hasLength(2));
    expect(calls.last.arguments, containsPair('height', 320.0));
    expect(calls.last.arguments, containsPair('y', 538.0));
  });

  testWidgets('Android keeps circular corners and makes no native queries', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(MobileModalCard),
        matching: find.byType(Material),
      ),
    );
    expect(
      material.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(32)),
      ),
    );
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  iosTest('disposing a modal ignores pending native response', (tester) async {
    final pending = Completer<Object?>();
    reply = (_) => pending.future;
    await pump(tester);
    await tester.pumpWidget(const SizedBox());
    pending.complete({'bottomLeft': 46, 'bottomRight': 46});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  iosTest('shared centered card also uses iOS continuous corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: const Center(
            child: AppModalCard(highlight: true, child: Text('Dialog')),
          ),
        ),
      ),
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppModalCard),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (container.decoration! as ShapeDecoration).shape,
      isA<RoundedSuperellipseBorder>(),
    );
    expect(calls, isEmpty);
  });
}
