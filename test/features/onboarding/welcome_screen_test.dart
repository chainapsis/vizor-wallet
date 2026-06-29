import 'dart:ui' show Size;

import 'package:flutter/material.dart' show MaterialApp, TextButton;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart' show Text, ValueKey, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';

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
    expect(find.text('Endpoint'), findsOneWidget);
    expect(find.text('Custom Endpoint'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
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
  });

  testWidgets('shows pending multisig summary without full session state', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _welcomeScreen(
        overrides: [
          multisigPendingSessionSummariesProvider.overrideWith((ref) async {
            return const [
              MultisigPendingSessionSummary(
                storageId: 'session-1:participant-1',
                sessionId: 'session-1',
                participantId: 'participant-1',
                role: MultisigPendingRole.creator,
                label: 'Family vault',
                state: 'collecting',
                updatedLocallyAt: 20,
              ),
            ];
          }),
          multisigAccountMaterialsProvider.overrideWith((ref) async {
            return const <MultisigAccountMaterial>[];
          }),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Continue multisig setup'), findsOneWidget);
    expect(find.text('session-1'), findsOneWidget);
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
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ...overrides,
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: WelcomeScreen(showBackButton: showBackButton),
      ),
    ),
  );
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
