@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp, Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_detail_tooltips.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_status_content.dart';

// Detail-row behaviour must follow SwapStatusDetailRowData.kind, not the
// localized label text, so Korean rows behave like English ones.
void main() {
  const address = '0x9aDFd2310B3FA54A8718445c82Eb2ef1c19Ef064';
  final ko = lookupAppLocalizations(const Locale('ko'));

  testWidgets('Korean labels keep fee ordering, tooltip and compaction', (
    tester,
  ) async {
    final rows = [
      SwapStatusDetailRowData(
        label: ko.swapActivityDetailTotalFees,
        kind: SwapStatusDetailKind.totalFees,
        value: '~0.25 USDC',
        help: true,
      ),
      SwapStatusDetailRowData(
        label: ko.swapActivityDetailRefundAddress('USDC'),
        kind: SwapStatusDetailKind.refundAddress,
        value: address,
        copyable: true,
        copyText: address,
      ),
      SwapStatusDetailRowData(
        label: ko.swapActivityDetailRecipient('USDC'),
        kind: SwapStatusDetailKind.recipient,
        value: address,
        copyable: true,
        copyText: address,
      ),
      SwapStatusDetailRowData(
        label: ko.swapActivityDetailTimestamp,
        kind: SwapStatusDetailKind.timestamp,
        value: 'May 20, 2026 13:20',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: appSupportedLocales(preview: true),
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, navigator) =>
            AppTheme(data: AppThemeData.light, child: navigator!),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            disableAnimations: true,
          ),
          child: SingleChildScrollView(
            child: MobileSwapStatusContent(
              presentation: SwapActivityStatusPresentation(
                title: '',
                payAsset: SwapAsset.zec,
                receiveAsset: SwapAsset.usdc,
                payFiatText: '',
                receiveFiatText: '',
                payAmountText: '1.12 ZEC',
                receiveAmountText: '100.12 USDC',
                badgeKind: SwapStatusBadgeKind.completed,
                progressIndex: 0,
                steps: const [],
                details: rows,
                showTabs: false,
              ),
              payHeaderRow: MobileSwapReviewHeaderRow(
                label: 'pay',
                amountText: '1.12 ZEC',
                asset: SwapAsset.zec,
                bottomText: '',
              ),
              receiveHeaderRow: MobileSwapReviewHeaderRow(
                label: 'receive',
                amountText: '100.12 USDC',
                asset: SwapAsset.usdc,
                bottomText: '',
              ),
              activeTab: SwapStatusTab.details,
              detailsExpanded: true,
              onTabChanged: (_) {},
              onToggleDetails: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The mobile relabel shows the localized swap-fee label for total fees.
    expect(find.text(ko.swapActivityDetailTotalFees), findsNothing);
    final feeFinder = find.text(ko.swapActivityDetailSwapFee);
    expect(feeFinder, findsOneWidget);
    // Success details hide the recipient row by kind.
    expect(find.text(ko.swapActivityDetailRecipient('USDC')), findsNothing);
    // The fee row sorts after the other rows.
    final feeY = tester.getTopLeft(feeFinder).dy;
    expect(
      feeY,
      greaterThan(
        tester.getTopLeft(find.text(ko.swapActivityDetailTimestamp)).dy,
      ),
    );
    expect(
      feeY,
      greaterThan(
        tester
            .getTopLeft(find.text(ko.swapActivityDetailRefundAddress('USDC')))
            .dy,
      ),
    );
    // Address values are compacted by kind.
    expect(find.text(address), findsNothing);
    expect(find.text('0x9aDF…Ef064'), findsOneWidget);
    // The fee tooltip is the Korean swap-fee tooltip.
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == swapFeeTooltip(ko),
      ),
      findsOneWidget,
    );
  });
}
