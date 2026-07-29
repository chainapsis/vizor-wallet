import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
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
  AnimationController? _controller;

  AnimationController get _activeController {
    return _controller ??= AnimationController(
      vsync: this,
      duration: AppLoadingIconTiming.period,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AppLoadingIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  bool get _effectiveAnimated {
    return widget.animated &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  void _syncAnimation() {
    if (_effectiveAnimated) {
      _activeController.repeat();
    } else {
      final controller = _controller;
      if (controller != null) {
        controller
          ..stop()
          ..value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncAnimation();
    final effectiveAnimated = _effectiveAnimated;
    final resolved =
        widget.color ??
        IconTheme.of(context).color ??
        context.colors.icon.regular;
    final icon = CustomPaint(
      painter: _LoaderIconPainter(
        color: resolved,
        repaint: effectiveAnimated ? _activeController : null,
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

abstract final class AppLoadingIconTiming {
  static const period = Duration(milliseconds: 900);

  @visibleForTesting
  static const spokeCount = 8;

  @visibleForTesting
  static const trailLength = 3.2;

  @visibleForTesting
  static const minOpacity = 0.28;

  @visibleForTesting
  static double progressForFrameTime(Duration frameTime) {
    final frameMicros = frameTime.inMicroseconds;
    final periodMicros = period.inMicroseconds;
    return (frameMicros % periodMicros) / periodMicros;
  }

  @visibleForTesting
  static double opacityForSpokeAtProgress(int index, double progress) {
    final active = progress * spokeCount;
    final trailDistance = (active - index + spokeCount) % spokeCount;
    if (trailDistance > trailLength) {
      return minOpacity;
    }
    final falloff = Curves.easeOutCubic.transform(
      1 - trailDistance / trailLength,
    );
    return minOpacity + falloff * (1 - minOpacity);
  }
}

class _LoaderIconPainter extends CustomPainter {
  _LoaderIconPainter({required this.color, required super.repaint})
    : _animated = repaint != null,
      super();

  static const _viewBoxSize = 24.0;
  static const _center = Offset(12, 12);
  static const _spokeRect = Rect.fromLTWH(10.5724, 1, 2.8552, 6.0464);
  static const _spokeRadius = Radius.circular(1.4276);

  final Color color;
  final bool _animated;

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

    for (var i = 0; i < AppLoadingIconTiming.spokeCount; i++) {
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
    if (!_animated) {
      return 1;
    }
    final progress = AppLoadingIconTiming.progressForFrameTime(
      SchedulerBinding.instance.currentFrameTimeStamp,
    );
    return AppLoadingIconTiming.opacityForSpokeAtProgress(index, progress);
  }

  @override
  bool shouldRepaint(covariant _LoaderIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate._animated != _animated;
  }
}
