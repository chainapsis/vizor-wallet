import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart'
    show InputTooLongException, QrCode, QrImage;

/// The quiet zone the QR specification asks for around a symbol, in modules.
const keystoneQrQuietZoneModules = 4;

/// The characters QR alphanumeric mode can carry. An upper-cased UR uses
/// nothing else.
final _qrAlphanumeric = RegExp(r'^[0-9A-Z $%*+\-./:]+$');

/// Encodes [data] as the smallest QR symbol that holds it at
/// [errorCorrectLevel].
///
/// Text made only of QR alphanumeric characters is encoded in alphanumeric
/// mode, 5.5 bits a character instead of 8, so the symbol has fewer and
/// larger modules. Anything else is encoded as bytes.
QrImage keystoneQrImage(String data, {required int errorCorrectLevel}) {
  if (!_qrAlphanumeric.hasMatch(data)) {
    return QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: errorCorrectLevel),
    );
  }
  for (var typeNumber = 1; typeNumber <= 40; typeNumber++) {
    try {
      return QrImage(
        QrCode(typeNumber, errorCorrectLevel)..addAlphaNumeric(data),
      );
    } on InputTooLongException {
      // The next symbol version holds more.
    }
  }
  throw ArgumentError.value(data.length, 'data', 'too long for a QR symbol');
}

/// Where a QR symbol lands once every module is a whole number of device
/// pixels.
@immutable
class KeystoneQrPixelGrid {
  const KeystoneQrPixelGrid({required this.modulePixels, required this.inset});

  /// Side of one module in device pixels.
  final int modulePixels;

  /// Device pixels from the box's edge to the symbol's first module. It
  /// covers the quiet zone plus what the box has left over.
  final int inset;

  /// Fits [moduleCount] modules and a quiet zone of [quietZoneModules] on each
  /// side into a box [boxPixels] device pixels wide.
  ///
  /// Returns `null` when the box cannot give each module a whole device pixel.
  static KeystoneQrPixelGrid? fit({
    required double boxPixels,
    required int moduleCount,
    required int quietZoneModules,
  }) {
    final totalModules = moduleCount + 2 * quietZoneModules;
    if (moduleCount <= 0 || quietZoneModules < 0 || !boxPixels.isFinite) {
      return null;
    }
    // A box a hair under a whole pixel count is that count; floating-point
    // scale factors produce such values.
    final wholeBoxPixels = (boxPixels + 1e-6).floor();
    final modulePixels = wholeBoxPixels ~/ totalModules;
    if (modulePixels < 1) return null;
    final symbolPixels = modulePixels * moduleCount;
    return KeystoneQrPixelGrid(
      modulePixels: modulePixels,
      inset: (wholeBoxPixels - symbolPixels) ~/ 2,
    );
  }
}

/// Paints a QR symbol for a camera to read: square modules, each a whole
/// number of device pixels and starting on a device pixel.
///
/// A symbol stretched to an arbitrary size puts module edges between pixels,
/// which the display renders as grey fringes. On a standard-density monitor
/// those fringes are a large part of each module of a dense symbol. This
/// widget shrinks the symbol to the largest size whose edges all fall on
/// device pixels and centres it; the rest of the box is quiet zone.
///
/// The widget paints only the dark modules. Its parent supplies the light
/// surface.
class KeystoneSnappedQr extends LeafRenderObjectWidget {
  const KeystoneSnappedQr({
    required this.qrImage,
    required this.color,
    this.quietZoneModules = keystoneQrQuietZoneModules,
    super.key,
  });

  final QrImage qrImage;
  final Color color;
  final int quietZoneModules;

