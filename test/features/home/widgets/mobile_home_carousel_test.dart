@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile_home_carousel.dart';

void main() {
  testWidgets('stays on the current banner until the user changes it', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    await tester.pump(const Duration(seconds: 20));
    expect(find.text('First banner'), findsOneWidget);
    expect(find.text('Second banner'), findsNothing);
  });

  testWidgets('page indicators are full-size controls without chevrons', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final secondIndicator = find.byKey(
      const ValueKey('mobile_home_carousel_indicator_1'),
    );
    expect(tester.getSize(secondIndicator), const Size(44, 44));
    expect(
      find.bySemanticsLabel('Show wallet setup banner 2 of 2'),
      findsOneWidget,
    );

    await tester.tap(secondIndicator);
    await tester.pumpAndSettle();
    expect(find.text('Second banner'), findsOneWidget);
  });

  testWidgets(
    'reduced motion can switch between banners of different heights',
    (tester) async {
      const secondMessage =
          'A longer setup message remains readable when text is enlarged. '
          'The banner grows without a size transition.';
      await tester.pumpWidget(
        _harness(
          disableAnimations: true,
          items: const [
            MobileHomeCarouselItem(
              id: 'short',
              child: _FlexibleBanner('First banner'),
            ),
            MobileHomeCarouselItem(
              id: 'long',
              child: _FlexibleBanner(secondMessage),
            ),
          ],
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_home_carousel_indicator_1')),
      );
      await tester.pump();
      expect(find.text(secondMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a slow horizontal drag changes the page', (tester) async {
    await tester.pumpWidget(_harness());
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('First banner')),
    );
    await gesture.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(seconds: 1),
    );
    await gesture.moveBy(
      const Offset(-30, 0),
      timeStamp: const Duration(seconds: 2),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Second banner'), findsOneWidget);
  });

  testWidgets('a rightward swipe advances the RTL carousel', (tester) async {
    await tester.pumpWidget(_harness(textDirection: TextDirection.rtl));
    await tester.fling(find.text('First banner'), const Offset(100, 0), 500);
    await tester.pumpAndSettle();
    expect(find.text('Second banner'), findsOneWidget);
  });

  testWidgets('removing all banners leaves no content or controls', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpWidget(_harness(items: const []));
    expect(find.text('First banner'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_home_carousel_indicator_0')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrow keys change the focused banner', (tester) async {
    await tester.pumpWidget(_harness());
    final focus = tester.widget<Focus>(
      find.byKey(const ValueKey('mobile_home_carousel_focus')),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Second banner'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('First banner'), findsOneWidget);
  });

  testWidgets('new item identities reset to the requested initial page', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(initialPage: 1));
    expect(find.text('Second banner'), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        items: const [
          MobileHomeCarouselItem(
            id: 'replacement-first',
            child: _FlexibleBanner('Replacement first'),
          ),
          MobileHomeCarouselItem(
            id: 'replacement-second',
            child: _FlexibleBanner('Replacement second'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replacement first'), findsOneWidget);
  });

  testWidgets('single banner grows for 200 percent text without controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _harness(
        items: const [
          MobileHomeCarouselItem(
            id: 'only',
            child: _FlexibleBanner(
              'A longer setup message remains readable when text is enlarged.',
            ),
          ),
        ],
      ),
    );
    expect(
      find.byKey(const ValueKey('mobile_home_carousel_indicator_0')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _harness({
  List<MobileHomeCarouselItem> items = const [
    MobileHomeCarouselItem(id: 'first', child: _FlexibleBanner('First banner')),
    MobileHomeCarouselItem(
      id: 'second',
      child: _FlexibleBanner('Second banner'),
    ),
  ],
  int initialPage = 0,
  bool disableAnimations = false,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return MaterialApp(
    builder: (context, child) => AppTheme(
      data: AppThemeData.dark,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: Directionality(textDirection: textDirection, child: child!),
      ),
    ),
    home: Scaffold(
      body: MobileHomeCarousel(items: items, initialPage: initialPage),
    ),
  );
}

class _FlexibleBanner extends StatelessWidget {
  const _FlexibleBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    color: context.colors.background.ground,
    child: Text(message),
  );
}
