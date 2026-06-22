@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
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
const _transparentSenderAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';
const _receivingShieldedAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';
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
  String? primaryAddress,
  String? sourceAddress,
  String? sourcePool,
  String? memo,
  List<rust_sync.TransactionDetailOutput> outputs = const [],
}) {
  return rust_sync.TransactionDetail(
    txidHex: _txid,
    txKind: kind,
    primaryAddress: primaryAddress ?? _address,
    sourceAddress: sourceAddress,
    sourcePool: sourcePool,
    memo: memo,
    outputs: outputs,
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
  setUpAll(_loadAppFonts);

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
        detail: _detail(primaryAddress: _texAddress),
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
    await tester.pumpWidget(
      _app(
        _tx(kind: 'received', fee: BigInt.zero),
        detail: _detail(
          kind: 'received',
          sourceAddress: _transparentSenderAddress,
          sourcePool: 'transparent',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Received'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    final fromY = tester.getTopLeft(find.text('From')).dy;
    final amountY = tester.getTopLeft(find.text('Amount')).dy;
    expect(fromY, lessThan(amountY));
    // Received txs report no fee — the fee section is dropped.
    expect(find.text('Tx fee'), findsNothing);
  });

  testWidgets('show full address opens the verify sheet', (tester) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    expect(find.text(_address), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('mobile_tx_status_show_full_address')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile_address_verify_chunks')),
      findsOneWidget,
    );
    expect(find.text('Unified address'), findsOneWidget);
    expect(find.text('u1l8x'), findsOneWidget);
    expect(find.text(_address), findsNothing);
  });

  testWidgets('show full address action label fits on mobile width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey('mobile_tx_status_show_full_address'),
    );
    final actionLabel = find.descendant(
      of: action,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() == 'Show full address',
      ),
    );

    expect(action, findsOneWidget);
    expect(actionLabel, findsOneWidget);
    final richText = tester.widget<RichText>(actionLabel);
    final textPainter = TextPainter(
      text: richText.text,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    expect(
      tester.getSize(actionLabel).width,
      greaterThanOrEqualTo(textPainter.width - 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('received tx separates transparent sender and shielded receiver', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _tx(kind: 'received', fee: BigInt.zero),
        detail: _detail(
          kind: 'received',
          sourceAddress: _transparentSenderAddress,
          sourcePool: 'transparent',
          outputs: [
            rust_sync.TransactionDetailOutput(
              address: _receivingShieldedAddress,
              amountZatoshi: BigInt.from(12312000000),
              pool: 'shielded',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${_transparentSenderAddress.substring(0, 6)} ... '
        '${_transparentSenderAddress.substring(_transparentSenderAddress.length - 5)}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '${_receivingShieldedAddress.substring(0, 6)} ... '
        '${_receivingShieldedAddress.substring(_receivingShieldedAddress.length - 5)}',
      ),
      findsOneWidget,
    );
    expect(find.text('Transparent'), findsOneWidget);

    final fromY = tester.getTopLeft(find.text('From')).dy;
    final amountY = tester.getTopLeft(find.text('Amount')).dy;
    expect(fromY, lessThan(amountY));
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

  testWidgets('long one-line memo preview does not overflow on mobile width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const memo = 'ㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎㅎ';
    await tester.pumpWidget(_app(_tx(), detail: _detail(memo: memo)));
    await tester.pumpAndSettle();

    expect(find.text('Message'), findsOneWidget);
    final previewText = tester.widget<Text>(
      find.text('${memo.substring(0, 18)}...'),
    );
    expect(previewText.maxLines, 1);
    expect(previewText.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no memo means no message row', (tester) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();
    expect(find.text('Message'), findsNothing);
  });
}

Future<void> _loadAppFonts() async {
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));

  await Future.wait([youngSerif.load(), geist.load()]);
}
