import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The "Review Wrap" card from the send review/status and received receipt
/// screens: full-width, 24px-radius surface with the subtle four-layer
/// surface shadow, hosting list rows and dividers with a 16px gap.
///
/// Figma `radii/m` is 24px → [AppRadii.large], NOT `AppRadii.medium` (16);
/// the radii scale is mapped by value, not by token name.
class ReviewWrapCard extends StatelessWidget {
  const ReviewWrapCard({required this.children, this.surfaceColor, super.key});

  /// List rows / dividers, separated by a 16px gap.
  final List<Widget> children;

  /// Fixed surface override. The failed status screen keeps the dark
  /// `#1b1f1f` card (`Primitives.p50Dark`) in BOTH themes — that instance
  /// must pass the primitive here instead of relying on the theme
  /// `background.ground` getter, which flips to near-white in light mode.
  final Color? surfaceColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surfaceColor ?? colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 1px hairline divider between list groups inside [ReviewWrapCard].
class ReviewWrapDivider extends StatelessWidget {
  const ReviewWrapDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        color: context.colors.border.regular,
        // Figma `input/radii` = 12px → AppRadii.small (value-mapped).
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
    );
  }
}
