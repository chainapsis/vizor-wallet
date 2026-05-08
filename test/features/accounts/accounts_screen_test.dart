import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/accounts/screens/accounts_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('accounts screen renders active account and other accounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_accountsHarness());
    await tester.pump();

    expect(find.text('Accounts'), findsOneWidget);
    final paneTop = tester.getTopLeft(find.byType(AppDesktopPane)).dy;
    final paneHeight = tester.getSize(find.byType(AppDesktopPane)).height;
    final titleTop = tester.getTopLeft(find.text('Accounts')).dy;
    expect(titleTop, lessThan(paneTop + paneHeight * 0.25));
    expect(
      find.byKey(const ValueKey('accounts_active_row_account-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('accounts_other_row_account-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('accounts_other_row_account-3')),
      findsOneWidget,
    );
    expect(find.text('Other'), findsOneWidget);

    await tester.tap(find.text('Add Account'));
    await tester.pumpAndSettle();

    expect(find.text('add account route'), findsOneWidget);
  });

  testWidgets('sidebar account selector opens accounts screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_sidebarHarness());
    await tester.pump();

    expect(find.text('home route'), findsOneWidget);

    final accountsButton = find.byKey(
      const ValueKey('sidebar_accounts_button'),
    );
    final walletButton = find.byKey(const ValueKey('sidebar_wallet_button'));
    expect(
      tester.getTopLeft(accountsButton).dy,
      lessThan(tester.getTopLeft(walletButton).dy),
    );

    await tester.tap(accountsButton);
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget);
  });

  testWidgets('selecting another account makes it active', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    late _FakeSyncNotifier syncNotifier;
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier:
            () => _FakeAccountNotifier(_bootstrap.initialAccountState),
        syncNotifier: () => syncNotifier = _FakeSyncNotifier(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Shielded Savings'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('accounts_active_row_account-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('accounts_other_row_account-1')),
      findsOneWidget,
    );
    expect(syncNotifier.refreshCount, 1);
  });

  testWidgets('account row menu opens actions and dismisses', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final syncNotifier = _FakeSyncNotifier();
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier:
            () => _FakeAccountNotifier(_bootstrap.initialAccountState),
        syncNotifier: () => syncNotifier,
      ),
    );
    await tester.pump();

    final row = find.byKey(const ValueKey('accounts_other_row_account-2'));
    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Name'), findsOneWidget);
    expect(find.text('Change Picture'), findsOneWidget);
    expect(find.text('Remove Account'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('accounts_active_row_account-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('accounts_other_row_account-2')),
      findsOneWidget,
    );
    expect(
      _accountRowBackgroundColor(tester, row),
      AppThemeData.light.colors.background.base,
    );
    expect(syncNotifier.refreshCount, 0);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Edit Name'), findsNothing);
    expect(find.text('Change Picture'), findsNothing);
    expect(find.text('Remove Account'), findsNothing);
  });

  testWidgets('account rows show hover treatment', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_accountsHarness());
    await tester.pump();

    final row = find.byKey(const ValueKey('accounts_other_row_account-2'));
    expect(_accountRowBackgroundColor(tester, row), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();

    expect(
      _accountRowBackgroundColor(tester, row),
      AppThemeData.light.colors.background.base,
    );
  });
}

Widget _accountsHarness({
  AccountNotifier Function()? accountNotifier,
  SyncNotifier Function()? syncNotifier,
}) {
  final router = GoRouter(
    initialLocation: '/accounts',
    routes: [
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings route'),
      ),
      GoRoute(path: '/about', builder: (_, _) => const Text('about route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      if (accountNotifier != null)
        accountProvider.overrideWith(accountNotifier),
      if (syncNotifier != null) syncProvider.overrideWith(syncNotifier),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Widget _sidebarHarness() {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder:
            (_, _) => const AppDesktopShell(
              sidebar: AppMainSidebar(),
              pane: AppDesktopPane(child: Text('home route')),
            ),
      ),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account route'),
      ),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Text('settings route'),
      ),
      GoRoute(path: '/about', builder: (_, _) => const Text('about route')),
    ],
  );

  return ProviderScope(
    overrides: [appBootstrapProvider.overrideWithValue(_bootstrap)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/accounts',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Primary Vault', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Shielded Savings', order: 1),
      AccountInfo(uuid: 'account-3', name: 'Travel Funds', order: 2),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1accountsaddress',
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

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }
}

class _FakeSyncNotifier extends SyncNotifier {
  int refreshCount = 0;

  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<void> refreshAfterSend() async {
    refreshCount += 1;
  }
}

Color? _accountRowBackgroundColor(WidgetTester tester, Finder row) {
  final containerFinder = find.descendant(
    of: row,
    matching: find.byType(AnimatedContainer),
  );
  final container = tester.widget<AnimatedContainer>(containerFinder.first);
  return (container.decoration as BoxDecoration?)?.color;
}
