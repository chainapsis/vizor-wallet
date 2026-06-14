@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_keystone_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_method_selection_screen.dart';

Widget _app({String initialLocation = '/welcome'}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

/// Welcome → "Get started" → Method Selection (where the entry points now
/// live).
Future<void> _openMethodSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('mobile_welcome_get_started')));
  await tester.pumpAndSettle();
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
    'Get started opens method selection with the three entry points and '
    'the legal footer',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      await _openMethodSelection(tester);

      expect(find.byType(MobileMethodSelectionScreen), findsOneWidget);
      expect(find.text('Create wallet'), findsOneWidget);
      expect(find.text('Import wallet'), findsOneWidget);
      expect(find.text('Connect Keystone'), findsOneWidget);
      expect(find.textContaining('you agree to our'), findsOneWidget);
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
    const contentKey = ValueKey('mobile_method_create_wallet_content');
    expect(find.byKey(artKey), findsOneWidget);
    expect(find.byKey(contentKey), findsOneWidget);

    final createCardStack = tester
        .widgetList<Stack>(find.byType(Stack))
        .firstWhere((stack) {
          final hasArt = stack.children.any(
            (child) => child is Positioned && child.child.key == artKey,
          );
          final hasContent = stack.children.any(
            (child) => child.key == contentKey,
          );
          return hasArt && hasContent;
        });

    final artIndex = createCardStack.children.indexWhere(
      (child) => child is Positioned && child.child.key == artKey,
    );
    final contentIndex = createCardStack.children.indexWhere(
      (child) => child.key == contentKey,
    );

    expect(contentIndex, greaterThan(artIndex));
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
