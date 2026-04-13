import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'main.dart' show log;
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/legacy_material_theme.dart';
import 'src/features/home/screens/home_screen.dart';
import 'src/features/onboarding/screens/create_wallet_screen.dart';
import 'src/features/onboarding/screens/import_wallet_screen.dart';
import 'src/features/onboarding/welcome.dart';
import 'src/features/history/screens/history_screen.dart';
import 'src/features/receive/screens/receive_screen.dart';
import 'src/features/accounts/screens/accounts_screen.dart';
import 'src/features/keystone/screens/import_keystone_screen.dart';
import 'src/features/send/screens/send_screen.dart';
import 'src/features/settings/screens/settings_screen.dart';
import 'src/providers/theme_mode_provider.dart';
import 'src/providers/wallet_provider.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final walletAsync = ref.watch(walletProvider);
  log('router: walletAsync=$walletAsync');

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // Don't redirect on error — let the error screen show instead of onboarding
      if (walletAsync.hasError) return null;

      final wallet = walletAsync.value;
      final hasWallet = wallet?.hasWallet ?? false;
      final isOnboarding = state.matchedLocation == '/welcome' ||
          state.matchedLocation == '/create' ||
          state.matchedLocation == '/import';

      log('router redirect: location=${state.matchedLocation}, hasWallet=$hasWallet, isOnboarding=$isOnboarding');

      if (!hasWallet && !isOnboarding) return '/welcome';
      if (hasWallet && state.matchedLocation == '/welcome') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, _) {
          if (walletAsync.hasError) return '/home'; // home shows error state
          final wallet = walletAsync.value;
          final hasWallet = wallet?.hasWallet ?? false;
          return hasWallet ? '/home' : '/welcome';
        },
      ),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/create',
        builder: (_, _) => const CreateWalletScreen(),
      ),
      GoRoute(
        path: '/import',
        builder: (_, _) => const ImportWalletScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const HomeScreen(),
      ),
      GoRoute(
        path: '/send',
        builder: (_, _) => const SendScreen(),
      ),
      GoRoute(
        path: '/receive',
        builder: (_, _) => const ReceiveScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (_, _) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const AccountsScreen(),
      ),
      GoRoute(
        path: '/import-keystone',
        builder: (_, _) => const ImportKeystoneScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsScreen(),
      ),
    ],
  );
});

class ZcashWalletApp extends ConsumerWidget {
  const ZcashWalletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Zcash Wallet',
      debugShowCheckedModeBanner: false,
      theme: buildLegacyLightTheme(),
      darkTheme: buildLegacyDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Resolve themeMode intent → concrete brightness using the OS's
        // current platformBrightness when mode is `system`. Rebuilds when
        // either themeMode or platform brightness changes.
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final brightness = switch (themeMode) {
          ThemeMode.system => platformBrightness,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.light => Brightness.light,
        };
        final appThemeData = brightness == Brightness.dark
            ? AppThemeData.dark
            : AppThemeData.light;
        return AppTheme(
          data: appThemeData,
          // Global "tap outside clears focus" — standard desktop/web
          // behavior. `HitTestBehavior.translucent` lets this GestureDetector
          // receive pointer events over empty regions; taps consumed by a
          // descendant's own GestureDetector (buttons, TextFields) win the
          // gesture arena before this `onTap` fires, so focused buttons
          // stay focused when re-clicked.
          child: GestureDetector(
            onTap: () {
              // Leaf-only: skip when the primary focus is a
              // `FocusScopeNode` rather than a concrete `FocusNode`.
              // Unfocusing the scope itself strips the scope's
              // "most-recently-focused child" memory, which leaves the
              // next Tab with no deterministic starting point.
              final primary = FocusManager.instance.primaryFocus;
              if (primary != null && primary is! FocusScopeNode) {
                primary.unfocus();
              }
            },
            behavior: HitTestBehavior.translucent,
            child: child!,
          ),
        );
      },
    );
  }
}
