import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Rasterizes a flat SVG asset (logos, icons) without any package.
///
/// Draws `<path>` elements only, with `d`, `fill`, `stroke`, `stroke-width`
/// and `fill-rule`; attributes on the root `<svg>` are inherited. Colors are
/// hex, `black`, `white` or `none`. For anything richer, export a PNG.
class SvgPathImage extends ImageProvider<SvgPathImage> {
  const SvgPathImage(this.asset, {this.size = 1536, this.bundle});

  final String asset;

  /// Longest side of the raster, in pixels. 1536 stays sharp for a logo up to
  /// about that many device pixels wide; raise it for bigger renders.
  final int size;
  final AssetBundle? bundle;

  @override
  Future<SvgPathImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    SvgPathImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    final svg = await (bundle ?? rootBundle).loadString(asset);
    final root = RegExp(r'<svg\b[^>]*>').firstMatch(svg)![0]!;
    final viewBox =
        _attr(
          root,
          'viewBox',
        )?.trim().split(RegExp(r'[\s,]+')).map(double.parse).toList() ??
        [
          0,
          0,
          double.parse(_attr(root, 'width')!),
          double.parse(_attr(root, 'height')!),
        ];
    final landscape = viewBox[2] >= viewBox[3];
    final width = landscape ? size : (size * viewBox[2] / viewBox[3]).round();
    final height = landscape ? (size * viewBox[3] / viewBox[2]).round() : size;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(width / viewBox[2], height / viewBox[3])
      ..translate(-viewBox[0], -viewBox[1]);
    for (final match in RegExp(r'<path\b[^>]*>').allMatches(svg)) {
      final tag = match[0]!;
      String? get(String name) => _attr(tag, name) ?? _attr(root, name);
      final path = parseSvgPathData(_attr(tag, 'd') ?? '')
        ..fillType = get('fill-rule') == 'evenodd'
            ? PathFillType.evenOdd
            : PathFillType.nonZero;
      final fill = _color(get('fill') ?? 'black');
      if (fill != null) canvas.drawPath(path, Paint()..color = fill);
      final stroke = _color(get('stroke') ?? 'none');
      if (stroke != null) {
        canvas.drawPath(
          path,
          Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = double.parse(get('stroke-width') ?? '1'),
        );
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    return ImageInfo(image: image);
  }

  static String? _attr(String tag, String name) =>
      RegExp('\\s$name\\s*=\\s*["\']([^"\']*)["\']').firstMatch(tag)?[1];

  static Color? _color(String value) {
    if (value == 'none') return null;
    if (value == 'white') return const Color(0xFFFFFFFF);
    if (!value.startsWith('#')) return const Color(0xFF000000);
    var hex = value.substring(1);
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    return Color(0xFF000000 | int.parse(hex.substring(0, 6), radix: 16));
  }

  @override
  bool operator ==(Object other) =>
      other is SvgPathImage &&
      other.asset == asset &&
      other.size == size &&
      other.bundle == bundle;

  @override
  int get hashCode => Object.hash(asset, size, bundle);
}

/// Parses SVG path data (`M L H V C S Q T A Z`, absolute and relative).
Path parseSvgPathData(String data) {
  final path = Path();
  final tokens = RegExp(
    r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
  ).allMatches(data).map((m) => m[0]!).toList();
  var i = 0;
  var command = '', previous = '';
  var current = Offset.zero, start = Offset.zero, control = Offset.zero;
  double number() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (RegExp(r'^[A-Za-z]$').hasMatch(tokens[i])) command = tokens[i++];
    final origin = command == command.toLowerCase() ? current : Offset.zero;
    Offset point() => Offset(number(), number()) + origin;
    final type = command.toUpperCase();
    switch (type) {
      case 'M':
        current = start = control = point();
        path.moveTo(current.dx, current.dy);
        command = command == 'm' ? 'l' : 'L'; // extra pairs are line-tos
      case 'L':
        current = control = point();
        path.lineTo(current.dx, current.dy);
      case 'H':
        current = control = Offset(number() + origin.dx, current.dy);
        path.lineTo(current.dx, current.dy);
      case 'V':
        current = control = Offset(current.dx, number() + origin.dy);
        path.lineTo(current.dx, current.dy);
      case 'C' || 'S':
        final c1 = type == 'C'
            ? point()
            : _reflect(previous, 'CS', current, control);
        control = point();
        current = point();
        path.cubicTo(
          c1.dx,
          c1.dy,
          control.dx,
          control.dy,
          current.dx,
          current.dy,
        );
      case 'Q' || 'T':
        control = type == 'Q'
            ? point()
            : _reflect(previous, 'QT', current, control);
        current = point();
        path.quadraticBezierTo(control.dx, control.dy, current.dx, current.dy);
      case 'A':
        final radius = Radius.elliptical(number(), number());
        final rotation = number(),
            largeArc = number() != 0,
            clockwise = number() != 0;
        current = control = point();
        path.arcToPoint(
          current,
          radius: radius,
          rotation: rotation,
          largeArc: largeArc,
          clockwise: clockwise,
        );
      case 'Z':
        path.close();
        current = control = start;
        command = '';
      default:
        i++; // stray number
    }
    previous = type;
  }
  return path;
}

Offset _reflect(
  String previous,
  String curves,
  Offset current,
  Offset control,
) => curves.contains(previous) ? current * 2 - control : current;
