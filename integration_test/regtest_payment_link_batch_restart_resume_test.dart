import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_batch_export.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets('restores the same 50-card group after a process restart', (
    tester,
  ) async {
    final proxy = RegtestLightwalletdProxy(log: e2eLog);
    await proxy.start();
    addTearDown(proxy.stop);
    addTearDown(() async {
      await cleanupDesktopRegtestWallet();
      await cleanupRegtestPaymentLinkClaimWallets();
      await deletePaymentLinkBatchRestartManifest();
    });

    final manifest = await readPaymentLinkBatchRestartManifest();
    expect(manifest.addresses, hasLength(50));

    await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
    // Let the startup route settle before typing into the unlock field.
    await pumpUntil(
      tester,
      () => tester.any(find.byKey(const ValueKey('unlock_password_field'))),
      description: 'unlock screen after restart',
    );
    await tester.pump(const Duration(seconds: 1));
    await unlockDesktopRegtestWallet(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
    );

    // One funding transaction, mined while the app was stopped.
    final history = await _waitForMinedFunding(tester, manifest);
    final sent = history.where((tx) => tx.txKind == 'sent').toList();
    expect(sent, hasLength(1));
    expect(sent.single.displayAmount, BigInt.from(50_500_000));

    final members =
        (await container
                .read(paymentLinkOperationsProvider)
                .loadCreatedLinkRecoveries())
            .where((record) => record.batchId == manifest.batchId)
            .toList();
    expect(members, hasLength(50));
    expect(
      members.map((record) => record.link.address).toSet(),
      manifest.addresses.toSet(),
    );
    expect(members.map((record) => record.fundingTxids).toSet(), {
      manifest.fundingTxid,
    });
    expect(isCompletePaymentLinkBatch(members), isTrue);

    // Every card's secret survived: all 50 links can be rebuilt.
    final rows = (await preparePaymentLinkBatchCsv(
      members,
    )).trim().split('\r\n');
    expect(rows, hasLength(51));
    expect(
      rows
          .skip(1)
          .map((row) => RegExp(r'"([^"]*)"$').firstMatch(row)!.group(1))
          .toSet(),
      hasLength(50),
    );

    await openPaymentLinksFromSettings(tester);
    // Once ready, the row's trailing status is "Ready to share" or a usage
    // summary such as "3 of 50 used".
    final row = find.byKey(ValueKey('payment_link_batch_${manifest.batchId}'));
    final readyStatus = RegExp(r'^(Ready to share|All used|\d+ of \d+ used)$');
    List<String> rowTexts() => [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: row, matching: find.byType(Text)),
      ))
        text.data ?? '',
    ];
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (!rowTexts().any(readyStatus.hasMatch)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The restored group never became ready: ${rowTexts()}');
      }
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    e2eLog(
      'batch restart recovered: 50 cards, one txid=${manifest.fundingTxid}, '
      'csv rows=${rows.length - 1}, row=${rowTexts()}',
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<List<rust_sync.TransactionInfo>> _waitForMinedFunding(
  WidgetTester tester,
  PaymentLinkBatchRestartManifest manifest,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  var history = const <rust_sync.TransactionInfo>[];
  while (DateTime.now().isBefore(deadline)) {
    history = await rust_sync.getTransactionHistory(
      dbPath: await getWalletDbPath(),
      network: paymentLinkRegtestNetwork,
      accountUuid: manifest.senderAccountUuid,
      limit: null,
    );
    if (history.any(
      (tx) =>
          paymentLinkTxidsMatch(tx.txidHex, manifest.fundingTxid) &&
          tx.minedHeight > BigInt.zero,
    )) {
      return history;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'The batch funding ${manifest.fundingTxid} was not mined in history: '
    '${history.map((tx) => '${tx.txidHex}:${tx.txKind}:height=${tx.minedHeight}').join(', ')}',
  );
}
