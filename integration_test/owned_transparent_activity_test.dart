import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/api/simple.dart' as rust_simple;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../test/features/activity/transaction_loading_test_support.dart';

/// Opt-in native check over a fabricated, privately recovered production database.
/// Generate it with VIZOR_OWNED_TRANSFER_FIXTURE_DIR and the matching Rust test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native recovered self-transfer shows two gross legs and both receipts',
    (tester) async {
      const directory = String.fromEnvironment(
        'VIZOR_OWNED_TRANSFER_FIXTURE_DIR',
      );
      expect(
        directory,
        isNotEmpty,
        reason: 'use a fresh isolated Rust fixture',
      );
      final identity =
          jsonDecode(await File('$directory/identity.json').readAsString())
              as Map<String, dynamic>;
      await RustLib.init();
      await rust_simple.configureRegtestIronwoodActivationHeight(height: 2);
      Future<List<rust_sync.TransactionInfo>> history(String _) async =>
          (await rust_sync.getTransactionHistory(
            dbPath: '$directory/wallet.db',
            network: 'regtest',
            accountUuid: identity['account'] as String,
          )).where((tx) => tx.txidHex == identity['txid']).toList();
      final rows = await history('');
      expect(rows.map((r) => r.txKind), ['sent', 'received']);
      expect(
        rows.every(
          (r) =>
              r.displayAmount == BigInt.from(250000) &&
              r.accountBalanceDelta == -15000 &&
              r.inferredAttribution == true &&
              !r.detailsComplete &&
              !r.amountIncludesFee,
        ),
        isTrue,
      );
      await tester.binding.setSurfaceSize(const Size(1512, 982));
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 500,
                  child: ActivityFeed(
                    sections: [
                      ActivityFeedSectionData(
                        title: 'Recovered transfer',
                        rows: [
                          for (final tx in rows)
                            buildTransactionActivityRow(
                              context: context,
                              transaction: tx,
                              accountUuid: identity['account'] as String,
                              privateQueriesEnabled: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      expect(find.text('Transparent'), findsNWidgets(2));
      expect(
        find.textContaining('0.0025', findRichText: true),
        findsNWidgets(2),
      );
      expect(find.textContaining('0.00015', findRichText: true), findsNothing);
      expect(
        tester.getTopLeft(find.text('Sent')).dy,
        lessThan(tester.getTopLeft(find.text('Received')).dy),
      );
      for (final tx in rows) {
        await pumpOwnedTransferReceipt(
          tester,
          transaction: tx,
          history: history,
          detail: (_, row) => rust_sync.getTransactionDetail(
            dbPath: '$directory/wallet.db',
            network: 'regtest',
            accountUuid: identity['account'] as String,
            txidHex: row.txidHex,
            txKind: row.txKind,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            tx.txKind == 'sent' ? 'Sent successfully' : 'Received successfully',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('0.0025', findRichText: true), findsWidgets);
        expect(find.text('Details incomplete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
