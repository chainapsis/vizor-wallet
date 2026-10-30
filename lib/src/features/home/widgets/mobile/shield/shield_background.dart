import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class ShieldScrimPainter extends CustomPainter {
  ShieldScrimPainter(this.shift);

  final double shift;

  static const _grey = Color(0x188A8A8A);
  static const _crimson = Color(0x18AA2455);

  @override
  void paint(Canvas canvas, Size size) {
    final s = shift;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        // The original video retains the blurred home through success.
        ..color = const Color(0xEF101916),
    );
    final matrix = Matrix4.identity()
      ..translateByDouble(size.width * 0.5, size.height * 1.02, 0, 1)
      ..scaleByDouble(
        size.width * ui.lerpDouble(2.8, 3.4, s)!,
        size.height * ui.lerpDouble(0.34, 0.4, s)!,
        1,
        1,
      );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          1,
          [Color.lerp(_grey, _crimson, s)!, const Color(0x00000000)],
          const [0, 1],
          TileMode.clamp,
          matrix.storage,
        ),
    );
  }

  @override
  bool shouldRepaint(ShieldScrimPainter old) => old.shift != shift;
}
