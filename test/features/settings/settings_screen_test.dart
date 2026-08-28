import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_screen.dart';
import 'package:zcash_wallet/src/features/settings/settings_platform.dart';
import 'package:zcash_wallet/src/features/settings/widgets/network_privacy_control.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/windows_update_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  test('uninstall setting is supported only on macOS and Linux', () {
    expect(settingsUninstallSupported(platform: TargetPlatform.macOS), isTrue);
    expect(settingsUninstallSupported(platform: TargetPlatform.linux), isTrue);
    expect(
      settingsUninstallSupported(platform: TargetPlatform.windows),
      isFalse,
    );
    expect(settingsUninstallSupported(platform: TargetPlatform.iOS), isFalse);
    expect(
      settingsUninstallSupported(platform: TargetPlatform.android),
      isFalse,
    );
  });

  testWidgets('settings rows show hover and focus states', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_settingsHarness());
    await tester.pump();

    expect(_rowBackgroundColor(tester, 'Password'), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Password')));
    await tester.pump();

    expect(
      _rowBackgroundColor(tester, 'Password'),
      AppThemeData.light.colors.background.base,
    );

    final detectorFinder = find.ancestor(
      of: find.text('Password'),
      matching: find.byType(FocusableActionDetector),
    );
    expect(detectorFinder, findsOneWidget);

    final detector = tester.widget<FocusableActionDetector>(detectorFinder);
    detector.onShowFocusHighlight?.call(true);
    await tester.pump();

    expect(_hasFocusRing(tester), isTrue);
  });

  testWidgets(
    'hardware account replaces secret passphrase with account details',
    (tester) async {
      const hardwareAccount = AccountState(
        accounts: [
          AccountInfo(
            uuid: 'ledger-account',
            name: 'Ledger account',
            order: 0,
            isHardware: true,
            hardwareSignerKind: HardwareSignerKind.ledger,
          ),
        ],
        activeAccountUuid: 'ledger-account',
        activeAddress: 'u1ledgeraddress',
      );

      await tester.pumpWidget(_settingsHarness(accountState: hardwareAccount));
      await tester.pump();

      expect(find.text('Secret passphrase'), findsNothing);
      expect(find.text('Account details'), findsOneWidget);

      await tester.tap(find.text('Account details'));
      await tester.pumpAndSettle();

      expect(
        find.text('hardware account route ledger-account'),
        findsOneWidget,
      );
    },
  );

  testWidgets('software account preserves secret passphrase navigation', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();

    expect(find.text('Secret passphrase'), findsOneWidget);
    expect(find.text('Account details'), findsNothing);

    await tester.tap(find.text('Secret passphrase'));
    await tester.pumpAndSettle();

    expect(find.text('secret passphrase route'), findsOneWidget);
  });

  testWidgets('uninstall setting is hidden on Windows', (tester) async {
    _overridePlatform(TargetPlatform.windows);

    try {
      await tester.pumpWidget(_settingsHarness());
      await tester.pump();

      expect(find.text('Danger zone'), findsNothing);
      expect(find.text('Uninstall Vizor'), findsNothing);
    } finally {
      _resetPlatformOverride();
    }
  });

  testWidgets('Settings update download uses the Tor privacy choice', (
    tester,
  ) async {
    _overridePlatform(TargetPlatform.windows);
    final downloads = <String>[];
    await tester.binding.setSurfaceSize(const Size(1512, 1100));

    try {
      await tester.pumpWidget(
        _settingsHarness(
          networkPrivacyState: const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connected,
          ),
          extraOverrides: [
            windowsUpdateProvider.overrideWith(
              () => _RecordingWindowsUpdateNotifier(downloads),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Updates'));
      await tester.pump();
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Download update'));
      await tester.pumpAndSettle();

      expect(find.text('Use Tor for this update?'), findsOneWidget);
      expect(downloads, isEmpty);

      await tester.tap(find.widgetWithText(AppButton, 'Continue with Tor'));
      await tester.pumpAndSettle();

      expect(downloads, ['download']);
    } finally {
      await tester.binding.setSurfaceSize(null);
      _resetPlatformOverride();
    }
  });

  testWidgets('Settings preserves the underlying Windows update error', (
    tester,
  ) async {
    _overridePlatform(TargetPlatform.windows);
    await tester.binding.setSurfaceSize(const Size(1512, 1100));

    try {
      await tester.pumpWidget(
        _settingsHarness(
          extraOverrides: [
            windowsUpdateProvider.overrideWith(
              () => _FailedWindowsUpdateNotifier(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Updates'));
      await tester.pump();
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();

      expect(find.text('Signed feed verification failed.'), findsOneWidget);
      expect(
        find.text("Couldn't complete the update. Try again."),
        findsNothing,
      );
    } finally {
      await tester.binding.setSurfaceSize(null);
      _resetPlatformOverride();
    }
  });

  testWidgets('settings hides legal links while keeping About Vizor', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHarness());
    await tester.pump();

    expect(find.text('About Vizor'), findsOneWidget);
    expect(find.text('Privacy policy'), findsNothing);
    expect(find.text('Terms of usage'), findsNothing);
    expect(find.text('Use Tor'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(
      find.text(
        'Tor is off. Requests to the Zcash network, in-app services, and software updates connect directly.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings Tor control explains transitions and toggles once', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pump();

    expect(find.text('Connecting…'), findsOneWidget);
    expect(
      find.text(
        'New requests wait until the Tor connection is ready. Turn Tor off to '
        'stop connecting and use a direct connection.',
      ),
      findsOneWidget,
    );

    final statusIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('network_privacy_status_icon')),
    );
    expect(statusIcon.name, AppIcons.loader);
    // Not dimmed: the control is the way out of the wait, so it has to look
    // like something the user may act on.
    expect(_toggleTrackOpacity(tester), 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('network_privacy_toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('network_privacy_toggle')));
    await tester.pump();
    // The bootstrap runs to a three-minute deadline with every request failing
    // closed, and relaunching starts the same wait, so switching to direct has
    // to stay reachable for the whole of it.
    expect(calls, [false]);
  });

  test('the toggle offers an escape from a pending Tor connection', () {
    // Every state maps to exactly one action, and the connecting-to-Tor state
    // maps to an escape rather than to nothing.
    NetworkPrivacyToggleAction actionFor({
      required bool torEnabled,
      required NetworkPrivacyConnectionStatus status,
      bool? targetTorEnabled,
    }) => networkPrivacyToggleAction(
      NetworkPrivacyState(
        torEnabled: torEnabled,
        status: status,
        targetTorEnabled: targetTorEnabled,
      ),
    );

    expect(
      actionFor(torEnabled: false, status: NetworkPrivacyConnectionStatus.off),
      NetworkPrivacyToggleAction.enable,
    );
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connected,
      ),
      NetworkPrivacyToggleAction.disable,
    );
    // A startup activation publishes no explicit target, so the effective one
    // is the route already shown — which is the state a user relaunching into a
    // blocked network lands in.
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
      ),
      NetworkPrivacyToggleAction.cancelPendingTor,
    );
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
        targetTorEnabled: true,
      ),
      NetworkPrivacyToggleAction.cancelPendingTor,
    );
    expect(
      actionFor(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
        targetTorEnabled: false,
      ),
      NetworkPrivacyToggleAction.none,
    );
  });

  test('cancelling a pending Tor connection asks for the direct route', () {
    expect(
      NetworkPrivacyToggleAction.cancelPendingTor.requestedTorEnabled,
      isFalse,
    );
    expect(NetworkPrivacyToggleAction.enable.requestedTorEnabled, isTrue);
    expect(NetworkPrivacyToggleAction.disable.requestedTorEnabled, isFalse);
    // Leaving a wait is not a second transition, and does not announce itself
    // as one.
    expect(
      NetworkPrivacyToggleAction.cancelPendingTor.semanticsLabel,
      'Stop connecting to Tor',
    );
    expect(NetworkPrivacyToggleAction.disable.semanticsLabel, 'Use Tor');
    expect(NetworkPrivacyToggleAction.none.isInteractive, isFalse);
  });

  testWidgets('a switch to direct cannot be driven back into Tor', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
          targetTorEnabled: false,
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pump();

    // Nothing to escape from here: the route is already on its way to direct.
    expect(_toggleTrackOpacity(tester), lessThan(1));
    await tester.ensureVisible(
      find.byKey(const ValueKey('network_privacy_toggle')),
    );
    await tester.tap(
      find.byKey(const ValueKey('network_privacy_toggle')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('connected Tor state describes Vizor and external app routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connected,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Connected'), findsOneWidget);
    expect(
      find.text(
        'Vizor’s network requests go through Tor. Links opened in other apps '
        'use those apps’ network settings.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('network_privacy_status_icon')),
      findsNothing,
    );
    expect(_toggleTrackOpacity(tester), 1);

    final torIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('network_privacy_tor_icon')),
    );
    expect(torIcon.name, AppIcons.tor);
    expect(torIcon.size, 20);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('network_privacy_toggle_track')),
      ),
      const Size(44, 20),
    );

    final status = tester.widget<Text>(
      find.byKey(const ValueKey('network_privacy_status_connected_true')),
    );
    expect(status.style?.fontSize, 14);
    expect(status.style?.fontWeight, FontWeight.w400);
    expect(status.style?.height, 16 / 14);
    expect(status.style?.color, AppThemeData.light.colors.text.brandCrimson);

    final description = tester.widget<Text>(
      find.byKey(const ValueKey('network_privacy_description_connected_true')),
    );
    expect(description.style?.fontSize, 14);
    expect(description.style?.fontWeight, FontWeight.w400);
    expect(description.style?.height, 21 / 14);
    expect(description.style?.color, AppThemeData.light.colors.text.accent);
  });

  testWidgets('Linux Tor copy assigns external traffic to the other app', (
    tester,
  ) async {
    _overridePlatform(TargetPlatform.linux);
    try {
      await tester.pumpWidget(
        _settingsHarness(
          networkPrivacyState: const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connected,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Vizor’s network requests go through Tor. Links opened in other apps '
          'use those apps’ network settings.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('software updates use Tor'), findsNothing);
    } finally {
      _resetPlatformOverride();
    }
  });

  testWidgets('Tor stays effective while switching to direct', (tester) async {
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
          targetTorEnabled: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Switching to direct…'), findsOneWidget);
    expect(
      find.text(
        'Vizor is switching network requests and software updates to a direct connection.',
      ),
      findsOneWidget,
    );

    final statusIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('network_privacy_status_icon')),
    );
    expect(statusIcon.name, AppIcons.loader);
    expect(_toggleTrackOpacity(tester), lessThan(1));
  });

  testWidgets('Tor update-route failure remains visible after the toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connected,
          softwareUpdatesAvailable: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Vizor’s network requests go through Tor, but software updates are '
        'unavailable.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry updates'), findsOneWidget);
  });

  testWidgets('failed Tor state offers retry and direct connection', (
    tester,
  ) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      _settingsHarness(
        networkPrivacyState: const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
          error: 'bootstrap failed',
        ),
        networkPrivacyCalls: calls,
      ),
    );
    await tester.pump();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(
      find.text('Direct requests remain blocked. Try again or turn off Tor.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(calls, [true]);

    await tester.ensureVisible(
      find.byKey(const ValueKey('network_privacy_toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('network_privacy_toggle')));
    await tester.pump();
    expect(calls, [true, false]);
  });

  testWidgets('uninstall setting is shown on macOS and Linux', (tester) async {
    try {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
        _overridePlatform(platform);

        await tester.pumpWidget(_settingsHarness());
        await tester.pump();

        expect(find.text('Danger zone'), findsOneWidget);
        expect(find.text('Uninstall Vizor'), findsOneWidget);
      }
    } finally {
      _resetPlatformOverride();
    }
  });
}

void _overridePlatform(TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
}

void _resetPlatformOverride() {
  debugDefaultTargetPlatformOverride = null;
}

Widget _settingsHarness({
  NetworkPrivacyState networkPrivacyState = const NetworkPrivacyState.off(),
  List<bool>? networkPrivacyCalls,
  List<Override> extraOverrides = const [],
  AccountState? accountState,
}) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/settings/secret-passphrase',
        builder: (_, _) => const Text('secret passphrase route'),
      ),
      GoRoute(
        path: '/settings/hardware-account',
        builder: (_, state) => Text('hardware account route ${state.extra}'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _settingsBootstrap(accountState ?? _bootstrap.initialAccountState),
      ),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      networkPrivacyProvider.overrideWith(
        () => _FakeNetworkPrivacyNotifier(
          networkPrivacyState,
          networkPrivacyCalls ?? <bool>[],
        ),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _FakeNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _FakeNetworkPrivacyNotifier(this.initialState, this.calls);

  final NetworkPrivacyState initialState;
  final List<bool> calls;

  @override
  NetworkPrivacyState build() => initialState;

  @override
  Future<void> setTorEnabled(bool enabled) async {
    calls.add(enabled);
  }
}

class _RecordingWindowsUpdateNotifier extends WindowsUpdateNotifier {
  _RecordingWindowsUpdateNotifier(this.downloads);

  final List<String> downloads;

  @override
  WindowsUpdateState build() => const WindowsUpdateState(
    supported: true,
    status: WindowsUpdateStatus.available,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: 0,
    pendingRestart: false,
    torProxyReady: true,
    message: '',
  );

  @override
  Future<WindowsUpdateDownloadResult> downloadUpdate() async {
    downloads.add('download');
    return const WindowsUpdateDownloadResult.started();
  }
}

class _FailedWindowsUpdateNotifier extends WindowsUpdateNotifier {
  @override
  WindowsUpdateState build() => const WindowsUpdateState(
    supported: true,
    status: WindowsUpdateStatus.failed,
    currentVersion: '1.0.0',
    appId: 'Vizor',
    repoUrl: 'https://updates.example.invalid/vizor',
    availableVersion: '9.9.9',
    downloadProgress: 0,
    pendingRestart: false,
    torProxyReady: true,
    message: 'Signed feed verification failed.',
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1settingsscreenaddress',
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

AppBootstrapState _settingsBootstrap(AccountState accountState) =>
    AppBootstrapState(
      initialLocation: _bootstrap.initialLocation,
      initialAccountState: accountState,
      initialSyncSnapshot: _bootstrap.initialSyncSnapshot,
      network: _bootstrap.network,
      rpcEndpointConfig: _bootstrap.rpcEndpointConfig,
      themeMode: _bootstrap.themeMode,
      privacyModeEnabled: _bootstrap.privacyModeEnabled,
      isPasswordConfigured: _bootstrap.isPasswordConfigured,
      isUnlocked: _bootstrap.isUnlocked,
      passwordRotationRecoveryFailed: _bootstrap.passwordRotationRecoveryFailed,
    );

double _toggleTrackOpacity(WidgetTester tester) {
  final opacity = tester.widget<Opacity>(
    find
        .ancestor(
          of: find.byKey(const ValueKey('network_privacy_toggle_track')),
          matching: find.byType(Opacity),
        )
        .first,
  );
  return opacity.opacity;
}

Color? _rowBackgroundColor(WidgetTester tester, String label) {
  final container = tester.widget<Container>(_rowContainerFinder(label));
  return (container.decoration as BoxDecoration?)?.color;
}

Finder _rowContainerFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.padding ==
              const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
    ),
  );
}

bool _hasFocusRing(WidgetTester tester) {
  final focusRing = find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    final border = decoration.border;
    if (border is! Border) return false;
    return border.top.color == AppThemeData.light.colors.state.focusRing &&
        border.top.width == 2;
  });
  return focusRing.evaluate().isNotEmpty;
}
