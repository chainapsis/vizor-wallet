@Tags(['mobile', 'figma-capture'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// Reproduce the actual edit sheet's validation through its normal save action.
/// ALLOW_ERRORS is only for recording the pre-fix comparison images.
void main() {
  const output = String.fromEnvironment('ACCOUNT_EDIT_REVIEW_OUTPUT');
  const allowErrors = bool.fromEnvironment('ACCOUNT_EDIT_REVIEW_ALLOW_ERRORS');
  if (output.isEmpty) return;

  final cases = [
    for (final scale in [1.0, 1.5, 2.0])
      for (final error in ['required', 'length'])
        (scale: scale, error: error, language: AppLanguage.en, keyboard: false),
    (scale: 1.0, error: 'none', language: AppLanguage.en, keyboard: false),
    for (final language in [AppLanguage.ko, AppLanguage.zh])
      (scale: 2.0, error: 'length', language: language, keyboard: false),
    (scale: 2.0, error: 'length', language: AppLanguage.en, keyboard: true),
  ];
  for (final sample in cases) {
    final percent = (sample.scale * 100).round();
    final name =
        '${sample.language.tag}-${sample.error}-$percent'
        '${sample.keyboard ? '-keyboard-320' : ''}';
    final size = Size(sample.keyboard ? 320 : 360, 800);
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.mobile,
      defaultLogicalSize: size,
      defaultPixelRatio: 3,
      mobilePlatform: TargetPlatform.android,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'mobile-account-edit-scale-review',
        themeMode: ThemeMode.light,
        language: sample.language,
        outputPath: '$output/$name.png',
        logicalSize: size,
        pixelRatio: 3,
      ),
      beforeCapture: (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = sample.scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final field = find.byKey(const ValueKey('mobile_account_edit_name'));
        expect(field, findsOneWidget);
        if (sample.error != 'none') {
          await tester.enterText(
            field,
            sample.error == 'required' ? '   ' : 'abcdefghijklmnopqrstu',
          );
          if (sample.keyboard) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 900);
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpAndSettle();
          }
          final save = find.byKey(const ValueKey('mobile_account_edit_save'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final l10n = tester.element(field).l10n;
        final message = sample.error == 'required'
            ? l10n.accountNameRequired
            : l10n.accountNameTooLong;
        final metrics = <String, Object?>{};
        if (sample.error != 'none') {
          final finder = find.text(message);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
            locale: paragraph.locale,
          )..layout(maxWidth: paragraph.size.width);
          metrics.addAll({
            'text': message,
            'allocatedHeight': paragraph.size.height,
            'naturalHeight': painter.height,
            'paintedRect': tester.getRect(finder).toString(),
            'lineCount': painter.computeLineMetrics().length,
          });
          if (!allowErrors) {
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.size.height, greaterThanOrEqualTo(painter.height));
            final viewport = tester.getRect(
              find.byKey(const ValueKey('mobile_modal_body_scroll')),
            );
            expect(viewport.contains(tester.getTopLeft(finder)), isTrue);
            expect(viewport.contains(tester.getBottomRight(finder)), isTrue);
          }
          painter.dispose();
        }
        final exceptions = <String>[];
        Object? exception;
        while ((exception = tester.takeException()) != null) {
          exceptions.add(exception.toString());
        }
        File('$output/$name.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'language': sample.language.tag,
            'scale': sample.scale,
            'logicalSize': [size.width, size.height],
            'simulatedKeyboardInset': sample.keyboard ? 300 : 0,
            'exceptions': exceptions,
            ...metrics,
          }),
        );
        if (!allowErrors) expect(exceptions, isEmpty);
      },
    );
  }
}
