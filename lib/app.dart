import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:go_router/go_router.dart';
import 'package:desktop_window_bootstrap/desktop_window_bootstrap.dart';
import 'package:url_launcher/url_launcher.dart';

import 'src/app_bootstrap.dart';
import 'src/core/layout/app_layout.dart';
import 'src/core/motion/onboarding_motion.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/app_theme_host.dart';
import 'src/core/theme/legacy_material_theme.dart';
import 'src/core/widgets/app_button.dart';
import 'src/core/widgets/app_icon.dart';
import 'src/core/widgets/network_fallback_toast.dart';
import 'src/features/activity/screens/activity_screen.dart';
import 'src/features/activity/screens/activity_transaction_status_screen.dart';
import 'src/features/accounts/screens/accounts_screen.dart';
import 'src/features/home/screens/home_screen.dart';
import 'src/features/about/screens/about_screen.dart';
import 'src/features/onboarding/create/address_types_screen.dart';
import 'src/features/onboarding/create/intro_zcash_screen.dart';
import 'src/features/onboarding/create/onboarding_split_view.dart';
import 'src/features/onboarding/create/secret_passphrase_screen.dart';
import 'src/features/onboarding/create/things_to_know_screen.dart';
import 'src/features/onboarding/import/import_secret_passphrase_screen.dart';
import 'src/features/onboarding/import/import_split_view.dart';
import 'src/features/onboarding/import/import_wallet_birthday_screen.dart';
import 'src/features/onboarding/keystone/keystone_how_to_connect_screen.dart';
import 'src/features/onboarding/keystone/keystone_onboarding_flow.dart';
import 'src/features/onboarding/keystone/keystone_scan_qr_screen.dart';
import 'src/features/onboarding/keystone/keystone_select_account_screen.dart';
import 'src/features/onboarding/keystone/keystone_wallet_birthday_screen.dart';
import 'src/features/onboarding/lost_password_screen.dart';
import 'src/features/onboarding/shared/onboarding_flow_args.dart';
import 'src/features/onboarding/shared/set_password_screen.dart';
import 'src/features/onboarding/storage_unavailable_screen.dart';
import 'src/features/onboarding/unlock_screen.dart';
import 'src/features/onboarding/welcome.dart';
import 'src/features/receive/screens/receive_screen.dart';
import 'src/features/send/screens/keystone_send_scan_screen.dart';
import 'src/features/send/screens/send_review_screen.dart';
import 'src/features/send/screens/send_screen.dart';
import 'src/features/send/screens/send_status_screen.dart';
import 'src/features/settings/screens/settings_screen.dart';
import 'src/features/settings/screens/settings_change_password_screen.dart';
import 'src/features/settings/screens/settings_endpoint_screen.dart';
import 'src/features/settings/screens/settings_seed_phrase_screen.dart';
import 'src/features/voting/screens/voting_polls_screen.dart';
import 'src/features/voting/screens/voting_proposal_detail_screen.dart';
import 'src/features/voting/screens/voting_results_screen.dart';
import 'src/features/voting/screens/voting_review_screen.dart';
import 'src/features/voting/screens/voting_status_screen.dart';
import 'src/features/voting/screens/voting_submission_confirmation_screen.dart';
import 'src/features/voting/screens/keystone_voting_scan_screen.dart';
import 'src/features/voting/screens/voting_software_account_guard.dart';
import 'src/providers/theme_mode_provider.dart';
import 'src/providers/app_security_provider.dart';
import 'src/providers/linux_update_provider.dart';
import 'src/providers/rpc_endpoint_failover_provider.dart';
import 'src/providers/router_refresh_provider.dart';
import 'src/providers/wallet_provider.dart';
import 'src/providers/windows_update_provider.dart';
import 'src/rust/frb_generated.dart';

void log(String message) => debugPrint('[zcash] $message');

Future<void> initializeZcashWalletRuntime() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  log('runtime: initializing RustLib');
  await RustLib.init();

  // Order matters: window_manager creates and shows the NSWindow inside
  // `initializeDesktopWindow`; the acrylic setup is only effective once
  // that window exists.
  log('runtime: initializing desktop window (no-op on mobile/web)');
  await initializeDesktopWindow();
  if (isDesktopLayoutPlatform) {
    log('runtime: initializing desktop window visuals');
    await DesktopWindowBootstrap.initialize();
    if (!Platform.isWindows) {
      await showDesktopWindow();
    }
  }
}

