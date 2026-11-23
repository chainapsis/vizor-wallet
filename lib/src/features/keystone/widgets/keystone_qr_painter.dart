import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../services/keystone_qr_sizing.dart';

/// Integer physical pixels keep camera-facing module edges sharp at any DPR.
/// Adapted from p0mvn's whole-pixel renderer in PR #1260.
class KeystoneQrPainter extends CustomPainter {
  const KeystoneQrPainter(this.frame, this.pixelRatio);

  final QrImage frame;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final count = frame.moduleCount;
    final pitch =
        (size.shortestSide *
                    pixelRatio /
                    (count + 2 * keystoneQrQuietZoneModules) +
                1e-9)
            .floor();
    if (pitch < 1) return;
    final left = ((size.width * pixelRatio - count * pitch) / 2).floor();
    final top = ((size.height * pixelRatio - count * pitch) / 2).floor();
    final ink = Paint()
      ..color = const Color(0xFF000000)
      ..isAntiAlias = false;
    canvas.save();
    canvas.scale(1 / pixelRatio);
    for (var row = 0; row < count; row++) {
      for (var column = 0; column < count; column++) {
        if (frame.isDark(row, column)) {
          canvas.drawRect(
            Rect.fromLTWH(
              (left + column * pitch).toDouble(),
              (top + row * pitch).toDouble(),
              pitch.toDouble(),
              pitch.toDouble(),
            ),
            ink,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(KeystoneQrPainter oldDelegate) =>
      frame != oldDelegate.frame || pixelRatio != oldDelegate.pixelRatio;
}
