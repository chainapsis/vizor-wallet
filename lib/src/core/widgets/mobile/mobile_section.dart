import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import 'mobile_surface_card.dart';

/// A titled group of mobile content: the label sits on the page above its
/// card, and the card floats on [mobileSurfaceShadows]. Settings, Accounts
/// and similar list screens share it.
class MobileSection extends StatelessWidget {
  const MobileSection({
    required this.title,
    required this.child,
    this.leading,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    super.key,
  });

  final String title;

  /// Optional 16px mark before the label, such as a network icon.
  final Widget? leading;

  /// The card's content; [MobileSectionRows] for a list.
  final Widget child;

  /// Inset inside the card. List rows carry their own height, so the default
  /// adds 8px above the first row and below the last.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                title,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        MobileSurfaceCard(
          cornerRadius: AppRadii.large,
          padding: padding,
          child: child,
        ),
      ],
    );
  }
}

/// List rows inside a [MobileSection] card, split by [MobileSectionDivider].
/// The rows carry their own height.
class MobileSectionRows extends StatelessWidget {
  const MobileSectionRows({required this.rows, super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const MobileSectionDivider(),
        rows[i],
      ],
    ],
  );
}

/// The hairline between rows of a [MobileSection], spanning the card's
/// content width.
class MobileSectionDivider extends StatelessWidget {
  const MobileSectionDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: context.colors.border.subtle);
}
