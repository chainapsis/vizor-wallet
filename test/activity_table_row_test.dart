import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_table.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  testWidgets('transaction rows are keyboard activatable but sync row is not', (
    tester,
  ) async {
    var txActivations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: ActivityTable(
            rows: [
              _row(title: 'Wallet Synced'),
              _row(
                title: 'Sent',
                subtitle: 'Shielded',
                onTap: () {
                  txActivations += 1;
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(_primaryFocusContainsText('Wallet Synced'), isFalse);
    expect(_primaryFocusContainsText('Sent'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(txActivations, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(txActivations, 2);
  });

  testWidgets('activity rows render manipulated zatoshi values', (
    tester,
  ) async {
    late final List<ActivityRowData> rows;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              rows = buildActivityRows(
                context: context,
                sync: SyncState(totalBalance: BigInt.from(10000)),
                transactions: [
                  _tx(
                    txidHex: 'received',
                    kind: 'received',
                    amount: BigInt.from(123450000),
                  ),
                  _tx(
                    txidHex: 'sent',
                    kind: 'sent',
                    amount: BigInt.from(100000000),
                  ),
                  _tx(
                    txidHex: 'shielded',
                    kind: 'shielded',
                    amount: BigInt.from(10000),
                  ),
                ],
              );
              return ActivityTable(rows: rows);
            },
          ),
        ),
      ),
    );

    expect(rows[0].amountText, '0.0001 ZEC');
    expect(rows[1].amountText, '+1.23 ZEC');
    expect(rows[2].amountText, '-1.00 ZEC');
    expect(rows[3].amountText, '0.0001 ZEC');
    expect(find.text('0.0001 ZEC'), findsNWidgets(2));
    expect(find.text('+1.23 ZEC'), findsOneWidget);
    expect(find.text('-1.00 ZEC'), findsOneWidget);
  });
}

rust_sync.TransactionInfo _tx({
  required String txidHex,
  required String kind,
  required BigInt amount,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.one,
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: kind,
    displayAmount: amount,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

ActivityRowData _row({
  required String title,
  String? subtitle,
  VoidCallback? onTap,
}) {
  return ActivityRowData(
    title: title,
    leadingIconName: AppIcons.sync,
    leadingBackgroundColor: const Color(0xFFE1E1E1),
    leadingIconColor: const Color(0xFF4D5252),
    subtitle: subtitle,
    amountText: '1.00 ZEC',
    statusText: 'Completed',
    timestampText: 'Today, 13:11',
    onTap: onTap,
  );
}

bool _primaryFocusContainsText(String value) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;

  var found = false;
  void visit(Element element) {
    if (found) return;
    final widget = element.widget;
    if (widget is Text && widget.data == value) {
      found = true;
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return found;
}
