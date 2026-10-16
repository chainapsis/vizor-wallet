import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../shield_haptics.dart';
import '../shield_timeline.dart';
import 'sprite_atlas.dart';

/// How each particle is drawn. Dots match the Figma halftone; digits are
/// the "numbers" look from the inspiration board.
enum ParticleGlyph { dot, digit }

const kParticleGlyph = ParticleGlyph.dot;

/// Everything the field needs to know about the screen, in logical points.
class FieldGeometry {
  const FieldGeometry({
    required this.cloudCenter,
    required this.cloudSlots,
    required this.cloudSizes,
    required this.cloudAlphas,
    required this.textRect,
    required this.textPoints,
    required this.shieldRect,
    required this.shieldSlots,
    required this.balancePoints,
    required this.iconPoints,
    required this.textDimFrom,
    required this.balanceDimFrom,
    required this.screen,
    required this.emitter,
  });

  final Offset cloudCenter;

  /// The cloud's dots on screen (Figma's 718-dot halftone, thickened to
  /// ~1,370), with their size and opacity.
  final List<Offset> cloudSlots;
  final List<double> cloudSizes;
  final List<double> cloudAlphas;

  /// The overlay balance (amount + "ZEC" pill) before it falls. Points are
  /// local to [textRect]'s top-left.
  final Rect textRect;
  final List<Offset> textPoints;

  /// Large particle shield, centered on the cloud. Screen coordinates.
  final Rect shieldRect;
  final List<Offset> shieldSlots;

  /// The success balance the particles finally pour into. Screen coordinates.
  final List<Offset> balancePoints;

  /// The 40pt success icon the shield's crown condenses into. Screen
  /// coordinates. `balancePoints.length + iconPoints.length == count`.
  final List<Offset> iconPoints;

  /// The "ZEC" pill starts at this local y in the falling balance and at
  /// this screen y in the success balance; particles there are dimmed.
  final double textDimFrom;
  final double balanceDimFrom;

  /// Full screen size: how far emitted particles travel.
  final Size screen;

  /// Where the strays stream out from once shielded: the shield field's
  /// center. Screen coordinates.
  final Offset emitter;

  int get count => cloudSlots.length;

  /// Balance particles + icon particles + strays.
  int get strays => count - balancePoints.length - iconPoints.length;
}

/// A projected particle, used when another shape takes over the same field.
class ShieldParticleSample {
  const ShieldParticleSample({
    required this.position,
    required this.size,
    required this.alpha,
    this.velocity = Offset.zero,
    this.color = const Color(0xFFFFFFFF),
    this.square = 0,
    this.extent,
    this.arrival = 1,
  });
  final Offset position;
  final Offset velocity;
  final double size;
  final double alpha;
  final Color color;
  final double square;
  final Size? extent;
  final double arrival;
}

enum _Mode { attached, cloud, shield, balance, emit }

/// The particle system behind the shield moment.
///
/// Each particle is a point in 3D pulled by its own spring toward a moving
/// target: its slot in the cloud (plus an orbit), then a cell of the shield,
/// then a point on the new balance (or, for the shield's crown, the icon).
/// Depth is real: a slow sway rotates the whole volume, so near and far
/// layers slide past each other.
///
/// All state lives in typed arrays and the frame is a single `drawRawAtlas`
/// call, plus one additive call for glows.
class ParticleField extends ChangeNotifier {
  ParticleField({
    required this.geometry,
    required this.atlas,
    required this.reduceMotion,
    int seed = 11,
  }) : n = geometry.count,
       _rng = math.Random(seed) {
    _allocate();
    _seed();
  }

  FieldGeometry geometry;
  SpriteAtlas atlas;
  bool reduceMotion;

  /// Replace artwork destinations without replaying the initial balance fall.
  /// Live positions, velocities, fades, springs and event clocks stay intact.
  void updateTargets(FieldGeometry next, SpriteAtlas nextAtlas) {
    assert(next.count == n);
    final old = geometry;
    final targets = ParticleField(
      geometry: next,
      atlas: nextAtlas,
      reduceMotion: reduceMotion,
    );
    void copy(Float64List to, Float64List from) => to.setAll(0, from);
    for (final pair in [
      (_homeX, targets._homeX),
      (_homeY, targets._homeY),
      (_homeZ, targets._homeZ),
      (_cloudSize, targets._cloudSize),
      (_cloudAlpha, targets._cloudAlpha),
      (_aX, targets._aX),
      (_aY, targets._aY),
      (_release, targets._release),
      (_shX, targets._shX),
      (_shY, targets._shY),
      (_shZ, targets._shZ),
      (_shSize, targets._shSize),
      (_shAlpha, targets._shAlpha),
      (_bX, targets._bX),
      (_bY, targets._bY),
      (_delayB, targets._delayB),
    ]) {
      copy(pair.$1, pair.$2);
    }
    // Omitting an unknown result amount turns its dots into residual emitters.
    // Initialize their lifetimes before copying the new roles; existing emitters
    // keep their live paths and clocks.
    for (var i = 0; i < n; i++) {
      if (targets._stray[i] == 1 && _stray[i] == 0) {
        _eLife[i] = targets._eLife[i];
        _eReach[i] = targets._eReach[i];
        _eSize[i] = targets._eSize[i];
      }
    }
    _icon.setAll(0, targets._icon);
    _stray.setAll(0, targets._stray);
    // A viewport change maps the current cloud into the new coordinate space.
    final scale = next.shieldRect.width / old.shieldRect.width;
    if (scale != 1 || next.cloudCenter != old.cloudCenter) {
      for (var i = 0; i < n; i++) {
        _x[i] = next.cloudCenter.dx + (_x[i] - old.cloudCenter.dx) * scale;
        _y[i] = next.cloudCenter.dy + (_y[i] - old.cloudCenter.dy) * scale;
        _vx[i] *= scale;
        _vy[i] *= scale;
        _eStartX[i] =
            next.cloudCenter.dx + (_eStartX[i] - old.cloudCenter.dx) * scale;
        _eStartY[i] =
            next.cloudCenter.dy + (_eStartY[i] - old.cloudCenter.dy) * scale;
      }
    }
    geometry = next;
    atlas = nextAtlas;
    targets.dispose();
  }

