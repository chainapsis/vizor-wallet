import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../figma_compare/figma_compare_font_loader.dart';
import '../support/wb_gallery_harness.dart';

const _output = String.fromEnvironment('VIZOR_FLOW_CAPTURE_DIR');

void setUpFlowCaptures() {
  if (_output.isNotEmpty) setUpAll(loadFigmaCompareFonts);
}

Future<void> captureFlowState(WidgetTester tester, String name) async {
  if (_output.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(kWbCaptureKey),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return await image.toByteData(format: ui.ImageByteFormat.png);
    } finally {
      image.dispose();
    }
  });
  Directory(_output).createSync(recursive: true);
  File('$_output/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}
