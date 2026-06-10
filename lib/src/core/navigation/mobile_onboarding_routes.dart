import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/mobile/mobile_create_steps.dart';
import '../../features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import '../../features/onboarding/mobile/mobile_onboarding_scaffold.dart';
import '../../features/onboarding/mobile/mobile_passcode_screen.dart';
import '../../features/onboarding/mobile/mobile_welcome_screen.dart';
import '../../features/onboarding/shared/onboarding_flow_args.dart';
import '../theme/app_theme.dart';

/// Mobile onboarding tree: single-pane screens pushed as
/// [CupertinoPage]s (edge-swipe back) under the same route paths as the
/// desktop onboarding, so the shared auth guard and
/// `bootstrap.initialLocation` keep working unchanged.
///
/// Mobile-only additions: `/onboarding/set-passcode` (the passcode is
/// the wallet password on mobile) and `/onboarding/biometrics`.
List<RouteBase> mobileOnboardingRoutes() => [
  GoRoute(
    path: '/welcome',
    pageBuilder: (context, state) =>
        CupertinoPage(key: state.pageKey, child: const MobileWelcomeScreen()),
  ),
  GoRoute(
    path: '/add-account',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileWelcomeScreen(showBackButton: true),
    ),
  ),
  GoRoute(
    path: '/onboarding/intro',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileOnboardingIntroScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/address-types',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileAddressTypesScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/things-to-know',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileThingsToKnowScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/secret-passphrase',
    pageBuilder: (context, state) {
      final args = state.extra is CreateSecretPassphraseArgs
          ? state.extra as CreateSecretPassphraseArgs
          : null;
      return CupertinoPage(
        key: state.pageKey,
        child: MobileSecretPassphraseScreen(args: args),
      );
    },
  ),
  GoRoute(
    path: '/onboarding/set-passcode',
    redirect: (_, state) =>
        state.extra is SetPasswordScreenArgs ? null : '/welcome',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: MobilePasscodeScreen(args: state.extra as SetPasswordScreenArgs),
    ),
  ),
  _step('/onboarding/biometrics'),
  _step('/import'),
  _step('/import/manual'),
  _step('/import/clipboard'),
  _step('/import/review'),
  _step('/import/birthday'),
  // Keystone onboarding has no mobile flow yet; the welcome button
  // shows the unsupported sheet and stray deep links land on welcome.
  GoRoute(path: '/import-keystone', redirect: (_, _) => '/welcome'),
  GoRoute(
    path: '/import-keystone/set-password',
    redirect: (_, _) => '/welcome',
  ),
];

/// Placeholder route for steps that land in follow-up commits.
GoRoute _step(String path) => GoRoute(
  path: path,
  pageBuilder: (context, state) =>
      CupertinoPage(key: state.pageKey, child: const _PendingStepScreen()),
);

class _PendingStepScreen extends StatelessWidget {
  const _PendingStepScreen();

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: 0.1,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Coming soon',
      child: Center(
        child: Text(
          'This step is being built.',
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}
