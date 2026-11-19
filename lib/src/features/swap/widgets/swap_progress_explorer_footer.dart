import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_wrap_card.dart';

/// A full-width external lookup action inside a Swap or Pay progress card.
/// A confidential swap or payment shows [SwapProgressConfidentialNote] in its
/// place.
class SwapProgressExplorerFooter extends StatelessWidget {
  const SwapProgressExplorerFooter({required this.uri, super.key});

  final Uri uri;

  Future<void> _open() async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A platform without a browser must not interrupt status tracking.
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: AppSpacing.s),
      const ReviewWrapDivider(),
      const SizedBox(height: AppSpacing.xxs),
      AppButton(
        key: const ValueKey('swap_progress_explorer_link'),
        onPressed: () => unawaited(_open()),
        variant: AppButtonVariant.ghost,
        hoverBackgroundColor: context.colors.background.ground.withValues(
          alpha: 0,
        ),
        height: AppButtonSizing.largeHeight,
        expand: true,
        constrainContent: true,
        growWithContent: true,
        borderRadius: BorderRadius.circular(AppRadii.small),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Row(
          children: [
            Expanded(child: Text(context.l10n.swapViewOnNearIntents)),
            const SizedBox(width: AppSpacing.xs),
            AppIcon(
              AppIcons.arrowTopRight,
              size: AppIconSize.medium,
              color: context.colors.icon.muted,
            ),
          ],
        ),
      ),
    ],
  );
}

/// Where [SwapProgressExplorerFooter] sits on a confidential swap or payment:
/// says the explorer link is missing on purpose and that progress shows here.
/// Not a button, but as tall as one, so the card keeps the footer's spacing.
class SwapProgressConfidentialNote extends StatelessWidget {
  const SwapProgressConfidentialNote({required this.payment, super.key});

  /// A Pay progress card rather than a swap's.
  final bool payment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Column(
      key: const ValueKey('swap_progress_confidential_note'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.s),
        const ReviewWrapDivider(),
        const SizedBox(height: AppSpacing.xxs),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppButtonSizing.largeHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xs,
            ),
            // No mark here: the route above the rows already carries it.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                payment
                    ? l10n.swapConfidentialNoExplorerPay
                    : l10n.swapConfidentialNoExplorerSwap,
                // Mobile text stays at 16px or more.
                style:
                    (kAppFormFactor == AppFormFactor.mobile
                            ? AppTypography.bodyMedium
                            : AppTypography.bodySmall)
                        .copyWith(color: colors.text.secondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
