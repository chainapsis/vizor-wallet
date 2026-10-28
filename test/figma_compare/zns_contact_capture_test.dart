@Tags(['figma-capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// Desktop contact form with a Zcash name typed as the address. Run with
/// `--dart-define=ZNS_CAPTURE_DIR=<absolute dir>` to write the PNGs.
void main() {
  const output = String.fromEnvironment('ZNS_CAPTURE_DIR');
  for (final (name, address) in [
    ('zns-desktop-contact-resolved', 'alice.zcash'),
    ('zns-desktop-contact-not-registered', 'nobody.zcash'),
  ]) {
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.desktop,
      defaultLogicalSize: const Size(1080, 720),
      defaultPixelRatio: 1,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'zns-desktop-contacts',
        themeMode: ThemeMode.dark,
        logicalSize: const Size(1080, 720),
        pixelRatio: 1,
        outputPath: output.isEmpty ? '' : '$output/$name.png',
      ),
      beforeCapture: (tester) async {
        await tester.tap(
          find.byKey(const ValueKey('address_book_add_contact_button')),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(
          find.byKey(const ValueKey('address_book_contact_label_field')),
          'Alice',
        );
        await tester.enterText(
          find.byKey(const ValueKey('address_book_contact_address_field')),
          address,
        );
        await tester.pump();
        // Past the lookup debounce, then one frame for the answer.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
      },
    );
  }
}
