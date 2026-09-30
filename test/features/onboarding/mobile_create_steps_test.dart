@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/create/onboarding_split_view.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

class _FixtureMnemonic extends CreateOnboardingMnemonicNotifier {
  @override
  String? build() =>
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
}

Widget _app(
  String initialLocation, {
  double bottomInset = 0,
  double topInset = 0,
  double textScale = 1,
  AppThemeData theme = AppThemeData.light,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      createOnboardingMnemonicProvider.overrideWith(_FixtureMnemonic.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: AppTheme(data: theme, child: child!),
      ),
    ),
  );
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
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('intro continues into address types and skip jumps ahead', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/onboarding/intro'));
    await tester.pumpAndSettle();

    expect(find.text('The Shielded World'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_intro_continue')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileAddressTypesScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_intro_skip')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSecretPassphraseScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOnboardingIntroScreen), findsOneWidget);
  });

  testWidgets('intro Back returns to Welcome', (tester) async {
    await tester.pumpWidget(_app('/welcome'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_get_started')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOnboardingIntroScreen), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileWelcomeScreen), findsOneWidget);
  });

  testWidgets('create education screens count welcome in progress', (
    tester,
  ) async {
    expect(kMobileCreateStepCount, 7);
    await tester.pumpWidget(_app('/onboarding/intro'));
    await tester.pumpAndSettle();
    expect(_stepsProgress(tester), closeTo(kMobileSelectionProgress, 0.0001));

    await tester.pumpWidget(_app('/onboarding/address-types'));
    await tester.pumpAndSettle();
    expect(_stepsProgress(tester), closeTo(mobileCreateProgress(3), 0.0001));

    await tester.pumpWidget(_app('/onboarding/things-to-know'));
    await tester.pumpAndSettle();
    expect(_stepsProgress(tester), closeTo(mobileCreateProgress(4), 0.0001));
  });

  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    for (final size in [const Size(393, 852), const Size(320, 568)]) {
      testWidgets(
        'intro scales text without clipping and keeps both actions reachable '
        'at $size in ${theme == AppThemeData.light ? 'light' : 'dark'}',
        (tester) async {
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            _app(
              '/onboarding/intro',
              theme: theme,
              textScale: 1.4,
              topInset: 55,
              bottomInset: size.width == 393 ? 34 : 0,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final card = tester.getRect(
            find.byKey(const ValueKey('mobile_intro_info_card')),
          );
          final body = tester.getRect(
            find.text(
              'Unlike Bitcoin or Ethereum, shielded Zcash transactions '
              'hide the sender, recipient, and amount — verified by '
              'cryptography, not trust.',
            ),
          );
          expect(body.left, greaterThanOrEqualTo(card.left));
          expect(body.right, lessThanOrEqualTo(card.right));
          expect(body.top, greaterThanOrEqualTo(card.top));
          expect(body.bottom, lessThanOrEqualTo(card.bottom));

          final continueAction = find.byKey(
            const ValueKey('mobile_intro_continue'),
          );
          final skipAction = find.byKey(const ValueKey('mobile_intro_skip'));
          expect(continueAction.hitTestable(), findsOneWidget);
          expect(skipAction.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(skipAction).bottom,
            lessThanOrEqualTo(size.height - (size.width == 393 ? 34 : 0)),
          );
          await tester.tap(skipAction);
          await tester.pumpAndSettle();
          expect(find.byType(MobileSecretPassphraseScreen), findsOneWidget);
        },
      );
    }
  }

  testWidgets('address types lists both pools and continues', (tester) async {
    await tester.pumpWidget(_app('/onboarding/address-types'));
    await tester.pumpAndSettle();

    expect(find.text('Shielded Address'), findsOneWidget);
    expect(find.text('Transparent Address'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_address_types_continue')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MobileThingsToKnowScreen), findsOneWidget);
  });

  testWidgets('things to know shows both notes', (tester) async {
    await tester.pumpWidget(_app('/onboarding/things-to-know'));
    await tester.pumpAndSettle();

    expect(find.text('Time to sync'), findsOneWidget);
    expect(find.text('How to keep privacy'), findsOneWidget);
  });

  for (final size in [const Size(393, 852), const Size(320, 568)]) {
    for (final step in ['address-types', 'things-to-know']) {
      testWidgets(
        '$step keeps separate sections and reachable action at $size',
        (tester) async {
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            _app('/onboarding/$step', bottomInset: size.width == 393 ? 34 : 0),
          );
          await tester.pumpAndSettle();

          final isAddress = step == 'address-types';
          final headings = isAddress
              ? ['Shielded Address', 'Transparent Address']
              : ['Time to sync', 'How to keep privacy'];
          Finder cardsFor(String heading) => find.ancestor(
            of: find.text(heading),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).color ==
                      AppThemeData.light.colors.background.ground,
            ),
          );
          if (isAddress) {
            expect(cardsFor(headings.first), findsOneWidget);
            expect(cardsFor(headings.last), findsOneWidget);
            final first = tester.getRect(cardsFor(headings.first));
            final second = tester.getRect(cardsFor(headings.last));
            expect(second.top - first.bottom, 16);
            expect(first.left, 16);
            expect(first.width, size.width - 32);
          } else {
            expect(cardsFor(headings.first), findsNothing);
            expect(cardsFor(headings.last), findsNothing);
          }
          final action = find.byKey(
            ValueKey(
              isAddress
                  ? 'mobile_address_types_continue'
                  : 'mobile_things_to_know_continue',
            ),
          );
          expect(tester.getRect(action).bottom, size.height - 48);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(
            find.byType(
              isAddress
                  ? MobileThingsToKnowScreen
                  : MobileSecretPassphraseScreen,
            ),
            findsOneWidget,
          );
          await tester.tap(find.bySemanticsLabel('Back'));
          await tester.pumpAndSettle();
          expect(
            find.byType(
              isAddress ? MobileAddressTypesScreen : MobileThingsToKnowScreen,
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
