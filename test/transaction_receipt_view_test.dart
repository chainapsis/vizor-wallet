import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/send/widgets/transaction_receipt_view.dart';

void main() {
  test('block data rejects competing title trailing actions', () {
    expect(
      () => TransactionReceiptBlockData(
        title: 'Message',
        onCopy: _noop,
        titleTrailing: const SizedBox.shrink(),
        child: const Text('memo'),
      ),
      throwsAssertionError,
    );
  });

  testWidgets('pins transaction hash action to the bottom when requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      _receiptHarness(
        const SizedBox(
          width: 400,
          height: 500,
          child: TransactionReceiptView(
            phase: TransactionReceiptPhase.succeeded,
            amountText: '15.12 zec',
            primaryBlock: TransactionReceiptBlockData(
              title: 'To',
              child: Text('u1testaddress'),
            ),
            dateText: 'April 20, 2026 13:50',
            feeText: '0.00012 ZEC',
            pinActionsToBottom: true,
            onTransactionHashPressed: _noop,
          ),
        ),
      ),
    );

    final button = find.widgetWithText(AppButton, 'Transaction Hash');

    expect(button, findsOneWidget);
    expect(tester.getTopLeft(button).dy, moreOrLessEquals(456, epsilon: 0.1));
  });

  testWidgets('labels tx fee and scales down long amount text', (tester) async {
    const longAmount = '123456789.12345678 ZEC';

    await tester.pumpWidget(
      _receiptHarness(
        const TransactionReceiptView(
          phase: TransactionReceiptPhase.succeeded,
          amountText: longAmount,
          primaryBlock: TransactionReceiptBlockData(
            title: 'To',
            child: Text('u1testaddress'),
          ),
          dateText: 'April 20, 2026 13:50',
          feeText: '0.00012 ZEC',
          onTransactionHashPressed: _noop,
        ),
      ),
    );

    expect(find.text('Tx Fee'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text(longAmount),
        matching: find.byWidgetPredicate(
          (widget) => widget is FittedBox && widget.fit == BoxFit.scaleDown,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('message block toggles between collapsed and expanded text', (
    tester,
  ) async {
    var expanded = false;

    await tester.pumpWidget(
      _receiptHarness(
        StatefulBuilder(
          builder: (context, setState) {
            return TransactionReceiptView(
              phase: TransactionReceiptPhase.succeeded,
              amountText: '15.12 zec',
              primaryBlock: const TransactionReceiptBlockData(
                title: 'To',
                child: Text('u1testaddress'),
              ),
              extraBlocks: [
                TransactionReceiptBlockData(
                  title: 'Message',
                  titleTrailing: TransactionReceiptMessageToggle(
                    expanded: expanded,
                    onTap: () => setState(() {
                      expanded = !expanded;
                    }),
                  ),
                  child: TransactionReceiptMessageText(
                    memo: _longMemo,
                    expanded: expanded,
                  ),
                ),
              ],
              dateText: 'April 20, 2026 13:50',
              feeText: '0.00012 ZEC',
              onTransactionHashPressed: _noop,
            );
          },
        ),
      ),
    );

    expect(find.text('Expand'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_longMemo)).maxLines, 3);

    await tester.tap(find.text('Expand'));
    await tester.pumpAndSettle();

    expect(find.text('Collapse'), findsOneWidget);
    expect(tester.widget<Text>(find.text(_longMemo)).maxLines, isNull);
  });

  testWidgets('address block shows the full wrapped address without a memo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _receiptHarness(
        const TransactionReceiptAddressText(
          address: _longAddress,
          highlightEdges: true,
        ),
      ),
    );

    final addressText = tester.widget<RichText>(find.byType(RichText));

    expect(addressText.text.toPlainText(), _longAddress);
    expect(addressText.text.toPlainText(), isNot(contains('...')));
  });

  testWidgets('address block shortens to two lines when memo is present', (
    tester,
  ) async {
    await tester.pumpWidget(
      _receiptHarness(
        const TransactionReceiptAddressText(
          address: _longAddress,
          highlightEdges: true,
          compact: true,
        ),
      ),
    );

    final addressText = tester.widget<RichText>(find.byType(RichText));
    final plainText = addressText.text.toPlainText();

    expect(plainText, startsWith('u1tvg4'));
    expect(plainText, contains('\n... '));
    expect(plainText, endsWith('n8fh5'));
    expect(plainText, isNot(_longAddress));
  });
}

Widget _receiptHarness(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      // Widget tests use the wide Ahem font; this keeps fixed Figma-width
      // receipt controls from reporting test-only overflows.
      data: const MediaQueryData(textScaler: TextScaler.linear(0.7)),
      child: AppTheme(
        data: AppThemeData.light,
        child: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

void _noop() {}

const _longMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs. Launched in October 2016, Zcash was '
    'developed by cryptographers at Johns Hopkins University and MIT and '
    'derived its code from bitcoin.';

const _longAddress =
    'u1tvg4akwn3gk64hhq6dfe05psw8zr0x4tspgwhkgy8x9yhy6djxjhrawuee0ecuzwm6zcwr8uewd366wefxxwp6tr8q8462lcdgvanwessx3sz87nm6c5mue444uzdumlecth9ncr4yavgtdqwd249nsfz5j3eds7qfhzek6scgcn8fh5';
