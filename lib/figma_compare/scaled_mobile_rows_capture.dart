import 'package:flutter/material.dart';

import '../src/core/l10n/l10n.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/pay/widgets/mobile/mobile_pay_add_contact_card.dart';
import '../src/features/swap/models/swap_activity_status_mapper.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/models/swap_status_presentation.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_status_content.dart';

Widget buildMobileContactChainCapture(BuildContext context) =>
    const MobileContactChainCapture();

Widget buildMobileLongContactChainCapture(BuildContext context) =>
    const MobileContactChainCapture(
      network: AddressBookNetwork.binanceSmartChain,
    );

/// The real contact editor and sheet frame, with a deterministic avatar.
class MobileContactChainCapture extends StatelessWidget {
  const MobileContactChainCapture({
    this.network = AddressBookNetwork.ethereum,
    super.key,
  });
  final AddressBookNetwork network;

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        resizeToAvoidBottomInset: false,
        body: MobileModalOverlay(
          background: ColoredBox(color: context.colors.background.window),
          child: MobilePayAddContactCard(
            network: network,
            address: '0x1111111111111111111111111111111111111111',
            profilePictureIdGenerator: () => 'pfp-07',
            onCancel: () {},
            onSave: (_, _) async {},
          ),
        ),
      ),
    ),
  );
}

Widget buildMobileSwapStatusRowCapture(BuildContext context) =>
    const MobileStatusRowCapture();
Widget buildMobileWarningStatusRowCapture(BuildContext context) =>
    const MobileStatusRowCapture(badgeKind: SwapStatusBadgeKind.warning);
Widget buildMobilePayStatusRowCapture(BuildContext context) =>
    const MobileStatusRowCapture(paymentMode: true);

/// Real Swap/Pay status content, independent of storage, Rust and the network.
class MobileStatusRowCapture extends StatelessWidget {
  const MobileStatusRowCapture({
    this.paymentMode = false,
    this.badgeKind = SwapStatusBadgeKind.completed,
    super.key,
  });
  final bool paymentMode;
  final SwapStatusBadgeKind badgeKind;

  PayActivityStatusPhase get _payPhase => switch (badgeKind) {
    SwapStatusBadgeKind.completed => PayActivityStatusPhase.completed,
    SwapStatusBadgeKind.refunded => PayActivityStatusPhase.refunded,
    SwapStatusBadgeKind.failed => PayActivityStatusPhase.failed,
    _ => PayActivityStatusPhase.inProgress,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(kMobilePageMargin),
      child: MobileSwapStatusContent(
        presentation: SwapActivityStatusPresentation(
          title: '',
          payAsset: SwapAsset.zec,
          receiveAsset: SwapAsset.usdc,
          payFiatText: r'$250.12',
          receiveFiatText: r'$250.12',
          payAmountText: '1.12 ZEC',
          receiveAmountText: '100.12 USDC',
          badgeKind: badgeKind,
          progressIndex: 0,
          steps: const [],
          details: const [],
          paymentMode: paymentMode,
          payStatus: paymentMode
              ? PayActivityStatusPresentation(
                  phase: _payPhase,
                  timestampText: 'Nov 17, 2026',
                  txIdText: '0x1234...5678',
                  convertedFromText: '1.12 ZEC',
                  transactionFeeText: '0.01 ZEC',
                )
              : null,
          showTabs: false,
        ),
        payHeaderRow: MobileSwapReviewHeaderRow(
          label: context.l10n.commonYourePaying,
          amountText: '1.12 ZEC',
          asset: SwapAsset.zec,
          bottomText: r'$250.12',
        ),
        receiveHeaderRow: MobileSwapReviewHeaderRow(
          label: context.l10n.commonYoureReceiving,
          amountText: '100.12 USDC',
          asset: SwapAsset.usdc,
          bottomText: r'$250.12',
        ),
        paymentHeader: paymentMode
            ? MobilePayStatusHeader(
                label: payActivityStatusAmountLabel(context.l10n, _payPhase),
                asset: SwapAsset.usdc,
                amountText: '100.12 USDC',
                fiatText: r'$250.12',
                recipientAddress: '0x1111111111111111111111111111111111111111',
                recipientName: 'Mike',
                recipientProfilePictureId: 'pfp-08',
              )
            : null,
        activeTab: SwapStatusTab.details,
        detailsExpanded: true,
        onTabChanged: (_) {},
        onToggleDetails: () {},
      ),
    ),
  );
}
