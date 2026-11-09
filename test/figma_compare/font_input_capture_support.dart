import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// Reuses the registered account-personalisation fixture, with representative
/// names, memo-like words and standalone jamo that exceeded the UI-only subset.
void runFontInputCaptures({required bool mobile, required String output}) {
  final platform = mobile ? 'mobile' : 'desktop';
  final size = mobile ? const Size(393, 852) : const Size(1080, 720);
  for (final language in [AppLanguage.ko, AppLanguage.zh]) {
    final text = language == AppLanguage.ko ? '김민수 ㅋㅋㅠㅠ 힣' : '王芳 李娜 朋友';
    for (final theme in [ThemeMode.dark, ThemeMode.light]) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: mobile
            ? AppFormFactor.mobile
            : AppFormFactor.desktop,
        defaultLogicalSize: size,
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: mobile ? 'mobile-customise-account' : 'customise-account',
          themeMode: theme,
          language: language,
          outputPath:
              '$output/$platform-customise.${language.tag}.${theme.name}.png',
          logicalSize: size,
          pixelRatio: 1,
        ),
        beforeCapture: (tester) async {
          final field = find.byType(EditableText);
          expect(field, findsOneWidget);
          expect(
            tester.widget<EditableText>(field).style.fontFamilyFallback,
            fontFamilyFallbackFor(language.locale),
          );
          // Set the deterministic fixture's controller without an OS keyboard
          // or focus/caret animation changing the app-content screenshot.
          tester.widget<EditableText>(field).controller.text = text;
          await tester.pump();
          expect(tester.widget<EditableText>(field).controller.text, text);
        },
      );
    }
  }
}
