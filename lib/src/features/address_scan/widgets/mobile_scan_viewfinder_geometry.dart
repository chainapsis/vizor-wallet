import 'dart:math' as math;
import 'package:flutter/rendering.dart';

/// Shared by the scanner stroke and the particles that form that stroke.
Path mobileScanViewfinderPath(
  Size size, {
  double cornerLength = 28,
  double cornerRadius = 24,
}) {
  final corner = Path()
    ..moveTo(0, cornerLength)
    ..lineTo(0, cornerRadius)
    ..arcToPoint(Offset(cornerRadius, 0), radius: Radius.circular(cornerRadius))
    ..lineTo(cornerLength, 0);
  final path = Path();
  for (var quarter = 0; quarter < 4; quarter++) {
    final matrix = Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..rotateZ(quarter * math.pi / 2)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
    path.addPath(corner.transform(matrix.storage), Offset.zero);
  }
  return path;
}
