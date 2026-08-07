import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

@immutable
class PaymentLinkCardLight {
  const PaymentLinkCardLight(this.position, this.strength);

  static const rest = PaymentLinkCardLight(Offset(0.5, 0.5), 0);

  final Offset position;
  final double strength;
}

/// Shares the single smoothed light source and current Y rotation with every
/// card layer. The front holo, amount shine, and back gloss therefore move as
/// one instead of each running an independent animation.
class PaymentLinkCardMotionScope extends InheritedWidget {
  const PaymentLinkCardMotionScope({
    required this.light,
    required this.rotation,
    required super.child,
    super.key,
  });

  final ValueListenable<PaymentLinkCardLight> light;
  final double rotation;

  static PaymentLinkCardMotionScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PaymentLinkCardMotionScope>();
  }

  @override
  bool updateShouldNotify(PaymentLinkCardMotionScope oldWidget) {
    return oldWidget.light != light || oldWidget.rotation != rotation;
  }
}

/// Designer-provided Gift Card reveal plus the settled desktop pointer motion.
///
/// [celebrate] is intentionally edge-triggered. A waiting card stays flat;
/// changing it to true runs the grow + full-turn reveal once. Cards that mount
/// with it true (the receive surface) reveal immediately.
class PaymentLinkCardMotion extends StatefulWidget {
  const PaymentLinkCardMotion({
    required this.child,
    this.celebrate = false,
    this.enableTilt = true,
    this.width = 320,
    this.height = 200,
    super.key,
  });

  static const revealDuration = Duration(milliseconds: 950);

  final Widget child;
  final bool celebrate;
  final bool enableTilt;
  final double width;
  final double height;

  @override
  State<PaymentLinkCardMotion> createState() => _PaymentLinkCardMotionState();
}

class _PaymentLinkCardMotionState extends State<PaymentLinkCardMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: PaymentLinkCardMotion.revealDuration,
    value: widget.celebrate ? 0 : 1,
  );
  late final Animation<double> _rotation = Tween<double>(
    begin: 0,
    end: 2 * math.pi,
  ).animate(
    CurvedAnimation(parent: _revealController, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _scale = CurvedAnimation(
    parent: _revealController,
    curve: Curves.easeOutBack,
  );
  final ValueNotifier<PaymentLinkCardLight> _light = ValueNotifier(
    PaymentLinkCardLight.rest,
  );
  bool _didRunCelebration = false;

  bool get _motionDisabled =>
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false) ||
      !TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionDisabled) {
      _didRunCelebration = widget.celebrate;
      _revealController
        ..stop()
        ..value = 1;
      _light.value = PaymentLinkCardLight.rest;
    } else if (widget.celebrate && !_didRunCelebration) {
      _runCelebration();
    }
  }

  @override
  void didUpdateWidget(covariant PaymentLinkCardMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.celebrate && widget.celebrate) {
      if (_motionDisabled) {
        _didRunCelebration = true;
        _revealController.value = 1;
      } else {
        _runCelebration();
      }
    }
  }

  void _runCelebration() {
    _didRunCelebration = true;
    _light.value = PaymentLinkCardLight.rest;
    _revealController.forward(from: 0);
  }

  @override
  void dispose() {
    _revealController.dispose();
    _light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _revealController,
      child: widget.child,
      builder: (context, child) {
        final disabled = _motionDisabled;
        final rotation = disabled ? 2 * math.pi : _rotation.value;
        final scale = disabled ? 1.0 : _scale.value;
        final revealed = disabled || !_revealController.isAnimating;
        final scopedCard = PaymentLinkCardMotionScope(
          light: _light,
          rotation: rotation,
          child: child!,
        );
        return _PaymentLinkPointerTilt(
          width: widget.width,
          height: widget.height,
          enabled: widget.enableTilt && revealed && !disabled,
          onLight: (light) => _light.value = light,
          child: Transform(
            key: const ValueKey('payment_link_reveal_transform'),
            alignment: Alignment.center,
            transform:
                Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(rotation),
            child: Transform.scale(
              key: const ValueKey('payment_link_reveal_scale'),
              scale: scale,
              child: scopedCard,
            ),
          ),
        );
      },
    );
  }
}

class _PaymentLinkPointerTilt extends StatefulWidget {
  const _PaymentLinkPointerTilt({
    required this.width,
    required this.height,
    required this.enabled,
    required this.onLight,
    required this.child,
  });

  final double width;
  final double height;
  final bool enabled;
  final ValueChanged<PaymentLinkCardLight> onLight;
  final Widget child;

  @override
  State<_PaymentLinkPointerTilt> createState() =>
      _PaymentLinkPointerTiltState();
}

