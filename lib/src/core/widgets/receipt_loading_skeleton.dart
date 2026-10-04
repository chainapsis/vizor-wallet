import 'package:flutter/widgets.dart';

import '../layout/app_form_factor.dart';
import '../theme/app_theme.dart';
import 'mobile/mobile_review_row.dart';
import 'review_info_row.dart';
import 'review_list_row.dart';

/// Static placeholders keep receipt geometry steady without adding motion
/// during the short local-wallet read. They never stand in for real addresses.
class ReceiptValueSkeleton extends StatelessWidget {
  const ReceiptValueSkeleton({this.width = 120, this.height = 12, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.text.secondary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
    ),
  );
}

class ReceiptCounterpartySkeleton extends StatelessWidget {
  const ReceiptCounterpartySkeleton({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    const value = ReceiptValueSkeleton(width: 180, height: 24);
    const bottom = Align(
      alignment: Alignment.centerLeft,
      child: ReceiptValueSkeleton(width: 88, height: 10),
    );
    final iconSize = mobile ? 40.0 : AppAssetSize.size;
    final leading = ReceiptValueSkeleton(width: iconSize, height: iconSize);
    return mobile
        ? MobileReviewInfoRow(
            label: label,
            value: '',
            valuePlaceholder: value,
            leading: leading,
            bottom: bottom,
          )
        : ReviewInfoRow(
            label: label,
            value: '',
            valuePlaceholder: value,
            leading: leading,
            bottomLeftPlaceholder: bottom,
          );
  }
}

class ReceiptMemoSkeleton extends StatelessWidget {
  const ReceiptMemoSkeleton({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ReviewListRow.height,
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Text(
            'Message',
            style:
                (kAppFormFactor == AppFormFactor.mobile
                        ? AppTypography.labelMedium
                        : AppTypography.bodyMediumStrong)
                    .copyWith(color: context.colors.text.secondary),
          ),
        ),
        const Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: ReceiptValueSkeleton(),
          ),
        ),
      ],
    ),
  );
}
