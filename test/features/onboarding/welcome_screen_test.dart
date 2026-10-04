import 'dart:async';

import 'dart:ui' show Size, Offset;

import 'package:flutter/material.dart' show MaterialApp, TextButton;
import 'package:flutter/services.dart'
    show FontLoader, rootBundle, LogicalKeyboardKey;
import 'package:flutter/widgets.dart'
    show BorderRadius, BoxDecoration, DecoratedBox, Text, ValueKey, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/enhance_pir_preference_store.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';

void main() {
  final api = _PrivacyApi();
  setUpAll(() async {
    await _loadAppFonts();
    RustLib.initMock(api: api);
  });
  tearDownAll(RustLib.dispose);
  setUp(() => api.enabled.clear());

  testWidgets('hides Back on first wallet creation entry', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    expect(find.text('Back'), findsNothing);
    expect(find.text('Or'), findsOneWidget);
  });

  testWidgets('shows Ledger on first wallet creation entry', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    expect(
      find.byKey(const ValueKey('welcome_connect_ledger_button')),
      findsOneWidget,
    );
  });

  testWidgets('shows endpoint settings on first wallet creation entry', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    expect(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
      findsOneWidget,
    );
  });

  testWidgets('keeps endpoint settings visible over the light hero', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    final button = find.byKey(
      const ValueKey('welcome_endpoint_settings_button'),
    );
    expect(tester.getSize(button), const Size(32, 32));

    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(of: button, matching: find.byType(DecoratedBox)),
    );
    final icon = tester.widget<AppIcon>(
      find.descendant(of: button, matching: find.byType(AppIcon)),
    );

    expect(
      (decoratedBox.decoration as BoxDecoration).color,
      AppBackgroundColors.light.neutralScrim,
    );
    expect(icon.color, AppIconColors.light.inverse);
  });

  testWidgets('hides legal links while preserving footer space', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    expect(find.text('Terms'), findsNothing);
    expect(find.text('Privacy'), findsNothing);

    final footerSpace = find.byKey(
      const ValueKey('welcome_legal_footer_space'),
    );
    expect(footerSpace, findsOneWidget);
    expect(tester.getSize(footerSpace), const Size(154, 36));
  });

  testWidgets('opens endpoint settings modal from welcome', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    await tester.tap(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('welcome_endpoint_settings_modal')),
      findsOneWidget,
    );
    expect(find.text('Network settings'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Use Tor'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('Custom endpoint'), findsOneWidget);
    expect(find.text('Update endpoint'), findsOneWidget);

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('network_privacy_surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(AppRadii.large));
    expect(decoration.boxShadow, hasLength(4));
    expect(
      tester.getSize(
        find.byKey(const ValueKey('network_privacy_toggle_track')),
      ),
      const Size(44, 20),
    );
  });

  testWidgets('uses the darker modal layer in dark mode', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen(theme: AppThemeData.dark));

    await tester.tap(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
    );
    await tester.pump();

    final panel = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('network_settings_panel_surface')),
    );
    final panelDecoration = panel.decoration as BoxDecoration;
    expect(panelDecoration.color, AppThemeData.dark.colors.background.window);

    final privacySurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('network_privacy_surface')),
    );
    final privacyDecoration = privacySurface.decoration as BoxDecoration;
    expect(privacyDecoration.color, AppThemeData.dark.colors.background.ground);
    expect(privacyDecoration.border, isNull);
  });

  testWidgets(
    'welcome network settings can enable Tor before wallet creation',
    (tester) async {
      final calls = <bool>[];
      await _setDesktopViewport(tester);
      await tester.pumpWidget(_welcomeScreen(networkPrivacyCalls: calls));

      await tester.tap(
        find.byKey(const ValueKey('welcome_endpoint_settings_button')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('network_privacy_toggle')));
      await tester.pump();

      expect(calls, [true]);
    },
  );

  testWidgets('private queries commit before welcome can be dismissed', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final store = _PrivacyStore()..pending = Completer<void>();
    final torCalls = <bool>[];
    await tester.pumpWidget(
      _welcomeScreen(privacyStore: store, networkPrivacyCalls: torCalls),
    );
    await tester.tap(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
    );
    await tester.pump();
    final toggle = find.byKey(const ValueKey('settings_enhance_pir_toggle'));
    expect(find.text('Private queries'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('Changing setting…'), findsOneWidget);
    expect(find.bySemanticsLabel('Close endpoint settings'), findsNothing);
    expect(api.enabled, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('welcome_endpoint_settings_modal')),
      findsOneWidget,
    );
    store.pending!.complete();
    await tester.pumpAndSettle();
    expect(store.value, isTrue);
    expect(api.enabled, [true]);
    expect(torCalls, isEmpty);
    expect(find.text('On'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('welcome_endpoint_settings_modal')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
    );
    await tester.pump();
    expect(find.text('On'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('network_privacy_toggle')));
    await tester.pump();
    expect(torCalls, [true]);
    expect(api.enabled, [true]);
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('failed private preference stays off and can be retried', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final store = _PrivacyStore()..fail = true;
    await tester.pumpWidget(_welcomeScreen(privacyStore: store));
    await tester.tap(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings_enhance_pir_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Setting unchanged. Try again.'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(api.enabled, isEmpty);
    store.fail = false;
    await tester.tap(find.byKey(const ValueKey('settings_enhance_pir_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('On'), findsOneWidget);
    expect(api.enabled, [true]);
  });

  testWidgets('private queries are hidden on an unsupported network', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen(privacyAvailable: false));
    await tester.tap(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
    );
    await tester.pump();
    expect(find.text('Private queries'), findsNothing);
    expect(find.text('Use Tor'), findsOneWidget);
  });

  testWidgets('network panel scrolls in a short desktop window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_welcomeScreen());
    await tester.tap(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final warning = find.textContaining(
      'If the endpoint is configured wrong',
      findRichText: true,
    );
    await tester.ensureVisible(warning);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.text('Update endpoint')).dy,
      lessThan(520),
    );
  });

  testWidgets('shows Back when adding an account to an existing wallet', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen(showBackButton: true));

    expect(find.text('Back'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('welcome_endpoint_settings_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('welcome_connect_ledger_button')),
      findsOneWidget,
    );
  });

  testWidgets('Back returns to the pushed accounts route', (tester) async {
    await _setDesktopViewport(tester);
    final router = GoRouter(
      initialLocation: '/accounts',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('Home')),
        GoRoute(
          path: '/accounts',
          builder: (context, _) => TextButton(
            onPressed: () => context.push('/add-account'),
            child: const Text('Open add account'),
          ),
        ),
        GoRoute(
          path: '/add-account',
          builder: (_, _) => const WelcomeScreen(showBackButton: true),
        ),
      ],
    );

    await tester.pumpWidget(_welcomeRouter(router));
    await tester.tap(find.text('Open add account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Open add account'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });
}

