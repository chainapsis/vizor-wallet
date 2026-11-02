// Liquid metal: a Flutter port of Paper Shaders' liquid-metal (image mode).
// https://github.com/paper-design/shaders (Apache-2.0)
//
// Needs `shaders: [shaders/liquid_metal.frag]` under `flutter:` in pubspec.yaml.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A chrome-like animated material filling an input shape.
///
/// The shape comes from [image]'s alpha: transparent pixels are outside it.
class LiquidMetal extends StatefulWidget {
  const LiquidMetal({
    super.key,
    required this.image,
    this.colorBack = const Color(0xFFAAAAAC),
    this.colorTint = const Color(0xFFFFFFFF),
    this.repetition = 2,
    this.softness = .1,
    this.shiftRed = .3,
    this.shiftBlue = .3,
    this.distortion = .07,
    this.contour = .4,
    this.angle = 70,
    this.speed = 1,
    this.frame = 0,
    this.scale = .6,
    this.fit = BoxFit.contain,
    this.preprocessed = false,
    this.adaptive = true,
  });

  final ImageProvider image;
  final Color colorBack;

  /// Blended over the metal with color burn.
  final Color colorTint;

  /// Density of the stripes, 1 to 10.
  final double repetition;

  /// Blur between stripes, 0 to 1.
  final double softness;

  /// Chromatic dispersion of the red and blue channels, -1 to 1.
  final double shiftRed;
  final double shiftBlue;

  /// Noise warping the stripes, 0 to 1.
  final double distortion;

  /// Edge hardness up to 0.4; above 0.5 the stripes bend along the edges.
  final double contour;

  /// Direction of the stripes in degrees, 0 to 360.
  final double angle;

  /// Animation speed; 0 stops the ticker.
  final double speed;

  /// Starting point of the animation in milliseconds.
  final double frame;

  /// Zoom of the graphic, 0.1 to 4.
  final double scale;

  /// [BoxFit.contain] or [BoxFit.cover].
  final BoxFit fit;

  /// [image] was baked ahead of time by `tool/bake_test.dart` (R = edge field,
  /// G = alpha), so the runtime preprocessing is skipped.
  final bool preprocessed;

  /// Drops to half the frame rate, then to a still frame, when the device
  /// can't hold 45 fps. Release and profile builds only. With Reduce Motion
  /// on, the widget always shows the still frame at [frame].
  final bool adaptive;

  @override
  State<LiquidMetal> createState() => _LiquidMetalState();
}

