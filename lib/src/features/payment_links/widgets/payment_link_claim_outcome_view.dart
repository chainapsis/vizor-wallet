import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../services/payment_link_received_store.dart';
import 'mobile/payment_link_mobile_views.dart';
import 'payment_link_desktop_views.dart';
import '../../../core/l10n/l10n.dart';

extension PaymentLinkAvailabilityCopy on PaymentLinkAvailability {
  String label(AppLocalizations l10n) => switch (this) {
    PaymentLinkAvailability.unchecked ||
    PaymentLinkAvailability.available => l10n.paymentLinkAvailabilityClaim,
    PaymentLinkAvailability.noBalance => l10n.paymentLinkAvailabilityNoBalance,
    PaymentLinkAvailability.claimedElsewhere =>
      l10n.paymentLinkClaimedElsewhereLabel,
    PaymentLinkAvailability.checking || PaymentLinkAvailability.rejected =>
      l10n.paymentLinkAvailabilityCheckingResult,
    PaymentLinkAvailability.failed => l10n.paymentLinkAvailabilityClaimFailed,
  };

  String description(AppLocalizations l10n) => switch (this) {
    PaymentLinkAvailability.claimedElsewhere =>
      l10n.paymentLinkClaimedElsewhereDescription,
    PaymentLinkAvailability.failed =>
      l10n.paymentLinkAvailabilityFailedDescription,
    PaymentLinkAvailability.rejected =>
      l10n.paymentLinkAvailabilityRejectedDescription,
    PaymentLinkAvailability.checking =>
      l10n.paymentLinkAvailabilityCheckingDescription,
    PaymentLinkAvailability.noBalance =>
      l10n.paymentLinkAvailabilityNoBalanceDescription,
    _ => l10n.paymentLinkAvailabilityReadyDescription,
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
            availability.label(context.l10n),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: isError
                  ? context.colors.text.destructive
                  : context.colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            availability.description(context.l10n),
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
              child: Text(
                busy
                    ? context.l10n.commonCheckingEllipsis
                    : context.l10n.paymentLinkCheckStatus,
              ),
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
            child: Text(context.l10n.paymentLinkRemoveCardLabel),
          )
        : onArchive == null
        ? null
        : AppButton(
            onPressed: busy ? null : onArchive,
            growWithContent: embedded,
            variant: AppButtonVariant.secondary,
            child: Text(
              archived
                  ? context.l10n.paymentLinkRestoreCard
                  : context.l10n.paymentLinkHideCard,
            ),
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
