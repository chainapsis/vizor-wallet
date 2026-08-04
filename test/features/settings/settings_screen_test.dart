import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_screen.dart';
import 'package:zcash_wallet/src/features/settings/settings_platform.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

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
        'Tor is off. Requests to the Zcash network and in-app services connect directly.',
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
      find.text('New requests wait until the Tor connection is ready.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('network_privacy_toggle')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(calls, isEmpty);
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
}) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
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
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      networkPrivacyProvider.overrideWith(
        () => _FakeNetworkPrivacyNotifier(
          networkPrivacyState,
          networkPrivacyCalls ?? <bool>[],
        ),
      ),
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
