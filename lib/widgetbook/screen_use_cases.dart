// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/layout/mobile/app_mobile_shell.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/core/privacy/sensitive_privacy_overlay.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/accounts/screens/accounts_screen.dart';
import '../src/features/about/screens/about_screen.dart';
import '../src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import '../src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../src/features/activity/swap_activity_row_items_provider.dart';
import '../src/features/home/screens/mobile/mobile_home_screen.dart';
import '../src/features/onboarding/lost_password_screen.dart';
import '../src/features/onboarding/mobile/forgot_passcode_sheet.dart';
import '../src/features/onboarding/mobile/mobile_biometrics_screen.dart';
import '../src/features/onboarding/mobile/mobile_passcode_screen.dart';
import '../src/features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import '../src/features/onboarding/mobile/mobile_unlock_screen.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/settings/screens/settings_change_password_screen.dart';
import '../src/features/settings/screens/settings_endpoint_screen.dart';
import '../src/features/settings/screens/settings_screen.dart';
import '../src/features/settings/screens/settings_seed_phrase_screen.dart';
import '../src/features/settings/screens/settings_uninstall_screen.dart';
import '../src/features/onboarding/unlock_screen.dart';
import '../src/features/onboarding/welcome.dart';
import '../src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/biometric_unlock_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/receive_address_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import '../src/services/biometric_unlock.dart';

const _previewMnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse '
    'access accident account accuse achieve acid acoustic acquire across act '
    'action actor actress actual';

/// Welcome screen in its large-layout form. Wrapped in a `ProviderScope`
/// with `appLayoutProvider` overridden to a no-op so the dev window does
/// not get reshaped by the screen's on-mount `setMode(large)` call, and
/// in a minimal `GoRouter` so the in-screen `context.go(...)` calls
/// resolve instead of throwing if a reviewer taps a button during the
/// preview.
Widget buildWelcomeLargeUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new)],
    child: _WelcomeHarness(),
  );
}

Widget buildUnlockLoginUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new)],
    child: _UnlockHarness(),
  );
}

Widget buildLostPasswordCountdownUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new)],
    child: IgnorePointer(
      child: LostPasswordScreen(
        initialCountdownSeconds: 3,
        countdownEnabled: false,
        onBack: () {},
        onReset: () async {},
      ),
    ),
  );
}

Widget buildLostPasswordEnabledUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [appLayoutProvider.overrideWith(_NoOpLayoutNotifier.new)],
    child: IgnorePointer(
      child: LostPasswordScreen(
        initialCountdownSeconds: 0,
        countdownEnabled: false,
        onBack: () {},
        onReset: () async {},
      ),
    ),
  );
}

Widget buildMobileUnlockPasscodeUseCase(BuildContext context) {
  return _buildMobileUnlockUseCase(BiometricUnlockState.initial);
}

Widget buildMobileUnlockFaceIdUseCase(BuildContext context) {
  return _buildMobileUnlockUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.face,
      ),
      enabled: true,
    ),
  );
}

Widget buildMobileUnlockBiometricBackdropUseCase(BuildContext context) {
  return const _MobilePreviewFrame(child: MobileBiometricSignInView());
}

Widget buildMobileUnlockFingerprintUseCase(BuildContext context) {
  return _buildMobileUnlockUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.fingerprint,
      ),
      enabled: true,
    ),
  );
}

Widget buildMobileCreatePasscodeUseCase(BuildContext context) {
  return _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobilePasscodeScreen(
        args: SetPasswordScreenArgs.create(mnemonic: _previewMnemonic),
      ),
    ),
  );
}

Widget buildMobileSecretPassphraseRevealedUseCase(BuildContext context) {
  return const _MobilePreviewFrame(
    child: IgnorePointer(
      child: MobileSecretPassphraseScreen(
        args: CreateSecretPassphraseArgs(mnemonic: _previewMnemonic),
        screenshotStream: Stream.empty(),
      ),
    ),
  );
}

Widget buildMobileSecretPassphraseProtectedUseCase(BuildContext context) {
  return const _MobileSecretPassphraseProtectedPreview();
}

