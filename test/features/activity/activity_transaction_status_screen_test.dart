import 'package:flutter/material.dart' show MaterialApp, ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/features/activity/widgets/gift_card_activity_detail_view.dart';
import 'package:zcash_wallet/src/features/activity/widgets/received_receipt_view.dart';
import 'package:zcash_wallet/src/features/activity/widgets/shielded_receipt_view.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_status_content_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/verify_address_modal.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import '../../fixtures/private_shielding_activity.dart';
import '../../fakes/fake_enhance_pir_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

const _txidHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const _recipientAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _receivingAddress = 't1Z9N3oVYrYDpnbqDcXJpuLrGpcSLDgHXyo';

const _transparentSenderAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

final _blockTime = BigInt.from(1764150000);

void main() {
  if (const String.fromEnvironment('GIFT_CARD_CAPTURE_DIR').isNotEmpty) {
    setUpAll(loadFigmaCompareFonts);
  }
  testWidgets('pending claim transaction ID opens the broadcast hash', (
    tester,
  ) async {
    const displayTxid =
        '012c6894d79c62d7f49659bf2405b6b67fda282aa89127539d77de76523be0d6';
    final protocolTxid = paymentLinkBroadcastTxidsToProtocolOrder(displayTxid);
    final launched = <String>[];
    final copied = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
        return false;
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: protocolTxid,
        txKind: 'receiving',
        initialTransaction: _transaction(
          txidHex: protocolTxid,
          txKind: 'receiving',
          minedHeight: BigInt.zero,
        ),
        giftCard: GiftCardActivityMetadata(
          kind: GiftCardActivityKind.redeemed,
          amountZatoshi: BigInt.from(100000),
          artworkId: 'ruby',
          message: null,
          isClaimInFlight: true,
        ),
      ),
    );
    expect(find.text(truncatedTxid(displayTxid)), findsOneWidget);
    await tester.tap(find.text(truncatedTxid(displayTxid)));
    await tester.pump();
    expect(launched, hasLength(1));
    expect(Uri.parse(launched.single).path, '/tx/$displayTxid');
    expect(copied, [displayTxid]);
  });

  for (final settings in [(false, false), (true, true)]) {
    testWidgets('hides saved fiat for disabled pricing or privacy $settings', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        pricingEnabled: settings.$1,
        privacyEnabled: settings.$2,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'received',
          initialTransaction: _transaction(txKind: 'received'),
          giftCard: GiftCardActivityMetadata(
            kind: GiftCardActivityKind.redeemed,
            amountZatoshi: BigInt.from(445000000),
            artworkId: 'ruby',
            message: null,
            fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 142.23),
          ),
        ),
      );
      expect(find.text(r'$142.23'), findsNothing);
    });
  }

  testWidgets(
    'an expired claim leg stays pending while the card is receiving',
    (tester) async {
      await _pumpScreen(
        tester,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'receiving',
          initialTransaction: _transaction(
            txKind: 'receiving',
            minedHeight: BigInt.zero,
            expiredUnmined: true,
          ),
          giftCard: GiftCardActivityMetadata(
            kind: GiftCardActivityKind.redeemed,
            amountZatoshi: BigInt.from(100000),
            artworkId: 'ruby',
            message: null,
            isClaimInFlight: true,
          ),
        ),
      );
      final view = tester.widget<GiftCardActivityDetailView>(
        find.byType(GiftCardActivityDetailView),
      );
      expect(view.isInFlight, isTrue);
      expect(view.isFailed, isFalse);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Failed'), findsNothing);
      expect(find.text('Refunded'), findsNothing);
    },
  );

  testWidgets('private gift card amount has one currency suffix', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      privacyEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(txKind: 'sent'),
        giftCard: GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          claimFeeReserveZatoshi: BigInt.from(10000),
          amountZatoshi: BigInt.from(100000),
          artworkId: 'ruby',
          message: null,
          fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 142.23),
        ),
      ),
    );
    final card = find.byType(GiftCardActivityDetailView);
    expect(
      tester.widget<GiftCardActivityDetailView>(card).amountText,
      '******',
    );
    expect(
      find.descendant(of: card, matching: find.text('ZEC')),
      findsOneWidget,
    );
    expect(find.text('0.001'), findsNothing);
    expect(find.text(r'$142.23'), findsNothing);
    const captureDir = String.fromEnvironment('GIFT_CARD_CAPTURE_DIR');
    if (captureDir.isNotEmpty) {
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();

      await expectLater(
        card,
        matchesGoldenFile('$captureDir/desktop-private-detail.png'),
      );
    }
  });

  testWidgets('renders created Gift Card activity metadata', (tester) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(10000),
        ),
        giftCard: GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          amountZatoshi: BigInt.from(100000),
          artworkId: 'ruby',
          message: 'Happy birthday!',
          fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 142.23),
          claimFeeReserveZatoshi: BigInt.from(20000),
        ),
      ),
    );

    expect(find.byType(GiftCardActivityDetailView), findsOneWidget);
    expect(find.text('Created a gift card'), findsOneWidget);
    expect(find.text('Happy birthday!'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('0.001'), findsOneWidget);
    expect(find.text('120'), findsNothing);
    expect(find.text('Card fee'), findsOneWidget);
    expect(find.text('0.0003 ZEC'), findsOneWidget);
    expect(find.text(r'$142.23'), findsOneWidget);
  });

  for (final privateQueries in [false, true]) {
    testWidgets(
      'batch unknown fees preserve public presentation, private=$privateQueries',
      (tester) async {
        await _pumpScreen(
          tester,
          privateQueriesEnabled: privateQueries,
          args: ActivityTransactionStatusArgs(
            txidHex: _txidHex,
            txKind: 'sent',
            initialTransaction: _transaction(
              txKind: 'sent',
              fee: BigInt.zero,
              feeState: rust_sync.TransactionFeeState.unknown,
            ),
            giftCard: GiftCardActivityMetadata(
              kind: GiftCardActivityKind.created,
              amountZatoshi: BigInt.from(200000000),
              amountPerCardZatoshi: BigInt.from(10000000),
              claimFeeReserveZatoshi: BigInt.from(200000),
              batchCount: 20,
              artworkId: 'ruby',
              message: null,
            ),
          ),
        );
        final batch = tester
            .widget<GiftCardActivityDetailView>(
              find.byType(GiftCardActivityDetailView),
            )
            .batch!;
        if (privateQueries) {
          expect(find.text('Unknown'), findsOneWidget);
          expect(batch.breakdownText, contains('Network fee Unknown'));
          expect(batch.breakdownText, isNot(contains('Network fee 0 ZEC')));
          expect(find.text('2.002 ZEC'), findsNothing);
        } else {
          expect(find.text('Unknown'), findsNothing);
          expect(find.text('2.002 ZEC'), findsOneWidget);
          expect(batch.breakdownText, contains('Network fee 0 ZEC'));
        }
      },
    );
  }

  testWidgets('batch known zero fee has an exact total in private queries', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      privateQueriesEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(txKind: 'sent', fee: BigInt.zero),
        giftCard: GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          amountZatoshi: BigInt.from(200000000),
          amountPerCardZatoshi: BigInt.from(10000000),
          claimFeeReserveZatoshi: BigInt.from(200000),
          batchCount: 20,
          artworkId: 'ruby',
          message: null,
        ),
      ),
    );
    expect(find.text('2.002 ZEC'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets(
    'older desktop receipt refreshes on sync completion without recent changes',
    (tester) async {
      var transaction = _transaction(
        txKind: 'sent',
        feeState: rust_sync.TransactionFeeState.unknown,
        detailsComplete: false,
        provisional: true,
      );
      var loads = 0;
      await _pumpScreen(
        tester,
        privateQueriesEnabled: true,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'sent',
          initialTransaction: transaction,
        ),
        historyLoader: (_) async {
          loads++;
          return [transaction];
        },
        detailLoader: (_, tx) async => _detail(txKind: tx.txKind),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityTransactionStatusScreen)),
      );
      final sync = container.read(syncProvider.notifier) as FakeSyncNotifier;
      final recent = List.generate(
        10,
        (i) => _transaction(
          txidHex: '${i + 1}'.padLeft(64, '0'),
          txKind: 'received',
        ),
      );
      sync.emit(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
          recentTransactions: recent,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = loads;
      transaction = _transaction(txKind: 'shielded', fee: BigInt.from(10000));
      sync.emit(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          recentTransactions: recent,
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, before + 1);
      expect(find.byType(ShieldedReceiptView), findsOneWidget);
      expect(find.text('Incomplete'), findsNothing);
      expect(find.text('Unknown'), findsNothing);
      sync.emit(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          percentage: 1,
          recentTransactions: recent,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        loads,
        before + 1,
        reason: 'unchanged completed snapshots do not reload',
      );
    },
  );

  testWidgets('renders one receipt for a created gift card batch', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(150000),
        ),
        giftCard: GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          amountZatoshi: BigInt.from(200000000),
          amountPerCardZatoshi: BigInt.from(10000000),
          claimFeeReserveZatoshi: BigInt.from(200000),
          batchCount: 20,
          artworkId: 'ruby',
          message: 'Enjoy the celebration!',
        ),
      ),
    );

    expect(
      tester
          .widget<GiftCardActivityDetailView>(
            find.byType(GiftCardActivityDetailView),
          )
          .batch
          ?.count,
      20,
    );
    expect(find.text('Created 20 gift cards'), findsOneWidget);
    expect(find.text('2.0035 ZEC'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('failed batch receipt does not claim funds were spent', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          expiredUnmined: true,
          fee: BigInt.from(150000),
        ),
        giftCard: GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          amountZatoshi: BigInt.from(200000000),
          amountPerCardZatoshi: BigInt.from(10000000),
          claimFeeReserveZatoshi: BigInt.from(200000),
          batchCount: 20,
          artworkId: 'ruby',
          message: null,
        ),
      ),
    );
    expect(find.text('Gift card group failed'), findsOneWidget);
    expect(find.text('Planned total'), findsOneWidget);
    expect(find.text('Total spent'), findsNothing);
  });

  testWidgets('renders redeemed Gift Card activity metadata', (tester) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(txKind: 'received'),
        giftCard: GiftCardActivityMetadata(
          kind: GiftCardActivityKind.redeemed,
          amountZatoshi: BigInt.from(100000),
          artworkId: 'crystal',
          message: null,
        ),
      ),
    );

    expect(find.byType(GiftCardActivityDetailView), findsOneWidget);
    expect(find.text('Redeemed a gift card'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
  });

  testWidgets('resolves Gift Card metadata the tapped row could not carry', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(10000),
        ),
      ),
      giftCardActivityIndex: GiftCardActivityIndex(
        createdTxids: {_txidHex},
        createdMetadataByTxid: {
          _txidHex: GiftCardActivityMetadata(
            claimFeeReserveZatoshi: BigInt.from(10000),
            kind: GiftCardActivityKind.created,
            amountZatoshi: BigInt.from(100000),
            artworkId: 'ruby',
            message: 'Happy birthday!',
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GiftCardActivityDetailView), findsOneWidget);
    expect(find.text('Created a gift card'), findsOneWidget);
    expect(find.text('Happy birthday!'), findsOneWidget);
  });

  testWidgets('drops passed-in Gift Card metadata after an account switch', (
    tester,
  ) async {
    final accountNotifier = _SwitchableAccountNotifier();
    await _pumpScreen(
      tester,
      accountNotifier: accountNotifier,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(10000),
        ),
        giftCard: GiftCardActivityMetadata(
          claimFeeReserveZatoshi: BigInt.from(10000),
          kind: GiftCardActivityKind.created,
          amountZatoshi: BigInt.from(100000),
          artworkId: 'ruby',
          message: 'Happy birthday!',
        ),
      ),
    );

    expect(find.byType(GiftCardActivityDetailView), findsOneWidget);

    accountNotifier.setActiveAccount('account-2');
    await tester.pump();
    await tester.pump();

    expect(find.byType(GiftCardActivityDetailView), findsNothing);
    expect(find.text('Created a gift card'), findsNothing);
    expect(find.text('Happy birthday!'), findsNothing);
  });

  testWidgets('renders the redesigned receipt for a confirmed receive', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(txKind: 'received'),
        initialDetail: _detail(
          txKind: 'received',
          memo: 'Thanks for lunch',
          sourcePool: 'unknown',
          outputs: [
            rust_sync.TransactionDetailOutput(
              usesOrchardReceiver: false,
              address: _receivingAddress,
              amountZatoshi: BigInt.from(12000000000),
              pool: 'transparent',
            ),
          ],
        ),
      ),
    );

    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Received successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('120.00 ZEC'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Unknown sender'), findsOneWidget);
    // Our receiving output's address shows as the Amount sub-line.
    expect(find.text('t1Z9N3o ... DgHXyo'), findsOneWidget);
    expect(find.text('Thanks for lunch'), findsOneWidget);
    expect(find.text(_expectedTimestamp(_blockTime)), findsOneWidget);
    // Zero fee on an inbound transaction hides the network fee row.
    expect(find.text('Network fee'), findsNothing);
  });

  testWidgets('labels shielded-source receives as shielded sender', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(txKind: 'received'),
        initialDetail: _detail(
          txKind: 'received',
          sourcePool: 'shielded',
          outputs: [
            rust_sync.TransactionDetailOutput(
              usesOrchardReceiver: false,
              address: _recipientAddress,
              amountZatoshi: BigInt.from(12000000000),
              pool: 'shielded',
            ),
          ],
        ),
      ),
    );

    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Shielded sender'), findsOneWidget);
    expect(find.text('Unknown sender'), findsNothing);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Show full address'), findsNothing);
  });

  testWidgets('shows the recorded network fee for a receive', (tester) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(
          txKind: 'received',
          fee: BigInt.from(10000),
        ),
        initialDetail: _detail(txKind: 'received'),
      ),
    );

    expect(find.text('Network fee'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsOneWidget);
  });

  testWidgets('masks the recorded receive fee in privacy mode', (tester) async {
    await _pumpScreen(
      tester,
      privacyEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(
          txKind: 'received',
          fee: BigInt.from(10000),
        ),
        initialDetail: _detail(txKind: 'received'),
      ),
    );
    expect(find.text('Network fee'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsNothing);
    final receipt = tester.widget<ReceivedReceiptView>(
      find.byType(ReceivedReceiptView),
    );
    expect(receipt.feeText, isNotNull);
    expect(receipt.feeText, isNot('--'));
  });

  for (final feeState in [
    rust_sync.TransactionFeeState.unknown,
    rust_sync.TransactionFeeState.notApplicable,
  ]) {
    testWidgets(
      'does not display a receive fee without known status: $feeState',
      (tester) async {
        await _pumpScreen(
          tester,
          args: ActivityTransactionStatusArgs(
            txidHex: _txidHex,
            txKind: 'received',
            initialTransaction: _transaction(
              txKind: 'received',
              fee: BigInt.from(10000),
              feeState: feeState,
            ),
            initialDetail: _detail(txKind: 'received'),
          ),
        );
        expect(find.text('Network fee'), findsNothing);
        expect(find.text('0.0001 ZEC'), findsNothing);
      },
    );
  }

  testWidgets('shows the in-progress receipt for an unconfirmed receive', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'receiving',
        initialTransaction: _transaction(
          txKind: 'receiving',
          minedHeight: BigInt.zero,
        ),
        initialDetail: _detail(txKind: 'receiving'),
      ),
    );

    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Receive in progress...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Received successfully'), findsNothing);
  });

  testWidgets('shows the saved contact sender for a received transaction', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(txKind: 'received'),
        initialDetail: _detail(
          txKind: 'received',
          sourceAddress: _transparentSenderAddress,
          sourcePool: 'transparent',
          outputs: [
            rust_sync.TransactionDetailOutput(
              usesOrchardReceiver: false,
              address: _recipientAddress,
              amountZatoshi: BigInt.from(12000000000),
              pool: 'shielded',
            ),
          ],
        ),
      ),
      contacts: [
        AddressBookContact(
          id: 'contact-1',
          label: 'Mom',
          network: AddressBookNetwork.zcash,
          address: _transparentSenderAddress,
          profilePictureId: 'pfp-01',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
    );

    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('t1PV7ny ... GVSpEX'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);

    await tester.tap(find.text('Show full address'));
    await tester.pump();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VerifyAddressModal),
        matching: find.text('Mom'),
      ),
      findsOneWidget,
    );
    expect(find.text('Unknown transparent address'), findsNothing);
    expect(find.textContaining('previous transaction'), findsNothing);
  });

  testWidgets('shows unknown transparent sender in the verify modal', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(txKind: 'received'),
        initialDetail: _detail(
          txKind: 'received',
          sourceAddress: _transparentSenderAddress,
          sourcePool: 'transparent',
        ),
      ),
    );

    await tester.tap(find.text('Show full address'));
    await tester.pump();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown transparent address'), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
  });

  testWidgets('shows an own account sender for a received transaction', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(txKind: 'received'),
        initialDetail: _detail(
          txKind: 'received',
          sourceAddress: _transparentSenderAddress,
          sourcePool: 'transparent',
        ),
      ),
      ownAccounts: {
        _transparentSenderAddress: const AccountInfo(
          uuid: 'account-2',
          name: 'Savings',
          profilePictureId: 'pfp-07',
          order: 1,
        ),
      },
    );

    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('t1PV7ny ... GVSpEX'), findsOneWidget);
  });

  testWidgets(
    'received transaction memo expands inline instead of opening a modal',
    (tester) async {
      const memo = 'Zcash is a privacy-focused message from the sender.';
      await _pumpScreen(
        tester,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'received',
          initialTransaction: _transaction(txKind: 'received'),
          initialDetail: _detail(txKind: 'received', memo: memo),
        ),
      );

      expect(find.byType(ReceivedReceiptView), findsOneWidget);
      expect(find.byType(VerifyAddressModal), findsNothing);

      await tester.tap(find.text(memo));
      await tester.pump();

      expect(find.text('Collapse'), findsOneWidget);
      expect(find.byType(VerifyAddressModal), findsNothing);
      expect(tester.widget<Text>(find.text(memo).last).maxLines, isNull);
    },
  );

  testWidgets('renders the send status view for a confirmed send', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(10000),
        ),
        initialDetail: _detail(
          txKind: 'sent',
          primaryAddress: _recipientAddress,
        ),
      ),
    );

    expect(find.byType(SendStatusContentView), findsOneWidget);
    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsOneWidget);
    expect(
      find.text(
        truncatedTxid(
          'efcdab8967452301efcdab8967452301'
          'efcdab8967452301efcdab8967452301',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'sent transaction memo expands inline instead of opening a modal',
    (tester) async {
      const memo = 'Zcash is a privacy-focused message for the recipient.';
      await _pumpScreen(
        tester,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'sent',
          initialTransaction: _transaction(txKind: 'sent'),
          initialDetail: _detail(
            txKind: 'sent',
            primaryAddress: _recipientAddress,
            memo: memo,
          ),
        ),
      );

      expect(find.byType(SendStatusContentView), findsOneWidget);
      expect(find.byType(VerifyAddressModal), findsNothing);

      await tester.tap(find.text(memo));
      await tester.pump();

      expect(find.text('Collapse'), findsOneWidget);
      expect(find.byType(VerifyAddressModal), findsNothing);
      expect(tester.widget<Text>(find.text(memo).last).maxLines, isNull);
    },
  );

  testWidgets('shows 0 ZEC and the memo for a zero-value receive', (
    tester,
  ) async {
    const memo = 'Memo-only payment';
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(
          txKind: 'received',
          displayAmount: BigInt.zero,
        ),
        initialDetail: _detail(
          txKind: 'received',
          sourcePool: 'shielded',
          memo: memo,
        ),
      ),
    );

    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Received successfully'), findsOneWidget);
    expect(find.text('0.00 ZEC'), findsOneWidget);
    expect(find.text(memo), findsOneWidget);
  });

  testWidgets('shows 0 ZEC and the memo for a zero-value send', (tester) async {
    const memo = 'Memo-only payment';
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          displayAmount: BigInt.zero,
          fee: BigInt.from(10000),
        ),
        initialDetail: _detail(
          txKind: 'sent',
          primaryAddress: _recipientAddress,
          memo: memo,
        ),
      ),
    );

    expect(find.byType(SendStatusContentView), findsOneWidget);
    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('0.00 ZEC'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsOneWidget);
    expect(find.text(memo), findsOneWidget);
  });

  testWidgets('show full address opens and closes the verify modal', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(txKind: 'sent'),
        initialDetail: _detail(
          txKind: 'sent',
          primaryAddress: _recipientAddress,
        ),
      ),
    );

    await tester.tap(find.text('Show full address'));
    await tester.pump();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('verify_address_close_button')));
    await tester.pump();

    expect(find.byType(VerifyAddressModal), findsNothing);
    expect(find.text('Unknown shielded address'), findsNothing);
  });

  testWidgets('renders the failed send presentation for an expired send', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          minedHeight: BigInt.zero,
          expiredUnmined: true,
        ),
        initialDetail: _detail(
          txKind: 'sent',
          primaryAddress: _recipientAddress,
        ),
      ),
    );

    expect(find.byType(SendStatusContentView), findsOneWidget);
    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('shows the saved contact recipient for a sent transaction', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(txKind: 'sent'),
        initialDetail: _detail(
          txKind: 'sent',
          primaryAddress: _recipientAddress,
        ),
      ),
      contacts: [
        AddressBookContact(
          id: 'contact-1',
          label: 'Mom',
          network: AddressBookNetwork.zcash,
          address: _recipientAddress,
          profilePictureId: 'pfp-01',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
    );

    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
  });

  testWidgets('renders the redesigned receipt for a shielding transaction', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'shielded',
        initialTransaction: _transaction(
          txKind: 'shielded',
          fee: BigInt.from(203209),
        ),
        initialDetail: _detail(txKind: 'shielded'),
      ),
    );

    expect(find.byType(ShieldedReceiptView), findsOneWidget);
    expect(find.byType(ReceivedReceiptView), findsNothing);
    expect(find.byType(SendStatusContentView), findsNothing);
    expect(find.text('Shielded successfully'), findsOneWidget);
    expect(find.text('From transparent balance'), findsOneWidget);
    expect(find.text('Shielded balance'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.00203209 ZEC'), findsOneWidget);
  });

  testWidgets(
    'a privately recovered shielding has a shielding receipt with the network fee',
    (tester) async {
      final cases = loadPrivateShieldingCases(
        txidHex: _txidHex,
        minedHeight: BigInt.from(3498120),
        blockTime: _blockTime,
      );
      final expected = ['0.0018 ZEC', '0.004 ZEC'];
      expect(cases, hasLength(expected.length));
      for (final (index, shielding) in cases.indexed) {
        await _pumpScreen(
          tester,
          privateQueriesEnabled: true,
          args: ActivityTransactionStatusArgs(
            txidHex: _txidHex,
            txKind: 'shielded',
            initialTransaction: shielding.transaction,
            initialDetail: shielding.detail,
          ),
          historyLoader: (_) async => [shielding.transaction],
          detailLoader: (_, _) async => shielding.detail,
        );

        expect(find.byType(ShieldedReceiptView), findsOneWidget);
        expect(find.byType(SendStatusContentView), findsNothing);
        expect(find.text('Shielded successfully'), findsOneWidget);
        expect(find.text(expected[index]), findsOneWidget);
        expect(find.text('Tx fee'), findsOneWidget);
        expect(find.text('0.0002 ZEC'), findsOneWidget);
        expect(find.text(kUnknownFeeText), findsNothing);
      }
    },
  );

  testWidgets('renders the Orchard to Ironwood migration receipt', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'migration',
        initialTransaction: _transaction(
          txKind: 'migration',
          fee: BigInt.from(105000),
        ),
        initialDetail: _detail(txKind: 'migration'),
      ),
    );

    expect(find.byType(ReceivedReceiptView), findsNothing);
    expect(find.byType(SendStatusContentView), findsNothing);
    expect(find.byType(ShieldedReceiptView), findsNothing);
    expect(find.text('Migrated to Ironwood'), findsOneWidget);
    expect(find.text('Amount migrated'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('Orchard balance'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Ironwood balance'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('0.00105 ZEC'), findsOneWidget);
  });

  testWidgets('renders a minimal fallback receipt for an unknown tx kind', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'unknown',
        initialTransaction: _transaction(txKind: 'unknown'),
        initialDetail: _detail(txKind: 'unknown'),
      ),
    );

    // No legacy illustration receipt: a neutral redesigned fallback with a
    // "Transaction" title, the amount row, and the status detail card.
    expect(find.byType(ReceivedReceiptView), findsNothing);
    expect(find.byType(SendStatusContentView), findsNothing);
    expect(find.byType(ShieldedReceiptView), findsNothing);
    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('120.00 ZEC'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text(_expectedTimestamp(_blockTime)), findsOneWidget);
  });

  testWidgets('keeps a dash for an unknown tx with no amount', (tester) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'unknown',
        initialTransaction: _transaction(
          txKind: 'unknown',
          displayAmount: BigInt.zero,
        ),
        initialDetail: _detail(txKind: 'unknown'),
      ),
    );

    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    expect(find.text('0.00 ZEC'), findsNothing);
  });

  testWidgets(
    'falls back to the minimal receipt for a sent tx with no recipient',
    (tester) async {
      // A sent tx whose detail carries no resolvable recipient address skips
      // the SendStatusContentView branch and routes to _fallbackContent.
      await _pumpScreen(
        tester,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'sent',
          initialTransaction: _transaction(
            txKind: 'sent',
            fee: BigInt.from(10000),
          ),
          // primaryAddress omitted (null) -> no recipient to resolve.
          initialDetail: _detail(txKind: 'sent'),
        ),
      );

      // No dedicated redesigned receipt rendered.
      expect(find.byType(SendStatusContentView), findsNothing);
      expect(find.byType(ReceivedReceiptView), findsNothing);
      expect(find.byType(ShieldedReceiptView), findsNothing);

      // Minimal fallback keeps the send status title: amount, status card.
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(find.text('Transaction'), findsNothing);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('120.00 ZEC'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      // Non-zero fee renders the fallback "Tx fee" row.
      expect(find.text('Tx fee'), findsOneWidget);
      expect(find.text('0.0001 ZEC'), findsOneWidget);
      // The fallback has no counterparty row, so no To/From label is forced.
      expect(find.text('To'), findsNothing);
      expect(find.text('From'), findsNothing);
    },
  );

  testWidgets(
    'a provisional debit shows an unknown fee and incomplete details',
    (tester) async {
      await _pumpScreen(
        tester,
        privateQueriesEnabled: true,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'sent',
          initialTransaction: _transaction(
            txKind: 'sent',
            feeState: rust_sync.TransactionFeeState.unknown,
            detailsComplete: false,
            provisional: true,
          ),
          initialDetail: _detail(txKind: 'sent'),
        ),
      );

      expect(find.byType(SendStatusContentView), findsNothing);
      expect(find.text('Tx fee'), findsOneWidget);
      expect(find.text(kUnknownFeeText), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Incomplete'), findsOneWidget);
    },
  );

  testWidgets('a fee-only entry is one network fee line', (tester) async {
    // Reconstructed zero external payment; recipient details can be missing.
    await _pumpScreen(
      tester,
      privateQueriesEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(65000),
          displayAmount: BigInt.from(65000),
          amountIncludesFee: true,
          detailsComplete: false,
          accountBalanceDelta: -65000,
          displayPool: 'transparent',
        ),
        initialDetail: _detail(txKind: 'sent'),
      ),
    );

    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text(kNetworkFeeText), findsOneWidget);
    expect(find.text('0.00065 ZEC'), findsOneWidget);
    expect(find.text('Amount'), findsNothing);
    expect(find.text('Tx fee'), findsNothing);
    expect(find.text('Incomplete'), findsOneWidget);
  });

  testWidgets(
    'a provisional fee-sized movement keeps its net change and fee explanation',
    (tester) async {
      // A mixed-pool balance decrease does not establish a fee-only activity.
      await _pumpScreen(
        tester,
        privateQueriesEnabled: true,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'sent',
          initialTransaction: _transaction(
            txKind: 'sent',
            fee: BigInt.from(20000),
            displayAmount: BigInt.from(20000),
            amountIncludesFee: true,
            detailsComplete: false,
            provisional: true,
            displayPool: 'unknown',
            accountBalanceDelta: -20000,
          ),
          initialDetail: _detail(txKind: 'sent'),
        ),
      );

      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text(kNetworkFeeText), findsNothing);
      expect(find.text(kNetChangeIncludesFeeText), findsOneWidget);
      expect(find.text('0.0002 ZEC'), findsNWidgets(2));
      expect(find.text('Amount'), findsNothing);
      expect(find.text('Tx fee'), findsOneWidget);
      expect(find.text('Incomplete'), findsOneWidget);
    },
  );

  testWidgets('an amount that includes the fee is labelled a net change', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(10000),
          displayAmount: BigInt.from(70000000),
          amountIncludesFee: true,
          detailsComplete: false,
          provisional: true,
        ),
        initialDetail: _detail(txKind: 'sent'),
      ),
    );

    expect(find.text(kNetChangeIncludesFeeText), findsOneWidget);
    expect(find.text('Amount'), findsNothing);
    // Nothing is subtracted, and the fee keeps its own line.
    expect(find.text('0.70 ZEC'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsOneWidget);
    expect(find.text(kNetworkFeeText), findsNothing);
  });

  for (final kind in ['sent', 'received', 'shielded', 'migration']) {
    for (final privateQueriesEnabled in [false, true]) {
      testWidgets(
        'feedback for $kind is private-only: $privateQueriesEnabled',
        (tester) async {
          await _pumpScreen(
            tester,
            privateQueriesEnabled: privateQueriesEnabled,
            args: ActivityTransactionStatusArgs(
              txidHex: _txidHex,
              txKind: kind,
              initialTransaction: _transaction(
                txKind: kind,
                fee: BigInt.zero,
                feeState: rust_sync.TransactionFeeState.unknown,
                detailsComplete: false,
                provisional: true,
              ),
              initialDetail: _detail(
                txKind: kind,
                primaryAddress: kind == 'sent' ? _recipientAddress : null,
              ),
            ),
          );

          expect(
            find.text('Incomplete'),
            privateQueriesEnabled ? findsOneWidget : findsNothing,
          );
          expect(
            find.text(kUnknownFeeText),
            privateQueriesEnabled && kind != 'received'
                ? findsOneWidget
                : findsNothing,
          );
        },
      );
    }
  }

  testWidgets('an open receipt updates feedback when Private queries changes', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.zero,
          feeState: rust_sync.TransactionFeeState.unknown,
          provisional: true,
        ),
        initialDetail: _detail(txKind: 'sent'),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActivityTransactionStatusScreen)),
    );
    for (final enabled in [true, false]) {
      await container.read(enhancePirProvider.notifier).set(enabled);
      await tester.pump();
      expect(find.text('Incomplete'), enabled ? findsOneWidget : findsNothing);
      expect(
        find.text(kUnknownFeeText),
        enabled ? findsOneWidget : findsNothing,
      );
      expect(find.text('Tx fee'), enabled ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('a dedicated receipt marks incomplete details', (tester) async {
    await _pumpScreen(
      tester,
      privateQueriesEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'received',
        initialTransaction: _transaction(
          txKind: 'received',
          feeState: rust_sync.TransactionFeeState.notApplicable,
          detailsComplete: false,
        ),
        initialDetail: _detail(txKind: 'received'),
      ),
    );

    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Incomplete'), findsOneWidget);
  });

  testWidgets('known payment details still mark unsettled effects', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      privateQueriesEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(txKind: 'sent', provisional: true),
        initialDetail: _detail(txKind: 'sent'),
      ),
    );

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Incomplete'), findsOneWidget);
  });

  testWidgets('an exact recovered send still marks missing recipient details', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      privateQueriesEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          displayPool: 'transparent',
          detailsComplete: false,
          displayAmount: BigInt.from(10000),
          fee: BigInt.from(10000),
          feeState: rust_sync.TransactionFeeState.known,
          accountBalanceDelta: -20000,
        ),
        initialDetail: _detail(txKind: 'sent'),
      ),
    );

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Incomplete'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
  });

  testWidgets('a complete receipt has no incomplete-details row', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      privateQueriesEnabled: true,
      args: ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
        initialTransaction: _transaction(
          txKind: 'sent',
          fee: BigInt.from(10000),
        ),
        initialDetail: _detail(txKind: 'sent'),
      ),
    );

    expect(find.text('Details'), findsNothing);
    expect(find.text(kUnknownFeeText), findsNothing);
  });

  testWidgets('shows the loading/not-found fallback when no tx is available', (
    tester,
  ) async {
    // With no initialTransaction the screen has tx == null and kicks off
    // _loadTransaction(showLoading: true). The FFI history call cannot run in
    // the widget-test harness (path_provider is unimplemented), so the screen
    // ends in the not-found state rather than the live "Loading transaction…"
    // spinner.
    await _pumpScreen(
      tester,
      args: const ActivityTransactionStatusArgs(
        txidHex: _txidHex,
        txKind: 'sent',
      ),
    );
    // Let the failed FFI load settle so the fallback message resolves.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SendStatusContentView), findsNothing);
    expect(find.byType(ReceivedReceiptView), findsNothing);
    expect(find.byType(ShieldedReceiptView), findsNothing);
    final showsLoading = find
        .text('Loading transaction…')
        .evaluate()
        .isNotEmpty;
    final showsNotFound = find
        .textContaining('could not be loaded')
        .evaluate()
        .isNotEmpty;
    expect(
      showsLoading || showsNotFound,
      isTrue,
      reason: 'expected the loading or not-found fallback copy',
    );
  });

  testWidgets(
    'received transparent output with a unified address shows no shield badge',
    (tester) async {
      // BUG-1 regression: the Dart layer no longer infers the pool from the
      // address prefix. A transparent receive whose recovered output address is
      // a unified (u1...) address must stay transparent, not flip to the
      // crimson "Shielded" badge.
      await _pumpScreen(
        tester,
        args: ActivityTransactionStatusArgs(
          txidHex: _txidHex,
          txKind: 'received',
          initialTransaction: _transaction(txKind: 'received'),
          initialDetail: _detail(
            txKind: 'received',
            // Transparent source with no address -> unknown (non-shielded)
            // sender, so the From row contributes no shield icon either.
            sourcePool: 'transparent',
            outputs: [
              rust_sync.TransactionDetailOutput(
                usesOrchardReceiver: false,
                address: _recipientAddress,
                amountZatoshi: BigInt.from(12000000000),
                pool: 'transparent',
              ),
            ],
          ),
        ),
      );

      expect(find.byType(ReceivedReceiptView), findsOneWidget);
      // The receiving sub-line glyph is the transparent-balance icon.
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.transparentBalance,
        ),
        findsWidgets,
      );
      // The shielded shield-keyhole glyph must not appear anywhere.
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.shieldKeyhole,
        ),
        findsNothing,
      );
      // And the crimson "Shielded" badge label is absent.
      expect(find.text('Shielded'), findsNothing);
    },
  );
}

