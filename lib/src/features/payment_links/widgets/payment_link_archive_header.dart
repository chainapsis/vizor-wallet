import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_action.dart';
import '../../../core/l10n/l10n.dart';

/// A quiet disclosure row; the entire row supports pointer and keyboard input.
class PaymentLinkArchiveHeader extends StatelessWidget {
  const PaymentLinkArchiveHeader({
    required this.count,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => PaymentLinkAction(
    expanded: expanded,
    semanticLabel: context.l10n.paymentLinkArchivedCount(count),
    onPressed: onToggle,
    builder: (context, hovered, focused) => Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: hovered ? context.colors.button.ghost.bgHover : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(
          color: focused
              ? context.colors.text.primary
              : const Color(0x00000000),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.paymentLinkArchivedCount(count),
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          RotatedBox(
            quarterTurns: expanded ? 1 : 0,
            child: AppIcon(
              AppIcons.chevronForward,
              size: 16,
              color: context.colors.icon.regular,
            ),
          ),
        ],
      ),
    ),
  );
}
