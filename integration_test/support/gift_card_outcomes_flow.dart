import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_wizard_chrome.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'desktop_regtest_flow.dart';
import 'payment_link_regtest_flow.dart';
import 'regtest_lightwalletd_proxy.dart';

final giftOutcomeAmount = BigInt.from(10_000_000);

ProviderContainer giftOutcomeContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ZcashWalletApp)));

Future<void> cleanupGiftOutcomes() async {
  await Clipboard.setData(const ClipboardData(text: ''));
  await cleanupDesktopRegtestWallet();
  await cleanupRegtestPaymentLinkClaimWallets();
  await deletePaymentLinkRestartManifest();
}

Future<PaymentLinkReceivedRecord> outcomeRecord(WidgetTester tester) async =>
    (await giftOutcomeContainer(
      tester,
    ).read(paymentLinkReceivedStoreProvider).load()).single;

Future<void> expectOutcomeText(WidgetTester tester, String text) => pumpUntil(
  tester,
  () => tester.any(find.text(text)),
  description: 'Gift Card UI: $text',
  timeout: const Duration(minutes: 3),
);

Future<void> openReceivedTab(WidgetTester tester) async {
  final tab = find.widgetWithText(PaymentLinkTabAction, 'Received');
  await pumpUntil(tester, () => tester.any(tab), description: 'Received tab');
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> openOutcome(WidgetTester tester) async {
  if (tester.any(find.text('Return home'))) {
    await tapPaymentLinkText(tester, 'Return home');
  }
  await openReceivedTab(tester);
  await tapPaymentLinkText(tester, 'Check status');
  await expectOutcomeText(tester, 'Checking result');
}

Future<void> checkOutcome(WidgetTester tester) async {
  await tapPaymentLinkText(tester, 'Check status');
  // The label changes to Checking... while the asynchronous scan is running.
  await expectOutcomeText(tester, 'Check status');
}

Future<void> expectFreshObserver(VizorPaymentLink link) async {
  final directory = await Directory.systemTemp.createTemp(
    'vizor-card-observer-',
  );
  try {
    final db = '${directory.path}/zcash_wallet.db';
    final imported = await rust_wallet.importWallet(
      mnemonic: link.mnemonic,
      bip39Passphrase: '',
      birthdayHeight: BigInt.from(link.birthdayHeight),
      network: 'regtest',
      dbPath: db,
    );
    await rust_sync.runPaymentLinkClaimSync(
      claimId: 'e2e-late-observer',
      dbPath: db,
      lightwalletdUrl: paymentLinkRegtestLightwalletdUrl,
      network: 'regtest',
      allowResubmit: false,
    );
    final evidence = await rust_sync.getPaymentLinkSpendEvidence(
      dbPath: db,
      accountUuid: imported.accountUuid,
      claimTxids: '',
    );
    expect(evidence.localClaimTxids, isEmpty);
    expect(evidence.allFundsSpentElsewhere, isTrue);
    final balance = await rust_sync.getBalance(
      dbPath: db,
      network: 'regtest',
      accountUuid: imported.accountUuid,
    );
    expect(balance.total, BigInt.zero);
  } finally {
    await directory.delete(recursive: true);
  }
}

/// Both wallets have scanned the same funding before this hook runs. The
/// independent competitor broadcasts first, then the app submits its real
/// prepared claim. Only scheduling is controlled; no wallet result is mocked.
Future<void> submitCompetitor(
  PaymentLinkClaimSession session,
  String winnerAccountUuid,
) async {
  final directory = await Directory.systemTemp.createTemp('vizor-card-race-');
  try {
    final dbPath = '${directory.path}/zcash_wallet.db';
    final account = await rust_wallet.importWallet(
      mnemonic: session.link.mnemonic,
      bip39Passphrase: '',
      birthdayHeight: BigInt.from(session.link.birthdayHeight),
      network: 'regtest',
      dbPath: dbPath,
    );
    await rust_sync.runPaymentLinkClaimSync(
      claimId: 'e2e-competitor',
      dbPath: dbPath,
      lightwalletdUrl: paymentLinkRegtestLightwalletdUrl,
      network: 'regtest',
      allowResubmit: false,
    );
    final winnerAddress = await rust_wallet.getUnifiedAddress(
      dbPath: await getWalletDbPath(),
      network: 'regtest',
      accountUuid: winnerAccountUuid,
    );
    final proposal = await rust_sync.proposeSend(
      dbPath: dbPath,
      network: 'regtest',
      accountUuid: account.accountUuid,
      sendFlowId: 'e2e-competitor',
      toAddress: winnerAddress,
      amountZatoshi: giftOutcomeAmount,
    );
    expect(proposal.needsSaplingParams, isFalse);
    final result = await rust_sync.executeProposal(
      dbPath: dbPath,
      lightwalletdUrl: paymentLinkRegtestLightwalletdUrl,
      proposalId: proposal.proposalId,
      sendFlowId: 'e2e-competitor',
      mnemonicBytes: utf8.encode(session.link.mnemonic),
    );
    expect(result.status, 'broadcasted');
    await waitForCompetitorInMempool(result.txids);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> waitForCompetitorInMempool(String txids) async {
  final mempool = await paymentLinkZcashdRpc<List<Object?>>('getrawmempool');
  // ExecuteProposal returns display-order IDs, unlike the received store.
  expect(mempool, containsAll(txids.split(',')));
}

Future<void> prepareGiftOutcome(
  WidgetTester tester, {
  required bool competition,
}) async {
  var retained = false;
  final proxy = RegtestLightwalletdProxy(log: e2eLog);
  await proxy.start();
  addTearDown(() async {
    await proxy.stop();
    await Clipboard.setData(const ClipboardData(text: ''));
    if (!retained) await cleanupGiftOutcomes();
  });
  await cleanupGiftOutcomes();
  await configurePaymentLinkRegtestProxyPrimary();
  String? winnerAccountUuid;
  PaymentLinkClaimResult? submitted;
  await tester.pumpWidget(
    await buildBootstrappedZcashWalletApp(
      overrides: [
        paymentLinkClaimSubmitterProvider.overrideWith((ref) {
          final operations = ref.watch(paymentLinkOperationsProvider);
          return (session) async {
            if (competition) {
              await submitCompetitor(session, winnerAccountUuid!);
            } else {
              proxy.dropNextAcceptedSendResponse();
            }
            return submitted = await operations.claimPreparedLink(session);
          };
        }),
      ],
    ),
  );
  await importDesktopRegtestWallet(tester);
  winnerAccountUuid = await firstDesktopRegtestAccountUuid();
  await waitForForegroundSyncIdle(tester);
  await waitForPaymentLinkAccountBalance(
    tester,
    accountUuid: winnerAccountUuid,
    total: BigInt.from(125_000_000),
    spendable: BigInt.from(125_000_000),
  );
  await openPaymentLinksFromSettings(tester);
  final link = await createPaymentLinkForRegtest(
    tester,
    amountText: '0.1',
    artworkId: 'coin',
    message: competition ? 'Competition outcome' : 'Lost response outcome',
  );
  await minePaymentLinkRegtestBlocks(6);
  await waitForPaymentLinkHistoryTransaction(
    tester,
    accountUuid: winnerAccountUuid,
    txKind: 'sent',
    amount: BigInt.from(10_010_000),
    pending: false,
  );
  await waitForForegroundSyncIdle(tester);
  final winnerBefore = await readPaymentLinkAccountBalance(winnerAccountUuid);
  await importAdditionalDesktopRegtestWallet(tester);
  final receiver = (await desktopRegtestAccounts())
      .singleWhere((account) => account.uuid != winnerAccountUuid)
      .uuid;
  await waitForForegroundSyncIdle(tester);
  final receiverBefore = await readPaymentLinkAccountBalance(receiver);
  await openPaymentLinksFromSettings(tester);
  await claimPaymentLinkForRegtest(tester, link);
  await pumpUntil(
    tester,
    () => submitted != null,
    description: 'real claim broadcast result',
  );
  expect(submitted!.status, PaymentLinkClaimBroadcastStatus.pendingBroadcast);
  expect(submitted!.broadcastFailureKind, competition ? 'rejected' : 'unknown');
  if (!competition) {
    expect(proxy.droppedAcceptedResponseCount, 1);
    final record = await outcomeRecord(tester);
    await waitForPaymentLinkMempoolTxids(tester, record.claimTxids!.split(','));
  }
  await openOutcome(tester);
  expect(find.text('Hide card'), findsNothing);
  expect(
    await giftOutcomeContainer(
      tester,
    ).read(paymentLinkReceivedStoreProvider).countReceivingForAccount(receiver),
    1,
  );

  if (competition) {
    await minePaymentLinkRegtestBlocks(5);
    await checkOutcome(tester);
    await expectOutcomeText(tester, 'Checking result');
    var record = await outcomeRecord(tester);
    expect(record.isClaimInFlight, isTrue);
    expect(record.claimLink, isNotNull);
    await minePaymentLinkRegtestBlocks(1);
    await checkOutcome(tester);
    await expectOutcomeText(tester, 'Already claimed');
    record = await outcomeRecord(tester);
    expect(record.isClaimInFlight, isFalse);
    expect(record.availability, PaymentLinkAvailability.claimedElsewhere);
    expect(record.destinationAccountUuid, isNull);
    expect(record.claimLink!.toUri(), link.toUri());
    expect(
      await giftOutcomeContainer(tester)
          .read(paymentLinkReceivedStoreProvider)
          .countReceivingForAccount(receiver),
      0,
    );
    await waitForPaymentLinkAccountBalance(
      tester,
      accountUuid: winnerAccountUuid,
      total: winnerBefore.total + giftOutcomeAmount,
    );
    await waitForPaymentLinkAccountBalance(
      tester,
      accountUuid: receiver,
      total: receiverBefore.total,
    );
    final sends = proxy.sendTransactionCount;
    await checkOutcome(tester);
    await expectOutcomeText(tester, 'Already claimed');
    expect(proxy.sendTransactionCount, sends);
    await expectFreshObserver(link);
    await tapPaymentLinkText(tester, 'Hide card');
    expect((await outcomeRecord(tester)).archived, isTrue);
  }
  await writePaymentLinkRestartManifest(
    PaymentLinkRestartManifest(
      receiverAccountUuid: receiver,
      receiverStartingTotal: receiverBefore.total,
      claims: [PaymentLinkRestartClaim.fromLink(link)],
    ),
  );
  expect(await (await paymentLinkClaimWalletDirectory(link)).exists(), isTrue);
  retained = true;
  e2eLog(
    competition
        ? 'SCENARIO 1 PASS: one winner; loser resolved and archived for scenario 3'
        : 'SCENARIO 2 PREPARED: accepted transaction response lost; restart next',
  );
}
