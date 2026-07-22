import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

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
    expect(find.byKey(const ValueKey('sidebar_voting_button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar_activity_button')),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Swap'), findsOneWidget);
    expect(find.text('Vote'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Wallet'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Receive'), findsNothing);
    expect(find.text('Address book'), findsNothing);
    expect(find.text('About Vizor'), findsNothing);
  });

  testWidgets(
    'sidebar keeps software migration automatic while children await anchors',
    (tester) async {
      await tester.pumpWidget(
        _sidebarHarness(
          _syncedSyncState,
          migrationCoordinatorState: IronwoodMigrationCoordinatorState(
            statuses: {'account-1': _readyMigrationStatus},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Migrating...'), findsOneWidget);
      expect(find.text('Needs input'), findsNothing);
      expect(
        find.byKey(const ValueKey('sidebar_orchard_home_row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('sidebar_migration_progress_button')),
        findsOneWidget,
      );
      expect(find.text('Ironwood'), findsOneWidget);
    },
  );

  testWidgets('sidebar keeps migration home rows while parts complete', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(
        _syncedSyncState,
        migrationCoordinatorState: IronwoodMigrationCoordinatorState(
          statuses: {'account-1': _mixedMigrationStatus},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Migrating...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar_orchard_balance')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sidebar_ironwood_balance')),
      findsOneWidget,
    );
    expect(find.textContaining('/3'), findsNothing);
  });

  testWidgets('sidebar requests input only for Keystone migration', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(
        _syncedSyncState,
        accountState: _hardwareAccountState,
        migrationCoordinatorState: IronwoodMigrationCoordinatorState(
          statuses: {'account-1': _readyMigrationStatus},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Needs input'), findsOneWidget);
    expect(find.text('Migrating...'), findsNothing);
    expect(
      find.byKey(const ValueKey('sidebar_migration_progress_button')),
      findsOneWidget,
    );
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

  testWidgets('sidebar keeps exact active navigation items clickable', (
    tester,
  ) async {
    final cases = [
      (route: '/home', label: 'Home'),
      (route: '/swap', label: 'Swap'),
      (route: '/voting', label: 'Vote'),
      (route: '/activity', label: 'Activity'),
      (route: '/settings', label: 'Settings'),
    ];

    for (final entry in cases) {
      await tester.pumpWidget(
        _sidebarHarness(_syncedSyncState, initialLocation: entry.route),
      );
      await tester.pump();

      final item = _sidebarItemWithLabel(tester, entry.label);
      expect(item.active, isTrue, reason: entry.label);
      expect(item.onTap, isNotNull, reason: entry.label);
      expect(_cursorForText(tester, entry.label), SystemMouseCursors.click);

      await tester.tap(find.text(entry.label));
      await tester.pumpAndSettle();
      expect(find.text(entry.label), findsOneWidget);
    }
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

  testWidgets('sidebar Activity item returns detail routes to the feed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, initialLocation: '/activity/detail'),
    );
    await tester.pump();

    final item = tester.widget<AppSidebarItem>(
      find.byKey(const ValueKey('sidebar_activity_button')),
    );
    expect(item.active, isTrue);
    expect(item.onTap, isNotNull);
    expect(find.text('activity detail'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.text('activity'), findsOneWidget);
    expect(find.text('activity detail'), findsNothing);
  });

  testWidgets('sidebar Settings item opens the settings route', (tester) async {
    await tester.pumpWidget(_sidebarHarness(_syncedSyncState));
    await tester.pump();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('sidebar Settings item returns detail routes to the root', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(_syncedSyncState, initialLocation: '/settings/endpoint'),
    );
    await tester.pump();

    final item = _sidebarItemWithLabel(tester, 'Settings');
    expect(item.active, isTrue);
    expect(item.onTap, isNotNull);
    expect(find.text('settings endpoint'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('settings'), findsOneWidget);
    expect(find.text('settings endpoint'), findsNothing);
  });

  testWidgets('sidebar keeps primary navigation item spacing consistent', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebarHarness(_syncedSyncState));
    await tester.pump();

    final positions = [
      tester.getTopLeft(find.text('Home')).dy,
      tester.getTopLeft(find.text('Swap')).dy,
      tester.getTopLeft(find.text('Vote')).dy,
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

  testWidgets('sidebar disables Swap, Vote, and Activity while importing', (
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

    await tester.tap(find.text('Vote'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('voting'), findsNothing);

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

  testWidgets(
    'sidebar disables Swap and Vote while Ironwood migration is required',
    (tester) async {
      await tester.pumpWidget(
        _sidebarHarness(
          _syncedSyncState,
          ironwoodHomeMigrationCtaState:
              const IronwoodHomeMigrationCtaState.start(
                network: 'main',
                accountUuid: 'account-1',
              ),
          ironwoodPostMigrationState: const IronwoodPostMigrationState.required(
            network: 'main',
            accountUuid: 'account-1',
          ),
        ),
      );
      await tester.pump();

      final swap = _sidebarItemWithLabel(tester, 'Swap');
      final vote = _sidebarItemWithLabel(tester, 'Vote');
      final activity = _sidebarItemWithLabel(tester, 'Activity');
      final settings = _sidebarItemWithLabel(tester, 'Settings');

      expect(swap.onTap, isNull);
      expect(vote.onTap, isNull);
      expect(activity.onTap, isNotNull);
      expect(settings.onTap, isNotNull);
      expect(_opacityForText(tester, 'Swap'), 0.5);
      expect(_opacityForText(tester, 'Vote'), 0.5);

      await tester.tap(find.text('Swap'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('swap'), findsNothing);

      await tester.tap(find.text('Vote'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('voting'), findsNothing);

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('activity'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('settings'), findsOneWidget);
    },
  );

  testWidgets(
    'sidebar restores ordinary actions once Ironwood migration is active',
    (tester) async {
      await tester.pumpWidget(
        _sidebarHarness(
          _syncedSyncState,
          ironwoodHomeMigrationCtaState: IronwoodHomeMigrationCtaState.resume(
            network: 'main',
            accountUuid: 'account-1',
            status: _mixedMigrationStatus,
          ),
          ironwoodPostMigrationState: IronwoodPostMigrationState.inProgress(
            network: 'main',
            accountUuid: 'account-1',
            status: _mixedMigrationStatus,
          ),
          migrationCoordinatorState: IronwoodMigrationCoordinatorState(
            statuses: {'account-1': _mixedMigrationStatus},
          ),
        ),
      );
      await tester.pump();

      expect(_sidebarItemWithLabel(tester, 'Swap').onTap, isNotNull);
      expect(_sidebarItemWithLabel(tester, 'Vote').onTap, isNotNull);
    },
  );

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
    expect(_syncIndicatorColor(tester), AppThemeData.light.colors.text.muted);
    _expectSyncIndicatorGlow(tester, blurRadius: 12);
  });

  testWidgets('sidebar shimmers the syncing label with animations on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sidebarHarness(
        SyncState(isSyncing: true, displayPercentage: 0.34),
        disableAnimations: false,
      ),
    );
    // The syncing animation repeats forever, so advance frames manually rather
    // than using pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sidebar_sync_text')),
        matching: find.byType(ShaderMask),
      ),
      findsOneWidget,
    );
    expect(_syncIndicatorColor(tester), AppThemeData.light.colors.text.muted);
    _expectSyncIndicatorGlow(tester);

    await tester.pumpWidget(const SizedBox());
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
    _expectSyncIndicatorGlow(tester, blurRadius: 12);
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
    _expectSyncIndicatorGlow(tester, blurRadius: 12);
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
  return _syncIndicatorDecoration(tester).color;
}

BoxDecoration _syncIndicatorDecoration(WidgetTester tester) {
  final indicator = find.byKey(const ValueKey('sidebar_sync_indicator'));
  final decoratedBox = tester.widget<DecoratedBox>(
    find.ancestor(of: indicator, matching: find.byType(DecoratedBox)).first,
  );
  return decoratedBox.decoration as BoxDecoration;
}

void _expectSyncIndicatorGlow(WidgetTester tester, {double? blurRadius}) {
  final shadows = _syncIndicatorDecoration(tester).boxShadow;
  expect(shadows, isNotNull);
  expect(shadows, hasLength(1));
  if (blurRadius != null) {
    expect(shadows!.single.blurRadius, blurRadius);
  }
}

BoxDecoration _boxDecorationByKey(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.byKey(key));
  return container.decoration! as BoxDecoration;
}

AppSidebarItem _sidebarItemWithLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<AppSidebarItem>(find.byType(AppSidebarItem))
      .singleWhere((item) => item.label == label);
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

double _opacityForText(WidgetTester tester, String text) {
  final opacity = tester.widget<Opacity>(
    find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
  );
  return opacity.opacity;
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
  bool disableAnimations = true,
  IronwoodHomeMigrationCtaState ironwoodHomeMigrationCtaState =
      const IronwoodHomeMigrationCtaState.hidden(),
  IronwoodPostMigrationState ironwoodPostMigrationState =
      const IronwoodPostMigrationState.unavailable(),
  IronwoodMigrationCoordinatorState migrationCoordinatorState =
      const IronwoodMigrationCoordinatorState(),
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
      GoRoute(
        path: '/swap',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('swap')),
        ),
      ),
      GoRoute(
        path: '/voting',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('voting')),
        ),
      ),
      GoRoute(
        path: '/address-book',
        builder: (_, _) => const Text('address book'),
      ),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('activity')),
        ),
      ),
      GoRoute(
        path: '/activity/detail',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('activity detail')),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('settings')),
        ),
      ),
      GoRoute(
        path: '/settings/endpoint',
        builder: (_, _) => const AppDesktopShell(
          sidebar: AppMainSidebar(),
          pane: AppDesktopPane(child: Text('settings endpoint')),
        ),
      ),
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
      ironwoodHomeMigrationCtaProvider.overrideWith((ref) async {
        return ironwoodHomeMigrationCtaState;
      }),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        ironwoodHomeMigrationCtaState,
      ),
      ironwoodPostMigrationStateProvider.overrideWith((ref) async {
        return ironwoodPostMigrationState;
      }),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        () => _FakeMigrationCoordinator(migrationCoordinatorState),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        // The syncing sidebar's shimmer and glow animate forever. Tests default
        // to reduced motion so pumpAndSettle can settle; animation-specific
        // tests opt back in with disableAnimations: false.
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: AppTheme(data: themeData, child: child!),
      ),
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

