@Tags(['mobile'])
library;

import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_hardware_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_method_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_wallet_link_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_backdrop.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/welcome_button_tokens.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

Widget _app({
  bool existingWallet = false,
  AppSecurityNotifier? security,
  String initialLocation = '/welcome',
  AppThemeData theme = AppThemeData.light,
  String network = 'main',
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ...mobileOnboardingRoutes(),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: initialLocation,
          initialAccountState: AppBootstrapState.empty.initialAccountState,
          initialSyncSnapshot: AppSyncSnapshot.empty,
          network: network,
          rpcEndpointConfig: defaultRpcEndpointConfig(network),
          themeMode: ThemeMode.system,
          privacyModeEnabled: false,
          isPasswordConfigured: existingWallet,
          isUnlocked: existingWallet,
          passwordRotationRecoveryFailed: false,
        ),
      ),
      if (security != null) appSecurityProvider.overrideWith(() => security),
      ledgerTargetPlatformProvider.overrideWithValue(platform),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: AppTheme(data: theme, child: child!),
      ),
    ),
  );
}

/// Welcome → Import wallet → import method selection.
Future<void> _openMethodSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mobile_welcome_import')));
  await tester.pumpAndSettle();
}

double _stepsProgress(WidgetTester tester) {
  final fill = tester.widget<FractionallySizedBox>(
    find.byType(FractionallySizedBox).first,
  );
  return fill.widthFactor!;
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1000)
      ..devicePixelRatio = 1.0;
  });

  for (final existing in [false, true]) {
    for (final entry in ['link', 'keystone', 'ledger']) {
      testWidgets('$entry advances after selection (existing=$existing)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            existingWallet: existing,
            initialLocation: existing ? '/add-account' : '/welcome',
          ),
        );
        await tester.pumpAndSettle();
        await _openMethodSelection(tester);
        if (entry != 'link') {
          await tester.tap(
            find.byKey(const ValueKey('mobile_import_hardware')),
          );
          await tester.pumpAndSettle();
          expect(_stepsProgress(tester), closeTo(60 / 196, 1e-8));
        }
        await tester.tap(
          find.byKey(
            ValueKey(
              entry == 'link'
                  ? 'mobile_welcome_link_desktop'
                  : 'mobile_welcome_$entry',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expected = switch (entry) {
          'link' => existing ? 0.44489795918 : 0.42176870748,
          'keystone' => existing ? 0.42176870748 : 0.40524781341,
          'ledger' => existing ? 0.47959183673 : 0.44489795918,
          _ => throw StateError(entry),
        };
        expect(_stepsProgress(tester), closeTo(expected, 1e-8));
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        expect(_stepsProgress(tester), closeTo(60 / 196, 1e-8));
      });
    }
  }

  testWidgets(
    'security changes do not reweight active pages; a new start captures them',
    (tester) async {
      final security = _MutableSecurity();
      await tester.pumpWidget(_app(security: security));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_welcome_get_started')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile_intro_continue')));
      await tester.pumpAndSettle();
      expect(_stepsProgress(tester), closeTo(0.42176870748, 1e-8));
      security.configure();
      await tester.pumpAndSettle();
      expect(_stepsProgress(tester), closeTo(0.42176870748, 1e-8));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(const ValueKey('mobile_welcome_get_started')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile_intro_continue')));
      await tester.pumpAndSettle();
      expect(_stepsProgress(tester), closeTo(0.44489795918, 1e-8));
    },
  );

  testWidgets('welcome exposes create and import without the method cards', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_welcome_get_started')),
      findsOneWidget,
    );
    expect(find.text('Get started'), findsOneWidget);
    // Method cards are shown after choosing Import wallet.
    expect(find.text('Create Wallet'), findsNothing);
  });

  testWidgets('Import wallet opens the three import methods and '
      'no legal footer', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);

    expect(find.byType(MobileMethodSelectionScreen), findsOneWidget);
    expect(find.text('Import secret passphrase'), findsOneWidget);
    expect(find.text('Import Account\nto Vizor'), findsOneWidget);
    expect(find.text('Link Vizor Desktop'), findsOneWidget);
    expect(find.text('Connect hardware wallet'), findsOneWidget);
    expect(_stepsProgress(tester), closeTo(60 / 196, 0.0001));
    expect(find.textContaining('you agree to our'), findsNothing);
    expect(find.text('Terms'), findsNothing);
    expect(find.text('Privacy'), findsNothing);
  });

  testWidgets('method selection content scrolls on short screens', (
    tester,
  ) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(393, 480);

    await tester.pumpWidget(_app(initialLocation: '/onboarding/method'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    const hardwareKey = ValueKey('mobile_import_hardware');
    final scrollable = find.byKey(
      const ValueKey('mobile_method_selection_scroll'),
    );
    expect(scrollable, findsOneWidget);

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byKey(hardwareKey)).bottom,
      greaterThan(screenHeight),
    );

    await tester.drag(scrollable, const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(hardwareKey)).bottom,
      lessThanOrEqualTo(screenHeight),
    );
  });

  testWidgets('import pushes the import entry step', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);
    final selectionProgress = _stepsProgress(tester);

    await tester.tap(find.byKey(const ValueKey('mobile_import_passphrase')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileImportScreen), findsOneWidget);
    expect(_stepsProgress(tester), greaterThan(selectionProgress));
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(_stepsProgress(tester), selectionProgress);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final network in ['main', 'test']) {
      testWidgets(
        '$platform $network hardware summary matches its destination',
        (tester) async {
          await tester.pumpWidget(_app(network: network, platform: platform));
          await tester.pumpAndSettle();
          await _openMethodSelection(tester);
          expect(
            find.text(
              network == 'main'
                  ? 'Ledger or Keystone wallet'
                  : 'Keystone wallet',
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('mobile_import_hardware')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Connect Keystone'), findsOneWidget);
          expect(
            find.text('Connect Ledger'),
            network == 'main' ? findsOneWidget : findsNothing,
          );
        },
      );
    }
  }

  testWidgets('link desktop pushes the wallet link intro step', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);

    await tester.tap(find.byKey(const ValueKey('mobile_welcome_link_desktop')));
    await tester.pumpAndSettle();

    expect(find.byType(MobileWalletLinkIntroScreen), findsOneWidget);
    expect(find.text('Link with Desktop'), findsOneWidget);
    expect(find.text('Copy your desktop wallet to this phone'), findsOneWidget);
    expect(
      find.text(
        'This copies the wallet and contacts to the phone. Nothing on the computer changes, and you can use both.',
      ),
      findsOneWidget,
    );
    expect(find.text('Go to Settings → Link Vizor Mobile'), findsOneWidget);
    expect(
      find.text('Scan the QR code on your desktop from the next screen.'),
      findsOneWidget,
    );
  });

  testWidgets('keystone pushes the keystone intro step', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);

    await tester.tap(find.byKey(const ValueKey('mobile_import_hardware')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_keystone')));
    await tester.pumpAndSettle();

    expect(find.byType(MobileKeystoneIntroScreen), findsOneWidget);
    expect(find.text('Connect Keystone'), findsOneWidget);
  });

  Future<void> pump(
    WidgetTester tester, {
    String location = '/welcome',
    AppThemeData theme = AppThemeData.light,
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(initialLocation: location, theme: theme));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'initial Welcome shows the current copy and accessible action sizes',
    (tester) async {
      await pump(tester);
      expect(find.text('Shielded\nby default'), findsOneWidget);
      expect(find.text('Activate gift card'), findsOneWidget);
      for (final key in [
        'mobile_welcome_get_started',
        'mobile_welcome_import',
        'mobile_welcome_redeem_card',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.width, 240);
        expect(size.height, greaterThanOrEqualTo(44));
      }
    },
  );

  testWidgets('Gift Card activation opens the first-wallet entry', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    final button = find.byKey(const ValueKey('mobile_welcome_redeem_card'));
    final node = tester.getSemantics(button);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isEnabled, Tristate.isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.text('Create wallet by redeeming Vizor Gift Card'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  for (final entry in ['/welcome', '/add-account']) {
    testWidgets('$entry retains its caller through create and every import '
        'choice', (tester) async {
      await pump(tester, location: entry);
      await tester.tap(
        find.byKey(const ValueKey('mobile_welcome_get_started')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileOnboardingIntroScreen), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mobile_welcome_import')));
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(
          tester.element(find.byType(MobileMethodSelectionScreen)),
        ).uri.path,
        '/onboarding/method',
      );
      final selectionProgress = _stepsProgress(tester);
      for (final choice in [
        (key: 'mobile_import_passphrase', screen: MobileImportScreen),
        (
          key: 'mobile_welcome_link_desktop',
          screen: MobileWalletLinkIntroScreen,
        ),
        (key: 'mobile_import_hardware', screen: MobileHardwareSelectionScreen),
      ]) {
        await tester.tap(find.byKey(ValueKey(choice.key)));
        await tester.pumpAndSettle();
        expect(find.byType(choice.screen), findsOneWidget);
        if (choice.screen == MobileImportScreen) {
          expect(_stepsProgress(tester), greaterThan(selectionProgress));
        }
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileMethodSelectionScreen), findsOneWidget);
        expect(_stepsProgress(tester), selectionProgress);
      }
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      final welcome = find.byKey(const ValueKey('mobile_welcome_get_started'));
      expect(GoRouterState.of(tester.element(welcome)).uri.path, entry);
      expect(
        find.byKey(const ValueKey('mobile_welcome_redeem_card')),
        findsOneWidget,
      );
    });
  }

  testWidgets('add-account Welcome offers Gift Card and returns home', (
    tester,
  ) async {
    await pump(tester, location: '/add-account');
    expect(find.text('Activate gift card'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_welcome_redeem_card')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('home-route'), findsOneWidget);
  });

  testWidgets('reduced motion uses the poster at the Figma video slot', (
    tester,
  ) async {
    await pump(tester);
    final poster = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == kMobileWelcomePosterAsset,
    );
    expect(poster, findsOneWidget);
    expect(tester.getSize(poster).width, 394);
  });

  for (final theme in {
    'light': AppThemeData.light,
    'dark': AppThemeData.dark,
  }.entries) {
    testWidgets('keyboard focus keeps the fixed dark palette (${theme.key})', (
      tester,
    ) async {
      await pump(tester, theme: theme.value);
      for (final key in [
        'mobile_welcome_get_started',
        'mobile_welcome_import',
      ]) {
        final target = find.byKey(ValueKey(key));
        final label = find
            .descendant(of: target, matching: find.byType(Text))
            .first;
        Focus.of(tester.element(label)).requestFocus();
        await tester.pumpAndSettle();
        final opacity = find.descendant(
          of: target,
          matching: find.byType(AnimatedOpacity),
        );
        expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
        final ring = tester.widget<DecoratedBox>(
          find.descendant(of: opacity, matching: find.byType(DecoratedBox)),
        );
        expect(
          ((ring.decoration as ShapeDecoration).shape as OutlinedBorder)
              .side
              .color,
          WelcomeButtonTokens.focusRing,
        );
      }
    });
  }

  testWidgets('touch feedback retains label contrast and cancels cleanly', (
    tester,
  ) async {
    await pump(tester);
    for (final entry in {
      'Get started': WelcomeButtonTokens.accentLabel,
      'Import wallet': WelcomeButtonTokens.secondaryLabel,
      'Activate gift card': WelcomeButtonTokens.accentLabel,
    }.entries) {
      final label = find.text(entry.key);
      final gesture = await tester.startGesture(tester.getCenter(label));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        DefaultTextStyle.of(tester.element(label)).style.color,
        entry.value,
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.text('Shielded\nby default'), findsOneWidget);
    }
  });
}

class _MutableSecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);
  void configure() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: true,
  );
}
