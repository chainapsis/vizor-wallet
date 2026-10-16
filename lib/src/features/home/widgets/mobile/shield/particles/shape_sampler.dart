import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Rasterizes real drawings (the balance block, icons) offscreen and turns
/// their coverage into particle targets, so particles leave from and land on
/// the actual shapes.
abstract final class ShapeSampler {
  /// Points covering whatever [paint] draws inside [size] (origin = its
  /// top-left). Exactly [count] points.
  static Future<List<Offset>> picture(
    Size size,
    void Function(Canvas) paint, {
    required int count,
    required math.Random random,
  }) async {
    final raster = await _Raster.paint(size, scale: 3, paint);
    final points = _fitCount(raster, count);
    return _exact(points, count, random, raster.lastPitch);
  }

  /// Exactly [count] points covering an SVG drawn at [height], in the
  /// SVG's own space (origin = its top-left).
  static Future<List<Offset>> svgPoints(
    String asset, {
    required double height,
    required int count,
    required math.Random random,
  }) async {
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    final scale = height / info.size.height;
    final raster = await _Raster.paint(info.size * scale, scale: 4, (canvas) {
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
    });
    info.picture.dispose();
    final points = _fitCount(raster, count);
    return _exact(points, count, random, raster.lastPitch);
  }

  /// Grid cells of [pitch] that fall inside an SVG drawn at [height].
  /// With [solid], holes inside the silhouette (the Zcash Z) are filled:
  /// every row runs from its leftmost to its rightmost covered cell.
  static Future<List<Offset>> svgCells(
    String asset, {
    required double height,
    required double pitch,
    bool solid = false,
  }) async {
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    final scale = height / info.size.height;
    final size = info.size * scale;
    final raster = await _Raster.paint(size, scale: 2, (canvas) {
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
    });
    info.picture.dispose();
    // Center the grid on the shape so the halftone sits symmetrically.
    final cols = (size.width / pitch).floor();
    final rows = (size.height / pitch).floor();
    final ox = (size.width - (cols - 1) * pitch) / 2;
    final oy = (size.height - (rows - 1) * pitch) / 2;
    final cells = <Offset>[];
    for (var r = 0; r < rows; r++) {
      final row = <int>[];
      for (var c = 0; c < cols; c++) {
        final p = Offset(ox + c * pitch, oy + r * pitch);
        if (raster.coverage(p, radius: pitch * 0.32) > 0.6) row.add(c);
      }
      if (row.isEmpty) continue;
      final from = solid ? row.first : null;
      final cs = solid ? [for (var c = from!; c <= row.last; c++) c] : row;
      for (final c in cs) {
        cells.add(Offset(ox + c * pitch, oy + r * pitch));
      }
    }
    return cells;
  }

  /// Whatever [paint] draws inside [size], blurred by [sigma], baked into a
  /// small image. Its rect is relative to the drawing's origin.
  static Future<BakedImage> blurred(
    Size size,
    void Function(Canvas) paint, {
    required double sigma,
  }) {
    final pad = sigma * 3;
    final logical = Rect.fromLTWH(
      -pad,
      -pad,
      size.width + 2 * pad,
      size.height + 2 * pad,
    );
    return _bake(logical, 0.5, (canvas) {
      canvas.saveLayer(
        logical,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
      );
      paint(canvas);
      canvas.restore();
    });
  }

  static Future<BakedImage> _bake(
    Rect logical,
    double scale,
    void Function(Canvas) paint,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.translate(-logical.left, -logical.top);
    paint(canvas);
    final image = await recorder.endRecording().toImage(
      (logical.width * scale).ceil(),
      (logical.height * scale).ceil(),
    );
    return BakedImage(image, logical);
  }

  /// Picks a pitch so the sampled grid yields about [count] points.
  static List<Offset> _fitCount(_Raster raster, int count) {
    var pitch = math.sqrt(raster.inkArea / count);
    var points = raster.grid(pitch);
    for (var i = 0; i < 6; i++) {
      final ratio = points.length / count;
      if ((ratio - 1).abs() < 0.03) break;
      pitch *= math.sqrt(ratio);
      points = raster.grid(pitch);
    }
    return points;
  }

  /// Trims or pads to exactly [count], keeping the spread even.
  static List<Offset> _exact(
    List<Offset> points,
    int count,
    math.Random random,
    double pitch,
  ) {
    final out = List<Offset>.of(points);
    while (out.length > count) {
      out.removeAt(random.nextInt(out.length));
    }
    final base = out.length;
    while (out.length < count) {
      final p = out[random.nextInt(base)];
      out.add(
        p +
            Offset(
              (random.nextDouble() - 0.5) * pitch * 0.6,
              (random.nextDouble() - 0.5) * pitch * 0.6,
            ),
      );
    }
    return out;
  }
}

/// A baked image and the logical rect it covers.
class BakedImage {
  BakedImage(this.image, this.rect);

  final ui.Image image;
  final Rect rect;

  void dispose() => image.dispose();
}

class _Raster {
  _Raster(this.size, this.scale, this.width, this.height, this.alpha);

  final Size size;
  final double scale;
  final int width;
  final int height;
  final Uint8List alpha;
  double lastPitch = 1;

  static Future<_Raster> paint(
    Size size,
    void Function(Canvas) painter, {
    double scale = 2,
  }) async {
    final w = (size.width * scale).ceil();
    final h = (size.height * scale).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    painter(canvas);
    final image = await recorder.endRecording().toImage(w, h);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    final alpha = Uint8List(w * h);
    final bytes = data.buffer.asUint8List();
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = bytes[i * 4 + 3];
    }
    return _Raster(size, scale, w, h, alpha);
  }

  double get inkArea {
    var sum = 0;
    for (final a in alpha) {
      sum += a;
    }
    return sum / 255 / (scale * scale);
  }

  int _at(double x, double y) {
    final px = (x * scale).floor();
    final py = (y * scale).floor();
    if (px < 0 || py < 0 || px >= width || py >= height) return 0;
    return alpha[py * width + px];
  }

  /// Fraction of a small square neighborhood that is painted.
  double coverage(Offset p, {required double radius}) {
    var hit = 0;
    var total = 0;
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        total++;
        if (_at(p.dx + dx * radius / 2, p.dy + dy * radius / 2) > 127) hit++;
      }
    }
    return hit / total;
  }

  List<Offset> grid(double pitch) {
    lastPitch = pitch;
    final out = <Offset>[];
    for (var y = pitch / 2; y < size.height; y += pitch) {
      for (var x = pitch / 2; x < size.width; x += pitch) {
        if (_at(x, y) > 127) out.add(Offset(x, y));
      }
    }
    return out;
  }
}
