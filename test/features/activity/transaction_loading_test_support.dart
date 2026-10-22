import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/receipt_loading_skeleton.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

const _txid =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

rust_sync.TransactionInfo _tx({
  String kind = 'received',
  int height = 100,
  int amount = 1,
  bool provisional = false,
}) => rust_sync.TransactionInfo(
  amountIncludesFee: false,
  detailsComplete: true,
  feeState: rust_sync.TransactionFeeState.known,
  provisional: provisional,
  txidHex: _txid,
  txKind: kind,
  minedHeight: BigInt.from(height),
  expiredUnmined: false,
  accountBalanceDelta: 0,
  fee: BigInt.zero,
  blockTime: BigInt.from(1764150000),
  createdTime: BigInt.from(1764150000),
  isTransparent: false,
  displayAmount: BigInt.from(amount * 100000000),
  displayPool: 'shielded',
);

rust_sync.TransactionDetail _detail(String memo, {String kind = 'received'}) =>
    rust_sync.TransactionDetail(
      detailsComplete: true,
      provisional: false,
      txidHex: _txid,
      txKind: kind,
      memo: memo,
      outputs: const [],
      transparentRecipients: const [],
      transparentOmissions: const [],
    );

void transactionLoadingTests({required bool mobile}) {
  setUpAll(loadFigmaCompareFonts);
  final receivedTitle = mobile ? 'Received' : 'Received successfully';
  testWidgets('summary appears while history and detail remain unresolved', (
    tester,
  ) async {
    final history = Completer<List<rust_sync.TransactionInfo>>();
    final detail = Completer<rust_sync.TransactionDetail?>();
    var detailReads = 0;
    await _pump(
      tester,
      mobile: mobile,
      history: (_, _) => history.future,
      detail: (_, _) {
        detailReads++;
        return detail.future;
      },
    );
    expect(find.text(receivedTitle), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'1(?:\.0+)? ZEC'), findRichText: true),
      findsWidgets,
    );
    // The tapped row's detail is asked for at once, not after the row read.
    expect(detailReads, 1);
    expect(find.byType(ReceiptMemoSkeleton), findsOneWidget);
    history.complete([_tx()]);
    await tester.pump();
    await tester.pump();
    // The row read reuses the detail already asked for.
    expect(detailReads, 1);
    expect(find.text(receivedTitle), findsOneWidget);
    expect(find.byType(ReceiptMemoSkeleton), findsOneWidget);
    detail.complete(_detail('Loaded memo'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Loaded memo'), findsOneWidget);
    expect(find.byType(ReceiptValueSkeleton), findsNothing);
  });

  testWidgets(
    'the tapped row\'s detail ends the skeleton before its row read',
    (tester) async {
      final history = Completer<List<rust_sync.TransactionInfo>>();
      await _pump(
        tester,
        mobile: mobile,
        history: (_, _) => history.future,
        detail: (_, _) async =>
            _completeDetail(kind: 'received', memo: 'Early memo'),
      );
      await tester.pump();
      await tester.pump();
      // The row read has not returned, yet the receipt shows its detail.
      expect(history.isCompleted, isFalse);
      expect(find.text('Early memo'), findsOneWidget);
      expect(find.byType(ReceiptValueSkeleton), findsNothing);
      expect(find.byType(ReceiptMemoSkeleton), findsNothing);
      history.complete([_tx()]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Early memo'), findsOneWidget);
      expect(find.byType(ReceiptValueSkeleton), findsNothing);
    },
  );

  testWidgets('the receipt reads its own transaction, not the history', (
    tester,
  ) async {
    final reads = <String>[];
    final sync = FakeSyncNotifier(_sync());
    await _pump(
      tester,
      mobile: mobile,
      sync: sync,
      history: (uuid, txid) async {
        reads.add('$uuid $txid');
        return [_tx()];
      },
      detail: (_, _) async => _detail('Memo'),
    );
    sync.emit(_sync(height: 101));
    await tester.pump();
    await tester.pump();
    expect(reads, ['account-1 $_txid', 'account-1 $_txid']);
  });

  testWidgets('a detail asked for a role the transaction left is not shown', (
    tester,
  ) async {
    // The tapped row was a provisional debit; its single row is now a
    // receive. The detail asked for the old role never reaches the receipt.
    final staleDetail = Completer<rust_sync.TransactionDetail?>();
    final kinds = <String>[];
    await _pump(
      tester,
      mobile: mobile,
      kind: 'sent',
      provisional: true,
      history: (_, _) async => [_tx()],
      detail: (_, tx) {
        kinds.add(tx.txKind);
        return tx.txKind == 'sent'
            ? staleDetail.future
            : Future.value(_detail('Receive memo'));
      },
    );
    expect(kinds, ['sent', 'received']);
    expect(find.text('Receive memo'), findsOneWidget);
    staleDetail.complete(_detail('Debit memo', kind: 'sent'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Debit memo'), findsNothing);
    expect(find.text('Receive memo'), findsOneWidget);
  });

  testWidgets(
    'a provisional row keeps its skeleton until the row read names its role',
    (tester) async {
      // The debit's detail answers first, but the row read turns the
      // transaction into a receive: no content may show and then give way
      // to the receive's skeleton.
      final rows = Completer<List<rust_sync.TransactionInfo>>();
      final receiveDetail = Completer<rust_sync.TransactionDetail?>();
      final memoSkeletonSeen = <bool>[];
      void sample() => memoSkeletonSeen.add(
        find.byType(ReceiptMemoSkeleton).evaluate().isNotEmpty,
      );
      await _pump(
        tester,
        mobile: mobile,
        kind: 'sent',
        provisional: true,
        history: (_, _) => rows.future,
        detail: (_, tx) => tx.txKind == 'sent'
            ? Future.value(_detail('Debit memo', kind: 'sent'))
            : receiveDetail.future,
      );
      await tester.pump();
      await tester.pump();
      sample();
      expect(find.text('Debit memo'), findsNothing);
      rows.complete([_tx()]);
      await tester.pump();
      await tester.pump();
      sample();
      receiveDetail.complete(_detail('Receive memo'));
      await tester.pump();
      await tester.pump();
      sample();
      expect(find.text('Debit memo'), findsNothing);
      expect(find.text('Receive memo'), findsOneWidget);
      expect(memoSkeletonSeen, [true, true, false]);
    },
  );

  testWidgets('a receive that became mined keeps its detail while it reloads', (
    tester,
  ) async {
    // The tapped row was unmined; the row read reports it received. The
    // receiving detail still fits the received row, so it stays shown, with
    // no skeleton, until the received detail replaces it.
    final rows = Completer<List<rust_sync.TransactionInfo>>();
    final receivedDetail = Completer<rust_sync.TransactionDetail?>();
    final kinds = <String>[];
    await _pump(
      tester,
      mobile: mobile,
      kind: 'receiving',
      history: (_, _) => rows.future,
      detail: (_, tx) {
        kinds.add(tx.txKind);
        return tx.txKind == 'receiving'
            ? Future.value(_detail('Early memo', kind: 'receiving'))
            : receivedDetail.future;
      },
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Early memo'), findsOneWidget);
    rows.complete([_tx()]);
    await tester.pump();
    await tester.pump();
    expect(kinds, ['receiving', 'received']);
    expect(find.text('Early memo'), findsOneWidget);
    expect(find.byType(ReceiptMemoSkeleton), findsNothing);
    expect(find.byType(ReceiptValueSkeleton), findsNothing);
    receivedDetail.complete(_detail('Mined memo'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Mined memo'), findsOneWidget);
  });

  for (final kind in ['sent', 'received', 'shielded']) {
    for (final hasMemo in [true, false]) {
      testWidgets('$kind detail skeleton preserves layout with memo=$hasMemo', (
        tester,
      ) async {
        final history = Completer<List<rust_sync.TransactionInfo>>();
        final detail = Completer<rust_sync.TransactionDetail?>();
        await _pump(
          tester,
          mobile: mobile,
          kind: kind,
          history: (_, _) => history.future,
          detail: (_, _) => detail.future,
        );
        double y(String label) => tester.getTopLeft(find.text(label).first).dy;
        final amountY = y('Amount');
        final statusY = y('Status');
        final timestampY = y('Timestamp');
        final txidY = y('Tx ID');
        expect(find.byType(ReceiptMemoSkeleton), findsOneWidget);
        for (final element in find.byType(ReceiptValueSkeleton).evaluate()) {
          final size = tester.getSize(find.byWidget(element.widget));
          expect(size.width, greaterThan(0));
          expect(size.height, greaterThan(0));
        }
        expect(find.text('Show full address'), findsNothing);
        if (kind == 'sent') {
          expect(find.text('Sent successfully'), findsOneWidget);
          expect(find.text('Shielded'), findsNothing);
        }
        history.complete([_tx(kind: kind)]);
        await tester.pump();
        await tester.pump();
        expect(y('Status'), statusY);
        expect(find.byType(ReceiptMemoSkeleton), findsOneWidget);
        detail.complete(
          _completeDetail(kind: kind, memo: hasMemo ? 'Loaded memo' : null),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(ReceiptValueSkeleton), findsNothing);
        expect(y('Amount'), amountY);
        expect(y('Status'), statusY);
        if (hasMemo) {
          expect(y('Timestamp'), timestampY);
          expect(y('Tx ID'), txidY);
        } else {
          expect(find.text('Message'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('null detail ends skeleton without inventing address or pool', (
    tester,
  ) async {
    final detail = Completer<rust_sync.TransactionDetail?>();
    await _pump(
      tester,
      mobile: mobile,
      kind: 'sent',
      history: (_, _) async => [_tx(kind: 'sent')],
      detail: (_, _) => detail.future,
    );
    expect(find.byType(ReceiptCounterpartySkeleton), findsOneWidget);
    detail.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ReceiptValueSkeleton), findsNothing);
    expect(find.text('Show full address'), findsNothing);
    // The send keeps its To row, naming no one.
    expect(find.text('To'), findsOneWidget);
    expect(find.text(kUnknownRecipientText), findsOneWidget);
    expect(find.text('Message'), findsNothing);
  });

  testWidgets('refresh keeps loaded detail without restarting skeleton', (
    tester,
  ) async {
    final detail = Completer<rust_sync.TransactionDetail?>();
    final sync = FakeSyncNotifier(_sync());
    await _pump(
      tester,
      mobile: mobile,
      sync: sync,
      initialDetail: _completeDetail(kind: 'received', memo: 'Existing memo'),
      history: (_, _) async => [_tx()],
      detail: (_, _) => detail.future,
    );
    expect(find.byType(ReceiptValueSkeleton), findsNothing);
    final statusY = tester.getTopLeft(find.text('Status')).dy;
    sync.emit(_sync(height: 101));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ReceiptValueSkeleton), findsNothing);
    expect(tester.getTopLeft(find.text('Status')).dy, statusY);
    detail.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ReceiptValueSkeleton), findsNothing);
    expect(find.text('Existing memo'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Status')).dy, statusY);
  });

  for (final kind in ['received', 'sent']) {
    for (final failDetail in [false, true]) {
      testWidgets(
        'failed ${failDetail ? 'detail' : 'history'} preserves $kind summary and shows error',
        (tester) async {
          final history = Completer<List<rust_sync.TransactionInfo>>();
          final detail = Completer<rust_sync.TransactionDetail?>();
          await _pump(
            tester,
            mobile: mobile,
            kind: kind,
            history: (_, _) => history.future,
            detail: (_, _) => detail.future,
          );
          if (failDetail) {
            history.complete([_tx(kind: kind)]);
            await tester.pump();
            await tester.pump();
            detail.completeError(StateError('read failed'));
          } else {
            history.completeError(StateError('read failed'));
          }
          await tester.pump();
          await tester.pump();
          // Desktop and mobile both keep the send title without a recipient.
          expect(
            find.text(kind == 'received' ? receivedTitle : 'Sent successfully'),
            findsOneWidget,
          );
          expect(find.text('Completed'), findsOneWidget);
          expect(
            find.textContaining(RegExp(r'1(?:\.0+)? ZEC'), findRichText: true),
            findsWidgets,
          );
          expect(
            find.text('Latest transaction status could not be refreshed.'),
            findsOneWidget,
          );
          expect(find.byType(ReceiptValueSkeleton), findsNothing);
        },
      );
    }
  }

  testWidgets('direct link shows loading then the account receipt', (
    tester,
  ) async {
    final history = Completer<List<rust_sync.TransactionInfo>>();
    await _pump(
      tester,
      mobile: mobile,
      seeded: false,
      history: (_, _) => history.future,
    );
    expect(find.text('Loading transaction…'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    history.complete([_tx()]);
    await tester.pump();
    await tester.pump();
    expect(find.text(receivedTitle), findsOneWidget);
  });

  testWidgets('direct-link failure displays one error without a receipt', (
    tester,
  ) async {
    final history = Completer<List<rust_sync.TransactionInfo>>();
    await _pump(
      tester,
      mobile: mobile,
      seeded: false,
      history: (_, _) => history.future,
    );
    history.completeError(StateError('read failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Transaction could not be loaded.'), findsOneWidget);
    expect(find.text('Loading transaction…'), findsNothing);
    expect(find.text('Completed'), findsNothing);
  });

  testWidgets('route data from another account is never shown', (tester) async {
    await _pump(
      tester,
      mobile: mobile,
      sourceAccount: 'account-2',
      initialDetail: _detail('Other account memo'),
      history: (_, _) => Completer<List<rust_sync.TransactionInfo>>().future,
    );
    expect(find.text('Loading transaction…'), findsOneWidget);
    expect(find.text(receivedTitle), findsNothing);
    expect(find.text('Other account memo'), findsNothing);
  });

  testWidgets(
    'same transaction with a different kind does not replace the row',
    (tester) async {
      var detailReads = 0;
      await _pump(
        tester,
        mobile: mobile,
        history: (_, _) async => [_tx(kind: 'sent')],
        detail: (_, _) async {
          detailReads++;
          return _detail('Wrong kind', kind: 'sent');
        },
      );
      // Only the tapped row's own detail is read; the other row's never.
      expect(detailReads, 1);
      expect(find.text(receivedTitle), findsOneWidget);
      expect(find.text('Wrong kind'), findsNothing);
    },
  );

  for (final staleError in [false, true]) {
    testWidgets(
      'A to B to A discards stale ${staleError ? 'errors' : 'details'}',
      (tester) async {
        final account = _Accounts();
        final oldDetail = Completer<rust_sync.TransactionDetail?>();
        var aReads = 0;
        await _pump(
          tester,
          mobile: mobile,
          accounts: account,
          history: (uuid, _) async => uuid == 'account-1' ? [_tx()] : [],
          detail: (_, _) {
            aReads++;
            return aReads == 1
                ? oldDetail.future
                : Future.value(_detail('Current memo'));
          },
        );
        expect(aReads, 1);
        account.switchTo('account-2');
        await tester.pump();
        await tester.pump();
        expect(find.text(receivedTitle), findsNothing);
        account.switchTo('account-1');
        await tester.pump();
        await tester.pump();
        expect(find.text('Current memo'), findsOneWidget);
        if (staleError) {
          oldDetail.completeError(StateError('stale failure'));
        } else {
          oldDetail.complete(_detail('Stale memo'));
        }
        await tester.pump();
        await tester.pump();
        expect(find.text('Current memo'), findsOneWidget);
        expect(find.text('Stale memo'), findsNothing);
        expect(
          find.text('Latest transaction status could not be refreshed.'),
          findsNothing,
        );
      },
    );
  }

  testWidgets('a refresh follows the shown leg of a two-row transaction', (
    tester,
  ) async {
    // Private recovery can report a sent and a received row for one txid,
    // the sent row first.
    SyncState legs({required int sent, required int received}) => SyncState(
      accountUuid: 'account-1',
      hasAccountScopedData: true,
      percentage: 1,
      recentTransactions: [
        _tx(kind: 'sent', amount: sent),
        _tx(amount: received),
      ],
    );
    final sync = FakeSyncNotifier(legs(sent: 1, received: 1));
    var reads = 0;
    await _pump(
      tester,
      mobile: mobile,
      sync: sync,
      history: (_, _) async {
        reads++;
        return [_tx()];
      },
    );
    final initialReads = reads;

    // Only the shown received leg changes: the receipt reloads.
    sync.emit(legs(sent: 1, received: 2));
    await tester.pump();
    await tester.pump();
    expect(reads, initialReads + 1);

    // Only the other leg changes: nothing to reload.
    sync.emit(legs(sent: 2, received: 2));
    await tester.pump();
    await tester.pump();
    expect(reads, initialReads + 1);
  });

  testWidgets('an older history refresh cannot overwrite the latest result', (
    tester,
  ) async {
    final first = Completer<List<rust_sync.TransactionInfo>>();
    final second = Completer<List<rust_sync.TransactionInfo>>();
    final sync = FakeSyncNotifier(_sync());
    var reads = 0;
    await _pump(
      tester,
      mobile: mobile,
      sync: sync,
      history: (_, _) => ++reads == 1 ? first.future : second.future,
      detail: (_, _) async => _detail('Latest memo'),
    );
    sync.emit(_sync(height: 101));
    await tester.pump();
    await tester.pump();
    expect(reads, 2);
    second.complete([_tx()]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Latest memo'), findsOneWidget);
    first.completeError(StateError('superseded history failure'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Latest memo'), findsOneWidget);
    expect(
      find.text('Latest transaction status could not be refreshed.'),
      findsNothing,
    );
  });

  testWidgets('completion after disposal is ignored', (tester) async {
    final history = Completer<List<rust_sync.TransactionInfo>>();
    await _pump(tester, mobile: mobile, history: (_, _) => history.future);
    await tester.pumpWidget(const SizedBox());
    history.completeError(StateError('late failure'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

rust_sync.TransactionDetail _completeDetail({
  required String kind,
  String? memo,
}) => rust_sync.TransactionDetail(
  detailsComplete: true,
  provisional: false,
  txidHex: _txid,
  txKind: kind,
  primaryAddress: kind == 'sent'
      ? 'u1syntheticrecipientaddress123456789'
      : null,
  sourcePool: kind == 'received' ? 'shielded' : null,
  memo: memo,
  outputs: kind == 'received'
      ? [
          rust_sync.TransactionDetailOutput(
            address: 'u1syntheticreceivingaddress123456789',
            amountZatoshi: BigInt.from(100000000),
            pool: 'shielded',
            usesOrchardReceiver: true,
          ),
        ]
      : const [],
  transparentRecipients: const [],
  transparentOmissions: const [],
);

SyncState _sync({int height = 100}) => SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  percentage: 1,
  recentTransactions: height == 100 ? [] : [_tx(height: height)],
);

Future<void> _pump(
  WidgetTester tester, {
  required bool mobile,
  required ActivityTxHistoryLoader history,
  ActivityTxDetailLoader? detail,
  bool seeded = true,
  String kind = 'received',
  bool provisional = false,
  String sourceAccount = 'account-1',
  rust_sync.TransactionDetail? initialDetail,
  _Accounts? accounts,
  FakeSyncNotifier? sync,
}) async {
  await tester.binding.setSurfaceSize(
    mobile ? const Size(393, 1200) : const Size(1512, 982),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/activity/tx/$_txid',
    routes: [
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, _) => mobile
            ? MobileTransactionStatusScreen(
                args: MobileTransactionStatusArgs(
                  txidHex: _txid,
                  txKind: kind,
                  initialTransaction: seeded
                      ? _tx(kind: kind, provisional: provisional)
                      : null,
                  initialDetail: initialDetail,
                  sourceAccountUuid: seeded ? sourceAccount : null,
                ),
                historyLoader: history,
                detailLoader: detail ?? (_, _) async => null,
              )
            : ActivityTransactionStatusScreen(
                args: ActivityTransactionStatusArgs(
                  txidHex: _txid,
                  txKind: kind,
                  initialTransaction: seeded
                      ? _tx(kind: kind, provisional: provisional)
                      : null,
                  initialDetail: initialDetail,
                  sourceAccountUuid: seeded ? sourceAccount : null,
                ),
                historyLoader: history,
                detailLoader: detail ?? (_, _) async => null,
              ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/activity',
            initialAccountState: _accountState,
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: 'main',
            rpcEndpointConfig: defaultRpcEndpointConfig('main'),
            themeMode: ThemeMode.light,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        accountProvider.overrideWith(() => accounts ?? _Accounts()),
        syncProvider.overrideWith(() => sync ?? FakeSyncNotifier(_sync())),
        swapFeatureEnabledProvider.overrideWithValue(false),
        ownAccountAddressesProvider.overrideWith((_) async => {}),
        giftCardActivityIndexProvider.overrideWith(
          (_, _) async => GiftCardActivityIndex.empty,
        ),
        addressBookRepositoryProvider.overrideWithValue(_AddressBook()),
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

const _accountState = AccountState(
  accounts: [
    AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
    AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
  ],
  activeAccountUuid: 'account-1',
);

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => _accountState;

  void switchTo(String uuid) =>
      state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
}

class _AddressBook implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async => [];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}
