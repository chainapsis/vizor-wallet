import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';

void main() {
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
}

Widget _backResolverHarness({required String initialLocation}) {
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
      GoRoute(path: '/receive', builder: (_, _) => const AppRouteBackLink()),
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
    ],
  );

  return MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
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
