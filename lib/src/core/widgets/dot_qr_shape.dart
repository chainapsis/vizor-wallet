import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// The Vizor QR look: circular "dot" data modules
/// ([PrettyQrSmoothSymbol] at `roundFactor: 1`) with ring + center-dot finder
/// patterns instead of the default squares. Shared by the receive and
/// swap-deposit QR surfaces so they stay visually identical.
class DotQrShape extends PrettyQrShape {
  const DotQrShape({this.color = const Color(0xFF000000), this.finderReferenceDimension});

  final Color color;

  /// When set, the finder dots clamp to
  /// `min(module, bounds / finderReferenceDimension)` so very dense codes
  /// (e.g. long transparent receive addresses) keep proportional finder
  /// patterns. Null uses the natural module size.
  final double? finderReferenceDimension;

  @override
  void paint(PrettyQrPaintingContext context) {
    PrettyQrSmoothSymbol(roundFactor: 1, color: color).paint(
      context.copyWith(
        matrix: _withoutComponent(
          context.matrix,
          PrettyQrComponentType.finderPattern,
        ),
      ),
    );
    _paintFinderPatterns(context);
  }

  void _paintFinderPatterns(PrettyQrPaintingContext context) {
    final module = context.moduleDimension;
    final reference = finderReferenceDimension;
    final visualModule = reference == null
        ? module
        : math.min(module, context.boundsDimension / reference);
    final ringPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      // Design-system finder (node 4755:89080): a 7-module outer ring that is
      // exactly 1 module thick (5-module inner hole). Stroke is centred on the
      // 3-module radius, so a full-module width lands the outer edge at 3.5
      // modules (7 across) and the inner edge at 2.5 (5 across).
      ..strokeWidth = visualModule;
    final dotPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;

    for (final pattern in context.matrix.positionDetectionPatterns) {
      final center = context.estimatedBounds.topLeft.translate(
        (pattern.left + PrettyQrPositionDetectionPattern.dimension / 2) * module,
        (pattern.top + PrettyQrPositionDetectionPattern.dimension / 2) * module,
      );
      context.canvas.drawCircle(center, visualModule * 3, ringPaint);
      context.canvas.drawCircle(center, visualModule * 1.5, dotPaint);
    }
  }

  PrettyQrMatrix _withoutComponent(
    PrettyQrMatrix matrix,
    PrettyQrComponentType component,
  ) {
    return PrettyQrMatrix(
      version: matrix.version,
      modules: [
        for (final module in matrix)
          module.type == component ? module.toBlank() : module,
      ],
    );
  }

  @override
  int get hashCode => Object.hash(DotQrShape, color, finderReferenceDimension);

  @override
  bool operator ==(Object other) {
    return other is DotQrShape &&
        other.color == color &&
        other.finderReferenceDimension == finderReferenceDimension;
  }
}
