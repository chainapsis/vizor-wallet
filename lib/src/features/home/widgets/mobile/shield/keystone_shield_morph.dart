import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../address_scan/widgets/mobile_scan_viewfinder_geometry.dart';
import '../../../../keystone/widgets/keystone_pczt_qr_stage.dart'
    show keystoneQrFrameInterval;
import 'particles/particle_field.dart';
import 'particles/shape_sampler.dart';

enum KeystoneShieldFocusStage { cloud, qr, scanner }

enum KeystoneShieldAnchorKind { qr, frame, torch }

/// Presentation inputs only. Signing and broadcasting remain with their owner.
class KeystoneShieldFocus {
  const KeystoneShieldFocus({
    required this.stage,
    required this.urParts,
    required this.scannerBuilder,
    this.onQrReadyChanged,
  });
  final KeystoneShieldFocusStage stage;
  final List<String> urParts;
  final Widget Function(BoxConstraints, KeystoneShieldMorph) scannerBuilder;
  final ValueChanged<bool>? onQrReadyChanged;
}

/// One matrix supplies both the scan surface and the particle destinations.
class KeystoneShieldQrFrames {
  KeystoneShieldQrFrames(this.parts);
  final List<String> parts;
  final Map<int, QrImage> _frames = {};

  QrImage frame(int index) => _frames[index] ??= QrImage(
    QrCode.fromData(
      data: parts[index],
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ),
  );

  /// Particles fill the white surface, leaving the dark QR modules empty.
  List<ShieldParticleSample> whiteCells(int index, Rect bounds, double dpr) {
    final grid = _KeystoneQrGrid(frame(index), bounds, dpr);
    final points = <ShieldParticleSample>[];
    for (var y = -grid.quiet; y < grid.count + grid.quiet; y++) {
      for (var x = -grid.quiet; x < grid.count + grid.quiet; x++) {
        if (grid.isDark(x, y)) continue;
        final rect = grid.cell(x, y);
        points.add(
          ShieldParticleSample(
            position: rect.center,
            size: math.max(rect.width, rect.height),
            alpha: 1,
            square: 1,
            extent: rect.size,
            arrival: grid.arrival(x, y),
          ),
        );
      }
    }
    return points;
  }

  /// The settled scan surface uses exactly the particle grid's pixel edges.
  void paint(Canvas canvas, int index, Rect bounds, double dpr) {
    final grid = _KeystoneQrGrid(frame(index), bounds, dpr);
    final paint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xFFFFFFFF);
    canvas.drawRect(grid.surface, paint);
    paint.color = const Color(0xFF000000);
    for (var y = 0; y < grid.count; y++) {
      for (var x = 0; x < grid.count; x++) {
        if (grid.isDark(x, y)) canvas.drawRect(grid.cell(x, y), paint);
      }
    }
  }
}

class _KeystoneQrGrid {
  _KeystoneQrGrid(this.image, this.bounds, this.dpr);
  final QrImage image;
  final Rect bounds;
  final double dpr;
  final int quiet = 4;
  int get count => image.moduleCount;
  double get pitch => bounds.width / (count + quiet * 2);
  double _edge(double value) => (value * dpr).round() / dpr;
  bool isDark(int x, int y) =>
      x >= 0 && y >= 0 && x < count && y < count && image.isDark(y, x);
  double arrival(int x, int y) {
    final sweep = (x + y + quiet * 2) / (2 * (count + quiet * 2 - 1));
    if (x < 0 || y < 0 || x >= count || y >= count) {
      return 0.62 + 0.10 * sweep;
    }
    if ((x < 7 && y < 7) ||
        (x >= count - 7 && y < 7) ||
        (x < 7 && y >= count - 7)) {
      return 0.70 + 0.08 * sweep;
    }
    final center = (count - 1) / 2;
    final radius = math.max((x - center).abs(), (y - center).abs()) / center;
    return 0.80 + 0.16 * (1 - radius) + 0.04 * sweep;
  }

