part of '../ironwood_migration_flow_screen.dart';

const _migrationProgressSegmentGap = 4.0;
const _migrationProgressSegmentPreferredMinWidth = 16.0;

class _MigrationProgressSegmentRow extends StatelessWidget {
  const _MigrationProgressSegmentRow({
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
    this.progressKeys = const [],
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final List<String> progressKeys;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _migrationSegmentRowLayout(
            values: values,
            totalZatoshi: totalZatoshi,
            maxWidth: constraints.maxWidth,
          );
          return Row(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) SizedBox(width: layout.gap),
                SizedBox(
                  width: i < layout.widths.length ? layout.widths[i] : 0,
                  child: _MigrationProgressSegment(
                    key: ValueKey(
                      'ironwood_migration_segment_${i < progressKeys.length ? progressKeys[i] : i}',
                    ),
                    index: i,
                    status: i < statuses.length
                        ? statuses[i]
                        : _MigrationBatchStatus.none,
                    progress: i < progresses.length ? progresses[i] : 0,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MigrationSegmentRowLayout {
  const _MigrationSegmentRowLayout({required this.gap, required this.widths});

  final double gap;
  final List<double> widths;
}

class _MigrationProgressSegment extends StatelessWidget {
  const _MigrationProgressSegment({
    super.key,
    required this.index,
    required this.status,
    required this.progress,
  });

  final int index;
  final _MigrationBatchStatus status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = status == _MigrationBatchStatus.complete
        ? 1.0
        : progress.clamp(0, 1).toDouble();

    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: effectiveProgress),
      builder: (context, animatedProgress, child) {
        final visibleProgress = _migrationSegmentVisibleProgress(
          status,
          animatedProgress,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _MigrationProgressSegmentPainter(
                status: status,
                progress: animatedProgress,
                isDark: context.appTheme == AppThemeData.dark,
              ),
            ),
            SizedBox.expand(
              key: ValueKey('ironwood_migration_segment_track_$index'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: visibleProgress.clamp(0, 1).toDouble(),
                heightFactor: 1,
                child: SizedBox.expand(
                  key: ValueKey('ironwood_migration_segment_fill_$index'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MigrationProgressSegmentPainter extends CustomPainter {
  const _MigrationProgressSegmentPainter({
    required this.status,
    required this.progress,
    required this.isDark,
  });

  static const _green = GreenPrimitives.p500Light;
  static const _greenStripe = Color(0xFF008752);
  static const _greenSoftFill = Color(0x400DC87D);
  static const _purple = Color(0xFFB83AD9);
  static const _purpleStripe = Color(0xFF8F25AB);
  static const _strokeWidth = 1.5;

  final _MigrationBatchStatus status;
  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final outlineRect = Offset.zero & size;
    final borderRect = outlineRect.deflate(_strokeWidth / 2);
    final radius = Radius.circular(size.height / 2);
    final outline = RRect.fromRectAndRadius(outlineRect, radius);
    final border = RRect.fromRectAndRadius(borderRect, radius);
    final clipPath = Path()..addRRect(outline);
    final borderPath = Path()..addRRect(border);

    switch (status) {
      case _MigrationBatchStatus.complete:
        _drawFilledPill(canvas, outline, _green);
        break;
      case _MigrationBatchStatus.none:
        _drawFilledPill(canvas, outline, _greenSoftFill);
        _drawDashedBorder(canvas, borderPath, _green);
        break;
      case _MigrationBatchStatus.preparing:
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          progress,
          fillColor: _green,
        );
        _drawDashedBorder(canvas, borderPath, _green);
        break;
      case _MigrationBatchStatus.scheduled:
        _drawStripedBackground(
          canvas,
          clipPath,
          outlineRect,
          fillColor: _greenSoftFill,
          stripeColor: _scheduledStripeColor,
        );
        _drawDashedBorder(canvas, borderPath, _green);
        break;
      case _MigrationBatchStatus.migrating:
      case _MigrationBatchStatus.confirming:
        _drawStripedBackground(
          canvas,
          clipPath,
          outlineRect,
          fillColor: _activeStripeFillColor,
          stripeColor: _activeStripeColor,
        );
        final solidProgress = math.min(
          progress.clamp(0, 1).toDouble(),
          _scheduledBlockProgressCap,
        );
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          solidProgress,
          fillColor: _green,
        );
        break;
      case _MigrationBatchStatus.needsInput:
        _drawStripedBackground(
          canvas,
          clipPath,
          outlineRect,
          fillColor: _purple.withValues(alpha: 0.22),
          stripeColor: _purpleStripe.withValues(alpha: 0.44),
        );
        final solidProgress = math.min(
          math.max(progress, 0.18).clamp(0, 1).toDouble(),
          0.18,
        );
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          solidProgress,
          fillColor: _purple,
        );
        break;
    }
  }

  void _drawFilledPill(Canvas canvas, RRect rrect, Color color) {
    canvas.drawRRect(rrect, Paint()..color = color);
  }

  Color get _activeStripeFillColor =>
      isDark ? const Color(0x590DC87D) : _greenSoftFill;

  Color get _activeStripeColor => isDark
      ? _green.withValues(alpha: 0.42)
      : _greenStripe.withValues(alpha: 0.48);

  Color get _scheduledStripeColor => isDark
      ? _green.withValues(alpha: 0.34)
      : _greenStripe.withValues(alpha: 0.28);

  void _drawStripedBackground(
    Canvas canvas,
    Path clipPath,
    Rect rect, {
    required Color fillColor,
    required Color stripeColor,
  }) {
    canvas.save();
    canvas.clipPath(clipPath);
    canvas.drawRect(rect, Paint()..color = fillColor);
    _drawDiagonalStripes(canvas, rect, stripeColor);
    canvas.restore();
  }

  void _drawProgressFill(
    Canvas canvas,
    Path clipPath,
    Rect rect,
    double progress, {
    double startProgress = 0,
    required Color fillColor,
    Color? stripeColor,
  }) {
    final clampedStart = startProgress.clamp(0, 1).toDouble();
    final clampedProgress = progress.clamp(0, 1).toDouble();
    if (clampedProgress <= clampedStart) return;

    final fillRect = Rect.fromLTWH(
      rect.left + rect.width * clampedStart,
      rect.top,
      rect.width * (clampedProgress - clampedStart),
      rect.height,
    );

    canvas.save();
    canvas.clipPath(clipPath);
    final fillPath = _progressFillPath(rect, fillRect, clampedStart);
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    if (stripeColor != null) {
      canvas.save();
      canvas.clipPath(fillPath);
      _drawDiagonalStripes(canvas, fillRect, stripeColor);
      canvas.restore();
    }
    canvas.restore();
  }

  Path _progressFillPath(Rect trackRect, Rect fillRect, double startProgress) {
    final radius = trackRect.height / 2;
    if (fillRect.width <= 0) return Path();

    final leftRadius = startProgress <= 0 ? radius : 0.0;
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        fillRect,
        topLeft: Radius.circular(leftRadius),
        bottomLeft: Radius.circular(leftRadius),
        topRight: Radius.circular(radius),
        bottomRight: Radius.circular(radius),
      ),
    );
  }

  void _drawDiagonalStripes(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const spacing = 4.0;
    final diagonal = rect.height * 1.45;
    for (
      var x = rect.left - diagonal;
      x < rect.right + diagonal;
      x += spacing
    ) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + diagonal, rect.top),
        paint,
      );
    }
  }

  void _drawDashedBorder(Canvas canvas, Path path, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 3.5;
      const gap = 2.5;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MigrationProgressSegmentPainter oldDelegate) {
    return oldDelegate.status != status ||
        oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark;
  }
}

double _migrationSegmentProgress({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required List<_MigrationBatchStatus> statuses,
  required List<double> progresses,
  required int index,
}) {
  if (index >= values.length) return 0;
  if (statuses.isEmpty) return 0;
  if (index >= statuses.length) return 0;

  final status = statuses[index];
  if (status == _MigrationBatchStatus.complete) return 1;

  final rawProgress = index < progresses.length
      ? progresses[index].clamp(0, 1).toDouble()
      : 0.0;

  final hasSharedPreparingProgress =
      rawProgress > 0 &&
      statuses.every((status) => status == _MigrationBatchStatus.preparing) &&
      progresses.isNotEmpty;
  if (!hasSharedPreparingProgress) return rawProgress;

  return _distributedMigrationSegmentProgress(
    values: values,
    totalZatoshi: totalZatoshi,
    progress: rawProgress,
    index: index,
  );
}

double _distributedMigrationSegmentProgress({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required double progress,
  required int index,
}) {
  if (totalZatoshi <= BigInt.zero) return progress;
  var before = BigInt.zero;
  for (var i = 0; i < index; i++) {
    before += values[i];
  }
  final current = values[index];
  if (current <= BigInt.zero) return 0;

  final start = before / totalZatoshi;
  final end = (before + current) / totalZatoshi;
  if (end <= start) return progress;
  return ((progress - start) / (end - start)).clamp(0, 1).toDouble();
}

double _migrationSegmentVisibleProgress(
  _MigrationBatchStatus status,
  double progress,
) {
  return switch (status) {
    _MigrationBatchStatus.none => 0,
    _MigrationBatchStatus.complete => 1,
    _MigrationBatchStatus.needsInput => math.max(progress, 0.18),
    _ => progress,
  };
}
