import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

/// A fixed-size payment-link placeholder with an optional shimmer sweep.
///
/// The configured [colors] always render as the base gradient, keeping static
/// captures identical to the loading design. When motion is allowed, only the
/// highlight band's transform changes; the bar's size and paint stay fixed.
class PaymentLinkSkeletonBar extends StatefulWidget {
  const PaymentLinkSkeletonBar({
    required this.width,
    required this.height,
    this.colors = const [Color(0x00858686), Color(0x80858686)],
    this.shimmerColor,
    this.shimmerKey,
    super.key,
  }) : assert(width > 0),
       assert(height > 0);

  static const Duration period = Duration(milliseconds: 1200);

  final double width;
  final double height;
  final List<Color> colors;
  final Color? shimmerColor;
  final Key? shimmerKey;

  @override
  State<PaymentLinkSkeletonBar> createState() => _PaymentLinkSkeletonBarState();
}

class _PaymentLinkSkeletonBarState extends State<PaymentLinkSkeletonBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PaymentLinkSkeletonBar.period,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        TickerMode.valuesOf(context).enabled;
    if (shouldAnimate == _motionEnabled) return;

    _motionEnabled = shouldAnimate;
    if (shouldAnimate) {
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
    assert(widget.colors.length >= 2);
    final sweepWidth = widget.width * 0.55;
    final shimmerColor =
        widget.shimmerColor ?? widget.colors.last.withValues(alpha: 0.75);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.full),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.colors),
              ),
            ),
            if (_motionEnabled)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _controller,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: sweepWidth,
                        height: widget.height,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                shimmerColor.withValues(alpha: 0),
                                shimmerColor,
                                shimmerColor.withValues(alpha: 0),
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    builder: (context, child) {
                      final travel = widget.width + (sweepWidth * 2);
                      return Transform.translate(
                        key: widget.shimmerKey,
                        offset: Offset(
                          -sweepWidth + (travel * _controller.value),
                          0,
                        ),
                        child: child,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