  /// Human approval steps keep the visual ambience without repeated impacts.
  bool hapticsEnabled = true;
  final int n;
  final math.Random _rng;
  bool captureProjectedParticles = false;
  final List<ShieldParticleSample> _projected = [];
  List<ShieldParticleSample> get projectedParticles => _projected;

  // ── Tunables ──
  static const _focal = 700.0;

  // Figma size classes, nearest (big, faint bokeh) to farthest (small, crisp).
  static const _layerZ = [70.0, 25.0, -25.0, -70.0];
  static const _orbitRadius = [5.0, 3.6, 2.6, 1.7];
  static const _floatAmp = [5.0, 4.0, 3.0, 2.2];
  static const _floatPeriod = [5.1, 6.3, 7.7, 9.2];
  static const _catchResponse = [1.55, 1.35, 1.15, 0.95];

  /// Medium impact strength per layer: near blinks hit harder.
  static const _blinkIntensity = [1.0, 0.82, 0.64, 0.48];

  /// Turbulence (pt/s²) on freshly released particles, and how long it lasts.
  static const _curl = 260.0;
  static const _curlFor = 2.0;

  // Sized for ~1,370 dots packed into the 56pt balance.
  static const _textDot = 1.4;
  static const _balanceDot = 1.35;

  /// The "ZEC" pill's dots: 60% like its outline and letters before
  /// shielding, brighter as they pour into the metal pill after.
  static const _textZecAlpha = 0.6;
  static const _balanceZecAlpha = 0.8;
  static const _iconDot = 1.3;
  static const _dustCount = 110;
  static const _bokehCount = 20;

  /// With Reduce Motion, shapes swap at this point after loading completes,
  /// while the field is fully faded out, instead of travelling.
  static const _reducedSwap = 0.2;

  // ── Per-particle constants ──
  late final Int32List _layer;
  late final Float64List _homeX, _homeY, _homeZ, _cloudSize, _cloudAlpha;
  late final Float64List _aX, _aY, _release;
  late final Float64List _shX, _shY, _shZ, _shSize, _shAlpha;
  late final Float64List _bX, _bY;
  late final Float64List _orbR, _orbW, _orbP, _orbE, _orbCos, _orbSin, _orbZ;
  late final Float64List _noise, _catchResp, _catchZeta, _delayA, _delayB;
  late final Int32List _digit;
  late final Uint8List _icon;

  // Strays first continue outward from their shield positions. Later passes
  // stream from the center; the first pass must not disappear and restart there.
  late final Uint8List _stray;
  late final Float64List _eLife, _eSeed, _eReach, _eSize;
  late final Float64List _eStartAt, _eStartX, _eStartY, _eStartZ;
  late final Float64List _eEnv, _eGrow;

  // ── Per-particle state ──
  late final Float64List _x, _y, _z, _vx, _vy, _vz, _k, _c;
  late final List<_Mode> _mode;
  late final Float64List _blinkAt;
  late final Float64List _s0, _s1, _a0, _a1, _w0, _w1, _vt, _vd;

  // ── Ambient dust (far specks + near bokeh) ──
  late final Float64List _dX, _dY, _dZ, _dSize, _dAlpha, _dR, _dW, _dP;

  // ── Render buffers ──
  late final Float32List _rst, _rects, _gRst, _gRects;
  late final Int32List _colors, _gColors;
  int _count = 0;
  int _gCount = 0;

  // ── Clock & events ──
  double _t = 0;
  double? _a;
  double? _lastUpdate;
  double _nextBlink = ShieldTimeline.blinksFrom;
  double _lastHaptic = -1;
  bool _prepared = false;
  bool _assembled = false;
  bool _locked = false;

  Offset get _c0 => geometry.cloudCenter;
  double get _motion => reduceMotion ? 0 : 1;

  void _allocate() {
    Float64List f() => Float64List(n);
    _layer = Int32List(n);
    _homeX = f();
    _homeY = f();
    _homeZ = f();
    _cloudSize = f();
    _cloudAlpha = f();
    _aX = f();
    _aY = f();
    _release = f();
    _shX = f();
    _shY = f();
    _shZ = f();
    _shSize = f();
    _shAlpha = f();
    _bX = f();
    _bY = f();
    _orbR = f();
    _orbW = f();
    _orbP = f();
    _orbE = f();
    _orbCos = f();
    _orbSin = f();
    _orbZ = f();
    _noise = f();
    _catchResp = f();
    _catchZeta = f();
    _delayA = f();
    _delayB = f();
    _digit = Int32List(n);
    _icon = Uint8List(n);
    _stray = Uint8List(n);
    _eLife = f();
    _eStartAt = f();
    _eStartX = f();
    _eStartY = f();
    _eStartZ = f();
    _eSeed = f();
    _eReach = f();
    _eSize = f();
    _eEnv = f();
    _eGrow = f();
    _x = f();
    _y = f();
    _z = f();
    _vx = f();
    _vy = f();
    _vz = f();
    _k = f();
    _c = f();
    _mode = List<_Mode>.filled(n, _Mode.attached);
    _blinkAt = Float64List(n)..fillRange(0, n, -10);
    _s0 = f();
    _s1 = f();
    _a0 = f();
    _a1 = f();
    _w0 = f();
    _w1 = f();
    _vt = f();
    _vd = Float64List(n)..fillRange(0, n, 1);

    final d = _dustCount;
    _dX = Float64List(d);
    _dY = Float64List(d);
    _dZ = Float64List(d);
    _dSize = Float64List(d);
    _dAlpha = Float64List(d);
    _dR = Float64List(d);
    _dW = Float64List(d);
    _dP = Float64List(d);

    final cap = n + _dustCount;
    _rst = Float32List(cap * 4);
    _rects = Float32List(cap * 4);
    _colors = Int32List(cap);
    final gCap = n * 3 + _dustCount;
    _gRst = Float32List(gCap * 4);
    _gRects = Float32List(gCap * 4);
    _gColors = Int32List(gCap);
  }

