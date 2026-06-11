import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_icon.dart';

/// The CTA stack at the bottom of the send review screens: a 44px primary
/// button (optional leading icon) over a 44px ghost secondary, centered in
/// the 420px content column with the Figma 196px minimum button width.
class ReviewButtonsStack extends StatelessWidget {
  const ReviewButtonsStack({
    required this.primaryLabel,
    required this.onPrimaryPressed,
    required this.secondaryLabel,
    required this.onSecondaryPressed,
    this.primaryLeadingIconName,
    super.key,
  });

  /// Primary CTA label ("Confirm & send"). `null` handler disables it.
  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;

  /// Ghost secondary label ("Cancel").
  final String secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  /// Optional 20px icon before the primary label (e.g. the send plane).
  final String? primaryLeadingIconName;

  static const _minButtonWidth = 196.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          onPressed: onPrimaryPressed,
          minWidth: _minButtonWidth,
          leading: primaryLeadingIconName != null
              ? AppIcon(primaryLeadingIconName!)
              : null,
          child: Text(primaryLabel),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          onPressed: onSecondaryPressed,
          variant: AppButtonVariant.ghost,
          minWidth: _minButtonWidth,
          child: Text(secondaryLabel),
        ),
      ],
    );
  }
}
