@Tags(['figma-capture'])
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

/// Capture the real screen layouts at larger text sizes. The optional
/// UI_SCALE_REVIEW_ALLOW_ERRORS flag records unfixed diagnostics for comparison;
/// normal captures reject overflow and clipped amount/label rows.
void main() {
  const output = String.fromEnvironment('UI_SCALE_REVIEW_OUTPUT');
  const allowErrors = bool.fromEnvironment('UI_SCALE_REVIEW_ALLOW_ERRORS');
  if (output.isEmpty) return;
  for (final screen in ['pay', 'request', 'memo']) {
    for (final scale in [1.0, 1.5, 2.0]) {
      final percent = (scale * 100).round();
      runFigmaCompareCaptureTest(
        expectedFormFactor: AppFormFactor.mobile,
        defaultLogicalSize: const Size(360, 800),
        defaultPixelRatio: 3,
        mobilePlatform: TargetPlatform.android,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: 'mobile-ui-scale-review-$screen',
          themeMode: ThemeMode.dark,
          language: AppLanguage.en,
          outputPath: '$output/$screen-$percent.png',
          logicalSize: const Size(360, 800),
          pixelRatio: 3,
        ),
        beforeCapture: (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final exceptions = <String>[];
          Object? exception;
          while ((exception = tester.takeException()) != null) {
            exceptions.add(exception.toString());
          }
          final paragraphs = <Map<String, Object?>>[];
          for (final paragraph
              in tester.allRenderObjects.whereType<RenderParagraph>()) {
            if (!paragraph.hasSize) continue;
            final painter = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              maxLines: paragraph.maxLines,
            )..layout(maxWidth: paragraph.size.width);
            final offset = paragraph.localToGlobal(Offset.zero);
            paragraphs.add({
              'text': paragraph.text.toPlainText(),
              'x': offset.dx,
              'y': offset.dy,
              'width': paragraph.size.width,
              'allocatedHeight': paragraph.size.height,
              'naturalHeight': painter.height,
              'textScale18': paragraph.textScaler.scale(18),
            });
            painter.dispose();
          }
          final editables = [
            for (final editable
                in tester.allRenderObjects.whereType<RenderEditable>())
              if (editable.hasSize)
                {
                  'text': editable.text?.toPlainText(),
                  'allocatedHeight': editable.size.height,
                  'preferredLineHeight': editable.preferredLineHeight,
                },
          ];
          Rect? rectFor(String key) {
            final finder = find.byKey(ValueKey(key));
            return finder.evaluate().isEmpty ? null : tester.getRect(finder);
          }

          final hit = rectFor('mobile_send_memo_scrollbar');
          final thumb = rectFor('mobile_send_memo_scrollbar_thumb');
          List<double>? rectJson(Rect? rect) => rect == null
              ? null
              : [rect.left, rect.top, rect.width, rect.height];
          File('$output/$screen-$percent.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert({
              'screen': screen,
              'textScale': scale,
              'logicalSize': [360, 800],
              'devicePixelRatio': 3,
              'exceptions': exceptions,
              'paragraphs': paragraphs,
              'editables': editables,
              'scrollbarHitRect': rectJson(hit),
              'scrollbarThumbRect': rectJson(thumb),
            }),
          );
          if (!allowErrors) {
            expect(exceptions, isEmpty, reason: '$screen at $percent%');
            if (screen == 'pay') expect(editables, isNotEmpty);
            for (final editable in editables) {
              expect(
                editable['allocatedHeight'] as double,
                greaterThanOrEqualTo(editable['preferredLineHeight'] as double),
                reason: '$screen input at $percent%',
              );
            }
            for (final paragraph in paragraphs) {
              final text = paragraph['text'] as String;
              if (text == 'Message' ||
                  text.endsWith('/512') ||
                  text == 'ZEC' ||
                  text.startsWith(r'$')) {
                expect(
                  paragraph['allocatedHeight'] as double,
                  greaterThanOrEqualTo(
                    (paragraph['naturalHeight'] as double) - 1,
                  ),
                  reason: '$text at $percent%',
                );
              }
            }
            if (screen == 'memo') expect(hit!.width, greaterThanOrEqualTo(24));
          }
        },
      );
    }
  }
}