  double _rand(double lo, double hi) => lo + (hi - lo) * _rng.nextDouble();

  void _seed() {
    final g = geometry;
    final c = _c0;

    // Layer from the Figma size class (largest = nearest).
    for (var i = 0; i < n; i++) {
      final s = g.cloudSizes[i];
      final layer = s > 4
          ? 0
          : s > 3
          ? 1
          : s > 2
          ? 2
          : 3;
      _layer[i] = layer;
      final z = _layerZ[layer] + _rand(-10, 10);
      // Inverse-project so that, seen head-on, every dot lands exactly where
      // Figma put it.
      final k = (_focal - z) / _focal;
      _homeX[i] = c.dx + (g.cloudSlots[i].dx - c.dx) * k;
      _homeY[i] = c.dy + (g.cloudSlots[i].dy - c.dy) * k;
      _homeZ[i] = z;
      _cloudSize[i] = s * k;
      _cloudAlpha[i] = g.cloudAlphas[i];

      _orbR[i] = _orbitRadius[layer] * _rand(0.7, 1.3);
      _orbW[i] = _rand(0.5, 1.4) * (_rng.nextBool() ? 1 : -1);
      _orbP[i] = _rand(0, 2 * math.pi);
      _orbE[i] = _rand(0.45, 1.0);
      final tilt = _rand(0, math.pi);
      _orbCos[i] = math.cos(tilt);
      _orbSin[i] = math.sin(tilt);
      _orbZ[i] = _orbR[i] * _rand(1.5, 2.5);
      _noise[i] = _rand(0, 2 * math.pi);
      _catchResp[i] = _catchResponse[layer] * _rand(0.85, 1.15);
      _catchZeta[i] = _rand(0.5, 0.7);
      _delayA[i] = _rand(0, 0.22);
      _digit[i] = _rng.nextInt(10);
    }

    // Pair every shape with the cloud so neighbors stay neighbors: left part
    // of the number falls into the left of the cloud, and so on.
    final cloudOrder = _stripOrder(g.cloudSlots);
    final textOrder = _stripOrder(g.textPoints);
    final shield = _shieldTargets();
    final shieldOrder = _stripOrder([for (final s in shield) s.$1]);

    final textH = g.textRect.height;
    const edge = 0.08; // dissolve soft edge, as a fraction of text height
    for (var r = 0; r < n; r++) {
      final i = cloudOrder[r];
      final tp = g.textPoints[textOrder[r]];
      _aX[i] = tp.dx;
      _aY[i] = tp.dy;
      // Bottom of the glyphs crumbles first.
      final fromBottom = 1 - (tp.dy / textH);
      final u = (fromBottom + edge) / (1 + 2 * edge);
      _release[i] =
          ShieldTimeline.fall.start +
          ShieldTimeline.fall.duration * u.clamp(0.0, 1.0) +
          _rand(-0.015, 0.015);

      // Same particle, same look: each keeps its cloud size, opacity and
      // (halved) depth, so the shield reads as the cloud reshaped.
      final sh = shield[shieldOrder[r]];
      final z = _homeZ[i] * 0.5;
      final k = (_focal - z) / _focal;
      _shX[i] = c.dx + (sh.$1.dx - c.dx) * k;
      _shY[i] = c.dy + (sh.$1.dy - c.dy) * k;
      _shZ[i] = z;
      _shSize[i] = g.cloudSizes[i] * k;
      _shAlpha[i] = _cloudAlpha[i] * (sh.$2 ? 0.4 : 1);
    }

    // The shield's crown (topmost particles) lifts off into the icon; the
    // body pours into the balance. Each group is paired by strip order so
    // neighbors stay neighbors.
    final byHeight = List<int>.generate(n, (i) => i)
      ..sort((a, b) => _shY[a].compareTo(_shY[b]));
    final crown = byHeight.take(g.iconPoints.length).toList();
    final body = byHeight.skip(g.iconPoints.length).toList()..shuffle(_rng);
    for (final i in crown) {
      _icon[i] = 1;
    }
    // A few body particles never settle: they become the emitter that
    // streams out of the field's center once shielded.
    final strays = body.take(g.strays).toList();
    body.removeRange(0, strays.length);
    final screen = g.screen;
    final reach =
        math.sqrt(screen.width * screen.width + screen.height * screen.height) /
        2;
    for (var k = 0; k < strays.length; k++) {
      final i = strays[k];
      _stray[i] = 1;
      _eLife[i] = _rand(3.6, 5.0);
      _eSeed[i] = _rand(0, 2 * math.pi);
      _eReach[i] = reach * _rand(0.7, 1.0);
      _eSize[i] = _rand(1.0, 2.0);
      _delayB[i] = _rand(0, 0.3);
    }
    void pair(List<int> group, List<Offset> targets) {
      final from = _stripOrder([
        for (final i in group) Offset(_shX[i], _shY[i]),
      ]);
      final to = _stripOrder(targets);
      for (var r = 0; r < group.length; r++) {
        final i = group[from[r]];
        final p = targets[to[r]];
        _bX[i] = p.dx;
        _bY[i] = p.dy;
      }
    }

    pair(crown, g.iconPoints);
    pair(body, g.balancePoints);
    for (var i = 0; i < n; i++) {
      if (_stray[i] == 1) continue;
      if (_icon[i] == 1) {
        _delayB[i] = _rand(0, 0.1);
      } else {
        // Pour left to right.
        final bx = (_bX[i] - g.shieldRect.left) / g.shieldRect.width;
        _delayB[i] = 0.07 + bx.clamp(0.0, 1.0) * 0.3 + _rand(0, 0.09);
      }
    }

    // Dust: far specks behind the cloud and a few close, defocused squares
    // that drift past the lens.
    for (var j = 0; j < _dustCount; j++) {
      final bokeh = j >= _dustCount - _bokehCount;
      final ang = _rand(0, 2 * math.pi);
      final rad = math.sqrt(_rng.nextDouble());
      if (bokeh) {
        // In front of the cloud, close enough to the lens to blur and to
        // slide the most when the volume sways.
        _dX[j] = c.dx + math.cos(ang) * rad * 150;
        _dY[j] = c.dy + math.sin(ang) * rad * 125;
        _dZ[j] = _rand(110, 200);
        _dSize[j] = _rand(12, 26);
        _dAlpha[j] = _rand(0.04, 0.09);
        _dR[j] = _rand(10, 20);
        _dW[j] = _rand(0.1, 0.22) * (_rng.nextBool() ? 1 : -1);
      } else {
        _dX[j] = c.dx + math.cos(ang) * rad * 205;
        _dY[j] = c.dy + math.sin(ang) * rad * 165;
        _dZ[j] = _rand(-220, -80);
        _dSize[j] = _rand(0.9, 1.4);
        _dAlpha[j] = _rand(0.18, 0.45);
        _dR[j] = _rand(6, 14);
        _dW[j] = _rand(0.15, 0.35) * (_rng.nextBool() ? 1 : -1);
      }
      _dP[j] = _rand(0, 2 * math.pi);
    }
  }

