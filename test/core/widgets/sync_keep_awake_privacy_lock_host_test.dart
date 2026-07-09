@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/sync_keep_awake_interaction_listener.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/sync_keep_awake_privacy_lock_host.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('shows the privacy screen after keep-awake idle timeout', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        syncNotifier: FakeSyncNotifier(
          _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('Unlock Vizor'), findsOneWidget);
  });

  testWidgets('does not show the privacy screen for near-tip catch-up', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        syncNotifier: FakeSyncNotifier(
          _sync(
            scannedHeight: 100,
            chainTipHeight: 102,
            lastSyncStartedAt: DateTime(2026, 7, 9, 12),
          ),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);
  });

  testWidgets('recent interaction delays the privacy screen', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        syncNotifier: FakeSyncNotifier(
          _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byKey(const ValueKey('home_surface')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);
  });

  testWidgets('unlock button clears the virtual privacy lock', (tester) async {
    _setMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);

    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isFalse);
  });

  testWidgets('keeps the privacy screen and shows done after sync completes', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        displayPercentage: 1,
        scannedHeight: 200,
        chainTipHeight: 200,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await tester.pump();

    expect(container.read(syncKeepAwakeActiveProvider), isFalse);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );
    expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);
    expect(find.text('Synced'), findsOneWidget);
    expect(
      find.text('Synced successfully.\nYou can unlock Vizor.'),
      findsOneWidget,
    );
    expect(find.text('Unlock Vizor'), findsOneWidget);
  });

  testWidgets('keeps the privacy screen across near-tip follow-up syncs', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        displayPercentage: 1,
        scannedHeight: 200,
        chainTipHeight: 200,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await tester.pump();

    expect(find.text('Synced'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        percentage: 0,
        displayPercentage: 0,
        scannedHeight: 200,
        chainTipHeight: 202,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12, 2),
      ),
    );
    await tester.pump();

    expect(container.read(syncKeepAwakeActiveProvider), isFalse);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );
    expect(find.text('Synced'), findsNothing);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        displayPercentage: 1,
        scannedHeight: 202,
        chainTipHeight: 202,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12, 2),
      ),
    );
    await tester.pump();

    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Unlock Vizor'), findsOneWidget);
  });

  testWidgets(
    'keeps the privacy screen with paused copy when sync stops early',
    (tester) async {
      _setMobileViewport(tester);
      final syncNotifier = FakeSyncNotifier(
        _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          syncProvider.overrideWith(() => syncNotifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _themedApp()),
      );
      await _settleInitialSync(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      syncNotifier.emit(
        _sync(
          isSyncing: false,
          percentage: 0.5,
          displayPercentage: 0.5,
          scannedHeight: 150,
          chainTipHeight: 200,
          lastSyncStartedAt: DateTime(2026, 7, 9, 12),
        ),
      );
      await tester.pump();

      expect(container.read(syncKeepAwakeActiveProvider), isFalse);
      expect(
        container.read(syncKeepAwakePrivacyLockModeProvider),
        SyncKeepAwakePrivacyLockMode.interrupted,
      );
      expect(find.text('Synced'), findsNothing);
      expect(
        find.text('Synced successfully.\nYou can unlock Vizor.'),
        findsNothing,
      );
      expect(find.text('Sync paused'), findsOneWidget);
      expect(find.text('Unlock Vizor to continue.'), findsOneWidget);
      expect(find.text('Unlock Vizor'), findsOneWidget);
    },
  );

  testWidgets('keeps the Figma vertical position on the reference viewport', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);

    final logoRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_logo')),
    );

    expect(logoRect.top, closeTo(110, 0.1));
  });

  testWidgets('keeps the done state Figma vertical positions', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _privacyScreenApp(mode: SyncKeepAwakePrivacyLockMode.done),
    );
    await _settleInitialSync(tester);

    final checkRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_done_check')),
    );
    final titleRect = tester.getRect(find.text('Synced'));
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );

    expect(checkRect.top, closeTo(306, 0.1));
    expect(titleRect.top, closeTo(406, 0.1));
    expect(buttonRect.top, closeTo(653, 0.1));
  });

  testWidgets('uses the status layout for the interrupted state', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _privacyScreenApp(mode: SyncKeepAwakePrivacyLockMode.interrupted),
    );
    await _settleInitialSync(tester);

    final warningRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_interrupted_warning')),
    );
    final titleRect = tester.getRect(find.text('Sync paused'));
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );

    expect(warningRect.top, closeTo(306, 0.1));
    expect(titleRect.top, closeTo(406, 0.1));
    expect(buttonRect.top, closeTo(653, 0.1));
  });

  testWidgets('renders the current display sync percentage', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('63%'), findsOneWidget);
  });

  testWidgets('animates display sync percentage changes', (tester) async {
    _setMobileViewport(tester);
    final syncNotifier = FakeSyncNotifier(
      _sync(
        percentage: 0.05,
        displayPercentage: 0.05,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncProvider.overrideWith(() => syncNotifier)],
        child: MaterialApp(
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
          home: const SyncKeepAwakePrivacyLockScreen(),
        ),
      ),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('5%'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        percentage: 0.10,
        displayPercentage: 0.10,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await tester.pump();

    expect(find.text('10%'), findsNothing);

    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('10%'), findsNothing);

    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('10%'), findsOneWidget);
  });

  testWidgets('centers the privacy stack on a shorter phone viewport', (
    tester,
  ) async {
    _setMobileViewport(tester, size: const Size(375, 667));
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);

    final logoRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_logo')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );
    final bottomGap =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        buttonRect.bottom;

    expect(logoRect.top, greaterThanOrEqualTo(0));
    expect(buttonRect.bottom, lessThanOrEqualTo(667));
    expect((logoRect.top - bottomGap).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('keeps logo and unlock button visible on compact short phones', (
    tester,
  ) async {
    _setMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);

    final logoRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_logo')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );

    expect(logoRect.top, greaterThanOrEqualTo(0));
    expect(buttonRect.bottom, lessThanOrEqualTo(568));
  });
}

void _setMobileViewport(
  WidgetTester tester, {
  Size size = const Size(393, 852),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app({required FakeSyncNotifier syncNotifier}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(() => syncNotifier),
    ],
    child: _themedApp(),
  );
}

Widget _privacyScreenApp({
  SyncKeepAwakePrivacyLockMode mode = SyncKeepAwakePrivacyLockMode.syncing,
}) {
  return ProviderScope(
    overrides: [
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          _sync(percentage: 0.63, lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: SyncKeepAwakePrivacyLockScreen(mode: mode),
    ),
  );
}

Widget _themedApp() {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: SyncKeepAwakePrivacyLockHost(
      idleTimeout: const Duration(milliseconds: 50),
      child: SyncKeepAwakeInteractionListener(
        child: Scaffold(
          body: GestureDetector(
            key: const ValueKey('home_surface'),
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const Center(child: Text('Home')),
          ),
        ),
      ),
    ),
  );
}

Future<void> _settleInitialSync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.dark,
    privacyModeEnabled: false,
    syncKeepAwakeEnabled: true,
    syncKeepAwakePromptSeen: true,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

SyncState _sync({
  bool isSyncing = true,
  bool isBackgroundMode = false,
  double percentage = 0.25,
  double? displayPercentage,
  int scannedHeight = 100,
  int chainTipHeight = 200,
  DateTime? lastSyncStartedAt,
}) {
  return SyncState(
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    displayPercentage: displayPercentage,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    lastSyncStartedAt: lastSyncStartedAt,
  );
}
