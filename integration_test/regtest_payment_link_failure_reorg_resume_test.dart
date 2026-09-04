import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';
import 'support/regtest_lightwalletd_proxy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'retains two claims below finality and across a natural reorg',
    (tester) async {
      final proxy = RegtestLightwalletdProxy(log: e2eLog);
      await proxy.start();
      addTearDown(proxy.stop);
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        await cleanupDesktopRegtestWallet();
        await cleanupRegtestPaymentLinkClaimWallets();
        await deletePaymentLinkRestartManifest();
      });

      final manifest = await readPaymentLinkRestartManifest();
      expect(manifest.claims, hasLength(2));
      for (final claim in manifest.claims) {
        expect(
          await (await paymentLinkClaimWalletDirectoryByName(
            claim.directoryName,
          )).exists(),
          isTrue,
        );
      }

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await unlockDesktopRegtestWallet(tester);

      final minedTransactions = <String, BigInt>{};
      for (final claim in manifest.claims) {
        final transaction = await waitForPaymentLinkHistoryTransaction(
          tester,
          accountUuid: manifest.receiverAccountUuid,
          txKind: 'received',
          amount: claim.amountZatoshi,
          pending: false,
        );
        minedTransactions[claim.address] = transaction.minedHeight;
      }
      await waitForForegroundSyncIdle(tester);

      final fiveConfirmationTip = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: paymentLinkRegtestLightwalletdUrl,
      );
      for (final minedHeight in minedTransactions.values) {
        expect(
          paymentLinkConfirmationCount(
            minedHeight: minedHeight,
            chainTipHeight: fiveConfirmationTip,
          ),
          5,
        );
      }
      await _expectReceivingClaimsAndDatabases(tester, manifest);

      final recordsBeforeReorg = await waitForReceivedRecords(
        tester,
        (records) => manifest.claims.every(
          (claim) => records.any(
            (record) =>
                record.address == claim.address &&
                record.status == PaymentLinkReceivedStatus.receiving,
          ),
        ),
        description: 'both claims to remain Receiving at five confirmations',
      );
      final claimTxids = recordsBeforeReorg
          .where(
            (record) =>
                manifest.claims.any((claim) => claim.address == record.address),
          )
          .expand((record) => record.claimTxids!.split(','))
          .map((txid) => txid.trim())
          .where((txid) => txid.isNotEmpty)
          .toSet();
      expect(claimTxids, isNotEmpty);

      final forkHeight =
          minedTransactions.values.map((height) => height.toInt()).reduce(min) -
          1;
      await _replaceClaimBranch(tester, forkHeight, claimTxids);

      for (final claim in manifest.claims) {
        await waitForPaymentLinkHistoryTransaction(
          tester,
          accountUuid: manifest.receiverAccountUuid,
          txKind: 'receiving',
          amount: claim.amountZatoshi,
          pending: true,
          timeout: const Duration(minutes: 4),
        );
      }
      await _expectReceivingClaimsAndDatabases(tester, manifest);

      for (final txid in claimTxids) {
        await paymentLinkZcashdRpc<bool>('prioritisetransaction', [
          txid,
          0,
          100_000_000,
        ]);
      }
      await minePaymentLinkRegtestBlocks(kPaymentLinkClaimConfirmationTarget);

      for (final claim in manifest.claims) {
        await waitForPaymentLinkHistoryTransaction(
          tester,
          accountUuid: manifest.receiverAccountUuid,
          txKind: 'received',
          amount: claim.amountZatoshi,
          pending: false,
          timeout: const Duration(minutes: 4),
        );
      }
      final received = await waitForReceivedRecords(
        tester,
        (records) => manifest.claims.every(
          (claim) => records.any(
            (record) =>
                record.address == claim.address &&
                record.status == PaymentLinkReceivedStatus.received,
          ),
        ),
        description: 'both reorged claims to finalize independently',
        timeout: const Duration(minutes: 4),
      );
      expect(received, hasLength(2));
      for (final claim in manifest.claims) {
        final record = received.singleWhere(
          (candidate) => candidate.address == claim.address,
        );
        expect(record.claimLink, isNull);
        expect(record.claimTxids, isNotEmpty);
        expect(
          await (await paymentLinkClaimWalletDirectoryByName(
            claim.directoryName,
          )).exists(),
          isFalse,
        );
      }
      await waitForPaymentLinkAccountBalance(
        tester,
        accountUuid: manifest.receiverAccountUuid,
        total:
            manifest.receiverStartingTotal +
            manifest.claims.fold<BigInt>(
              BigInt.zero,
              (total, claim) => total + claim.amountZatoshi,
            ),
      );
      e2eLog('both Gift Card claims survived retry and reorg finality');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _expectReceivingClaimsAndDatabases(
  WidgetTester tester,
  PaymentLinkRestartManifest manifest,
) async {
  final records = await waitForReceivedRecords(
    tester,
    (records) => manifest.claims.every(
      (claim) => records.any(
        (record) =>
            record.address == claim.address &&
            record.status == PaymentLinkReceivedStatus.receiving,
      ),
    ),
    description: 'both claims to remain Receiving with retained databases',
  );
  expect(records, hasLength(2));
  for (final claim in manifest.claims) {
    final directory = await paymentLinkClaimWalletDirectoryByName(
      claim.directoryName,
    );
    expect(await directory.exists(), isTrue);
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}zcash_wallet.db',
      ).exists(),
      isTrue,
    );
  }
}

Future<void> _replaceClaimBranch(
  WidgetTester tester,
  int forkHeight,
  Set<String> claimTxids,
) async {
  await ensurePaymentLinkRegtestChain();
  final oldTip = await paymentLinkZcashdRpc<int>('getblockcount');
  expect(forkHeight, lessThan(oldTip));
  final invalidatedHash = await paymentLinkZcashdRpc<String>('getblockhash', [
    forkHeight + 1,
  ]);
  await paymentLinkZcashdRpc<Object?>('invalidateblock', [invalidatedHash]);
  for (final txid in claimTxids) {
    await paymentLinkZcashdRpc<bool>('prioritisetransaction', [
      txid,
      0,
      -100_000_000,
    ]);
  }
  await minePaymentLinkRegtestBlocks(oldTip - forkHeight + 1);
  final newTip = await paymentLinkZcashdRpc<int>('getblockcount');
  expect(newTip, oldTip + 1);
  await waitForPaymentLinkMempoolTxids(tester, claimTxids);
}
