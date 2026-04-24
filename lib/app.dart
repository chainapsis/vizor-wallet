import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';

import 'main.dart' show log;
import 'src/app_bootstrap.dart';
import 'src/core/motion/onboarding_motion.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/legacy_material_theme.dart';
import 'src/features/home/screens/home_screen.dart';
import 'src/features/onboarding/create/address_types_screen.dart';
import 'src/features/onboarding/create/intro_zcash_screen.dart';
import 'src/features/onboarding/create/onboarding_split_view.dart';
import 'src/features/onboarding/create/secret_passphrase_screen.dart';
import 'src/features/onboarding/create/things_to_know_screen.dart';
import 'src/features/onboarding/import/import_secret_passphrase_screen.dart';
import 'src/features/onboarding/import/import_split_view.dart';
import 'src/features/onboarding/import/import_wallet_birthday_screen.dart';
import 'src/features/onboarding/shared/onboarding_flow_args.dart';
import 'src/features/onboarding/shared/set_password_screen.dart';
import 'src/features/onboarding/unlock_screen.dart';
import 'src/features/onboarding/welcome.dart';
import 'src/features/history/screens/history_screen.dart';
import 'src/features/receive/screens/receive_screen.dart';
import 'src/features/accounts/screens/accounts_screen.dart';
import 'src/features/keystone/screens/import_keystone_screen.dart';
import 'src/features/send/screens/send_review_screen.dart';
import 'src/features/send/screens/send_screen.dart';
import 'src/features/send/screens/send_status_screen.dart';
import 'src/features/settings/screens/settings_screen.dart';
import 'src/providers/theme_mode_provider.dart';
import 'src/providers/app_security_provider.dart';
import 'src/providers/router_refresh_provider.dart';
import 'src/providers/wallet_provider.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final bootstrap = ref.watch(appBootstrapProvider);
  final refresh = ref.watch(routerRefreshProvider);
  ref.listen(walletProvider, (_, _) {
    refresh.requestRefresh();
  });
  ref.listen(appSecurityProvider, (_, _) {
    refresh.requestRefresh();
  });
  log('router: initialized');

  return GoRouter(
    initialLocation: bootstrap.initialLocation,
    refreshListenable: refresh,
    redirect: (context, state) {
      final walletAsync = ref.read(walletProvider);
      final security = ref.read(appSecurityProvider);

      // Don't redirect on error — let the error screen show instead of onboarding
      if (walletAsync.hasError) return null;

      final wallet = walletAsync.value;
      final hasWallet = wallet?.hasWallet ?? bootstrap.hasWallet;
      final isUnlocked = security.isUnlocked || bootstrap.isUnlocked;
      final requiresUnlock = hasWallet && !isUnlocked;
      final isOnboarding =
          state.matchedLocation == '/welcome' ||
          state.matchedLocation == '/add-account' ||
          state.matchedLocation.startsWith('/onboarding/') ||
          state.matchedLocation.startsWith('/import');
      final isUnlock = state.matchedLocation == '/unlock';

      log(
        'router redirect: location=${state.matchedLocation}, hasWallet=$hasWallet, '
        'requiresUnlock=$requiresUnlock, isOnboarding=$isOnboarding',
      );

      if (!hasWallet && isUnlock) return '/welcome';
      if (!hasWallet && !isOnboarding) return '/welcome';
      if (!hasWallet && state.matchedLocation == '/add-account') {
        return '/welcome';
      }
      if (requiresUnlock && !isUnlock) return '/unlock';
      if (!requiresUnlock && isUnlock) return hasWallet ? '/home' : '/welcome';
      if (hasWallet && state.matchedLocation == '/welcome') {
        return requiresUnlock ? '/unlock' : '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, _) {
          final walletAsync = ref.read(walletProvider);
          final security = ref.read(appSecurityProvider);
          if (walletAsync.hasError) return '/home'; // home shows error state
          final wallet = walletAsync.value;
          final hasWallet = wallet?.hasWallet ?? bootstrap.hasWallet;
          final isUnlocked = security.isUnlocked || bootstrap.isUnlocked;
          if (!hasWallet) return '/welcome';
          if (!isUnlocked) return '/unlock';
          return '/home';
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
      GoRoute(
        path: '/add-account',
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
            showPasswordStep: !ref
                .read(appSecurityProvider)
                .isPasswordConfigured,
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
            pageBuilder: (context, state) {
              final args = state.extra is CreateSecretPassphraseArgs
                  ? state.extra as CreateSecretPassphraseArgs
                  : null;

              return CustomTransitionPage<void>(
                key: state.pageKey,
                transitionDuration: kOnboardingForwardDuration,
                reverseTransitionDuration: kOnboardingReverseDuration,
                child: SecretPassphraseScreen(args: args),
                transitionsBuilder: _onboardingFadeTransition,
              );
            },
          ),
          GoRoute(
            path: '/onboarding/set-password',
            redirect: (_, state) {
              final args = state.extra;
              if (args is SetPasswordScreenArgs &&
                  args.flow == SetPasswordFlow.create) {
                return null;
              }
              return OnboardingStep.secretPassphrase.routePath;
            },
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: SetPasswordScreen(
                args: state.extra as SetPasswordScreenArgs,
              ),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
        ],
      ),
      ShellRoute(
        pageBuilder: (context, state, child) => CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: kOnboardingForwardDuration,
          reverseTransitionDuration: kOnboardingReverseDuration,
          child: ImportOnboardingShell(
            activeStep: importOnboardingStepFromLocation(state.matchedLocation),
            showPasswordStep: !ref
                .read(appSecurityProvider)
                .isPasswordConfigured,
            child: child,
          ),
          transitionsBuilder: (_, _, _, child) => child,
        ),
        routes: [
          GoRoute(
            path: '/import',
            pageBuilder: (context, state) {
              final args = state.extra is ImportSecretPassphraseArgs
                  ? state.extra as ImportSecretPassphraseArgs
                  : null;

              return CustomTransitionPage<void>(
                key: state.pageKey,
                transitionDuration: kOnboardingForwardDuration,
                reverseTransitionDuration: kOnboardingReverseDuration,
                child: ImportSecretPassphraseScreen(args: args),
                transitionsBuilder: _onboardingFadeTransition,
              );
            },
          ),
          GoRoute(
            path: '/import/birthday',
            redirect: (_, state) =>
                state.extra is ImportBirthdayArgs ? null : '/import',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: ImportWalletBirthdayScreen(
                args: state.extra as ImportBirthdayArgs,
              ),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: '/import/set-password',
            redirect: (_, state) {
              final args = state.extra;
              if (args is SetPasswordScreenArgs &&
                  args.flow == SetPasswordFlow.importWallet) {
                return null;
              }
              return '/import';
            },
            pageBuilder: (context, state) {
              final args = state.extra as SetPasswordScreenArgs;

              return CustomTransitionPage<void>(
                key: state.pageKey,
                transitionDuration: kOnboardingForwardDuration,
                reverseTransitionDuration: kOnboardingReverseDuration,
                child: SetPasswordScreen(args: args),
                transitionsBuilder: _onboardingFadeTransition,
              );
            },
          ),
        ],
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const UnlockScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/send', builder: (_, _) => const SendScreen()),
      GoRoute(
        path: '/send/review',
        builder: (_, state) {
          final args = state.extra;
          if (args is! SendReviewArgs) return const SendScreen();
          return SendReviewScreen(args: args);
        },
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) {
          final args = state.extra;
          if (args is! SendReviewArgs) return const SendScreen();
          return SendStatusScreen(args: args);
        },
      ),
      GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/import-keystone',
        builder: (_, _) => const ImportKeystoneScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
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
      title: 'Vizor',
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
          // `DesktopWindowTitlebarSafeArea` pads the app content down past the macOS
          // titlebar area when the native full-size content view is
          // enabled, so traffic-light controls don't overlap UI. It is a
          // no-op on Windows and Linux where the native title strip does
          // not overlap Flutter content.
          //
          // The inner `GestureDetector` handles global "tap outside clears
          // focus" — `HitTestBehavior.translucent` lets it receive pointer
          // events over empty regions while descendant GestureDetectors
          // (buttons, TextFields) win the gesture arena first, keeping
          // focused buttons focused when re-clicked.
          child: DesktopWindowTitlebarSafeArea(
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
