import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_capture.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';

void main() {
  test('comparison scenarios have stable unique IDs', () {
    final ids = figmaCompareScenarios.map((scenario) => scenario.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids,
      containsAll(<String>[
        'pay-recipient',
        'pay-recipient-new-address',
        'pay-add-contact',
        'pay-in-progress',
        'pay-completed',
      ]),
    );
  });

  test('window capture path stays beside the Flutter content capture', () {
    expect(
      figmaCompareWindowCapturePath('/tmp/pay-recipient/content.png'),
      '/tmp/pay-recipient/content.window.png',
    );
    expect(
      figmaCompareWindowCapturePath('/tmp/pay-recipient/content'),
      '/tmp/pay-recipient/content.window.png',
    );
  });

  for (final scenario in figmaCompareScenarios) {
    testWidgets('${scenario.id} renders at the desktop comparison viewport', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        FigmaCompareApp(
          scenario: scenario,
          themeMode: ThemeMode.dark,
          captureBoundaryKey: boundaryKey,
        ),
      );
      await tester.pump();

      expect(boundaryKey.currentContext, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
