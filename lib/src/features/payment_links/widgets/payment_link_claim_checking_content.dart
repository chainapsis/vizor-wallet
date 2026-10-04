import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import 'payment_link_copy.dart';

/// The waiting surface keeps discovery separate from permission to claim.
/// Flow layout lets the heading and status grow with accessibility text size.
class PaymentLinkClaimCheckingContent extends StatelessWidget {
  const PaymentLinkClaimCheckingContent({
    required this.card,
    required this.status,
    this.statusSpacing = AppSpacing.md,
    super.key,
  });

  final Widget card;
  final Widget status;
  final double statusSpacing;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FittedBox(fit: BoxFit.scaleDown, child: card),
      const SizedBox(height: AppSpacing.base),
      Text(
        kPaymentLinkClaimCheckingHeading,
        textAlign: TextAlign.center,
        style: AppTypography.displayLarge.copyWith(
          color: context.colors.text.accent,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        kPaymentLinkClaimCheckingDescription,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
      SizedBox(height: statusSpacing),
      Semantics(liveRegion: true, child: status),
    ],
  );
}
