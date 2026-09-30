@Tags(['mobile'])
library;

import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_method_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_wallet_link_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_backdrop.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/welcome_button_tokens.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

Widget _app({
  String initialLocation = '/welcome',
  AppThemeData theme = AppThemeData.light,
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
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
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

/// Welcome → "Get started" → Method Selection (where the entry points now
/// live).
Future<void> _openMethodSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mobile_welcome_get_started')));
  await tester.pumpAndSettle();
}

double _stepsProgress(WidgetTester tester) {
  final fill = tester.widget<FractionallySizedBox>(
    find.byType(FractionallySizedBox).first,
  );
  return fill.widthFactor!;
}

BoxDecoration _cardBackgroundDecoration(WidgetTester tester, Key cardKey) {
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(cardKey),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((decoration) => decoration.color != null);
}

Color? _cardIconColor(WidgetTester tester, Key cardKey) {
  final icon = tester.widget<AppIcon>(
    find
        .descendant(of: find.byKey(cardKey), matching: find.byType(AppIcon))
        .first,
  );
  return icon.color;
}

Color? _textColor(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text)).style?.color;
}

String _assetNameForKey(WidgetTester tester, Key key) {
  final image = tester.widget<Image>(find.byKey(key));
  return (image.image as AssetImage).assetName;
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1000)
      ..devicePixelRatio = 1.0;
  });

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
    // The entry points moved to the method-selection step.
    expect(find.text('Create Wallet'), findsNothing);
  });

  testWidgets(
    'Get started opens method selection with the four entry points and '
    'no legal footer',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _openMethodSelection(tester);

      expect(find.byType(MobileMethodSelectionScreen), findsOneWidget);
      expect(find.text('Create Wallet'), findsOneWidget);
      expect(find.text('Import Wallet'), findsOneWidget);
      expect(find.text('Link Vizor Desktop'), findsOneWidget);
      expect(find.text('Connect Keystone'), findsOneWidget);
      expect(_stepsProgress(tester), closeTo(60 / 196, 0.0001));
      expect(find.textContaining('you agree to our'), findsNothing);
      expect(find.text('Terms'), findsNothing);
      expect(find.text('Privacy'), findsNothing);
    },
  );

  testWidgets('method selection content scrolls on short screens', (
    tester,
  ) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(393, 568);

    await tester.pumpWidget(_app(initialLocation: '/onboarding/method'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    const keystoneKey = ValueKey('mobile_welcome_keystone');
    final scrollable = find.byKey(
      const ValueKey('mobile_method_selection_scroll'),
    );
    expect(scrollable, findsOneWidget);

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byKey(keystoneKey)).bottom,
      greaterThan(screenHeight),
    );

    await tester.drag(scrollable, const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(keystoneKey)).bottom,
      lessThanOrEqualTo(screenHeight),
    );
  });

  testWidgets('method cards use full-card figma background assets', (
    tester,
  ) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(393, 852);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);

    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_create_wallet_art'),
      ),
      'assets/illustrations/method_create_card_bg.png',
    );
    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_import_wallet_art'),
      ),
      'assets/illustrations/method_import_card_bg.png',
    );
    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_link_vizor_desktop_art'),
      ),
      'assets/illustrations/method_link_desktop_card_bg.png',
    );
    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_connect_keystone_art'),
      ),
      'assets/illustrations/method_keystone_card_bg.png',
    );

    expect(
      find.byKey(const ValueKey('mobile_method_create_wallet_content')),
      findsOneWidget,
    );
  });

  testWidgets('method cards use figma light theme colors and assets', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/onboarding/method'));
    await tester.pumpAndSettle();

    final colors = AppThemeData.light.colors;

    expect(
      _cardBackgroundDecoration(
        tester,
        const ValueKey('mobile_welcome_create'),
      ).color,
      colors.background.homeCard,
    );
    expect(_textColor(tester, 'Create Wallet'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_create')),
      colors.text.homeCard,
    );

    expect(
      _cardBackgroundDecoration(
        tester,
        const ValueKey('mobile_welcome_import'),
      ).color,
      colors.background.homeCard,
    );
    expect(_textColor(tester, 'Import Wallet'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_import')),
      colors.text.homeCard,
    );
    expect(_textColor(tester, 'Link Vizor Desktop'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_link_desktop')),
      colors.text.homeCard,
    );

    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_connect_keystone_art'),
      ),
      'assets/illustrations/method_keystone_card_bg.png',
    );
  });

  testWidgets('method cards use figma dark theme colors and assets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(initialLocation: '/onboarding/method', theme: AppThemeData.dark),
    );
    await tester.pumpAndSettle();

    final colors = AppThemeData.dark.colors;

    expect(
      _cardBackgroundDecoration(
        tester,
        const ValueKey('mobile_welcome_create'),
      ).color,
      colors.background.homeCard,
    );
    expect(_textColor(tester, 'Create Wallet'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_create')),
      colors.text.homeCard,
    );

    expect(
      _cardBackgroundDecoration(
        tester,
        const ValueKey('mobile_welcome_import'),
      ).color,
      colors.background.homeCard,
    );
    expect(_textColor(tester, 'Import Wallet'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_import')),
      colors.text.homeCard,
    );
    expect(_textColor(tester, 'Link Vizor Desktop'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_link_desktop')),
      colors.text.homeCard,
    );

    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_connect_keystone_art'),
      ),
      'assets/illustrations/method_keystone_card_bg.png',
    );
  });

  testWidgets('create pushes the intro step', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);

    await tester.tap(find.byKey(const ValueKey('mobile_welcome_create')));
    await tester.pumpAndSettle();

    expect(find.byType(MobileOnboardingIntroScreen), findsOneWidget);
  });

  testWidgets('import pushes the import entry step', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);

    await tester.tap(find.byKey(const ValueKey('mobile_welcome_import')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileImportScreen), findsOneWidget);
  });

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

    await tester.tap(find.byKey(const ValueKey('mobile_welcome_keystone')));
    await tester.pumpAndSettle();

    expect(find.byType(MobileKeystoneIntroScreen), findsOneWidget);
    expect(find.text('Connect Keystone'), findsOneWidget);
  });

  testWidgets('add-account variant shows back to home affordance', (
    tester,
  ) async {
    await tester.pumpWidget(_app(initialLocation: '/add-account'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
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

  testWidgets('Gift Card TODO is disabled with no tap action or destination', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    final button = find.byKey(const ValueKey('mobile_welcome_redeem_card'));
    final node = tester.getSemantics(button);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Shielded\nby default'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Get started keeps the existing creation method screen', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_get_started')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileMethodSelectionScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_welcome_create')), findsOneWidget);
  });

  testWidgets('Import wallet keeps the existing import entry and can return', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_import')));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.byType(MobileImportScreen)));
    expect(
      GoRouterState.of(
        tester.element(find.byType(MobileImportScreen)),
      ).uri.path,
      '/import',
    );
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Shielded\nby default'), findsOneWidget);
  });

  testWidgets('add-account Welcome hides Gift Card and returns home', (
    tester,
  ) async {
    await pump(tester, location: '/add-account');
    expect(find.text('Activate Gift Card'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_welcome_redeem_card')),
      findsNothing,
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
