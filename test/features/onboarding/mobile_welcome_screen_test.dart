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
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';
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

Border _cardBorder(WidgetTester tester, Key cardKey) {
  final decoration = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(cardKey),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((decoration) => decoration.border != null);
  return decoration.border! as Border;
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
    expect(find.text('Create wallet'), findsNothing);
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
    'the hidden legal footer space',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _openMethodSelection(tester);

      expect(find.byType(MobileMethodSelectionScreen), findsOneWidget);
      expect(find.text('Create wallet'), findsOneWidget);
      expect(find.text('Import wallet'), findsOneWidget);
      expect(find.text('Link Vizor Desktop'), findsOneWidget);
      expect(find.text('Connect Keystone'), findsOneWidget);
      expect(_stepsProgress(tester), closeTo(mobileCreateProgress(2), 0.0001));
      expect(find.textContaining('you agree to our'), findsOneWidget);
      final hiddenFooter = find.byKey(
        const ValueKey('mobile_method_legal_footer_hidden'),
      );
      expect(hiddenFooter, findsOneWidget);
      expect(tester.widget<Opacity>(hiddenFooter).opacity, 0);
      final semantics = find.byKey(
        const ValueKey('mobile_method_legal_footer_semantics'),
      );
      final pointer = find.byKey(
        const ValueKey('mobile_method_legal_footer_pointer'),
      );
      expect(semantics, findsOneWidget);
      expect(tester.widget<ExcludeSemantics>(semantics).excluding, isTrue);
      expect(pointer, findsOneWidget);
      expect(tester.widget<IgnorePointer>(pointer).ignoring, isTrue);
    },
  );

  testWidgets('create method text paints above the bleeding illustration', (
    tester,
  ) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(393, 852);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openMethodSelection(tester);

    const artKey = ValueKey('mobile_method_create_wallet_art');
    const artClipKey = ValueKey('mobile_method_create_wallet_art_clip');
    const contentKey = ValueKey('mobile_method_create_wallet_content');
    expect(find.byKey(artKey), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(artClipKey), matching: find.byKey(artKey)),
      findsOneWidget,
    );
    expect(
      tester.widget<ClipPath>(find.byKey(artClipKey)).clipBehavior,
      Clip.antiAlias,
    );
    expect(find.byKey(contentKey), findsOneWidget);

    final createCardStack = tester
        .widgetList<Stack>(find.byType(Stack))
        .firstWhere((stack) {
          final hasArtClip = stack.children.any(
            (child) => child is Positioned && child.child.key == artClipKey,
          );
          final hasContent = stack.children.any(
            (child) => child.key == contentKey,
          );
          return hasArtClip && hasContent;
        });

    final artClipIndex = createCardStack.children.indexWhere(
      (child) => child is Positioned && child.child.key == artClipKey,
    );
    final borderIndex = createCardStack.children.indexWhere(
      (child) => child is Positioned && child.child is IgnorePointer,
    );
    final contentIndex = createCardStack.children.indexWhere(
      (child) => child.key == contentKey,
    );

    expect(borderIndex, lessThan(artClipIndex));
    expect(contentIndex, greaterThan(artClipIndex));
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
    expect(_textColor(tester, 'Create wallet'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_create')),
      colors.text.homeCard,
    );

    expect(
      _cardBackgroundDecoration(
        tester,
        const ValueKey('mobile_welcome_import'),
      ).color,
      colors.background.raised,
    );
    expect(_textColor(tester, 'Import wallet'), colors.text.accent);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_import')),
      colors.text.accent,
    );
    expect(_textColor(tester, 'Link Vizor Desktop'), colors.text.accent);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_link_desktop')),
      colors.text.accent,
    );

    final createBorder = _cardBorder(
      tester,
      const ValueKey('mobile_welcome_create'),
    );
    expect(createBorder.top.color, colors.border.subtle);
    expect(createBorder.top.width, 1.5);

    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_connect_keystone_art'),
      ),
      'assets/illustrations/method_keystone_light.png',
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
      colors.background.raised,
    );
    expect(_textColor(tester, 'Create wallet'), colors.text.homeCard);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_create')),
      colors.text.homeCard,
    );

    expect(
      _cardBackgroundDecoration(
        tester,
        const ValueKey('mobile_welcome_import'),
      ).color,
      colors.background.raised,
    );
    expect(_textColor(tester, 'Import wallet'), colors.text.accent);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_import')),
      colors.text.accent,
    );
    expect(_textColor(tester, 'Link Vizor Desktop'), colors.text.accent);
    expect(
      _cardIconColor(tester, const ValueKey('mobile_welcome_link_desktop')),
      colors.text.accent,
    );

    final createBorder = _cardBorder(
      tester,
      const ValueKey('mobile_welcome_create'),
    );
    expect(createBorder.top.color, colors.border.subtle);
    expect(createBorder.top.width, 1.5);

    expect(
      _assetNameForKey(
        tester,
        const ValueKey('mobile_method_connect_keystone_art'),
      ),
      'assets/illustrations/method_keystone_dark.png',
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
