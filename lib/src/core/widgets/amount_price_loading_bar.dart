import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The "price not here yet" placeholder that stands in for a converted amount
/// under an amount field: a small pill where the `$ 12.34` readout would be.
///
/// Shared by both send composers and both request composers so every surface
/// that waits on a price reads the same. Desktop keeps it static; mobile
/// sweeps a highlight across it ([animated]) — and only while tickers run and
/// the platform has not asked for reduced motion.
class AmountPriceLoadingBar extends StatefulWidget {
  const AmountPriceLoadingBar({
    this.animated = false,
    this.width = 48,
    this.height = 12,
    super.key,
  });

  final bool animated;
  final double width;
  final double height;

  static const sweepPeriod = Duration(milliseconds: 1200);

  @override
  State<AmountPriceLoadingBar> createState() => _AmountPriceLoadingBarState();
}

class _AmountPriceLoadingBarState extends State<AmountPriceLoadingBar>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  AnimationController get _activeController {
    return _controller ??= AnimationController(
      vsync: this,
      duration: AmountPriceLoadingBar.sweepPeriod,
    );
  }

  bool get _shouldAnimate {
    if (!widget.animated) return false;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return false;
    return TickerMode.valuesOf(context).enabled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(AmountPriceLoadingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (!_activeController.isAnimating) _activeController.repeat();
      return;
    }
    final controller = _controller;
    if (controller != null) {
      controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final baseColor = colors.background.overlay.withValues(alpha: 0.15);
    final highlightColor = colors.background.raised;

    if (!widget.animated) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _shouldAnimate
          ? AnimatedBuilder(
              animation: _activeController,
              builder: (context, _) => CustomPaint(
                painter: _AmountPriceLoadingPainter(
                  progress: _activeController.value,
                  baseColor: baseColor,
                  highlightColor: highlightColor,
                ),
              ),
            )
          : CustomPaint(
              painter: _AmountPriceLoadingPainter(
                progress: 0,
                baseColor: baseColor,
                highlightColor: highlightColor,
                animate: false,
              ),
            ),
    );
  }
}

class _AmountPriceLoadingPainter extends CustomPainter {
  const _AmountPriceLoadingPainter({
    required this.progress,
    required this.baseColor,
    required this.highlightColor,
    this.animate = true,
  });

  final double progress;
  final Color baseColor;
  final Color highlightColor;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(AppRadii.full));
    if (!animate) {
      final shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [highlightColor, baseColor],
      ).createShader(rect);
      canvas.drawRRect(rrect, Paint()..shader = shader);
      return;
    }
    canvas.drawRRect(rrect, Paint()..color = baseColor);
    canvas.save();
    canvas.clipRRect(rrect);
    final sweepWidth = size.width * 1.6;
    final left = -sweepWidth + progress * (size.width + sweepWidth);
    final sweepRect = Rect.fromLTWH(left, 0, sweepWidth, size.height);
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        baseColor.withValues(alpha: 0),
        highlightColor,
        baseColor.withValues(alpha: 0),
      ],
      stops: const [0, 0.5, 1],
    ).createShader(sweepRect);
    canvas.drawRect(sweepRect, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AmountPriceLoadingPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        baseColor != oldDelegate.baseColor ||
        highlightColor != oldDelegate.highlightColor ||
        animate != oldDelegate.animate;
  }
}
