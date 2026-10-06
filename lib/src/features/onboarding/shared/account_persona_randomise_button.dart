import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

/// The account card's renew control, with a 28px circle inside a 44px target.
class AccountPersonaRandomiseButton extends StatelessWidget {
  const AccountPersonaRandomiseButton({
    required this.onPressed,
    this.actionKey,
    this.visualKey,
    this.showTooltip = false,
    super.key,
  });

  static const tapSize = 44.0;
  static const visualSize = 28.0;
  static const _label = 'Randomise account name and profile picture';

  final VoidCallback? onPressed;
  final Key? actionKey;
  final Key? visualKey;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: _label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: AppButton(
          key: actionKey,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.medium,
          height: tapSize,
          minWidth: tapSize,
          contentPadding: EdgeInsets.zero,
          enabledBackgroundColor: colors.background.homeCard.withValues(
            alpha: 0,
          ),
          pressedBackgroundColor: colors.background.homeCard.withValues(
            alpha: 0,
          ),
          disabledBackgroundColor: colors.background.homeCard.withValues(
            alpha: 0,
          ),
          onPressed: onPressed,
          child: Container(
            key: visualKey,
            width: visualSize,
            height: visualSize,
            decoration: BoxDecoration(
              color: enabled
                  ? colors.button.secondary.bg
                  : colors.button.disabled.bg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AppIcon(
                AppIcons.renew,
                size: 16,
                color: enabled
                    ? colors.button.secondary.label
                    : colors.button.disabled.label,
              ),
            ),
          ),
        ),
      ),
    );
    return showTooltip
        ? Tooltip(message: _label, excludeFromSemantics: true, child: button)
        : button;
  }
}