class _PaymentLinkPointerTiltState extends State<_PaymentLinkPointerTilt>
    with SingleTickerProviderStateMixin {
  static const _tauFollow = 0.09;
  static const _tauEngage = 0.14;
  static const _tauRelease = 0.35;
  static const _maxTilt = 0.18;
  static const _liftScale = 1.05;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Offset _position = const Offset(0.5, 0.5);
  Offset _goalPosition = const Offset(0.5, 0.5);
  double _strength = 0;
  double _goalStrength = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  void _update(Offset localPosition) {
    if (!widget.enabled) return;
    _goalPosition = Offset(
      (localPosition.dx / widget.width).clamp(0.0, 1.0),
      (localPosition.dy / widget.height).clamp(0.0, 1.0),
    );
    _goalStrength = 1;
    _drive();
  }

  void _reset({bool immediate = false}) {
    _goalPosition = const Offset(0.5, 0.5);
    _goalStrength = 0;
    if (immediate) {
      _ticker.stop();
      _position = _goalPosition;
      _strength = 0;
      widget.onLight(PaymentLinkCardLight.rest);
      return;
    }
    _drive();
  }

  void _drive() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    double approach(double value, double goal, double tau) {
      return goal + (value - goal) * math.exp(-dt / tau);
    }

    final strengthTau = _goalStrength > _strength ? _tauEngage : _tauRelease;
    setState(() {
      _position = Offset(
        approach(_position.dx, _goalPosition.dx, _tauFollow),
        approach(_position.dy, _goalPosition.dy, _tauFollow),
      );
      _strength = approach(_strength, _goalStrength, strengthTau);
      if ((_position - _goalPosition).distance < 0.001 &&
          (_strength - _goalStrength).abs() < 0.002) {
        _position = _goalPosition;
        _strength = _goalStrength;
        _ticker.stop();
      }
    });
    widget.onLight(PaymentLinkCardLight(_position, _strength));
  }

  @override
  void didUpdateWidget(covariant _PaymentLinkPointerTilt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _reset(immediate: true);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = (_position.dx * 2 - 1) * _strength;
    final y = (_position.dy * 2 - 1) * _strength;
    final transform =
        widget.enabled
            ? (Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateX(-y * _maxTilt)
              ..rotateY(x * _maxTilt))
            : Matrix4.identity();
    final scale = widget.enabled ? 1 + (_liftScale - 1) * _strength : 1.0;

    return MouseRegion(
      key: const ValueKey('payment_link_tilt_mouse_region'),
      onHover: (event) => _update(event.localPosition),
      onExit: (_) => _reset(),
      child: Listener(
        onPointerDown: (event) => _update(event.localPosition),
        onPointerMove: (event) => _update(event.localPosition),
        onPointerUp: (_) => _reset(),
        onPointerCancel: (_) => _reset(),
        child: Transform(
          key: const ValueKey('payment_link_tilt_transform'),
          alignment: Alignment.center,
          transform: transform,
          child: Transform.scale(scale: scale, child: widget.child),
        ),
      ),
    );
  }
}

class PaymentLinkCardHoloShine extends StatefulWidget {
  const PaymentLinkCardHoloShine({required this.light, super.key});

  final ValueListenable<PaymentLinkCardLight> light;

  @override
  State<PaymentLinkCardHoloShine> createState() =>
      _PaymentLinkCardHoloShineState();
}