  /// Shield slots: one particle per halftone cell, each nudged a little off
  /// its grid point. Leftovers ring the shield as a faint aura (flagged).
  List<(Offset, bool)> _shieldTargets() {
    final g = geometry;
    final cells = List<Offset>.of(g.shieldSlots)..shuffle(_rng);
    final out = <(Offset, bool)>[
      for (final cell in cells.take(n))
        (cell + Offset(_rand(-3.8, 3.8), _rand(-3.8, 3.8)), false),
    ];
    final center = g.shieldRect.center;
    final rx = g.shieldRect.width * 0.62;
    final ry = g.shieldRect.height * 0.56;
    while (out.length < n) {
      final ang = _rand(0, 2 * math.pi);
      final r = _rand(0.95, 1.08);
      out.add((
        center + Offset(math.cos(ang) * rx * r, math.sin(ang) * ry * r),
        true,
      ));
    }
    return out;
  }

  /// Orders points into vertical strips (by x), each strip sorted by y.
  /// Pairing two shapes by this order keeps neighborhoods together.
  List<int> _stripOrder(List<Offset> pts) {
    final idx = List<int>.generate(pts.length, (i) => i)
      ..sort((a, b) => pts[a].dx.compareTo(pts[b].dx));
    final strips = math.max(1, (math.sqrt(pts.length) / 2).round());
    final per = (pts.length / strips).ceil();
    final out = <int>[];
    for (var s = 0; s < pts.length; s += per) {
      final strip = idx.sublist(s, math.min(s + per, pts.length))
        ..sort((a, b) => pts[a].dy.compareTo(pts[b].dy));
      out.addAll(strip);
    }
    return out;
  }

  // ───────────────────────── Simulation ─────────────────────────

