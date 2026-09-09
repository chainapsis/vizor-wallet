import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Model-neutral device guidance; never depicts a specific physical button.
class LedgerDeviceIllustration extends StatelessWidget {
  const LedgerDeviceIllustration({
    this.large = false,
    this.busy = false,
    this.attention = false,
    this.destructive = false,
    this.complete = false,
    super.key,
  });

  final bool large;
  final bool busy;
  final bool attention;
  final bool destructive;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: large ? 240 : 180,
        height: large ? 112 : 80,
        padding: EdgeInsets.all(large ? AppSpacing.md : AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: colors.border.subtle),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.background.base,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(
              color: attention ? colors.text.secondary : colors.border.subtle,
            ),
          ),
          child: Center(
            child: AppIcon(
              busy
                  ? AppIcons.loader
                  : complete
                  ? AppIcons.check
                  : destructive
                  ? AppIcons.warningCircle
                  : AppIcons.ledger,
              size: large ? 32 : 24,
              color: destructive ? colors.text.destructive : colors.text.accent,
            ),
          ),
        ),
      ),
    );
  }
}