  Rect cell(int x, int y) => Rect.fromLTRB(
    _edge(bounds.left + (x + quiet) * pitch),
    _edge(bounds.top + (y + quiet) * pitch),
    _edge(bounds.left + (x + quiet + 1) * pitch),
    _edge(bounds.top + (y + quiet + 1) * pitch),
  );
  Rect get surface => Rect.fromPoints(
    cell(-quiet, -quiet).topLeft,
    cell(count + quiet - 1, count + quiet - 1).bottomRight,
  );
}

/// Retargets the visible particles without restarting the cloud or transaction.
class KeystoneShieldMorph {
  final spaceKey = GlobalKey();
  final Map<KeystoneShieldAnchorKind, Rect> _bounds = {};
  KeystoneShieldFocus? _focus;
  KeystoneShieldQrFrames? _qr;
  List<Offset>? _torch;
  List<ShieldParticleSample> _from = [];
  List<ShieldParticleSample> _to = [];
  List<ShieldParticleSample> _particles = [];
  List<int> _targetIndices = [];
  int _scannerFrameCount = 0;
  KeystoneShieldFocusStage _goal = KeystoneShieldFocusStage.cloud;
  KeystoneShieldFocusStage _settled = KeystoneShieldFocusStage.cloud;
  double? _start;
  double _time = 0;
  double _duration = 1;
  double _progress = 1;
  double _fromBlack = 0;
  double blackMix = 0;
  double _qrStarted = 0;
  bool _pending = false;
  bool _disposed = false;
  bool _lastReady = false;
  bool _scannerWasVisible = false;
  double _cameraMix = 0;
  double _fromCamera = 0;
  double _glyphMix = 0;
  double _fromGlyph = 0;
  double devicePixelRatio = 1;
  bool reduceMotion = false;
  double footerOpacity = 0;
  double? _footerAt;
  double _footerFrom = 0;
  double _footerTo = 0;
  double _footerDuration = 0.18;

  double get footerDy =>
      reduceMotion || _footerTo == 0 ? 0 : 6 * (1 - footerOpacity);
  bool get footerInteractive =>
      _goal != KeystoneShieldFocusStage.cloud && footerOpacity >= 0.999;

  void _fadeFooter(double target) {
    _footerFrom = footerOpacity;
    _footerTo = target;
    _footerAt = _time;
    _footerDuration = reduceMotion
        ? 0.12
        : target == 1
        ? 0.18
        : 0.14;
  }

  void _updateFooter() {
    final entranceDuration = reduceMotion ? 0.12 : 0.18;
    if (_goal != KeystoneShieldFocusStage.cloud &&
        _footerTo != 1 &&
        !_pending &&
        (_start == null || (_time - _start!) >= _duration - entranceDuration)) {
      _fadeFooter(1);
      if (_start != null) _footerAt = _start! + _duration - entranceDuration;
    }
    final at = _footerAt;
    if (at == null) return;
    final p = ((_time - at) / _footerDuration).clamp(0.0, 1.0);
    footerOpacity = ui.lerpDouble(
      _footerFrom,
      _footerTo,
      Curves.easeOut.transform(p),
    )!;
    if (p == 1) _footerAt = null;
  }

  KeystoneShieldFocusStage get stage => _goal;
  bool get active =>
      _goal != KeystoneShieldFocusStage.cloud || _pending || _start != null;
  bool get cloudReady => !active;
  bool get qrReady =>
      !_pending && _start == null && _settled == KeystoneShieldFocusStage.qr;
  bool get scannerVisible =>
      _goal == KeystoneShieldFocusStage.scanner ||
      (_scannerWasVisible && (_pending || _start != null));
  double get scannerOpacity => _cameraMix;
  double get scannerGlyphOpacity => _glyphMix;
  double get leavingOpacity => _goal == KeystoneShieldFocusStage.cloud
      ? 1 - Curves.easeInOut.transform(_progress)
      : 1;
  List<ShieldParticleSample> get particles => _particles;

