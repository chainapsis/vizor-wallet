import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';

/// Shared "Confirm access" password gate card.
///
/// Used by the secret passphrase, change password, and uninstall flows;
/// only [subtitle] and the submit destination differ between them.
class ConfirmAccessCard extends StatelessWidget {
  const ConfirmAccessCard({
    required this.subtitle,
    required this.controller,
    required this.errorText,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    this.autofocus = true,
    super.key,
  });

  final String subtitle;
  final TextEditingController controller;
  final String? errorText;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final bool autofocus;

  static const width = 396.0;

  // Title block (33 + 4 + 16), field block (66), and 16/8 vertical
  // padding total 200 in the design; the remainder is this fixed gap.
  static const _titleFieldGap = 57.0;

  // Field shell (46) + message gap (4) + message row (16). The design
  // reserves the message row at opacity 0, so the card height does not
  // change when an error appears.
  static const _fieldBlockHeight = 66.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;
    final hasError = errorText != null && errorText!.trim().isNotEmpty;

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(
          color: const Color(0x12FFFFFF),
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm access',
                      style: AppTypography.headlineLarge.copyWith(
                        color: cardTextColor,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Opacity(
                      opacity: 0.5,
                      child: Text(
                        subtitle,
                        style: AppTypography.labelMedium.copyWith(
                          color: cardTextColor,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Opacity(
                opacity: 0.5,
                child: AppIcon(AppIcons.lock, size: 32, color: cardTextColor),
              ),
            ],
          ),
          const SizedBox(height: _titleFieldGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: _fieldBlockHeight,
                  child: AppTextField(
                    label: 'Password',
                    showLabel: false,
                    controller: controller,
                    hintText: 'Your password...',
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    autofocus: autofocus,
                    enabled: !isSubmitting,
                    messageText: errorText,
                    tone: hasError
                        ? AppTextFieldTone.destructive
                        : AppTextFieldTone.neutral,
                    inputHorizontalPadding: AppSpacing.s,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Semantics(
                button: true,
                label: 'Confirm password',
                child: AppButton(
                  onPressed: canSubmit && !isSubmitting ? onSubmit : null,
                  variant: AppButtonVariant.secondary,
                  minWidth: 80,
                  child: AppIcon(
                    isSubmitting ? AppIcons.loader : AppIcons.chevronForward,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
