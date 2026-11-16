@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/feedback/app_haptics.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_page.dart';

class _Stack extends StatefulWidget {
  const _Stack({this.animated = true, super.key});

  final bool animated;

  @override
  State<_Stack> createState() => _StackState();
}

class _StackState extends State<_Stack> {
  late final _pages = <Page<void>>[_page('first')];

  Page<void> _page(String name) => MobilePage<void>(
    key: ValueKey(name),
    animated: widget.animated,
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
    bool animated = true,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: _Stack(key: stack, animated: animated),
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
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));

    // A pop fades out first and draws nothing for the rest.
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(of: second, matching: find.byType(Opacity)),
          )
          .map((opacity) => opacity.opacity),
      contains(0),
    );
    await tester.pumpAndSettle();
    expect(second, findsNothing);
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

  testWidgets('an instant page slides opaque under a back swipe', (
    tester,
  ) async {
    await pumpStack(tester, animated: false);
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
