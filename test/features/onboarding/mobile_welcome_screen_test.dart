@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_method_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_wallet_link_screens.dart';

Widget _app({
  String initialLocation = '/welcome',
  AppThemeData theme = AppThemeData.light,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: theme, child: child!),
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
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1000)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('welcome shows the Get started call to action only', (
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

  testWidgets('hero illustration fills the whole screen', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // The full-bleed hero is the Positioned.fill background. Guards against
    // the Stack collapsing to its min-height content column (which would
    // shrink the hero into a band at the top).
    final hero = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName.contains('mobile_welcome_hero'),
    );
    expect(hero, findsOneWidget);
    final size = tester.getSize(hero);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(size.width, screen.width);
    expect(size.height, screen.height);
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
}
