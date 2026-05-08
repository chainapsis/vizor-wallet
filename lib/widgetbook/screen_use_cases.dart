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
import '../src/core/profile_pictures.dart';
import '../src/features/accounts/screens/accounts_screen.dart';
import '../src/features/onboarding/lost_password_screen.dart';
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
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_accountsBootstrap),
      accountProvider.overrideWith(
        () => _PreviewAccountNotifier(_accountsState),
      ),
      syncProvider.overrideWith(_PreviewSyncNotifier.new),
    ],
    child: _AccountsHarness(),
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
        GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
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
    return Router.withConfig(config: _router);
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
    return Router.withConfig(config: _router);
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
    return Router.withConfig(config: _router);
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

final _accountsState = AccountState(
  accounts: [
    const AccountInfo(
      uuid: 'preview-account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
    for (var index = 2; index <= 20; index += 1)
      AccountInfo(
        uuid: 'preview-account-$index',
        name: 'Account $index',
        order: index - 1,
        profilePictureId: index.isEven ? 'samurai' : 'knight',
      ),
  ],
  activeAccountUuid: 'preview-account-1',
  activeAddress: 'u1widgetbookaccountsaddress',
);

final _accountsBootstrap = AppBootstrapState(
  initialLocation: '/accounts',
  initialAccountState: _accountsState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

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
  @override
  Future<SyncState> build() async => SyncState();

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
