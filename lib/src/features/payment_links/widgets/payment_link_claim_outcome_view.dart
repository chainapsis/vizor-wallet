import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../services/payment_link_received_store.dart';

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

/// Shared outcome content uses form-factor tokens and scrolls on small screens.
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
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBackLink(label: 'My Cards', onTap: onBack),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 396),
              child: Column(
                children: [
                  Text(
                    availability.label,
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: context.colors.text.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    availability.description,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (onCheck != null)
                    AppButton(
                      onPressed: busy ? null : onCheck,
                      child: Text(busy ? 'Checking...' : 'Check status'),
                    ),
                  if (onArchive != null) ...[
                    const SizedBox(height: AppSpacing.s),
                    AppButton(
                      onPressed: busy ? null : onArchive,
                      variant: AppButtonVariant.secondary,
                      child: Text(archived ? 'Restore card' : 'Hide card'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
