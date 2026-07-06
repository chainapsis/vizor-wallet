import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal_card.dart';

class SendSpendableInfoModal extends StatelessWidget {
  const SendSpendableInfoModal({required this.onDismiss, super.key});

  static const size = Size(312, 357);

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );

    return Container(
      key: const ValueKey('send_spendable_info_modal'),
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appModalShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 41,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spendable vs. Total Balances',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Why they may differ',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 184,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your Spendable Balance may be lower than\n'
                  'your Total Balance.',
                  style: bodyStyle,
                  softWrap: false,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Funds need confirmations before they can\n'
                  'be spent: 3 confirmations for change from\n'
                  'your own wallet, 10 confirmation for funds\n'
                  'received from others.',
                  style: bodyStyle,
                  softWrap: false,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Shielded notes also need to be fully\n'
                  "scanned. They'll become available shortly.",
                  style: bodyStyle,
                  softWrap: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('send_spendable_info_ack_button'),
            onPressed: onDismiss,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.mediumLarge,
            height: kAppModalButtonHeight,
            minWidth: double.infinity,
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }
}
