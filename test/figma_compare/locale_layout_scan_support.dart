import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

/// Renders every registered scenario in every language and appends one JSON
/// line per render to `LOCALE_SCAN_REPORT`: the first layout exception (a
/// RenderFlex overflow, for example) and the texts cut off by `maxLines` or a
/// single line. Compare a translation's lines with English to find the
/// screens it breaks. `LOCALE_SCAN_SCENARIOS` limits the run to ids starting
/// with one of its comma-separated prefixes, and `LOCALE_SCAN_OUTPUT` (a
/// directory) also writes `<scenario>.<language>.png` for each render.
void runLocaleLayoutScan({
  required AppFormFactor formFactor,
  required Size logicalSize,
}) {
  const reportPath = String.fromEnvironment('LOCALE_SCAN_REPORT');
  const prefixText = String.fromEnvironment('LOCALE_SCAN_SCENARIOS');
  const outputDirectory = String.fromEnvironment('LOCALE_SCAN_OUTPUT');
  final prefixes = [
    for (final prefix in prefixText.split(','))
      if (prefix.trim().isNotEmpty) prefix.trim(),
  ];
  final report = reportPath.isEmpty ? null : File(reportPath);

  for (final scenario in figmaCompareScenarios) {
    final supported = switch (formFactor) {
      AppFormFactor.desktop => scenario.desktop,
      AppFormFactor.mobile => scenario.mobile,
    };
    if (!supported) continue;
    if (prefixes.isNotEmpty && !prefixes.any(scenario.id.startsWith)) {
      continue;
    }
    for (final language in AppLanguage.values) {
      runFigmaCompareCaptureTest(
        expectedFormFactor: formFactor,
        defaultLogicalSize: logicalSize,
        defaultPixelRatio: 1,
        overrideConfiguration: FigmaCompareConfiguration(
          scenarioId: scenario.id,
          themeMode: ThemeMode.dark,
          outputPath: outputDirectory.isEmpty
              ? ''
              : '$outputDirectory/${scenario.id}.${language.tag}.png',
          logicalSize: logicalSize,
          pixelRatio: 1,
          language: language,
        ),
        beforeCapture: (tester) async {
          final exception = tester.takeException();
          final record = {
            'scenario': scenario.id,
            'language': language.tag,
            'exception': exception?.toString().split('\n').first,
            'cutOff': _cutOffTexts(tester),
            'overflowingFlexes': _overflowingFlexes(tester),
          };
          report?.writeAsStringSync(
            '${jsonEncode(record)}\n',
            mode: FileMode.append,
            flush: true,
          );
        },
      );
    }
  }
}

List<String> _cutOffTexts(WidgetTester tester) {
  return [
    for (final paragraph
        in tester.allRenderObjects.whereType<RenderParagraph>())
      if (paragraph.hasSize && _isCutOff(paragraph))
        paragraph.text.toPlainText(includeSemanticsLabels: false),
  ];
}

// Creator chains of the Rows and Columns whose children do not fit, so the
// report points at the widget to fix.
List<String> _overflowingFlexes(WidgetTester tester) {
  final chains = <String>[];
  for (final flex in tester.allRenderObjects.whereType<RenderFlex>()) {
    if (!flex.hasSize) continue;
    var extent = flex.spacing * (flex.childCount - 1).clamp(0, 1 << 20);
    var child = flex.firstChild;
    while (child != null) {
      if (child.hasSize) {
        extent += flex.direction == Axis.vertical
            ? child.size.height
            : child.size.width;
      }
      child = flex.childAfter(child);
    }
    final available = flex.direction == Axis.vertical
        ? flex.size.height
        : flex.size.width;
    if (extent <= available + 0.5) continue;
    final creator = flex.debugCreator;
    final chain = creator is DebugCreator
        ? creator.element.debugGetCreatorChain(12)
        : flex.toStringShort();
    chains.add('${(extent - available).toStringAsFixed(1)}px: $chain');
  }
  return chains;
}

bool _isCutOff(RenderParagraph paragraph) {
  if (paragraph.didExceedMaxLines) return true;
  if (paragraph.softWrap) return false;
  final full = paragraph.getMaxIntrinsicWidth(double.infinity);
  return full > paragraph.size.width + 0.5;
}
