import 'dart:ui' show Size;

import 'package:flutter/material.dart' show MaterialApp, TextButton;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart'
    show BorderRadius, BoxDecoration, DecoratedBox, Text, ValueKey, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('hides Back on first wallet creation entry', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    expect(find.text('Back'), findsNothing);
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

  testWidgets('hides derive option when wallet has no accounts', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_welcomeScreen());

    expect(
      find.byKey(const ValueKey('welcome_derive_account_button')),
      findsNothing,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('welcome_create_wallet_button')),
          )
          .variant,
      AppButtonVariant.primary,
    );
  });

  testWidgets('shows derive option when a software account exists', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _welcomeScreen(accountState: _softwareAccountState),
    );

    expect(
      find.byKey(const ValueKey('welcome_derive_account_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('welcome_create_wallet_button')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('welcome_create_wallet_button')),
          )
          .variant,
      AppButtonVariant.secondary,
    );
  });

  testWidgets('derive option routes to customise with derive args', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    CustomiseAccountArgs? routedArgs;
    final router = GoRouter(
      initialLocation: '/add-account',
      routes: [
        GoRoute(
          path: '/add-account',
          builder: (_, _) => const WelcomeScreen(showBackButton: true),
        ),
        GoRoute(
          path: '/onboarding/customise-account',
          builder: (_, state) {
            routedArgs = state.extra! as CustomiseAccountArgs;
            return const Text('Customise destination');
          },
        ),
      ],
    );

    await tester.pumpWidget(
      _welcomeRouter(router, accountState: _softwareAccountState),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('welcome_derive_account_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customise destination'), findsOneWidget);
    expect(routedArgs?.isDeriveFlow, isTrue);
    expect(routedArgs?.deriveFromAccountUuid, 'software-account');
    expect(routedArgs?.mnemonic, isEmpty);
  });

  testWidgets('hides derive option for a hardware-only wallet', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _welcomeScreen(
        accountState: const AccountState(
          accounts: [
            AccountInfo(
              uuid: 'keystone-account',
              name: 'Keystone',
              order: 0,
              isHardware: true,
            ),
          ],
          activeAccountUuid: 'keystone-account',
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('welcome_derive_account_button')),
      findsNothing,
    );
  });

  testWidgets(
    'derives from the first software account when hardware is active',
    (tester) async {
      await _setDesktopViewport(tester);
      CustomiseAccountArgs? routedArgs;
      final router = GoRouter(
        initialLocation: '/add-account',
        routes: [
          GoRoute(
            path: '/add-account',
            builder: (_, _) => const WelcomeScreen(showBackButton: true),
          ),
          GoRoute(
            path: '/onboarding/customise-account',
            builder: (_, state) {
              routedArgs = state.extra! as CustomiseAccountArgs;
              return const Text('Customise destination');
            },
          ),
        ],
      );
      await tester.pumpWidget(
        _welcomeRouter(
          router,
          accountState: const AccountState(
            accounts: [
              AccountInfo(uuid: 'software', name: 'Software', order: 0),
              AccountInfo(
                uuid: 'keystone',
                name: 'Keystone',
                order: 1,
                isHardware: true,
              ),
            ],
            activeAccountUuid: 'keystone',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('welcome_derive_account_button')),
      );
      await tester.pumpAndSettle();

      expect(routedArgs?.deriveFromAccountUuid, 'software');
      expect(routedArgs?.mnemonic, isEmpty);
    },
  );

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
  AccountState accountState = const AccountState(),
  List<bool>? networkPrivacyCalls,
  AppThemeData theme = AppThemeData.light,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(() => _FakeAccountNotifier(accountState)),
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

Widget _welcomeRouter(
  GoRouter router, {
  AccountState accountState = const AccountState(),
  List<bool>? networkPrivacyCalls,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(() => _FakeAccountNotifier(accountState)),
      networkPrivacyProvider.overrideWith(
        () => _FakeNetworkPrivacyNotifier(networkPrivacyCalls ?? <bool>[]),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.fixedState);

  final AccountState fixedState;

  @override
  AccountState build() => fixedState;
}

const _softwareAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'software-account',
      name: 'Primary',
      order: 0,
      isSeedAnchor: true,
    ),
  ],
  activeAccountUuid: 'software-account',
);
