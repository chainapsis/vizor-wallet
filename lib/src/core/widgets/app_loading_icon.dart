import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Animated loading icon that mirrors `assets/icons/loader.svg`.
///
/// The static frame is drawn as eight rounded spokes in the same 24x24
/// coordinate space as the exported SVG. Animation rotates that same drawing
/// instead of relying on SVG animation support.
class AppLoadingIcon extends StatefulWidget {
  const AppLoadingIcon({
    this.size = AppIconSize.medium,
    this.color,
    this.animated = true,
    this.semanticLabel,
    super.key,
  });

  final double size;
  final Color? color;
  final bool animated;
  final String? semanticLabel;

  @override
  State<AppLoadingIcon> createState() => _AppLoadingIconState();
}

class _AppLoadingIconState extends State<AppLoadingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _turns = Tween<double>(
    begin: 0,
    end: 1 / 8,
  ).animate(_controller);

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AppLoadingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated == oldWidget.animated) {
      return;
    }
    if (widget.animated) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved =
        widget.color ??
        IconTheme.of(context).color ??
        context.colors.icon.regular;
    final icon = CustomPaint(
      painter: _LoaderIconPainter(color: resolved),
      size: Size.square(widget.size),
    );
    final child = SizedBox.square(
      dimension: widget.size,
      child: widget.animated
          ? RotationTransition(turns: _turns, child: icon)
          : icon,
    );
    if (widget.semanticLabel == null) {
      return child;
    }
    return Semantics(label: widget.semanticLabel, image: true, child: child);
  }
}

class _LoaderIconPainter extends CustomPainter {
  const _LoaderIconPainter({required this.color});

  static const _viewBoxSize = 24.0;
  static const _center = Offset(12, 12);
  static const _spokeRect = Rect.fromLTWH(10.5724, 1, 2.8552, 6.0464);
  static const _spokeRadius = Radius.circular(1.4276);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / _viewBoxSize;
    final dx = (size.width - _viewBoxSize * scale) / 2;
    final dy = (size.height - _viewBoxSize * scale) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final spoke = RRect.fromRectAndRadius(_spokeRect, _spokeRadius);

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);

    for (var i = 0; i < 8; i++) {
      canvas
        ..save()
        ..translate(_center.dx, _center.dy)
        ..rotate(i * math.pi / 4)
        ..translate(-_center.dx, -_center.dy)
        ..drawRRect(spoke, paint)
        ..restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoaderIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
