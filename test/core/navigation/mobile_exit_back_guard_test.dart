@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_exit_back_guard.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

_ExitBackTestRouter _exitBackRouter({
  MobileExitBackGuard? exitBackGuard,
  String initialLocation = '/home',
  List<RouteBase> routes = const [],
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  final guard =
      exitBackGuard ?? MobileExitBackGuard(platform: TargetPlatform.android);
  late final GoRouter router;
  final dispatcher = MobileExitBackDispatcher(
    exitBackGuard: guard,
    navigatorKey: navigatorKey,
    canPop: () => router.canPop(),
    currentLocation: () =>
        router.routerDelegate.currentConfiguration.uri.toString(),
  );
  addTearDown(dispatcher.dispose);
  router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    routes: routes.isEmpty
        ? [
            _placeholderRoute('/home', 'Home route'),
            _placeholderRoute('/detail', 'Detail route'),
          ]
        : routes,
  );
  return _ExitBackTestRouter(
    router: router,
    dispatcher: dispatcher,
    exitBackGuard: guard,
  );
}

class _ExitBackTestRouter {
  const _ExitBackTestRouter({
    required this.router,
    required this.dispatcher,
    required this.exitBackGuard,
  });

  final GoRouter router;
  final MobileExitBackDispatcher dispatcher;
  final MobileExitBackGuard exitBackGuard;
}

GoRoute _placeholderRoute(String path, String label) => GoRoute(
  path: path,
  builder: (_, _) => Center(child: Text(label)),
);

Widget _app(
  _ExitBackTestRouter testRouter, {
  AppThemeData theme = AppThemeData.dark,
}) => MaterialApp.router(
  routeInformationProvider: testRouter.router.routeInformationProvider,
  routeInformationParser: testRouter.router.routeInformationParser,
  routerDelegate: testRouter.router.routerDelegate,
  backButtonDispatcher: testRouter.dispatcher,
  onNavigationNotification: testRouter.dispatcher.handleNavigationNotification,
  builder: (_, child) => AppTheme(data: theme, child: child!),
);

List<MethodCall> _capturePlatformCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

int _systemNavigatorPopCallCount(List<MethodCall> calls) =>
    calls.where((call) => call.method == 'SystemNavigator.pop').length;

void _clearExitHint(_ExitBackTestRouter testRouter) {
  testRouter.exitBackGuard.reset();
  MobileExitBackGuard.dismissVisibleHint();
}

void main() {
  tearDown(MobileExitBackGuard.dismissVisibleHint);

  testWidgets('android root back shows a lower exit hint before exiting', (
    tester,
  ) async {
    final platformCalls = _capturePlatformCalls(tester);
    final testRouter = _exitBackRouter();
    await tester.pumpWidget(_app(testRouter));
    await tester.pumpAndSettle();

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();

    final surfaceFinder = find.byKey(
      const ValueKey('mobile_exit_back_hint_surface'),
    );
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsOneWidget);
    expect(surfaceFinder, findsOneWidget);

    final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
    final hintCenter = tester.getCenter(surfaceFinder);
    expect(hintCenter.dy, greaterThan(screenHeight * 0.55));
    expect(hintCenter.dy, lessThan(screenHeight * 0.8));
    expect(_systemNavigatorPopCallCount(platformCalls), 0);

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();
    expect(_systemNavigatorPopCallCount(platformCalls), 1);
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsNothing);
  });

  testWidgets('android root back requires the second press inside the window', (
    tester,
  ) async {
    final testRouter = _exitBackRouter();
    await tester.pumpWidget(_app(testRouter));
    await tester.pumpAndSettle();

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsOneWidget);

    await tester.pump(MobileExitBackGuard.confirmationWindow);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsNothing);

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsOneWidget);
    _clearExitHint(testRouter);
  });

  testWidgets('android root back confirmation resets after app lifecycle', (
    tester,
  ) async {
    final platformCalls = _capturePlatformCalls(tester);
    final testRouter = _exitBackRouter();
    await tester.pumpWidget(_app(testRouter));
    await tester.pumpAndSettle();

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text(MobileExitBackGuard.exitHintMessage), findsNothing);

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsOneWidget);
    expect(_systemNavigatorPopCallCount(platformCalls), 0);
    _clearExitHint(testRouter);
  });

  testWidgets('android root back guard covers unlock and onboarding routes', (
    tester,
  ) async {
    final platformCalls = _capturePlatformCalls(tester);
    final testRouter = _exitBackRouter(
      initialLocation: '/unlock',
      routes: [
        _placeholderRoute('/unlock', 'Unlock route'),
        _placeholderRoute('/welcome', 'Welcome route'),
      ],
    );
    await tester.pumpWidget(_app(testRouter));
    await tester.pumpAndSettle();

    expect(find.text('Unlock route'), findsOneWidget);

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsOneWidget);
    expect(_systemNavigatorPopCallCount(platformCalls), 0);

    testRouter.exitBackGuard.reset();
    MobileExitBackGuard.dismissVisibleHint();
    testRouter.router.go('/welcome');
    await tester.pumpAndSettle();
    expect(find.text('Welcome route'), findsOneWidget);

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsOneWidget);
    expect(_systemNavigatorPopCallCount(platformCalls), 0);
    _clearExitHint(testRouter);
  });

  testWidgets('android pushed routes pop before the exit hint is considered', (
    tester,
  ) async {
    final testRouter = _exitBackRouter();
    await tester.pumpWidget(_app(testRouter));
    await tester.pumpAndSettle();

    testRouter.router.push('/detail');
    await tester.pumpAndSettle();
    expect(find.text('Detail route'), findsOneWidget);

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('Detail route'), findsNothing);
    expect(find.text('Home route'), findsOneWidget);
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsNothing);
  });

  testWidgets('exit hint follows the resolved app theme', (tester) async {
    final testRouter = _exitBackRouter();
    await tester.pumpWidget(_app(testRouter, theme: AppThemeData.light));
    await tester.pumpAndSettle();

    expect(await testRouter.dispatcher.didPopRoute(), isTrue);
    await tester.pump();

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('mobile_exit_back_hint_surface')),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, AppThemeData.light.colors.background.inverse);

    final text = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_exit_back_hint_text')),
    );
    expect(text.style?.color, AppThemeData.light.colors.text.inverse);
    expect(text.style?.decoration, TextDecoration.none);
    _clearExitHint(testRouter);
  });

  testWidgets('non-Android mobile platforms do not intercept root back', (
    tester,
  ) async {
    final testRouter = _exitBackRouter(
      exitBackGuard: MobileExitBackGuard(platform: TargetPlatform.iOS),
    );
    await tester.pumpWidget(_app(testRouter));
    await tester.pumpAndSettle();

    expect(await testRouter.dispatcher.didPopRoute(), isFalse);
    await tester.pump();
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsNothing);
  });
}