  Future<void> prepare() async {
    try {
      const icon = Icons.flashlight_on_outlined;
      final points = await ShapeSampler.picture(
        const Size(24, 24),
        (canvas) {
          final painter = TextPainter(
            text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontSize: 24,
                height: 1,
                color: const Color(0xFFFFFFFF),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(
            canvas,
            Offset((24 - painter.width) / 2, (24 - painter.height) / 2),
          );
          painter.dispose();
        },
        count: 32,
        random: math.Random(17),
      );
      if (!_disposed) _torch = points;
    } catch (error) {
      // The real icon and button remain usable if decorative sampling fails.
      if (!_disposed) _torch = const [];
      debugPrint('Keystone torch particle sampling unavailable: $error');
    }
  }

  void configure(KeystoneShieldFocus focus) {
    final changedParts = _qr == null || !identical(_qr!.parts, focus.urParts);
    _focus = focus;
    if (changedParts) _qr = KeystoneShieldQrFrames(focus.urParts);
    if (_goal != focus.stage ||
        (changedParts && focus.stage == KeystoneShieldFocusStage.qr)) {
      _scannerWasVisible = scannerOpacity > 0;
      _fromCamera = _cameraMix;
      _fromGlyph = _glyphMix;
      _progress = 0;
      _goal = focus.stage;
      if (_goal == KeystoneShieldFocusStage.cloud) _fadeFooter(0);
      _pending = true;
      _start = null;
      _reportReady(false);
    }
  }

  void setBounds(KeystoneShieldAnchorKind kind, Rect rect) {
    if (_disposed || rect.isEmpty || _bounds[kind] == rect) return;
    _bounds[kind] = rect;
    // A held QR follows layout changes directly. Restarting it here creates a
    // feedback loop when the enabled footer's border changes its own height.
    if (kind == KeystoneShieldAnchorKind.qr && qrReady) {
      _particles = _qr!.whiteCells(qrIndex, rect, devicePixelRatio);
      return;
    }
    if (_goal != KeystoneShieldFocusStage.cloud) {
      _scannerWasVisible = _cameraMix > 0;
      _fromCamera = _cameraMix;
      _fromGlyph = _glyphMix;
      _progress = 0;
      _start = null;
      _pending = true;
      _reportReady(false);
    }
  }

  void _reportReady(bool value) {
    if (_lastReady == value) return;
    _lastReady = value;
    final callback = _focus?.onQrReadyChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _lastReady == value) callback?.call(value);
    });
  }

  List<ShieldParticleSample>? _target(List<ShieldParticleSample> cloud) {
    switch (_goal) {
      case KeystoneShieldFocusStage.cloud:
        return cloud.isNotEmpty
            ? cloud
            : [
                for (final p in _particles)
                  ShieldParticleSample(
                    position: p.position,
                    size: p.size,
                    alpha: 0,
                    square: p.square,
                    extent: p.extent,
                  ),
              ];
      case KeystoneShieldFocusStage.qr:
        final bounds = _bounds[KeystoneShieldAnchorKind.qr];
        if (bounds == null || _qr == null || _qr!.parts.isEmpty) return null;
        return _qr!.whiteCells(0, bounds, devicePixelRatio);
      case KeystoneShieldFocusStage.scanner:
        final frame = _bounds[KeystoneShieldAnchorKind.frame];
        final torch = _bounds[KeystoneShieldAnchorKind.torch];
        if (frame == null || torch == null || _torch == null) return null;
        final points = <ShieldParticleSample>[];
        for (final metric in mobileScanViewfinderPath(
          frame.size,
        ).computeMetrics()) {
          for (var d = 0.0; d <= metric.length; d += 1.8) {
            final position =
                frame.topLeft + metric.getTangentForOffset(d)!.position;
            if (frame.inflate(1.5).contains(position)) {
              points.add(
                ShieldParticleSample(
                  position: position,
                  size: 3,
                  alpha: 1,
                  arrival: 0.82,
                ),
              );
            }
          }
        }
        _scannerFrameCount = points.length;
        points.addAll(
          _torch!.map(
            (p) => ShieldParticleSample(
              position:
                  torch.topLeft +
                  Offset(p.dx * torch.width / 24, p.dy * torch.height / 24),
              size: 1.7 * torch.width / 24,
              alpha: 1,
              arrival: 0.96,
            ),
          ),
        );
        return points;
    }
  }

  int get qrIndex => _qr == null || _qr!.parts.isEmpty || !qrReady
      ? 0
      : (((_time - _qrStarted) / (keystoneQrFrameInterval.inMicroseconds / 1e6))
                .floor()) %
            _qr!.parts.length;

  ShieldParticleSample _faded(ShieldParticleSample p, double alpha) =>
      ShieldParticleSample(
        position: p.position,
        velocity: p.velocity,
        size: p.size,
        alpha: alpha,
        color: p.color,
        square: p.square,
        extent: p.extent,
        arrival: p.arrival,
      );

  Rect _visibleBounds(List<ShieldParticleSample> particles) {
    final visible = particles.where((p) => p.alpha > 0.01).toList();
    final points = visible.isEmpty ? particles : visible;
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final p in points) {
      left = math.min(left, p.position.dx);
      top = math.min(top, p.position.dy);
      right = math.max(right, p.position.dx);
      bottom = math.max(bottom, p.position.dy);
    }
    return Rect.fromLTWH(
      left,
      top,
      math.max(1, right - left),
      math.max(1, bottom - top),
    );
  }

  Offset _project(Offset point, Rect from, Rect to) => Offset(
    to.left + (point.dx - from.left) / from.width * to.width,
    to.top + (point.dy - from.top) / from.height * to.height,
  );

  bool _onRim(Offset point, Rect rect) =>
      !rect.deflate(rect.shortestSide * 0.12).contains(point);

  int _corner(Offset point, Rect rect) =>
      (point.dx >= rect.center.dx ? 1 : 0) +
      (point.dy >= rect.center.dy ? 2 : 0);

  ShieldParticleSample _clearScannerInterior(
    ShieldParticleSample source,
    Rect qr,
  ) {
    final relative = source.position - qr.center;
    final radius =
        (math.max(relative.dx.abs(), relative.dy.abs()) / (qr.shortestSide / 2))
            .clamp(0.0, 1.0);
    final outward = relative.distance < 0.001
        ? Offset.zero
        : relative / relative.distance * 10;
    return ShieldParticleSample(
      position: source.position + outward,
      size: source.size * 0.45,
      alpha: 0,
      square: 0,
      arrival: 0.32 + 0.28 * radius,
    );
  }

  void _pairTargets(
    List<ShieldParticleSample> origin,
    List<ShieldParticleSample> target,
    List<ShieldParticleSample> cloud,
  ) {
    final count = math.max(origin.length, target.length);
    _from = [
      ...origin,
      for (var i = origin.length; i < count; i++)
        _faded(origin[i % origin.length], 0),
    ];
    final originBounds = _visibleBounds(origin);
    final qr = _bounds[KeystoneShieldAnchorKind.qr] ?? originBounds;
    final frame = _bounds[KeystoneShieldAnchorKind.frame];
    final scanner = _goal == KeystoneShieldFocusStage.scanner;
    _to = [
      for (var i = 0; i < count; i++)
        if (scanner)
          _clearScannerInterior(_from[i], qr)
        else
          _faded(
            cloud.isNotEmpty ? cloud[(i * 73 + 17) % cloud.length] : _from[i],
            0,
          ),
    ];
    _targetIndices = List.filled(count, -1);
    final used = List.filled(count, false);
    final order = List.generate(target.length, (i) => i)
      ..sort((a, b) => target[a].arrival.compareTo(target[b].arrival));
    for (final j in order) {
      var nearest = -1;
      var distance = double.infinity;
      final frameTarget = scanner && j < _scannerFrameCount && frame != null;
      final aim = frameTarget
          ? _project(target[j].position, frame, qr)
          : _goal == KeystoneShieldFocusStage.qr
          ? _project(target[j].position, qr, originBounds)
          : target[j].position;
      for (var i = 0; i < count; i++) {
        if (used[i]) continue;
        var d = (_from[i].position - aim).distanceSquared;
        if (frameTarget &&
            (!_onRim(_from[i].position, qr) ||
                _corner(_from[i].position, qr) !=
                    _corner(target[j].position, frame))) {
          d += qr.longestSide * qr.longestSide * 16;
        }
        // Lower central cells feed the torch; the rest of the surface clears
        // locally instead of draining into a central particle cloud.
        if (scanner && !frameTarget) {
          final torchAim = Offset(qr.center.dx, qr.bottom);
          d = (_from[i].position - torchAim).distanceSquared;
        }
        if (scanner && _from[i].alpha < 0.01) {
          d += qr.longestSide * qr.longestSide * 32;
        }
        if (d < distance) {
          nearest = i;
          distance = d;
        }
      }
      used[nearest] = true;
      _to[nearest] = target[j];
      _targetIndices[nearest] = j;
    }
  }

  void update(double time, List<ShieldParticleSample> cloud) {
    if (_disposed) return;
    _time = time;
    if (_pending) {
      final target = _target(cloud);
      if (target == null || target.isEmpty) return;
      final origin = _particles.isNotEmpty
          ? _particles
          : cloud.isNotEmpty
          ? cloud
          : [
              for (final p in target)
                ShieldParticleSample(
                  position: p.position,
                  size: p.size,
                  alpha: 0,
                  square: p.square,
                  extent: p.extent,
                ),
            ];
      _pairTargets(origin, target, cloud);
      _fromBlack = blackMix;
      _duration = reduceMotion
          ? 0.18
          : _goal == KeystoneShieldFocusStage.qr
          ? 0.6
          : 0.45;
      _start = time;
      _progress = 0;
      _pending = false;
    }
    final start = _start;
    if (start == null) {
      if (qrReady) {
        _particles = _qr!.whiteCells(
          qrIndex,
          _bounds[KeystoneShieldAnchorKind.qr]!,
          devicePixelRatio,
        );
      } else if (cloudReady) {
        _particles = List.of(cloud);
      }
      _updateFooter();
      return;
    }
    _progress = ((time - start) / _duration).clamp(0.0, 1.0);
    final ease = Curves.easeInOutCubic.transform(_progress);
    blackMix = ui.lerpDouble(
      _fromBlack,
      _goal == KeystoneShieldFocusStage.qr ? 1 : 0,
      ease,
    )!;
    _cameraMix = ui.lerpDouble(
      _fromCamera,
      _goal == KeystoneShieldFocusStage.scanner ? 1 : 0,
      !reduceMotion && _goal == KeystoneShieldFocusStage.scanner
          ? _segment(_progress, 0.28, 0.94)
          : ease,
    )!;
    _glyphMix = _goal == KeystoneShieldFocusStage.scanner
        ? ui.lerpDouble(_fromGlyph, 1, _segment(_progress, 0.72, 1))!
        : _fromGlyph * (1 - (_progress / 0.2).clamp(0.0, 1.0));
    final count = math.max(_from.length, _to.length);
    final next = <ShieldParticleSample>[];
    for (var i = 0; i < count; i++) {
      final source = _from[i % _from.length];
      final destination =
          _goal == KeystoneShieldFocusStage.cloud &&
              cloud.isNotEmpty &&
              _targetIndices[i] >= 0
          ? cloud[_targetIndices[i] % cloud.length]
          : _to[i];
      final fromAlpha = source.alpha;
      final toAlpha = destination.alpha;
      if (reduceMotion) {
        next.add(_faded(source, fromAlpha * (1 - ease)));
        continue;
      }
      final span = _duration * destination.arrival;
      final p = (_progress / destination.arrival).clamp(0.0, 1.0);
      final localEase = Curves.easeInOutCubic.transform(p);
      final formingQr = _goal == KeystoneShieldFocusStage.qr;
      final torchTarget =
          _goal == KeystoneShieldFocusStage.scanner &&
          _targetIndices[i] >= _scannerFrameCount;
      final sizeEase = formingQr
          ? _segment(p, 0.45, 1)
          : torchTarget
          ? Curves.easeOutCubic.transform(p)
          : localEase;
      final alphaEase =
          _goal == KeystoneShieldFocusStage.scanner && toAlpha == 0
          ? Curves.easeOutCubic.transform(p)
          : formingQr && fromAlpha == 0
          ? _segment(p, 0.20, 0.85)
          : localEase;
      final p2 = p * p, p3 = p2 * p;
      final position =
          source.position * (2 * p3 - 3 * p2 + 1) +
          source.velocity * (span * (p3 - 2 * p2 + p)) +
          destination.position * (-2 * p3 + 3 * p2) +
          destination.velocity * (span * (p3 - p2));
      final velocity =
          source.position * ((6 * p2 - 6 * p) / span) +
          source.velocity * (3 * p2 - 4 * p + 1) +
          destination.position * ((-6 * p2 + 6 * p) / span) +
          destination.velocity * (3 * p2 - 2 * p);
      next.add(
        ShieldParticleSample(
          position: position,
          velocity: velocity,
          size: ui.lerpDouble(source.size, destination.size, sizeEase)!,
          alpha: ui.lerpDouble(fromAlpha, toAlpha, alphaEase)!,
          color: Color.lerp(source.color, destination.color, localEase)!,
          square: ui.lerpDouble(source.square, destination.square, sizeEase)!,
          extent: Size.lerp(
            source.extent ?? Size.square(source.size),
            destination.extent ?? Size.square(destination.size),
            sizeEase,
          ),
        ),
      );
    }
    if (reduceMotion) {
      for (var i = 0; i < _to.length; i++) {
        final target =
            _goal == KeystoneShieldFocusStage.cloud &&
                cloud.isNotEmpty &&
                _targetIndices[i] >= 0
            ? cloud[_targetIndices[i] % cloud.length]
            : _to[i];
        next.add(_faded(target, target.alpha * ease));
      }
    }
    _particles = next;
    _updateFooter();
    if (_progress >= 1) {
      if (_goal == KeystoneShieldFocusStage.cloud && cloud.isNotEmpty) {
        _particles = List.of(cloud);
      }
      _settled = _goal;
      _start = null;
      _scannerWasVisible = _goal == KeystoneShieldFocusStage.scanner;
      if (_goal == KeystoneShieldFocusStage.qr) _qrStarted = time;
      _reportReady(qrReady);
    }
  }

  double _segment(double progress, double start, double end) => Curves
      .easeInOutCubic
      .transform(((progress - start) / (end - start)).clamp(0.0, 1.0));

  void paint(Canvas canvas) {
    if (!active) return;
    if (qrReady) {
      _qr!.paint(
        canvas,
        qrIndex,
        _bounds[KeystoneShieldAnchorKind.qr]!,
        devicePixelRatio,
      );
      return;
    }
    final glyphOut = 1 - scannerGlyphOpacity;
    for (final particle in _particles) {
      final alpha =
          particle.alpha *
          ((_goal == KeystoneShieldFocusStage.scanner || _scannerWasVisible)
              ? glyphOut
              : 1);
      if (alpha < 0.004) continue;
      final paint = Paint()
        ..color = particle.color.withValues(alpha: alpha.clamp(0.0, 1.0));
      final rect = Rect.fromCenter(
        center: particle.position,
        width: particle.extent?.width ?? particle.size,
        height: particle.extent?.height ?? particle.size,
      );
      paint.isAntiAlias = particle.square < 0.999;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(particle.size * (1 - particle.square) / 2),
        ),
        paint,
      );
    }
  }

  void dispose() {
    _disposed = true;
  }
}

/// Reports the actual laid-out scanner geometry in the particle canvas's space.
class KeystoneShieldAnchor extends SingleChildRenderObjectWidget {
  const KeystoneShieldAnchor({
    required this.morph,
    required this.kind,
    required super.child,
    super.key,
  });
  final KeystoneShieldMorph morph;
  final KeystoneShieldAnchorKind kind;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _AnchorRender(morph, kind);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderProxyBox renderObject,
  ) {
    (renderObject as _AnchorRender)
      ..morph = morph
      ..kind = kind;
  }
}

class _AnchorRender extends RenderProxyBox {
  _AnchorRender(this.morph, this.kind);
  KeystoneShieldMorph morph;
  KeystoneShieldAnchorKind kind;
  bool _scheduled = false;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached) return;
      final space = morph.spaceKey.currentContext?.findRenderObject();
      if (space is! RenderBox || !space.attached) return;
      morph.setBounds(kind, localToGlobal(Offset.zero, ancestor: space) & size);
    });
  }
}
