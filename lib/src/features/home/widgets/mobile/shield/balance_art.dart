import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'shield_motion.dart';

enum BalanceLook { transparent, shielded, solid }

/// The original video uses a plain serif amount and ZEC, without a capsule.
/// Painting and particle sampling share this geometry at every handover.
class BalanceArt {
  BalanceArt(
    String amount, {
    required this.look,
    required this.unitTop,
    this.fontSize = 84,
  }) : _amount = TextPainter(
         text: TextSpan(
           text: amount,
           style: VText.display.copyWith(
             color: _white,
             fontSize: fontSize,
             fontWeight: FontWeight.w700,
             letterSpacing: -0.04 * fontSize,
             height: 1,
           ),
         ),
         textDirection: TextDirection.ltr,
       )..layout(),
       _zec = TextPainter(
         text: TextSpan(
           text: 'ZEC',
           style: VText.display.copyWith(
             color: look == BalanceLook.solid
                 ? _white
                 : const Color(0x99FFFFFF),
             fontSize: 48 * fontSize / 84,
             fontWeight: FontWeight.w500,
             letterSpacing: 0,
             height: 1,
           ),
         ),
         textDirection: TextDirection.ltr,
       )..layout();

  final BalanceLook look;
  final double unitTop;
  final double fontSize;
  double get unitY => unitTop * fontSize / 84;
  double get unitFrom => unitY - 5 * fontSize / 84;
  final TextPainter _amount;
  final TextPainter _zec;
  static const unitOffset = 80.0;
  static const _white = Color(0xFFFFFFFF);
  Size get size =>
      Size(math.max(_amount.width, _zec.width), unitY + _zec.height);

  void paint(Canvas canvas) {
    _amount.paint(canvas, Offset((size.width - _amount.width) / 2, 0));
    _zec.paint(canvas, Offset((size.width - _zec.width) / 2, unitY));
  }
}