Widget buildMobileSecretPassphraseScreenshotWarningUseCase(
  BuildContext context,
) {
  return _MobilePreviewFrame(
    child: Stack(
      children: [
        const IgnorePointer(
          child: MobileSecretPassphraseScreen(
            args: CreateSecretPassphraseArgs(mnemonic: _previewMnemonic),
            screenshotStream: Stream.empty(),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: AppTheme.of(context).colors.background.neutralScrim,
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            child: MobileModalCard(child: MobileSeedScreenshotWarningSheet()),
          ),
        ),
      ],
    ),
  );
}

Widget buildMobileFaceIdOptInUseCase(BuildContext context) {
  return _buildMobileBiometricOptInUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.face,
      ),
      enabled: false,
    ),
  );
}

Widget buildMobileFingerprintOptInUseCase(BuildContext context) {
  return _buildMobileBiometricOptInUseCase(
    const BiometricUnlockState(
      availability: BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.fingerprint,
      ),
      enabled: false,
    ),
  );
}

Widget buildMobileForgotPasscodeSheetUseCase(BuildContext context) {
  return _buildMobileUnlockModalUseCase(context, const ForgotPasscodeSheet());
}

Widget buildMobileForgotPasscodeLastWarningUseCase(BuildContext context) {
  return _buildMobileUnlockModalUseCase(
    context,
    const ForgotPasscodeLastWarningSheet(),
  );
}

Widget buildMobileSeedScreenshotWarningSheetUseCase(BuildContext context) {
  return _buildMobileModalSnapshotUseCase(
    context,
    const MobileSeedScreenshotWarningSheet(),
  );
}

Widget buildAccountsManyUseCase(BuildContext context) {
  return _buildAccountsUseCase(_accountsManyState);
}

Widget buildAccountsOtherMenuUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialOpenMenuAccountUuid: 'preview-account-2',
  );
}

Widget buildAccountsCurrentMenuUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialOpenMenuAccountUuid: 'preview-account-1',
  );
}

Widget buildAccountsEditAccountUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialModalAccountUuid: 'preview-account-2',
    initialModal: AccountsScreenInitialModal.editAccount,
  );
}

Widget buildAccountsProfilePictureUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialModalAccountUuid: 'preview-account-2',
    initialModal: AccountsScreenInitialModal.profilePicture,
  );
}

Widget buildAccountsRemoveUseCase(BuildContext context) {
  return _buildAccountsUseCase(
    _accountsDesignState,
    initialModalAccountUuid: 'preview-account-2',
    initialModal: AccountsScreenInitialModal.removeAccount,
  );
}

Widget buildSettingsMainUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsBootstrap(_accountsDesignState, initialLocation: '/settings'),
      ),
      accountProvider.overrideWith(
        () => _PreviewAccountNotifier(_accountsDesignState),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(_accountsDesignState.activeAccountUuid),
      ),
    ],
    child: _SettingsHarness(),
  );
}

Widget buildSettingsEndpointUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/endpoint',
    const SettingsEndpointScreen(),
  );
}

Widget buildSettingsSecretPassphraseGateUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/secret-passphrase',
    const SettingsSeedPhraseScreen(),
  );
}

Widget buildSettingsChangePasswordGateUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/change-password',
    const SettingsChangePasswordScreen(),
  );
}

Widget buildSettingsUninstallConfirmUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/uninstall',
    const SettingsUninstallScreen(),
  );
}

/// Done stage demo: plays the badge motion (1000ms hold, then the helmet
/// fades out over 500ms) on entry. Re-select the use case to replay.
Widget buildSettingsUninstallDoneUseCase(BuildContext context) {
  return _buildSettingsSubScreenUseCase(
    '/settings/uninstall',
    const SettingsUninstallScreen(initialStage: SettingsUninstallStage.done),
  );
}

Widget _buildSettingsSubScreenUseCase(String path, Widget screen) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _accountsBootstrap(_accountsDesignState, initialLocation: path),
      ),
      accountProvider.overrideWith(
        () => _PreviewAccountNotifier(_accountsDesignState),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(_accountsDesignState.activeAccountUuid),
      ),
    ],
    child: _SettingsSubScreenHarness(path: path, screen: screen),
  );
}

