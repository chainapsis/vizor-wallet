@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';

Future<void> _setMobileViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GoRouter _router(AppThemeData theme) {
  return GoRouter(
    initialLocation: '/pay/submitted/intent-1',
    routes: [
      GoRoute(
        path: '/pay/submitted/:intentId',
        builder: (context, state) => AppTheme(
          data: theme,
          child: MobilePaySubmittedScreen(
            intentId: state.pathParameters['intentId']!,
          ),
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
      GoRoute(
        path: '/activity/swap/:intentId',
        builder: (_, state) => Text(
          'activity:${state.pathParameters['intentId']}:${state.uri.queryParameters['from']}',
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('renders the Figma payment submitted state', (tester) async {
    await _setMobileViewport(tester);
    final router = _router(AppThemeData.light);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.text('Payment\nSubmitted'), findsOneWidget);
    expect(
      find.text('It will confirm on-chain shortly.\nTrack it in Activity.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pay_submitted_status')), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Go to activity'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/illustrations/pay_submitted_background_light.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the payment activity for the started intent', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    final router = _router(AppThemeData.dark);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay_submitted_activity')));
    await tester.pumpAndSettle();

    expect(find.text('activity:intent-1:pay'), findsOneWidget);
  });
}
