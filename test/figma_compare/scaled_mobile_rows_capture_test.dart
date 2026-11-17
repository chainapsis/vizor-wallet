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

/// Baseline captures may record known clipping. Regular captures reject it.
void main() {
  const output = String.fromEnvironment('SCALED_ROWS_REVIEW_OUTPUT');
  const allowErrors = bool.fromEnvironment('SCALED_ROWS_REVIEW_ALLOW_ERRORS');
  if (output.isEmpty) return;
  final cases = [
    for (final surface in [
      'contact-chain',
      'swap-status-row',
      'pay-status-row',
    ])
      for (final scale in [1.0, 1.5, 2.0])
        (
          surface: surface,
          scale: scale,
          language: AppLanguage.en,
          narrow: false,
          keyboard: false,
        ),
    for (final surface in ['contact-long-chain', 'warning-status-row'])
      (
        surface: surface,
        scale: 2.0,
        language: AppLanguage.en,
        narrow: false,
        keyboard: false,
      ),
    for (final language in [AppLanguage.ko, AppLanguage.zh])
      for (final surface in ['contact-chain', 'swap-status-row'])
        (
          surface: surface,
          scale: 2.0,
          language: language,
          narrow: false,
          keyboard: false,
        ),
    for (final surface in ['contact-chain', 'swap-status-row'])
      (
        surface: surface,
        scale: 2.0,
        language: AppLanguage.en,
        narrow: true,
        keyboard: surface == 'contact-chain',
      ),
  ];
  for (final sample in cases) {
    final name =
        '${sample.surface}-${sample.language.tag}-${(sample.scale * 100).round()}'
        '${sample.narrow ? '-320' : ''}${sample.keyboard ? '-keyboard' : ''}';
    final size = Size(sample.narrow ? 320 : 360, 800);
    runFigmaCompareCaptureTest(
      expectedFormFactor: AppFormFactor.mobile,
      defaultLogicalSize: size,
      defaultPixelRatio: 3,
      mobilePlatform: TargetPlatform.android,
      overrideConfiguration: FigmaCompareConfiguration(
        scenarioId: 'mobile-${sample.surface}-scale-review',
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
        final contact = sample.surface.startsWith('contact');
        final l10n = tester.element(find.byType(Scaffold).last).l10n;
        final labels = contact
            ? [
                l10n.commonChainAndAddress,
                sample.surface == 'contact-long-chain'
                    ? 'Binance Smart Chain'
                    : 'Ethereum',
              ]
            : [
                l10n.swapStatusRowLabel,
                sample.surface == 'warning-status-row'
                    ? l10n.swapStatusBadgeNeedsAttention
                    : l10n.commonCompleted,
              ];
        final row = contact
            ? find.byKey(const ValueKey('mobile_pay_add_contact_chain_row'))
            : find.text(l10n.swapStatusRowLabel);
        await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
        await tester.pumpAndSettle();
        final metrics = <Map<String, Object?>>[];
        for (final label in labels) {
          final finder = find.text(label);
          expect(finder, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
            locale: paragraph.locale,
          )..layout(maxWidth: paragraph.size.width);
          metrics.add({
            'text': label,
            'allocatedHeight': paragraph.size.height,
            'naturalHeight': painter.height,
            'ellipsis': paragraph.didExceedMaxLines,
            'rect': tester.getRect(finder).toString(),
            'style': (paragraph.text as TextSpan).style.toString(),
            'baseline': painter.computeLineMetrics().first.baseline,
            'constraints': paragraph.constraints.toString(),
          });
          if (!allowErrors) {
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(paragraph.size.height, greaterThanOrEqualTo(painter.height));
          }
          painter.dispose();
        }
        final errors = <String>[];
        Object? error;
        while ((error = tester.takeException()) != null) {
          errors.add(error.toString());
        }
        File('$output/$name.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'surface': sample.surface,
            'scale': sample.scale,
            'language': sample.language.tag,
            'logicalSize': [size.width, size.height],
            'keyboardInset': sample.keyboard ? 300 : 0,
            'paragraphs': metrics,
            'exceptions': errors,
          }),
        );
        if (!allowErrors) expect(errors, isEmpty);
      },
    );
  }
}