Widget buildAboutUtilityUseCase(BuildContext context) {
  return _buildUtilityUseCase('/about', _accountsDesignState);
}

Widget buildTermsUtilityUseCase(BuildContext context) {
  return _buildUtilityUseCase('/terms', const AccountState());
}

Widget buildPrivacyUtilityUseCase(BuildContext context) {
  return _buildUtilityUseCase('/privacy', const AccountState());
}

Widget buildMobileAccountsUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(_accountsDesignState);
}

Widget buildMobileAccountsEditAccountUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(
    _accountsDesignState,
    initialSheetAccountUuid: 'preview-account-2',
    initialSheet: MobileAccountsInitialSheet.editAccount,
  );
}

Widget buildMobileAccountsRemoveAccountUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(
    _accountsDesignState,
    initialSheetAccountUuid: 'preview-account-2',
    initialSheet: MobileAccountsInitialSheet.removeAccount,
  );
}

Widget buildMobileAccountsManyUseCase(BuildContext context) {
  return _buildMobileAccountsUseCase(_accountsManyState);
}

Widget buildMobileHomeDefaultUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(
      orchardBalance: BigInt.from(14312000000),
      recentTransactions: [_homeTx(1), _homeTx(2)],
    ),
  );
}

Widget buildMobileHomeNoActivityUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(orchardBalance: BigInt.from(14312000000)),
  );
}

Widget buildMobileHomeNoBalanceUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(),
  );
}

Widget buildMobileHomeNoBalanceKeystoneUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _homeKeystoneState,
    syncState: _homeSyncedState(accountUuid: _homeKeystoneAccountUuid),
  );
}

Widget buildMobileHomeImportingUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: SyncState(
      accountUuid: _accountsDesignState.activeAccountUuid,
      isSyncing: true,
      percentage: 0.34,
      displayPercentage: 0.34,
    ),
  );
}

Widget buildMobileHomeAccountsModalUseCase(BuildContext context) {
  return _buildMobileHomeUseCase(
    accountState: _accountsDesignState,
    syncState: _homeSyncedState(orchardBalance: BigInt.from(14312000000)),
    openAccountsSheet: true,
  );
}

Widget _buildAccountsUseCase(
  AccountState accountState, {
  String? initialOpenMenuAccountUuid,
  String? initialModalAccountUuid,
  AccountsScreenInitialModal? initialModal,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_accountsBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(accountState.activeAccountUuid),
      ),
    ],
    child: _AccountsHarness(
      initialOpenMenuAccountUuid: initialOpenMenuAccountUuid,
      initialModalAccountUuid: initialModalAccountUuid,
      initialModal: initialModal,
    ),
  );
}

Widget _buildUtilityUseCase(String initialLocation, AccountState accountState) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _utilityBootstrap(initialLocation, accountState),
      ),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(accountState.activeAccountUuid),
      ),
    ],
    child: _UtilityHarness(initialLocation: initialLocation),
  );
}

Widget _buildMobileHomeUseCase({
  required AccountState accountState,
  required SyncState syncState,
  bool openAccountsSheet = false,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_homeBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      receiveAddressServiceProvider.overrideWithValue(
        const _PreviewReceiveAddressService(),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(
          accountState.activeAccountUuid,
          initialState: syncState,
        ),
      ),
      privacyModeProvider.overrideWith(_PreviewPrivacyModeNotifier.new),
      zecMarketDataSourceProvider.overrideWithValue(
        const _PreviewZecMarketDataSource(
          ZecMarketData(usdPrice: 70, change24hPct: 13.12),
        ),
      ),
      swapActivityRowItemsProvider.overrideWith((ref, accountUuid) async {
        return const [];
      }),
    ],
    child: Center(
      child: SizedBox(
        width: 393,
        height: 852,
        child: _MobileHomeHarness(openAccountsSheet: openAccountsSheet),
      ),
    ),
  );
}

