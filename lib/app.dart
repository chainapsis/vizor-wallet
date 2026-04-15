import 'package:flutter/material.dart';
import 'package:flutter_acrylic/widgets/titlebar_safe_area.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'main.dart' show log;
import 'src/core/motion/onboarding_motion.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/legacy_material_theme.dart';
import 'src/features/home/screens/home_screen.dart';
import 'src/features/onboarding/screens/address_types_screen.dart';
import 'src/features/onboarding/screens/create_wallet_screen.dart';
import 'src/features/onboarding/screens/import_wallet_screen.dart';
import 'src/features/onboarding/screens/intro_zcash_screen.dart';
import 'src/features/onboarding/screens/onboarding_split_view.dart';
import 'src/features/onboarding/screens/secret_passphrase_screen.dart';
import 'src/features/onboarding/screens/things_to_know_screen.dart';
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
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(walletProvider, (_, _) {
    refresh.value++;
  });
  log('router: initialized');

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final walletAsync = ref.read(walletProvider);

      // Don't redirect on error — let the error screen show instead of onboarding
      if (walletAsync.hasError) return null;

      final wallet = walletAsync.value;
      final hasWallet = wallet?.hasWallet ?? false;
      final isOnboarding =
          state.matchedLocation == '/welcome' ||
          state.matchedLocation.startsWith('/onboarding/') ||
          state.matchedLocation == '/create' ||
          state.matchedLocation == '/import';

      log(
        'router redirect: location=${state.matchedLocation}, hasWallet=$hasWallet, isOnboarding=$isOnboarding',
      );

      if (!hasWallet && !isOnboarding) return '/welcome';
      if (hasWallet && state.matchedLocation == '/welcome') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, _) {
          final walletAsync = ref.read(walletProvider);
          if (walletAsync.hasError) return '/home'; // home shows error state
          final wallet = walletAsync.value;
          final hasWallet = wallet?.hasWallet ?? false;
          return hasWallet ? '/home' : '/welcome';
        },
      ),
      // Onboarding-route transitions. Desktop acrylic visibly stutters
      // through a snapped page swap, so each route gets a custom
      // page builder that lets contents enter while the acrylic stays
      // composited continuously. Welcome cross-fades; IntroZcash
      // delegates the page-level transition to its own widget tree
      // (sidebar slides, trailing pane fades) so the two halves can
      // drive separate motion against the shared route animation.
      // Other routes stay on the GoRouter default.
      GoRoute(
        path: '/welcome',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: kOnboardingForwardDuration,
          reverseTransitionDuration: kOnboardingReverseDuration,
          child: const WelcomeScreen(),
          transitionsBuilder: _onboardingFadeTransition,
        ),
      ),
      ShellRoute(
        pageBuilder: (context, state, child) => CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: kOnboardingForwardDuration,
          reverseTransitionDuration: kOnboardingReverseDuration,
          child: OnboardingSplitViewShell(
            activeStep: onboardingStepFromLocation(state.matchedLocation),
            child: child,
          ),
          transitionsBuilder: (_, _, _, child) => child,
        ),
        routes: [
          GoRoute(
            path: '/onboarding/intro',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const IntroZcashScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: '/onboarding/address-types',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const AddressTypesScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: '/onboarding/things-to-know',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const ThingsToKnowScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: '/onboarding/secret-passphrase',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const SecretPassphraseScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
        ],
      ),
      GoRoute(path: '/create', builder: (_, _) => const CreateWalletScreen()),
      GoRoute(path: '/import', builder: (_, _) => const ImportWalletScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/send', builder: (_, _) => const SendScreen()),
      GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
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

/// Cross-fade for onboarding page-level transitions. Both legs keep the
/// two screens visible during the dissolve so the acrylic backdrop stays
/// unbroken while the opaque inner panes swap. Shares the curve pair
/// with `IntroZcashScreen`'s internal motion via the motion-token
/// constants in `onboarding_motion.dart`.
Widget _onboardingFadeTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final incoming = CurvedAnimation(
    parent: animation,
    curve: kOnboardingForwardCurve,
    reverseCurve: kOnboardingReverseCurve,
  );
  final outgoing = CurvedAnimation(
    parent: secondaryAnimation,
    curve: kOnboardingForwardCurve,
    reverseCurve: kOnboardingReverseCurve,
  );
  return FadeTransition(
    opacity: incoming,
    child: FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.0).animate(outgoing),
      child: child,
    ),
  );
}

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
          // `TitlebarSafeArea` pads the app content down past the macOS
          // titlebar area when flutter_acrylic's full-size content view is
          // enabled, so traffic-light controls don't overlap UI. It is a
          // no-op on Windows and Linux where the native title strip does
          // not overlap Flutter content.
          //
          // The inner `GestureDetector` handles global "tap outside clears
          // focus" — `HitTestBehavior.translucent` lets it receive pointer
          // events over empty regions while descendant GestureDetectors
          // (buttons, TextFields) win the gesture arena first, keeping
          // focused buttons focused when re-clicked.
          child: TitlebarSafeArea(
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
          ),
        );
      },
    );
  }
}
