import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] with RenderFlex overflow reports dropped. At large text sizes
/// the fixed-size mobile nav and amount cards overflow, which is not what a
/// test of a wrapping message is checking. Other errors still fail the test.
Future<void> ignoringFlexOverflows(Future<void> Function() body) async {
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.exceptionAsString().contains('A RenderFlex overflowed')) {
      onError?.call(details);
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = onError;
  }
}

/// Scrolls [text] into view and expects every line of it on screen: no line
/// limit cut it short and no edge of the view clips it.
Future<void> expectTextFullyShown(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(
    tester.renderObject<RenderParagraph>(finder).didExceedMaxLines,
    isFalse,
  );
  final view =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  final shown = tester.getRect(finder);
  expect(view.intersect(shown), shown);
}
