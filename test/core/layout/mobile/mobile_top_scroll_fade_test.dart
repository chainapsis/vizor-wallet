import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_scroll_fade.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

Widget _app(Widget home) {
  return MaterialApp(
    builder: (_, c) => AppTheme(data: AppThemeData.dark, child: c!),
    home: home,
  );
}

Widget _fadeOverList({void Function()? onFirstRowTap}) {
  return MobileTopScrollFade(
    child: ListView(
      children: [
        GestureDetector(
          key: const ValueKey('first_row'),
          behavior: HitTestBehavior.opaque,
          onTap: onFirstRowTap,
          child: const SizedBox(height: 48),
        ),
        for (var i = 0; i < 40; i++) SizedBox(height: 48, child: Text('$i')),
      ],
    ),
  );
}

Finder get _overlayOpacity => find.descendant(
  of: find.byType(MobileTopScrollFade),
  matching: find.byType(Opacity),
);

void main() {
  testWidgets('invisible at rest, eased in once scrolled, gone again at the '
      'top', (tester) async {
    await tester.pumpWidget(_app(_fadeOverList()));

    expect(tester.widget<Opacity>(_overlayOpacity).opacity, 0);

    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();
    expect(tester.widget<Opacity>(_overlayOpacity).opacity, 1);

    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(_overlayOpacity).opacity, 0);
  });

  testWidgets('the fade samples a smoothstep curve, not a two-stop ramp', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_fadeOverList()));

    final box = tester.widget<DecoratedBox>(
      find.descendant(of: _overlayOpacity, matching: find.byType(DecoratedBox)),
    );
    final gradient =
        (box.decoration as BoxDecoration).gradient! as LinearGradient;

    expect(gradient.stops, [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]);
    final alphas = [for (final color in gradient.colors) color.a];
    expect(alphas.first, 1.0);
    expect(alphas.last, 0.0);
    // Interior samples follow smoothstep 3t² − 2t³.
    expect(alphas[1], closeTo(0.896, 0.005));
    expect(alphas[2], closeTo(0.648, 0.005));
    expect(alphas[3], closeTo(0.352, 0.005));
    expect(alphas[4], closeTo(0.104, 0.005));
  });

  testWidgets('the overlay never intercepts taps in the fade band', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_app(_fadeOverList(onFirstRowTap: () => taps++)));

    // The first row sits inside the 40px overlay band; the tap must
    // reach it through the IgnorePointer.
    await tester.tapAt(
      tester.getTopLeft(find.byType(MobileTopScrollFade)) +
          const Offset(40, 10),
    );
    expect(taps, 1);
  });
}