rust_sync.TransactionInfo _transaction({
  String txidHex = _txidHex,
  required String txKind,
  BigInt? minedHeight,
  bool expiredUnmined = false,
  BigInt? fee,
  rust_sync.TransactionFeeState feeState = rust_sync.TransactionFeeState.known,
  bool detailsComplete = true,
  bool provisional = false,
  bool amountIncludesFee = false,
  BigInt? displayAmount,
  int accountBalanceDelta = 0,
  String displayPool = 'shielded',
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: accountBalanceDelta,
    fee: fee ?? BigInt.zero,
    feeState: feeState,
    detailsComplete: detailsComplete,
    provisional: provisional,
    amountIncludesFee: amountIncludesFee,
    blockTime: _blockTime,
    isTransparent: displayPool == 'transparent',
    txKind: txKind,
    displayAmount: displayAmount ?? BigInt.from(12000000000),
    displayPool: displayPool,
    createdTime: _blockTime,
  );
}

rust_sync.TransactionDetail _detail({
  required String txKind,
  String? primaryAddress,
  String? sourceAddress,
  String? sourcePool,
  String? memo,
  List<rust_sync.TransactionDetailOutput> outputs = const [],
}) {
  return rust_sync.TransactionDetail(
    txidHex: _txidHex,
    detailsComplete: true,
    provisional: false,
    txKind: txKind,
    primaryAddress: primaryAddress,
    sourceAddress: sourceAddress,
    sourcePool: sourcePool,
    memo: memo,
    outputs: outputs,
    transparentRecipients: const [],
  );
}

