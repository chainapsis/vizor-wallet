import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:go_router/go_router.dart';

import '../../features/onboarding/mobile/mobile_biometrics_screen.dart';
import '../../features/onboarding/mobile/mobile_customise_account_screen.dart';
import '../../features/onboarding/mobile/mobile_create_steps.dart';
import '../../features/onboarding/mobile/mobile_import_birthday_screen.dart';
import '../../features/onboarding/mobile/mobile_import_manual_screen.dart';
import '../../features/onboarding/mobile/mobile_import_review_screen.dart';
import '../../features/onboarding/mobile/mobile_import_screens.dart';
import '../../features/onboarding/mobile/mobile_keystone_screens.dart';
import '../../features/onboarding/mobile/mobile_method_selection_screen.dart';
import '../../features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import '../../features/onboarding/mobile/mobile_passcode_screen.dart';
import '../../features/onboarding/mobile/mobile_welcome_screen.dart';
import '../../features/onboarding/mobile/mobile_wallet_link_screens.dart';
import '../../features/onboarding/shared/onboarding_flow_args.dart';

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
    path: '/onboarding/method',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileMethodSelectionScreen(),
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
  GoRoute(
    path: '/onboarding/customise-account',
    redirect: (_, state) =>
        state.extra is CustomiseAccountArgs ? null : '/welcome',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: MobileCustomiseAccountScreen(
        args: state.extra as CustomiseAccountArgs,
      ),
    ),
  ),
  GoRoute(
    path: '/onboarding/biometrics',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileBiometricsScreen(),
    ),
  ),
  GoRoute(
    path: '/import',
    pageBuilder: (context, state) =>
        CupertinoPage(key: state.pageKey, child: const MobileImportScreen()),
  ),
  GoRoute(
    path: '/import/manual',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileImportManualScreen(),
    ),
  ),
  GoRoute(
    path: '/import/review',
    redirect: (_, state) =>
        state.extra is ImportSecretPassphraseArgs ? null : '/import',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: MobileImportReviewScreen(
        args: state.extra as ImportSecretPassphraseArgs,
      ),
    ),
  ),
  GoRoute(
    path: '/import/birthday',
    redirect: (_, state) =>
        state.extra is ImportBirthdayArgs ? null : '/import',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: MobileImportBirthdayScreen(
        args: state.extra as ImportBirthdayArgs,
      ),
    ),
  ),
  GoRoute(
    path: '/onboarding/link-desktop',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileWalletLinkIntroScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/link-desktop/scan',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileWalletLinkScanScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/link-desktop/accounts',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileWalletLinkSelectAccountsScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/link-desktop/contacts',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileWalletLinkSelectContactsScreen(),
    ),
  ),
  // Keystone onboarding — same route paths as the desktop flow so the
  // shared redirect guard and deep links treat them identically.
  GoRoute(
    path: '/onboarding/keystone',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileKeystoneIntroScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/keystone/scan',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileKeystoneScanScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/keystone/select-account',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileKeystoneSelectAccountScreen(),
    ),
  ),
  GoRoute(
    path: '/onboarding/keystone/birthday',
    pageBuilder: (context, state) => CupertinoPage(
      key: state.pageKey,
      child: const MobileKeystoneBirthdayScreen(),
    ),
  ),
  // Legacy keystone aliases land on the mobile flow entry.
  GoRoute(path: '/import-keystone', redirect: (_, _) => '/onboarding/keystone'),
  GoRoute(
    path: '/import-keystone/set-password',
    redirect: (_, _) => '/onboarding/keystone',
  ),
];
