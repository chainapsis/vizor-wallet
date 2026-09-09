import 'package:flutter/widgets.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Presentation data supplied by the owner after a feasible amount is known.
/// Produced by the Ledger-aware quote after a capacity-limited proposal is verified.
class SendAmountSuggestion {
  const SendAmountSuggestion({required this.amountZatoshi});
  final BigInt amountZatoshi;

  String get amountText => formatZecAmount(amountZatoshi);
  bool appliesTo(BigInt? amount) => amount != null && amount > amountZatoshi;
}

class SendAmountSuggestionReviewHint extends StatelessWidget {
  const SendAmountSuggestionReviewHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('send_amount_adjustment_hint'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppIcon(
          AppIcons.warningCircle,
          size: AppIconSize.medium,
          color: context.colors.icon.warning,
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            'Ledger requires a smaller transfer.',
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}
