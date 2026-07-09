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

Widget _privacyScreenApp() {
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
      home: const SyncKeepAwakePrivacyLockScreen(),
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
  int scannedHeight = 100,
  int chainTipHeight = 200,
  DateTime? lastSyncStartedAt,
}) {
  return SyncState(
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    lastSyncStartedAt: lastSyncStartedAt,
  );
}
