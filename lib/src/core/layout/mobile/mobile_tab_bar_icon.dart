import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../widgets/app_icon.dart';

/// A tab bar icon that plays a short flourish of its own when its tab becomes
/// the active one, driven by [progress] running 0 → 1:
///
/// * home tower — turns side to side like a raised shield, settling in three
///   shrinking swings;
/// * swap arrows — half a turn, so the arrows trade places;
/// * history — the ring arrow spins one full turn clockwise, the way it
///   points, while the hand sweeps two turns the opposite way;
/// * settings cog — a quarter turn that coasts to a stop.
///
/// Every flourish ends exactly where it began (each icon is symmetric under
/// the turn it makes), and at rest the plain [AppIcon] is drawn with no extra
/// layers. Other icons are drawn as-is.
class MobileTabBarIcon extends StatelessWidget {
  const MobileTabBarIcon({
    required this.iconName,
    required this.size,
    required this.color,
    required this.progress,
    super.key,
  });

  final String iconName;
  final double size;
  final Color color;
  final Animation<double> progress;

  /// How long [iconName]'s flourish runs; zero when it has none.
  static Duration durationFor(String iconName) => switch (iconName) {
    AppIcons.home => const Duration(milliseconds: 600),
    AppIcons.swapArrows => const Duration(milliseconds: 420),
    AppIcons.history => const Duration(milliseconds: 650),
    AppIcons.cog => const Duration(milliseconds: 520),
    _ => Duration.zero,
  };

  /// Strong ease-in-out for turns that start and end at rest.
  static const _easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// Strong ease-out for a turn that starts briskly and coasts to a stop.
  static const _easeOut = Cubic(0.23, 1, 0.32, 1);

  @override
  Widget build(BuildContext context) {
    final icon = AppIcon(iconName, size: size, color: color);
    return switch (iconName) {
      AppIcons.home => _Flourish(
        progress: progress,
        child: icon,
        builder: (t, child) => Transform(
          alignment: Alignment.center,
          // Perspective sized for the 24px icon, so the near edge visibly
          // grows as the tower turns.
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.012)
            ..rotateY(_shieldTurn(t)),
          child: child,
        ),
      ),
      AppIcons.swapArrows => _Flourish(
        progress: progress,
        child: icon,
        builder: (t, child) => Transform.rotate(
          angle: math.pi * _easeInOut.transform(t),
          child: child,
        ),
      ),
      AppIcons.cog => _Flourish(
        progress: progress,
        child: icon,
        builder: (t, child) => Transform.rotate(
          angle: math.pi / 2 * _easeOut.transform(t),
          child: child,
        ),
      ),
      AppIcons.history => _Flourish(
        progress: progress,
        child: icon,
        builder: (t, child) => Stack(
          children: [
            Transform.rotate(
              angle: 2 * math.pi * _easeInOut.transform(t),
              child: ClipPath(
                clipper: const _ClockHandClip(hand: false),
                clipBehavior: Clip.hardEdge,
                child: child,
              ),
            ),
            Transform.rotate(
              angle: -4 * math.pi * _easeInOut.transform(t),
              child: ClipPath(
                clipper: const _ClockHandClip(hand: true),
                clipBehavior: Clip.hardEdge,
                child: child,
              ),
            ),
          ],
        ),
      ),
      _ => icon,
    };
  }

  /// Damped sway about the vertical axis: about 35° one way, 15° back, then a
  /// last 3° before it rests.
  static double _shieldTurn(double t) =>
      -0.78 * math.sin(3 * math.pi * t) * math.pow(1 - t, 1.5);
}

/// Rebuilds [builder] each frame of [progress], but draws the plain [child]
/// at rest so an idle tab costs nothing extra.
class _Flourish extends StatelessWidget {
  const _Flourish({
    required this.progress,
    required this.builder,
    required this.child,
  });

  final Animation<double> progress;
  final Widget Function(double t, Widget child) builder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final t = progress.value;
        if (t == 0 || t == 1) return child!;
        return builder(t, child!);
      },
    );
  }
}

/// Splits the 24px history artwork into its hand ([hand]) and everything
/// else (the ring and its arrowhead), so the two can turn separately. The
/// hand sits inside this outline; the ring and arrowhead never enter it.
class _ClockHandClip extends CustomClipper<Path> {
  const _ClockHandClip({required this.hand});

  final bool hand;

  static const _outline = [
    Offset(10.3, 5.9),
    Offset(13.7, 5.9),
    Offset(13.7, 11.0),
    Offset(16.4, 13.4),
    Offset(16.4, 16.6),
    Offset(10.3, 16.6),
  ];

  @override
  Path getClip(Size size) {
    final scale = size.width / 24;
    final outline = Path()
      ..addPolygon([for (final point in _outline) point * scale], true);
    if (hand) return outline;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(outline, Offset.zero);
  }

  @override
  bool shouldReclip(_ClockHandClip oldClipper) => oldClipper.hand != hand;
}
