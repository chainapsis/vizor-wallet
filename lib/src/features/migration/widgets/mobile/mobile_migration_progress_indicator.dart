import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';

class MobileMigrationProgressHero extends StatelessWidget {
  const MobileMigrationProgressHero({
    required this.amount,
    required this.progress,
    super.key,
  });

  final String amount;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 4,
            right: 4,
            top: 4,
            height: 106,
            child: _MobileMigrationProgressArc(progress: progress),
          ),
          const Positioned(
            top: 49,
            child: AppIcon(
              AppIcons.shieldKeyhole,
              size: 32,
              color: Color(0xFF00A460),
            ),
          ),
          Positioned(
            top: 97,
            child: Text(
              'Migrating...',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            top: 131,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                key: const ValueKey('mobile_ironwood_remaining_amount'),
                TextSpan(
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                    fontSize: 40,
                    height: 1,
                    letterSpacing: 0,
                  ),
                  children: [
                    TextSpan(text: '$amount '),
                    TextSpan(
                      text: 'ZEC',
                      style: AppTypography.displayLarge.copyWith(
                        color: colors.text.accent,
                        fontSize: 32,
                        height: 33 / 32,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 183,
            child: Text(
              'Left to transfer',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MobileMigrationPasscodeHero extends StatelessWidget {
  const MobileMigrationPasscodeHero({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 194,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 4,
            right: 4,
            top: 20,
            height: 106,
            child: _MobileMigrationProgressArc(progress: progress),
          ),
          Positioned(
            top: 116,
            child: Text(
              'Welcome Back',
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
                letterSpacing: 0,
              ),
            ),
          ),
          Positioned(
            top: 172,
            child: Text(
              'Migrating...',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationProgressArc extends StatelessWidget {
  const _MobileMigrationProgressArc({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '${(progress * 100).round()}% done',
      child: CustomPaint(
        painter: _MobileMigrationProgressArcPainter(
          trackColor: colors.background.raised,
          progressColor: const Color(0xFF00A460),
          progress: progress,
          labelStyle: AppTypography.labelMedium.copyWith(
            color: colors.text.muted,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationProgressArcPainter extends CustomPainter {
  const _MobileMigrationProgressArcPainter({
    required this.trackColor,
    required this.progressColor,
    required this.progress,
    required this.labelStyle,
  });

  final Color trackColor;
  final Color progressColor;
  final double progress;
  final TextStyle labelStyle;

  static const _sourceWidth = 352.999;
  static const _sourceHeight = 106.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _sourceWidth, size.height / _sourceHeight);

    canvas.drawPath(
      _trackOutline(),
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.fill,
    );

    final arc = _arcCenterline();
    final metric = arc.computeMetrics().first;
    final progressLength = metric.length * progress.clamp(0.0, 1.0).toDouble();
    if (progressLength > 0) {
      canvas.drawPath(
        metric.extractPath(0, progressLength),
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8.72
          ..strokeCap = StrokeCap.round,
      );
    }

    _paintProgressLabel(
      canvas,
      '${(progress * 100).round()}% DONE',
      _labelPath(),
    );
    canvas.restore();
  }

  Path _trackOutline() {
    return Path()
      ..moveTo(2.16207, 105.415)
      ..cubicTo(0.0848519, 104.211, -0.6307, 101.541, 0.612172, 99.4816)
      ..cubicTo(18.5429, 69.7681, 43.6661, 45.0558, 73.6743, 27.6616)
      ..cubicTo(104.937, 9.54017, 140.4, -0.000008, 176.5, 0)
      ..cubicTo(212.599, 0.000008, 248.062, 9.5402, 279.325, 27.6617)
      ..cubicTo(309.333, 45.0559, 334.456, 69.7682, 352.387, 99.4816)
      ..cubicTo(353.63, 101.541, 352.914, 104.211, 350.837, 105.415)
      ..cubicTo(348.76, 106.619, 346.108, 105.901, 344.863, 103.843)
      ..cubicTo(327.696, 75.4546, 303.67, 51.8427, 274.982, 35.2139)
      ..cubicTo(245.039, 17.8578, 211.074, 8.72055, 176.5, 8.72054)
      ..cubicTo(141.925, 8.72053, 107.96, 17.8578, 78.0173, 35.2139)
      ..cubicTo(49.3296, 51.8426, 25.3032, 75.4545, 8.13617, 103.843)
      ..cubicTo(6.89139, 105.901, 4.23928, 106.619, 2.16207, 105.415)
      ..close();
  }

  Path _arcCenterline() {
    return Path()
      ..moveTo(4.374, 101.662)
      ..cubicTo(21.923, 72.612, 46.498, 48.449, 75.846, 31.438)
      ..cubicTo(106.448, 13.699, 141.163, 4.36, 176.5, 4.36)
      ..cubicTo(211.837, 4.36, 246.551, 13.699, 277.154, 31.438)
      ..cubicTo(306.502, 48.449, 331.076, 72.612, 348.625, 101.662);
  }

  Path _labelPath() {
    return Path()
      ..moveTo(-6, 100)
      ..cubicTo(12.9517, 67.4679, 40.2101, 40.453, 73.0355, 21.6706)
      ..cubicTo(105.861, 2.88815, 143.097, -7, 181, -7)
      ..cubicTo(218.903, -7, 256.139, 2.88812, 288.964, 21.6705)
      ..cubicTo(321.79, 40.4529, 349.048, 67.4678, 368, 100);
  }

  void _paintProgressLabel(Canvas canvas, String label, Path path) {
    final metric = path.computeMetrics().first;
    var offset = 2.0;
    for (final character in label.split('')) {
      final painter = TextPainter(
        text: TextSpan(text: character, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final advance = character == ' ' ? 4.0 : painter.width;
      final characterCenter = offset + advance / 2;
      final tangent = metric.getTangentForOffset(characterCenter);
      if (tangent == null) break;

      if (character != ' ') {
        canvas.save();
        canvas.translate(tangent.position.dx, tangent.position.dy);
        canvas.rotate(math.atan2(tangent.vector.dy, tangent.vector.dx));
        painter.paint(canvas, Offset(-painter.width / 2, -painter.height + 1));
        canvas.restore();
      }
      offset += advance;
    }
  }

  @override
  bool shouldRepaint(covariant _MobileMigrationProgressArcPainter oldDelegate) {
    return oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.progress != progress ||
        oldDelegate.labelStyle != labelStyle;
  }
}