String _expectedTimestamp(BigInt seconds) {
  const months = <String>[
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = DateTime.fromMillisecondsSinceEpoch(
    seconds.toInt() * 1000,
  ).toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month]}, $hh:$mm';
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required ActivityTransactionStatusArgs args,
  List<AddressBookContact> contacts = const [],
  Map<String, AccountInfo> ownAccounts = const {},
  GiftCardActivityIndex? giftCardActivityIndex,
  AccountNotifier? accountNotifier,
  bool pricingEnabled = true,
  bool privacyEnabled = false,
  bool privateQueriesEnabled = false,
  Future<List<rust_sync.TransactionInfo>> Function(String)? historyLoader,
  Future<rust_sync.TransactionDetail?> Function(
    String,
    rust_sync.TransactionInfo,
  )?
  detailLoader,
}) async {
  await tester.binding.setSurfaceSize(const Size(1512, 982));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  final router = GoRouter(
    initialLocation: '/activity/tx/${args.txidHex}',
    routes: [
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, _) => ActivityTransactionStatusScreen(
          args: args,
          historyLoader: historyLoader,
          detailLoader: detailLoader,
        ),
      ),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/payment-links',
        builder: (_, state) =>
            Text('batch route: ${state.uri.queryParameters['batch']}'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        swapFeatureEnabledProvider.overrideWithValue(pricingEnabled),
        privacyModeProvider.overrideWith(() => _FixedPrivacy(privacyEnabled)),
        enhancePirProvider.overrideWith(
          () => FakeEnhancePirNotifier(privateQueriesEnabled),
        ),
        appBootstrapProvider.overrideWithValue(_bootstrap),
        if (accountNotifier != null)
          accountProvider.overrideWith(() => accountNotifier),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              percentage: 1,
            ),
          ),
        ),
        addressBookRepositoryProvider.overrideWithValue(
          _FakeAddressBookRepository(contacts),
        ),
        ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
        if (giftCardActivityIndex != null)
          giftCardActivityIndexProvider.overrideWith(
            (ref, accountUuid) async => giftCardActivityIndex,
          ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/activity',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _SwitchableAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
    ],
    activeAccountUuid: 'account-1',
  );

  void setActiveAccount(String uuid) {
    state = AsyncData(
      state.requireValue.copyWith(activeAccountUuid: uuid, activeAddress: null),
    );
  }
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([this._contacts = const []]);

  final List<AddressBookContact> _contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => _contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

class _FixedPrivacy extends PrivacyModeNotifier {
  _FixedPrivacy(this.enabled);
  final bool enabled;
  @override
  bool build() => enabled;
}
