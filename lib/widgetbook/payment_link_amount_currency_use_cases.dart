import 'package:flutter/widgets.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/features/payment_links/widgets/payment_link_amount_card.dart';
import 'payment_link_amount_preview.dart';
import 'payment_link_mobile_use_cases.dart';
import 'payment_link_use_cases.dart';

Widget buildGiftCardZecAmountUseCase(BuildContext context) =>
    _frame(const PaymentLinkAmountPreview());

Widget buildGiftCardUsdAmountUseCase(BuildContext context) => _frame(
  const PaymentLinkAmountPreview(
    initialCurrency: PaymentLinkAmountCurrency.usd,
  ),
);

Widget buildGiftCardEmptyAmountUseCase(BuildContext context) =>
    _frame(const PaymentLinkAmountPreview(initialAmount: ''));

Widget buildGiftCardAmountPriceUnavailableUseCase(BuildContext context) =>
    _frame(const PaymentLinkAmountPreview(priceAvailable: false));

Widget buildGiftCardAmountPriceLoadingUseCase(BuildContext context) => _frame(
  const PaymentLinkAmountPreview(priceAvailable: false, priceLoading: true),
);

Widget _frame(Widget content) => kAppFormFactor == AppFormFactor.mobile
    ? buildMobilePaymentLinkPreviewFrame(content)
    : PaymentLinkDesktopPreview(
        state: PaymentLinkPreviewState.createAmount,
        content: content,
      );