Future<void> _loadAppFonts() async {
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));

  await Future.wait([youngSerif.load(), geist.load()]);
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _welcomeScreen({
  bool showBackButton = false,
  List<bool>? networkPrivacyCalls,
  AppThemeData theme = AppThemeData.light,
  _PrivacyStore? privacyStore,
  bool privacyAvailable = true,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      enhancePirAvailableProvider.overrideWithValue(privacyAvailable),
      enhancePirPreferenceStoreProvider.overrideWithValue(
        privacyStore ?? _PrivacyStore(),
      ),
      enhancePirBackgroundSinkProvider.overrideWithValue((_) async {}),
      syncProvider.overrideWith(_OnboardingSync.new),
      networkPrivacyProvider.overrideWith(
        () => _FakeNetworkPrivacyNotifier(networkPrivacyCalls ?? <bool>[]),
      ),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: theme,
        child: WelcomeScreen(showBackButton: showBackButton),
      ),
    ),
  );
}

class _FakeNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _FakeNetworkPrivacyNotifier(this.calls);

  final List<bool> calls;

  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();

  @override
  Future<void> setTorEnabled(bool enabled) async {
    calls.add(enabled);
  }
}

Widget _welcomeRouter(GoRouter router) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _PrivacyApi extends RustLibApi {
  final enabled = <bool>[];
  @override
  void crateApiSyncSetEnhancePirEnabled({required bool enabled}) =>
      this.enabled.add(enabled);
  @override
  bool crateApiSyncIsSyncRunning() => false;
  @override
  bool crateApiSyncIsMempoolObserverRunning() => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PrivacyStore implements EnhancePirPreferenceStore {
  bool? value;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<bool?> readEnabled() async => value;
  @override
  Future<void> writeEnabled(bool enabled) async {
    if (pending != null) await pending!.future;
    if (fail) throw StateError('storage unavailable');
    value = enabled;
  }
}

class _OnboardingSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
  @override
  void startSync({int? latestTipHeight}) => fail('No wallet exists to sync');
}
