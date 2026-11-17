import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

/// Shows [child] as an option of the setting above it: indented by [indent],
/// with a hooked line from [lineX] down and across to the child's first row,
/// whose vertical center is [rowCenter] below the child's top.
class SettingsSubOption extends StatelessWidget {
  const SettingsSubOption({
    required this.indent,
    required this.lineX,
    required this.rowCenter,
    required this.child,
    super.key,
  });

  final double indent;
  final double lineX;
  final double rowCenter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: lineX,
          top: 0,
          width: indent - lineX - AppSpacing.xxs,
          height: rowCenter,
          child: CustomPaint(
            painter: _HookPainter(context.colors.border.medium),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: indent),
          child: child,
        ),
      ],
    );
  }
}

/// Paints a line down the left edge that turns right along the bottom.
class _HookPainter extends CustomPainter {
  _HookPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 6.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height - radius)
      ..quadraticBezierTo(0, size.height, radius, size.height)
      ..lineTo(size.width, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_HookPainter old) => old.color != color;
}
