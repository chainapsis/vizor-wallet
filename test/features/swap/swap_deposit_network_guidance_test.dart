import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_deposit_tokens_page_content.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  // Real app fonts, so wrapping matches what users see.
  setUpAll(loadFigmaCompareFonts);

  for (final mobile in [false, true]) {
    testWidgets('deposit guidance shows token and network (mobile: $mobile)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, navigator) =>
              AppTheme(data: AppThemeData.dark, child: navigator!),
          home: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: mobile ? 361 : 420,
                child: SwapDepositTokensPageContent(
                  asset: SwapAsset.usdc,
                  amountText: '150 USDC',
                  depositAddress: '0x1234567890',
                  expiresInLabel: '14:59',
                  mobile: mobile,
                  onDeposited: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final guidance = find.byKey(
        const ValueKey('swap_deposit_network_guidance'),
      );
      expect(guidance, findsOneWidget);
      expect(find.text('Send only USDC on Ethereum'), findsOneWidget);
      expect(tester.getSize(guidance).height, AppSpacing.lg);
      expect(
        find.byKey(const ValueKey('swap_deposit_network_help')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a long network name wraps instead of truncating', (
    tester,
  ) async {
    final asset = SwapAsset.live(
      assetId: 'nep141:bsc-usdt',
      symbol: 'USDT',
      blockchain: 'bsc',
      decimals: 18,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, navigator) => AppTheme(
          data: AppThemeData.dark,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: navigator!,
          ),
        ),
        home: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: 288,
              child: SwapDepositTokensPageContent(
                asset: asset,
                amountText: '150 USDT',
                depositAddress: '0x1234567890',
                expiresInLabel: '14:59',
                mobile: true,
                onDeposited: () {},
              ),
            ),
          ),
        ),
      ),
    );

    const warning = 'Send only USDT on Binance Smart Chain';
    final paragraph = tester.renderObject<RenderParagraph>(find.text(warning));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('swap_deposit_network_guidance')))
          .height,
      greaterThan(AppSpacing.lg),
    );
    expect(tester.takeException(), isNull);
  });
}
