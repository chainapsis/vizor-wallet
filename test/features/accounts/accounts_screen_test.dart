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
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
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
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Keystone'), findsOneWidget);
    final keystoneIcon = tester
        .widgetList<AppIcon>(find.byType(AppIcon))
        .singleWhere((icon) => icon.name == AppIcons.keystone);
    expect(keystoneIcon.color, AppThemeData.light.colors.icon.accent);

    await tester.tap(find.text('Add Account'));
    await tester.pumpAndSettle();

    expect(find.text('add account route'), findsOneWidget);
  });

  testWidgets(
    'accounts screen hides other section when there are no other accounts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1512, 982));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      const accountState = AccountState(
        accounts: [
          AccountInfo(
            uuid: 'account-1',
            name: 'Primary Vault',
            order: 0,
            isSeedAnchor: true,
          ),
        ],
        activeAccountUuid: 'account-1',
        activeAddress: 'u1accountsaddress',
      );
      await tester.pumpWidget(
        _accountsHarness(
          accountNotifier: () => _FakeAccountNotifier(accountState),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('accounts_active_row_account-1')),
        findsOneWidget,
      );
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      expect(find.text('Add Account'), findsOneWidget);
    },
  );

  testWidgets('other accounts list scrolls while add account stays pinned', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final accountState = AccountState(
      accounts: [
        const AccountInfo(
          uuid: 'account-1',
          name: 'Primary Vault',
          order: 0,
          isSeedAnchor: true,
        ),
        for (var index = 2; index <= 20; index += 1)
          AccountInfo(
            uuid: 'account-$index',
            name: 'Account $index',
            order: index - 1,
          ),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1accountsaddress',
    );
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => _FakeAccountNotifier(accountState),
      ),
    );
    await tester.pump();

    final addButton = find.text('Add Account');
    final addButtonTop = tester.getTopLeft(addButton).dy;

    expect(
      find.byKey(const ValueKey('accounts_list_scrollbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('accounts_active_row_account-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('accounts_other_row_account-20')),
      findsNothing,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('accounts_active_row_account-1')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(addButton).dy, moreOrLessEquals(addButtonTop));
    expect(
      find.byKey(const ValueKey('accounts_other_row_account-20')),
      findsOneWidget,
    );
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

    late _FakeAccountNotifier accountNotifier;
    late _FakeSyncNotifier syncNotifier;
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => accountNotifier = _FakeAccountNotifier(
          _bootstrap.initialAccountState,
        ),
        syncNotifier: () => syncNotifier = _FakeSyncNotifier(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Shielded Savings'));
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
    expect(accountNotifier.switchedUuid, 'account-2');
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
        accountNotifier: () =>
            _FakeAccountNotifier(_bootstrap.initialAccountState),
        syncNotifier: () => syncNotifier,
      ),
    );
    await tester.pump();

    final menuButton = find.byKey(
      const ValueKey('accounts_row_menu_button_account-2'),
    );
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
      _accountMenuButtonBackgroundColor(tester, menuButton),
      AppThemeData.light.colors.background.base,
    );
    expect(syncNotifier.refreshCount, 0);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Edit Name'), findsNothing);
    expect(find.text('Change Picture'), findsNothing);
    expect(find.text('Remove Account'), findsNothing);
  });

  testWidgets('account row hover is limited to other accounts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_accountsHarness());
    await tester.pump();

    final row = find.byKey(const ValueKey('accounts_other_row_account-2'));
    final activeRow = find.byKey(
      const ValueKey('accounts_active_row_account-1'),
    );
    final menuButton = find.byKey(
      const ValueKey('accounts_row_menu_button_account-2'),
    );
    final activeMenuButton = find.byKey(
      const ValueKey('accounts_row_menu_button_account-1'),
    );
    expect(_accountRowBackgroundColor(tester, 'account-2'), isNull);
    expect(_accountRowBackgroundColor(tester, 'account-1'), isNull);
    expect(_accountMenuButtonBackgroundColor(tester, menuButton), isNull);
    expect(_accountMenuButtonBackgroundColor(tester, activeMenuButton), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();

    expect(
      _accountRowBackgroundColor(tester, 'account-2'),
      AppThemeData.light.colors.background.base,
    );
    expect(_accountMenuButtonBackgroundColor(tester, menuButton), isNull);

    await mouse.moveTo(tester.getCenter(menuButton));
    await tester.pumpAndSettle();

    expect(
      _accountRowBackgroundColor(tester, 'account-2'),
      AppThemeData.light.colors.background.base,
    );
    expect(
      _accountMenuButtonBackgroundColor(tester, menuButton),
      AppThemeData.light.colors.background.base,
    );

    await mouse.moveTo(tester.getCenter(activeRow));
    await tester.pumpAndSettle();

    expect(_accountRowBackgroundColor(tester, 'account-1'), isNull);
    expect(_accountMenuButtonBackgroundColor(tester, activeMenuButton), isNull);

    await mouse.moveTo(tester.getCenter(activeMenuButton));
    await tester.pumpAndSettle();

    expect(_accountRowBackgroundColor(tester, 'account-1'), isNull);
    expect(
      _accountMenuButtonBackgroundColor(tester, activeMenuButton),
      AppThemeData.light.colors.background.base,
    );
  });

  testWidgets('only the last seed anchor is protected from removal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    const accountState = AccountState(
      accounts: [
        AccountInfo(uuid: 'account-1', name: 'Imported First', order: 0),
        AccountInfo(
          uuid: 'account-2',
          name: 'Seed Anchor',
          order: 1,
          isSeedAnchor: true,
        ),
        AccountInfo(uuid: 'account-3', name: 'Imported Other', order: 2),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1accountsaddress',
    );
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => _FakeAccountNotifier(accountState),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remove Account'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remove Account'), findsNothing);
  });

  testWidgets('edit name menu action renames the selected account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final accountNotifier = _FakeAccountNotifier(
      _bootstrap.initialAccountState,
    );
    await tester.pumpWidget(
      _accountsHarness(accountNotifier: () => accountNotifier),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Name'));
    await tester.pumpAndSettle();

    expect(find.text('New Account Name'), findsOneWidget);
    expect(find.byType(AppPaneModalOverlay), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(BackdropFilter)),
      tester.getTopLeft(find.byType(AppDesktopPane)),
    );
    expect(
      tester.getSize(find.byType(BackdropFilter)),
      tester.getSize(find.byType(AppDesktopPane)),
    );

    await tester.enterText(find.byType(TextField), 'Savings Vault');
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(accountNotifier.renamedUuid, 'account-2');
    expect(accountNotifier.renamedName, 'Savings Vault');
    expect(find.text('Savings Vault'), findsOneWidget);
    expect(find.text('New Account Name'), findsNothing);
  });

  testWidgets('change picture menu action updates the selected account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final accountNotifier = _FakeAccountNotifier(
      _bootstrap.initialAccountState,
    );
    await tester.pumpWidget(
      _accountsHarness(accountNotifier: () => accountNotifier),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change Picture'));
    await tester.pumpAndSettle();

    expect(find.text('Select Profile Picture'), findsOneWidget);
    expect(find.byType(AppPaneModalOverlay), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('profile_picture_option_samurai')),
    );
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(accountNotifier.updatedProfilePictureUuid, 'account-2');
    expect(accountNotifier.updatedProfilePictureId, 'samurai');
    expect(find.text('Select Profile Picture'), findsNothing);
  });

  testWidgets('remove account menu action removes the selected account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final accountNotifier = _FakeAccountNotifier(
      _bootstrap.initialAccountState,
    );
    final syncNotifier = _FakeSyncNotifier();
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => accountNotifier,
        syncNotifier: () => syncNotifier,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Account'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Are you sure you want to remove this account?'),
      findsOneWidget,
    );
    expect(
      find.textContaining("This action can't be reverted."),
      findsOneWidget,
    );
    expect(
      find.textContaining('You will have to re-import your account.'),
      findsOneWidget,
    );
    expect(find.byType(AppPaneModalOverlay), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(accountNotifier.removedUuid, 'account-2');
    expect(syncNotifier.refreshCount, 1);
    expect(
      find.byKey(const ValueKey('accounts_other_row_account-2')),
      findsNothing,
    );
    expect(
      find.textContaining('Are you sure you want to remove this account?'),
      findsNothing,
    );
  });

  testWidgets('remove account pauses sync mutation before deleting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final events = <String>[];
    final accountNotifier = _FakeAccountNotifier(
      _bootstrap.initialAccountState,
      events: events,
    );
    final syncNotifier = _FakeSyncNotifier(events: events);
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => accountNotifier,
        syncNotifier: () => syncNotifier,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(events, ['pause', 'remove:account-2', 'resume', 'refresh']);
  });

  testWidgets('remove modal shows stopping sync before removing account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final pauseCompleter = Completer<void>();
    final removeCompleter = Completer<void>();
    final accountNotifier = _FakeAccountNotifier(
      _bootstrap.initialAccountState,
      removeCompleter: removeCompleter,
    );
    final syncNotifier = _FakeSyncNotifier(pauseCompleter: pauseCompleter);
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => accountNotifier,
        syncNotifier: () => syncNotifier,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump();

    expect(find.text('Stopping sync...'), findsOneWidget);
    expect(find.text('Removing account...'), findsNothing);

    pauseCompleter.complete();
    await tester.pump();

    expect(find.text('Stopping sync...'), findsNothing);
    expect(find.text('Removing account...'), findsOneWidget);

    removeCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Removing account...'), findsNothing);
    expect(accountNotifier.removedUuid, 'account-2');
  });

  testWidgets('remove account logs timing checkpoints', (tester) async {
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      await tester.binding.setSurfaceSize(const Size(1512, 982));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      final events = <String>[];
      final accountNotifier = _FakeAccountNotifier(
        _bootstrap.initialAccountState,
        events: events,
      );
      final syncNotifier = _FakeSyncNotifier(events: events);
      await tester.pumpWidget(
        _accountsHarness(
          accountNotifier: () => accountNotifier,
          syncNotifier: () => syncNotifier,
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('accounts_row_menu_button_account-2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(
      messages.any(
        (message) => message.contains('removeAccountFlow: sync pause complete'),
      ),
      isTrue,
    );
    expect(
      messages.any(
        (message) =>
            message.contains('removeAccountFlow: account mutation complete'),
      ),
      isTrue,
    );
    expect(
      messages.any(
        (message) =>
            message.contains('removeAccountFlow: refreshAfterSend complete'),
      ),
      isTrue,
    );
  });

  testWidgets('removing the last account resets the wallet and goes welcome', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    const singleAccountState = AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: 'Primary Vault',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1accountsaddress',
    );
    final events = <String>[];
    final accountNotifier = _FakeAccountNotifier(
      singleAccountState,
      events: events,
    );
    final syncNotifier = _FakeSyncNotifier(events: events);
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => accountNotifier,
        syncNotifier: () => syncNotifier,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Account'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Removing this account will completely reset the Vizor app.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'This means deleting all accounts and requiring you to import accounts again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('This cannot be undone.'), findsOneWidget);

    await tester.tap(find.text('Reset Vizor'));
    await tester.pumpAndSettle();

    expect(events, ['pause', 'resetWallet', 'clearCachedWalletDbPath']);
    expect(accountNotifier.resetWalletCalled, isTrue);
    expect(find.text('welcome route'), findsOneWidget);
  });

  testWidgets('last account reset failure shows reset-specific error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    const singleAccountState = AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: 'Primary Vault',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1accountsaddress',
    );
    final accountNotifier = _FakeAccountNotifier(
      singleAccountState,
      resetError: Exception('reset failed'),
    );
    await tester.pumpWidget(
      _accountsHarness(
        accountNotifier: () => accountNotifier,
        syncNotifier: () => _FakeSyncNotifier(),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('accounts_row_menu_button_account-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Vizor'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reset Vizor."), findsOneWidget);
    expect(find.text("Couldn't remove account."), findsNothing);
    expect(find.text('welcome route'), findsNothing);
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
      GoRoute(path: '/welcome', builder: (_, _) => const Text('welcome route')),
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
        builder: (_, _) => const AppDesktopShell(
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
      AccountInfo(
        uuid: 'account-1',
        name: 'Primary Vault',
        order: 0,
        isSeedAnchor: true,
      ),
      AccountInfo(
        uuid: 'account-2',
        name: 'Shielded Savings',
        order: 1,
        isHardware: true,
        profilePictureId: kDefaultProfilePictureId,
      ),
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
  _FakeAccountNotifier(
    this.initialState, {
    this.events,
    this.removeCompleter,
    this.resetError,
  });

  final AccountState initialState;
  final List<String>? events;
  final Completer<void>? removeCompleter;
  final Object? resetError;
  String? renamedUuid;
  String? renamedName;
  String? updatedProfilePictureUuid;
  String? updatedProfilePictureId;
  String? removedUuid;
  String? switchedUuid;
  bool resetWalletCalled = false;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    switchedUuid = uuid;
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }

  @override
  Future<void> renameAccount(String uuid, String newName) async {
    renamedUuid = uuid;
    renamedName = newName;
    final prev = state.value ?? initialState;
    final updated = [
      for (final account in prev.accounts)
        if (account.uuid == uuid) account.copyWith(name: newName) else account,
    ];
    state = AsyncData(prev.copyWith(accounts: updated));
  }

  @override
  Future<void> updateProfilePicture(
    String uuid,
    String profilePictureId,
  ) async {
    updatedProfilePictureUuid = uuid;
    updatedProfilePictureId = profilePictureId;
    final prev = state.value ?? initialState;
    final updated = [
      for (final account in prev.accounts)
        if (account.uuid == uuid)
          account.copyWith(profilePictureId: profilePictureId)
        else
          account,
    ];
    state = AsyncData(prev.copyWith(accounts: updated));
  }

  @override
  Future<void> removeAccount(String uuid) async {
    events?.add('remove:$uuid');
    removedUuid = uuid;
    await removeCompleter?.future;
    final prev = state.value ?? initialState;
    final updated = [
      for (final account in prev.accounts)
        if (account.uuid != uuid) account,
    ];
    state = AsyncData(prev.copyWith(accounts: updated));
  }

  @override
  Future<void> resetWallet() async {
    events?.add('resetWallet');
    final error = resetError;
    if (error != null) {
      throw error;
    }
    resetWalletCalled = true;
    state = const AsyncData(AccountState());
  }
}

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier({this.events, this.pauseCompleter});

  final List<String>? events;
  final Completer<void>? pauseCompleter;
  int refreshCount = 0;

  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<void> refreshAfterSend() async {
    events?.add('refresh');
    refreshCount += 1;
  }

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    events?.add('pause');
    await pauseCompleter?.future;
    return const WalletMutationSyncPause(
      hadActiveSync: true,
      hadPolling: false,
      hadBackgroundSync: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {
    events?.add('resume');
  }

  @override
  void clearCachedWalletDbPath() {
    events?.add('clearCachedWalletDbPath');
  }

  @override
  Future<void> clearSensitiveStateForLock() async {
    events?.add('clearSensitiveState');
  }
}

Color? _accountMenuButtonBackgroundColor(WidgetTester tester, Finder button) {
  final containerFinder = find.descendant(
    of: button,
    matching: find.byType(AnimatedContainer),
  );
  final container = tester.widget<AnimatedContainer>(containerFinder.first);
  return (container.decoration as BoxDecoration?)?.color;
}

Color? _accountRowBackgroundColor(WidgetTester tester, String accountUuid) {
  final container = tester.widget<AnimatedContainer>(
    find.byKey(ValueKey('accounts_row_background_$accountUuid')),
  );
  return (container.decoration as BoxDecoration?)?.color;
}