  /// Advances the field to [t] seconds after commit. [a] is seconds since
  /// loading completed (null while still loading).
  void update(double t, double? a) {
    final last = _lastUpdate;
    // Late artwork availability must start in the current cloud, rather than
    // applying many seconds of gravity to a newly attached particle.
    if (last == null && t > ShieldTimeline.fall.end + 0.1) {
      for (var i = 0; i < n; i++) {
        _mode[i] = _Mode.cloud;
        _x[i] = _homeX[i];
        _y[i] = _homeY[i];
        _z[i] = _homeZ[i];
        _setSpring(i, 0.3, 0.92);
        _fadeTo(
          i,
          t,
          0.1,
          size: _cloudSize[i],
          alpha: _cloudAlpha[i],
          white: 0,
          from: (_cloudSize[i], _cloudAlpha[i], 0),
        );
      }
    }
    final dt = last == null ? 0.0 : (t - last).clamp(0.0, 1 / 30);
    _lastUpdate = t;
    _t = t;
    _a = a;

    _events(t, a);

    final theta = _yaw(t, a);
    final phi = _pitch(t, a);
    final cosT = math.cos(theta), sinT = math.sin(theta);
    final cosP = math.cos(phi), sinP = math.sin(phi);
    final m = _motion;
    final breath = 1 + m * 0.012 * math.sin(2 * math.pi * t / 4.7);
    final sc = geometry.shieldRect.center;
    final layerFloat = [
      for (var l = 0; l < 4; l++)
        m *
            _floatAmp[l] *
            math.sin(2 * math.pi * t / _floatPeriod[l] + l * 1.7),
    ];

    final steps = math.max(1, (dt * 240).ceil());
    final h = dt / steps;

    for (var i = 0; i < n; i++) {
      if (_mode[i] == _Mode.attached) {
        if (t < _release[i]) continue;
        _breakFree(i, t);
      }

      double tx, ty, tz;
      switch (_mode[i]) {
        case _Mode.cloud:
          final ang = _orbP[i] + _orbW[i] * t;
          final ox = _orbR[i] * math.cos(ang);
          final oy = _orbR[i] * _orbE[i] * math.sin(ang);
          final rx = ox * _orbCos[i] - oy * _orbSin[i];
          final ry = ox * _orbSin[i] + oy * _orbCos[i];
          final rz = _orbZ[i] * math.sin(ang + 1.1);
          final wx = (_homeX[i] + m * rx - _c0.dx) * breath;
          final wy =
              (_homeY[i] + m * ry + layerFloat[_layer[i]] - _c0.dy) * breath;
          final wz = _homeZ[i] + m * rz;
          final x1 = wx * cosT + wz * sinT;
          final z1 = -wx * sinT + wz * cosT;
          tx = _c0.dx + x1;
          ty = _c0.dy + wy * cosP - z1 * sinP;
          tz = wy * sinP + z1 * cosP;
          // Catch springs relax into tight orbit-tracking springs.
          final u = _smooth((t - _release[i] - 1.4) / 1.2);
          _setSpring(
            i,
            _lerp(_catchResp[i], 0.3, u),
            _lerp(_catchZeta[i], 0.92, u),
          );
        case _Mode.shield:
          // The wave swells each row outward as it passes.
          final swell = 1 + 0.05 * _wave(_shY[i], a);
          final wx = (_shX[i] - sc.dx) * swell;
          final wy = (_shY[i] - sc.dy) * swell;
          final wz = _shZ[i];
          final x1 = wx * cosT + wz * sinT;
          final z1 = -wx * sinT + wz * cosT;
          tx = sc.dx + x1;
          ty = sc.dy + wy * cosP - z1 * sinP;
          tz = wy * sinP + z1 * cosP;
        case _Mode.balance:
          tx = _bX[i];
          ty = _bY[i];
          tz = 0;
        case _Mode.emit:
          // Placed directly on its path; no spring.
          _emit(i, a ?? 0);
          continue;
        case _Mode.attached:
          continue;
      }

      if (reduceMotion) {
        _x[i] = tx;
        _y[i] = ty;
        _z[i] = tz;
        continue;
      }
      final k = _k[i], c = _c[i];
      var x = _x[i], y = _y[i], z = _z[i];
      var vx = _vx[i], vy = _vy[i], vz = _vz[i];
      var fx = 0.0, fy = 0.0;
      final age = t - _release[i];
      if (_mode[i] == _Mode.cloud && age < _curlFor) {
        final amp = _curl * m * (1 - _smooth(age / _curlFor));
        fx = amp * math.sin(y * 0.045 + t * 1.7 + _noise[i]);
        fy = amp * 0.7 * math.cos(x * 0.045 - t * 1.3 + _noise[i]);
      }
      for (var s = 0; s < steps; s++) {
        vx += (k * (tx - x) - c * vx + fx) * h;
        vy += (k * (ty - y) - c * vy + fy) * h;
        vz += (k * (tz - z) - c * vz) * h;
        x += vx * h;
        y += vy * h;
        z += vz * h;
      }
      _x[i] = x;
      _y[i] = y;
      _z[i] = z;
      _vx[i] = vx;
      _vy[i] = vy;
      _vz[i] = vz;
    }

    _blink(t, a);
    _buildFrame();
    notifyListeners();
  }

  void _breakFree(int i, double t) {
    final r = geometry.textRect;
    final s = ShieldTimeline.fallScale(t);
    final dy = ShieldTimeline.fallDy(t);
    _x[i] = r.center.dx + (_aX[i] - r.width / 2) * s;
    _y[i] = r.center.dy + dy + (_aY[i] - r.height / 2) * s;
    _z[i] = 0;
    if (reduceMotion) {
      _x[i] = _homeX[i];
      _y[i] = _homeY[i];
      _z[i] = _homeZ[i];
    }
    // Keep the fall's momentum and spray outward from the impact, so the
    // cloud billows sideways before it settles.
    _vx[i] = (_x[i] - r.center.dx) * 0.9 + _rand(-110, 110);
    _vy[i] = ShieldTimeline.fallVelocity(t) + _rand(0, 55);
    _vz[i] = _rand(-140, 140);
    _mode[i] = _Mode.cloud;
    _setSpring(i, _catchResp[i], _catchZeta[i]);
    _fadeTo(
      i,
      t,
      0.9,
      size: _cloudSize[i],
      alpha: _cloudAlpha[i],
      white: 0,
      from: (
        _textDot,
        reduceMotion ? 0 : (_aY[i] >= geometry.textDimFrom ? _textZecAlpha : 1),
        1,
      ),
    );
  }

  void _events(double t, double? a) {
    if (!_prepared && t >= ShieldTimeline.blinksFrom - 0.3) {
      _prepared = true;
      Haptics.prepare();
    }
    if (a == null) return;

    if (!_assembled) {
      _assembled = true;
      Haptics.prepare();
    }
    for (var i = 0; i < n; i++) {
      final at = reduceMotion ? _reducedSwap : _delayA[i];
      if (_mode[i] == _Mode.cloud && a >= at) _toShield(i, t);
    }
    if (!_locked && a >= ShieldTimeline.lock) {
      _locked = true;
      for (var i = 0; i < n; i++) {
        if (_mode[i] != _Mode.shield) _toShield(i, t);
        _setSpring(i, 0.16, 1.0);
      }
    }
    if (a >= ShieldTimeline.split && !reduceMotion) {
      for (var i = 0; i < n; i++) {
        if (_mode[i] == _Mode.shield &&
            _stray[i] == 1 &&
            a >= ShieldTimeline.split + _delayB[i]) {
          _eStartAt[i] = a;
          _eStartX[i] = _x[i];
          _eStartY[i] = _y[i];
          _eStartZ[i] = _z[i];
          _eSeed[i] = math.atan2(
            _y[i] - geometry.emitter.dy,
            _x[i] - geometry.emitter.dx,
          );
          _mode[i] = _Mode.emit;
          _fadeTo(
            i,
            t,
            0.3,
            size: _eSize[i],
            alpha: _rand(0.55, 0.9),
            white: 0.7,
          );
          continue;
        }
        if (_mode[i] == _Mode.shield &&
            a >= ShieldTimeline.split + _delayB[i]) {
          _mode[i] = _Mode.balance;
          final icon = _icon[i] == 1;
          _setSpring(
            i,
            icon ? _rand(0.65, 0.8) : _rand(0.65, 0.85),
            icon ? 0.9 : 0.95,
          );
          _fadeTo(
            i,
            t,
            0.6,
            size: icon ? _iconDot : _balanceDot,
            alpha: !icon && _bY[i] >= geometry.balanceDimFrom
                ? _balanceZecAlpha
                : 1,
            white: 1,
          );
        }
      }
    }
  }

