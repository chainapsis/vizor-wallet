@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// Mobile contact sheet with a Zcash name typed as the address. Run with
/// `--dart-define=ZNS_CAPTURE_DIR=<absolute dir>` to write the PNGs.
void main() {
  const output = String.fromEnvironment('ZNS_CAPTURE_DIR');
  for (final (name, address) in [
    ('zns-mobile-contact-resolved', 'alice.zec'),
    ('zns-mobile-contact-not-registered', 'nobody.zcash'),
  ]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.mobile,
      defaultLogicalSize: const Size(393, 852),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'zns-mobile-contacts',
        themeMode: ThemeMode.dark,
        logicalSize: const Size(393, 852),
        pixelRatio: 1,
        outputPath: output.isEmpty ? '' : '$output/$name.png',
      ),
      beforeCapture: (tester) async {
        await tester.tap(
          find.byKey(const ValueKey('mobile_contacts_add_empty')),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.enterText(
          find.byKey(const ValueKey('mobile_address_book_label')),
          'Alice',
        );
        await tester.enterText(
          find.byKey(const ValueKey('mobile_address_book_address')),
          address,
        );
        await tester.pump();
        // Past the lookup debounce, then one frame for the answer.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  }
}
