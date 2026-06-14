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

Widget _fadeOverList({
  ScrollController? controller,
  void Function()? onFirstRowTap,
}) {
  return MobileTopScrollFade(
    child: ListView(
      controller: controller,
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

Finder get _overlayPositioned => find.descendant(
  of: find.byType(MobileTopScrollFade),
  matching: find.byType(Positioned),
);

Finder get _overlayBox => find.descendant(
  of: find.byType(MobileTopScrollFade),
  matching: find.byType(DecoratedBox),
);

void main() {
  testWidgets('grows the fade band across the first 24px of scroll', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_fadeOverList(controller: controller)));

    expect(tester.widget<Positioned>(_overlayPositioned).height, 0);

    controller.jumpTo(AppSpacing.md / 2);
    await tester.pump();
    expect(
      tester.widget<Positioned>(_overlayPositioned).height,
      closeTo(16, 0.005),
    );

    controller.jumpTo(AppSpacing.md);
    await tester.pump();
    expect(
      tester.widget<Positioned>(_overlayPositioned).height,
      AppSpacing.base,
    );

    controller.jumpTo(0);
    await tester.pump();
    expect(tester.widget<Positioned>(_overlayPositioned).height, 0);
  });

  testWidgets('the fade keeps the top edge opaque while scaling the tail', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_fadeOverList(controller: controller)));

    LinearGradient gradient() {
      final box = tester.widget<DecoratedBox>(_overlayBox);
      return (box.decoration as BoxDecoration).gradient! as LinearGradient;
    }

    const expectedStops = [
      0.0,
      0.071,
      0.143,
      0.214,
      0.286,
      0.357,
      0.429,
      0.5,
      0.571,
      0.643,
      0.714,
      0.786,
      0.857,
      0.929,
      1.0,
    ];
    const expectedTailAlphas = [
      0.985,
      0.945,
      0.882,
      0.802,
      0.708,
      0.606,
      0.5,
      0.394,
      0.292,
      0.198,
      0.118,
      0.055,
      0.015,
      0.0,
    ];

    var currentGradient = gradient();
    expect(currentGradient.stops, expectedStops);
    var alphas = [for (final color in currentGradient.colors) color.a];
    expect(alphas.first, 1.0);
    expect(alphas.last, 0.0);
    for (final alpha in alphas.skip(1)) {
      expect(alpha, 0.0);
    }

    controller.jumpTo(AppSpacing.md / 2);
    await tester.pump();
    currentGradient = gradient();
    alphas = [for (final color in currentGradient.colors) color.a];
    expect(alphas.first, 1.0);
    for (var i = 0; i < expectedTailAlphas.length; i++) {
      expect(alphas[i + 1], closeTo(expectedTailAlphas[i] * 0.5, 0.005));
    }

    controller.jumpTo(AppSpacing.md);
    await tester.pump();
    currentGradient = gradient();
    alphas = [for (final color in currentGradient.colors) color.a];
    expect(alphas.first, 1.0);
    // Interior samples follow smoothstep 3t² − 2t³ at full strength.
    for (var i = 0; i < expectedTailAlphas.length; i++) {
      expect(alphas[i + 1], closeTo(expectedTailAlphas[i], 0.005));
    }
  });

  testWidgets('the overlay never intercepts taps in the fade band', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_app(_fadeOverList(onFirstRowTap: () => taps++)));

    // The first row sits inside the 32px overlay band; the tap must
    // reach it through the IgnorePointer.
    await tester.tapAt(
      tester.getTopLeft(find.byType(MobileTopScrollFade)) +
          const Offset(40, 10),
    );
    expect(taps, 1);
  });
}
