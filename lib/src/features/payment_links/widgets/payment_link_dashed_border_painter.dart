import 'package:flutter/widgets.dart';

/// Dashed rounded-rectangle border used by the payment-link drop zones and
/// status pills on both form factors.
class PaymentLinkDashedBorderPainter extends CustomPainter {
  const PaymentLinkDashedBorderPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 2,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant PaymentLinkDashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}
