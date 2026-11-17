@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/feedback/app_haptics.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_page.dart';

class _Stack extends StatefulWidget {
  const _Stack({this.transition = MobilePageTransition.fadeZoom, super.key});

  final MobilePageTransition transition;

  @override
  State<_Stack> createState() => _StackState();
}

class _StackState extends State<_Stack> {
  late final _pages = <Page<void>>[_page('first')];

  Page<void> _page(String name) => MobilePage<void>(
    key: ValueKey(name),
    transition: widget.transition,
    child: ColoredBox(
      key: ValueKey('$name-screen'),
      color: const Color(0xff202020),
      child: Center(child: Text(name)),
    ),
  );

  void push() => setState(() => _pages.add(_page('second')));

  @override
  Widget build(BuildContext context) => Navigator(
    pages: List.of(_pages),
    onDidRemovePage: (page) => setState(() => _pages.remove(page)),
  );
}

void main() {
  final stack = GlobalKey<_StackState>();
  final haptics = <Object?>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  final first = find.byKey(const ValueKey('first-screen'));
  final second = find.byKey(const ValueKey('second-screen'));

  Future<void> pumpStack(
    WidgetTester tester, {
    bool disableAnimations = false,
    MobilePageTransition transition = MobilePageTransition.fadeZoom,
    TextDirection textDirection = TextDirection.ltr,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: textDirection,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
      ),
      home: _Stack(key: stack, transition: transition),
    ),
  );

  bool translucent(WidgetTester tester, Finder page) => tester
      .widgetList<Opacity>(
        find.ancestor(of: page, matching: find.byType(Opacity)),
      )
      .any((opacity) => opacity.opacity < 1);

  testWidgets('a pushed page fades and zooms in rather than sliding', (
    tester,
  ) async {
    await pumpStack(tester);
    final screen = tester.getRect(first);

    stack.currentState!.push();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    // Centred, a little smaller and translucent: it grows in place.
    expect(tester.getRect(second).center.dx, screen.center.dx);
    expect(tester.getRect(second).width, lessThan(screen.width));
    expect(translucent(tester, second), isTrue);
    // The page it covers grows a touch.
    expect(tester.getRect(first).width, greaterThan(screen.width));

    await tester.pumpAndSettle();
    expect(tester.getRect(second), screen);
    expect(translucent(tester, second), isFalse);
  });

  testWidgets('the fade ends early, so most of the zoom draws opaque', (
    tester,
  ) async {
    await pumpStack(tester);
    final screen = tester.getRect(first);

    stack.currentState!.push();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    // Still growing, but no longer drawn through an offscreen layer.
    expect(tester.getRect(second).width, lessThan(screen.width));
    expect(translucent(tester, second), isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'button Back slides opaque at full size and restores the previous '
    'page in step over 400ms',
    (tester) async {
      await pumpStack(tester);
      final screen = tester.getRect(first);
      stack.currentState!.push();
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(second))!;

      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pump();
      expect(tester.getRect(second), screen);
      var previousShift = 0.0;
      for (final milliseconds in [100, 160, 130]) {
        await tester.pump(Duration(milliseconds: milliseconds));
        final outgoing = tester.getRect(second);
        final shift = (outgoing.left - screen.left) / screen.width;
        expect(shift, greaterThan(previousShift));
        expect(shift, lessThan(1));
        expect(outgoing.width, closeTo(screen.width, .000001));
        expect(outgoing.height, closeTo(screen.height, .000001));
        expect(translucent(tester, second), false);
        expect(
          tester.getRect(first).width / screen.width,
          closeTo(1 + .03 * (1 - shift), .000001),
        );
        expect(
          tester.getRect(first).center,
          offsetMoreOrLessEquals(screen.center),
        );
        previousShift = shift;
      }
      await tester.pump(const Duration(milliseconds: 10));
      expect(route.animation!.value, 0);
      await tester.pumpAndSettle();
      expect(second, findsNothing);
      expect(tester.getRect(first), screen);
    },
  );

  testWidgets('button Back mirrors the slide in RTL', (tester) async {
    await pumpStack(tester, textDirection: TextDirection.rtl);
    final screen = tester.getRect(first);
    stack.currentState!.push();
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(second).left, lessThan(screen.left));
    expect(tester.getRect(second).size, screen.size);
    expect(translucent(tester, second), false);
    await tester.pumpAndSettle();
    expect(tester.getRect(first), screen);
  });

  testWidgets('Back during entry reverses without a geometry or opacity jump', (
    tester,
  ) async {
    await pumpStack(tester);
    final screen = tester.getRect(first);
    stack.currentState!.push();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final outgoing = tester.getRect(second);
    final covered = tester.getRect(first);
    final opacity = tester
        .widget<Opacity>(
          find.ancestor(of: second, matching: find.byType(Opacity)).first,
        )
        .opacity;
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pump();
    expect(tester.getRect(second), outgoing);
    expect(tester.getRect(first), covered);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: second, matching: find.byType(Opacity)).first,
          )
          .opacity,
      opacity,
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getRect(second).center, screen.center);
    expect(tester.getRect(second).width, lessThan(outgoing.width));
    await tester.pumpAndSettle();
    expect(second, findsNothing);
    expect(tester.getRect(first), screen);
  });

  testWidgets('reduced motion keeps only the fade', (tester) async {
    await pumpStack(tester, disableAnimations: true);
    final screen = tester.getRect(first);

    stack.currentState!.push();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(tester.getRect(second), screen);
    expect(tester.getRect(first), screen);
    expect(translucent(tester, second), isTrue);

    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(second))!;
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getRect(second), screen);
    expect(tester.getRect(first), screen);
    expect(translucent(tester, second), true);
    await tester.pump(const Duration(milliseconds: 220));
    expect(second, findsOneWidget);
    expect(route.animation!.value, greaterThan(0));
    expect(tester.getRect(second), screen);
    await tester.pump(const Duration(milliseconds: 140));
    expect(route.animation!.value, 0);
    await tester.pumpAndSettle();
    expect(second, findsNothing);
  });

  testWidgets('a swipe from the leading edge follows the finger and pops', (
    tester,
  ) async {
    await pumpStack(tester);
    stack.currentState!.push();
    await tester.pumpAndSettle();
    final screen = tester.getRect(second);
    final start = Offset(screen.left + 2, screen.center.dy);

    // A short, slow drag moves the page with the finger, then settles back.
    // The page slides opaque at full size, so nothing shows through it.
    var drag = await tester.startGesture(start);
    await drag.moveBy(Offset(screen.width * .25, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(second).left, greaterThan(screen.left));
    expect(tester.getRect(second).size, screen.size);
    expect(translucent(tester, second), isFalse);
    final shift = (tester.getRect(second).left - screen.left) / screen.width;
    expect(
      tester.getRect(first).width / screen.width,
      closeTo(1 + .03 * (1 - shift), .000001),
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(second), screen);

    // Past halfway it pops.
    drag = await tester.startGesture(start);
    await drag.moveBy(Offset(screen.width * .75, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await drag.up();
    await tester.pumpAndSettle();
    expect(second, findsNothing);
    expect(tester.getRect(first), screen);
  });

  testWidgets(
    'button Back after a cancelled swipe still slides without fading',
    (tester) async {
      await pumpStack(tester);
      stack.currentState!.push();
      await tester.pumpAndSettle();
      final screen = tester.getRect(second);
      final drag = await tester.startGesture(Offset(screen.left + 2, 200));
      await drag.moveBy(Offset(screen.width * .25, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(second), screen);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pump();
      expect(tester.getRect(second), screen);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(second).left, greaterThan(screen.left));
      expect(tester.getRect(second).width, closeTo(screen.width, .000001));
      expect(translucent(tester, second), false);
      await tester.pumpAndSettle();
      expect(second, findsNothing);
      expect(tester.getRect(first), screen);
    },
  );

  testWidgets('onboarding enters instantly and slides out over 400ms on Back', (
    tester,
  ) async {
    await pumpStack(tester, transition: MobilePageTransition.onboarding);
    final screen = tester.getRect(first);
    stack.currentState!.push();
    await tester.pump();
    expect(tester.getRect(second), screen);
    expect(translucent(tester, second), false);
    final route = ModalRoute.of(tester.element(second))!;
    expect(route.animation!.isCompleted, true);

    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(second, findsOneWidget);
    expect(tester.getRect(second).left, greaterThan(screen.left));
    expect(tester.getRect(second).width, closeTo(screen.width, 0.001));
    expect(translucent(tester, second), false);
    expect(tester.getRect(first), screen);
    await tester.pump(const Duration(milliseconds: 180));
    expect(second, findsOneWidget);
    expect(route.animation!.value, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 130));
    expect(route.animation!.value, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 10));
    expect(route.animation!.value, closeTo(0, 0.001));
    await tester.pumpAndSettle();
    expect(second, findsNothing);
    expect(tester.getRect(first), screen);
  });

  testWidgets(
    'onboarding reduced-motion exit fades without moving or scaling',
    (tester) async {
      await pumpStack(
        tester,
        transition: MobilePageTransition.onboarding,
        disableAnimations: true,
      );
      final screen = tester.getRect(first);
      stack.currentState!.push();
      await tester.pump();
      expect(tester.getRect(second), screen);
      expect(translucent(tester, second), false);
      final route = ModalRoute.of(tester.element(second))!;
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(second), screen);
      expect(tester.getRect(first), screen);
      expect(translucent(tester, second), true);
      await tester.pump(const Duration(milliseconds: 180));
      expect(second, findsOneWidget);
      expect(route.animation!.value, greaterThan(0));
      expect(tester.getRect(second), screen);
      await tester.pump(const Duration(milliseconds: 140));
      expect(route.animation!.value, 0);
      await tester.pumpAndSettle();
      expect(second, findsNothing);
    },
  );

  testWidgets('onboarding Back slides toward the leading edge in RTL', (
    tester,
  ) async {
    await pumpStack(
      tester,
      transition: MobilePageTransition.onboarding,
      textDirection: TextDirection.rtl,
    );
    stack.currentState!.push();
    await tester.pump();
    final screen = tester.getRect(second);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getRect(second).left, lessThan(screen.left));
    await tester.pumpAndSettle();
    expect(second, findsNothing);
  });

  testWidgets('onboarding go() replaces a step immediately without keeping it '
      'in back history', (tester) async {
    final router = GoRouter(
      initialLocation: '/first',
      routes: [
        for (final name in ['first', 'second'])
          GoRoute(
            path: '/$name',
            pageBuilder: (_, state) => MobilePage<void>(
              key: state.pageKey,
              transition: MobilePageTransition.onboarding,
              child: ColoredBox(
                key: ValueKey('$name-screen'),
                color: Colors.white,
                child: Center(child: Text(name)),
              ),
            ),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    final screen = tester.getRect(first);
    router.go('/second');
    await tester.pump();
    expect(tester.getRect(second), screen);
    expect(second.hitTestable(), findsOneWidget);
    expect(translucent(tester, second), false);
    expect(router.canPop(), false);
    await tester.pumpAndSettle();
    expect(first, findsNothing);
  });

  testWidgets('onboarding swipe completion and cancellation keep settling '
      'after release', (tester) async {
    await pumpStack(tester, transition: MobilePageTransition.onboarding);
    stack.currentState!.push();
    await tester.pumpAndSettle();
    final screen = tester.getRect(second);
    final start = Offset(screen.left + 2, screen.center.dy);

    // The page moves with the finger at full size and opacity; the page
    // below holds still beside it.
    var drag = await tester.startGesture(start);
    await drag.moveBy(Offset(screen.width * .25, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(second).left, greaterThan(screen.left));
    expect(tester.getRect(second).size, screen.size);
    expect(translucent(tester, second), isFalse);
    expect(tester.getRect(first), screen);
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(second).left, greaterThan(screen.left));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    await tester.pump(const Duration(milliseconds: 249));
    expect(navigator.userGestureInProgress, true);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(navigator.userGestureInProgress, false);
    expect(tester.getRect(second), screen);

    // Past halfway it pops.
    drag = await tester.startGesture(start);
    await drag.moveBy(Offset(screen.width * .75, 0));
    await tester.pump(const Duration(milliseconds: 400));
    final releasedAt = tester.getRect(second).left;
    await drag.up();
    expect(navigator.userGestureInProgress, true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(second, findsOneWidget);
    expect(tester.getRect(second).left, greaterThan(releasedAt));
    expect(tester.getRect(first), screen);
    expect(translucent(tester, second), false);
    await tester.pump(const Duration(milliseconds: 249));
    expect(second, findsOneWidget);
    expect(navigator.userGestureInProgress, true);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(navigator.userGestureInProgress, false);
    expect(second, findsNothing);
    expect(tester.getRect(first), screen);
  });

  testWidgets('a short fast onboarding swipe animates its remaining distance', (
    tester,
  ) async {
    await pumpStack(tester, transition: MobilePageTransition.onboarding);
    stack.currentState!.push();
    await tester.pump();
    final screen = tester.getRect(second);
    final drag = await tester.startGesture(Offset(screen.left + 2, 200));
    for (var i = 1; i <= 5; i++) {
      await drag.moveBy(
        const Offset(15, 0),
        timeStamp: Duration(milliseconds: i * 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getRect(second).left, lessThan(screen.width / 2));
    await drag.up(timeStamp: const Duration(milliseconds: 96));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    expect(navigator.userGestureInProgress, true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(second, findsOneWidget);
    expect(tester.getRect(second).left, greaterThan(75));
    await tester.pumpAndSettle();
    expect(second, findsNothing);
    expect(navigator.userGestureInProgress, false);
  });

  testWidgets('opening and closing a page each play one light tap', (
    tester,
  ) async {
    await pumpStack(tester);
    // The first page appears without one.
    expect(haptics, isEmpty);

    stack.currentState!.push();
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(haptics, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('a back swipe taps only when it pops', (tester) async {
    await pumpStack(tester);
    stack.currentState!.push();
    await tester.pumpAndSettle();
    haptics.clear();
    final screen = tester.getRect(second);
    final start = Offset(screen.left + 2, screen.center.dy);

    var drag = await tester.startGesture(start);
    await drag.moveBy(Offset(screen.width * .25, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await drag.up();
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);

    drag = await tester.startGesture(start);
    await drag.moveBy(Offset(screen.width * .75, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await drag.up();
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('a button that tapped already is not tapped again', (
    tester,
  ) async {
    await pumpStack(tester);

    // As Home's Send does: an action tap, then the push on the next frame.
    await AppHaptics.action();
    stack.currentState!.push();
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });
}
