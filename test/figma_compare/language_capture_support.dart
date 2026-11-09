import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'capture_locale_fonts.dart';
import 'figma_compare_capture_support.dart';

void runLanguageCaptures({required bool mobile, required String output}) {
  final platform = mobile ? 'mobile' : 'desktop';
  final size = mobile ? const Size(393, 852) : const Size(1080, 720);
  for (final screen in ['welcome', 'settings']) {
    for (final picker in [false, true]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: mobile
            ? AppFormFactor.mobile
            : AppFormFactor.desktop,
        defaultLogicalSize: size,
        defaultPixelRatio: 2,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: '$platform-language-$screen',
          themeMode: ThemeMode.dark,
          language: AppLanguage.en,
          outputPath: '$output/$platform-$screen${picker ? '-picker' : ''}.png',
          logicalSize: size,
          pixelRatio: 2,
        ),
        beforeCapture: (tester) async {
          // Even English pickers display Korean and Chinese language names.
          await loadCaptureLocaleFonts(AppLanguage.ko);
          await tester.pump();
          final key = screen == 'welcome'
              ? (mobile ? 'mobile_welcome_language' : 'welcome_language_button')
              : (mobile
                    ? 'mobile_settings_language_row'
                    : 'settings_language_row');
          final entry = find.byKey(ValueKey(key));
          if (mobile && screen == 'settings') {
            await tester.scrollUntilVisible(entry, 250);
          }
          expect(entry, findsOneWidget);
          if (screen == 'settings') {
            await Scrollable.ensureVisible(
              tester.element(entry),
              alignment: 0.5,
            );
            await tester.pump();
          }
          if (picker) {
            await tester.tap(entry);
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 400));
            }
            expect(
              find.byKey(
                ValueKey(
                  mobile ? 'mobile_language_option_ko' : 'language_option_ko',
                ),
              ),
              findsOneWidget,
            );
          }
        },
      );
    }
  }
}
