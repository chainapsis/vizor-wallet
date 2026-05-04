import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/about/screens/about_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

void main() {
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
    expect(find.text('Version: 0.1.24 Public Beta'), findsOneWidget);
  });

  testWidgets('Terms and Privacy are public before wallet creation', (
    tester,
  ) async {
    await _setDesktopViewport(tester);

    await tester.pumpWidget(_appHarness(_emptyBootstrap('/terms')));
    await tester.pumpAndSettle();

    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Private Money.\nFor the New Internet'), findsNothing);

    await tester.pumpWidget(_appHarness(_emptyBootstrap('/privacy')));
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Private Money.\nFor the New Internet'), findsNothing);
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

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _appHarness(AppBootstrapState bootstrap) {
  return ProviderScope(
    overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    child: const ZcashWalletApp(),
  );
}

Widget _routerHarness(GoRouter router, AppBootstrapState bootstrap) {
  return ProviderScope(
    overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
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
