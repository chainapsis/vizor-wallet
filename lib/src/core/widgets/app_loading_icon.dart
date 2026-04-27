import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Animated loading icon used by `AppIcon(AppIcons.loader)`.
///
/// The static frame is drawn as eight rounded spokes in the same 24x24
/// coordinate space as the exported SVG. Animation keeps every spoke fixed in
/// place and moves an opacity pulse from one spoke to the next.
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
      painter: _LoaderIconPainter(
        color: resolved,
        animation: widget.animated ? _controller : null,
      ),
      size: Size.square(widget.size),
    );
    final child = SizedBox.square(dimension: widget.size, child: icon);
    if (widget.semanticLabel == null) {
      return child;
    }
    return Semantics(label: widget.semanticLabel, image: true, child: child);
  }
}

class _LoaderIconPainter extends CustomPainter {
  _LoaderIconPainter({required this.color, required this.animation})
    : super(repaint: animation);

  static const _spokeCount = 8;
  static const _viewBoxSize = 24.0;
  static const _center = Offset(12, 12);
  static const _spokeRect = Rect.fromLTWH(10.5724, 1, 2.8552, 6.0464);
  static const _spokeRadius = Radius.circular(1.4276);

  final Color color;
  final Animation<double>? animation;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / _viewBoxSize;
    final dx = (size.width - _viewBoxSize * scale) / 2;
    final dy = (size.height - _viewBoxSize * scale) / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final spoke = RRect.fromRectAndRadius(_spokeRect, _spokeRadius);

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);

    for (var i = 0; i < _spokeCount; i++) {
      paint.color = color.withValues(alpha: _opacityForSpoke(i));
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

  double _opacityForSpoke(int index) {
    final progress = animation?.value;
    if (progress == null) {
      return 1;
    }
    final active = progress * _spokeCount;
    final trailDistance = (active - index + _spokeCount) % _spokeCount;
    const trailLength = 3.2;
    const minOpacity = 0.28;
    if (trailDistance > trailLength) {
      return minOpacity;
    }
    final falloff = Curves.easeOutCubic.transform(
      1 - trailDistance / trailLength,
    );
    return minOpacity + falloff * (1 - minOpacity);
  }

  @override
  bool shouldRepaint(covariant _LoaderIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.animation != animation;
  }
}
