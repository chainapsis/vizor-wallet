import 'package:flutter/widgets.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../src/features/payment_links/widgets/payment_link_qr_share_card.dart';
import '../widgetbook/payment_link_amount_preview.dart';
import '../widgetbook/payment_link_mobile_use_cases.dart';
import '../widgetbook/payment_link_use_cases.dart';

Widget buildRogueCatGiftCardAmountCapture(BuildContext context) {
  const content = PaymentLinkAmountPreview(
    initialAmount: '4.45',
    initialArtwork: PaymentLinkCardArtwork.rogueCat,
  );
  return kAppFormFactor == AppFormFactor.mobile
      ? buildMobilePaymentLinkPreviewFrame(content)
      : const PaymentLinkDesktopPreview(
          state: PaymentLinkPreviewState.createAmount,
          content: content,
        );
}

Widget buildRogueCatGiftCardQrCapture(BuildContext context) {
  final link = VizorPaymentLink(
    network: 'main',
    address: 'u1previewgiftcardaddress',
    amountZatoshi: BigInt.from(445000000),
    mnemonic: List.filled(24, 'abandon').join(' '),
    birthdayHeight: 3000000,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 6),
    presentation: const PaymentLinkPresentation(artworkId: 'rogueCat'),
  );
  return Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: PaymentLinkQrShareCard(
        artwork: PaymentLinkCardArtwork.rogueCat,
        qrData: link.toUri().toString(),
      ),
    ),
  );
}
