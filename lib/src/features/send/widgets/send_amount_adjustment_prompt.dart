import 'package:flutter/material.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'send_amount_suggestion.dart';

enum SendAmountAdjustmentChoice { review, edit }

/// Mobile uses a sheet. Desktop mounts the prompt in its content pane instead
/// of a navigator dialog so the sidebar stays outside the modal and scrim.
Future<SendAmountAdjustmentChoice?> showMobileSendAmountAdjustmentSheet(
  BuildContext context, {
  required BigInt enteredAmount,
  required SendAmountSuggestion suggestion,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  ModalRoute<dynamic>? promptRoute;

  Widget content(BuildContext promptContext) {
    promptRoute = ModalRoute.of(promptContext);
    return SendAmountAdjustmentPrompt(
      enteredAmount: enteredAmount,
      suggestion: suggestion,
      onReview: () =>
          Navigator.of(promptContext).pop(SendAmountAdjustmentChoice.review),
      onEdit: () =>
          Navigator.of(promptContext).pop(SendAmountAdjustmentChoice.edit),
      onClose: () => Navigator.of(promptContext).pop(),
    );
  }

  final choice = await showAppMobileSheet<SendAmountAdjustmentChoice>(
    context: context,
    builder: content,
  );
  // Wait for the overlay to leave before opening Review or restoring the
  // keyboard. This uses route completion, not a guessed animation delay.
  await promptRoute?.completed;
  return choice;
}

class SendAmountAdjustmentPrompt extends StatelessWidget {
  const SendAmountAdjustmentPrompt({
    required this.enteredAmount,
    required this.suggestion,
    required this.onReview,
    required this.onEdit,
    required this.onClose,
    super.key,
  });

  final BigInt enteredAmount;
  final SendAmountSuggestion suggestion;
  final VoidCallback onReview;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  static const _mobile = kAppFormFactor == AppFormFactor.mobile;
  static const _title = 'A smaller transfer is needed';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your Ledger can’t sign this transfer as entered. '
          'You can review a smaller amount for this transfer.',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.neutralSubtleOpacity,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Column(
            children: [
              _amountRow(
                context,
                'Entered',
                ZecAmount.fromZatoshi(enteredAmount).pretty().amountText,
              ),
              const SizedBox(height: AppSpacing.s),
              _amountRow(
                context,
                'This transfer',
                suggestion.amountText,
                emphasized: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'Only the amount changes. Nothing is sent until you review and approve.',
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('send_amount_adjustment_review'),
          onPressed: onReview,
          expand: true,
          size: _mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
          child: Text('Review ${suggestion.amountText} ZEC'),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('send_amount_adjustment_edit'),
          onPressed: onEdit,
          expand: true,
          variant: AppButtonVariant.ghost,
          size: _mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
          child: const Text('Edit amount'),
        ),
      ],
    );
    if (_mobile) {
      return SingleChildScrollView(
        child: MobileModalScaffold(
          key: const ValueKey('send_amount_adjustment_sheet'),
          title: _title,
          titleMaxLines: 2,
          onClose: onClose,
          child: body,
        ),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('send_amount_adjustment_dialog'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.text.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey('send_amount_adjustment_close'),
                onPressed: onClose,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.medium,
                child: const AppIcon(AppIcons.cross, semanticLabel: 'Close'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          body,
        ],
      ),
    );
  }

  Widget _amountRow(
    BuildContext context,
    String label,
    String amount, {
    bool emphasized = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            '$amount ZEC',
            textAlign: TextAlign.end,
            style: AppTypography.labelLarge.copyWith(
              color: emphasized
                  ? context.colors.text.accent
                  : context.colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}