Widget _buildMobileAccountsUseCase(
  AccountState accountState, {
  String? initialSheetAccountUuid,
  MobileAccountsInitialSheet? initialSheet,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_accountsBootstrap(accountState)),
      accountProvider.overrideWith(() => _PreviewAccountNotifier(accountState)),
      receiveAddressServiceProvider.overrideWithValue(
        const _PreviewReceiveAddressService(),
      ),
      syncProvider.overrideWith(
        () => _PreviewSyncNotifier(accountState.activeAccountUuid),
      ),
    ],
    child: Center(
      child: SizedBox(
        width: 393,
        height: 852,
        child: _MobileAccountsHarness(
          initialSheetAccountUuid: initialSheetAccountUuid,
          initialSheet: initialSheet,
        ),
      ),
    ),
  );
}

class _NoOpLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    // Intentional no-op: `AppLayoutNotifier.setMode` would reshape the
    // native window via `window_manager`, which is disruptive in a
    // Widgetbook preview where the window belongs to the dev tool.
  }
}

class _AccountsHarness extends StatefulWidget {
  const _AccountsHarness({
    this.initialOpenMenuAccountUuid,
    this.initialModalAccountUuid,
    this.initialModal,
  });

  final String? initialOpenMenuAccountUuid;
  final String? initialModalAccountUuid;
  final AccountsScreenInitialModal? initialModal;

  @override
  State<_AccountsHarness> createState() => _AccountsHarnessState();
}

class _AccountsHarnessState extends State<_AccountsHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        GoRoute(
          path: '/accounts',
          builder: (_, _) => AccountsScreen(
            initialOpenMenuAccountUuid: widget.initialOpenMenuAccountUuid,
            initialModalAccountUuid: widget.initialModalAccountUuid,
            initialModal: widget.initialModal,
          ),
        ),
        GoRoute(
          path: '/add-account',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/add-account'),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/home'),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/receive'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
        GoRoute(
          path: '/about',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/about'),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/welcome'),
        ),
        GoRoute(
          path: '/unlock',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/unlock'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _SettingsSubScreenHarness extends StatefulWidget {
  const _SettingsSubScreenHarness({required this.path, required this.screen});

  final String path;
  final Widget screen;

  @override
  State<_SettingsSubScreenHarness> createState() =>
      _SettingsSubScreenHarnessState();
}

