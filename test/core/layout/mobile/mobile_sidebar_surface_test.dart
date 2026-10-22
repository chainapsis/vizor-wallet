@Tags(['mobile'])
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sidebar_surface.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_wallet_sidebar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sync_status.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/services/native_modal_corners.dart';

void main() {
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall)? reply;
  const radius = {
    'topLeft': 48.0,
    'topRight': 24.0,
    'bottomLeft': 56.0,
    'bottomRight': 24.0,
  };
  setUp(() {
    reply = (_) async => radius;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModalCorners.channel, (call) {
          calls.add(call);
          return reply!(call);
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModalCorners.channel, null),
  );

  Future<void> pump(
    WidgetTester tester, {
    double left = 16,
    double top = 40,
    Widget? panel,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(982, 654);
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: 256,
              height: 540,
              child:
                  panel ?? const MobileSidebarSurface(child: SizedBox.expand()),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BorderRadius outline(WidgetTester tester) {
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(MobileSidebarSurface),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is ShapeDecoration &&
              (widget.decoration as ShapeDecoration).shape
                  is RoundedSuperellipseBorder,
        ),
      ),
    );
    final shape = (decorated.decoration as ShapeDecoration).shape;
    expect(shape, isA<RoundedSuperellipseBorder>());
    final clip = tester.widget<ClipPath>(
      find.descendant(
        of: find.byType(MobileSidebarSurface),
        matching: find.byType(ClipPath),
      ),
    );
    expect((clip.clipper! as ShapeBorderClipper).shape, shape);
    return (shape as RoundedSuperellipseBorder).borderRadius as BorderRadius;
  }

  Widget sidebar({double bottomInset = 18}) => MediaQuery(
    data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
    child: MobileWalletSidebar(
      accountName: 'Test account',
      avatar: const SizedBox(width: 40, height: 40),
      status: const SyncStatusLabel(
        kind: SyncStatusKind.synced,
        label: 'Vizor is synced',
        semanticsLabel: 'Vizor is synced',
      ),
      currentPath: '/home',
      swapEnabled: true,
      onSelect: (_) {},
      onAccountTap: () {},
    ),
  );

  testWidgets(
    'keyboard animation keeps the panel corners and sync position on every frame',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      await pump(tester, panel: sidebar());
      final panelRect = tester.getRect(find.byType(MobileSidebarSurface));
      final syncRect = tester.getRect(find.byType(MobileSyncStatus));
      final delayed = Completer<Object?>();
      reply = (_) => delayed.future;
      for (final inset in [100.0, 200.0, 300.0, 200.0, 100.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        // The post-frame resolver runs first; inspect its pending frame too.
        await tester.pump();
        await tester.pump();
        expect(outline(tester).bottomLeft.y, 56, reason: 'inset=$inset');
        expect(tester.getRect(find.byType(MobileSidebarSurface)), panelRect);
        expect(tester.getRect(find.byType(MobileSyncStatus)), syncRect);
        expect(calls.length, 1);
      }
      delayed.complete(radius);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'duplicate keyboard metrics revalidate without flashing resolved corners',
    (tester) async {
      addTearDown(tester.view.reset);
      await pump(tester, panel: sidebar());
      final syncRect = tester.getRect(find.byType(MobileSyncStatus));
      for (final inset in [300.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        final delayed = Completer<Object?>();
        reply = (_) => delayed.future;
        // Native iOS sends repeated metrics with an identical final inset.
        tester.binding.handleMetricsChanged();
        await tester.pump();
        await tester.pump();
        expect(outline(tester).bottomLeft.y, 56);
        expect(tester.getRect(find.byType(MobileSyncStatus)), syncRect);
        delayed.complete(radius);
        await tester.pumpAndSettle();
        expect(outline(tester).bottomLeft.y, 56);
        expect(tester.getRect(find.byType(MobileSyncStatus)), syncRect);
      }
      expect(calls.length, 3);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'panel movement during a keyboard-only update still requests new corners',
    (tester) async {
      addTearDown(tester.view.reset);
      final offset = ValueNotifier(Offset.zero);
      addTearDown(offset.dispose);
      await pump(
        tester,
        panel: ValueListenableBuilder(
          valueListenable: offset,
          builder: (_, value, child) =>
              Transform.translate(offset: value, child: child),
          child: const MobileSidebarSurface(child: SizedBox.expand()),
        ),
      );
      reply = (_) async => {...radius, 'bottomLeft': 40.0};
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      offset.value = const Offset(16, 0);
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(calls.last.arguments, containsPair('x', 32.0));
      expect(outline(tester).bottomLeft.y, 40);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'keyboard metrics preserve an in-flight request for unchanged geometry',
    (tester) async {
      addTearDown(tester.view.reset);
      final first = Completer<Object?>();
      reply = (_) => first.future;
      await pump(tester);
      for (final inset in [300.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        expect(calls.length, 1);
      }
      first.complete(radius);
      await tester.pumpAndSettle();
      expect(outline(tester).bottomLeft.y, 56);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'window resize with keyboard metrics invalidates the old native geometry',
    (tester) async {
      addTearDown(tester.view.reset);
      await pump(tester);
      final resized = Completer<Object?>();
      reply = (_) => resized.future;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.physicalSize = const Size(1000, 654);
      await tester.pump();
      await tester.pump();
      expect(calls.length, 2);
      expect(calls.last.arguments, containsPair('viewWidth', 1000.0));
      expect(outline(tester), BorderRadius.circular(24));
      resized.complete({...radius, 'bottomLeft': 40.0});
      await tester.pumpAndSettle();
      expect(outline(tester).bottomLeft.y, 40);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'non-keyboard metrics and app resume still revalidate identical geometry',
    (tester) async {
      addTearDown(tester.view.reset);
      await pump(tester);
      final stale = Completer<Object?>();
      reply = (_) => stale.future;
      // Native orientation can change without changing logical dimensions.
      tester.binding.handleMetricsChanged();
      await tester.pump();
      expect(calls.length, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      reply = (_) async => {...radius, 'bottomLeft': 40.0};
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.length, 3);
      expect(outline(tester).bottomLeft.y, 40);
      stale.complete(radius);
      await tester.pumpAndSettle();
      expect(outline(tester).bottomLeft.y, 40);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'uses actual panel frame for both fill and continuous clipping; updates on movement',
    (tester) async {
      addTearDown(tester.view.reset);
      await pump(tester);
      expect(calls.single.method, 'resolveSidebar');
      expect(calls.single.arguments, containsPair('x', 16.0));
      expect(calls.single.arguments, containsPair('y', 40.0));
      expect(calls.single.arguments, containsPair('height', 540.0));
      expect(outline(tester).topLeft.x, 48);
      expect(outline(tester).bottomLeft.x, 56);
      expect(outline(tester).topRight.x, 24);
      await pump(tester, left: 32, top: 64);
      expect(calls.length, 2);
      expect(calls.last.arguments, containsPair('y', 64.0));
      await tester.pump();
      expect(calls.length, 2); // No per-frame requests from normal rebuilds.
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'sync hugs the left edge and follows the exact native corner used by the panel',
    (tester) async {
      addTearDown(tester.view.reset);
      void verify(double corner, double gap) {
        final panel = tester.getRect(find.byType(MobileSidebarSurface));
        final sync = tester.getRect(find.byType(MobileSyncStatus));
        final bar = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.constraints?.maxWidth == 6 &&
                widget.constraints?.maxHeight == 50,
          ),
        );
        expect(outline(tester).bottomLeft.y, corner);
        expect(bar.left, panel.left);
        expect(panel.bottom - sync.bottom, gap);
        expect(
          tester.getRect(find.text('Vizor is synced')).left,
          panel.left + 6 + AppSpacing.s,
        );
        expect(tester.takeException(), isNull);
      }

      await pump(tester, panel: sidebar());
      verify(56, 56 + AppSpacing.sm);
      reply = (_) async => {...radius, 'bottomLeft': 39.0};
      await pump(tester, left: 32, panel: sidebar());
      verify(39, 39 + AppSpacing.sm);
      // Safety replaces the corner gap when larger; it is never added to it.
      await pump(tester, left: 32, panel: sidebar(bottomInset: 80));
      verify(39, 80);
      reply = (_) async => null;
      await pump(tester, left: 48, panel: sidebar());
      verify(AppRadii.large, AppRadii.large + AppSpacing.sm);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'rejects late results and falls back when current native geometry is invalid',
    (tester) async {
      addTearDown(tester.view.reset);
      final first = Completer<Object?>();
      reply = (_) => calls.length == 1
          ? first.future
          : Future.value({'topLeft': double.nan});
      await pump(tester);
      await pump(tester, left: 32);
      expect(outline(tester), BorderRadius.circular(24));
      first.complete(radius);
      await tester.pumpAndSettle();
      expect(outline(tester), BorderRadius.circular(24));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Android uses its fallback outline without calling UIKit', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pump(tester);
    expect(calls, isEmpty);
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(MobileSidebarSurface),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(
      (decorated.decoration as ShapeDecoration).shape,
      isA<RoundedRectangleBorder>(),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