const _hardwareAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Keystone Vault',
      order: 0,
      isHardware: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

final _readyMigrationStatus = rust_sync.MigrationStatus(
  phase: 'ready_to_migrate',
  activeRunId: 'run-1',
  targetValuesZatoshi: frb.Uint64List.fromList([
    1000000000,
    200000000,
    50000000,
    20000000,
    10000000,
    2000000,
  ]),
  preparedNoteCount: 6,
  denominationConfirmationCount: 3,
  denominationConfirmationTarget: 3,
  denominationSplitCompletedCount: 1,
  denominationSplitTotalCount: 1,
  pendingTxCount: 0,
  broadcastedTxCount: 0,
  confirmedTxCount: 0,
  totalCount: 6,
  signedChildPcztCount: 6,
  pendingSplitStageCount: 0,
  canAbandon: false,
  signingBatchLimit: 50,
  scheduleMeanDelayBlocks: 144,
  scheduleMaxDelayBlocks: 576,
  maxPreparedNotesPerRun: 64,
  scheduledBroadcasts: const [],
  parts: const [],
);

final _mixedMigrationStatus = rust_sync.MigrationStatus(
  phase: 'migrating',
  activeRunId: 'run-1',
  targetValuesZatoshi: frb.Uint64List.fromList([
    1000000000,
    200000000,
    50000000,
  ]),
  preparedNoteCount: 3,
  denominationConfirmationCount: 3,
  denominationConfirmationTarget: 3,
  denominationSplitCompletedCount: 1,
  denominationSplitTotalCount: 1,
  pendingTxCount: 1,
  broadcastedTxCount: 0,
  confirmedTxCount: 2,
  totalCount: 3,
  signedChildPcztCount: 3,
  pendingSplitStageCount: 0,
  canAbandon: false,
  signingBatchLimit: 50,
  scheduleMeanDelayBlocks: 144,
  scheduleMaxDelayBlocks: 576,
  maxPreparedNotesPerRun: 64,
  scheduledBroadcasts: const [],
  parts: [
    rust_sync.MigrationPartStatus(
      partIndex: 0,
      valueZatoshi: BigInt.from(1000000000),
      state: rust_sync.MigrationPartState.confirming,
      txidHex: 'part-0',
      confirmationCount: 1,
      confirmationTarget: 3,
    ),
    rust_sync.MigrationPartStatus(
      partIndex: 1,
      valueZatoshi: BigInt.from(200000000),
      state: rust_sync.MigrationPartState.completed,
      txidHex: 'part-1',
      confirmationCount: 3,
      confirmationTarget: 3,
    ),
    rust_sync.MigrationPartStatus(
      partIndex: 2,
      valueZatoshi: BigInt.from(50000000),
      state: rust_sync.MigrationPartState.scheduled,
      txidHex: 'part-2',
      scheduledHeight: 600,
      confirmationCount: 0,
      confirmationTarget: 3,
    ),
  ],
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

class _FakeMigrationCoordinator extends IronwoodMigrationCoordinator {
  _FakeMigrationCoordinator(this.initialState);

  final IronwoodMigrationCoordinatorState initialState;

  @override
  IronwoodMigrationCoordinatorState build() => initialState;
}