  /// Preserve the shield's residual particles through the landing. Subsequent
  /// passes turn by the golden angle and fade before the screen edge.
  void _emit(int i, double a) {
    final local = math.max(0.0, a - _eStartAt[i]);
    final life = _eLife[i];
    final cycle = (local / life).floor();
    final u = local / life - cycle;
    final ang = _eSeed[i] + cycle * 2.39996;
    final dirX = math.cos(ang), dirY = math.sin(ang);
    final reach = _eReach[i];
    final first = cycle == 0;
    final d = (first ? 0 : 6) + reach * math.pow(u, 1.3);
    // A slight sideways sway so the rays aren't ruler-straight.
    final sway = 7 * u * math.sin(1.7 * a + _noise[i] + cycle);
    final c = first ? Offset(_eStartX[i], _eStartY[i]) : geometry.emitter;
    _x[i] = c.dx + dirX * d - dirY * sway;
    _y[i] = c.dy + dirY * d + dirX * sway;
    _z[i] = first ? _eStartZ[i] * (1 - _smooth(local / 0.35)) : 0;
    final speed = reach * 1.3 * math.pow(math.max(u, 0.01), 0.3) / life;
    _vx[i] = dirX * speed;
    _vy[i] = dirY * speed;
    _eEnv[i] = (first ? 1 : _smooth(u / 0.15)) * (1 - _smooth((u - 0.6) / 0.4));
    _eGrow[i] = first ? 1 : 0.45 + 0.95 * u;
  }

  void _toShield(int i, double t) {
    if (_mode[i] == _Mode.attached) _breakFree(i, t);
    _mode[i] = _Mode.shield;
    // A tangential kick around the center turns the gather into a vortex.
    final dx = _x[i] - _c0.dx;
    final dy = _y[i] - _c0.dy;
    final swirl = 2.4 * _rand(0.8, 1.2) * _motion;
    _vx[i] += -dy * swirl;
    _vy[i] += dx * swirl;
    _setSpring(i, _rand(0.48, 0.72), 0.72);
    _fadeTo(i, t, 0.8, size: _shSize[i], alpha: _shAlpha[i], white: 0.25);
  }

  void _setSpring(int i, double response, double zeta) {
    final w = 2 * math.pi / response;
    _k[i] = w * w;
    _c[i] = 2 * zeta * w;
  }

  void _fadeTo(
    int i,
    double t,
    double duration, {
    required double size,
    required double alpha,
    required double white,
    (double, double, double)? from,
  }) {
    final cur = from ?? _visual(i, t);
    _s0[i] = cur.$1;
    _a0[i] = cur.$2;
    _w0[i] = cur.$3;
    _s1[i] = size;
    _a1[i] = alpha;
    _w1[i] = white;
    _vt[i] = t;
    _vd[i] = duration;
  }

  (double, double, double) _visual(int i, double t) {
    final q = _smooth((t - _vt[i]) / _vd[i]);
    return (
      _lerp(_s0[i], _s1[i], q),
      _lerp(_a0[i], _a1[i], q),
      _lerp(_w0[i], _w1[i], q),
    );
  }

  // Sway: two incommensurate slow waves, never a strict loop.
  double _swayAmount(double t, double? a) {
    final cloudIn = _smooth((t - 0.6) / 1.4);
    if (a == null) return cloudIn * _motion;
    // Calmer while the shield holds, still before it pours into the balance.
    final hold = _lerp(1, 0.55, _smooth(a / ShieldTimeline.assemble));
    final out = 1 - _smooth((a - ShieldTimeline.split) / 0.3);
    return cloudIn * hold * out * _motion;
  }

  double _yaw(double t, double? a) =>
      _swayAmount(t, a) *
      (0.11 * math.sin(2 * math.pi * t / 7.3) +
          0.05 * math.sin(2 * math.pi * t / 11.9 + 1.3));

  double _pitch(double t, double? a) =>
      _swayAmount(t, a) * 0.05 * math.sin(2 * math.pi * t / 9.1 + 0.7);

  /// Band of light and scale rolling down the locked shield, 0..1 for a
  /// particle whose shield slot sits at [slotY].
  double _wave(double slotY, double? a) {
    if (a == null || reduceMotion) return 0;
    final p = ShieldTimeline.wave.progress(a);
    if (p <= 0 || p >= 1) return 0;
    final r = geometry.shieldRect;
    const reach = 40.0; // start above the top edge, end below the bottom
    final front =
        r.top - reach + (r.height + 2 * reach) * _waveCurve.transform(p);
    final d = slotY - front;
    // Wide, soft band whose strength eases in and out over the pass.
    return math.sin(math.pi * p) * math.exp(-(d * d) / (2 * 26 * 26));
  }

  // ───────────────────────── Blinks & haptics ─────────────────────────

