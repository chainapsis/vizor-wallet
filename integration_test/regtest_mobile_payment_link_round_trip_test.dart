import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/navigation/vizor_deep_link.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

/// Mobile regtest E2E: the mobile twin of
/// regtest_payment_link_round_trip_test.dart. One app holds both regtest
/// accounts; the first creates and funds a Gift Card through Settings ›
/// My Gift Cards, the second pastes the card link, waits out the six
/// confirmations, claims it, and ends up credited.
///
/// The mobile create flow differs from desktop only in its surfaces: the
/// message editor is the card itself rather than a "Start typing..."
/// action, and claiming leaves the Gift Cards route for `/home`, so the
/// Received row is re-opened from Settings to watch it settle.
const _senderMnemonic =
    'winter shiver fetch refuse absurd mail pistol eight market lounge manual '
    'roast miracle ethics found child scare curve congress renew salute pig '
    'better used';
const _receiverMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';
const _giftAmountText = '0.1';
const _giftArtworkId = 'coin';
const _giftMessage = 'Congrats from the mobile payment link E2E!';
const _walletSpendableConfirmationTarget = 10;
final _giftAmountZatoshi = BigInt.from(10_000_000);
final _fundingAmountZatoshi = BigInt.from(10_010_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets(
    'creates, opens, and claims a Gift Card between two mobile accounts',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        await cleanupE2eWalletState();
        await cleanupMobileE2ePaymentLinkClaimWallets();
      });
      await cleanupE2eWalletState();
      await cleanupMobileE2ePaymentLinkClaimWallets();

      logE2e('pumping app for the mobile payment-link round trip');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());

      await importWalletViaPaste(
        tester,
        mnemonic: _senderMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '1.25 $mobileE2eTicker');
      final senderUuid = await accountUuidAtOrder(0);
      // The card fee quote only runs once the funds are spendable, so the
      // amount step's Continue would stay disabled without this.
      await _waitForSpendableAtLeast(
        tester,
        accountUuid: senderUuid,
        spendable: BigInt.from(125_000_000),
      );

      await _openGiftCardsFromSettings(tester);
      final link = await _createGiftCard(tester);
      expect(link.network, mobileE2eNetwork);
      expect(link.amountZatoshi, _giftAmountZatoshi);
      expect(link.presentation?.artworkId, _giftArtworkId);
      expect(link.presentation?.message, _giftMessage);

      final pendingFunding = await _waitForHistoryTransaction(
        tester,
        accountUuid: senderUuid,
        txKind: 'sent',
        amount: _fundingAmountZatoshi,
        pending: true,
      );
      await mineRegtestBlocks(kPaymentLinkShareConfirmationTarget);
      final minedFunding = await _waitForHistoryTransaction(
        tester,
        accountUuid: senderUuid,
        txKind: 'sent',
        amount: _fundingAmountZatoshi,
        pending: false,
        txid: pendingFunding.txidHex,
      );

      await tapAppButton(
        tester,
        const ValueKey('payment_link_mobile_ready_home_button'),
      );
      await _leaveGiftCards(tester);

      await openAddAccountFlow(tester);
      await importWalletViaPaste(
        tester,
        mnemonic: _receiverMnemonic,
        birthdayHeight: 1,
        isFirstWallet: false,
      );
      final receiverUuid = await accountUuidAtOrder(1);
      final receiverStartingBalance = await _readAccountBalance(receiverUuid);

      final operations = _paymentLinkOperations(tester);
      await Clipboard.setData(ClipboardData(text: link.toUri().toString()));
      await _openGiftCardsFromSettings(tester);
      await tapAppButton(
        tester,
        const ValueKey('payment_links_mobile_redeem_button'),
      );
      await tapAppButton(
        tester,
        const ValueKey('payment_link_mobile_paste_button'),
        timeout: const Duration(minutes: 1),
      );

      // One confirmation in: the card is held behind the six-confirmation
      // gate, so the claim action must not be offered yet.
      await pumpUntil(
        tester,
        () => tester.any(find.textContaining('Waiting for 6 confirmations.')),
        description: 'the received card to wait for six confirmations',
        timeout: const Duration(minutes: 2),
      );
      expect(
        find.byKey(const ValueKey('payment_link_mobile_claim_button')),
        findsNothing,
      );

      await mineRegtestBlocks(
        kPaymentLinkClaimConfirmationTarget -
            kPaymentLinkShareConfirmationTarget,
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('payment_link_mobile_claim_button')),
        ),
        description: 'the claim action after six confirmations',
        timeout: const Duration(minutes: 3),
      );
      await _revealGiftMessage(tester);
      expect(find.text(_giftMessage), findsOneWidget);

      await tapAppButton(
        tester,
        const ValueKey('payment_link_mobile_claim_button'),
      );
      // Claiming leaves the Gift Cards route on mobile.
      await waitForHome(tester);

      final receivingRecord = await _waitForReceivedRecord(
        tester,
        operations,
        address: link.address,
        status: PaymentLinkReceivedStatus.receiving,
        description: 'the claim to persist as Receiving',
      );
      expect(receivingRecord.claimTxids, isNotEmpty);
      expect(
        receivingRecord.claimLink?.toUri().toString(),
        link.toUri().toString(),
      );

      final pendingClaim = await _waitForHistoryTransaction(
        tester,
        accountUuid: receiverUuid,
        txKind: 'receiving',
        amount: _giftAmountZatoshi,
        pending: true,
      );
      expect(pendingClaim.txidHex, isNot(minedFunding.txidHex));

      // One block past the target so the reconciler's timer cannot land on
      // the exact confirmation boundary and decide the outcome.
      await mineRegtestBlocks(kPaymentLinkClaimConfirmationTarget + 1);
      final minedClaim = await _waitForHistoryTransaction(
        tester,
        accountUuid: receiverUuid,
        txKind: 'received',
        amount: _giftAmountZatoshi,
        pending: false,
        txid: pendingClaim.txidHex,
      );
      expect(minedClaim.txidHex, isNot(minedFunding.txidHex));

      final receivedRecord = await _waitForReceivedRecord(
        tester,
        operations,
        address: link.address,
        status: PaymentLinkReceivedStatus.received,
        description: 'the mined claim to settle as Received',
      );
      expect(receivedRecord.claimLink, isNull);

      await _openGiftCardsFromSettings(tester);
      await tapWidget(
        tester,
        const ValueKey('payment_links_mobile_received_tab'),
      );
      final receivedRow = find.byKey(
        ValueKey('payment_link_mobile_received_${link.address}'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.descendant(of: receivedRow, matching: find.text('Received')),
        ),
        description: 'the received row to read Received',
        timeout: const Duration(minutes: 2),
      );
      await _leaveGiftCards(tester);

      // The Gift Card is received after six confirmations; the receiver's
      // ordinary wallet still needs ten before that value is spendable.
      await mineRegtestBlocks(
        _walletSpendableConfirmationTarget -
            kPaymentLinkClaimConfirmationTarget -
            1,
      );
      final expectedTotal = receiverStartingBalance.total + _giftAmountZatoshi;
      await _waitForAccountBalance(
        tester,
        accountUuid: receiverUuid,
        total: expectedTotal,
        spendable: receiverStartingBalance.spendable + _giftAmountZatoshi,
      );
      await openHomeTab(tester);
      final expectedBalanceText = ZecAmount.fromZatoshi(
        expectedTotal,
      ).compactBalance.amountText;
      await waitForShieldedBalance(
        tester,
        '$expectedBalanceText $mobileE2eTicker',
      );
      logE2e('mobile payment-link round trip completed');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