class _LiquidMetalState extends State<LiquidMetal>
    with SingleTickerProviderStateMixin {
  static final Future<ui.FragmentProgram> _program =
      ui.FragmentProgram.fromAsset('shaders/liquid_metal.frag');

  // Processed textures by image, so switching back to a shape is instant. Each
  // is a few MB of GPU memory, so only the most recent few are kept.
  static const _cacheSize = 3;
  static final _textures = <ImageProvider, Future<ui.Image>>{};

  // How much motion this device affords, shared by every instance and only
  // ever lowered: 0 = every frame, 1 = every other frame, 2 = still.
  static int _motionTier = 0;

  late final Ticker _ticker = createTicker(_tick);
  late final ValueNotifier<double> _time = ValueNotifier(widget.frame / 1000);
  late final ImageStreamListener _listener = ImageStreamListener(_onImage);
  Duration _lastTick = Duration.zero;
  double _pendingTime = 0;
  int _tickCount = 0;
  Duration _probeStart = Duration.zero;
  int _probeFrames = 0;
  ImageStream? _stream;
  ui.FragmentShader? _shader;
  ui.Image? _texture;
  int _job = 0;

  @override
  void initState() {
    super.initState();
    _program.then((program) {
      if (mounted) setState(() => _shader = program.fragmentShader());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
    _syncTicker();
  }

  @override
  void didUpdateWidget(LiquidMetal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _resolveImage();
    if (widget.frame != oldWidget.frame) _time.value = widget.frame / 1000;
    _syncTicker();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    _texture?.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) _time.value = widget.frame / 1000;
    final animate = widget.speed != 0 && !reduceMotion && _motionTier < 2;
    if (animate && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _probeFrames = 0;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    _pendingTime += delta.inMicroseconds / 1e6 * widget.speed;
    if (_motionTier == 0 || (++_tickCount).isEven) {
      _time.value += _pendingTime;
      _pendingTime = 0;
    }
    if (widget.adaptive && !kDebugMode && _texture != null) {
      _probe(elapsed, delta);
    }
  }

  // Counts frames over 1.5 s windows. Below 45 fps (75% of 60 Hz, so 120 Hz
  // screens that run at 60 still pass) the device drops a motion tier.
  void _probe(Duration elapsed, Duration delta) {
    if (_probeFrames == 0 || delta > const Duration(milliseconds: 250)) {
      _probeStart = elapsed; // first frame, or back from a pause
      _probeFrames = 1;
      return;
    }
    _probeFrames++;
    final seconds = (elapsed - _probeStart).inMicroseconds / 1e6;
    if (seconds < 1.5) return;
    final fps = (_probeFrames - 1) / seconds;
    _probeFrames = 0;
    if (fps >= 45) return;
    _motionTier++;
    if (_motionTier >= 2) _ticker.stop(); // keep the current frame
  }

  void _resolveImage() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  Future<void> _onImage(ImageInfo info, bool _) async {
    final job = ++_job;
    final provider = widget.image;
    final processed =
        _textures.remove(provider) ??
        (widget.preprocessed
            ? Future.value(info.image.clone())
            : processLiquidMetalImage(info.image));
    _textures[provider] = processed; // most recent last
    if (_textures.length > _cacheSize) {
      _textures.remove(_textures.keys.first)!.then((t) => t.dispose());
    }
    final texture = (await processed).clone();
    info.dispose();
    if (!mounted || job != _job) {
      texture.dispose();
      return;
    }
    setState(() {
      _texture?.dispose();
      _texture = texture;
      _probeFrames = 0; // measure from the first frame that runs the shader
    });
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader, texture = _texture;
    final pixelRatio =
        MediaQuery.maybeDevicePixelRatioOf(context) ??
        View.of(context).devicePixelRatio;
    final paint = shader == null || texture == null
        ? null
        : RepaintBoundary(
            child: CustomPaint(
              painter: _LiquidMetalPainter(
                widget,
                shader,
                texture,
                pixelRatio,
                _time,
              ),
            ),
          );
    // Fills the parent; falls back to 16:9 where a side is unbounded (Column, ListView).
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox.fromSize(
        size: constraints.hasBoundedWidth && constraints.hasBoundedHeight
            ? constraints.biggest
            : constraints.constrainSizeAndAttemptToPreserveAspectRatio(
                const Size(1280, 720),
              ),
        child: paint,
      ),
    );
  }
}

class _LiquidMetalPainter extends CustomPainter {
  _LiquidMetalPainter(
    this.widget,
    this.shader,
    this.texture,
    this.pixelRatio,
    this.time,
  ) : super(repaint: time);

  final LiquidMetal widget;
  final ui.FragmentShader shader;
  final ui.Image texture;
  final double pixelRatio;
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = widget.fit == BoxFit.cover ? math.max : math.min;
    final aspect = texture.width / texture.height;
    final boxWidth =
        fit(size.width / aspect, size.height) * aspect * widget.scale;
    final boxHeight = boxWidth / aspect;
    // Paper processes SVGs at 4096 px and blurs the edge by texels, so the
    // blur radius is normalized to that size whatever the texture size.
    final longSide = math.max(texture.width, texture.height) / 4096;

    var i = 0;
    void float(double value) => shader.setFloat(i++, value);
    void color(Color c) => [c.r, c.g, c.b, c.a].forEach(float);

    float(size.width);
    float(size.height);
    float(boxWidth);
    float(boxHeight);
    float(longSide / texture.width);
    float(longSide / texture.height);
    float(1 / pixelRatio / boxWidth);
    float(1 / pixelRatio / boxHeight);
    float(
      size.shortestSide * math.max(pixelRatio, 2),
    ); // Paper renders at 2x at least
    float(time.value);
    color(widget.colorBack);
    color(widget.colorTint);
    float(widget.softness);
    float(widget.repetition);
    float(widget.shiftRed);
    float(widget.shiftBlue);
    float(widget.distortion);
    float(widget.contour);
    float(widget.angle);
    shader.setImageSampler(0, texture, filterQuality: FilterQuality.medium);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_LiquidMetalPainter old) =>
      old.widget != widget ||
      old.shader != shader ||
      old.texture != texture ||
      old.pixelRatio != pixelRatio;
}

const _workingSize = 512;
const _iterations = 40;