class _SettingsSubScreenHarnessState extends State<_SettingsSubScreenHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.path,
      routes: [
        GoRoute(path: widget.path, builder: (_, _) => widget.screen),
        for (final path in [
          '/settings',
          '/home',
          '/welcome',
          '/unlock',
          '/swap',
          '/activity',
          '/accounts',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _PreviewRoutePlaceholder(label: path),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _SettingsHarness extends StatefulWidget {
  @override
  State<_SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<_SettingsHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        for (final path in const [
          '/settings/secret-passphrase',
          '/settings/change-password',
          '/settings/endpoint',
          '/settings/uninstall',
          '/address-book',
          '/about',
          '/privacy',
          '/terms',
          '/home',
          '/send',
          '/receive',
          '/activity',
          '/accounts',
          '/welcome',
          '/unlock',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => _PreviewRoutePlaceholder(label: path),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _UtilityHarness extends StatefulWidget {
  const _UtilityHarness({required this.initialLocation});

  final String initialLocation;

  @override
  State<_UtilityHarness> createState() => _UtilityHarnessState();
}

class _UtilityHarnessState extends State<_UtilityHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      routes: [
        GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
        GoRoute(path: '/terms', builder: (_, _) => const TermsScreen()),
        GoRoute(
          path: '/privacy',
          builder: (_, _) => const PrivacyPolicyScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/home'),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/receive'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/welcome'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _MobileAccountsHarness extends StatefulWidget {
  const _MobileAccountsHarness({
    this.initialSheetAccountUuid,
    this.initialSheet,
  });

  final String? initialSheetAccountUuid;
  final MobileAccountsInitialSheet? initialSheet;

  @override
  State<_MobileAccountsHarness> createState() => _MobileAccountsHarnessState();
}

class _MobileAccountsHarnessState extends State<_MobileAccountsHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        GoRoute(
          path: '/accounts',
          builder: (_, _) => MobileAccountsScreen(
            initialSheetAccountUuid: widget.initialSheetAccountUuid,
            initialSheet: widget.initialSheet,
          ),
        ),
        GoRoute(
          path: '/add-account',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/add-account'),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _MobileHomeHarness extends StatefulWidget {
  const _MobileHomeHarness({required this.openAccountsSheet});

  final bool openAccountsSheet;

  @override
  State<_MobileHomeHarness> createState() => _MobileHomeHarnessState();
}

class _MobileHomeHarnessState extends State<_MobileHomeHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => AppMobileShell(
            body: _MobileHomeBody(openAccountsSheet: widget.openAccountsSheet),
            tabBar: AppMobileTabBar(
              items: _mobileHomeTabItems,
              currentIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/send'),
        ),
        GoRoute(
          path: '/receive',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/receive'),
        ),
        GoRoute(
          path: '/swap',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/swap'),
        ),
        GoRoute(
          path: '/activity',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/activity'),
        ),
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, state) => _PreviewRoutePlaceholder(
            label: '/activity/tx/${state.pathParameters['txid']}',
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/settings'),
        ),
        GoRoute(
          path: '/accounts',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/accounts'),
        ),
        GoRoute(
          path: '/add-account',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/add-account'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _MobileHomeBody extends StatefulWidget {
  const _MobileHomeBody({required this.openAccountsSheet});

  final bool openAccountsSheet;

  @override
  State<_MobileHomeBody> createState() => _MobileHomeBodyState();
}

class _MobileHomeBodyState extends State<_MobileHomeBody> {
  var _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened || !widget.openAccountsSheet) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showMobileAccountsSheet(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const MobileHomeScreen();
  }
}

class _WelcomeHarness extends StatefulWidget {
  @override
  State<_WelcomeHarness> createState() => _WelcomeHarnessState();
}

class _WelcomeHarnessState extends State<_WelcomeHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        // Stub destinations so buttons in the preview don't throw when
        // tapped. They render nothing meaningful — the point is just to
        // satisfy the router.
        GoRoute(
          path: '/onboarding/intro',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/onboarding/intro'),
        ),
        GoRoute(
          path: '/import',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/import'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

class _UnlockHarness extends StatefulWidget {
  @override
  State<_UnlockHarness> createState() => _UnlockHarnessState();
}

class _UnlockHarnessState extends State<_UnlockHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/unlock',
      routes: [
        GoRoute(
          path: '/unlock',
          // Preview-only: keep navigation inert inside Widgetbook.
          builder: (_, _) => const IgnorePointer(child: UnlockScreen()),
        ),
        GoRoute(
          path: '/home',
          builder: (_, _) => const _PreviewRoutePlaceholder(label: '/home'),
        ),
        GoRoute(
          path: '/lost-password',
          builder: (_, _) =>
              const _PreviewRoutePlaceholder(label: '/lost-password'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mirror the app-level `_DesktopOpaqueWindowBackground` underlay so
    // transparent shells (backdrop screens) don't show Widgetbook chrome.
    return ColoredBox(
      color: context.colors.macosUtility.window,
      child: Router.withConfig(config: _router),
    );
  }
}

Widget _buildMobileUnlockUseCase(BiometricUnlockState biometricState) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewBiometricUnlockNotifier(biometricState),
      ),
    ],
    child: _MobilePreviewFrame(
      child: IgnorePointer(
        child: MobileUnlockScreen(autoPromptBiometric: false),
      ),
    ),
  );
}

Widget _buildMobileBiometricOptInUseCase(BiometricUnlockState biometricState) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewBiometricUnlockNotifier(biometricState),
      ),
    ],
    child: const _MobilePreviewFrame(
      child: IgnorePointer(child: MobileBiometricsScreen()),
    ),
  );
}

