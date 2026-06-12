import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  Future<ActivityRowData> mapRow(
    WidgetTester tester,
    rust_sync.TransactionInfo transaction,
  ) async {
    late ActivityRowData row;
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Builder(
          builder: (context) {
            row = buildTransactionActivityRow(
              context: context,
              transaction: transaction,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return row;
  }

  testWidgets('unconfirmed send renders as an in-flight loader row', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(txKind: 'sent', minedHeight: BigInt.zero),
    );
    expect(row.title, 'Sending ...');
    expect(row.leadingIconName, AppIcons.loader);
    expect(row.statusText, 'In progress');
  });

  testWidgets('unconfirmed receive renders as an in-flight loader row', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(txKind: 'receiving', minedHeight: BigInt.zero),
    );
    expect(row.title, 'Receiving ...');
    expect(row.leadingIconName, AppIcons.loader);
  });

  testWidgets('confirmed transactions keep their settled titles and icons', (
    tester,
  ) async {
    final sent = await mapRow(tester, _transaction(txKind: 'sent'));
    expect(sent.title, 'Sent');
    expect(sent.leadingIconName, AppIcons.plane);

    final received = await mapRow(tester, _transaction(txKind: 'received'));
    expect(received.title, 'Received');
    expect(received.leadingIconName, AppIcons.arrowDownCircle);
  });

  testWidgets('expired send stays a failed row, not an in-flight one', (
    tester,
  ) async {
    final row = await mapRow(
      tester,
      _transaction(
        txKind: 'sent',
        minedHeight: BigInt.zero,
        expiredUnmined: true,
      ),
    );
    expect(row.title, 'Send failed');
    expect(row.leadingIconName, isNot(AppIcons.loader));
  });
}

rust_sync.TransactionInfo _transaction({
  required String txKind,
  BigInt? minedHeight,
  bool expiredUnmined = false,
}) {
  return rust_sync.TransactionInfo(
    txidHex: 'ab12cd34',
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: BigInt.from(1750000000),
    isTransparent: false,
    txKind: txKind,
    displayAmount: BigInt.from(12000000000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1750000000),
  );
}
