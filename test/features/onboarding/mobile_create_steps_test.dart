@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_create_steps.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/create/onboarding_split_view.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

class _FixtureMnemonic extends CreateOnboardingMnemonicNotifier {
  @override
  String? build() =>
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
}

Widget _app(String initialLocation, {double bottomInset = 0}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return ProviderScope(
    overrides: [
      createOnboardingMnemonicProvider.overrideWith(_FixtureMnemonic.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(padding: EdgeInsets.only(bottom: bottomInset)),
        child: AppTheme(data: AppThemeData.light, child: child!),
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
    // Secret passphrase is still the placeholder until OB-4.
    expect(find.byType(MobileAddressTypesScreen), findsNothing);
  });

  testWidgets('create education screens count welcome in progress', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/onboarding/intro'));
    await tester.pumpAndSettle();
    expect(_stepsProgress(tester), closeTo(mobileCreateProgress(3), 0.0001));

    await tester.pumpWidget(_app('/onboarding/address-types'));
    await tester.pumpAndSettle();
    expect(_stepsProgress(tester), closeTo(mobileCreateProgress(4), 0.0001));

    await tester.pumpWidget(_app('/onboarding/things-to-know'));
    await tester.pumpAndSettle();
    expect(_stepsProgress(tester), closeTo(mobileCreateProgress(5), 0.0001));
  });

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
