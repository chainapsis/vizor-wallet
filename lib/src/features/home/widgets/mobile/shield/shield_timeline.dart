import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

import 'shield_motion.dart';

/// The score for the shield moment. Every value is in seconds.
///
/// Two clocks: `t` counts from the instant the knob locks in; `a` counts from
/// the moment loading completes and the particles start to assemble. Visuals
/// and particles read the same numbers, so nothing can drift out of sync.
abstract final class ShieldTimeline {
  // ── After commit (t) ──
  static const headerOut = Window(0.00, 0.26);
  static const sliderOut = Window(0.08, 0.28);

  /// Gravity drop; the glyphs crumble bottom-up over the same window.
  static const fall = Window(0.24, 0.50);

  static const glowTextIn = Window(0.34, 0.90);
  static const statusIn = Window(0.62, 0.42);

  /// When the blink "rain" (and its haptics) begins, and how long it takes to
  /// reach full density.
  static const blinksFrom = 0.80;
  static const blinksRamp = 1.20;

  /// Stand-in for real proving time. The cloud always gets at least
  /// [minCloud] on screen, however fast loading finishes.
  static const minCloud = 3.0;

  // ── After loading completes (a) ──
  static const statusOut = Window(0.00, 0.24);
  static const glowTextOut = Window(0.00, 0.60);

  /// Particles spiral into the shield, blinks accelerate into a drumroll.
  static const assemble = 1.00;

  /// The particle shield locks (success haptic), then a wave of light and
  /// scale rolls through it from top to bottom.
  static const lock = 1.00;
  static const wave = Window(1.18, 0.32);

  /// On the lock the scheme turns from black-and-white (frame 1) to crimson
  /// (frame 2): the light below warms and widens.
  static const backgroundShift = Window(1.00, 1.50);

  /// The shield splits: its crown lifts off and condenses into the 40pt
  /// icon, the rest pours down into the new balance.
  static const split = 1.98;

  /// How many particles form the icon, and how many stay loose to stream
  /// out of the shield field's center afterwards (the rest form the
  /// balance).
  static const iconParticles = 96;
  static const strays = 32;

  // The resolve is deliberately unhurried (about 1.8x the rest of the
  // score) so the shield turning into icon + balance can be felt.
  static const iconIn = Window(2.59, 0.55);

  /// The landing beat: the dots settle into the icon and the amount, the
  /// soft haptic plays, and the shield field scales out around them.
  static const land = 2.71;
  // Keep a readable particle amount before the blurred crisp text takes over.
  static const textIn = Window(2.43, 0.70);
  static const particlesOut = Window(2.75, 0.45);
  static const successLabelIn = Window(3.06, 0.42);
  static const completeIn = Window(3.31, 0.46);

  /// The shield field scales up on the landing beat. Only the Reduce Motion
  /// fade uses the duration.
  static const bubble = Window(land, 1.20);
  static const done = 4.00;

  // ── Balance fall transform (shared by the crisp text and its particles) ──

  static const fallDistance = 60.0;

  /// Vertical offset of the overlay balance at time [t] after commit.
  static double fallDy(double t) {
    if (t <= fall.start) return 0;
    // Gravity: position grows with u², so velocity grows linearly.
    final u = (t - fall.start) / fall.duration;
    return fallDistance * u * u;
  }

  /// Downward speed (pt/s) of the balance at time [t]; handed to each
  /// particle as it breaks free so the crumble keeps the fall's momentum.
  static double fallVelocity(double t) {
    if (t < fall.start) return 0;
    final u = (t - fall.start) / fall.duration;
    return 2 * fallDistance * u / fall.duration;
  }

  /// Keep the balance at its review size before the fall, then recede into
  /// depth as it falls.
  static double fallScale(double t) {
    if (t < fall.start) return 1;
    final u = math.min((t - fall.start) / fall.duration, 1.6);
    return 1 - 0.12 * u * u;
  }

  /// Dissolve front, 0 = nothing eaten, 1 = fully crumbled.
  static double dissolve(double t) => fall.progress(t);

  /// The crisp icon settles with a whisper of overshoot as it resolves.
  static final _iconSpring = SpringSimulation(
    VMotion.spring(response: 0.6, dampingRatio: 0.6),
    0,
    1,
    0,
  );
  static double iconSettle(double a) {
    if (a <= iconIn.start) return 0;
    return _iconSpring.x(a - iconIn.start);
  }
}

/// A slice of a timeline: starts at [start], lasts [duration].
class Window {
  const Window(this.start, this.duration);

  final double start;
  final double duration;

  double get end => start + duration;

  /// Linear 0..1 progress through the window.
  double progress(double t) =>
      ((t - start) / duration).clamp(0.0, 1.0).toDouble();

  /// Eased progress through the window.
  double eased(double t, [Curve curve = VMotion.easeOut]) =>
      curve.transform(progress(t));
}
