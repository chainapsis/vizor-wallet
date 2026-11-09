import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/receipt_loading_skeleton.dart';

/// Matches the 44px Activity row, including icon and text-line slots.
/// Static placeholders avoid adding animation work to a local wallet read.
class ActivitySkeletonRow extends StatelessWidget {
  const ActivitySkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    const iconSize = mobile ? AppAssetSize.size : 32.0;
    final titleHeight = _lineHeight(AppTypography.labelLarge);
    final subtitleHeight = math.max(
      titleHeight,
      mobile ? AppIconSize.medium : 16.0,
    );
    final supportingHeight = _lineHeight(
      mobile ? AppTypography.labelLarge : AppTypography.labelSmall,
    );
    return ExcludeSemantics(
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Row(
            children: [
              const ReceiptValueSkeleton(width: iconSize, height: iconSize),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(width: 104, height: titleHeight),
                    const SizedBox(height: AppSpacing.xxs),
                    _line(width: 76, height: subtitleHeight),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _line(width: 88, height: titleHeight),
                  const SizedBox(height: AppSpacing.xxs),
                  _line(width: 64, height: supportingHeight),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _lineHeight(TextStyle style) => style.fontSize! * (style.height ?? 1);

  Widget _line({required double width, required double height}) => SizedBox(
    height: height,
    child: Align(
      alignment: Alignment.centerLeft,
      child: ReceiptValueSkeleton(width: width, height: 10),
    ),
  );
}
