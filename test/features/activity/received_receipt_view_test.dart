import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/review_info_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/src/features/activity/widgets/received_receipt_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_review_layout.dart';

const _transparentFromAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

const _transparentReceivingAddress = 't1Z9N3oVYrYDpnbqDcXJpuLrGpcSLDgHXyo';

const _shieldedReceivingAddress =
    'u1j9g9dnk7f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190592';

void main() {
  testWidgets('renders the full received receipt', (tester) async {
    await _pump(
      tester,
      ReceivedReceiptView(
        fromRecipient: const SendReviewAddressRecipient(
          address: _transparentFromAddress,
        ),
        isShieldedSource: false,
        amountText: '120 ZEC',
        receivingAddress: _transparentReceivingAddress,
        memoText: 'Zcash is a privacy-focused ...',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text('Received successfully'), findsOneWidget);
    expect(find.byType(ReviewInfoRow), findsNWidgets(2));
    expect(find.text('From'), findsOneWidget);
    // Canonical 7+6 truncation for both the sender headline and the
    // receiving sub-line.
    expect(find.text('t1PV7ny ... GVSpEX'), findsOneWidget);
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('Show full address'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('120 ZEC'), findsOneWidget);
    expect(find.text('t1Z9N3o ... DgHXyo'), findsOneWidget);

    expect(find.byType(ReviewWrapCard), findsOneWidget);
    expect(find.byType(ReviewWrapDivider), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Zcash is a privacy-focused ...'), findsOneWidget);
    expect(find.text('25 May, 13:30'), findsOneWidget);
    expect(find.text('0123123124512512'), findsOneWidget);
    expect(find.text('Network fee'), findsOneWidget);
    expect(find.text('0.012 ZEC'), findsOneWidget);

    final statusText = tester.widget<Text>(find.text('Completed'));
    expect(
      statusText.style?.color,
      AppThemeData.light.colors.text.positiveStrong,
    );
  });

  testWidgets('groups detail rows tightly with the 16px card gap around', (
    tester,
  ) async {
    await _pump(
      tester,
      ReceivedReceiptView(
        fromRecipient: const SendReviewAddressRecipient(
          address: _transparentFromAddress,
        ),
        isShieldedSource: false,
        amountText: '120 ZEC',
        memoText: 'Memo',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    final statusTop = tester.getTopLeft(find.text('Status')).dy;
    final messageTop = tester.getTopLeft(find.text('Message')).dy;
    final timestampTop = tester.getTopLeft(find.text('Timestamp')).dy;
    final txIdTop = tester.getTopLeft(find.text('Tx ID')).dy;

    // Status is its own list group: row height + 16px card gap to Message.
    expect(messageTop - statusTop, ReviewListRow.height + AppSpacing.sm);
    // Message / Timestamp / Tx ID share one group: rows stack with no gap.
    expect(timestampTop - messageTop, ReviewListRow.height);
    expect(txIdTop - timestampTop, ReviewListRow.height);
  });

  testWidgets('matches the Figma received vertical offsets in pixels', (
    tester,
  ) async {
    await _pump(
      tester,
      ReceivedReceiptView(
        fromRecipient: const SendReviewAddressRecipient(
          address: _transparentFromAddress,
        ),
        isShieldedSource: false,
        amountText: '120 ZEC',
        receivingAddress: _transparentReceivingAddress,
        memoText: 'Memo',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    final titleTop = tester.getTopLeft(find.text('Received successfully')).dy;
    final fromTop = tester.getTopLeft(find.byType(ReviewInfoRow).at(0)).dy;
    final amountTop = tester.getTopLeft(find.byType(ReviewInfoRow).at(1)).dy;
    final cardTop = tester.getTopLeft(find.byType(ReviewWrapCard)).dy;

    expect(fromTop - titleTop, 56);
    expect(amountTop - titleTop, 170);
    expect(cardTop - titleTop, 292);
  });

  testWidgets('omits the message row when absent', (tester) async {
    await _pump(
      tester,
      ReceivedReceiptView(
        unknownFromKind: ReceivedReceiptUnknownFromKind.shieldedSender,
        isShieldedSource: true,
        amountText: '120 ZEC',
        receivingAddress: _shieldedReceivingAddress,
        isShieldedReceivingAddress: true,
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text('Message'), findsNothing);
    expect(find.text('Shielded sender'), findsOneWidget);
    expect(find.text('Unknown sender'), findsNothing);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.textContaining(' ... '), findsOneWidget);
  });

  testWidgets('renders an unknown source row without a pool badge', (
    tester,
  ) async {
    await _pump(
      tester,
      const ReceivedReceiptView(
        unknownFromKind: ReceivedReceiptUnknownFromKind.unknownSender,
        amountText: '120 ZEC',
        receivingAddress: _transparentReceivingAddress,
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
      ),
    );

    expect(find.text('From'), findsOneWidget);
    expect(find.text('Unknown sender'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.text('Shielded'), findsNothing);
    expect(find.text('Show full address'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.arrowDown,
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders a known sender as a contact row', (tester) async {
    await _pump(
      tester,
      ReceivedReceiptView(
        fromRecipient: const SendReviewContactRecipient(
          address: _transparentFromAddress,
          name: 'Mike',
          profilePictureId: 'pfp-03',
        ),
        isShieldedSource: false,
        amountText: '120 ZEC',
        receivingAddress: _shieldedReceivingAddress,
        isShieldedReceivingAddress: true,
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
      ),
    );

    expect(find.text('From'), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('t1PV7ny ... GVSpEX'), findsOneWidget);
    expect(find.text('Show full address'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
  });

  testWidgets('shows the loader status row while receiving', (tester) async {
    await _pump(
      tester,
      const ReceivedReceiptView(
        status: ReceivedReceiptStatus.inProgress,
        amountText: '120 ZEC',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
      ),
    );

    expect(find.text('Receive in progress...'), findsOneWidget);
    expect(find.text('Received successfully'), findsNothing);
    expect(find.text('In progress'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.loader,
      ),
      findsOneWidget,
    );

    final statusText = tester.widget<Text>(find.text('In progress'));
    expect(statusText.style?.color, AppThemeData.light.colors.text.secondary);
  });

  testWidgets('shows the failed status row when expired', (tester) async {
    await _pump(
      tester,
      const ReceivedReceiptView(
        status: ReceivedReceiptStatus.failed,
        amountText: '120 ZEC',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
      ),
    );

    expect(find.text('Receive failed'), findsOneWidget);
    final statusText = tester.widget<Text>(find.text('Failed'));
    expect(statusText.style?.color, AppThemeData.light.colors.text.destructive);
  });

  testWidgets('hides the tx fee row and divider when feeText is null', (
    tester,
  ) async {
    await _pump(
      tester,
      const ReceivedReceiptView(
        amountText: '120 ZEC',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
      ),
    );

    expect(find.text('Network fee'), findsNothing);
    expect(find.byType(ReviewWrapDivider), findsNothing);
  });

  testWidgets('hides the from row and connector when source is null', (
    tester,
  ) async {
    await _pump(
      tester,
      const ReceivedReceiptView(
        amountText: '120 ZEC',
        receivingAddress: _transparentReceivingAddress,
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
      ),
    );

    expect(find.text('From'), findsNothing);
    expect(find.text('Show full address'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.arrowDown,
      ),
      findsNothing,
    );
    // Only the Amount row remains, still carrying the receiving sub-line.
    expect(find.byType(ReviewInfoRow), findsOneWidget);
    expect(find.text('t1Z9N3o ... DgHXyo'), findsOneWidget);
  });

  testWidgets('fires the affordance callbacks', (tester) async {
    var fullAddress = 0;
    var message = 0;
    var txId = 0;
    var feeHelp = 0;
    await _pump(
      tester,
      ReceivedReceiptView(
        fromRecipient: const SendReviewAddressRecipient(
          address: _transparentFromAddress,
        ),
        isShieldedSource: false,
        amountText: '120 ZEC',
        memoText: 'Memo',
        timestampText: '25 May, 13:30',
        txIdText: '0123123124512512',
        feeText: '0.012 ZEC',
        onShowFullAddress: () => fullAddress++,
        onExpandMemo: () => message++,
        onTxIdPressed: () => txId++,
        onFeeHelpPressed: () => feeHelp++,
      ),
    );

    await tester.tap(find.text('Show full address'));
    await tester.tap(find.text('Memo'));
    await tester.tap(find.text('0123123124512512'));
    await tester.tap(find.text('0.012 ZEC'));
    await tester.pump();

    expect(fullAddress, 1);
    expect(message, 1);
    expect(txId, 1);
    expect(feeHelp, 1);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: AppWindowSizing.contentAreaMaxWidth,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
