import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';
import 'package:zxing2/qrcode.dart';

// An independently generated mainnet Orchard + Sapling Unified Address.
// This is the longest address shape Vizor normally renders, so it exercises a
// denser QR grid than an Orchard-only Keystone or transparent address.
const _softwareUnifiedAddress =
    'u1flce76a85e0zvdtrqaqj59mdk2mv35d074lafaeej5s09qjm4vflc9gndayyxt'
    '37v6tekfgram4p9209ygugkz7es438hc9gsujwmcm0trr7zt5lcz8xmpfg9rqyfyzn'
    'c83ax697lc5ur3nem8wwyen732wemtxcg6lxr4n2agm437m2';

void main() {
  testWidgets('receive QR decodes at every quarter-turn rotation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: const Center(
            child: ReceiveQrSurface(
              address: _softwareUnifiedAddress,
              size: 260,
              paddingX: 16,
              paddingY: 24,
              type: ReceiveAddressType.shielded,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final renderedQr = tester.widget<RawImage>(find.byType(RawImage)).image!;
    final rgba = await renderedQr.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);

    // The shielded QR is white-on-black. Composite its potentially transparent
    // quiet-zone pixels onto the same black backing used by the receive card.
    final uprightPixels = _rgbPixelsOnBlack(
      rgba!,
      renderedQr.width,
      renderedQr.height,
    );

    for (var quarterTurns = 0; quarterTurns < 4; quarterTurns++) {
      final pixels = _rotateSquare(
        uprightPixels,
        renderedQr.width,
        quarterTurns,
      );
      final decoded = _decodeQr(pixels, renderedQr.width);

      expect(
        decoded,
        _softwareUnifiedAddress,
        reason: 'QR failed to decode at ${quarterTurns * 90} degrees',
      );
    }
  });
}

Int32List _rgbPixelsOnBlack(ByteData rgba, int width, int height) {
  final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
  final pixels = Int32List(width * height);

  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    final alpha = bytes[offset + 3];
    final red = bytes[offset] * alpha ~/ 255;
    final green = bytes[offset + 1] * alpha ~/ 255;
    final blue = bytes[offset + 2] * alpha ~/ 255;
    pixels[i] = (red << 16) | (green << 8) | blue;
  }

  return pixels;
}

Int32List _rotateSquare(Int32List source, int size, int quarterTurns) {
  if (quarterTurns == 0) {
    return source;
  }

  final rotated = Int32List(source.length);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final (rotatedX, rotatedY) = switch (quarterTurns) {
        1 => (size - 1 - y, x),
        2 => (size - 1 - x, size - 1 - y),
        3 => (y, size - 1 - x),
        _ => throw ArgumentError.value(quarterTurns, 'quarterTurns'),
      };
      rotated[rotatedY * size + rotatedX] = source[y * size + x];
    }
  }

  return rotated;
}

String _decodeQr(Int32List pixels, int size) {
  final source = RGBLuminanceSource(size, size, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  ReaderException? lastError;

  // Vizor's shielded QR is inverted (light modules on a dark surface), but
  // trying both polarities keeps this test valid if its colors change later.
  for (final candidate in [source, source.invert()]) {
    try {
      return QRCodeReader()
          .decode(BinaryBitmap(HybridBinarizer(candidate)), hints: hints)
          .text;
    } on ReaderException catch (error) {
      lastError = error;
    }
  }

  throw lastError ?? StateError('QR decoder returned no result');
}
