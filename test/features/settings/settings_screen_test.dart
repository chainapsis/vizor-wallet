import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
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

  testWidgets('settings opens voting for software accounts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_settingsHarness());
    await tester.tap(find.text('Coinholder Polling'));
    await tester.pumpAndSettle();

    expect(find.text('voting route'), findsOneWidget);
  });

  testWidgets('settings opens voting for hardware accounts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_settingsHarness(isHardware: true));
    await tester.pump();

    expect(find.text('Hardware accounts coming soon'), findsNothing);
    await tester.tap(find.text('Coinholder Polling'));
    await tester.pumpAndSettle();
    expect(find.text('voting route'), findsOneWidget);
  });
}

Widget _settingsHarness({bool isHardware = false}) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(isHardware: isHardware),
      ),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AppBootstrapState _bootstrap({bool isHardware = false}) => AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        isHardware: isHardware,
      ),
    ],
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
