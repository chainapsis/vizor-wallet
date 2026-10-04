@Tags(['mobile'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_claim_flow_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/mobile_regtest_flow.dart';

// Uses the real regtest chain, secure store, account DB, claim coordinator and
// native UI. Never log or capture recovery phrases or bearer card links.
// Backup only exercises birthday copy; bearer input uses the pasteboard.
// Run via scripts/e2e/flutter-ios-regtest-mobile-gift-onboarding.sh.
final _giftAmount = BigInt.from(10_000_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'creates a wallet from a gift, receives funds, and completes Home setup',
    (tester) async {
      await _mountFreshApp(tester);
      final link = await _newGift();

      // An unfunded card offers an exit without saving a passcode or account.
      // A freshly created card intentionally allows setup during its funding
      // grace period, so advance beyond that period before testing the exit.
      await mineRegtestBlocks(kPaymentLinkFreshCardGraceBlocks);
      await _inspectGift(tester, link);
      await tapAppButton(tester, const ValueKey('gift_claim_go_back'));
      expect(
        _container(tester).read(accountProvider).value?.hasAccounts,
        isFalse,
      );
      expect(await AppSecureStore.instance.isPasswordConfigured(), isFalse);

      await _fundGift(link, confirmations: kPaymentLinkClaimConfirmationTarget);
      await _inspectGift(tester, link);
      await _createGiftWallet(tester, name: 'Gift recipient');

      final uuid = await accountUuidAtOrder(0);
      final account = _container(
        tester,
      ).read(accountProvider).value!.activeAccount!;
      expect(account.name, 'Gift recipient');
      expect(account.setupPending, isTrue);
      expect(account.giftEducationPending, isTrue);
      final recipientMnemonic = await AppSecureStore.instance
          .readAccountMnemonic(uuid);
      expect(recipientMnemonic?.split(' '), hasLength(24));
      expect(recipientMnemonic, isNot(link.mnemonic));
      await _assertClaimReceived(tester, link, uuid);

      // Home has two manually selected setup banners, and no Gift banner.
      final carousel = find.byKey(ValueKey('mobile_home_setup_carousel_$uuid'));
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(const ValueKey('mobile_home_backup'))),
        description: 'backup banner',
      );
      await tester.drag(carousel, const Offset(-160, 0));
      await settle(tester, const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('mobile_home_zcash_education')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsNothing);
      await tapWidget(
        tester,
        const ValueKey('mobile_home_carousel_indicator_0'),
      );
      await settle(tester, const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsOneWidget);

      await tapWidget(tester, const ValueKey('mobile_home_backup'));
      await tapWidget(
        tester,
        const ValueKey('mobile_seed_backup_remind_later'),
      );
      await waitForHome(tester);
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsNothing);
      final deferred = _container(
        tester,
      ).read(accountProvider).value!.activeAccount!;
      expect(deferred.setupPending, isTrue);
      expect(
        deferred.backupReminderSnoozedUntilUtc?.isAfter(DateTime.now().toUtc()),
        isTrue,
      );

      // Settings still permits backup while the Home reminder is snoozed.
      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Settings'),
        outcome: find.byKey(const ValueKey('mobile_settings_seed_row')),
        description: 'Settings backup entry',
      );
      await tapWidget(tester, const ValueKey('mobile_settings_seed_row'));
      await enterPasscode(tester, mobileE2ePasscode);
      await pumpUntil(
        tester,
        () =>
            tester.any(find.bySemanticsLabel('Copy Birthday block height')) &&
            tester.any(find.bySemanticsLabel('Copy Birthday date')),
        description: 'loaded backup birthday metadata',
        timeout: const Duration(minutes: 1),
      );
      final birthday = await rust_sync.getExportBirthdayHeight(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: uuid,
      );
      final heightCopy = find.bySemanticsLabel('Copy Birthday block height');
      await tester.ensureVisible(heightCopy);
      await tester.tap(heightCopy);
      await pumpUntil(
        tester,
        () => tester.any(find.text('Birthday height copied')),
        description: 'birthday copy confirmation',
      );
      expect((await Clipboard.getData('text/plain'))?.text, '$birthday');
      await Clipboard.setData(const ClipboardData(text: ''));
      await tapAppButton(tester, const ValueKey('mobile_seed_backed_up'));
      await openHomeTab(tester);
      expect(
        _container(
          tester,
        ).read(accountProvider).value!.activeAccount!.setupPending,
        isFalse,
      );
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsNothing);

      await tapWidget(tester, const ValueKey('mobile_home_zcash_education'));
      await tapAppButton(tester, const ValueKey('mobile_intro_continue'));
      await tapAppButton(
        tester,
        const ValueKey('mobile_address_types_continue'),
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_things_to_know_continue'),
      );
      await waitForHome(tester);
      expect(
        _container(
          tester,
        ).read(accountProvider).value!.activeAccount!.giftEducationPending,
        isFalse,
      );
      expect(carousel, findsNothing);
      logE2e(
        'Gift creation, real receipt, manual carousel, backup and education verified',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  testWidgets(
    'imports the first wallet from a gift and claims into the imported account',
    (tester) async {
      await _mountFreshApp(tester);
      final link = await _newGift();
      await _fundGift(link, confirmations: kPaymentLinkClaimConfirmationTarget);
      final recipient = await rust_wallet.generateSoftwareAccount(
        network: mobileE2eNetwork,
      );
      await _inspectGift(tester, link);
      await tapAppButton(
        tester,
        const ValueKey('gift_claim_claim_with_an_existing_wallet'),
      );
      await importPassphraseViaPaste(
        tester,
        mnemonic: recipient.mnemonic,
        birthdayHeight: link.birthdayHeight,
        isFirstWallet: true,
      );
      final uuid = await accountUuidAtOrder(0);
      expect(await AppSecureStore.instance.isPasswordConfigured(), isTrue);
      expect(
        (await AppSecureStore.instance.readAccountMnemonic(uuid))?.isNotEmpty,
        isTrue,
      );
      expect(
        await AppSecureStore.instance.readPlain(
              kGiftClaimImportHandoffStorageKey,
            ) ==
            null,
        isTrue,
      );
      await _assertClaimReceived(tester, link, uuid);
      logE2e('Gift first-wallet import and automatic receipt verified');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'removing a waiting gift recipient removes its unclaimed card and temporary DB',
    (tester) async {
      await _mountFreshApp(tester);
      final link = await _newGift();
      await _fundGift(link, confirmations: 1);
      await _inspectGift(tester, link);
      await _createGiftWallet(tester, name: 'Waiting recipient');
      final recipientUuid = await accountUuidAtOrder(0);
      final record = await _waitForRecord(
        tester,
        link,
        (record) =>
            record?.status == PaymentLinkReceivedStatus.readyToClaim &&
            record?.setupAccountUuid == recipientUuid,
      );
      expect(record?.claimTxids, isNull);
      final directory = await _claimDirectory(link);
      expect(await directory.exists(), isTrue);

      // No blocks are mined during additional import/removal: the Gift cannot
      // become spendable or turn into an in-flight claim in this scenario.
      final other = await rust_wallet.generateSoftwareAccount(
        network: mobileE2eNetwork,
      );
      await openAddAccountFlow(tester);
      expect(
        find.byKey(const ValueKey('mobile_welcome_redeem_card')),
        findsNothing,
      );
      await importWalletViaPaste(
        tester,
        mnemonic: other.mnemonic,
        birthdayHeight: link.birthdayHeight,
        isFirstWallet: false,
      );
      final survivorUuid = await accountUuidAtOrder(1);
      await openAccountsSheet(tester);
      await tapUntilVisible(
        tester,
        trigger: find.text('Manage accounts'),
        outcome: find.byKey(ValueKey('mobile_accounts_menu_$recipientUuid')),
        description: 'manage gift recipient',
      );
      await tapWidget(tester, ValueKey('mobile_accounts_menu_$recipientUuid'));
      await tapWidget(tester, const ValueKey('mobile_account_menu_remove'));
      await tapAppButton(
        tester,
        const ValueKey('mobile_account_remove_confirm'),
      );
      await _waitForRecord(tester, link, (record) => record == null);
      expect(await directory.exists(), isFalse);
      final accounts = _container(tester).read(accountProvider).value!;
      expect(accounts.accounts.map((a) => a.uuid), [survivorUuid]);
      logE2e(
        'Waiting Gift recipient deletion, Card deletion and temporary DB cleanup verified',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ZcashWalletApp)));

Future<void> _mountFreshApp(WidgetTester tester) async {
  addTearDown(() async {
    if (tester.any(find.byType(ZcashWalletApp))) {
      await _container(tester)
          .read(paymentLinkClaimCoordinatorProvider)
          .quiesceAndDrain()
          .timeout(const Duration(minutes: 3));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await Clipboard.setData(const ClipboardData(text: ''));
    await cleanupE2eWalletState();
    await cleanupMobileE2ePaymentLinkClaimWallets();
  });
  await cleanupE2eWalletState();
  await cleanupMobileE2ePaymentLinkClaimWallets();
  await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
}

Future<VizorPaymentLink> _newGift() async {
  final tip = await zcashdRpc<int>('getblockcount');
  final gift = await rust_wallet.generateSoftwareAccount(
    network: mobileE2eNetwork,
  );
  expect(gift.mnemonic.split(' '), hasLength(12));
  return VizorPaymentLink(
    network: mobileE2eNetwork,
    address: gift.unifiedAddress,
    amountZatoshi: _giftAmount,
    mnemonic: gift.mnemonic,
    birthdayHeight: tip,
    label: 'Onboarding E2E',
    createdAt: DateTime.now().toUtc(),
    presentation: const PaymentLinkPresentation(artworkId: 'coin'),
  );
}

Future<void> _fundGift(
  VizorPaymentLink link, {
  required int confirmations,
}) async {
  await postDriver('/fund-confirmed', {
    'address': link.address,
    // Recipient value plus the actual Orchard claim fee.
    'amount': '0.1001',
    'confirmations': confirmations,
  }, timeout: const Duration(minutes: 5));
}

Future<void> _inspectGift(WidgetTester tester, VizorPaymentLink link) async {
  await tapWidget(tester, const ValueKey('mobile_welcome_redeem_card'));
  final uri = link.toShareUri();
  expect(uri.fragment, startsWith('v3='));
  await Clipboard.setData(ClipboardData(text: uri.toString()));
  await tapAppButton(
    tester,
    const ValueKey('payment_link_mobile_paste_button'),
  );
  await Clipboard.setData(const ClipboardData(text: ''));
  await pumpUntil(
    tester,
    () =>
        _container(tester).read(giftClaimFlowProvider)?.phase ==
        GiftClaimPhase.inspected,
    description: 'real Gift inspection',
    timeout: const Duration(minutes: 3),
  );
  final inspected = _container(tester).read(giftClaimFlowProvider)!.inspection!;
  expect(inspected.link.mnemonic, link.mnemonic);
  expect(inspected.link.address, link.address);
}

Future<void> _createGiftWallet(
  WidgetTester tester, {
  required String name,
}) async {
  await tapAppButton(
    tester,
    const ValueKey('gift_claim_create_a_wallet_to_claim'),
  );
  await enterPasscode(tester, mobileE2ePasscode);
  await enterPasscode(tester, mobileE2ePasscode);
  // Cupertino keeps the outgoing passcode page mounted during its transition.
  // Finish that transition before bringing up the name field's native keyboard.
  await settle(tester, const Duration(milliseconds: 600));
  await enterText(
    tester,
    const ValueKey('mobile_customise_account_name_field'),
    name,
  );
  await tapAppButton(
    tester,
    const ValueKey('mobile_customise_account_continue'),
    timeout: const Duration(minutes: 2),
  );
  await tapWidget(
    tester,
    const ValueKey('mobile_biometrics_not_now'),
    timeout: const Duration(minutes: 2),
  );
  await waitForHome(tester);
}

Future<PaymentLinkReceivedRecord?> _waitForRecord(
  WidgetTester tester,
  VizorPaymentLink link,
  bool Function(PaymentLinkReceivedRecord?) matches,
) async {
  final store = _container(tester).read(paymentLinkReceivedStoreProvider);
  final deadline = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(deadline)) {
    final record = await store.find(link.address);
    if (matches(record)) return record;
    await settle(tester, const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for the persisted Gift lifecycle state.');
}

Future<Directory> _claimDirectory(VizorPaymentLink link) async => Directory(
  '${(await getWalletSupportDirectory()).path}${Platform.pathSeparator}'
  '${paymentLinkClaimWalletDirectoryName(link)}',
);

Future<void> _assertClaimReceived(
  WidgetTester tester,
  VizorPaymentLink link,
  String uuid,
) async {
  expect(find.byKey(const ValueKey('mobile_home_receive')), findsOneWidget);
  final receiving = await _waitForRecord(
    tester,
    link,
    (record) => record?.status == PaymentLinkReceivedStatus.receiving,
  );
  expect(receiving?.destinationAccountUuid, uuid);
  expect(receiving?.claimTxids?.isNotEmpty, isTrue);
  final txid = receiving!.claimTxids!;

  await mineRegtestBlocks(kPaymentLinkReceiptConfirmationTarget);
  await waitForShieldedBalance(tester, '0.10 $mobileE2eTicker');
  expect(find.byKey(const ValueKey('mobile_home_send')), findsOneWidget);
  await pumpUntil(
    tester,
    () => tester.any(find.text('Redeemed a gift card')),
    description: 'Gift transaction in Home activity',
    timeout: const Duration(minutes: 2),
  );
  await _waitForRecord(
    tester,
    link,
    (record) => record?.status == PaymentLinkReceivedStatus.received,
  );
  final history = await rust_sync.getTransactionHistory(
    dbPath: await getWalletDbPath(),
    network: mobileE2eNetwork,
    accountUuid: uuid,
    limit: 10,
  );
  expect(
    history.any(
      (tx) =>
          tx.txidHex == txid &&
          tx.txKind == 'received' &&
          tx.displayAmount == _giftAmount &&
          tx.minedHeight > BigInt.zero &&
          !tx.expiredUnmined,
    ),
    isTrue,
  );

  await mineRegtestBlocks(
    kPaymentLinkClaimRecoveryConfirmationTarget -
        kPaymentLinkReceiptConfirmationTarget,
  );
  final finalized = await _waitForRecord(
    tester,
    link,
    (record) =>
        record?.status == PaymentLinkReceivedStatus.received &&
        record?.claimLink == null,
  );
  expect(finalized?.claimTxids, txid);
  expect(await (await _claimDirectory(link)).exists(), isFalse);
}
