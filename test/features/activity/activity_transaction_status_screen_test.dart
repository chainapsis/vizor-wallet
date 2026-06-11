import 'package:flutter/material.dart' show MaterialApp, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/widgets/received_receipt_view.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_status_content_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/transaction_receipt_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/verify_address_modal.dart';
import 'package:zcash_wallet/src/features/activity/widgets/shielded_receipt_view.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _txidHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const _recipientAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _receivingAddress = 't1Z9N3oVYrYDpnbqDcXJpuLrGpcSLDgHXyo';

const _transparentSenderAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

final _blockTime = BigInt.from(1764150000);

void main() {
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
              address: _receivingAddress,
              amountZatoshi: BigInt.from(12000000000),
              pool: 'transparent',
            ),
          ],
        ),
      ),
    );

    expect(find.byType(ReceivedReceiptView), findsOneWidget);
    expect(find.byType(TransactionReceiptView), findsNothing);
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

  testWidgets('shows the fee row for a receive with a known fee', (
    tester,
  ) async {
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
    expect(find.byType(TransactionReceiptView), findsNothing);
    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsOneWidget);
    expect(find.text(_txidHex), findsOneWidget);
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
    expect(find.byType(TransactionReceiptView), findsNothing);
    expect(find.byType(ReceivedReceiptView), findsNothing);
    expect(find.byType(SendStatusContentView), findsNothing);
    expect(find.text('Shielded successfully'), findsOneWidget);
    expect(find.text('From transparent balance'), findsOneWidget);
    expect(find.text('Shielded balance'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.00203209 ZEC'), findsOneWidget);
  });
}

rust_sync.TransactionInfo _transaction({
  required String txKind,
  BigInt? minedHeight,
  bool expiredUnmined = false,
  BigInt? fee,
}) {
  return rust_sync.TransactionInfo(
    txidHex: _txidHex,
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: 0,
    fee: fee ?? BigInt.zero,
    blockTime: _blockTime,
    isTransparent: false,
    txKind: txKind,
    displayAmount: BigInt.from(12000000000),
    displayPool: 'shielded',
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
    txKind: txKind,
    primaryAddress: primaryAddress,
    sourceAddress: sourceAddress,
    sourcePool: sourcePool,
    memo: memo,
    outputs: outputs,
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
        builder: (_, _) => ActivityTransactionStatusScreen(args: args),
      ),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              percentage: 1,
              displayPercentage: 1,
            ),
          ),
        ),
        addressBookRepositoryProvider.overrideWithValue(
          _FakeAddressBookRepository(contacts),
        ),
        ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
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

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([this._contacts = const []]);

  final List<AddressBookContact> _contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => _contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}
