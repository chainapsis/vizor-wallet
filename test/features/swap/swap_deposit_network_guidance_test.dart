import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_deposit_tokens_page_content.dart';

void main() {
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
}
