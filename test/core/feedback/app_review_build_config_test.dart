@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/config/google_play_config.dart';
import 'package:zcash_wallet/src/core/feedback/app_review.dart';
import 'package:zcash_wallet/src/core/feedback/app_review_host.dart';

import 'app_review_test.dart' show MemoryReviewStore, FakeReviewNative;

void main() {
  test('iOS reviews remain enabled in either Android build configuration', () {
    expect(isNativeAppReviewEnabled(isIOS: true, isAndroid: false), isTrue);
  });

  test('Android reviews follow the compiled degoogle opt-out', () {
    expect(
      isNativeAppReviewEnabled(isIOS: false, isAndroid: true),
      kVizorDegoogled ? isFalse : isTrue,
    );
  });

  test('other platforms do not enable native reviews', () {
    expect(isNativeAppReviewEnabled(isIOS: false, isAndroid: false), isFalse);
  });

  testWidgets('Android host starts only when Google Play is enabled', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final store = MemoryReviewStore(const AppReviewHistory(launches: 2));
    final native = FakeReviewNative();
    final controller = AppReviewController(store: store, native: native);
    var completedActions = 0;
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => Consumer(
            builder: (_, ref, _) => TextButton(
              onPressed: () async {
                expectAppReviewVisit(ref, '/send');
                final result = await duringAppReviewBusy(ref, () async => 42);
                expect(result, 42);
                completedActions++;
              },
              child: const Text('Use wallet'),
            ),
          ),
        ),
      ],
    );
    var controllerReads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appReviewEnabledProvider.overrideWithValue(
            isNativeAppReviewEnabled(isIOS: false, isAndroid: true),
          ),
          appReviewControllerProvider.overrideWith((ref) {
            controllerReads++;
            return controller;
          }),
          appReviewSurfaceSafeProvider.overrideWithValue(true),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => AppReviewHost(router: router, child: child!),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.text('Use wallet'));
    await tester.pump();
    expect(completedActions, 1);
    expect(controllerReads, kVizorDegoogled ? 0 : 1);
    expect(store.value.launches, kVizorDegoogled ? 2 : 3);
    expect(native.preparations, 0);
    expect(native.requests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    controller.dispose();
  });
}
