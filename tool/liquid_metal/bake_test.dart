// Bakes tool/liquid_metal/nu7.svg into the texture LiquidMetal reads with
// `preprocessed: true`, then convert it with the illustrations script:
//
//   fvm flutter test tool/liquid_metal/bake_test.dart
//   scripts/convert-illustrations-to-webp.py --apply
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/liquid_metal.dart';

import 'svg_path_image.dart';

const _size = int.fromEnvironment('SIZE', defaultValue: 1536);

void main() {
  testWidgets('bake the NU7 liquid metal texture', (tester) async {
    await tester.runAsync(() async {
      final source = await _resolve(
        SvgPathImage(
          'tool/liquid_metal/nu7.svg',
          size: _size,
          bundle: _FileBundle(),
        ),
      );
      final baked = await processLiquidMetalImage(source);
      final png = await baked.toByteData(format: ui.ImageByteFormat.png);
      File(
        'assets/illustrations/nu7_liquid_metal_shape.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}

Future<ui.Image> _resolve(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  provider
      .resolve(ImageConfiguration.empty)
      .addListener(
        ImageStreamListener((info, _) => completer.complete(info.image)),
      );
  return completer.future;
}

/// Reads the source SVG from disk; it is not a bundled asset.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}
