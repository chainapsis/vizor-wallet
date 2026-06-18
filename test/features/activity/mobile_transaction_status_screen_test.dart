@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1statusaddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
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
);

const _txid =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _address =
    'u1l8xunezsvhq8fgzfl7404m450nwnd76zshe7f5dxv5z3w4gthawuwukdn5aalh6g'
    '5wfshmrjmd5gh';
const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';

rust_sync.TransactionInfo _tx({
  String kind = 'sent',
  BigInt? minedHeight,
  bool expired = false,
  BigInt? fee,
  String displayPool = 'shielded',
}) {
  return rust_sync.TransactionInfo(
    txidHex: _txid,
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expired,
    accountBalanceDelta: 0,
    fee: fee ?? BigInt.from(15000),
    blockTime: BigInt.from(1750000000),
    isTransparent: false,
    txKind: kind,
    displayAmount: BigInt.from(12312000000),
    displayPool: displayPool,
    createdTime: BigInt.from(1750000000),
  );
}

rust_sync.TransactionDetail _detail({
  String kind = 'sent',
  String? memo,
  String address = _address,
}) {
  return rust_sync.TransactionDetail(
    txidHex: _txid,
    txKind: kind,
    primaryAddress: address,
    memo: memo,
    outputs: const [],
  );
}

Widget _app(
  rust_sync.TransactionInfo tx, {
  rust_sync.TransactionDetail? detail,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      ),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: MobileTransactionStatusScreen(
          args: MobileTransactionStatusArgs(
            txidHex: tx.txidHex,
            txKind: tx.txKind,
            initialTransaction: tx,
          ),
          historyLoader: (_) async => [tx],
          detailLoader: (_, _) async => detail ?? _detail(kind: tx.txKind),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mined sent tx shows success title, chip, fee, and address', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('123.12 ZEC'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    // Figma-style 6 ... 5 truncation of the recipient.
    expect(find.text('u1l8xu ... d5gh'.replaceAll('  ', ' ')), findsNothing);
    expect(
      find.text(
        '${_address.substring(0, 6)} ... ${_address.substring(_address.length - 5)}',
      ),
      findsOneWidget,
    );
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.00015 ZEC'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(
      find.text('${_txid.substring(0, 8)}...${_txid.substring(56)}'),
      findsOneWidget,
    );
  });

  testWidgets('sent TEX tx keeps a TEX recipient label', (tester) async {
    await tester.pumpWidget(
      _app(
        _tx(displayPool: 'transparent'),
        detail: _detail(address: _texAddress),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(
      find.text(
        '${_texAddress.substring(0, 6)} ... ${_texAddress.substring(_texAddress.length - 5)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unmined sent tx shows the in-progress state', (tester) async {
    await tester.pumpWidget(_app(_tx(minedHeight: BigInt.zero)));
    // No pumpAndSettle — the in-progress loader spins forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sending...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('expired tx shows the failed state with strikethrough', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx(minedHeight: BigInt.zero, expired: true)));
    await tester.pumpAndSettle();

    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Failed, funds returned'), findsOneWidget);

    final addressText = tester.widget<Text>(
      find.text(
        '${_address.substring(0, 6)} ... ${_address.substring(_address.length - 5)}',
      ),
    );
    expect(addressText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('received tx puts the sender above the amount', (tester) async {
    await tester.pumpWidget(_app(_tx(kind: 'received', fee: BigInt.zero)));
    await tester.pumpAndSettle();

    expect(find.text('Received'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    final fromY = tester.getTopLeft(find.text('From')).dy;
    final amountY = tester.getTopLeft(find.text('Amount')).dy;
    expect(fromY, lessThan(amountY));
    // Received txs report no fee — the fee section is dropped.
    expect(find.text('Tx fee'), findsNothing);
  });

  testWidgets('show full address expands and collapses the address', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    expect(find.text(_address), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('mobile_tx_status_toggle_address')),
    );
    await tester.pump();
    expect(find.text(_address), findsOneWidget);
    expect(find.text('Hide full address'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_tx_status_toggle_address')),
    );
    await tester.pump();
    expect(find.text(_address), findsNothing);
  });

  testWidgets('memo renders a message row that expands', (tester) async {
    const memo = 'Zcash is a privacy protecting digital currency.';
    await tester.pumpWidget(_app(_tx(), detail: _detail(memo: memo)));
    await tester.pumpAndSettle();

    expect(find.text('Message'), findsOneWidget);
    expect(find.text(memo), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('mobile_tx_status_message_toggle')),
    );
    await tester.pump();
    expect(find.text(memo), findsOneWidget);
  });

  testWidgets('no memo means no message row', (tester) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsNothing);
  });
}
