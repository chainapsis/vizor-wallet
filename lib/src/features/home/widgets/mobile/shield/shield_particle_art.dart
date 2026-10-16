import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'balance_art.dart';
import 'particles/cloud_layout.dart';
import 'particles/shape_sampler.dart';
import 'particles/sprite_atlas.dart';
import 'shield_timeline.dart';

final List<({Offset p, double size, double alpha})> shieldCloudDots = () {
  const scale = 1.0;
  const center = Offset(196.0, 386.7);
  String at(int r, int c) => r < kCloudRows.length && c < kCloudRows[r].length
      ? kCloudRows[r][c]
      : ' ';
  ({Offset p, double size, double alpha}) dot(double r, double c, String k) {
    final p = Offset(
      kCloudOriginX + c * kCloudPitchX,
      kCloudOriginY + r * kCloudPitchY,
    );
    return (
      p: center + (p - center) * scale,
      size: switch (k) {
        '.' => 1.146,
        ':' => 2.292,
        'o' => 3.438,
        _ => 4.584,
      },
      alpha: switch (k) {
        '.' => 1.0,
        ':' => 0.75,
        'o' => 0.5,
        _ => 0.25,
      },
    );
  }

  return [
    for (var r = 0; r < kCloudRows.length; r++)
      for (var c = 0; c < kCloudRows[r].length; c++)
        if (at(r, c) != ' ') dot(r.toDouble(), c.toDouble(), at(r, c)),
  ];
}();

class ShieldParticleArt {
  ShieldParticleArt({
    required this.atlas,
    required this.textPoints,
    required this.shieldCells,
    required this.shieldSize,
    required this.balancePoints,
    required this.iconPoints,
    required this.glowText,
    required this.glowSize,
  });

  final SpriteAtlas atlas;
  final List<Offset> textPoints;
  final List<Offset> shieldCells;
  final Size shieldSize;
  final List<Offset> balancePoints;
  final List<Offset> iconPoints;
  final BakedImage glowText;
  final Size glowSize;
  static const _shieldAsset = 'assets/icons/shielding_success_shield_fill.svg';
  static const iconWidth = 31.7234;
  static const iconHeight = 36.6677;

  static Future<ShieldParticleArt> load(
    String amount, {
    required String resultAmount,
    bool showResultAmount = true,
    required int count,
    required math.Random random,
    required double fontSize,
    double? resultFontSize,
  }) async {
    final atlas = await SpriteAtlas.build();
    // Solid stand-ins with the same plain-text geometry: the dots crumble from the
    // amount and its unit, and pour back into them.
    final before = BalanceArt(
      amount,
      look: BalanceLook.solid,
      unitTop: BalanceArt.unitOffset,
      fontSize: fontSize,
    );
    final after = BalanceArt(
      resultAmount,
      look: BalanceLook.solid,
      unitTop: BalanceArt.unitOffset,
      fontSize: resultFontSize ?? fontSize,
    );
    final textPoints = await ShapeSampler.picture(
      before.size,
      before.paint,
      count: count,
      random: random,
    );
    final balancePoints = showResultAmount
        ? await ShapeSampler.picture(
            after.size,
            after.paint,
            count: count - ShieldTimeline.iconParticles - ShieldTimeline.strays,
            random: random,
          )
        : <Offset>[];
    final iconPoints = await ShapeSampler.svgPoints(
      _shieldAsset,
      height: iconHeight,
      count: ShieldTimeline.iconParticles,
      random: random,
    );

    // Keep the reference video's original density and shield scale, with
    // one particle per halftone cell.
    final pitch = kCloudPitchX * math.sqrt(718 / count);
    var height = 286.0;
    var cells = <Offset>[];
    for (var i = 0; i < 4; i++) {
      cells = await ShapeSampler.svgCells(
        _shieldAsset,
        height: height,
        pitch: pitch,
        solid: true,
      );
      final ratio = cells.length / count;
      if ((ratio - 1).abs() < 0.04) break;
      height /= math.sqrt(ratio);
    }

    // Blurred ghost of the balance, a touch larger, behind the cloud.
    const glowScale = 1.05;
    final glowSize = before.size * glowScale;
    return ShieldParticleArt(
      atlas: atlas,
      textPoints: textPoints,
      shieldCells: cells,
      shieldSize: Size(height * iconWidth / iconHeight, height),
      balancePoints: balancePoints,
      iconPoints: iconPoints,
      glowText: await ShapeSampler.blurred(glowSize, (canvas) {
        canvas.scale(glowScale);
        before.paint(canvas);
      }, sigma: 48.859),
      glowSize: glowSize,
    );
  }

  void dispose() {
    atlas.dispose();
    glowText.dispose();
  }
}
