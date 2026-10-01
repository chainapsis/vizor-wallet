@Tags(['mobile'])
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/feedback/app_review.dart';
import 'package:zcash_wallet/src/core/feedback/app_review_host.dart';
import 'app_review_test.dart' show MemoryReviewStore, FakeReviewNative;

void main() {
  late AppReviewController controller;
  late FakeReviewNative native;
  late AppReviewRouteObserver observer;
  late GoRouter router;
  late ValueNotifier<bool> safe;
  late ScrollController scroll;

  Future<void> mount(
    WidgetTester tester, {
    bool hadWalletAtStartup = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => ValueListenableBuilder<bool>(
          valueListenable: safe,
          builder: (context, safeValue, _) => AppReviewInteractionHost(
            router: router,
            controller: controller,
            observer: observer,
            safe: safeValue,
            readSafety: () => safe.value,
            hadWalletAtStartup: hadWalletAtStartup,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> idle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  }

  setUp(() {
    native = FakeReviewNative();
    controller = AppReviewController(
      store: MemoryReviewStore(const AppReviewHistory(launches: 2)),
      native: native,
    );
    observer = AppReviewRouteObserver();
    safe = ValueNotifier(true);
    scroll = ScrollController();
    router = GoRouter(
      initialLocation: '/home',
      observers: [observer],
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(
            body: shell,
            bottomNavigationBar: Row(
              children: [
                TextButton(
                  onPressed: () => shell.goBranch(0),
                  child: const Text('Home tab'),
                ),
                TextButton(
                  onPressed: () {
                    controller.expectVisit('/settings');
                    shell.goBranch(1);
                  },
                  child: const Text('Settings tab'),
                ),
              ],
            ),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) => ListView(
                    controller: scroll,
                    children: [
                      TextButton(
                        onPressed: () {
                          controller.expectVisit('/receive');
                          context.push('/receive');
                        },
                        child: const Text('Receive'),
                      ),
                      TextButton(
                        onPressed: () => context.push('/accounts'),
                        child: const Text('Accounts'),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Show balance'),
                      ),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            content: SizedBox(
                              height: 150,
                              width: 250,
                              child: ListView(
                                children: const [SizedBox(height: 1000)],
                              ),
                            ),
                          ),
                        ),
                        child: const Text('Dialog'),
                      ),
                      const SizedBox(height: 1800),
                    ],
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (_, _) => const Text('Settings screen'),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const Scaffold(body: Text('Receive screen')),
        ),
        GoRoute(
          path: '/accounts',
          builder: (_, _) => const Scaffold(body: Text('Accounts screen')),
        ),
      ],
    );
  });
  tearDown(() {
    router.dispose();
    observer.dispose();
    controller.dispose();
    safe.dispose();
    scroll.dispose();
  });

  testWidgets('existing users request on first launch only after home usage', (
    tester,
  ) async {
    (controller.store as MemoryReviewStore).value = const AppReviewHistory();
    await mount(tester, hadWalletAtStartup: true);
    await idle(tester);
    expect(controller.history.launches, 1);
    expect(controller.history.existingUser, isTrue);
    expect(native.requests, 0);
    await tester.tap(find.text('Settings tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home tab'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(native.requests, 0);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(native.requests, 1);
  });

  testWidgets(
    'blocked startup leaves classification untouched until recovery',
    (tester) async {
      (controller.store as MemoryReviewStore).value = const AppReviewHistory();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      Widget app(bool? startupWallet) => ProviderScope(
        overrides: [
          appReviewEnabledProvider.overrideWithValue(true),
          appReviewStartupWalletProvider.overrideWithValue(startupWallet),
          appReviewControllerProvider.overrideWithValue(controller),
          appReviewRouteObserverProvider.overrideWithValue(observer),
          appReviewSurfaceSafeProvider.overrideWithValue(true),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => AppReviewHost(router: router, child: child!),
        ),
      );
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      expect((controller.store as MemoryReviewStore).value.launches, 0);
      expect(
        (controller.store as MemoryReviewStore).value.existingUser,
        isNull,
      );
      expect(native.preparations, 0);
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(controller.history.launches, 1);
      expect(controller.history.existingUser, isTrue);
      expect(native.requests, 0);
      await tester.tap(find.text('Settings tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home tab'));
      await tester.pumpAndSettle();
      await idle(tester);
      expect(native.requests, 1);
    },
  );

  testWidgets('no prompt merely from home, balance toggle or account picker', (
    tester,
  ) async {
    await mount(tester);
    await idle(tester);
    expect(native.requests, 0);
    await tester.tap(find.text('Show balance'));
    await idle(tester);
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 0);
  });

  testWidgets(
    'explicit screen visit requests only after return and two idle seconds',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Receive'));
      await tester.pumpAndSettle();
      await idle(tester);
      expect(native.requests, 0);
      router.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(native.requests, 0);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump();
      expect(native.requests, 1);
    },
  );

  testWidgets('home kept mounted under another tab cannot request', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Settings tab'));
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 0);
    await tester.tap(find.text('Home tab'));
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 1);
  });

  testWidgets('programmatic scroll does not qualify, an actual drag does', (
    tester,
  ) async {
    await mount(tester);
    scroll.jumpTo(80);
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 0);
    await tester.drag(find.byType(ListView).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 1);
  });

  testWidgets(
    'any interaction restarts the idle wait without qualifying by itself',
    (tester) async {
      await mount(tester);
      controller.recordUse();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Show balance'));
      await tester.pump(const Duration(seconds: 1));
      expect(native.requests, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(native.requests, 1);
    },
  );

  testWidgets('modal defers eligible usage and retries when dismissed', (
    tester,
  ) async {
    await mount(tester);
    controller.recordUse();
    await tester.tap(find.text('Dialog'));
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 0);
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 1);
  });

  testWidgets('modal scrolling does not count as home usage', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Dialog'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListView),
      ),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    router.routerDelegate.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await idle(tester);
    expect(native.requests, 0);
  });

  testWidgets('lock and lifecycle defer without recounting launches', (
    tester,
  ) async {
    await mount(tester);
    controller.recordUse();
    safe.value = false;
    await tester.pump();
    await idle(tester);
    expect(native.requests, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    safe.value = true;
    await tester.pump();
    await idle(tester);
    expect(native.requests, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await idle(tester);
    expect(native.requests, 1);
    expect(controller.history.launches, 3);
  });

  testWidgets('keyboard defers until closed', (tester) async {
    await mount(tester);
    controller.recordUse();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await idle(tester);
    expect(native.requests, 0);
    tester.view.resetViewInsets();
    await tester.pump();
    await idle(tester);
    expect(native.requests, 1);
  });

  testWidgets('route change during asynchronous native preparation cancels', (
    tester,
  ) async {
    await mount(tester);
    native.preparation = Completer<bool>();
    controller.recordUse();
    await idle(tester);
    router.go('/settings');
    await tester.pumpAndSettle();
    native.preparation!.complete(true);
    await tester.pump();
    expect(native.requests, 0);
    expect(controller.history.requests, 0);
  });
  testWidgets(
    'cancelled preparation re-arms after a modal has already closed',
    (tester) async {
      await mount(tester);
      native.preparation = Completer<bool>();
      controller.recordUse();
      await idle(tester);
      await tester.tap(find.text('Dialog'));
      await tester.pumpAndSettle();
      router.routerDelegate.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      native.preparation!.complete(true);
      await tester.pump();
      expect(native.requests, 0);
      native.preparation = null;
      await idle(tester);
      expect(native.requests, 1);
      expect(controller.history.requests, 1);
    },
  );
  testWidgets(
    'an interrupted gesture cannot block the next foreground opportunity',
    (tester) async {
      await mount(tester);
      controller.recordUse();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Show balance')),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await idle(tester);
      expect(native.requests, 1);
      await gesture.cancel();
    },
  );
  testWidgets('locking before the next frame cancels pending native dispatch', (
    tester,
  ) async {
    await mount(tester);
    native.preparation = Completer<bool>();
    controller.recordUse();
    await idle(tester);
    safe.value = false;
    native.preparation!.complete(true);
    await tester.idle();
    expect(native.requests, 0);
    expect(controller.history.requests, 0);
    await tester.pump();
    native.preparation = null;
    safe.value = true;
    await idle(tester);
    expect(native.requests, 1);
  });
  testWidgets(
    'home scrolling ending under a modal cannot lose the deferred opportunity',
    (tester) async {
      await mount(tester);
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, -200),
        1000,
      );
      unawaited(
        showDialog<void>(
          context: router.routerDelegate.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(content: Text('Covered home')),
        ),
      );
      await tester.pumpAndSettle();
      await idle(tester);
      expect(native.requests, 0);
      router.routerDelegate.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await idle(tester);
      expect(native.requests, 1);
    },
  );
}
