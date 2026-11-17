import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/zcash/spendable_wait.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/send/widgets/spendable_wait_breakdown.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

final _wait = SpendableWait(
  availableNow: BigInt.from(100000000),
  changeWaiting: BigInt.from(120000000),
  receivedWaiting: BigInt.from(130000000),
  changeWait: const AvailableIn.minutes(1, 2),
  receivedWait: const AvailableIn.minutes(1, 3),
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  home: AppTheme(
    data: AppThemeData.light,
    child: Center(child: SizedBox(width: 360, child: child)),
  ),
);

void main() {
  testWidgets('lists what is spendable, each wait and the total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(SpendableWaitBreakdown(wait: _wait, compact: true)),
    );

    expect(find.text('Available now'), findsOneWidget);
    expect(find.text('1 ZEC'), findsOneWidget);
    expect(find.text('Finishing your last payment'), findsOneWidget);
    expect(find.text('Available in 1–2 min'), findsOneWidget);
    expect(find.text('+1.2 ZEC'), findsOneWidget);
    expect(find.text('Just received'), findsOneWidget);
    expect(find.text('Available in 1–3 min'), findsOneWidget);
    expect(find.text('+1.3 ZEC'), findsOneWidget);
    expect(find.text('3.5 ZEC'), findsOneWidget);
  });

  testWidgets('the sheet titles the amount and lists the same rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(SpendableWaitSheetContent(wait: _wait, onClose: () {})),
    );

    // The title is the sheet's; the amount under it is one serif figure.
    expect(find.text('Available now'), findsOneWidget);
    expect(find.text('1 ZEC', findRichText: true), findsOneWidget);
    expect(find.text('Finishing your last payment'), findsOneWidget);
    expect(find.text('+1.2 ZEC'), findsOneWidget);
    expect(find.text('3.5 ZEC'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('the sheet masks every amount in privacy mode', (tester) async {
    await tester.pumpWidget(
      _app(
        SpendableWaitSheetContent(
          wait: _wait,
          privacyModeEnabled: true,
          onClose: () {},
        ),
      ),
    );

    expect(find.text('1 ZEC', findRichText: true), findsNothing);
    expect(find.textContaining('1.2', findRichText: true), findsNothing);
    expect(find.textContaining('1.3', findRichText: true), findsNothing);
    expect(find.textContaining('3.5', findRichText: true), findsNothing);
    expect(find.text('Available in 1–3 min'), findsOneWidget);
  });

  testWidgets('privacy mode masks every amount', (tester) async {
    await tester.pumpWidget(
      _app(
        SpendableWaitBreakdown(
          wait: _wait,
          privacyModeEnabled: true,
          compact: true,
        ),
      ),
    );

    for (final amount in ['1 ZEC', '+1.2 ZEC', '+1.3 ZEC', '3.5 ZEC']) {
      expect(find.text(amount), findsNothing);
    }
    expect(find.textContaining('1.2'), findsNothing);
    expect(find.textContaining('1.3'), findsNothing);
    expect(find.textContaining('3.5'), findsNothing);
    expect(find.text('Available in 1–3 min'), findsOneWidget);
  });

  testWidgets('a confirming receipt row says when it is available', (
    tester,
  ) async {
    const waits = <String, ReceivedSpendableWait>{
      'received-1000': (
        wait: AvailableIn.minutes(1, 3),
        confirmations: 1,
        requiredConfirmations: 6,
      ),
    };
    late ActivityRowData waiting;
    late ActivityRowData withoutWaits;
    late ActivityRowData spendable;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            waiting = buildTransactionActivityRow(
              context: context,
              transaction: _received(minedHeight: 1000),
              spendableWaits: waits,
            );
            withoutWaits = buildTransactionActivityRow(
              context: context,
              transaction: _received(minedHeight: 1000),
            );
            spendable = buildTransactionActivityRow(
              context: context,
              transaction: _received(minedHeight: 990),
              spendableWaits: waits,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(waiting.title, 'Received');
    expect(waiting.subtitle, 'Available in 1–3 min');
    expect(withoutWaits.subtitle, isNot(contains('Available')));
    expect(spendable.subtitle, withoutWaits.subtitle);
  });
}

rust_sync.TransactionInfo _received({required int minedHeight}) {
  return rust_sync.TransactionInfo(
    txidHex: 'received-$minedHeight',
    minedHeight: BigInt.from(minedHeight),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    feeState: rust_sync.TransactionFeeState.notApplicable,
    detailsComplete: true,
    provisional: false,
    amountIncludesFee: false,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.from(130000000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
