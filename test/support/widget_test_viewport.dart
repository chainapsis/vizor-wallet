import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps render constraints and the View metrics read by adaptive layouts in
/// agreement, including when a test resizes an already mounted app.
Future<void> setWidgetTestViewport(
  WidgetTester tester,
  Size logicalSize, {
  double? devicePixelRatio,
}) async {
  if (devicePixelRatio != null) {
    tester.view.devicePixelRatio = devicePixelRatio;
  }
  tester.view.physicalSize = logicalSize * tester.view.devicePixelRatio;
  await tester.binding.setSurfaceSize(logicalSize);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