PaymentLinkOperations _paymentLinkOperations(WidgetTester tester) {
  return ProviderScope.containerOf(
    tester.element(find.byType(ZcashWalletApp)),
  ).read(paymentLinkOperationsProvider);
}

/// Home tab → Settings tab → My Gift Cards.
Future<void> _openGiftCardsFromSettings(WidgetTester tester) async {
  await tapUntilVisible(
    tester,
    trigger: find.bySemanticsLabel('Settings'),
    outcome: find.byKey(const ValueKey('mobile_settings_gift_cards_row')),
    description: 'the settings tab',
    timeout: const Duration(minutes: 1),
  );
  await tapUntilVisible(
    tester,
    trigger: find.byKey(const ValueKey('mobile_settings_gift_cards_row')),
    outcome: find.byKey(const ValueKey('payment_links_mobile_screen')),
    description: 'the Gift Cards screen',
    timeout: const Duration(minutes: 1),
  );
}

/// Pops the Gift Cards route back to Settings and returns to the Home tab.
Future<void> _leaveGiftCards(WidgetTester tester) async {
  await tapBack(tester);
  await openHomeTab(tester);
}

/// Create → amount + design → message → review → funded card, returning the
/// link the ready page copies to the clipboard.
Future<VizorPaymentLink> _createGiftCard(WidgetTester tester) async {
  await tapAppButton(
    tester,
    const ValueKey('payment_links_mobile_create_button'),
  );
  await enterText(
    tester,
    const ValueKey('payment_link_amount_editor'),
    _giftAmountText,
  );
  await _selectCardArtwork(tester, _giftArtworkId);
  await tapAppButton(
    tester,
    const ValueKey('payment_link_mobile_amount_continue_button'),
    timeout: const Duration(minutes: 2),
  );
  await enterText(
    tester,
    const ValueKey('payment_link_message_editor'),
    _giftMessage,
  );
  await tapAppButton(
    tester,
    const ValueKey('payment_link_mobile_message_continue_button'),
  );
  await tapAppButton(
    tester,
    const ValueKey('payment_link_mobile_review_continue_button'),
    timeout: const Duration(minutes: 1),
  );
  await tapAppButton(
    tester,
    const ValueKey('payment_link_mobile_copy_button'),
    timeout: const Duration(minutes: 3),
  );
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final rawLink = data?.text?.trim() ?? '';
  if (!rawLink.startsWith(
    'https://${VizorDeepLink.host}${VizorDeepLink.paymentLinkPath}#v1=',
  )) {
    fail('The clipboard did not contain a Vizor payment link: "$rawLink"');
  }
  logE2e('copied the funded Gift Card link');
  return VizorPaymentLink.parse(rawLink);
}