Widget _buildMobileUnlockModalUseCase(BuildContext context, Widget sheet) {
  return ProviderScope(
    overrides: [
      biometricUnlockProvider.overrideWith(
        () => _PreviewBiometricUnlockNotifier(
          const BiometricUnlockState(
            availability: BiometricAvailability(
              supported: true,
              enrolled: true,
              kind: BiometricKind.face,
            ),
            enabled: true,
          ),
        ),
      ),
    ],
    child: _MobilePreviewFrame(
      child: Stack(
        children: [
          const IgnorePointer(
            child: MobileUnlockScreen(autoPromptBiometric: false),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: AppTheme.of(context).colors.background.neutralScrim,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                ),
                child: MobileModalCard(child: sheet),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildMobileModalSnapshotUseCase(BuildContext context, Widget sheet) {
  return Center(
    child: SizedBox.fromSize(
      size: const Size(393, 435),
      child: ClipRect(
        child: ColoredBox(
          color: AppTheme.of(context).colors.background.neutralScrim,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: const Size(393, 435),
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
              ),
              child: MobileModalCard(child: sheet),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MobileSecretPassphraseProtectedPreview extends StatefulWidget {
  const _MobileSecretPassphraseProtectedPreview();

  @override
  State<_MobileSecretPassphraseProtectedPreview> createState() =>
      _MobileSecretPassphraseProtectedPreviewState();
}

class _MobileSecretPassphraseProtectedPreviewState
    extends State<_MobileSecretPassphraseProtectedPreview> {
  late final SensitivePrivacyOverlayController _privacyController =
      SensitivePrivacyOverlayController(initiallySafe: false);

  @override
  void dispose() {
    _privacyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MobilePreviewFrame(
      child: IgnorePointer(
        child: MobileSecretPassphraseScreen(
          args: const CreateSecretPassphraseArgs(mnemonic: _previewMnemonic),
          screenshotStream: const Stream.empty(),
          privacyOverlayController: _privacyController,
        ),
      ),
    );
  }
}

class _MobilePreviewFrame extends StatelessWidget {
  const _MobilePreviewFrame({required this.child});

  final Widget child;

  static const size = Size(393, 852);
  static const safeAreaPadding = EdgeInsets.only(top: 55, bottom: 24);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Center(
      child: SizedBox.fromSize(
        size: size,
        child: ClipRect(
          child: MediaQuery(
            data: mediaQuery.copyWith(
              size: size,
              padding: safeAreaPadding,
              viewPadding: safeAreaPadding,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PreviewBiometricUnlockNotifier extends BiometricUnlockNotifier {
  _PreviewBiometricUnlockNotifier(this.initialState);

  final BiometricUnlockState initialState;

  @override
  Future<BiometricUnlockState> build() async => initialState;

  @override
  Future<String?> readPasscode({required String reason}) async => null;
}

class _PreviewRoutePlaceholder extends StatelessWidget {
  const _PreviewRoutePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Navigated to $label'));
  }
}

final _accountsDesignState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: 'preview-account-1',
      name: 'Account Name',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'preview-account-2',
      name: 'Account Name',
      order: 1,
      isHardware: true,
      profilePictureId: 'pfp-01',
    ),
    AccountInfo(
      uuid: 'preview-account-3',
      name: 'Account Name',
      order: 2,
      profilePictureId: 'pfp-02',
    ),
    AccountInfo(
      uuid: 'preview-account-4',
      name: 'Account Name',
      order: 3,
      profilePictureId: 'pfp-01',
    ),
  ],
  activeAccountUuid: 'preview-account-1',
  activeAddress: 'u1widgetbookaccountsaddress',
);

final _accountsManyState = AccountState(
  accounts: [
    const AccountInfo(
      uuid: 'preview-account-1',
      name: 'Primary Vault',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
    for (var index = 2; index <= 20; index += 1)
      AccountInfo(
        uuid: 'preview-account-$index',
        name: index == 2 ? 'Keystone Vault' : 'Account $index',
        order: index - 1,
        isHardware: index == 2,
        profilePictureId: index.isEven ? 'pfp-02' : 'pfp-01',
      ),
  ],
  activeAccountUuid: 'preview-account-1',
  activeAddress: 'u1widgetbookaccountsaddress',
);

const _homeKeystoneAccountUuid = 'preview-keystone-account';

final _homeKeystoneState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: _homeKeystoneAccountUuid,
      name: 'Keystone Vault',
      order: 0,
      isHardware: true,
      profilePictureId: 'pfp-02',
    ),
  ],
  activeAccountUuid: _homeKeystoneAccountUuid,
  activeAddress: 'u1widgetbookkeystoneaddress',
);

const _mobileHomeTabItems = [
  AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
  AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
  AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
  AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
];

AppBootstrapState _accountsBootstrap(
  AccountState accountState, {
  String initialLocation = '/accounts',
}) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: accountState,
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

AppBootstrapState _utilityBootstrap(
  String initialLocation,
  AccountState accountState,
) {
  final hasWallet = accountState.accounts.isNotEmpty;
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: accountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: hasWallet,
    isUnlocked: hasWallet,
    passwordRotationRecoveryFailed: false,
  );
}

AppBootstrapState _homeBootstrap(AccountState accountState) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: accountState,
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

SyncState _homeSyncedState({
  String? accountUuid,
  BigInt? orchardBalance,
  List<rust_sync.TransactionInfo> recentTransactions = const [],
}) {
  return SyncState(
    accountUuid: accountUuid ?? _accountsDesignState.activeAccountUuid,
    hasAccountScopedData: true,
    percentage: 1,
    displayPercentage: 1,
    orchardBalance: orchardBalance ?? BigInt.zero,
    recentTransactions: recentTransactions,
  );
}

rust_sync.TransactionInfo _homeTx(int index) {
  final seconds = BigInt.from(1800000000 + index);
  return rust_sync.TransactionInfo(
    txidHex: 'preview-home-tx-$index',
    minedHeight: BigInt.from(1000 + index),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: seconds,
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.from(index) * BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: seconds,
  );
}

class _PreviewAccountNotifier extends AccountNotifier {
  _PreviewAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }

  @override
  Future<void> renameAccount(String uuid, String newName) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      prev.copyWith(
        accounts: [
          for (final account in prev.accounts)
            if (account.uuid == uuid)
              account.copyWith(name: newName)
            else
              account,
        ],
      ),
    );
  }

  @override
  Future<void> updateProfilePicture(
    String uuid,
    String profilePictureId,
  ) async {
    final prev = state.value ?? initialState;
    state = AsyncData(
      prev.copyWith(
        accounts: [
          for (final account in prev.accounts)
            if (account.uuid == uuid)
              account.copyWith(profilePictureId: profilePictureId)
            else
              account,
        ],
      ),
    );
  }

  @override
  Future<void> removeAccount(String uuid) async {
    final prev = state.value ?? initialState;
    final updated = [
      for (final account in prev.accounts)
        if (account.uuid != uuid) account,
    ];
    state = AsyncData(prev.copyWith(accounts: updated));
  }

  @override
  Future<void> resetWallet() async {
    state = const AsyncData(AccountState());
  }
}

class _PreviewSyncNotifier extends SyncNotifier {
  _PreviewSyncNotifier(this.activeAccountUuid, {this.initialState});

  final String? activeAccountUuid;
  final SyncState? initialState;

  @override
  Future<SyncState> build() async =>
      initialState ??
      SyncState(
        accountUuid: activeAccountUuid,
        hasAccountScopedData: activeAccountUuid != null,
        isSyncing: true,
        percentage: 0.34,
        displayPercentage: 0.34,
        totalBalance: BigInt.from(14223000000),
      );

  @override
  Future<void> refreshAfterSend() async {}

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    return const WalletMutationSyncPause(
      hadActiveSync: false,
      hadPolling: false,
      hadBackgroundSync: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {}

  @override
  Future<void> clearSensitiveStateForLock() async {}
}

class _PreviewPrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _PreviewZecMarketDataSource implements ZecMarketDataSource {
  const _PreviewZecMarketDataSource(this.data);

  final ZecMarketData? data;

  @override
  Future<ZecMarketData?> fetchMarketData() async => data;
}

class _PreviewReceiveAddressService implements ReceiveAddressService {
  const _PreviewReceiveAddressService();

  @override
  String? getCachedTransparentAddress(String accountUuid) =>
      't1WidgetbookTransparentAddress';

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    return currentShieldedAddress?.isNotEmpty == true
        ? currentShieldedAddress!
        : 'u1widgetbookaccountsaddress';
  }

  @override
  Future<String> loadTransparentReceiveAddress({
    required String accountUuid,
  }) async {
    return 't1WidgetbookTransparentAddress';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return 'u1widgetbookaccountsrenewedaddress';
  }
}
