import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/core/widgets/app_decorative_divider.dart';
import 'package:zcash_wallet/src/features/about/screens/about_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _utilityPageScrollbarKey = ValueKey('utility-page-scrollbar');

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('About Vizor sidebar item opens the About page', (tester) async {
    await _setDesktopViewport(tester);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => AppDesktopShell(
            sidebar: const AppMainSidebar(),
            pane: AppDesktopPane(
              child: Text(
                'home route',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppThemeData.light.colors.text.primary,
                ),
              ),
            ),
          ),
        ),
        GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
        GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const Text('receive route'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const Text('activity route'),
        ),
        GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      ],
    );

    await tester.pumpWidget(_routerHarness(router, _walletBootstrap('/home')));

    await tester.tap(find.text('About Vizor'));
    await tester.pumpAndSettle();

    expect(find.text('About Vizor Wallet'), findsOneWidget);
    expect(find.text('Version: 0.0.0 Public Beta'), findsOneWidget);
    expect(find.text('Built by the Keplr team'), findsOneWidget);
    expect(find.text('Designed for shielded Zcash'), findsOneWidget);
    expect(
      find.text('Open source, verifiable, and self-custodial'),
      findsOneWidget,
    );
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
  });

  testWidgets('About sidebar navigation uses the standard Home back target', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    final router = GoRouter(
      initialLocation: '/send',
      routes: [
        GoRoute(
          path: '/send',
          builder: (_, _) => AppDesktopShell(
            sidebar: const AppMainSidebar(),
            pane: AppDesktopPane(
              child: Text(
                'send route',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppThemeData.light.colors.text.primary,
                ),
              ),
            ),
          ),
        ),
        GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
        GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const Text('receive route'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const Text('activity route'),
        ),
        GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      ],
    );

    await tester.pumpWidget(_routerHarness(router, _walletBootstrap('/send')));

    await tester.tap(find.text('About Vizor'));
    await tester.pumpAndSettle();

    expect(find.text('About Vizor Wallet'), findsOneWidget);
    final backLink = find.byType(AppRouteBackLink);
    expect(
      find.descendant(of: backLink, matching: find.text('Home')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: backLink, matching: find.text('Home')),
    );
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('utility scrollbars fill the pane edge', (tester) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/terms',
          routes: [
            GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
          ],
        ),
        _emptyBootstrap('/terms'),
      ),
    );
    await tester.pumpAndSettle();

    _expectScrollbarFillsPaneEdge(tester, const Size(1280, 900));
    _expectUtilityContentCentered(
      tester,
      const Size(1280, 900),
      headingText: 'From the team that brought you Keplr Wallet.',
    );

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/about',
          routes: [
            GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
          ],
        ),
        _walletBootstrap('/about'),
      ),
    );
    await tester.pumpAndSettle();

    _expectScrollbarFillsPaneEdge(tester, const Size(1280, 900));
    _expectUtilityContentCentered(
      tester,
      const Size(1280, 900),
      headingText: 'Built by the Keplr team',
    );
  });

  testWidgets('legal back row scrolls with the page content', (tester) async {
    const viewport = Size(1280, 520);
    await _setViewport(tester, viewport);

    await tester.pumpWidget(
      _routerHarness(
        GoRouter(
          initialLocation: '/terms',
          routes: [
            GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
          ],
        ),
        _emptyBootstrap('/terms'),
      ),
    );
    await tester.pumpAndSettle();

    _expectScrollbarFillsPaneEdge(tester, viewport);

    final backTopBeforeScroll = tester.getTopLeft(find.text('Back')).dy;
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    final backTopAfterScroll = tester.getTopLeft(find.text('Back')).dy;

    expect(backTopAfterScroll, lessThan(backTopBeforeScroll));
  });

  testWidgets('legal back link reuses shared back link style', (tester) async {
    await _setDesktopViewport(tester);

    final router = GoRouter(
      initialLocation: '/terms',
      routes: [
        GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
        GoRoute(path: '/welcome', builder: (_, _) => const Text('welcome')),
      ],
    );

    await tester.pumpWidget(_routerHarness(router, _emptyBootstrap('/terms')));
    await tester.pumpAndSettle();

    final backLink = find.byType(AppBackLink);
    expect(
      find.descendant(of: backLink, matching: find.text('Back')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: backLink, matching: find.text('Back')),
    );
    await tester.pumpAndSettle();

    expect(find.text('welcome'), findsOneWidget);
  });

  testWidgets('Terms and Privacy are public before wallet creation', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(_appHarness(_emptyBootstrap('/terms')));
    await tester.pumpAndSettle();

    expect(find.text('Terms of Use'), findsOneWidget);
    expect(
      find.text('Behind the Vizor.\nYour money stays private.'),
      findsNothing,
    );

    await tester.pumpWidget(_appHarness(_emptyBootstrap('/privacy')));
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(
      find.text('Behind the Vizor.\nYour money stays private.'),
      findsNothing,
    );
  });

  testWidgets('welcome footer links open legal pages', (tester) async {
    await _setDesktopViewport(tester);

    final router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
        GoRoute(
          path: '/privacy',
          builder: (_, _) => const PrivacyPolicyScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      _routerHarness(router, _emptyBootstrap('/welcome')),
    );

    await tester.tap(find.text('Terms'));
    await tester.pumpAndSettle();
    expect(find.text('Terms of Use'), findsOneWidget);

    router.go('/welcome');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);
  });
}

Future<void> _loadAppFonts() async {
  final libreCaslonText = FontLoader('Libre Caslon Text')
    ..addFont(rootBundle.load('assets/fonts/LibreCaslonText-Regular.ttf'));
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));

  await Future.wait([libreCaslonText.load(), geist.load()]);
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await _setViewport(tester, const Size(1280, 900));
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _appHarness(AppBootstrapState bootstrap) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
    child: const ZcashWalletApp(),
  );
}

Widget _routerHarness(GoRouter router, AppBootstrapState bootstrap) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

void _expectScrollbarFillsPaneEdge(WidgetTester tester, Size viewport) {
  final scrollbarRect = tester.getRect(find.byKey(_utilityPageScrollbarKey));
  expect(scrollbarRect.top, moreOrLessEquals(AppSpacing.xs));
  expect(scrollbarRect.right, moreOrLessEquals(viewport.width - AppSpacing.xs));
  expect(
    scrollbarRect.bottom,
    moreOrLessEquals(viewport.height - AppSpacing.xs),
  );
}

void _expectUtilityContentCentered(
  WidgetTester tester,
  Size viewport, {
  required String headingText,
}) {
  final scrollbarRect = tester.getRect(find.byKey(_utilityPageScrollbarKey));
  final dividerRect = tester.getRect(find.byType(AppDecorativeDivider).last);
  expect(dividerRect.width, moreOrLessEquals(256));
  expect(dividerRect.center.dx, moreOrLessEquals(scrollbarRect.center.dx));

  final headingRect = tester.getRect(find.text(headingText).first);
  expect(headingRect.left, greaterThan(scrollbarRect.left + 100));
}

AppBootstrapState _emptyBootstrap(String initialLocation) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: const AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: false,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
  );
}

AppBootstrapState _walletBootstrap(String initialLocation) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: const AccountState(
      accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1aboutscreenaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}
