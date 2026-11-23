import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zxing2/qrcode.dart' as zxing;

import 'voting_qr_frames.dart';

/// Capture the real screen, not an isolated painter. Decoder and pixel checks
/// are independent of the production QR encoder, sizing and paint geometry.
/// Adapted from the multi-frame capture harness in PR #1260.
Future<void> checkVotingQrFrames(
  WidgetTester tester,
  GlobalKey boundaryKey,
  double ratio, {
  required Finder qr,
  double minimumPatternSize = 0,
}) async {
  final viewport = RenderAbstractViewport.maybeOf(tester.renderObject(qr));
  if (viewport != null) {
    await tester.ensureVisible(qr);
    await tester.pump();
    final box = viewport as RenderBox;
    final scrollBounds = box.localToGlobal(Offset.zero) & box.size;
    final qrRect = tester.getRect(qr);
    expect(scrollBounds.intersect(qrRect), qrRect);
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final rect = tester.getRect(qr).shift(-boundary.localToGlobal(Offset.zero));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(boundary.size.width));
  expect(rect.bottom, lessThanOrEqualTo(boundary.size.height));
  var smallestPattern = double.infinity;
  for (final expected in votingQrFrames) {
    final source = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: ratio);
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return zxing.RGBLuminanceSource(
          image.width,
          image.height,
          bytes.buffer.asInt32List(),
        ).crop(
          (rect.left * ratio).round(),
          (rect.top * ratio).round(),
          (rect.width * ratio).round(),
          (rect.height * ratio).round(),
        );
      } finally {
        image.dispose();
      }
    }))!;
    final bitmap = zxing.BinaryBitmap(zxing.HybridBinarizer(source));
    expect(zxing.QRCodeReader().decode(bitmap).text, expected);
    final patternSize = _checkPhysicalGrid(source) / ratio;
    if (patternSize < smallestPattern) smallestPattern = patternSize;
    expect(patternSize, greaterThanOrEqualTo(minimumPatternSize));
    await tester.pump(keystoneQrFrameInterval);
  }
  debugPrint(
    'QR ${rect.size} at ${ratio}x: ${votingQrFrames.length} frames decoded, '
    'smallest data pattern ${smallestPattern.toStringAsFixed(1)} logical px',
  );
}

int _checkPhysicalGrid(zxing.LuminanceSource source) {
  final width = source.width;
  final height = source.height;
  final pixels = source.getMatrix().buffer.asUint8List();
  var left = width, top = height, right = -1, bottom = -1;
  // Ignore the outermost pixel: the white card itself may start at a
  // fractional physical coordinate, independently of the black module grid.
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final p = pixels[y * width + x];
      if (p != 0 && p != 255) {
        fail('Gray module edge at ($x, $y): $p');
      }
      if (p == 0) {
        if (x < left) left = x;
        if (y < top) top = y;
        if (x > right) right = x;
        if (y > bottom) bottom = y;
      }
    }
  }
  final patternWidth = right - left + 1;
  expect(patternWidth, greaterThan(0));
  expect(bottom - top + 1, patternWidth);
  expect(patternWidth % votingQrModuleCount, 0);
  final pitch = patternWidth ~/ votingQrModuleCount;
  expect(pitch, greaterThanOrEqualTo(3));
  // Conservative allowance for rounding the capture's physical crop origin.
  for (final margin in [left, top, width - 1 - right, height - 1 - bottom]) {
    expect(margin, greaterThanOrEqualTo(4 * pitch - 1));
  }
  // Every run boundary and repeated row must match the integer module grid.
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      final p = pixels[y * width + x];
      if ((x - left) % pitch != 0 && p != pixels[y * width + x - 1]) {
        fail('Horizontal edge is off the module grid at ($x, $y)');
      }
      if ((y - top) % pitch != 0 && p != pixels[(y - 1) * width + x]) {
        fail('Vertical edge is off the module grid at ($x, $y)');
      }
    }
  }
  return patternWidth;
}
