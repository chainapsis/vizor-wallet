import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _txid =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

rust_sync.TransactionInfo _tx({String kind = 'received', int height = 100}) =>
    rust_sync.TransactionInfo(
      txidHex: _txid,
      txKind: kind,
      minedHeight: BigInt.from(height),
      expiredUnmined: false,
      accountBalanceDelta: 0,
      fee: BigInt.zero,
      blockTime: BigInt.from(1764150000),
      createdTime: BigInt.from(1764150000),
      isTransparent: false,
      displayAmount: BigInt.from(100000000),
      displayPool: 'shielded',
    );

rust_sync.TransactionDetail _detail(String memo, {String kind = 'received'}) =>
    rust_sync.TransactionDetail(
      txidHex: _txid,
      txKind: kind,
      memo: memo,
      outputs: const [],
    );

void transactionLoadingTests({required bool mobile}) {
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
      history: (_) => history.future,
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
    expect(detailReads, 0);
    history.complete([_tx()]);
    await tester.pump();
    await tester.pump();
    expect(detailReads, 1);
    expect(find.text(receivedTitle), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    detail.complete(_detail('Loaded memo'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Loaded memo'), findsOneWidget);
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
            history: (_) => history.future,
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
          expect(
            find.text(
              kind == 'received'
                  ? receivedTitle
                  : mobile
                  ? 'Sent successfully'
                  : 'Transaction',
            ),
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
      history: (_) => history.future,
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
      history: (_) => history.future,
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
      history: (_) => Completer<List<rust_sync.TransactionInfo>>().future,
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
        history: (_) async => [_tx(kind: 'sent')],
        detail: (_, _) async {
          detailReads++;
          return _detail('Wrong kind', kind: 'sent');
        },
      );
      expect(detailReads, 0);
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
          history: (uuid) async => uuid == 'account-1' ? [_tx()] : [],
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
      history: (_) => ++reads == 1 ? first.future : second.future,
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
    await _pump(tester, mobile: mobile, history: (_) => history.future);
    await tester.pumpWidget(const SizedBox());
    history.completeError(StateError('late failure'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

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
                  initialTransaction: seeded ? _tx(kind: kind) : null,
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
                  initialTransaction: seeded ? _tx(kind: kind) : null,
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
