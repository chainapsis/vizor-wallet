import 'package:flutter/widgets.dart';

import '../layout/app_form_factor.dart';
import '../theme/app_theme.dart';
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
    return ReviewInfoRow(
      label: label,
      value: '',
      valuePlaceholder: const ReceiptValueSkeleton(width: 180, height: 24),
      leading: const ReceiptValueSkeleton(
        width: AppAssetSize.size,
        height: AppAssetSize.size,
      ),
      bottomLeftPlaceholder: const Align(
        alignment: Alignment.centerLeft,
        child: ReceiptValueSkeleton(width: 88, height: 10),
      ),
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
