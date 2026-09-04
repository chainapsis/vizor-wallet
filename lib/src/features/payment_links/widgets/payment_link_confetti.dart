import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';

/// Decorative, one-shot celebration used by the Gift Card ready states.
///
/// The timing, launch, palette, and deterministic particle generation follow
/// the designer-provided `vizor-card-handoff` motion implementation.
class PaymentLinkConfetti extends StatefulWidget {
  const PaymentLinkConfetti({this.alignment, super.key});

  static const int pieceCount = 72;
  static const Duration burstDuration = Duration(milliseconds: 1600);

  final Alignment? alignment;

  @override
  State<PaymentLinkConfetti> createState() => _PaymentLinkConfettiState();
}

class _PaymentLinkConfettiState extends State<PaymentLinkConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PaymentLinkConfetti.burstDuration,
  );
  bool _showStaticFrame = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !TickerMode.valuesOf(context).enabled) {
      _showStaticFrame = true;
      _controller.stop();
      return;
    }

    _showStaticFrame = false;
    if (_controller.value < 1 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The original handoff extends the paint surface 160 px horizontally and
    // 140 px vertically around a 360 x 225 card. Keep that relationship while
    // aligning the burst origin with the current desktop/mobile card slots.
    const defaultAlignment =
        kAppFormFactor == AppFormFactor.mobile
            ? Alignment(0, -0.22)
            : Alignment(0, -0.08);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Align(
          alignment: widget.alignment ?? defaultAlignment,
          child: OverflowBox(
            maxWidth: 680,
            maxHeight: 505,
            child: SizedBox(
              width: 680,
              height: 505,
              child: AnimatedBuilder(
                animation: _controller,
                builder:
                    (context, _) => RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('payment_link_confetti_burst'),
                        painter: _ConfettiPainter(
                          progress: _showStaticFrame ? 0.55 : _controller.value,
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.spin,
    required this.phase,
  });

  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;
  final double phase;
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress});

  static const _colors = <Color>[
    Color(0xFFE9536B),
    Color(0xFFF2B33D),
    Color(0xFF4FC1C9),
    Color(0xFF5AC466),
    Color(0xFFF27B3D),
    Color(0xFF7B61FF),
  ];
  static final List<_Particle> _particles = _generateParticles();

  final double progress;

  static List<_Particle> _generateParticles() {
    final random = math.Random(1337);
    return List.generate(PaymentLinkConfetti.pieceCount, (_) {
      return _Particle(
        angle: -math.pi / 2 + (random.nextDouble() - 0.5) * math.pi * 1.7,
        speed: 180 + random.nextDouble() * 260,
        size: 5 + random.nextDouble() * 5,
        color: _colors[random.nextInt(_colors.length)],
        spin: (random.nextDouble() - 0.5) * 14,
        phase: random.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress;
    if (t <= 0 || t >= 1) return;

    final center = size.center(Offset.zero);
    final travel = Curves.easeOutCubic.transform(t);
    final opacity = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;

    for (final particle in _particles) {
      final position =
          center +
          Offset(
            math.cos(particle.angle) * particle.speed * travel,
            math.sin(particle.angle) * particle.speed * travel + 320 * t * t,
          );
      final paint = Paint()..color = particle.color.withValues(alpha: opacity);

      canvas
        ..save()
        ..translate(position.dx, position.dy)
        ..rotate(particle.phase + particle.spin * t)
        ..scale(1, 0.4 + 0.6 * math.cos(particle.phase + t * 9).abs())
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size,
              height: particle.size * 0.62,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
