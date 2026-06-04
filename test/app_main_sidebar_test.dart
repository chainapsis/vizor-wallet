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
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  const failureLabels = {
    SyncFailureKind.endpoint: 'Syncing failed: Endpoint error',
    SyncFailureKind.databaseBusy: 'Syncing failed: Wallet data busy',
    SyncFailureKind.databaseFatal: 'Syncing failed: Wallet data error',
    SyncFailureKind.chainRecovery: 'Syncing failed: Chain recovery',
    SyncFailureKind.parseFatal: 'Syncing failed: Data error',
    SyncFailureKind.unknown: 'Syncing failed: Unknown error',
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

  testWidgets('sidebar hides Swap when swap feature is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebarHarness(SyncState(), swapEnabled: false));
    await tester.pump();

    expect(find.byKey(const ValueKey('sidebar_swap_button')), findsNothing);
    expect(find.text('Swap'), findsNothing);
    expect(find.byKey(const ValueKey('sidebar_home_button')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    final homeIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar_home_button')),
        matching: find.byType(AppIcon),
      ),
    );
    expect(homeIcon.name, AppIcons.home);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Receive'), findsNothing);
    expect(find.byKey(const ValueKey('sidebar_voting_button')), findsOneWidget);
    expect(find.text('Vote'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar_address_book_button')),
      findsOneWidget,
    );
  });

  testWidgets('sidebar Vote item opens the voting route', (tester) async {
    await tester.pumpWidget(_sidebarHarness(SyncState()));
    await tester.pump();

    await tester.tap(find.text('Vote'));
    await tester.pumpAndSettle();

    expect(find.text('voting'), findsOneWidget);
  });

  testWidgets('sidebar Address Book item opens the address book route', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebarHarness(SyncState()));
    await tester.pump();

    await tester.tap(find.text('Address book'));
    await tester.pumpAndSettle();

    expect(find.text('address book'), findsOneWidget);
  });

  testWidgets('sidebar keeps primary navigation item spacing consistent', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebarHarness(SyncState()));
    await tester.pump();

    final positions = [
      tester.getTopLeft(find.text('Home')).dy,
      tester.getTopLeft(find.text('Swap')).dy,
      tester.getTopLeft(find.text('Vote')).dy,
      tester.getTopLeft(find.text('Address book')).dy,
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

    expect(indicatorLeft, moreOrLessEquals(0, epsilon: 0.1));
    expect(textLeft - indicatorLeft, moreOrLessEquals(32, epsilon: 0.1));
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

    expect(find.text('Syncing failed: Network error'), findsOneWidget);
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

Widget _sidebarHarness(
  SyncState syncState, {
  AppThemeData themeData = AppThemeData.light,
  bool swapEnabled = true,
}) {
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
      GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send')),
      GoRoute(path: '/swap', builder: (_, _) => const Text('swap')),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive')),
      GoRoute(
        path: '/address-book',
        builder: (_, _) => const Text('address book'),
      ),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(path: '/about', builder: (_, _) => const Text('about')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(syncState)),
      swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: themeData, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
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

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
