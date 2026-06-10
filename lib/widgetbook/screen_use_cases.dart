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
import '../src/core/theme/app_theme.dart';
import '../src/core/profile_pictures.dart';
import '../src/features/accounts/screens/accounts_screen.dart';
import '../src/features/onboarding/lost_password_screen.dart';
import '../src/features/settings/screens/settings_change_password_screen.dart';
import '../src/features/settings/screens/settings_endpoint_screen.dart';
import '../src/features/settings/screens/settings_screen.dart';
import '../src/features/settings/screens/settings_seed_phrase_screen.dart';
import '../src/features/settings/screens/settings_uninstall_screen.dart';
import '../src/features/onboarding/unlock_screen.dart';
import '../src/features/onboarding/welcome.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';

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
    initialModal: AccountsScreenInitialModal.accountName,
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
  _PreviewSyncNotifier(this.activeAccountUuid);

  final String? activeAccountUuid;

  @override
  Future<SyncState> build() async => SyncState(
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
