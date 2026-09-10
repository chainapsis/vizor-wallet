@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_claim_account_sheet.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final size in [const Size(393, 852), const Size(320, 568)]) {
    testWidgets('only accounts scroll at $size, with the Claim button fixed', (
      tester,
    ) async {
      String? confirmedAccount;
      await _openSheet(
        tester,
        size: size,
        accountCount: 12,
        onConfirm: (uuid) async => confirmedAccount = uuid,
      );
      final button = find.byKey(
        const ValueKey('payment_link_claim_account_confirm'),
      );
      final headingTop = tester.getTopLeft(
        find.text('Choose receiving account'),
      );
      final amountTop = tester.getTopLeft(find.text('4.45 ZEC'));
      final buttonTop = tester.getTopLeft(button);
      final list = find.byKey(const ValueKey('payment_link_claim_accounts'));
      final last = find.byKey(
        const ValueKey('payment_link_claim_account_account-11'),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getBottomRight(button).dy, lessThan(size.height));
      await tester.scrollUntilVisible(
        last,
        160,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Choose receiving account')),
        headingTop,
      );
      expect(tester.getTopLeft(find.text('4.45 ZEC')), amountTop);
      expect(tester.getTopLeft(button), buttonTop);
      await tester.tap(last);
      await tester.pump();
      expect(confirmedAccount, isNull);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(confirmedAccount, 'account-11');
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openSheet(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  required int accountCount,
  required Future<void> Function(String) onConfirm,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    AppTheme(
      data: AppThemeData.dark,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPaymentLinkClaimAccountSheet(
                context: context,
                amountZatoshi: BigInt.from(445000000),
                accounts: [
                  for (var i = 0; i < accountCount; i++)
                    AccountInfo(
                      uuid: 'account-$i',
                      name: 'Account $i',
                      order: i,
                    ),
                ],
                activeAccountUuid: 'account-0',
                onConfirm: onConfirm,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
