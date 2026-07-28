import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_carousel.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';

const _items = [
  AppCarouselItem.icon(
    message: 'First carousel message uses two lines when rendered.',
    tileColor: Color(0xFF9667E2),
    icon: AppIcons.history,
  ),
  AppCarouselItem.icon(
    message: 'Second carousel message.',
    tileColor: Color(0xFF00A460),
    icon: AppIcons.wallet,
  ),
  AppCarouselItem.image(
    message: 'Third carousel message.',
    tileColor: Color(0xFFB90A4A),
    imageAsset: 'assets/illustrations/ironwood_migration_expect_running.png',
  ),
];

void main() {
  testWidgets('matches the Figma shell and card geometry', (tester) async {
    await tester.pumpWidget(_harness(autoplay: false));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel'))),
      const Size(560, 116),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_viewport'))),
      const Size(560, 100),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_card_0'))),
      const Size(396, 74),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(40, 6),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(20, 6),
    );
  });

  testWidgets('dragging changes page and updates the settled indicator', (
    tester,
  ) async {
    final pages = <int>[];
    await tester.pumpWidget(
      _harness(autoplay: false, onPageChanged: pages.add),
    );
    await tester.drag(
      find.byKey(const ValueKey('app_carousel_page_view')),
      const Offset(-415, 0),
    );
    await tester.pumpAndSettle();

    expect(pages, [1]);
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(20, 6),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(40, 6),
    );

    await tester.drag(
      find.byKey(const ValueKey('app_carousel_page_view')),
      const Offset(415, 0),
    );
    await tester.pumpAndSettle();

    expect(pages, [1, 0]);
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(40, 6),
    );
  });

  testWidgets('mouse dragging changes page', (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(
      _harness(autoplay: false, onPageChanged: pages.add),
    );
    final pageView = find.byKey(const ValueKey('app_carousel_page_view'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final center = tester.getCenter(pageView);
    await mouse.addPointer(location: center);
    await mouse.down(center);
    await mouse.moveBy(const Offset(-415, 0));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(pages, [1]);
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(40, 6),
    );
  });

  testWidgets('a single item is not duplicated or scrollable', (tester) async {
    await tester.pumpWidget(
      _harness(
        items: const [
          AppCarouselItem.icon(
            message: 'Only carousel message.',
            tileColor: Color(0xFF9667E2),
            icon: AppIcons.history,
          ),
        ],
        autoplay: false,
      ),
    );
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey('app_carousel_page_view')),
    );
    final delegate =
        pageView.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, 1);
    expect(pageView.physics, isA<NeverScrollableScrollPhysics>());
    expect(find.byKey(const ValueKey('app_carousel_card_0')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('app_carousel_page_view')),
      const Offset(-415, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(40, 6),
    );
  });

  testWidgets('autoplay advances after five seconds and loops', (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(_harness(onPageChanged: pages.add));

    await _advanceAutoplay(tester);
    expect(pages, [1]);

    await _advanceAutoplay(tester);
    await _advanceAutoplay(tester);
    expect(pages, [1, 2, 0]);
  });

  testWidgets('indicator selection responds before the card settles', (
    tester,
  ) async {
    final pages = <int>[];
    await tester.pumpWidget(_harness(onPageChanged: pages.add));

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 250));

    expect(pages, [1]);
  });

  testWidgets('reduced motion disables autoplay', (tester) async {
    await tester.pumpWidget(_harness(disableAnimations: true));
    await tester.pump(const Duration(seconds: 12));

    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(40, 6),
    );
  });

  testWidgets('hover pauses autoplay and restarts a full dwell on exit', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('app_carousel'))),
    );

    await tester.pump(const Duration(seconds: 12));
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(40, 6),
    );

    await mouse.moveTo(Offset.zero);
    await _advanceAutoplay(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(40, 6),
    );
  });

  testWidgets('app lifecycle pauses autoplay until the app resumes', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    await tester.pump(const Duration(seconds: 12));
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(40, 6),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _advanceAutoplay(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(40, 6),
    );
  });

  testWidgets('focus pauses autoplay and arrow keys navigate', (tester) async {
    await tester.pumpWidget(_harness());
    final carousel = find.byKey(const ValueKey('app_carousel'));
    final focus = tester.widget<Focus>(
      find.descendant(of: carousel, matching: find.byType(Focus)),
    );

    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_0'))),
      const Size(40, 6),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(40, 6),
    );
  });

  testWidgets('exposes only the active card as carousel semantics', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(autoplay: false));

    expect(
      find.bySemanticsLabel(
        'Migration information 1 of 3. '
        'First carousel message uses two lines when rendered.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Migration information 2 of 3. Second carousel message.',
      ),
      findsNothing,
    );
  });
}

Future<void> _advanceAutoplay(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Widget _harness({
  List<AppCarouselItem> items = _items,
  bool autoplay = true,
  bool disableAnimations = false,
  ValueChanged<int>? onPageChanged,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(900, 700),
      ).copyWith(disableAnimations: disableAnimations),
      child: AppTheme(
        data: AppThemeData.dark,
        child: ColoredBox(
          color: AppThemeData.dark.colors.background.window,
          child: Center(
            child: AppCarousel(
              items: items,
              autoplay: autoplay,
              semanticLabel: 'Migration information',
              onPageChanged: onPageChanged,
            ),
          ),
        ),
      ),
    ),
  );
}
