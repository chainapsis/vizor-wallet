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
import 'package:zcash_wallet/src/core/layout/mobile/prepared_modal_sheet_route.dart';

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

  iosTest(
    'keyboard retargets current radius and restores native cached geometry',
    (tester) async {
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
      expect(calls, hasLength(2));
      tester.view.viewInsets = const FakeViewPadding(bottom: 1005);
      await tester.pumpAndSettle();
      expect(radius(tester).bottomLeft.x, 32);
      expect(radius(tester).topLeft.x, 32);
    },
  );

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
    expect(radius(tester).bottomLeft.x, 46);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.length, 3);
    expect(radius(tester).bottomLeft.x, 46);
  });

  for (final timeout in [false, true]) {
    iosTest('first visible route frame is final (timeout: $timeout)', (
      tester,
    ) async {
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
      await tester.pump();
      expect(calls, hasLength(1));
      expect(calls.single.arguments, containsPair('y', 344.0));
      final card = find.byType(MobileModalCard, skipOffstage: false);
      final route =
          ModalRoute.of(tester.element(card))! as PreparedModalSheetRoute;
      expect(route.offstage, isTrue);
      final labels = MaterialLocalizations.of(tester.element(card));
      expect(route.barrierLabel, labels.scrimLabel);
      expect(
        route.barrierOnTapHint,
        labels.scrimOnTapHint(labels.bottomSheetLabel),
      );
      if (timeout) {
        await tester.pump(const Duration(milliseconds: 101));
      } else {
        pending.complete({'bottomLeft': 46, 'bottomRight': 46});
        await tester.pump();
      }
      await tester.pump();
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(radius(tester).bottomLeft.x, timeout ? 32 : 46);
      }
      if (timeout) {
        pending.complete({'bottomLeft': 62, 'bottomRight': 62});
        await tester.pumpAndSettle();
        expect(radius(tester).bottomLeft.x, 32);
      }
      expect(calls, hasLength(1));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(MobileModalCard), findsNothing);
    });
  }

  iosTest(
    'inline card is hidden until final radius without remounting content',
    (tester) async {
      final pending = Completer<Object?>();
      reply = (_) => pending.future;
      final key = GlobalKey();
      await pump(
        tester,
        child: SizedBox(key: key, height: 240, width: double.infinity),
      );
      final before = key.currentContext;
      Opacity visibility() => tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(MobileModalCard),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(visibility().opacity, 0);
      pending.complete({'bottomLeft': 46, 'bottomRight': 46});
      await tester.pump();
      await tester.pump();
      expect(visibility().opacity, 1);
      expect(radius(tester).bottomLeft.x, 46);
      expect(identical(before, key.currentContext), isTrue);
    },
  );

  for (final closeEarly in [false, true]) {
    iosTest('preparation tolerates covering or closing route ($closeEarly)', (
      tester,
    ) async {
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
      await tester.pump();
      final card = find.byType(MobileModalCard, skipOffstage: false);
      final route =
          ModalRoute.of(tester.element(card))! as PreparedModalSheetRoute;
      if (closeEarly) {
        navigator.currentState!.pop();
      } else {
        navigator.currentState!.push(
          DialogRoute<void>(
            context: navigator.currentContext!,
            builder: (_) => const Text('Cover'),
          ),
        );
      }
      await tester.pump();
      pending.complete({'bottomLeft': 46, 'bottomRight': 46});
      await tester.pumpAndSettle();
      if (!closeEarly) {
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(route.offstage, isFalse);
        expect(radius(tester).bottomLeft.x, 46);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(find.byType(MobileModalCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  iosTest('a resize query canceled by drag retries at the settled position', (
    tester,
  ) async {
    final height = ValueNotifier(240.0);
    addTearDown(height.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppMobileSheet<void>(
              context: context,
              builder: (_) => ValueListenableBuilder<double>(
                valueListenable: height,
                builder: (_, value, _) => ColoredBox(
                  color: Colors.red,
                  child: SizedBox(height: value, width: double.infinity),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final pending = Completer<Object?>();
    reply = (_) => pending.future;
    height.value = 320;
    await tester.pump();
    await tester.pump();
    expect(calls, hasLength(2));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MobileModalCard)),
    );
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.byType(MobileModalCard)))!;
    expect(route.animation!.value, lessThan(1));
    reply = (_) async => {'bottomLeft': 60, 'bottomRight': 60};
    pending.complete({'bottomLeft': 40, 'bottomRight': 40});
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, hasLength(3));
    expect(radius(tester).bottomLeft.x, 60);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  });

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