class _PaymentLinkCardHoloShineState extends State<PaymentLinkCardHoloShine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void initState() {
    super.initState();
    widget.light.addListener(_syncDrift);
    _syncDrift();
  }

  void _syncDrift() {
    final visible = widget.light.value.strength > 0.002;
    if (visible && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!visible && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void didUpdateWidget(covariant PaymentLinkCardHoloShine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.light != widget.light) {
      oldWidget.light.removeListener(_syncDrift);
      widget.light.addListener(_syncDrift);
      _syncDrift();
    }
  }

  @override
  void dispose() {
    widget.light.removeListener(_syncDrift);
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_drift, widget.light]),
          builder: (context, _) {
            final light = widget.light.value;
            if (light.strength <= 0.002) return const SizedBox.expand();
            return CustomPaint(
              key: const ValueKey('payment_link_holo_shine'),
              painter: _PaymentLinkHoloPainter(
                progress: _drift.value,
                pointer: light.position,
                intensity: light.strength,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PaymentLinkHoloPainter extends CustomPainter {
  const _PaymentLinkHoloPainter({
    required this.progress,
    required this.pointer,
    required this.intensity,
  });

  static const _rainbow = <Color>[
    Color(0x09FF3D3D),
    Color(0x09FF9E3D),
    Color(0x09FFE53D),
    Color(0x093DFF6E),
    Color(0x093DE1FF),
    Color(0x09A23DFF),
    Color(0x09FF3DCB),
  ];
  static const _glow = Color(0x1FFFFFFF);

  final double progress;
  final Offset pointer;
  final double intensity;

  Color _scaled(Color color) {
    return color.withValues(alpha: color.a * intensity);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final tau = 2 * math.pi;
    final driftStrength = 1 - intensity;
    final drift = Offset(
      math.sin(progress * tau) * 0.07 * driftStrength,
      math.cos(progress * tau * 0.8) * 0.06 * driftStrength,
    );
    final x = (pointer.dx + drift.dx).clamp(0.0, 1.0);
    final y = (pointer.dy + drift.dy).clamp(0.0, 1.0);
    final center = Alignment(x * 2 - 1, y * 2 - 1);
    final angle = (x - 0.5) * 1.4 + (y - 0.5) * 0.9 + progress * tau * 0.15;

    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          colors: _rainbow.map(_scaled).toList(),
          tileMode: TileMode.mirror,
          transform: GradientRotation(angle),
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          center: center,
          radius: 0.75,
          colors: [_scaled(_glow), const Color(0x00FFFFFF)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_PaymentLinkHoloPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pointer != pointer ||
        oldDelegate.intensity != intensity;
  }
}

class PaymentLinkCardMetallicShine extends StatelessWidget {
  const PaymentLinkCardMetallicShine({
    required this.light,
    required this.rotation,
    required this.child,
    super.key,
  });

  final ValueListenable<PaymentLinkCardLight> light;
  final double rotation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PaymentLinkCardLight>(
      valueListenable: light,
      builder: (context, value, child) {
        final restPosition = math.sin(rotation);
        final hoverPosition = value.position.dx * 2 - 1;
        final position =
            ui.lerpDouble(restPosition, hoverPosition, value.strength)!;
        final restGlare = 0.72 + 0.28 * math.cos(rotation).abs();
        final glare = ui.lerpDouble(restGlare, 1, value.strength)!;
        final center = 0.5 + position * 0.5;
        Color metal(double brightness) {
          final channel = (brightness * glare * 255).round().clamp(0, 255);
          return Color.fromARGB(255, channel, channel, channel);
        }

        return ShaderMask(
          key: const ValueKey('payment_link_metallic_shine'),
          blendMode: BlendMode.srcIn,
          shaderCallback:
              (bounds) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [metal(0.62), metal(1), metal(0.62)],
                stops: [
                  (center - 0.38).clamp(0.0, 1.0),
                  center.clamp(0.0, 1.0),
                  (center + 0.38).clamp(0.0, 1.0),
                ],
              ).createShader(bounds),
          child: child,
        );
      },
      child: child,
    );
  }
}

class PaymentLinkCardGlossShine extends StatefulWidget {
  const PaymentLinkCardGlossShine({
    required this.light,
    this.maskAsset =
        'assets/illustrations/payment_links/payment_link_message_pattern.png',
    super.key,
  });

  final ValueListenable<PaymentLinkCardLight> light;
  final String maskAsset;

  @override
  State<PaymentLinkCardGlossShine> createState() =>
      _PaymentLinkCardGlossShineState();
}

class _PaymentLinkCardGlossShineState extends State<PaymentLinkCardGlossShine> {
  ui.Image? _mask;

  @override
  void initState() {
    super.initState();
    _loadMask();
  }

  Future<void> _loadMask() async {
    try {
      final data = await rootBundle.load(widget.maskAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _mask = frame.image);
      } else {
        frame.image.dispose();
      }
    } catch (_) {
      // The message side remains usable if its decorative mask is unavailable.
    }
  }

  @override
  void dispose() {
    _mask?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mask = _mask;
    if (mask == null) return const SizedBox.expand();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: widget.light,
          builder: (context, _) {
            final light = widget.light.value;
            if (light.strength <= 0.002) return const SizedBox.expand();
            return CustomPaint(
              key: const ValueKey('payment_link_gloss_shine'),
              painter: _PaymentLinkGlossPainter(
                mask: mask,
                pointer: light.position,
                opacity: light.strength * 0.28,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PaymentLinkGlossPainter extends CustomPainter {
  const _PaymentLinkGlossPainter({
    required this.mask,
    required this.pointer,
    required this.opacity,
  });

  final ui.Image mask;
  final Offset pointer;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(pointer.dx * 2 - 1, pointer.dy * 2 - 1),
          radius: 0.8,
          colors: const [
            Color(0xFFFFFFFF),
            Color(0x8CFFFFFF),
            Color(0x33FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: const [0, 0.35, 0.65, 1],
        ).createShader(rect),
    );

    final source = Rect.fromLTWH(
      0,
      0,
      mask.width.toDouble(),
      mask.height.toDouble(),
    );
    final scale = math.max(size.width / mask.width, size.height / mask.height);
    final width = mask.width * scale;
    final height = mask.height * scale;
    final destination = Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
    canvas.drawImageRect(
      mask,
      source,
      destination,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaymentLinkGlossPainter oldDelegate) {
    return oldDelegate.mask != mask ||
        oldDelegate.pointer != pointer ||
        oldDelegate.opacity != opacity;
  }
}