Future<Widget> buildBootstrappedZcashWalletApp({
  List<Override> overrides = const [],
}) async {
  final bootstrap = await loadAppBootstrap();
  return BootstrappedZcashWalletApp(
    initialBootstrap: bootstrap,
    overrides: overrides,
  );
}

Widget buildZcashWalletApp({
  required AppBootstrapState bootstrap,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap),
      appBootstrapRetryProvider.overrideWithValue(() async {}),
      ...overrides,
    ],
    child: const ZcashWalletApp(),
  );
}

class BootstrappedZcashWalletApp extends StatefulWidget {
  const BootstrappedZcashWalletApp({
    required this.initialBootstrap,
    this.overrides = const [],
    super.key,
  });

  final AppBootstrapState initialBootstrap;
  final List<Override> overrides;

  @override
  State<BootstrappedZcashWalletApp> createState() =>
      _BootstrappedZcashWalletAppState();
}

class _BootstrappedZcashWalletAppState
    extends State<BootstrappedZcashWalletApp> {
  late AppBootstrapState _bootstrap = widget.initialBootstrap;
  var _scopeGeneration = 0;

  Future<void> _reloadBootstrap() async {
    final bootstrap = await loadAppBootstrap();
    if (!mounted) return;
    setState(() {
      _bootstrap = bootstrap;
      _scopeGeneration += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey(_scopeGeneration),
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        appBootstrapRetryProvider.overrideWithValue(_reloadBootstrap),
        ...widget.overrides,
      ],
      child: const ZcashWalletApp(),
    );
  }
}

