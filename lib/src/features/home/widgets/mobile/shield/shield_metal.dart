import 'package:flutter/painting.dart';

/// The original video's bright neutral silver drag pin and its inside edge.
abstract final class Metal {
  static const _fill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEDEEEE), Color(0xFF858B89)],
  );

  static const _stroke = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFF44454A), Color(0xFFECECEC)],
    stops: [0, 0.558, 1],
  );

  /// Paints a fully rounded metal pill filling [rect].
  static void pill(Canvas canvas, Rect rect) {
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.shortestSide / 2),
    );
    canvas.drawRRect(rrect, Paint()..shader = _fill.createShader(rect));
    canvas.drawDRRect(
      rrect,
      rrect.deflate(2),
      Paint()..shader = _stroke.createShader(rect),
    );
  }
}