/// Paper's toProcessedLiquidMetal: solves a Poisson equation inside the
/// shape's alpha mask at a fixed working size, then bakes R = edge field,
/// G = alpha. Runs inside [LiquidMetal], or ahead of time in `tool/bake_test.dart`.
Future<ui.Image> processLiquidMetalImage(ui.Image source) async {
  final width = source.width, height = source.height;
  final workingScale = _workingSize / math.min(width, height);
  final workingWidth = (width * workingScale).round();
  final workingHeight = (height * workingScale).round();

  final small = await _readPixels(
    source,
    workingWidth,
    workingHeight,
    FilterQuality.low,
  );
  final field = await compute(_solveEdgeField, (
    small,
    workingWidth,
    workingHeight,
  ));
  final fieldImage = await _decodePixels(field, workingWidth, workingHeight);
  final edge = await _readPixels(fieldImage, width, height, FilterQuality.high);
  fieldImage.dispose();
  final alpha = (await source.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;

  final pixels = await compute(_bakeChannels, (
    edge,
    alpha.buffer.asUint8List(),
  ));
  return _decodePixels(pixels, width, height);
}

/// Draws [image] at [width] x [height] and reads it back unpremultiplied.
Future<Uint8List> _readPixels(
  ui.Image image,
  int width,
  int height,
  FilterQuality quality,
) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = quality,
  );
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(width, height);
  picture.dispose();
  final bytes = await scaled.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  scaled.dispose();
  return bytes!.buffer.asUint8List();
}

Future<ui.Image> _decodePixels(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// 40 red-black SOR iterations of ∇²u = -C with u = 0 on the shape boundary.
/// Returns gray = 255 * (1 - u / max) inside the shape, transparent outside.
Uint8List _solveEdgeField((Uint8List, int, int) args) {
  final (rgba, width, height) = args;
  final count = width * height;
  final inShape = Uint8List(count);
  for (var i = 0; i < count; i++) {
    inShape[i] = rgba[i * 4 + 3] == 0 ? 0 : 1;
  }

  // Interior = shape pixels whose 8 neighbors are all shape; the rest of the
  // shape is boundary and stays 0. Interior pixels never touch the image edge.
  final red = <int>[], black = <int>[];
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      if (inShape[i] == 0) continue;
      if (inShape[i - 1] == 0 ||
          inShape[i + 1] == 0 ||
          inShape[i - width] == 0 ||
          inShape[i + width] == 0 ||
          inShape[i - width - 1] == 0 ||
          inShape[i - width + 1] == 0 ||
          inShape[i + width - 1] == 0 ||
          inShape[i + width + 1] == 0) {
        continue;
      }
      ((x + y).isEven ? red : black).add(i);
    }
  }

  const c = 0.01, omega = 1.9;
  final u = Float32List(count);
  final passes = [Int32List.fromList(red), Int32List.fromList(black)];
  for (var iteration = 0; iteration < _iterations; iteration++) {
    for (final pass in passes) {
      for (final i in pass) {
        final sum = u[i + 1] + u[i - 1] + u[i - width] + u[i + width];
        u[i] = omega * ((c + sum) / 4) + (1 - omega) * u[i];
      }
    }
  }

  var max = 0.0;
  for (final pass in passes) {
    for (final i in pass) {
      if (u[i] > max) max = u[i];
    }
  }

  final scale = max > 0 ? 1 / max : 0.0;
  final out = Uint8List(count * 4);
  for (var i = 0, p = 0; i < count; i++, p += 4) {
    if (inShape[i] == 0) continue;
    final gray = _roundHalfEven(255 * (1 - u[i] * scale));
    out[p] = out[p + 1] = out[p + 2] = gray;
    out[p + 3] = 255;
  }
  return out;
}

/// R = upscaled edge field (255 outside the shape), G = original alpha.
Uint8List _bakeChannels((Uint8List, Uint8List) args) {
  final (edge, alpha) = args;
  final out = Uint8List(alpha.length);
  for (var p = 0; p < alpha.length; p += 4) {
    final a = alpha[p + 3];
    out[p] = a == 0 ? 255 : (edge[p + 3] == 0 ? 0 : edge[p]);
    out[p + 1] = a;
    out[p + 2] = 255;
    out[p + 3] = 255;
  }
  return out;
}

/// Uint8ClampedArray rounding: nearest, ties to even.
int _roundHalfEven(double value) {
  final floor = value.floor();
  final fraction = value - floor;
  final rounded = fraction > .5 || (fraction == .5 && floor.isOdd)
      ? floor + 1
      : floor;
  return rounded.clamp(0, 255);
}
