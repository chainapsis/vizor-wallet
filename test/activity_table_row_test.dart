import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_table.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  final ticker = kZcashDefaultCurrencyTicker;

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

    expect(rows[0].amountText, '+1.2345 $ticker');
    expect(rows[1].amountText, '-1 $ticker');
    expect(rows[2].amountText, '0.0001 $ticker');
    expect(find.text('0.0001 $ticker'), findsOneWidget);
    expect(find.text('+1.2345 $ticker'), findsOneWidget);
    expect(find.text('-1 $ticker'), findsOneWidget);
    expect(find.text('Wallet Synced'), findsNothing);
  });

  testWidgets('pending inbound activity rows render as receiving', (
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
                transactions: [
                  _tx(
                    txidHex: 'receiving',
                    kind: 'receiving',
                    amount: BigInt.from(123450000),
                    minedHeight: BigInt.zero,
                  ),
                ],
              );
              return ActivityTable(rows: rows);
            },
          ),
        ),
      ),
    );

    expect(rows[0].title, 'Receiving');
    expect(rows[0].amountText, '+1.2345 $ticker');
    expect(rows[0].statusText, 'In progress');
    expect(rows[0].leadingIconName, AppIcons.arrowDownCircle);
    expect(find.text('Receiving'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('failed sent activity rows render refunded state', (
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
                transactions: [
                  _tx(
                    txidHex: 'failed-sent',
                    kind: 'sent',
                    amount: BigInt.from(111000000),
                    expiredUnmined: true,
                  ),
                ],
              );
              return ActivityTable(rows: rows);
            },
          ),
        ),
      ),
    );

    expect(rows[0].title, 'Send failed');
    expect(rows[0].amountText, '1.11 $ticker');
    expect(rows[0].amountIconName, AppIcons.arrowBack);
    expect(rows[0].amountSubtitle, 'Refunded');
    expect(rows[0].statusText, 'Failed');
    expect(rows[0].statusIconName, AppIcons.skull);
    expect(rows[0].backgroundColor, isNull);
    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
  });

  testWidgets('amount subtitles can render an inline status icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: ActivityTable(
            rows: [
              _row(
                title: 'Swap failed',
                amountSubtitle: 'Timeout',
                amountSubtitleIconName: AppIcons.time,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Timeout'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.time,
      ),
      findsOneWidget,
    );
  });

  testWidgets('activity rows hide asset amounts with a fixed mask', (
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
                privacyModeEnabled: true,
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

    expect(rows[0].amountText, '*** $ticker');
    expect(rows[1].amountText, '*** $ticker');
    expect(rows[2].amountText, '*** $ticker');
    expect(find.text('*** $ticker'), findsNWidgets(3));
    expect(find.text('+1.2345 $ticker'), findsNothing);
    expect(find.text('-1 $ticker'), findsNothing);
  });

  testWidgets('shielded activity rows use the shield keyhole outline icon', (
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
                transactions: [
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

    expect(rows[0].leadingIconName, AppIcons.shieldKeyholeOutline);
  });

  testWidgets('activity row value cells use label large typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: ActivityTable(rows: [_row(title: 'Wallet Synced')]),
        ),
      ),
    );

    for (final value in ['1.00 $ticker', 'Completed', 'Today, 13:11']) {
      final text = tester.widget<Text>(find.text(value));
      expect(text.style?.fontFamily, AppTypography.labelLarge.fontFamily);
      expect(text.style?.fontWeight, AppTypography.labelLarge.fontWeight);
      expect(text.style?.fontSize, AppTypography.labelLarge.fontSize);
      expect(text.style?.height, AppTypography.labelLarge.height);
      expect(text.style?.letterSpacing, AppTypography.labelLarge.letterSpacing);
    }
  });

  testWidgets('activity table renders grouped child rows under parent rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: ActivityTable(
            rows: [
              _row(
                title: 'Swapping...',
                childRows: [_row(title: 'Receiving ZEC...')],
              ),
              _row(title: 'Sent'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Swapping...'), findsOneWidget);
    expect(find.text('Receiving ZEC...'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);

    final parentTop = tester.getTopLeft(find.text('Swapping...')).dy;
    final childTop = tester.getTopLeft(find.text('Receiving ZEC...')).dy;
    final nextTop = tester.getTopLeft(find.text('Sent')).dy;
    expect(childTop, greaterThan(parentTop));
    expect(nextTop, greaterThan(childTop));
  });

  testWidgets('swap progress avatar keeps the row icon in the center', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: ActivityTable(
            rows: [
              _row(
                title: 'Swapping...',
                leadingIconName: AppIcons.swapArrows,
                leadingProgressValue: 0.75,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.swapArrows &&
            widget.size == 16,
      ),
      findsOneWidget,
    );
  });
}

rust_sync.TransactionInfo _tx({
  required String txidHex,
  required String kind,
  required BigInt amount,
  BigInt? minedHeight,
  bool expiredUnmined = false,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: minedHeight ?? BigInt.one,
    expiredUnmined: expiredUnmined,
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
  String leadingIconName = AppIcons.sync,
  String? subtitle,
  String? amountSubtitle,
  String? amountSubtitleIconName,
  double? leadingProgressValue,
  List<ActivityRowData> childRows = const [],
  VoidCallback? onTap,
}) {
  return ActivityRowData(
    title: title,
    leadingIconName: leadingIconName,
    leadingBackgroundColor: const Color(0xFFE1E1E1),
    leadingIconColor: const Color(0xFF4D5252),
    leadingProgressValue: leadingProgressValue,
    subtitle: subtitle,
    amountText: '1.00 $kZcashDefaultCurrencyTicker',
    amountSubtitle: amountSubtitle,
    amountSubtitleIconName: amountSubtitleIconName,
    statusText: 'Completed',
    timestampText: 'Today, 13:11',
    childRows: childRows,
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
