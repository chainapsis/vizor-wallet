import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/payment_request_intake.dart';
import '../../../core/navigation/payment_uri_drain_policy.dart';
import '../../../core/payments/cross_chain_payment_request.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/zcash/zip321_payment_request.dart';

const paymentRequestRefundAddressMessage =
    'Enter or scan a plain refund address. A payment request cannot be used here.';

class PaymentRequestInputNotice extends StatelessWidget {
  const PaymentRequestInputNotice({required this.onReview, super.key});

  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Payment request detected. Review the network, token, and amount before continuing.',
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
      const SizedBox(height: AppSpacing.s),
      AppButton(
        key: const ValueKey('review_pasted_payment_request'),
        expand: true,
        constrainContent: true,
        onPressed: onReview,
        child: const Text(
          'Review payment request',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// Accepts the whole request into the common card flow. A failed request stays
/// a request: callers must never fall through to extracting just its address.
Future<bool> reviewPaymentRequestFromInput(WidgetRef ref, String raw) async {
  if (!isPaymentRequestUri(raw)) return false;
  FocusScope.of(ref.context).unfocus();
  try {
    return await intakePaymentRequest(ref, raw);
  } catch (error) {
    if (!ref.context.mounted) return false;
    final message = switch (error) {
      CrossChainPaymentParseException() => error.toString(),
      Zip321ParseException() ||
      Zip321UnsupportedRequestException() => paymentUriRejectionMessage(error),
      _ => 'This payment request could not be read.',
    };
    showAppToast(
      ref.context,
      message,
      iconName: AppIcons.warning,
      tone: AppToastTone.destructive,
    );
    return false;
  }
}
