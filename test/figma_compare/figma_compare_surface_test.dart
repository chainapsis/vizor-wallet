import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';

void main() {
  for (final outside in [false, true]) {
    testWidgets(
      'capture reproduces app-level text inheritance (outside=$outside)',
      (tester) async {
        await tester.pumpWidget(
          FigmaCompareApp(
            scenario: FigmaCompareScenario(
              id: 'text-style-probe',
              description: 'Capture surface style boundary',
              outsideScaffold: outside,
              builder: (_) => const Text('Style probe'),
            ),
            themeMode: ThemeMode.light,
            captureBoundaryKey: GlobalKey(),
          ),
        );
        final text = tester.widget<RichText>(
          find.descendant(
            of: find.text('Style probe'),
            matching: find.byType(RichText),
          ),
        );
        final style = (text.text as TextSpan).style!;
        expect(
          style.decoration?.contains(TextDecoration.underline) ?? false,
          outside,
        );
        if (outside) expect(style.decorationColor, const Color(0xFFFFFF00));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