  void _blink(double t, double? a) {
    if (a != null && a >= ShieldTimeline.lock) return;
    if (t < ShieldTimeline.blinksFrom || t < _nextBlink) return;

    var i = _rng.nextInt(n);
    for (var tries = 0; tries < 12; tries++) {
      if (_mode[i] != _Mode.attached && t - _blinkAt[i] > 0.8) break;
      i = _rng.nextInt(n);
    }
    _blinkAt[i] = t;
    if (hapticsEnabled && t - _lastHaptic >= 0.055) {
      _lastHaptic = t;
      Haptics.impact(ImpactStyle.medium, intensity: _blinkIntensity[_layer[i]]);
    }

    double interval;
    if (a != null) {
      // Drumroll: the gather speeds the rain up until the shield locks.
      final u = (a / ShieldTimeline.assemble).clamp(0.0, 1.0);
      interval = _lerp(0.14, 0.05, u * u) * _rand(0.8, 1.2);
    } else {
      final ramp = ((t - ShieldTimeline.blinksFrom) / ShieldTimeline.blinksRamp)
          .clamp(0.0, 1.0);
      interval = _lerp(0.55, 0.24, ramp) * _rand(0.45, 1.55);
      // Occasional quick pairs keep the rhythm organic.
      if (_rng.nextDouble() < 0.12) interval = _rand(0.07, 0.1);
    }
    _nextBlink = t + interval;
  }

  static double _blinkEnvelope(double since) {
    if (since < 0 || since > 0.8) return 0;
    if (since < 0.04) return since / 0.04;
    return math.exp(-(since - 0.04) / 0.16);
  }

  // ───────────────────────── Rendering ─────────────────────────

  /// Field-wide opacity for the balance group and the icon group.
  (double, double) _globalAlpha(double? a) {
    if (a == null) return (1, 1);
    if (reduceMotion) {
      // Swap shapes while invisible; let the crisp UI take over at the split.
      final dip = _smooth((a - _reducedSwap).abs() / _reducedSwap);
      final v = dip * (1 - _smooth((a - ShieldTimeline.split) / 0.25));
      return (v, v);
    }
    // Each group fades into its crisp counterpart once it has arrived.
    return (
      1 - _smooth(ShieldTimeline.particlesOut.progress(a)),
      1 - _smooth(ShieldTimeline.iconIn.progress(a)),
    );
  }

  /// Emitted particles shimmer gently as they travel.
  double _twinkle(int i, double t) =>
      0.7 + 0.3 * math.sin(1.3 * t + _noise[i] * 3);

  double _dustAlpha(double t, double? a) {
    var v = _smooth((t - 0.6) / 1.2);
    if (a != null) v *= 1 - _smooth(a / 0.5);
    return v * (reduceMotion ? 0 : 1);
  }

  void _buildFrame() {
    final t = _t;
    final a = _a;
    final c0 = _c0;
    final yaw = _yaw(t, a);
    final cosT = math.cos(yaw), sinT = math.sin(yaw);
    final bump = reduceMotion ? 0.0 : 1.0;
    final (groupBalance, groupIcon) = _globalAlpha(a);
    final dustA = _dustAlpha(t, a);
    _count = 0;
    _gCount = 0;
    _projected.clear();

    // Far dust behind everything.
    if (dustA > 0.001) {
      for (var j = 0; j < _dustCount; j++) {
        final ang = _dP[j] + _dW[j] * t;
        final wx = _dX[j] + _dR[j] * math.cos(ang) - c0.dx;
        final wy = _dY[j] + _dR[j] * 0.6 * math.sin(ang) - c0.dy;
        final wz = _dZ[j];
        final x1 = wx * cosT + wz * sinT;
        final z1 = -wx * sinT + wz * cosT;
        final s = _focal / (_focal - z1);
        final px = c0.dx + x1 * s;
        final py = c0.dy + wy * s;
        final bokeh = j >= _dustCount - _bokehCount;
        if (bokeh) {
          _pushGlow(
            SpriteAtlas.halo,
            px,
            py,
            _dSize[j] * s,
            _dAlpha[j] * dustA,
            0xD9,
            0xD9,
            0xD9,
          );
        } else {
          _push(
            SpriteAtlas.dot,
            px,
            py,
            _dSize[j] * s,
            0,
            _dAlpha[j] * dustA,
            0xD9,
          );
        }
      }
    }

    for (var i = 0; i < n; i++) {
      if (_mode[i] == _Mode.attached) continue;
      final q = _smooth((t - _vt[i]) / _vd[i]);
      final visSize = _lerp(_s0[i], _s1[i], q);
      final visAlpha = _lerp(_a0[i], _a1[i], q);
      final visWhite = _lerp(_w0[i], _w1[i], q);
      final global = _mode[i] == _Mode.emit
          ? _eEnv[i] * _twinkle(i, t)
          : _icon[i] == 1
          ? groupIcon
          : groupBalance;
      final e = _blinkEnvelope(t - _blinkAt[i]);
      final g = _mode[i] == _Mode.shield ? _wave(_shY[i], a) : 0.0;
      // A brief white band marks the lock, as in the original video.
      final flash = math.max(e, (g * 1.3).clamp(0.0, 1.0));

      // At the handover each particle is pinned to its exact glyph point,
      // so dots and crisp text/icon coincide pixel for pixel.
      var x = _x[i], y = _y[i], z = _z[i];
      var lock = 0.0;
      if (_mode[i] == _Mode.balance && a != null) {
        final arrive = _icon[i] == 1
            ? ShieldTimeline.iconIn.start
            : ShieldTimeline.textIn.start;
        lock = _smooth((a - arrive + 0.2) / 0.4);
        x = _lerp(x, _bX[i], lock);
        y = _lerp(y, _bY[i], lock);
        z = _lerp(z, 0, lock);
      }
      final s = _focal / (_focal - z);
      final px = c0.dx + (x - c0.dx) * s;
      final py = c0.dy + (y - c0.dy) * s;
      final grow = _mode[i] == _Mode.emit ? _eGrow[i] : 1.0;
      final size = visSize * s * grow * (1 + bump * (0.9 * e + 0.55 * g));
      var alpha = visAlpha + (1 - visAlpha) * flash;
      alpha *= global;
      final white = math.max(visWhite, flash);
      final grey = (0xD9 + (0xFF - 0xD9) * white).round();
      if (captureProjectedParticles) {
        _projected.add(
          ShieldParticleSample(
            position: Offset(px, py),
            velocity: Offset(_vx[i] * s, _vy[i] * s),
            size: size,
            alpha: alpha,
            color: Color.fromARGB(255, grey, grey, grey),
          ),
        );
      }
      if (alpha < 0.004) continue;

      // Fast movers stretch into streaks along their velocity.
      final speed =
          math.sqrt(_vx[i] * _vx[i] + _vy[i] * _vy[i]) * s * (1 - lock);
      Sprite sprite = kParticleGlyph == ParticleGlyph.digit
          ? SpriteAtlas.digits[_digit[i]]
          : SpriteAtlas.dot;
      var rot = 0.0;
      if (!reduceMotion && speed > 260 && kParticleGlyph == ParticleGlyph.dot) {
        final aspect = 1 + speed * 0.009;
        if (aspect >= 1.7) {
          final idx = aspect < 2.8
              ? 0
              : aspect < 4.8
              ? 1
              : 2;
          sprite = SpriteAtlas.streaks[idx];
          rot = math.atan2(_vy[i], _vx[i]);
        }
      }
      _push(sprite, px, py, size, rot, alpha, grey);

      // Wave glow: soft white light around the band.
      if (g > 0.05) {
        _pushGlow(
          SpriteAtlas.halo,
          px,
          py,
          math.max(size * 4.5, 8),
          0.24 * g * global,
          0xFF,
          0xFF,
          0xFF,
        );
      }

      // Blink halo: white core, brand-pink bloom, added light.
      if (e > 0.02) {
        _pushGlow(
          SpriteAtlas.halo,
          px,
          py,
          math.max(size * 5, 9),
          0.55 * e * global,
          0xFF,
          0xFF,
          0xFF,
        );
        _pushGlow(
          SpriteAtlas.halo,
          px,
          py,
          math.max(size * 12, 22),
          0.4 * e * global,
          0xA8,
          0x38,
          0x61,
        );
      }
    }
  }

