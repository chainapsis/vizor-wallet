import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// An SVG asset drawn into an image, for widgets that take their shape from
/// an image's alpha, such as `LiquidMetal`. Colors are kept but only the
/// alpha matters there, so any icon from `assets/icons/` works as is.
@immutable
class SvgShapeImage extends ImageProvider<SvgShapeImage> {
  const SvgShapeImage(this.assetName, {this.size = 512});

  /// The SVG asset, e.g. `assets/icons/plane.svg`.
  final String assetName;

  /// Pixel length of the image's longer side. 512 matches the working size
  /// `LiquidMetal` processes shapes at.
  final int size;

  @override
  Future<SvgShapeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<SvgShapeImage>(this);

  @override
  ImageStreamCompleter loadImage(
    SvgShapeImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load(key));

  static Future<ImageInfo> _load(SvgShapeImage key) async {
    final info = await vg.loadPicture(SvgAssetLoader(key.assetName), null);
    try {
      final scale = key.size / math.max(info.size.width, info.size.height);
      final width = math.max(1, (info.size.width * scale).round());
      final height = math.max(1, (info.size.height * scale).round());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..scale(scale)
        ..drawPicture(info.picture);
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      return ImageInfo(image: image, debugLabel: key.assetName);
    } finally {
      info.picture.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SvgShapeImage &&
      other.assetName == assetName &&
      other.size == size;

  @override
  int get hashCode => Object.hash(assetName, size);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'SvgShapeImage')}("$assetName", $size)';
}
