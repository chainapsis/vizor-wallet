import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_deposit_tokens_page_content.dart';

void main() {
  testWidgets(
    'desktop network guidance opens from its text and brightens on hover',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, navigator) =>
              AppTheme(data: AppThemeData.dark, child: navigator!),
          home: Center(
            child: SizedBox(
              width: 396,
              child: SwapDepositTokensPageContent(
                asset: SwapAsset.usdc,
                amountText: '150 USDC',
                depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
                expiresInLabel: '2hrs',
                onDeposited: () {},
              ),
            ),
          ),
        ),
      );

      final label = find.text('USDC on Ethereum only');
      final normalColor = tester.widget<Text>(label).style!.color;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(label));
      await tester.pump();
      expect(tester.widget<Text>(label).style!.color, isNot(normalColor));

      await tester.tap(label);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.textContaining('Recovery isn’t guaranteed'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