  void _push(
    Sprite sp,
    double x,
    double y,
    double size,
    double rot,
    double alpha,
    int grey,
  ) {
    final o = _count * 4;
    final scale = size / sp.unit;
    final sc = scale * math.cos(rot);
    final ss = scale * math.sin(rot);
    _rst[o] = sc;
    _rst[o + 1] = ss;
    _rst[o + 2] = x - (sc * sp.anchor.dx - ss * sp.anchor.dy);
    _rst[o + 3] = y - (ss * sp.anchor.dx + sc * sp.anchor.dy);
    _rects[o] = sp.rect.left;
    _rects[o + 1] = sp.rect.top;
    _rects[o + 2] = sp.rect.right;
    _rects[o + 3] = sp.rect.bottom;
    final a8 = (alpha.clamp(0.0, 1.0) * 255).round();
    _colors[_count] = (a8 << 24) | (grey << 16) | (grey << 8) | grey;
    _count++;
  }

  void _pushGlow(
    Sprite sp,
    double x,
    double y,
    double diameter,
    double alpha,
    int r,
    int g,
    int b,
  ) {
    if (_gCount * 4 >= _gRst.length) return;
    final o = _gCount * 4;
    final scale = diameter / sp.unit;
    _gRst[o] = scale;
    _gRst[o + 1] = 0;
    _gRst[o + 2] = x - scale * sp.anchor.dx;
    _gRst[o + 3] = y - scale * sp.anchor.dy;
    _gRects[o] = sp.rect.left;
    _gRects[o + 1] = sp.rect.top;
    _gRects[o + 2] = sp.rect.right;
    _gRects[o + 3] = sp.rect.bottom;
    final a8 = (alpha.clamp(0.0, 1.0) * 255).round();
    _gColors[_gCount] = (a8 << 24) | (r << 16) | (g << 8) | b;
    _gCount++;
  }

  static final _paint = Paint()..filterQuality = FilterQuality.low;
  static final _glowPaint = Paint()
    ..filterQuality = FilterQuality.low
    ..blendMode = BlendMode.plus;

  void paint(Canvas canvas) {
    if (_count > 0) {
      canvas.drawRawAtlas(
        atlas.image,
        Float32List.sublistView(_rst, 0, _count * 4),
        Float32List.sublistView(_rects, 0, _count * 4),
        Int32List.sublistView(_colors, 0, _count),
        BlendMode.modulate,
        null,
        _paint,
      );
    }
    if (_gCount > 0) {
      canvas.drawRawAtlas(
        atlas.image,
        Float32List.sublistView(_gRst, 0, _gCount * 4),
        Float32List.sublistView(_gRects, 0, _gCount * 4),
        Int32List.sublistView(_gColors, 0, _gCount),
        BlendMode.modulate,
        null,
        _glowPaint,
      );
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _smooth(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}

/// Wave travel: gentle ease in and out (sine-like), so the sheen glides.
const _waveCurve = Cubic(0.45, 0, 0.55, 1);

/// Paints a [ParticleField]; repaints whenever the field advances.
class ParticlePainter extends CustomPainter {
  ParticlePainter(this.field) : super(repaint: field);

  final ParticleField field;

  @override
  void paint(Canvas canvas, Size size) => field.paint(canvas);

  @override
  bool shouldRepaint(ParticlePainter old) => old.field != field;
}
