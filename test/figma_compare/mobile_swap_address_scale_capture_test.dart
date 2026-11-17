@Tags(['mobile', 'figma-capture'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// ALLOW_ERRORS records pre-fix evidence only; regular captures reject clipping.
void main() {
  const output = String.fromEnvironment('SWAP_ADDRESS_REVIEW_OUTPUT');
  const allowErrors = bool.fromEnvironment('SWAP_ADDRESS_REVIEW_ALLOW_ERRORS');
  if (output.isEmpty) return;

  final cases = [
    for (final scale in [1.0, 1.5, 2.0])
      for (final feedback in ['error', 'contact'])
        (
          scale: scale,
          feedback: feedback,
          language: AppLanguage.en,
          keyboard: false,
          refund: false,
        ),
    (
      scale: 1.0,
      feedback: 'none',
      language: AppLanguage.en,
      keyboard: false,
      refund: false,
    ),
    for (final language in [AppLanguage.ko, AppLanguage.zh])
      (
        scale: 2.0,
        feedback: 'error',
        language: language,
        keyboard: false,
        refund: false,
      ),
    (
      scale: 2.0,
      feedback: 'error',
      language: AppLanguage.en,
      keyboard: true,
      refund: false,
    ),
    (
      scale: 2.0,
      feedback: 'error',
      language: AppLanguage.en,
      keyboard: false,
      refund: true,
    ),
  ];
  for (final sample in cases) {
    final percent = (sample.scale * 100).round();
    final name =
        '${sample.language.tag}-${sample.feedback}-$percent'
        '${sample.refund ? '-refund' : ''}'
        '${sample.keyboard ? '-keyboard-320' : ''}';
    final size = Size(sample.keyboard ? 320 : 360, 800);
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.mobile,
      defaultLogicalSize: size,
      defaultPixelRatio: 3,
      mobilePlatform: TargetPlatform.android,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: sample.refund
            ? 'mobile-swap-refund-address-scale-review'
            : 'mobile-swap-address-scale-review',
        themeMode: ThemeMode.light,
        language: sample.language,
        outputPath: '$output/$name.png',
        logicalSize: size,
        pixelRatio: 3,
      ),
      beforeCapture: (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = sample.scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (sample.keyboard) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 900);
          addTearDown(tester.view.resetViewInsets);
        }
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('swap_destination_field'));
        expect(field, findsOneWidget);
        if (sample.feedback != 'none') {
          await tester.enterText(
            field,
            sample.feedback == 'error'
                ? 'invalid'
                : '0x52908400098527886e0f7030069857d2e4169ee7',
          );
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final metrics = <String, Object?>{};
        if (sample.feedback != 'none') {
          final finder = sample.feedback == 'error'
              ? find.byKey(const ValueKey('swap_destination_format_error'))
              : find.descendant(
                  of: find.byKey(
                    const ValueKey('swap_destination_contact_match'),
                  ),
                  matching: find.byType(Text),
                );
          // Center keyboard-constrained feedback clear of the scroll-edge fade.
          await Scrollable.ensureVisible(
            tester.element(finder),
            alignment: sample.keyboard ? 0.5 : 0,
          );
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
            locale: paragraph.locale,
          )..layout(maxWidth: paragraph.size.width);
          metrics.addAll({
            'text': paragraph.text.toPlainText(),
            'allocatedHeight': paragraph.size.height,
            'naturalHeight': painter.height,
            'lineCount': painter.computeLineMetrics().length,
            'paintedRect': tester.getRect(finder).toString(),
          });
          if (!allowErrors) {
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.size.height, greaterThanOrEqualTo(painter.height));
            final viewport = tester.getRect(
              find.byKey(const ValueKey('mobile_modal_body_scroll')),
            );
            expect(
              viewport.top,
              lessThanOrEqualTo(tester.getTopLeft(finder).dy),
            );
            expect(
              viewport.bottom,
              greaterThanOrEqualTo(tester.getBottomRight(finder).dy),
            );
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
