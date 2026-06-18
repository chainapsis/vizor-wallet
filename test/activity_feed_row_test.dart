import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  final ticker = kZcashDefaultCurrencyTicker;

  testWidgets('transaction rows are keyboard activatable but sync row is not', (
    tester,
  ) async {
    var txActivations = 0;

    await _pumpActivityFeed(
      tester,
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

    await _pumpMappedTransactions(
      tester,
      transactions: [
        _tx(
          txidHex: 'received',
          kind: 'received',
          amount: BigInt.from(123450000),
        ),
        _tx(txidHex: 'sent', kind: 'sent', amount: BigInt.from(100000000)),
        _tx(txidHex: 'shielded', kind: 'shielded', amount: BigInt.from(10000)),
      ],
      onRows: (value) => rows = value,
    );

    expect(rows[0].amountText, '+1.2345 $ticker');
    expect(rows[1].amountText, '-1 $ticker');
    expect(rows[2].amountText, '0.0001 $ticker');
    expect(rows[0].amountColor, AppThemeData.light.colors.text.positiveStrong);
    expect(rows[1].amountColor, outgoingAmountColor(AppThemeData.light.colors));
    expect(find.text('0.0001 $ticker'), findsOneWidget);
    expect(find.text('+1.2345 $ticker'), findsOneWidget);
    expect(find.text('-1 $ticker'), findsOneWidget);
    expect(find.text('Wallet Synced'), findsNothing);
  });

  testWidgets('pending inbound activity rows render as receiving', (
    tester,
  ) async {
    late final List<ActivityRowData> rows;

    await _pumpMappedTransactions(
      tester,
      transactions: [
        _tx(
          txidHex: 'receiving',
          kind: 'receiving',
          amount: BigInt.from(123450000),
          minedHeight: BigInt.zero,
        ),
      ],
      onRows: (value) => rows = value,
    );

    expect(rows[0].title, 'Receiving ...');
    expect(rows[0].amountText, '+1.2345 $ticker');
    expect(rows[0].statusText, 'In progress');
    expect(rows[0].leadingIconName, AppIcons.loader);
    expect(find.text('Receiving ...'), findsOneWidget);
    expect(find.text('+1.2345 $ticker'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.loader &&
            widget.size == 16 &&
            widget.animated,
      ),
      findsOneWidget,
    );
  });

  testWidgets('pending sent activity rows render as sending', (tester) async {
    late final List<ActivityRowData> rows;

    await _pumpMappedTransactions(
      tester,
      transactions: [
        _tx(
          txidHex: 'sending',
          kind: 'sent',
          amount: BigInt.from(100000000),
          minedHeight: BigInt.zero,
        ),
      ],
      onRows: (value) => rows = value,
    );

    expect(rows[0].title, 'Sending ...');
    expect(rows[0].amountText, '-1 $ticker');
    expect(rows[0].statusText, 'In progress');
    expect(rows[0].leadingIconName, AppIcons.loader);
    expect(find.text('Sending ...'), findsOneWidget);
    expect(find.text('-1 $ticker'), findsOneWidget);
  });

  testWidgets('failed sent activity rows render refunded state', (
    tester,
  ) async {
    late final List<ActivityRowData> rows;

    await _pumpMappedTransactions(
      tester,
      transactions: [
        _tx(
          txidHex: 'failed-sent',
          kind: 'sent',
          amount: BigInt.from(111000000),
          expiredUnmined: true,
        ),
      ],
      onRows: (value) => rows = value,
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
    await _pumpActivityFeed(
      tester,
      rows: [
        _row(
          title: 'Swap failed',
          amountSubtitle: 'Timeout',
          amountSubtitleIconName: AppIcons.time,
        ),
      ],
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

    await _pumpMappedTransactions(
      tester,
      privacyModeEnabled: true,
      transactions: [
        _tx(
          txidHex: 'received',
          kind: 'received',
          amount: BigInt.from(123450000),
        ),
        _tx(txidHex: 'sent', kind: 'sent', amount: BigInt.from(100000000)),
        _tx(txidHex: 'shielded', kind: 'shielded', amount: BigInt.from(10000)),
      ],
      onRows: (value) => rows = value,
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

    await _pumpMappedTransactions(
      tester,
      transactions: [
        _tx(txidHex: 'shielded', kind: 'shielded', amount: BigInt.from(10000)),
      ],
      onRows: (value) => rows = value,
    );

    expect(rows[0].leadingIconName, AppIcons.shieldKeyholeOutline);
  });

  testWidgets('transparent activity rows use the transparent subtitle icon', (
    tester,
  ) async {
    late final List<ActivityRowData> rows;

    await _pumpMappedTransactions(
      tester,
      transactions: [
        _tx(
          txidHex: 'transparent-sent',
          kind: 'sent',
          amount: BigInt.from(100000000),
          displayPool: 'transparent',
        ),
      ],
      onRows: (value) => rows = value,
    );

    expect(rows[0].subtitle, 'Transparent');
    expect(rows[0].subtitleIconName, AppIcons.transparentBalance);
    expect(find.text('Transparent'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.transparentBalance &&
            widget.size == 16,
      ),
      findsOneWidget,
    );
  });

  testWidgets('activity feed uses compact value typography', (tester) async {
    await _pumpActivityFeed(tester, rows: [_row(title: 'Wallet Synced')]);

    final amount = tester.widget<Text>(find.text('1.00 $ticker'));
    expect(amount.style?.fontFamily, AppTypography.labelLarge.fontFamily);
    // Content Line amounts render in the semibold emphasis weight.
    expect(amount.style?.fontWeight, FontWeight.w600);
    expect(amount.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(amount.style?.height, AppTypography.labelLarge.height);

    final timestamp = tester.widget<Text>(find.text('Today, 13:11'));
    expect(timestamp.style?.fontFamily, AppTypography.labelSmall.fontFamily);
    expect(timestamp.style?.fontWeight, AppTypography.labelSmall.fontWeight);
    expect(timestamp.style?.fontSize, AppTypography.labelSmall.fontSize);
    expect(timestamp.style?.height, AppTypography.labelSmall.height);
  });

  testWidgets('activity feed renders grouped child rows under parent rows', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      rows: [
        _row(
          title: 'Swapping...',
          childRows: [_row(title: 'Receiving ZEC...')],
        ),
        _row(title: 'Sent'),
      ],
    );

    expect(find.text('Swapping...'), findsOneWidget);
    expect(find.text('Receiving ZEC...'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activity_feed_child_connector')),
      findsOneWidget,
    );

    final parentTop = tester.getTopLeft(find.text('Swapping...')).dy;
    final childTop = tester.getTopLeft(find.text('Receiving ZEC...')).dy;
    final nextTop = tester.getTopLeft(find.text('Sent')).dy;
    expect(childTop, greaterThan(parentTop));
    expect(nextTop, greaterThan(childTop));
  });

  testWidgets('child rows are tappable only when they carry an onTap', (
    tester,
  ) async {
    var tappableActivations = 0;

    await _pumpActivityFeed(
      tester,
      rows: [
        _row(
          title: 'Swapped',
          childRows: [
            _row(
              title: 'Received ZEC',
              onTap: () {
                tappableActivations += 1;
              },
            ),
            _row(title: 'Deposited USDC'),
          ],
        ),
      ],
    );

    // The shared child slot animates in via AnimatedSize, and the connector
    // line renders for the grouped children.
    expect(find.byType(AnimatedSize), findsWidgets);
    expect(
      find.byKey(const ValueKey('activity_feed_child_connector')),
      findsWidgets,
    );

    // The tappable child opts into the click cursor; the inert one does not.
    expect(
      find.ancestor(
        of: find.text('Received ZEC'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsWidgets,
    );
    expect(
      find.ancestor(
        of: find.text('Deposited USDC'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Received ZEC'));
    await tester.pump();
    expect(tappableActivations, 1);

    // Tapping the inert child must do nothing (no callback to fire).
    await tester.tap(find.text('Deposited USDC'));
    await tester.pump();
    expect(tappableActivations, 1);
  });

  testWidgets('tappable child rows are keyboard activatable', (tester) async {
    var childActivations = 0;

    await _pumpActivityFeed(
      tester,
      rows: [
        _row(
          title: 'Swapped',
          childRows: [
            _row(
              title: 'Received ZEC',
              onTap: () {
                childActivations += 1;
              },
            ),
          ],
        ),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(_primaryFocusContainsText('Received ZEC'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(childActivations, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(childActivations, 2);
  });

  testWidgets('swap progress avatar keeps the row icon in the center', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      rows: [
        _row(
          title: 'Swapping...',
          leadingIconName: AppIcons.swapArrows,
          leadingProgressValue: 0.75,
        ),
      ],
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

  testWidgets('activity feed uses stable row ids when available', (
    tester,
  ) async {
    await _pumpActivityFeed(
      tester,
      rows: [
        _row(title: 'Received', stableId: 'tx:received:received'),
        _row(title: 'Sent', stableId: 'tx:sent:sent'),
      ],
    );

    expect(find.byKey(const ValueKey('tx:received:received')), findsOneWidget);
    expect(find.byKey(const ValueKey('tx:sent:sent')), findsOneWidget);
  });

  testWidgets('activity feed sliver lazily builds row items', (tester) async {
    await _pumpActivityFeedSliver(
      tester,
      rows: [
        for (var index = 0; index < 60; index++)
          _row(title: 'Row $index', stableId: 'row-$index'),
      ],
    );

    expect(find.byKey(const ValueKey('row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-59')), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('row-59')),
      240,
      scrollable: find.byType(Scrollable),
      maxScrolls: 80,
    );

    expect(find.byKey(const ValueKey('row-59')), findsOneWidget);
  });

  test('formatActivityTimestamp drops the clock time when dateOnly', () {
    final dt = DateTime(2026, 5, 14, 17, 45);
    expect(formatActivityTimestamp(dt), 'May 14, 17:45');
    expect(formatActivityTimestamp(dt, dateOnly: true), 'May 14');
  });
}

Future<void> _pumpMappedTransactions(
  WidgetTester tester, {
  required List<rust_sync.TransactionInfo> transactions,
  required ValueChanged<List<ActivityRowData>> onRows,
  bool privacyModeEnabled = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Builder(
          builder: (context) {
            final rows = [
              for (final tx in transactions)
                buildTransactionActivityRow(
                  context: context,
                  transaction: tx,
                  privacyModeEnabled: privacyModeEnabled,
                ),
            ];
            onRows(rows);
            return _feed(rows);
          },
        ),
      ),
    ),
  );
}

Future<void> _pumpActivityFeed(
  WidgetTester tester, {
  required List<ActivityRowData> rows,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AppTheme(data: AppThemeData.light, child: _feed(rows)),
    ),
  );
}

Widget _feed(List<ActivityRowData> rows) {
  return Center(
    child: SizedBox(
      width: 420,
      child: ActivityFeed(
        sections: [ActivityFeedSectionData(title: 'This week', rows: rows)],
      ),
    ),
  );
}

Future<void> _pumpActivityFeedSliver(
  WidgetTester tester, {
  required List<ActivityRowData> rows,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: 420,
            height: 240,
            child: CustomScrollView(
              slivers: [
                ActivityFeedSliver(
                  sections: [
                    ActivityFeedSectionData(title: 'This week', rows: rows),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

rust_sync.TransactionInfo _tx({
  required String txidHex,
  required String kind,
  required BigInt amount,
  BigInt? minedHeight,
  bool expiredUnmined = false,
  String displayPool = 'shielded',
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
    displayPool: displayPool,
    createdTime: BigInt.from(1800000000),
  );
}

ActivityRowData _row({
  required String title,
  String? stableId,
  String leadingIconName = AppIcons.sync,
  String? subtitle,
  String? amountSubtitle,
  String? amountSubtitleIconName,
  double? leadingProgressValue,
  List<ActivityRowData> childRows = const [],
  VoidCallback? onTap,
}) {
  return ActivityRowData(
    stableId: stableId,
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