Future<void> runZcashWalletApp() async {
  log('runtime: starting');
  await initializeZcashWalletRuntime();
  final app = await buildBootstrappedZcashWalletApp();
  log('runtime: launching app');
  runApp(app);
  if (isDesktopLayoutPlatform && Platform.isWindows) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(showDesktopWindow());
    });
  }
}

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
      final isStorageUnavailable =
          state.matchedLocation == '/storage-unavailable';

      if (bootstrap.hasBlockingFailure) {
        return isStorageUnavailable ? null : '/storage-unavailable';
      }

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
      final isPublicLegal =
          state.matchedLocation == '/terms' ||
          state.matchedLocation == '/privacy';
      final isUnlock = state.matchedLocation == '/unlock';
      final isLostPassword = state.matchedLocation == '/lost-password';
      final isUnlockFlow = isUnlock || isLostPassword;

      log(
        'router redirect: location=${state.matchedLocation}, hasWallet=$hasWallet, '
        'requiresUnlock=$requiresUnlock, isOnboarding=$isOnboarding',
      );

      if (isStorageUnavailable) {
        if (!hasWallet) return '/welcome';
        return requiresUnlock ? '/unlock' : '/home';
      }
      if (!hasWallet && isUnlockFlow) return '/welcome';
      if (!hasWallet && !isOnboarding && !isPublicLegal) return '/welcome';
      if (!hasWallet && state.matchedLocation == '/add-account') {
        return '/welcome';
      }
      // `/lost-password` is intentionally part of the unlock flow: a locked
      // wallet must be able to reach its local reset path from `/unlock`.
      if (requiresUnlock && !isUnlockFlow && !isPublicLegal) return '/unlock';
      if (!requiresUnlock && isUnlockFlow) {
        return hasWallet ? '/home' : '/welcome';
      }
      if (hasWallet && state.matchedLocation == '/welcome') {
        return requiresUnlock ? '/unlock' : '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, _) {
          if (bootstrap.hasBlockingFailure) return '/storage-unavailable';
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
      GoRoute(
        path: '/storage-unavailable',
        builder: (_, _) => const StorageUnavailableScreen(),
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
          child: const WelcomeScreen(showBackButton: true),
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
          child: KeystoneOnboardingShell(
            activeStep: keystoneOnboardingStepFromLocation(
              state.matchedLocation,
            ),
            showPasswordStep: !ref
                .read(appSecurityProvider)
                .isPasswordConfigured,
            child: child,
          ),
          transitionsBuilder: (_, _, _, child) => child,
        ),
        routes: [
          GoRoute(
            path: KeystoneOnboardingStep.howToConnect.routePath,
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const KeystoneHowToConnectScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: KeystoneOnboardingStep.scanQrCode.routePath,
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const KeystoneScanQrScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: KeystoneOnboardingStep.selectAccount.routePath,
            redirect: (_, _) {
              final accounts = ref.read(keystoneOnboardingProvider).accounts;
              return accounts.isEmpty
                  ? KeystoneOnboardingStep.scanQrCode.routePath
                  : null;
            },
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const KeystoneSelectAccountScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: KeystoneOnboardingStep.walletBirthdayHeight.routePath,
            redirect: (_, _) {
              final state = ref.read(keystoneOnboardingProvider);
              if (state.accounts.isEmpty) {
                return KeystoneOnboardingStep.scanQrCode.routePath;
              }
              return state.selectedAccount == null
                  ? KeystoneOnboardingStep.selectAccount.routePath
                  : null;
            },
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: kOnboardingForwardDuration,
              reverseTransitionDuration: kOnboardingReverseDuration,
              child: const KeystoneWalletBirthdayScreen(),
              transitionsBuilder: _onboardingFadeTransition,
            ),
          ),
          GoRoute(
            path: KeystoneOnboardingStep.setPassword.routePath,
            redirect: (_, state) {
              final args = state.extra;
              if (args is SetPasswordScreenArgs &&
                  args.flow == SetPasswordFlow.importKeystone) {
                return null;
              }
              return KeystoneOnboardingStep.walletBirthdayHeight.routePath;
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
      GoRoute(
        path: '/lost-password',
        builder: (_, _) => const LostPasswordScreen(),
      ),
      GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyPolicyScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
      GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, state) {
          final txid = state.pathParameters['txid'];
          if (txid == null || txid.isEmpty) {
            return const ActivityScreen();
          }
          final txKind = state.uri.queryParameters['kind'];
          final extra = state.extra;
          if (extra is ActivityTransactionStatusArgs) {
            final args = extra.txKind == null && txKind != null
                ? ActivityTransactionStatusArgs(
                    txidHex: extra.txidHex,
                    txKind: txKind,
                    initialTransaction: extra.initialTransaction,
                    initialDetail: extra.initialDetail,
                  )
                : extra;
            return ActivityTransactionStatusScreen(args: args);
          }
          return ActivityTransactionStatusScreen(
            args: ActivityTransactionStatusArgs(txidHex: txid, txKind: txKind),
          );
        },
      ),
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
        path: '/send/keystone/scan',
        builder: (_, _) => const KeystoneSendScanScreen(),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) {
          final args = state.extra;
          if (args is KeystoneBroadcastArgs) {
            return SendStatusScreen(args: args.reviewArgs, keystone: args);
          }
          if (args is! SendReviewArgs) return const SendScreen();
          return SendStatusScreen(args: args);
        },
      ),
      GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/import-keystone',
        redirect: (_, _) => KeystoneOnboardingStep.howToConnect.routePath,
      ),
      GoRoute(
        path: '/import-keystone/set-password',
        redirect: (_, _) => KeystoneOnboardingStep.howToConnect.routePath,
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/secret-passphrase',
        builder: (_, _) => const SettingsSeedPhraseScreen(),
      ),
      GoRoute(
        path: '/settings/change-password',
        builder: (_, _) => const SettingsChangePasswordScreen(),
      ),
      GoRoute(
        path: '/settings/endpoint',
        builder: (_, _) => const SettingsEndpointScreen(),
      ),
      GoRoute(
        path: '/voting',
        builder: (_, _) => _guardVotingScreen(const VotingPollsScreen()),
      ),
      GoRoute(
        path: '/voting/poll/:roundId',
        builder: (_, state) => _guardVotingScreen(
          VotingProposalDetailScreen(
            roundId: state.pathParameters['roundId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/review',
        builder: (_, state) => _guardVotingScreen(
          VotingReviewScreen(roundId: state.pathParameters['roundId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/status',
        builder: (_, state) => _guardVotingScreen(
          VotingStatusScreen(roundId: state.pathParameters['roundId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/voting/keystone/scan',
        builder: (_, _) => _guardVotingScreen(const KeystoneVotingScanScreen()),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/submitted',
        builder: (_, state) => _guardVotingScreen(
          VotingSubmissionConfirmationScreen(
            roundId: state.pathParameters['roundId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/voting/poll/:roundId/results',
        builder: (_, state) => _guardVotingScreen(
          VotingResultsScreen(roundId: state.pathParameters['roundId'] ?? ''),
        ),
      ),
    ],
  );
});

Widget _guardVotingScreen(Widget child) {
  return VotingSoftwareAccountGuard(child: child);
}

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
        return AppThemeHost(
          themeMode: themeMode,
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
          child: _LinuxUpdateNoticeListener(
            child: _WindowsUpdateStartupCheck(
              child: _WindowsUpdatePromptHost(
                router: router,
                child: _RpcEndpointFailoverToastListener(
                  child: _LinuxOpaqueWindowBackground(
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
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WindowsUpdateStartupCheck extends ConsumerStatefulWidget {
  const _WindowsUpdateStartupCheck({required this.child});

  final Widget child;

  @override
  ConsumerState<_WindowsUpdateStartupCheck> createState() =>
      _WindowsUpdateStartupCheckState();
}

class _WindowsUpdateStartupCheckState
    extends ConsumerState<_WindowsUpdateStartupCheck> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(windowsUpdateProvider.notifier).checkOnStartup());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WindowsUpdatePromptHost extends ConsumerStatefulWidget {
  const _WindowsUpdatePromptHost({required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<_WindowsUpdatePromptHost> createState() =>
      _WindowsUpdatePromptHostState();
}

class _WindowsUpdatePromptHostState
    extends ConsumerState<_WindowsUpdatePromptHost> {
  final Set<String> _dismissedPromptKeys = {};
  var _routeRebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_handleRouteChanged);
  }

  @override
  void didUpdateWidget(covariant _WindowsUpdatePromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router == widget.router) return;
    oldWidget.router.routerDelegate.removeListener(_handleRouteChanged);
    widget.router.routerDelegate.addListener(_handleRouteChanged);
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_handleRouteChanged);
    super.dispose();
  }

  void _handleRouteChanged() {
    if (!mounted || _routeRebuildScheduled) return;
    _routeRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _routeRebuildScheduled = false;
      setState(() {});
    });
  }

  String get _currentPath {
    return widget.router.routerDelegate.currentConfiguration.uri.path;
  }

  bool _canShowForCurrentRoute() {
    final path = _currentPath;
    if (path == '/unlock' ||
        path == '/welcome' ||
        path == '/add-account' ||
        path == '/lost-password' ||
        path.startsWith('/onboarding/') ||
        path.startsWith('/import') ||
        path.startsWith('/import-keystone') ||
        path.startsWith('/send') ||
        path.startsWith('/settings/secret-passphrase') ||
        path.startsWith('/settings/change-password')) {
      return false;
    }
    return true;
  }

  String _promptKey(WindowsUpdateState state) {
    return '${state.status.name}:${state.availableVersion}';
  }

  bool _shouldShowPrompt(WindowsUpdateState state) {
    if (!_canShowForCurrentRoute()) return false;
    if (!state.supported) return false;
    final visibleStatus = switch (state.status) {
      WindowsUpdateStatus.available ||
      WindowsUpdateStatus.downloading ||
      WindowsUpdateStatus.ready ||
      WindowsUpdateStatus.applying => true,
      _ => false,
    };
    if (!visibleStatus) return false;
    return !_dismissedPromptKeys.contains(_promptKey(state));
  }

  void _dismiss(WindowsUpdateState state) {
    setState(() {
      _dismissedPromptKeys.add(_promptKey(state));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(windowsUpdateProvider);
    final showPrompt = _shouldShowPrompt(state);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: AppSpacing.base,
          right: AppSpacing.base,
          bottom: AppSpacing.base,
          child: IgnorePointer(
            ignoring: !showPrompt,
            child: Align(
              alignment: Alignment.bottomRight,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final position = Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: position, child: child),
                  );
                },
                child: showPrompt
                    ? _WindowsUpdatePrompt(
                        key: ValueKey(_promptKey(state)),
                        state: state,
                        onDownload: () {
                          unawaited(
                            ref
                                .read(windowsUpdateProvider.notifier)
                                .downloadUpdate(),
                          );
                        },
                        onRestart: () {
                          unawaited(
                            ref
                                .read(windowsUpdateProvider.notifier)
                                .applyUpdateAndRestart(),
                          );
                        },
                        onLater: () => _dismiss(state),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('empty-windows-update-prompt'),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WindowsUpdatePrompt extends StatelessWidget {
  const _WindowsUpdatePrompt({
    required this.state,
    required this.onDownload,
    required this.onRestart,
    required this.onLater,
    super.key,
  });

  final WindowsUpdateState state;
  final VoidCallback onDownload;
  final VoidCallback onRestart;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final action = _primaryAction();

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 424),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(
              color: isDark ? colors.border.subtle : colors.border.regular,
            ),
            boxShadow: isDark
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      offset: Offset(0, 4),
                      blurRadius: 12,
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WindowsUpdatePromptIcon(status: state.status),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _message(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (state.status == WindowsUpdateStatus.downloading) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _WindowsUpdatePromptProgress(
                    progress: state.downloadProgress,
                  ),
                ],
                const SizedBox(height: AppSpacing.s),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_canDismiss()) ...[
                      AppButton(
                        onPressed: onLater,
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.small,
                        child: const Text('Later'),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                    ],
                    AppButton(
                      onPressed: action.onPressed,
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.small,
                      child: Text(action.label),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _title() {
    return switch (state.status) {
      WindowsUpdateStatus.available =>
        'Update ${state.availableVersion} available',
      WindowsUpdateStatus.downloading => 'Downloading update',
      WindowsUpdateStatus.ready => 'Update ready',
      WindowsUpdateStatus.applying => 'Restarting Vizor',
      _ => 'Update available',
    };
  }

  String _message() {
    return switch (state.status) {
      WindowsUpdateStatus.available => 'Download now or keep working.',
      WindowsUpdateStatus.downloading =>
        '${state.downloadProgress}% downloaded.',
      WindowsUpdateStatus.ready => 'Restart when you are ready.',
      WindowsUpdateStatus.applying => 'Applying after Vizor closes.',
      _ => '',
    };
  }

  bool _canDismiss() {
    return state.status == WindowsUpdateStatus.available ||
        state.status == WindowsUpdateStatus.ready;
  }

  _WindowsUpdatePromptAction _primaryAction() {
    return switch (state.status) {
      WindowsUpdateStatus.available => _WindowsUpdatePromptAction(
        label: 'Download',
        onPressed: onDownload,
      ),
      WindowsUpdateStatus.ready => _WindowsUpdatePromptAction(
        label: 'Restart',
        onPressed: onRestart,
      ),
      WindowsUpdateStatus.downloading => const _WindowsUpdatePromptAction(
        label: 'Downloading',
      ),
      WindowsUpdateStatus.applying => const _WindowsUpdatePromptAction(
        label: 'Restarting',
      ),
      _ => const _WindowsUpdatePromptAction(label: 'Update'),
    };
  }
}

class _WindowsUpdatePromptAction {
  const _WindowsUpdatePromptAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;
}

class _WindowsUpdatePromptIcon extends StatelessWidget {
  const _WindowsUpdatePromptIcon({required this.status});

  final WindowsUpdateStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: AppIcon(
        status == WindowsUpdateStatus.ready ? AppIcons.check : AppIcons.sync,
        size: 16,
        color: colors.icon.accent,
      ),
    );
  }
}

class _WindowsUpdatePromptProgress extends StatelessWidget {
  const _WindowsUpdatePromptProgress({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 4,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress.clamp(0, 100) / 100,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.inverse),
        ),
      ),
    );
  }
}

class _LinuxUpdateNoticeListener extends ConsumerWidget {
  const _LinuxUpdateNoticeListener({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<LinuxUpdateInfo?>>(linuxUpdateProvider, (
      previous,
      next,
    ) {
      final update = next.asData?.value;
      if (update == null) return;

      final previousUpdate = previous?.asData?.value;
      if (previousUpdate?.buildNumber == update.buildNumber) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;

        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Vizor ${update.assetVersion} is available.'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'View Release',
              onPressed: () => unawaited(_openLinuxUpdateRelease(update)),
            ),
          ),
        );
      });
    });

    return child;
  }
}

Future<void> _openLinuxUpdateRelease(LinuxUpdateInfo update) async {
  final uri = Uri.tryParse(update.releaseUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _LinuxOpaqueWindowBackground extends StatelessWidget {
  const _LinuxOpaqueWindowBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
      return child;
    }
    return ColoredBox(color: context.colors.background.ground, child: child);
  }
}

class _RpcEndpointFailoverToastListener extends StatelessWidget {
  const _RpcEndpointFailoverToastListener({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NetworkFallbackToastHost(
      child: _RpcEndpointFailoverToastBridge(child: child),
    );
  }
}

class _RpcEndpointFailoverToastBridge extends ConsumerWidget {
  const _RpcEndpointFailoverToastBridge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<RpcEndpointFailoverEvent?>(
      rpcEndpointFailoverProvider.select((state) => state.lastEvent),
      (previous, next) {
        if (next == null || next.sequence == previous?.sequence) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          showNetworkFallbackToast(
            context,
            next.message,
            duration: const Duration(seconds: 4),
          );
        });
      },
    );
    return child;
  }
}
