import 'package:flutter/widgets.dart';

import 'app_typography.dart';

/// Figma serif display style: YoungSerif-Medium 32/33 with the OpenType
/// 'case' feature, which swaps Young Serif's default old-style figures for
/// uniform lining digits. Shared by the review-info amounts, the swap
/// composer amounts, and serif page titles.
TextStyle appSerifDisplayStyle({required Color color}) {
  return AppTypography.displaySmall.copyWith(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.enable('case')],
    color: color,
  );
}
