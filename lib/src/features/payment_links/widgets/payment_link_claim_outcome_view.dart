import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../services/payment_link_received_store.dart';
import 'mobile/payment_link_mobile_views.dart';
import 'payment_link_desktop_views.dart';

extension PaymentLinkAvailabilityCopy on PaymentLinkAvailability {
  String get label => switch (this) {
    PaymentLinkAvailability.unchecked ||
    PaymentLinkAvailability.available => 'Claim',
    PaymentLinkAvailability.noBalance => 'No balance',
    PaymentLinkAvailability.claimedElsewhere => 'Already claimed',
    PaymentLinkAvailability.checking ||
    PaymentLinkAvailability.rejected => 'Checking result',
    PaymentLinkAvailability.failed => 'Claim failed',
  };

  String get description => switch (this) {
    PaymentLinkAvailability.claimedElsewhere =>
      'This gift card was claimed elsewhere. There is no balance available to claim.',
    PaymentLinkAvailability.failed =>
      'Your claim did not complete. Check the card before trying again.',
    PaymentLinkAvailability.rejected =>
      'The network did not accept this claim. Check its status before trying again.',
    PaymentLinkAvailability.checking =>
      'Your claim result is not confirmed yet. Check again shortly.',
    PaymentLinkAvailability.noBalance =>
      'There is currently no balance available to claim.',
    _ => 'This gift card is ready to claim.',
  };
}

/// Claim outcomes stay inside the existing redeem surface in both form factors.
class PaymentLinkClaimOutcomeView extends StatelessWidget {
  const PaymentLinkClaimOutcomeView({
    required this.availability,
    required this.onBack,
    this.onCheck,
    this.onArchive,
    this.archived = false,
    this.busy = false,
    super.key,
  });
  final PaymentLinkAvailability availability;
  final VoidCallback onBack;
  final VoidCallback? onCheck;
  final VoidCallback? onArchive;
  final bool archived;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isError = switch (availability) {
      PaymentLinkAvailability.noBalance ||
      PaymentLinkAvailability.claimedElsewhere ||
      PaymentLinkAvailability.failed => true,
      _ => false,
    };
    final content = SingleChildScrollView(
      key: const ValueKey('payment_link_claim_outcome_scroll'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          key: const ValueKey('payment_link_claim_outcome_content'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              availability.label,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: isError
                    ? context.colors.text.destructive
                    : context.colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              availability.description,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            if (onCheck != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: busy ? null : onCheck,
                child: Text(busy ? 'Checking...' : 'Check status'),
              ),
            ],
          ],
        ),
      ),
    );
    final archiveAction = onArchive == null
        ? null
        : AppButton(
            onPressed: busy ? null : onArchive,
            variant: AppButtonVariant.secondary,
            child: Text(archived ? 'Restore card' : 'Hide card'),
          );
    if (kAppFormFactor == AppFormFactor.mobile) {
      return PaymentLinkRedeemMobileView(
        state: PaymentLinkRedeemMobileState.paste,
        onBack: onBack,
        subtitle: '',
        statusContent: content,
        secondaryAction: archiveAction,
      );
    }
    return PaymentLinkRedeemDesktopView(
      state: PaymentLinkRedeemVisualState.paste,
      onBack: onBack,
      subtitle: '',
      statusContent: content,
      secondaryAction: archiveAction,
    );
  }
}
