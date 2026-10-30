import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../shield_motion.dart';

/// One sprite inside the atlas: its source rect, the anchor the particle
/// position maps to, and how many atlas pixels equal one "size" unit.
class Sprite {
  const Sprite(this.rect, this.anchor, this.unit);

  final Rect rect;
  final Offset anchor;
  final double unit;
}

/// White sprites rendered once. Every particle in a frame is a single
/// `drawRawAtlas` call that tints, scales and rotates one of these.
class SpriteAtlas {
  SpriteAtlas._(this.image);

  final ui.Image image;

  static const _px = 24.0; // dot diameter in atlas pixels
  static const _pad = 2.0;

  /// Round dot, the Figma halftone particle (corner radius 111 on each rect).
  static const dot = Sprite(
    Rect.fromLTWH(0, 0, _px + 2 * _pad, _px + 2 * _pad),
    Offset(_px / 2 + _pad, _px / 2 + _pad),
    _px,
  );

  /// Soft radial glow for blink halos and out-of-focus bokeh.
  static const halo = Sprite(Rect.fromLTWH(28, 0, 96, 96), Offset(48, 48), 96);

  /// Motion streaks: the dot plus a fading tail, in three lengths (as a
  /// multiple of the dot size). Anchored on the head.
  static const streakAspects = [2.0, 3.5, 6.0];
  static const streaks = [
    Sprite(Rect.fromLTWH(124, 0, 52, 28), Offset(52 - 14, 14), _px),
    Sprite(Rect.fromLTWH(176, 0, 88, 28), Offset(88 - 14, 14), _px),
    Sprite(Rect.fromLTWH(264, 0, 148, 28), Offset(148 - 14, 14), _px),
  ];

  /// Digits 0–9 for the "numbers" particle look.
  static const _digitW = 28.0;
  static const _digitH = 40.0;
  static final digits = List<Sprite>.unmodifiable([
    for (var d = 0; d < 10; d++)
      Sprite(
        Rect.fromLTWH(d * _digitW, 96, _digitW, _digitH),
        const Offset(_digitW / 2, _digitH / 2),
        // Scales the 32px glyphs so a particle's size reads as digit weight.
        9.5,
      ),
  ]);

  static Future<SpriteAtlas> build() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final white = Paint()..color = const Color(0xFFFFFFFF);

    // Dot.
    canvas.drawCircle(dot.rect.center, _px / 2, white);

    // Halo: Gaussian-ish falloff, fully transparent at the cell edge.
    canvas.drawCircle(
      halo.rect.center,
      48,
      Paint()
        ..shader = ui.Gradient.radial(
          halo.rect.center,
          48,
          const [
            Color(0xFFFFFFFF),
            Color(0x8CFFFFFF),
            Color(0x2EFFFFFF),
            Color(0x0AFFFFFF),
            Color(0x00FFFFFF),
          ],
          const [0, 0.22, 0.5, 0.75, 1],
        ),
    );

    // Streaks: a rounded tail fades in toward a round head.
    for (var i = 0; i < streaks.length; i++) {
      final r = streaks[i].rect;
      final body = Rect.fromLTRB(
        r.left + _pad,
        r.top + _pad,
        r.right - _pad,
        r.bottom - _pad,
      );
      final tail = Rect.fromLTRB(
        body.left,
        body.top,
        body.right - _px,
        body.bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(tail, const Radius.circular(_px / 2)),
        Paint()
          ..shader = ui.Gradient.linear(
            tail.centerLeft,
            tail.centerRight,
            const [Color(0x00FFFFFF), Color(0xB3FFFFFF)],
          ),
      );
      canvas.drawCircle(
        Offset(body.right - _px / 2, body.center.dy),
        _px / 2,
        white,
      );
    }

    // Digits.
    for (var d = 0; d < 10; d++) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$d',
          style: const TextStyle(
            fontFamily: VText.geist,
            fontWeight: FontWeight.w500,
            fontSize: 32,
            height: 1,
            color: Color(0xFFFFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final cell = digits[d].rect;
      tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
    }

    final image = await recorder.endRecording().toImage(512, 136);
    return SpriteAtlas._(image);
  }

  void dispose() => image.dispose();
}
