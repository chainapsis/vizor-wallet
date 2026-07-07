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
import 'package:zcash_wallet/src/providers/fiat_currency_provider.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_screen.dart';
import 'package:zcash_wallet/src/features/settings/settings_platform.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/in_memory_fiat_currency_notifier.dart';

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

  testWidgets('currency row opens the picker and updates the value', (
    tester,
  ) async {
    _overridePlatform(TargetPlatform.macOS);
    try {
      await tester.pumpWidget(_settingsHarness());
      await tester.pump();

      await tester.ensureVisible(find.text('Currency'));
      await tester.pump();
      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);

      await tester.tap(find.text('Currency'));
      await tester.pump();

      final krwOption = find.byKey(
        const ValueKey('settings_currency_option_krw'),
      );
      await tester.ensureVisible(krwOption);
      await tester.pump();
      await tester.tap(krwOption);
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('account_modal_action_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't update currency."), findsNothing);
      // Modal closed, row now shows the selection.
      expect(
        find.byKey(const ValueKey('settings_currency_option_krw')),
        findsNothing,
      );
      expect(find.text('KRW'), findsOneWidget);
      expect(find.text('USD'), findsNothing);
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

Widget _settingsHarness() {
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
      // Secure-storage platform channels never complete in widget tests, so
      // the currency preference runs in-memory here.
      fiatCurrencyProvider.overrideWith(InMemoryFiatCurrencyNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
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
