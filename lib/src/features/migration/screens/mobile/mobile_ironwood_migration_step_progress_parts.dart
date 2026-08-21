part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationRailSegment extends StatelessWidget {
  const _MobileMigrationRailSegment({
    required this.width,
    required this.status,
    this.progress,
  });

  final double width;
  final MobileIronwoodMigrationPartStatus status;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: _mobileMigrationPlanFinalBarHeight,
      child: CustomPaint(
        painter: _MobileMigrationRailSegmentPainter(
          status: status,
          progress: progress,
          successColor: colors.icon.success,
          inputColor: colors.text.brandCrimson,
          pendingFill: colors.icon.success.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _MobileMigrationRailSegmentPainter extends CustomPainter {
  const _MobileMigrationRailSegmentPainter({
    required this.status,
    required this.successColor,
    required this.inputColor,
    required this.pendingFill,
    this.progress,
  });

  final MobileIronwoodMigrationPartStatus status;
  final Color successColor;
  final Color inputColor;
  final Color pendingFill;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final accent = status == MobileIronwoodMigrationPartStatus.needsInput
        ? inputColor
        : successColor;

    switch (status) {
      case MobileIronwoodMigrationPartStatus.complete:
        canvas.drawRRect(bounds, Paint()..color = accent);
      case MobileIronwoodMigrationPartStatus.pending:
        canvas.drawRRect(bounds, Paint()..color = pendingFill);
        _drawDashedRailBorder(canvas, bounds, accent);
      case MobileIronwoodMigrationPartStatus.active:
      case MobileIronwoodMigrationPartStatus.needsInput:
        canvas.drawRRect(
          bounds,
          Paint()..color = accent.withValues(alpha: 0.14),
        );
        canvas.save();
        canvas.clipRRect(bounds);
        final fill = (progress ?? 0.35).clamp(0.0, 1.0);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width * fill, size.height),
          Paint()..color = accent,
        );
        final hatch = Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..strokeWidth = 1;
        for (double x = -size.height; x < size.width; x += 5) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            hatch,
          );
        }
        canvas.restore();
    }
  }

  void _drawDashedRailBorder(Canvas canvas, RRect bounds, Color color) {
    final path = Path()..addRRect(bounds.deflate(1));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 3, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 3;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MobileMigrationRailSegmentPainter oldDelegate) {
    return oldDelegate.status != status ||
        oldDelegate.progress != progress ||
        oldDelegate.successColor != successColor ||
        oldDelegate.inputColor != inputColor ||
        oldDelegate.pendingFill != pendingFill;
  }
}

String? _mobileMigrationPercentage(BigInt value, BigInt total) {
  if (value < BigInt.zero || total <= BigInt.zero) return null;
  final percentage = value.toDouble() * 100 / total.toDouble();
  final fixed = percentage.toStringAsFixed(1);
  return '${fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed}%';
}
