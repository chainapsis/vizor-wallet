import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Measure the full message, independently of any widget line limit, and check
/// its painted bounds against the actual row (including FittedBox transforms).
void expectUnclippedRowText(WidgetTester tester, Finder finder, Rect row) {
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final full = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
  )..layout(maxWidth: paragraph.size.width);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.size.height, greaterThanOrEqualTo(full.height));
  final painted = tester.getRect(finder);
  final bounds = row.inflate(0.01);
  expect(bounds.contains(painted.topLeft), isTrue);
  expect(bounds.contains(painted.bottomRight), isTrue);
  full.dispose();
}
