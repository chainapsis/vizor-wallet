import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

/// Figma swap display style: YoungSerif-Medium 32/33 with the OpenType
/// 'case' feature, which swaps Young Serif's default old-style figures for
/// uniform lining digits. Shared by the composer amounts, the swap page
/// title, and the review/status summary amounts.
TextStyle swapSerifDisplayStyle({required Color color}) {
  return AppTypography.displaySmall.copyWith(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.enable('case')],
    color: color,
  );
}
