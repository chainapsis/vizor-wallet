import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/pay_activity_status_content.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

void main() {
  testWidgets('a Tx ID without an explorer link copies the full value', (
    tester,
  ) async {
    Future<ReviewListRow> pumpTxIdRow({VoidCallback? onOpenExplorer}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          home: AppTheme(
            data: AppThemeData.dark,
            child: SingleChildScrollView(
              child: PayActivityStatusContent(
                status: const PayActivityStatusPresentation(
                  phase: PayActivityStatusPhase.completed,
                  timestampText: '25 May, 13:30',
                  txIdText: 't1bufats...CvaAzeBo',
                  txIdCopyText: 't1bufatsuYMEZJ8watyV52rsNZ4CvaAzeBo',
                  convertedFromText: '4.0000 ZEC',
                  transactionFeeText: 'Not reported',
                ),
                amountAsset: SwapAsset.usdc,
                amountText: '100 USDC',
                amountFiatText: r'$100.00',
                recipientAddress: '0xrecipient-address',
                onShowFullAddress: () {},
                onOpenExplorer: onOpenExplorer,
              ),
            ),
          ),
        ),
      );
      return tester.widget<ReviewListRow>(
        find.ancestor(
          of: find.text('Tx ID'),
          matching: find.byType(ReviewListRow),
        ),
      );
    }

    final linked = await pumpTxIdRow(onOpenExplorer: () {});
    expect(linked.trailingIconName, AppIcons.arrowTopRight);
    expect(linked.copyText, isNull);

    final copied = await pumpTxIdRow();
    expect(copied.trailingIconName, isNull);
    expect(copied.copyText, 't1bufatsuYMEZJ8watyV52rsNZ4CvaAzeBo');
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Tx ID'),
          matching: find.byType(ReviewListRow),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is AppIcon && widget.name == AppIcons.copy,
        ),
      ),
      findsOneWidget,
    );
  });
}