/// The design rail cycles endlessly and is narrower than the artwork list,
/// so the wanted design is nudged into the viewport before it is tapped.
Future<void> _selectCardArtwork(WidgetTester tester, String artworkName) async {
  final selector = find.byKey(
    ValueKey('payment_link_card_selector_$artworkName'),
  );
  final rail = find.byKey(const ValueKey('payment_link_card_selector_scroll'));
  await pumpUntil(
    tester,
    () => tester.any(rail),
    description: 'the card design rail',
  );
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!tester.any(selector.hitTestable())) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out reaching the "$artworkName" card design.');
    }
    await tester.drag(rail.first, const Offset(-80, 0));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.tap(selector.hitTestable().first);
  await tester.pump(const Duration(milliseconds: 500));
  logE2e('selected the "$artworkName" card design');
}

/// The received card's message sits behind an unkeyed flip action.
Future<void> _revealGiftMessage(WidgetTester tester) async {
  final finder = find.bySemanticsLabel('Reveal gift card message');
  await pumpUntil(
    tester,
    () => tester.any(finder),
    description: 'the reveal-message action',
  );
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 600));
}

Future<PaymentLinkReceivedRecord> _waitForReceivedRecord(
  WidgetTester tester,
  PaymentLinkOperations operations, {
  required String address,
  required PaymentLinkReceivedStatus status,
  required String description,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastStatuses = '<not read>';
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final records = await operations.loadReceivedLinkRecoveries();
      lastStatuses = records
          .map((record) => '${record.address}:${record.status.name}')
          .join(', ');
      for (final record in records) {
        if (record.address == address && record.status == status) return record;
      }
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final error = lastError == null ? '' : ' Last error: $lastError';
  fail('Timed out waiting for $description. Statuses: $lastStatuses.$error');
}

Future<rust_sync.TransactionInfo> _waitForHistoryTransaction(
  WidgetTester tester, {
  required String accountUuid,
  required String txKind,
  required BigInt amount,
  required bool pending,
  String? txid,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(timeout);
  var lastHistory = '<not read>';
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final history = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        limit: 50,
        accountUuid: accountUuid,
      );
      lastHistory = history
          .map(
            (tx) =>
                '${tx.txidHex}:${tx.txKind}:${tx.displayAmount}:'
                'mined=${tx.minedHeight}',
          )
          .join(', ');
      for (final tx in history) {
        if (tx.txKind == txKind &&
            tx.displayAmount == amount &&
            (tx.minedHeight == BigInt.zero) == pending &&
            !tx.expiredUnmined &&
            (txid == null || tx.txidHex == txid)) {
          return tx;
        }
      }
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final error = lastError == null ? '' : ' Last error: $lastError';
  fail(
    'Timed out waiting for $txKind amount=$amount pending=$pending. '
    'History: $lastHistory.$error',
  );
}

Future<rust_sync.WalletBalance> _readAccountBalance(String accountUuid) async {
  return rust_sync.getBalance(
    dbPath: await getWalletDbPath(),
    network: mobileE2eNetwork,
    accountUuid: accountUuid,
  );
}

Future<void> _waitForSpendableAtLeast(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt spendable,
  Duration timeout = const Duration(minutes: 4),
}) async {
  rust_sync.WalletBalance? last;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await _readAccountBalance(accountUuid);
      if (last.spendable >= spendable) return;
    } catch (_) {
      // The foreground sync can briefly own the wallet connection.
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for spendable>=$spendable. '
    'Last spendable=${last?.spendable}, total=${last?.total}.',
  );
}

Future<void> _waitForAccountBalance(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt total,
  required BigInt spendable,
  Duration timeout = const Duration(minutes: 4),
}) async {
  rust_sync.WalletBalance? last;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await _readAccountBalance(accountUuid);
      if (last.total == total && last.spendable == spendable) return;
    } catch (_) {
      // The foreground sync can briefly own the wallet connection.
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for total=$total spendable=$spendable. '
    'Last total=${last?.total}, spendable=${last?.spendable}.',
  );
}
