import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';

void main() {
  testWidgets('a captured back callback checks protection before navigation', (
    tester,
  ) async {
    await tester.pumpWidget(_backResolverHarness(initialLocation: '/receive'));
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(AppRouteBackLink));
    final router = GoRouter.of(element);
    final container = ProviderScope.containerOf(element, listen: false);
    final back = tester.widget<AppBackLink>(find.byType(AppBackLink)).onTap;
    final lease = container
        .read(externalActionGuardProvider.notifier)
        .tryProtect()!;
    await back();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/receive');
    lease.release();
    await back();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets(
    'accepted back cleanup prevents persistence until navigation settles',
    (tester) async {
      final cleanup = Completer<void>();
      await tester.pumpWidget(
        _backResolverHarness(
          initialLocation: '/receive',
          onBeforeNavigate: () => cleanup.future,
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(AppRouteBackLink));
      final container = ProviderScope.containerOf(element, listen: false);
      final back = tester.widget<AppBackLink>(find.byType(AppBackLink)).onTap;
      final navigation = Future<void>.value(back());
      expect(
        container.read(externalActionGuardProvider).pendingNavigationCount,
        1,
      );
      expect(
        container.read(externalActionGuardProvider.notifier).tryProtect(),
        isNull,
      );
      cleanup.complete();
      await navigation;
      await tester.pumpAndSettle();
      expect(
        container.read(externalActionGuardProvider).pendingNavigationCount,
        0,
      );
    },
  );

  testWidgets(
    'falls back to Home when the current route has no previous route',
    (tester) async {
      await tester.pumpWidget(
        _backResolverHarness(initialLocation: '/receive'),
      );
      await tester.pump();

      expect(find.text('Home'), findsOneWidget);
    },
  );

  testWidgets('uses the actual previous route for pushed transaction details', (
    tester,
  ) async {
    await tester.pumpWidget(_backResolverHarness(initialLocation: '/home'));
    await tester.pump();

    await tester.tap(find.text('Open Home Tx'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Activity'), findsNothing);
  });

  testWidgets('updates the label when the same route is pushed from activity', (
    tester,
  ) async {
    await tester.pumpWidget(_backResolverHarness(initialLocation: '/activity'));
    await tester.pump();

    await tester.tap(find.text('Open Activity Tx'));
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('uses Send when review is pushed from send', (tester) async {
    await tester.pumpWidget(_backResolverHarness(initialLocation: '/send'));
    await tester.pump();

    await tester.tap(find.text('Open Review'));
    await tester.pumpAndSettle();

    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('uses Swap when transaction details are pushed from swap', (
    tester,
  ) async {
    await tester.pumpWidget(_backResolverHarness(initialLocation: '/swap'));
    await tester.pump();

    await tester.tap(find.text('Open Swap Tx'));
    await tester.pumpAndSettle();

    expect(find.text('Swap'), findsOneWidget);
  });

  testWidgets('keeps send status pinned to Home', (tester) async {
    await tester.pumpWidget(_backResolverHarness(initialLocation: '/send'));
    await tester.pump();

    await tester.tap(find.text('Open Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Status'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Review'), findsNothing);
  });

  testWidgets('uses voting route labels for pushed poll screens', (
    tester,
  ) async {
    await tester.pumpWidget(_backResolverHarness(initialLocation: '/voting'));
    await tester.pump();

    await tester.tap(find.text('Open Poll'));
    await tester.pumpAndSettle();

    expect(find.text('Vote'), findsOneWidget);

    await tester.tap(find.text('Open Voting Review'));
    await tester.pumpAndSettle();

    expect(find.text('Voting round'), findsOneWidget);
  });
}

Widget _backResolverHarness({
  required String initialLocation,
  FutureOr<void> Function()? onBeforeNavigate,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const _PushRouteButton(
          label: 'Open Home Tx',
          location: '/activity/tx/home-tx',
        ),
      ),
      GoRoute(
        path: '/receive',
        builder: (_, _) => AppRouteBackLink(onBeforeNavigate: onBeforeNavigate),
      ),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Column(
          children: [
            AppRouteBackLink(),
            _PushRouteButton(
              label: 'Open Activity Tx',
              location: '/activity/tx/activity-tx',
            ),
          ],
        ),
      ),
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, _) => const AppRouteBackLink(),
      ),
      GoRoute(
        path: '/swap',
        builder: (_, _) => const Column(
          children: [
            AppRouteBackLink(),
            _PushRouteButton(
              label: 'Open Swap Tx',
              location: '/activity/tx/swap-tx',
            ),
          ],
        ),
      ),
      GoRoute(
        path: '/address-book',
        builder: (_, _) => const AppRouteBackLink(),
      ),
      GoRoute(
        path: '/send',
        builder: (_, _) => const Column(
          children: [
            AppRouteBackLink(),
            _PushRouteButton(label: 'Open Review', location: '/send/review'),
          ],
        ),
      ),
      GoRoute(
        path: '/send/review',
        builder: (_, _) => const Column(
          children: [
            AppRouteBackLink(),
            _PushRouteButton(label: 'Open Status', location: '/send/status'),
          ],
        ),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, _) => const AppRouteBackLink(),
      ),
      GoRoute(
        path: '/voting',
        builder: (_, _) => const Column(
          children: [
            AppRouteBackLink(),
            _PushRouteButton(
              label: 'Open Poll',
              location: '/voting/poll/round-1',
            ),
          ],
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId',
        builder: (_, _) => const Column(
          children: [
            AppRouteBackLink(),
            _PushRouteButton(
              label: 'Open Voting Review',
              location: '/voting/poll/round-1/review',
            ),
          ],
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/review',
        builder: (_, _) => const AppRouteBackLink(),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _PushRouteButton extends StatelessWidget {
  const _PushRouteButton({required this.label, required this.location});

  final String label;
  final String location;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.push(location),
      child: Text(label),
    );
  }
}
