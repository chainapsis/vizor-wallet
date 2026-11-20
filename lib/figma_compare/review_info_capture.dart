import 'package:flutter/widgets.dart';

import '../src/core/formatting/address_display.dart';
import '../src/core/l10n/l10n.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/address_line_text.dart';
import '../src/features/swap/domain/swap_asset.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_status_content.dart';
import '../src/features/swap/widgets/one_time_address_label.dart';

const _recipient = '0x1235112351123511235112351123511235176123';
const _walletAddress =
    'u1q6g2k3r4s5t6u7v8w9x0yzaabbccddeeff00112233445566778899';

/// The mobile swap and Pay `Review Info` headers, which have no standalone
/// Widgetbook fixture, in one mobile-width page. The address lines use the
/// selected locale, so a capture shows how they fit in each language.
Widget buildMobileReviewInfoHeadersCapture(BuildContext context) {
  final colors = context.colors;
  final l10n = context.l10n;
  Widget caption(String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      text,
      style: AppTypography.labelSmall.copyWith(color: colors.text.muted),
    ),
  );
  return ColoredBox(
    color: colors.background.window,
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          caption('Swap review / status'),
          MobileSwapReviewHeader(
            pay: const MobileSwapReviewHeaderRow(
              label: "You're paying",
              amountText: '1.12 ZEC',
              asset: SwapAsset.zec,
              bottomText: r'$250.12',
            ),
            receive: MobileSwapReviewHeaderRow(
              label: "You're receiving",
              amountText: '100.12 USDC',
              asset: SwapAsset.usdc,
              bottomAddress: AddressLine.inTemplate(
                l10n.swapReviewToAddress,
                address: truncatedAddress(_recipient),
              ),
              fullAddress: _recipient,
            ),
          ),
          caption('Swap review, saved contact'),
          MobileSwapReviewHeader(
            pay: const MobileSwapReviewHeaderRow(
              label: "You're paying",
              amountText: '1.12 ZEC',
              asset: SwapAsset.zec,
              bottomText: r'$250.12',
            ),
            receive: MobileSwapReviewHeaderRow(
              label: "You're receiving",
              amountText: '100.12 USDC',
              asset: SwapAsset.usdc,
              bottomAddress: AddressLine.inTemplate(
                l10n.swapReviewToAddress,
                address: truncatedAddress(_recipient),
                label: 'Treasury',
              ),
              fullAddress: _recipient,
            ),
          ),
          caption('Swap status, one-time payout address'),
          MobileSwapReviewHeader(
            pay: const MobileSwapReviewHeaderRow(
              label: 'You paid',
              amountText: '100.12 USDC',
              asset: SwapAsset.usdc,
              bottomText: r'$100.12',
            ),
            receive: MobileSwapReviewHeaderRow(
              label: 'You received',
              amountText: '1.12 ZEC',
              asset: SwapAsset.zec,
              bottomAddress: AddressLine.inTemplate(
                l10n.swapPanelRecipientTo,
                address: truncatedAddress(_walletAddress),
              ),
              oneTimeAddress: OneTimeAddressRole.payout,
            ),
          ),
          caption('Pay status'),
          const MobilePayStatusHeader(
            asset: SwapAsset.usdc,
            amountText: '990 USDC',
            fiatText: r'$250.12',
            recipientAddress: _recipient,
            recipientName: 'Mike',
            recipientProfilePictureId: 'pfp-08',
          ),
        ],
      ),
    ),
  );
}
