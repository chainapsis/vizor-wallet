import 'package:flutter/widgets.dart';

import 'app_typography.dart';

/// Figma serif display style: YoungSerif-Medium 32/33 with the OpenType
/// 'case' feature, which swaps Young Serif's default old-style figures for
/// uniform lining digits. Shared by the review-info amounts, the swap
/// composer amounts, and serif page titles.
///
/// [AppTypography.displaySmall] carries the full serif spec since the
/// Young Serif token migration; this helper remains as the colored
/// convenience wrapper its call sites were written against.
TextStyle appSerifDisplayStyle({required Color color}) {
  return AppTypography.displaySmall.copyWith(color: color);
}
