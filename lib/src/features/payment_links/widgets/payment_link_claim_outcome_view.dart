import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../services/payment_link_received_store.dart';
import 'mobile/payment_link_mobile_views.dart';
import 'payment_link_copy.dart';
import 'payment_link_desktop_views.dart';

extension PaymentLinkAvailabilityCopy on PaymentLinkAvailability {
  String get label => switch (this) {
    PaymentLinkAvailability.unchecked ||
    PaymentLinkAvailability.available => 'Claim',
    PaymentLinkAvailability.noBalance => 'No balance',
    PaymentLinkAvailability.claimedElsewhere =>
      kPaymentLinkClaimedElsewhereLabel,
    PaymentLinkAvailability.checking ||
    PaymentLinkAvailability.rejected => 'Checking result',
    PaymentLinkAvailability.failed => 'Claim failed',
  };

  String get description => switch (this) {
    PaymentLinkAvailability.claimedElsewhere =>
      kPaymentLinkClaimedElsewhereDescription,
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
    this.onRemove,
    this.archived = false,
    this.busy = false,
    this.embedded = false,
    super.key,
  });
  final PaymentLinkAvailability availability;
  final VoidCallback onBack;
  final VoidCallback? onCheck;
  final VoidCallback? onArchive;

  /// Offered instead of hiding when nothing is left to claim.
  final VoidCallback? onRemove;
  final bool archived;
  final bool busy;

  /// Share the owning claim stage instead of adding another scroll surface.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final isError = switch (availability) {
      PaymentLinkAvailability.noBalance ||
      PaymentLinkAvailability.claimedElsewhere ||
      PaymentLinkAvailability.failed => true,
      _ => false,
    };
    final details = Padding(
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
              growWithContent: embedded,
              child: Text(busy ? 'Checking…' : 'Check status'),
            ),
          ],
        ],
      ),
    );
    final content = SingleChildScrollView(
      key: const ValueKey('payment_link_claim_outcome_scroll'),
      child: details,
    );
    final archiveAction = onRemove != null
        ? AppButton(
            onPressed: busy ? null : onRemove,
            growWithContent: embedded,
            variant: AppButtonVariant.secondary,
            child: const Text(kPaymentLinkRemoveCardLabel),
          )
        : onArchive == null
        ? null
        : AppButton(
            onPressed: busy ? null : onArchive,
            growWithContent: embedded,
            variant: AppButtonVariant.secondary,
            child: Text(archived ? 'Restore card' : 'Hide card'),
          );
    if (embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          details,
          if (archiveAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            archiveAction,
          ],
        ],
      );
    }
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
