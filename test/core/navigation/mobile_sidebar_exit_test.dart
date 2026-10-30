@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_navigation_scope.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_destinations.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_sidebar_exit.dart';

Widget _app(GoRouter router, MobileSidebarExitController controller) =>
    MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => MobileNavigationScope(
        mode: MobileNavigationMode.sidebar,
        navigation: MobileBranchNavigation(),
        sidebarExit: controller,
        child: child!,
      ),
    );

void main() {
  test(
    'read-only routes allow navigation and stateful flows require a policy',
    () {
      for (final path in [
        '/home',
        '/accounts',
        '/swap',
        '/activity',
        '/activity/tx/abc',
        '/settings',
        '/settings/endpoint',
        '/receive',
        '/about',
        '/voting',
        '/voting/poll/round/results',
      ]) {
        expect(requiresMobileSidebarExitPolicy(path), isFalse, reason: path);
      }
      for (final path in [
        '/send',
        '/send/amount',
        '/send/review',
        '/send/status',
        '/swap/review',
        '/swap/keystone-sign',
        '/pay',
        '/pay/review',
        '/pay/submitted/intent',
        '/payment-links',
        '/voting/poll/round',
        '/voting/poll/round/status',
        '/migration/options',
        '/migration/private/status',
        '/settings/change-password',
        '/settings/seed-phrase',
        '/settings/viewing-key',
        '/future-wallet-flow',
      ]) {
        expect(requiresMobileSidebarExitPolicy(path), isTrue, reason: path);
      }
    },
  );

  testWidgets('screen state separates menu navigation from account switching', (
    tester,
  ) async {
    final controller = MobileSidebarExitController();
    final busy = ValueNotifier(false);
    final router = GoRouter(
      initialLocation: '/send',
      routes: [
        GoRoute(
          path: '/send',
          builder: (_, _) => ValueListenableBuilder(
            valueListenable: busy,
            builder: (_, value, _) => MobileSidebarExitScope(
              canNavigate: !value,
              child: const SizedBox(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);
    addTearDown(busy.dispose);
    await tester.pumpWidget(_app(router, controller));
    await tester.pumpAndSettle();
    expect(controller.canNavigate('/send', requiresPolicy: true), isTrue);
    expect(controller.canSwitchAccount('/send', requiresPolicy: true), isFalse);
    busy.value = true;
    await tester.pump();
    expect(controller.canNavigate('/send', requiresPolicy: true), isFalse);
    busy.value = false;
    await tester.pump();
    expect(controller.canNavigate('/send', requiresPolicy: true), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cleanup is awaited once, failed cleanup stays retryable', (
    tester,
  ) async {
    final controller = MobileSidebarExitController();
    var cleanup = Completer<bool>();
    var calls = 0;
    final router = GoRouter(
      initialLocation: '/send',
      routes: [
        GoRoute(
          path: '/send',
          builder: (_, _) => MobileSidebarExitScope(
            onExit: () {
              calls++;
              return cleanup.future;
            },
            child: const SizedBox(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(router, controller));
    await tester.pumpAndSettle();
    final first = controller.prepareLeave('/send', requiresPolicy: true);
    expect(calls, 1);
    expect(controller.canNavigate('/send', requiresPolicy: true), isFalse);
    expect(
      await controller.prepareLeave('/send', requiresPolicy: true),
      isFalse,
    );
    expect(calls, 1);
    cleanup.complete(false);
    expect(await first, isFalse);
    cleanup = Completer<bool>();
    final retry = controller.prepareLeave('/send', requiresPolicy: true);
    cleanup.complete(true);
    expect(await retry, isTrue);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'covered routes do not lock the visible page; nested work can block its owner',
    (tester) async {
      final controller = MobileSidebarExitController();
      final router = GoRouter(
        initialLocation: '/send',
        routes: [
          GoRoute(
            path: '/send',
            builder: (_, _) => const MobileSidebarExitScope(
              canNavigate: false,
              child: SizedBox(),
            ),
          ),
          GoRoute(
            path: '/pay',
            builder: (_, _) => const MobileSidebarExitScope(child: SizedBox()),
          ),
          GoRoute(
            path: '/payment-links',
            builder: (_, _) => const MobileSidebarExitScope(
              child: MobileSidebarExitScope(
                canNavigate: false,
                child: SizedBox(),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(router, controller));
      await tester.pumpAndSettle();
      unawaited(router.push('/pay'));
      await tester.pumpAndSettle();
      expect(controller.canNavigate('/pay', requiresPolicy: true), isTrue);
      expect(controller.canNavigate('/send', requiresPolicy: true), isFalse);
      router.go('/payment-links');
      await tester.pumpAndSettle();
      expect(
        controller.canNavigate('/payment-links', requiresPolicy: true),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
