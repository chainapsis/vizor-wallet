import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Rounded content surface used by the mobile screens (Figma `Surface`
/// groups in the mobile frames): a ground-colored card that sections
/// settings rows, activity groups, and similar list content.
class MobileSurfaceCard extends StatelessWidget {
  const MobileSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.cornerRadius = defaultRadius,
    super.key,
  });

  /// Corner radius measured from the Figma mobile surfaces (not
  /// tokenized as a variable yet).
  static const defaultRadius = 20.0;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
