import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tappable.dart';

class SwapModalIconBadge extends StatelessWidget {
  const SwapModalIconBadge({
    required this.iconName,
    required this.iconColor,
    super.key,
  });

  final String iconName;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: AppIcon(iconName, size: 16, color: iconColor),
    );
  }
}

class SwapInlineIconButton extends StatelessWidget {
  const SwapInlineIconButton({
    required this.iconName,
    required this.onTap,
    super.key,
  });

  final String iconName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTappable(
      onTap: onTap,
      child: SizedBox(
        width: 20,
        height: 20,
        child: AppIcon(iconName, size: 20, color: colors.icon.accent),
      ),
    );
  }
}

class SwapModalButtons extends StatelessWidget {
  const SwapModalButtons({
    required this.primaryKey,
    required this.cancelKey,
    required this.onPrimary,
    required this.onCancel,
    this.primaryLabel = 'Update',
    this.primaryEnabled = true,
    super.key,
  });

  final Key primaryKey;
  final Key cancelKey;
  final VoidCallback onPrimary;
  final VoidCallback onCancel;
  final String primaryLabel;
  final bool primaryEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: primaryKey,
          onPressed: primaryEnabled ? onPrimary : null,
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: 280,
          child: SizedBox(
            width: 220,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(primaryLabel)),
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          key: cancelKey,
          onPressed: onCancel,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.large,
          minWidth: 280,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
