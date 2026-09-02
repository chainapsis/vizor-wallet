import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'payment_link_card_motion.dart';

/// A controlled, two-sided Y-axis flip for payment-link gift cards.
///
/// The parent owns which side is visible through [showBack]. Rebuilding with
/// the opposite value continues from the current animation value, so a second
/// click can reverse an in-progress flip without snapping. The animation only
/// changes the transform; both sides are expected to have the same card size.
class PaymentLinkCardFlip extends StatefulWidget {
  const PaymentLinkCardFlip({
    required this.showBack,
    required this.front,
    required this.back,
    this.onAnimationEnd,
    super.key,
  });

  /// The handoff spring has no fixed duration. This is a conservative budget
  /// for tests and previews to reach rest.
  static const Duration settleDuration = Duration(seconds: 2);
  static const double edgeBand = 0.13;

  final bool showBack;
  final Widget front;
  final Widget back;
  final VoidCallback? onAnimationEnd;

  @override
  State<PaymentLinkCardFlip> createState() => _PaymentLinkCardFlipState();
}

class _PaymentLinkCardFlipState extends State<PaymentLinkCardFlip>
    with SingleTickerProviderStateMixin {
  static const _springResponse = 0.7;
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness:
        (2 * math.pi / _springResponse) * (2 * math.pi / _springResponse),
    ratio: 1,
  );

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.showBack ? 1 : 0,
  );
  bool? _lastMotionDisabled;

  bool get _motionDisabled =>
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
      !TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = _motionDisabled;
    if (disabled) {
      _controller
        ..stop()
        ..value = widget.showBack ? 1 : 0;
    } else if (_lastMotionDisabled == true) {
      _controller.value = widget.showBack ? 1 : 0;
    }
    _lastMotionDisabled = disabled;
  }

  @override
  void didUpdateWidget(covariant PaymentLinkCardFlip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showBack == widget.showBack) return;
    final target = widget.showBack ? 1.0 : 0.0;
    if (_motionDisabled) {
      widget.onAnimationEnd?.call();
      return;
    }
    _controller
        .animateWith(SpringSimulation(_spring, _controller.value, target, 0))
        .then((_) {
          if (mounted && widget.showBack == (target == 1)) {
            widget.onAnimationEnd?.call();
          }
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = PaymentLinkCardMotionScope.maybeOf(context);
    if (_motionDisabled) {
      return _faces(
        showBack: widget.showBack,
        front: widget.front,
        back: widget.back,
        motion: motion,
        rotation: (motion?.rotation ?? 0) + (widget.showBack ? math.pi : 0),
      );
    }
    return AnimatedBuilder(
      key: const ValueKey('payment_link_flip_animation'),
      animation: _controller,
      builder: (context, _) {
        final value = _controller.value.clamp(0.0, 1.0);
        final showingBack = value >= 0.5;
        final rawAngle = value * math.pi;
        // Keep a narrow projected width around the face swap instead of
        // rendering a fully edge-on (and therefore invisible) card frame.
        final angle =
            showingBack
                ? math.max(
                  rawAngle,
                  (math.pi / 2) + PaymentLinkCardFlip.edgeBand,
                )
                : math.min(
                  rawAngle,
                  (math.pi / 2) - PaymentLinkCardFlip.edgeBand,
                );
        final transform = Matrix4.identity();
        // PaymentLinkCardMotion owns the camera when present. Keeping the
        // local flip rotation but omitting a second perspective avoids the
        // wide-angle distortion caused by stacked cameras.
        if (motion == null) transform.setEntry(3, 2, 0.0012);
        transform.rotateY(angle);
        return Transform(
          key: const ValueKey('payment_link_flip_transform'),
          alignment: Alignment.center,
          transform: transform,
          child: _faces(
            showBack: showingBack,
            front: widget.front,
            back: widget.back,
            motion: motion,
            rotation: (motion?.rotation ?? 0) + (value * math.pi),
          ),
        );
      },
    );
  }

  static Widget _faces({
    required bool showBack,
    required Widget front,
    required Widget back,
    required PaymentLinkCardMotionScope? motion,
    required double rotation,
  }) {
    Widget faces = IndexedStack(
      index: showBack ? 1 : 0,
      children: [
        KeyedSubtree(
          key: const ValueKey('payment_link_flip_front'),
          child: front,
        ),
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(math.pi),
          child: KeyedSubtree(
            key: const ValueKey('payment_link_flip_back'),
            child: back,
          ),
        ),
      ],
    );
    if (motion == null) return faces;
    faces = PaymentLinkCardMotionScope(
      light: motion.light,
      rotation: rotation,
      child: faces,
    );
    return faces;
  }
}
