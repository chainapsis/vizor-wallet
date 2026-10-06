import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fixtures/private_send_activity.dart';

/// The reported shielded send with a transparent output, as Vizor's Rust
/// history read produces it for a public and a private restore of the same
/// chain (`private_send_activity_tests.rs`).
void main() {
  final activity = loadPrivateSendActivity();

  Future<List<ActivityRowData>> pumpRows(
    WidgetTester tester,
    List<rust_sync.TransactionInfo> transactions, {
    required bool privateQueriesEnabled,
  }) async {
    late List<ActivityRowData> rows;
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              rows = [
                for (final tx in transactions)
                  buildTransactionActivityRow(
                    context: context,
                    transaction: tx,
                    privateQueriesEnabled: privateQueriesEnabled,
                  ),
              ];
              return Center(
                child: SizedBox(
                  width: 420,
                  child: ActivityFeed(
                    sections: [
                      ActivityFeedSectionData(title: 'This week', rows: rows),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    return rows;
  }

  List<(String, String, String?, String?)> shown(List<ActivityRowData> rows) =>
      [
        for (final row in rows)
          (row.title, row.amountText, row.subtitle, row.subtitleIconName),
      ];

  testWidgets('the public restore shows the send and the known receive', (
    tester,
  ) async {
    final rows = await pumpRows(
      tester,
      activity.public,
      privateQueriesEnabled: false,
    );
    expect(shown(rows), [
      ('Sent', '-0.0025 ZEC', 'Transparent', AppIcons.transparentBalance),
      ('Received', '+0.0025 ZEC', 'Transparent', AppIcons.transparentBalance),
    ]);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('-0.0025 ZEC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a private restore shows the public send, title and pool, marked incomplete',
    (tester) async {
      final public = shown(
        await pumpRows(tester, activity.public, privateQueriesEnabled: false),
      );
      final rows = await pumpRows(
        tester,
        activity.private,
        privateQueriesEnabled: true,
      );
      expect(shown(rows), public);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('-0.0025 ZEC'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('+0.0025 ZEC'), findsOneWidget);
      // The amount is inferred, not attributed: the rows say so.
      for (final row in rows) {
        expect(row.amountSubtitle, kIncompleteDetailsText);
        expect(row.statusText, 'Completed');
      }
      expect(find.text(kIncompleteDetailsText), findsNWidgets(2));
      // The whole network fee is shown beside the amount, never inside it.
      for (final tx in activity.private) {
        expect(tx.feeState, rust_sync.TransactionFeeState.known);
        expect(tx.fee, BigInt.from(15000));
        expect(
          transactionFeePresentation(tx),
          TransactionFeePresentation.separate,
        );
        expect(transactionDetailsIncomplete(tx), isTrue);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a private restore without transparent rows shows the same send alone',
    (tester) async {
      final public = shown(
        await pumpRows(tester, activity.public, privateQueriesEnabled: false),
      );
      final rows = await pumpRows(
        tester,
        activity.privateWithoutTransparentRows,
        privateQueriesEnabled: true,
      );
      expect(shown(rows), [public.first]);
      expect(rows.single.amountSubtitle, kIncompleteDetailsText);
      expect(find.text('Received'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
