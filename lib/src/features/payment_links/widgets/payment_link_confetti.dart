import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Decorative, one-shot celebration used by the payment-link ready states.
///
/// Piece geometry comes directly from the Figma Confetti component. Motion is
/// applied to three cached layers, keeping the individual painter geometry
/// deterministic for captures and tests.
class PaymentLinkConfetti extends StatefulWidget {
  const PaymentLinkConfetti({super.key});

  static const int pieceCount = 165;
  static const Duration entranceDuration = Duration(milliseconds: 620);

  @override
  State<PaymentLinkConfetti> createState() => _PaymentLinkConfettiState();
}

class _PaymentLinkConfettiState extends State<PaymentLinkConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PaymentLinkConfetti.entranceDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
      return;
    }

    if (!TickerMode.valuesOf(context).enabled) {
      _controller.stop();
      return;
    }

    if (_controller.value < 1 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _layerProgress(int layer, double value) {
    final start = layer * 0.08;
    final end = 0.84 + (layer * 0.08);
    final normalized = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            // Figma's 420px content area gives the Confetti coordinate space
            // 12px horizontal padding on each side.
            width: 396,
            height: 620,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    for (var layer = 0; layer < 3; layer += 1)
                      _buildLayer(
                        layer,
                        _layerProgress(layer, _controller.value),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayer(int layer, double progress) {
    const horizontalOffsets = [-5.0, 4.0, -3.0];
    const rotations = [-0.025, 0.018, -0.012];
    return Opacity(
      key: ValueKey('payment_link_confetti_layer_$layer'),
      opacity: progress,
      child: Transform.translate(
        key: ValueKey('payment_link_confetti_transform_$layer'),
        offset: Offset(
          horizontalOffsets[layer] * (1 - progress),
          (10 + (layer * 3)) * (1 - progress),
        ),
        child: Transform.rotate(
          angle: rotations[layer] * (1 - progress),
          child: Transform.scale(
            scale: 0.96 + (0.04 * progress),
            child: RepaintBoundary(
              child: CustomPaint(painter: _ConfettiPainter(layer)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.layer);

  final int layer;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = layer; index < _pieces.length; index += 3) {
      final piece = _pieces[index];
      if (piece.opacity == 0) continue;
      final center = Offset(
        piece.left + (piece.outerWidth / 2),
        piece.top + (piece.outerHeight / 2),
      );
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(piece.rotationDegrees * math.pi / 180)
        ..drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: piece.innerWidth,
            height: piece.innerHeight,
          ),
          Paint()
            ..color = const Color(0xFFA83861).withValues(alpha: piece.opacity),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.layer != layer;
}

class _ConfettiPiece {
  const _ConfettiPiece(
    this.left,
    this.top,
    this.outerWidth,
    this.outerHeight,
    this.innerWidth,
    this.innerHeight,
    this.rotationDegrees,
    this.opacity,
  );

  final double left;
  final double top;
  final double outerWidth;
  final double outerHeight;
  final double innerWidth;
  final double innerHeight;
  final double rotationDegrees;
  final double opacity;
}

const _pieces = <_ConfettiPiece>[
  _ConfettiPiece(-14.7, 177.17, 12.986, 14.402, 10.446, 12.345, -13.18, 0.25),
  _ConfettiPiece(303.05, 75.29, 13.74, 12.139, 10.446, 12.345, 81.59, 0.25),
  _ConfettiPiece(392.68, 331.96, 12.986, 14.402, 10.446, 12.345, 166.82, 0),
  _ConfettiPiece(114.92, 468.39, 13.74, 12.139, 10.446, 12.345, -98.41, 0),
  _ConfettiPiece(47.97, 189.52, 11.773, 9.226, 10.446, 7.029, -13.18, 0.25),
  _ConfettiPiece(290.79, 136.72, 8.482, 11.362, 10.446, 7.029, 81.59, 0.25),
  _ConfettiPiece(336.74, 359.67, 11.773, 9.226, 10.446, 7.029, 166.82, 0.5),
  _ConfettiPiece(97.21, 410.34, 8.482, 11.362, 10.446, 7.029, -98.41, 0.5),
  _ConfettiPiece(42.8, 176.28, 12.635, 12.906, 10.446, 10.809, -13.18, 0.25),
  _ConfettiPiece(300.68, 132.66, 12.221, 11.914, 10.446, 10.809, 81.59, 0.25),
  _ConfettiPiece(321.46, 372.79, 12.635, 12.906, 10.446, 10.809, 166.82, 1),
  _ConfettiPiece(81.67, 394.02, 12.221, 11.914, 10.446, 10.809, -98.41, 1),
  _ConfettiPiece(89.76, 152.48, 15.029, 15.011, 10.446, 10.809, -46.98, 1),
  _ConfettiPiece(317.94, 181, 15.024, 14.999, 10.446, 10.809, 47.79, 1),
  _ConfettiPiece(50.27, 328.28, 15.024, 14.999, 10.446, 10.809, -132.21, 0.5),
  _ConfettiPiece(376.55, 476.18, 11.214, 11.451, 10.446, 5.59, 133.02, 1),
  _ConfettiPiece(-24.62, 439.88, 11.159, 11.493, 10.446, 5.59, -132.21, 1),
  _ConfettiPiece(94.25, 107.58, 11.745, 7.961, 6.064, 10.809, -79.32, 1),
  _ConfettiPiece(369.11, 189.35, 8.723, 12.033, 6.064, 10.809, 15.45, 1),
  _ConfettiPiece(290.5, 442.88, 11.745, 7.961, 6.064, 10.809, 100.68, 1),
  _ConfettiPiece(18.65, 357.03, 8.723, 12.033, 6.064, 10.809, -164.55, 1),
  _ConfettiPiece(126.05, 168.36, 11.33, 12.287, 6.064, 10.809, -143.21, 0.25),
  _ConfettiPiece(302.06, 215.76, 12.11, 11.708, 6.064, 10.809, -48.43, 0.25),
  _ConfettiPiece(259.11, 377.77, 11.33, 12.287, 6.064, 10.809, 36.79, 0.5),
  _ConfettiPiece(82.32, 330.95, 12.11, 11.708, 6.064, 10.809, 131.57, 0.5),
  _ConfettiPiece(110.13, 179.2, 12.368, 10.139, 6.064, 10.809, -115.6, 0.5),
  _ConfettiPiece(294.92, 199.33, 9.511, 12.259, 6.064, 10.809, -20.83, 0.5),
  _ConfettiPiece(273.99, 369.08, 12.368, 10.139, 6.064, 10.809, 64.4, 0.5),
  _ConfettiPiece(92.06, 346.83, 9.511, 12.259, 6.064, 10.809, 159.17, 0.5),
  _ConfettiPiece(142.94, 160.08, 7.603, 8.321, 4.098, 7.306, -144.11, 0.75),
  _ConfettiPiece(312.99, 233.51, 8.212, 7.869, 4.098, 7.306, -49.34, 0.75),
  _ConfettiPiece(245.95, 390.02, 7.603, 8.321, 4.098, 7.306, 35.89, 0.5),
  _ConfettiPiece(75.29, 317.04, 8.212, 7.869, 4.098, 7.306, 130.66, 0.5),
  _ConfettiPiece(133.44, 85.06, 11.555, 7.526, 6.064, 10.809, -98.1, 0.25),
  _ConfettiPiece(389.54, 230.65, 6.681, 11.143, 6.064, 10.809, -3.33, 0.25),
  _ConfettiPiece(0.27, 316.63, 6.681, 11.143, 6.064, 10.809, 176.67, 0.25),
  _ConfettiPiece(170.47, 76.52, 10.618, 12.393, 6.064, 10.809, -150.34, 1),
  _ConfettiPiece(389.76, 267.61, 12.344, 11.113, 6.064, 10.809, -55.57, 1),
  _ConfettiPiece(-5.61, 279.7, 12.344, 11.113, 6.064, 10.809, 124.43, 1),
  _ConfettiPiece(-60.28, 261.69, 12.986, 14.402, 10.446, 12.345, -13.18, 0.25),
  _ConfettiPiece(222.62, 22.84, 13.74, 12.139, 10.446, 12.345, 81.59, 0.25),
  _ConfettiPiece(61.5, 300.8, 12.525, 14.046, 10.446, 12.345, 10.53, 0),
  _ConfettiPiece(173.25, 140.13, 14.663, 13.333, 10.446, 12.345, 105.3, 0),
  _ConfettiPiece(322.47, 243.57, 12.525, 14.046, 10.446, 12.345, -169.47, 0.25),
  _ConfettiPiece(76.58, 228.36, 16.092, 16.135, 10.446, 12.345, 44.09, 0),
  _ConfettiPiece(242.34, 161.46, 15.989, 16.169, 10.446, 12.345, 138.86, 0),
  _ConfettiPiece(303.82, 313.93, 16.092, 16.135, 10.446, 12.345, -135.91, 0.25),
  _ConfettiPiece(138.17, 380.79, 15.989, 16.169, 10.446, 12.345, -41.14, 0.25),
  _ConfettiPiece(60.32, 239.85, 16.092, 16.135, 10.446, 12.345, 44.09, 1),
  _ConfettiPiece(232.24, 144.3, 15.989, 16.169, 10.446, 12.345, 138.86, 1),
  _ConfettiPiece(320.08, 302.44, 16.092, 16.135, 10.446, 12.345, -135.91, 0.5),
  _ConfettiPiece(233.15, 278.78, 13.76, 12.164, 10.446, 12.345, -81.46, 1),
  _ConfettiPiece(182.63, 313.17, 13.008, 14.419, 10.446, 12.345, 13.32, 1),
  _ConfettiPiece(132.38, 496.16, 13.987, 12.334, 6.675, 12.345, 56.89, 0),
  _ConfettiPiece(-25.07, 194.97, 11.735, 14.034, 6.675, 12.345, 151.66, 0),
  _ConfettiPiece(250.13, 49.93, 13.987, 12.334, 6.675, 12.345, -123.11, 0.5),
  _ConfettiPiece(409.82, 349.42, 11.735, 14.034, 6.675, 12.345, -28.34, 0.5),
  _ConfettiPiece(-14.12, 142.63, 11.735, 14.034, 6.675, 12.345, 151.66, 0.75),
  _ConfettiPiece(303.19, 56.49, 13.987, 12.334, 6.675, 12.345, -123.11, 0.75),
  _ConfettiPiece(398.87, 401.75, 11.735, 14.034, 6.675, 12.345, -28.34, 0.75),
  _ConfettiPiece(147.68, 319.62, 10.165, 9.061, 7.568, 8.944, 79.58, 0.5),
  _ConfettiPiece(153.04, 225.33, 8.412, 9.646, 7.568, 8.944, 174.35, 0.5),
  _ConfettiPiece(238.64, 229.74, 10.165, 9.061, 7.568, 8.944, -100.42, 0.25),
  _ConfettiPiece(235.04, 323.45, 8.412, 9.646, 7.568, 8.944, -5.65, 0.25),
  _ConfettiPiece(138.04, 339.37, 10.457, 9.439, 7.568, 8.944, 103.43, 0),
  _ConfettiPiece(133.17, 213.6, 9.983, 10.861, 7.568, 8.944, -161.8, 0),
  _ConfettiPiece(247.99, 209.61, 10.457, 9.439, 7.568, 8.944, -76.57, 0.25),
  _ConfettiPiece(253.34, 333.96, 9.983, 10.861, 7.568, 8.944, 18.2, 0.25),
  _ConfettiPiece(60.37, 271.57, 15.986, 15.362, 10.446, 12.345, 121.56, 1),
  _ConfettiPiece(201.14, 141.71, 15.729, 16.134, 10.446, 12.345, -143.67, 1),
  _ConfettiPiece(320.13, 271.49, 15.986, 15.362, 10.446, 12.345, -58.44, 0),
  _ConfettiPiece(179.62, 400.58, 15.729, 16.134, 10.446, 12.345, 36.33, 0),
  _ConfettiPiece(36.72, 261.24, 10.004, 8.659, 7.994, 9.448, 85.83, 0.25),
  _ConfettiPiece(220.81, 119.6, 8.094, 9.532, 7.994, 9.448, -179.39, 0.25),
  _ConfettiPiece(349.77, 288.52, 10.004, 8.659, 7.994, 9.448, -94.17, 0.25),
  _ConfettiPiece(13.75, 340.7, 15.779, 15.878, 10.267, 12.134, 42.85, 0),
  _ConfettiPiece(135.87, 89.5, 15.763, 15.883, 10.267, 12.134, 137.62, 0),
  _ConfettiPiece(366.96, 201.85, 15.779, 15.878, 10.267, 12.134, -137.15, 0.75),
  _ConfettiPiece(46.08, 348.1, 14.889, 13.762, 10.267, 12.134, 70.26, 0.75),
  _ConfettiPiece(128.24, 121.5, 13.053, 14.374, 10.267, 12.134, 165.03, 0.75),
  _ConfettiPiece(335.53, 196.55, 14.889, 13.762, 10.267, 12.134, -109.74, 0.5),
  _ConfettiPiece(-9.95, 329.11, 13.861, 14.496, 9.517, 11.247, 29.95, 0.5),
  _ConfettiPiece(150.7, 66.77, 14.665, 14.228, 9.517, 11.247, 124.72, 0.5),
  _ConfettiPiece(392.58, 214.81, 13.861, 14.496, 9.517, 11.247, -150.05, 0.25),
  _ConfettiPiece(29.93, 393.68, 13.909, 12.913, 9.517, 11.247, 69.01, 0.5),
  _ConfettiPiece(85.01, 101.62, 12.279, 13.457, 9.517, 11.247, 163.78, 0.5),
  _ConfettiPiece(352.65, 151.82, 13.909, 12.913, 9.517, 11.247, -110.99, 0.25),
  _ConfettiPiece(299.2, 443.34, 12.279, 13.457, 9.517, 11.247, -16.22, 0.25),
  _ConfettiPiece(88.81, 387.04, 13.909, 12.913, 9.517, 11.247, 69.01, 1),
  _ConfettiPiece(86.74, 160.85, 12.279, 13.457, 9.517, 11.247, 163.78, 1),
  _ConfettiPiece(293.77, 158.47, 13.909, 12.913, 9.517, 11.247, -110.99, 1),
  _ConfettiPiece(297.47, 384.11, 12.279, 13.457, 9.517, 11.247, -16.22, 1),
  _ConfettiPiece(279.68, 132.54, 13.909, 12.913, 9.517, 11.247, -110.99, 0),
  _ConfettiPiece(324.48, 372.22, 12.279, 13.457, 9.517, 11.247, -16.22, 0),
  _ConfettiPiece(22.42, 193.92, 8.906, 12.159, 7.436, 11.247, -172.13, 0.5),
  _ConfettiPiece(257.12, 97.82, 11.633, 8.034, 7.436, 11.247, -86.9, 0.75),
  _ConfettiPiece(365.17, 352.34, 8.906, 12.159, 7.436, 11.247, 7.87, 0.75),
  _ConfettiPiece(0.49, 432.62, 11.633, 8.034, 7.436, 11.247, 93.1, 0.75),
  _ConfettiPiece(52.87, 68.77, 8.906, 12.159, 7.436, 11.247, -172.13, 0.75),
  _ConfettiPiece(384.36, 117.77, 11.633, 8.034, 7.436, 11.247, -86.9, 0.5),
  _ConfettiPiece(334.71, 477.49, 8.906, 12.159, 7.436, 11.247, 7.87, 0.5),
  _ConfettiPiece(405.98, 122.1, 11.633, 8.034, 7.436, 11.247, -86.9, 0.25),
  _ConfettiPiece(328.6, 498.67, 8.906, 12.159, 7.436, 11.247, 7.87, 0.25),
  _ConfettiPiece(357.64, 184.93, 13.341, 11.512, 7.436, 11.247, -115.16, 1),
  _ConfettiPiece(316.71, 195.22, 13.341, 11.512, 7.436, 11.247, -115.16, 0.5),
  _ConfettiPiece(236, 246.5, 13.341, 11.512, 7.436, 11.247, -115.16, 1),
  _ConfettiPiece(215.97, 319.15, 10.889, 13.133, 7.436, 11.247, -20.39, 1),
  _ConfettiPiece(235.05, 312.02, 13.231, 13.191, 7.436, 11.247, -134.57, 1),
  _ConfettiPiece(148.91, 312.5, 12.913, 13.401, 7.436, 11.247, -39.8, 1),
  _ConfettiPiece(280.95, 303.78, 10.683, 10.681, 7.436, 7.671, -134.57, 0.75),
  _ConfettiPiece(155.81, 359.14, 10.623, 10.653, 7.436, 7.671, -39.8, 0.75),
  _ConfettiPiece(390.78, 283.53, 10.683, 10.681, 7.436, 7.671, -134.57, 1),
  _ConfettiPiece(327.16, 164.83, 11.633, 8.034, 7.436, 11.247, -86.9, 0),
  _ConfettiPiece(292.57, 416.57, 8.906, 12.159, 7.436, 11.247, 7.87, 0),
  _ConfettiPiece(61.27, 467.75, 7.323, 9.931, 6.044, 9.141, 171.54, 0),
  _ConfettiPiece(11.74, 126.95, 9.511, 6.619, 6.044, 9.141, -93.69, 0),
  _ConfettiPiece(327.9, 80.73, 7.323, 9.931, 6.044, 9.141, -8.46, 0.25),
  _ConfettiPiece(375.24, 424.85, 9.511, 6.619, 6.044, 9.141, 86.31, 0.25),
  _ConfettiPiece(31.83, 308.22, 12.45, 13.671, 6.203, 12.447, -142.95, 0.75),
  _ConfettiPiece(169.14, 110.13, 13.412, 12.922, 6.203, 12.447, -48.18, 0.75),
  _ConfettiPiece(352.21, 236.53, 12.45, 13.671, 6.203, 12.447, 37.05, 1),
  _ConfettiPiece(131.54, 227.5, 16.092, 16.135, 10.446, 12.345, 44.09, 1),
  _ConfettiPiece(238.62, 216.3, 15.989, 16.169, 10.446, 12.345, 138.86, 1),
  _ConfettiPiece(252.14, 303.47, 16.092, 16.135, 10.446, 12.345, -135.91, 1),
  _ConfettiPiece(152.88, 330.16, 15.989, 16.169, 10.446, 12.345, -41.14, 1),
  _ConfettiPiece(151.48, 180.97, 13.107, 11.359, 10.446, 12.345, 94.38, 0.75),
  _ConfettiPiece(287.69, 239.91, 12.277, 13.849, 10.446, 12.345, -170.85, 0.75),
  _ConfettiPiece(231.9, 366.09, 13.107, 11.359, 10.446, 12.345, -85.62, 0),
  _ConfettiPiece(96.53, 304.66, 12.277, 13.849, 10.446, 12.345, 9.15, 0),
  _ConfettiPiece(113.5, 199.02, 13.107, 11.359, 10.446, 12.345, 94.38, 0),
  _ConfettiPiece(272.87, 200.56, 12.277, 13.849, 10.446, 12.345, -170.85, 0),
  _ConfettiPiece(269.89, 348.04, 13.107, 11.359, 10.446, 12.345, -85.62, 0),
  _ConfettiPiece(111.35, 344.01, 12.277, 13.849, 10.446, 12.345, 9.15, 0),
  _ConfettiPiece(-112.51, 299.67, 8.059, 8.447, 5.558, 6.568, 29.26, 0.5),
  _ConfettiPiece(194.88, -32.65, 8.554, 8.282, 5.558, 6.568, 124.03, 0.5),
  _ConfettiPiece(500.94, 250.3, 8.059, 8.447, 5.558, 6.568, -150.74, 1),
  _ConfettiPiece(193.06, 582.78, 8.554, 8.282, 5.558, 6.568, -55.97, 1),
  _ConfettiPiece(-25.37, 412.81, 8.509, 8.18, 5.558, 6.568, 58.31, 1),
  _ConfettiPiece(75.31, 44.97, 7.93, 8.373, 5.558, 6.568, 153.08, 1),
  _ConfettiPiece(413.35, 137.43, 8.509, 8.18, 5.558, 6.568, -121.69, 0.25),
  _ConfettiPiece(313.25, 505.07, 7.93, 8.373, 5.558, 6.568, -26.92, 0.25),
  _ConfettiPiece(-44.14, 351.9, 16.599, 13.175, 5.558, 16.076, 58.31, 0.25),
  _ConfettiPiece(132.59, 30.92, 12.235, 16.85, 5.558, 16.076, 153.08, 0.25),
  _ConfettiPiece(424.03, 193.34, 16.599, 13.175, 5.558, 16.076, -121.69, 0),
  _ConfettiPiece(251.67, 510.65, 12.235, 16.85, 5.558, 16.076, -26.92, 0),
  _ConfettiPiece(376.54, 225.6, 16.599, 13.175, 5.558, 16.076, -121.69, 1),
  _ConfettiPiece(-40.34, 293.98, 7.54, 7.903, 5.558, 6.237, 22.79, 1),
  _ConfettiPiece(195.07, 39.75, 8.1, 7.813, 5.558, 6.237, 117.56, 1),
  _ConfettiPiece(429.29, 256.54, 7.54, 7.903, 5.558, 6.237, -157.21, 1),
  _ConfettiPiece(82.16, 247.45, 7.54, 7.903, 5.558, 6.237, 22.79, 0.25),
  _ConfettiPiece(231.25, 165.69, 8.1, 7.813, 5.558, 6.237, 117.56, 0.25),
  _ConfettiPiece(306.79, 303.07, 7.54, 7.903, 5.558, 6.237, -157.21, 0),
  _ConfettiPiece(157.14, 384.92, 8.1, 7.813, 5.558, 6.237, -62.44, 0),
  _ConfettiPiece(26.13, 76.52, 15.444, 14.438, 10.446, 12.345, 67.01, 1),
  _ConfettiPiece(399.82, 124.15, 13.782, 14.992, 10.446, 12.345, 161.78, 1),
  _ConfettiPiece(354.91, 467.46, 15.444, 14.438, 10.446, 12.345, -112.99, 0),
  _ConfettiPiece(-17.11, 419.28, 13.782, 14.992, 10.446, 12.345, -18.22, 0),
  _ConfettiPiece(34.68, 139.19, 12.937, 8.528, 4.026, 12.345, 67.01, 0.5),
  _ConfettiPiece(342.75, 127.45, 7.684, 12.985, 4.026, 12.345, 161.78, 0.5),
  _ConfettiPiece(348.87, 410.7, 12.937, 8.528, 4.026, 12.345, -112.99, 0.25),
  _ConfettiPiece(46.05, 417.98, 7.684, 12.985, 4.026, 12.345, -18.22, 0.25),
  _ConfettiPiece(55.57, 154.38, 8.167, 5.744, 4.026, 7.397, 104.44, 0.75),
  _ConfettiPiece(328.18, 147.09, 6.236, 8.31, 4.026, 7.397, -160.78, 0.75),
  _ConfettiPiece(332.75, 398.29, 8.167, 5.744, 4.026, 7.397, -75.56, 0.75),
  _ConfettiPiece(62.07, 403.02, 6.236, 8.31, 4.026, 7.397, 19.22, 0.75),
];
