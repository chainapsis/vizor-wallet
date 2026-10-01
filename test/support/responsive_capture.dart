import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Checks only the text surfaces selected by a screen's readability contract.
/// Scrolling, ancestor clipping, content counts, and taps remain screen-owned.
/// Texts in [ellipsisAllowed] may truncate but must still have enough height.
List<String> readableTextIssues(
  Iterable<Finder> surfaces, {
  Set<String> ellipsisAllowed = const {},
}) {
  final elements = <Element>{};
  for (final surface in surfaces) {
    elements.addAll(surface.evaluate().where((e) => e.widget is RichText));
    elements.addAll(
      find.descendant(of: surface, matching: find.byType(RichText)).evaluate(),
    );
  }
  return [
    for (final element in elements)
      ..._paragraphIssues(
        element.findRenderObject()! as RenderParagraph,
        ellipsisAllowed,
      ),
  ];
}

List<String> _paragraphIssues(
  RenderParagraph paragraph,
  Set<String> ellipsisAllowed,
) {
  final text = paragraph.text.toPlainText();
  final allocatedHeight = paragraph.size.height;
  final intrinsicHeight = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
  return [
    if (paragraph.didExceedMaxLines && !ellipsisAllowed.contains(text))
      'Truncated text: $text',
    if (intrinsicHeight > allocatedHeight + 0.5)
      'Text needs $intrinsicHeight px but has $allocatedHeight px of height: $text',
  ];
}

/// Measurements and image export share an output directory, not an execution
/// dependency. Disable only PNG export with RESPONSIVE_SAVE_IMAGES=false.
class ResponsiveCaptureOutput {
  ResponsiveCaptureOutput(
    String directory, {
    this.saveImages = const bool.fromEnvironment(
      'RESPONSIVE_SAVE_IMAGES',
      defaultValue: true,
    ),
  }) : directory = Directory(directory)..createSync(recursive: true);

  final Directory directory;
  final bool saveImages;

  void writeJson(String name, Map<String, Object?> data) => File(
    '${directory.path}/$name.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));

  Future<void> capturePng(
    WidgetTester tester,
    GlobalKey boundaryKey,
    String name,
  ) async {
    if (!saveImages) return;
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${directory.path}/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }
}
