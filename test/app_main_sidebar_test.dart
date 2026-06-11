import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  const failureLabels = {
    SyncFailureKind.endpoint: 'Syncing failed. Endpoint error...',
    SyncFailureKind.databaseBusy: 'Syncing failed. Wallet data busy...',
    SyncFailureKind.databaseFatal: 'Syncing failed. Wallet data error...',
    SyncFailureKind.chainRecovery: 'Syncing failed. Chain recovery...',
    SyncFailureKind.parseFatal: 'Syncing failed. Data error...',
    SyncFailureKind.unknown: 'Syncing failed. Unknown error...',
  };

  testWidgets('sidebar shows in-progress sync percentage', (tester) async {
    await tester.pumpWidget(
      _sidebarHarness(
        SyncState(isSyncing: true, percentage: 1, displayPercentage: 1),
      ),
    );
    await tester.pump();

    expect(find.text('99% Syncing...'), findsOneWidget);
    expect(find.text('Vizor is synced'), findsNothing);
  });

  testWidgets('sidebar shows primary navigation', (tester) async {
    await tester.pumpWidget(_sidebarHarness(_syncedSyncState));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('sidebar_accounts_button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sidebar_home_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_swap_button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar_activity_button')),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Swap'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Wallet'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Receive'), findsNothing);
    expect(find.text('Vote'), findsNothing);
    expect(find.text('Address book'), findsNothing);
    expect(find.text('About Vizor'), findsNothing);
  });

  testWidgets('sidebar keeps Home active and clickable on send routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, initialLocation: '/send'),
    );
    await tester.pump();

    final homeItem = tester.widget<AppSidebarItem>(
      find.byKey(const ValueKey('sidebar_home_button')),
    );
    expect(homeItem.active, isTrue);
    expect(homeItem.onTap, isNotNull);
    expect(find.text('send route'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar_home_button')));
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
    expect(find.text('send route'), findsNothing);
  });

  testWidgets('sidebar keeps Home active and clickable on receive routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, initialLocation: '/receive'),
    );
    await tester.pump();

    final homeItem = tester.widget<AppSidebarItem>(
      find.byKey(const ValueKey('sidebar_home_button')),
    );
    expect(homeItem.active, isTrue);
    expect(homeItem.onTap, isNotNull);
    expect(find.text('receive route'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar_home_button')));
    await tester.pumpAndSettle();

    expect(find.text('home route'), findsOneWidget);
    expect(find.text('receive route'), findsNothing);
  });

  testWidgets('sidebar accounts popover shows boundaries and click cursors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, accountState: _multiAccountState),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('sidebar_accounts_button')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('sidebar_accounts_popover')),
      findsOneWidget,
    );
    expect(find.text('My accounts'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar_accounts_divider_0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sidebar_accounts_actions_divider')),
      findsOneWidget,
    );

    final popoverDecoration = _boxDecorationByKey(
      tester,
      const ValueKey('sidebar_accounts_popover'),
    );
    // The Figma dropdown has no stroke; its outline comes from the
    // three-layer shadow stack.
    expect(popoverDecoration.border, isNull);
    expect(popoverDecoration.boxShadow, hasLength(3));
    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('sidebar_accounts_scrollbar')),
    );
    expect(scrollbar.controller, isNotNull);
    expect(scrollbar.thumbVisibility, isFalse);
    expect(
      DefaultTextStyle.of(
        tester.element(find.text('My accounts')),
      ).style.decoration,
      TextDecoration.none,
    );
    expect(_cursorForText(tester, 'Primary Vault'), SystemMouseCursors.click);
    expect(
      _cursorForKey(tester, const ValueKey('sidebar_accounts_manage')),
      SystemMouseCursors.click,
    );
    expect(
      _cursorForKey(tester, const ValueKey('sidebar_accounts_add')),
      SystemMouseCursors.click,
    );
  });

  testWidgets('sidebar accounts popover scrolls long account list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, accountState: _manyAccountState),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('sidebar_accounts_button')));
    await tester.pump();

    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('sidebar_accounts_scrollbar')),
    );
    expect(scrollbar.controller, isNotNull);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(find.text('Account 8'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('sidebar_accounts_list')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account 8'), findsOneWidget);
    final listBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('sidebar_accounts_list')))
        .dy;
    final lastRowBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey('sidebar_account_popover_row_account-8')),
        )
        .dy;
    expect(
      listBottom - lastRowBottom,
      moreOrLessEquals(AppSpacing.xs, epsilon: 0.1),
    );
  });

  testWidgets('sidebar accounts popover closes on outside pane click', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, accountState: _multiAccountState),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('sidebar_accounts_button')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('sidebar_accounts_popover')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(420, 120));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('sidebar_accounts_popover')),
      findsNothing,
    );
  });

  testWidgets('sidebar hides Swap when swap feature is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, swapEnabled: false),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('sidebar_swap_button')), findsNothing);
    expect(find.text('Swap'), findsNothing);
    expect(find.byKey(const ValueKey('sidebar_home_button')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar_activity_button')),
      findsOneWidget,
    );
    expect(find.text('Activity'), findsOneWidget);
  });

  testWidgets('sidebar Swap item opens the swap route', (tester) async {
    await tester.pumpWidget(_sidebarHarness(_syncedSyncState));
    await tester.pump();

    await tester.tap(find.text('Swap'));
    await tester.pumpAndSettle();

    expect(find.text('swap'), findsOneWidget);
  });

  testWidgets('sidebar Activity item opens the activity route', (tester) async {
    await tester.pumpWidget(_sidebarHarness(_syncedSyncState));
    await tester.pump();

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.text('activity'), findsOneWidget);
  });

  testWidgets('sidebar Settings item opens the settings route', (tester) async {
    await tester.pumpWidget(_sidebarHarness(_syncedSyncState));
    await tester.pump();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('sidebar keeps primary navigation item spacing consistent', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebarHarness(_syncedSyncState));
    await tester.pump();

    final positions = [
      tester.getTopLeft(find.text('Home')).dy,
      tester.getTopLeft(find.text('Swap')).dy,
      tester.getTopLeft(find.text('Activity')).dy,
    ];
    final gaps = [
      for (var i = 1; i < positions.length; i++)
        positions[i] - positions[i - 1],
    ];

    for (final gap in gaps.skip(1)) {
      expect(gap, moreOrLessEquals(gaps.first, epsilon: 0.1));
    }
  });

  testWidgets('sidebar disables only Swap and Activity while importing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: false,
          isSyncing: true,
          displayPercentage: 0.32,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Importing...'), findsOneWidget);

    await tester.tap(find.text('Swap'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('swap'), findsNothing);

    await tester.tap(find.text('Activity'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('activity'), findsNothing);
    expect(find.text('home route'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar_accounts_button')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('sidebar_accounts_popover')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(420, 120));
    await tester.pump();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('sidebar sync indicator is pinned to the sidebar edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(SyncState(isSyncing: true, displayPercentage: 0.34)),
    );
    await tester.pump();

    final indicatorLeft = tester
        .getTopLeft(find.byKey(const ValueKey('sidebar_sync_indicator')))
        .dx;
    final textLeft = tester
        .getTopLeft(find.byKey(const ValueKey('sidebar_sync_text')))
        .dx;

    expect(indicatorLeft, moreOrLessEquals(AppSpacing.xs, epsilon: 0.1));
    expect(
      textLeft - indicatorLeft,
      moreOrLessEquals(AppSpacing.sm + AppSpacing.xs, epsilon: 0.1),
    );
  });

  testWidgets('sidebar shows synced state after sync completes', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebarHarness(SyncState()));
    await tester.pump();

    expect(find.text('Vizor is synced'), findsOneWidget);
    expect(find.textContaining('Syncing'), findsNothing);
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('sidebar_sync_text')),
    );
    expect(text.style?.color, AppThemeData.light.colors.sync.text);
    expect(
      _syncIndicatorColor(tester),
      AppThemeData.light.colors.sync.lightSuccess,
    );
  });

  testWidgets('sidebar treats complete background progress as synced', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(
        SyncState(
          isBackgroundMode: true,
          percentage: 1,
          displayPercentage: 1,
          scannedHeight: 100,
          chainTipHeight: 100,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Vizor is synced'), findsOneWidget);
    expect(find.text('99% Syncing...'), findsNothing);
  });

  testWidgets('sidebar keeps network sync failures visible', (tester) async {
    await tester.pumpWidget(
      _sidebarHarness(
        SyncState(
          failure: const SyncFailure(
            kind: SyncFailureKind.network,
            rawMessage: 'network failed',
            userMessage: 'Network connection lost.',
            showSettingsAction: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Syncing failed. Network error...'), findsOneWidget);
    expect(find.text('Vizor is synced'), findsNothing);
    final text = tester.widget<Text>(
      find.byKey(const ValueKey('sidebar_sync_text')),
    );
    expect(text.style?.color, AppThemeData.light.colors.sync.textError);
    expect(
      _syncIndicatorColor(tester),
      AppThemeData.light.colors.sync.lightError,
    );
  });

  testWidgets('sidebar uses dark success sync indicator color from Figma', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(SyncState(), themeData: AppThemeData.dark),
    );
    await tester.pump();

    expect(_syncIndicatorColor(tester), const Color(0xFF0DC87D));
  });

  testWidgets('sidebar uses dark failure sync indicator color from Figma', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(
        SyncState(
          failure: const SyncFailure(
            kind: SyncFailureKind.network,
            rawMessage: 'network failed',
            userMessage: 'Network connection lost.',
            showSettingsAction: false,
          ),
        ),
        themeData: AppThemeData.dark,
      ),
    );
    await tester.pump();

    expect(_syncIndicatorColor(tester), const Color(0xFFA3A4A4));
  });

  for (final entry in failureLabels.entries) {
    testWidgets('sidebar maps ${entry.key} sync failures', (tester) async {
      await tester.pumpWidget(
        _sidebarHarness(
          SyncState(
            failure: SyncFailure(
              kind: entry.key,
              rawMessage: 'failure',
              userMessage: 'Sync failed.',
              showSettingsAction: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(entry.value), findsOneWidget);
    });
  }
}

Color? _syncIndicatorColor(WidgetTester tester) {
  final indicator = find.byKey(const ValueKey('sidebar_sync_indicator'));
  final decoratedBox = tester.widget<DecoratedBox>(
    find.ancestor(of: indicator, matching: find.byType(DecoratedBox)).first,
  );
  return (decoratedBox.decoration as BoxDecoration).color;
}

BoxDecoration _boxDecorationByKey(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.byKey(key));
  return container.decoration! as BoxDecoration;
}

MouseCursor _cursorForText(WidgetTester tester, String text) {
  final mouseRegion = tester.widget<MouseRegion>(
    find
        .ancestor(of: find.text(text), matching: find.byType(MouseRegion))
        .first,
  );
  return mouseRegion.cursor;
}

MouseCursor _cursorForKey(WidgetTester tester, Key key) {
  final mouseRegion = tester.widget<MouseRegion>(
    find
        .ancestor(of: find.byKey(key), matching: find.byType(MouseRegion))
        .first,
  );
  return mouseRegion.cursor;
}

final _syncedSyncState = SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
);

Widget _sidebarHarness(
  SyncState syncState, {
  AppThemeData themeData = AppThemeData.light,
  bool swapEnabled = true,
  AccountState? accountState,
  String initialLocation = '/home',
}) {
  final bootstrap = _bootstrapFor(accountState ?? _singleAccountState);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('home route')),
        ),
      ),
      GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
      GoRoute(
        path: '/send',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('send route')),
        ),
      ),
      GoRoute(
        path: '/receive',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('receive route')),
        ),
      ),
      GoRoute(path: '/swap', builder: (_, _) => const Text('swap')),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting')),
      GoRoute(
        path: '/address-book',
        builder: (_, _) => const Text('address book'),
      ),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account'),
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const Text('unlock')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(syncState)),
      swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: themeData, child: child!),
    ),
  );
}

const _singleAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

const _multiAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-2',
      name: 'Trading Vault',
      order: 1,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

const _manyAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account 1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-2',
      name: 'Account 2',
      order: 1,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-3',
      name: 'Account 3',
      order: 2,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-4',
      name: 'Account 4',
      order: 3,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-5',
      name: 'Account 5',
      order: 4,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-6',
      name: 'Account 6',
      order: 5,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-7',
      name: 'Account 7',
      order: 6,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-8',
      name: 'Account 8',
      order: 7,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

AppBootstrapState _bootstrapFor(AccountState accountState) => AppBootstrapState(
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

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
