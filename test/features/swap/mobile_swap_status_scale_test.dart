@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_status_content.dart';

import '../../support/app_test_fonts.dart';
import '../../support/scaled_row_text_checks.dart';

/// The swap status header amounts, its Full address action and the progress
/// step titles keep their full text on a narrow screen at large text sizes.
void main() {
  setUpAll(loadAppTestFonts);
  final ltc = SwapAsset.live(
    assetId: 'nep141:ltc.omft.near',
    symbol: 'LTC',
    blockchain: 'ltc',
    decimals: 8,
  );
  const pay = '11.31900656 LTC';
  const receive = '0.55495667 ZEC';
  const stepTitles = ['LTC sent', 'Deposit confirmation', 'Swap', 'Send ZEC'];

  for (final width in [320.0, 393.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('header and steps keep full text width=$width scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final presentation = SwapActivityStatusPresentation(
          title: 'Swap in progress',
          payAsset: ltc,
          receiveAsset: SwapAsset.zec,
          payFiatText: '',
          receiveFiatText: '',
          payAmountText: pay,
          receiveAmountText: receive,
          badgeKind: SwapStatusBadgeKind.liveQuote,
          progressIndex: 0,
          steps: [
            for (final title in stepTitles)
              SwapStatusStepData(
                title: title,
                state: SwapStatusStepState.pending,
              ),
          ],
          details: const [],
          showTabs: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: appSupportedLocales(),
            builder: (context, child) => AppTheme(
              data: AppThemeData.light,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                // The page's side margins, as the activity detail page sets.
                padding: const EdgeInsets.symmetric(
                  horizontal: kMobilePageMargin,
                ),
                child: MobileSwapStatusContent(
                  presentation: presentation,
                  payHeaderRow: MobileSwapReviewHeaderRow(
                    label: presentation.payLabel,
                    amountText: pay,
                    asset: ltc,
                    bottomText: 'Refund to: ltc1q … c8n4q',
                  ),
                  receiveHeaderRow: MobileSwapReviewHeaderRow(
                    label: presentation.receiveLabel,
                    amountText: receive,
                    asset: SwapAsset.zec,
                    bottomText: 'To: u1abc … 8b7a6',
                    fullAddress: 'u1abcrecipient8b7a6',
                  ),
                  activeTab: SwapStatusTab.progress,
                  detailsExpanded: false,
                  onTabChanged: (_) {},
                  onToggleDetails: () {},
                ),
              ),
            ),
          ),
        );
        // The active step's loader keeps animating, so pump instead of settle.
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final text in [pay, receive, ...stepTitles]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(text),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: text);
        }
        expectUnclippedRowText(
          tester,
          find.text('Full address'),
          tester.getRect(
            find.byKey(const ValueKey('mobile_swap_full_address')),
          ),
        );
      });
    }
  }
}