  @override
  RenderKeystoneSnappedQr createRenderObject(BuildContext context) {
    return RenderKeystoneSnappedQr(
      qrImage: qrImage,
      color: color,
      quietZoneModules: quietZoneModules,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderKeystoneSnappedQr renderObject,
  ) {
    renderObject
      ..qrImage = qrImage
      ..color = color
      ..quietZoneModules = quietZoneModules
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderKeystoneSnappedQr extends RenderBox {
  RenderKeystoneSnappedQr({
    required QrImage qrImage,
    required Color color,
    required int quietZoneModules,
    required double devicePixelRatio,
  }) : _qrImage = qrImage,
       _color = color,
       _quietZoneModules = quietZoneModules,
       _devicePixelRatio = devicePixelRatio;

  QrImage _qrImage;
  set qrImage(QrImage value) {
    if (identical(_qrImage, value)) return;
    _qrImage = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  int _quietZoneModules;
  set quietZoneModules(int value) {
    if (_quietZoneModules == value) return;
    _quietZoneModules = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// The grid used by the last paint, or `null` if that paint could not snap.
  @visibleForTesting
  KeystoneQrPixelGrid? debugLastPixelGrid;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final side = constraints.biggest.shortestSide;
    return constraints.constrain(Size.square(side.isFinite ? side : 0));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final side = size.shortestSide;
    final moduleCount = _qrImage.moduleCount;
    if (side <= 0 || moduleCount <= 0) return;

    final placement = _devicePlacement();
    final grid = placement == null
        ? null
        : KeystoneQrPixelGrid.fit(
            boxPixels: side * placement.scale,
            moduleCount: moduleCount,
            quietZoneModules: _quietZoneModules,
          );
    debugLastPixelGrid = grid;

    if (placement == null || grid == null) {
      _paintUnsnapped(context.canvas, offset, side, moduleCount);
      return;
    }

    // Work in device pixels, then map each edge back to this box's
    // coordinates. Every edge is a whole device pixel, so antialiasing has
    // nothing to blend.
    final scale = placement.scale;
    final originX = placement.origin.dx.round() + grid.inset;
    final originY = placement.origin.dy.round() + grid.inset;
    double localX(int devicePixel) =>
        offset.dx + (devicePixel - placement.origin.dx) / scale;
    double localY(int devicePixel) =>
        offset.dy + (devicePixel - placement.origin.dy) / scale;

    final paint = Paint()
      ..color = _color
      ..isAntiAlias = false;
    _forEachDarkRun(moduleCount, (row, startColumn, endColumn) {
      context.canvas.drawRect(
        Rect.fromLTRB(
          localX(originX + startColumn * grid.modulePixels),
          localY(originY + row * grid.modulePixels),
          localX(originX + endColumn * grid.modulePixels),
          localY(originY + (row + 1) * grid.modulePixels),
        ),
        paint,
      );
    });
  }

  /// This box's top-left corner in device pixels and the device pixels per
  /// logical pixel, or `null` under a rotation, skew, or non-uniform scale.
  ({Offset origin, double scale})? _devicePlacement() {
    if (!attached) return null;
    final transform = getTransformTo(null);
    final scaleX = transform.entry(0, 0);
    final scaleY = transform.entry(1, 1);
    const tolerance = 1e-6;
    if (transform.entry(0, 1).abs() > tolerance ||
        transform.entry(1, 0).abs() > tolerance ||
        scaleX <= 0 ||
        (scaleX - scaleY).abs() > tolerance) {
      return null;
    }
    final scale = scaleX * _devicePixelRatio;
    if (!scale.isFinite || scale <= 0) return null;
    return (
      origin: Offset(
        transform.entry(0, 3) * _devicePixelRatio,
        transform.entry(1, 3) * _devicePixelRatio,
      ),
      scale: scale,
    );
  }

  void _paintUnsnapped(
    Canvas canvas,
    Offset offset,
    double side,
    int moduleCount,
  ) {
    final module = side / (moduleCount + 2 * _quietZoneModules);
    final inset = module * _quietZoneModules;
    final paint = Paint()..color = _color;
    _forEachDarkRun(moduleCount, (row, startColumn, endColumn) {
      canvas.drawRect(
        Rect.fromLTRB(
          offset.dx + inset + startColumn * module,
          offset.dy + inset + row * module,
          offset.dx + inset + endColumn * module,
          offset.dy + inset + (row + 1) * module,
        ),
        paint,
      );
    });
  }

  /// Calls [paintRun] for each horizontal run of dark modules, so adjoining
  /// modules are one rectangle with no seam between them.
  void _forEachDarkRun(
    int moduleCount,
    void Function(int row, int startColumn, int endColumn) paintRun,
  ) {
    for (var row = 0; row < moduleCount; row++) {
      var column = 0;
      while (column < moduleCount) {
        if (!_qrImage.isDark(row, column)) {
          column++;
          continue;
        }
        final start = column;
        while (column < moduleCount && _qrImage.isDark(row, column)) {
          column++;
        }
        paintRun(row, start, column);
      }
    }
  }
}
