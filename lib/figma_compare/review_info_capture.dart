import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/swap/domain/swap_asset.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_status_content.dart';

const _recipient = '0x1235112351123511235112351123511235176123';

/// The mobile swap and Pay `Review Info` headers, which have no standalone
/// Widgetbook fixture, in one mobile-width page.
Widget buildMobileReviewInfoHeadersCapture(BuildContext context) {
  final colors = context.colors;
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
          const MobileSwapReviewHeader(
            pay: MobileSwapReviewHeaderRow(
              label: "You're paying",
              amountText: '1.12 ZEC',
              asset: SwapAsset.zec,
              bottomText: r'$250.12',
            ),
            receive: MobileSwapReviewHeaderRow(
              label: "You're receiving",
              amountText: '100.12 USDC',
              asset: SwapAsset.usdc,
              bottomText: 'To: 0x1125 ... 8712',
              fullAddress: _recipient,
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
