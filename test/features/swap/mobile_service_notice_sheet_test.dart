@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/prepared_modal_sheet_route.dart';
import 'package:zcash_wallet/src/core/navigation/route_owned_redirect.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_service_status.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/near_intents_service_status_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/near_intents_service_notice_host.dart';
import 'package:zcash_wallet/src/services/native_modal_corners.dart';

import 'support/service_status_fixture.dart';

const _notice = ValueKey('near_intents_service_notice');
const _ok = ValueKey('near_intents_service_notice_ok');

Widget _app(GlobalKey<NavigatorState> navigator) => ProviderScope(
  overrides: [
    nearIntentsServiceStatusProvider.overrideWith(
      () => FixtureServiceStatusNotifier(serviceStatusFixture()),
    ),
  ],
  child: MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [RouteOwnedNavigationObserver()],
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: const Scaffold(
      body: NearIntentsServiceNoticeHost(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        child: Text('Composer'),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeModalCorners.channel,
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeModalCorners.channel, null);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final keyboard in [false, true]) {
      testWidgets(
        '${platform.name} uses shared sheet chrome with keyboard=$keyboard',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(393, 852);
          tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
          tester.view.padding = FakeViewPadding(
            top: 47,
            bottom: keyboard ? 0 : 34,
          );
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 300 : 0);
          addTearDown(tester.view.reset);
          final navigator = GlobalKey<NavigatorState>();
          await tester.pumpWidget(_app(navigator));
          await tester.pumpAndSettle();

          final route = ModalRoute.of(tester.element(find.byKey(_notice)))!;
          expect(route, isA<ModalBottomSheetRoute<void>>());
          if (platform == TargetPlatform.iOS) {
            expect(route, isA<PreparedModalSheetRoute<void>>());
          }
          expect(find.byType(MobileModalCard), findsOneWidget);
          expect(find.byType(MobileModalScaffold), findsOneWidget);
          final surface = tester.getRect(
            find
                .descendant(
                  of: find.byType(MobileModalCard),
                  matching: find.byType(Material),
                )
                .first,
          );
          final bottom = keyboard ? 552.0 : 852.0;
          final gap = keyboard || platform == TargetPlatform.iOS ? 16.0 : 50.0;
          expect(surface.left, 16);
          expect(surface.width, 361);
          expect(surface.bottom, bottom - gap);
          expect(
            tester.getRect(find.byKey(_ok)).bottom,
            lessThan(surface.bottom),
          );
          expect(
            tester.getRect(find.byType(ModalBarrier).last),
            const Rect.fromLTWH(0, 0, 393, 852),
          );

          await tester.tap(find.byKey(_ok));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 30));
          expect(
            find.byKey(_notice),
            findsOneWidget,
            reason: 'Keep content mounted throughout the shared exit animation',
          );
          await tester.pumpAndSettle();
          expect(find.byKey(_notice), findsNothing);
          expect(find.text('Composer'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }

    for (final dismissal in ['barrier', 'back', 'drag']) {
      testWidgets('${platform.name} $dismissal dismisses without reopening', (
        tester,
      ) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(_app(navigator));
        await tester.pumpAndSettle();
        if (dismissal == 'barrier') {
          await tester.tapAt(const Offset(10, 10));
        } else if (dismissal == 'back') {
          await navigator.currentState!.maybePop();
        } else {
          // Drag the common header rather than the scrollable incident body.
          await tester.drag(
            find.text('Maintenance notice'),
            const Offset(0, 500),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byKey(_notice), findsNothing);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(NearIntentsServiceNoticeHost)),
        );
        (container.read(nearIntentsServiceStatusProvider.notifier)
                as FixtureServiceStatusNotifier)
            .publish(serviceStatusFixture());
        await tester.pumpAndSettle();
        expect(find.byKey(_notice), findsNothing);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant({platform}));
    }

    testWidgets('${platform.name} clears only its sheet below a newer route', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(navigator));
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('New screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New screen'), findsOneWidget);
      expect(find.byKey(_notice, skipOffstage: false), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Composer'), findsOneWidget);
      expect(find.byKey(_notice), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets(
    'clearing status during iOS corner preparation removes the owned route',
    (tester) async {
      final corners = Completer<dynamic>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeModalCorners.channel,
            (_) => corners.future,
          );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(navigator));
      await tester.pump();
      await tester.pump();
      final host = find.byType(
        NearIntentsServiceNoticeHost,
        skipOffstage: false,
      );
      final container = ProviderScope.containerOf(tester.element(host));
      (container.read(nearIntentsServiceStatusProvider.notifier)
              as FixtureServiceStatusNotifier)
          .publish(NearIntentsServiceStatus(now: DateTime.utc(2026, 11, 3)));
      await tester.pumpAndSettle();
      corners.complete(null);
      await tester.pumpAndSettle();
      expect(find.byKey(_notice, skipOffstage: false), findsNothing);
      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.text('Composer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
