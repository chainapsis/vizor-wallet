import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

void main() {
  for (final scenario in [
    'caps-lock-unlock',
    'caps-lock-set-password',
    'caps-lock-confirm-password',
    'caps-lock-settings',
    'caps-lock-remove-account',
  ]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.desktop,
      defaultLogicalSize: const Size(1080, 720),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: scenario,
        themeMode: ThemeMode.dark,
        outputPath: '',
        logicalSize: const Size(1080, 720),
        pixelRatio: 1,
      ),
      beforeCapture: (tester) async {
        final warning = find.text('Caps Lock is on');
        expect(warning, findsOneWidget);
        final bubble = tester.getRect(
          find.ancestor(of: warning, matching: find.byType(Container)).first,
        );
        // Compare painted glyphs, not the label's expanded layout box.
        for (final element in find.byType(RichText).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          final text = paragraph.text.toPlainText();
          if (text.isEmpty || text == 'Caps Lock is on') continue;
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length),
          )) {
            final ink = box.toRect().shift(
              paragraph.localToGlobal(Offset.zero),
            );
            expect(
              bubble.overlaps(ink),
              isFalse,
              reason: 'Warning overlaps "$text" in $scenario',
            );
          }
        }
      },
    );
  }
}
