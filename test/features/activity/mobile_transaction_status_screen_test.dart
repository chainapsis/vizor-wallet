@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

String _reverseHexBytes(String hex) {
  final bytes = [
    for (var index = 0; index < hex.length; index += 2)
      hex.substring(index, index + 2),
  ];
  return bytes.reversed.join();
}

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
  String txid = _txid,
  BigInt? minedHeight,
  bool expired = false,
  BigInt? fee,
  String displayPool = 'shielded',
  BigInt? blockTime,
  BigInt? createdTime,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expired,
    accountBalanceDelta: 0,
    fee: fee ?? BigInt.from(15000),
    blockTime: blockTime ?? BigInt.from(1750000000),
    isTransparent: false,
    txKind: kind,
    displayAmount: BigInt.from(12312000000),
    displayPool: displayPool,
    createdTime: createdTime ?? BigInt.from(1750000000),
  );
}

rust_sync.TransactionDetail _detail({
  String kind = 'sent',
  String txid = _txid,
  String? primaryAddress,
  String? sourceAddress,
  String? sourcePool,
  String? memo,
  List<rust_sync.TransactionDetailOutput> outputs = const [],
}) {
  return rust_sync.TransactionDetail(
    txidHex: txid,
    txKind: kind,
    primaryAddress: primaryAddress ?? _address,
    sourceAddress: sourceAddress,
    sourcePool: sourcePool,
    memo: memo,
    outputs: outputs,
  );
}

GiftCardActivityMetadata _giftCard({
  GiftCardActivityKind kind = GiftCardActivityKind.created,
  BigInt? amountZatoshi,
  String? message,
  DateTime? activityTimestamp,
  bool isClaimInFlight = false,
  PaymentLinkFiatSnapshot? fiatSnapshot,
}) {
  return GiftCardActivityMetadata(
    kind: kind,
    amountZatoshi: amountZatoshi ?? BigInt.from(100000),
    artworkId: 'ruby',
    message: message,
    activityTimestamp: activityTimestamp,
    isClaimInFlight: isClaimInFlight,
    fiatSnapshot: fiatSnapshot,
    claimFeeReserveZatoshi: BigInt.from(20000),
  );
}

Widget _app(
  rust_sync.TransactionInfo tx, {
  rust_sync.TransactionDetail? detail,
  GiftCardActivityMetadata? giftCard,
  GiftCardActivityIndex giftCardIndex = GiftCardActivityIndex.empty,
  GiftCardActivityIndex Function()? giftCardIndexLoader,
  AccountNotifier? accountNotifier,
  List<AddressBookContact> contacts = const [],
  Map<String, AccountInfo> ownAccounts = const {},
  bool pricingEnabled = true,
  bool privacyEnabled = false,
  String? routeTxid,
  List<rust_sync.TransactionInfo>? history,
}) {
  final resolvedDetail = detail ?? _detail(kind: tx.txKind);
  return ProviderScope(
    overrides: [
      swapFeatureEnabledProvider.overrideWithValue(pricingEnabled),
      privacyModeProvider.overrideWith(() => _FixedPrivacy(privacyEnabled)),
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      ),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(contacts),
      ),
      ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
      giftCardActivityIndexProvider.overrideWith(
        (ref, _) async => giftCardIndexLoader?.call() ?? giftCardIndex,
      ),
      if (accountNotifier != null)
        accountProvider.overrideWith(() => accountNotifier),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: MobileTransactionStatusScreen(
          args: MobileTransactionStatusArgs(
            txidHex: routeTxid ?? tx.txidHex,
            txKind: tx.txKind,
            initialTransaction: tx,
            initialDetail: resolvedDetail,
            giftCard: giftCard,
          ),
          historyLoader: (_) async => history ?? [tx],
          detailLoader: (_, _) async => resolvedDetail,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('redeemed receipt refreshes when only the network fee arrives', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final initial = _tx(kind: 'received', fee: BigInt.zero);
    final history = [initial];
    await tester.pumpWidget(
      _app(
        initial,
        history: history,
        giftCard: _giftCard(kind: GiftCardActivityKind.redeemed),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileTransactionStatusScreen)),
    );
    final notifier = container.read(syncProvider.notifier) as FakeSyncNotifier;
    notifier.setSyncState(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        recentTransactions: [initial],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('--'), findsOneWidget);
    final enriched = _tx(kind: 'received', fee: BigInt.from(15000));
    history[0] = enriched;
    notifier.setSyncState(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        recentTransactions: [enriched],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.00015 ZEC'), findsOneWidget);
    expect(find.text('--'), findsNothing);
  });

  for (final fee in [0, 15000]) {
    testWidgets('redeemed card keeps the fee row with fee $fee', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          _tx(kind: 'received', fee: BigInt.from(fee)),
          giftCard: _giftCard(kind: GiftCardActivityKind.redeemed),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Redeemed a gift card'), findsOneWidget);
      expect(find.text('Tx fee'), findsOneWidget);
      expect(find.text('Card fee'), findsNothing);
      expect(find.text(fee == 0 ? '--' : '0.00015 ZEC'), findsOneWidget);
      // The sender's reserve must not be substituted or added here.
      expect(find.text('0.0002 ZEC'), findsNothing);
      expect(find.text('0.00035 ZEC'), findsNothing);
    });
  }

  for (final settings in [(true, false), (false, false), (true, true)]) {
    testWidgets(
      'card detail fiat gates $settings and aggregates the saved reserve',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _app(
            _tx(),
            giftCard: _giftCard(
              fiatSnapshot: const PaymentLinkFiatSnapshot(amount: 142.23),
            ),
            pricingEnabled: settings.$1,
            privacyEnabled: settings.$2,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Amount'), findsNothing);
        expect(find.text('Card fee'), findsOneWidget);
        expect(find.text('Tx fee'), findsNothing);
        expect(
          find.text(r'$142.23'),
          settings.$1 && !settings.$2 ? findsOneWidget : findsNothing,
        );
        if (!settings.$2) {
          expect(find.text('0.00035 ZEC'), findsOneWidget);
          await tester.tap(find.text('0.00035 ZEC'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Includes the creation fee and the fee reserved for claiming.',
            ),
            findsOneWidget,
          );
        }
      },
    );
  }

  setUpAll(_loadAppFonts);

  testWidgets('renders the complete receipt on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pump();

    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
  });

  testWidgets(
    'Gift Card detail resolves a reversed wallet txid and reaches completed',
    (tester) async {
      final storageTxid = _reverseHexBytes(_txid);
      final claimTime = DateTime.utc(2026, 9, 7, 12, 16);
      final placeholder = _tx(
        kind: 'receiving',
        txid: _txid,
        minedHeight: BigInt.zero,
        blockTime: BigInt.zero,
        createdTime: BigInt.zero,
      );
      final actual = _tx(
        kind: 'received',
        txid: storageTxid,
        minedHeight: BigInt.from(2500000),
      );
      final giftCard = _giftCard(
        kind: GiftCardActivityKind.redeemed,
        activityTimestamp: claimTime,
      );

      await tester.pumpWidget(
        _app(
          placeholder,
          routeTxid: _txid,
          history: [actual],
          detail: _detail(kind: 'received', txid: storageTxid),
          giftCard: giftCard,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redeemed'), findsOneWidget);
      expect(find.text(formatActivityTimestamp(claimTime)), findsOneWidget);
      expect(find.text('0.001'), findsOneWidget);
      expect(find.text('Amount'), findsNothing);
    },
  );

  testWidgets(
    'a mined gift receipt uses live claim state instead of stale route metadata',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tx = _tx(kind: 'received');
      final pending = GiftCardActivityMetadata(
        kind: GiftCardActivityKind.redeemed,
        amountZatoshi: BigInt.from(100000),
        artworkId: 'ruby',
        message: null,
        isClaimInFlight: true,
      );
      GiftCardActivityIndex index(GiftCardActivityMetadata metadata) =>
          GiftCardActivityIndex(
            redeemedTxids: {_txid},
            redeemedMetadataByTxid: {_txid: metadata},
          );
      var currentIndex = index(pending);
      await tester.pumpWidget(
        _app(tx, giftCard: pending, giftCardIndexLoader: () => currentIndex),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Redeeming...'), findsOneWidget);
      currentIndex = index(_giftCard(kind: GiftCardActivityKind.redeemed));
      ProviderScope.containerOf(
        tester.element(find.byType(MobileTransactionStatusScreen)),
      ).invalidate(giftCardActivityIndexProvider('account-1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Redeemed'), findsOneWidget);
    },
  );

  testWidgets('Gift Card detail shows the promised amount, not its funding', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(_tx(), giftCard: _giftCard()));
    await tester.pumpAndSettle();

    expect(find.text('0.001'), findsOneWidget);
    expect(find.text('Amount'), findsNothing);
    expect(find.text('123.12 ZEC'), findsNothing);
  });

  testWidgets('Gift Card receipt titles the card and hides the link address', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(_tx(), giftCard: _giftCard(message: 'Happy birthday!')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Created a gift card'), findsOneWidget);
    expect(find.text('Sent successfully'), findsNothing);
    // The single-use link address is not a counterparty worth verifying.
    expect(find.text('To'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_tx_status_show_full_address')),
      findsNothing,
    );
    expect(
      find.text(
        '${_address.substring(0, 6)} ... '
        '${_address.substring(_address.length - 5)}',
      ),
      findsNothing,
    );
    expect(find.byType(PaymentLinkGiftCard), findsOneWidget);

    expect(find.text('Message'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_tx_status_message_toggle')),
    );
    await tester.pump();
    expect(find.text('Happy birthday!'), findsOneWidget);
  });

  testWidgets(
    'Gift Card receipt drops route metadata after an account switch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final accountNotifier = _SwitchableAccountNotifier();
      await tester.pumpWidget(
        _app(
          _tx(),
          giftCard: _giftCard(message: 'Happy birthday!'),
          accountNotifier: accountNotifier,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Created a gift card'), findsOneWidget);
      expect(find.byType(PaymentLinkGiftCard), findsOneWidget);

      // account-2's index knows nothing about this txid, so the receipt must
      // fall back to the generic one instead of keeping account-1's card.
      accountNotifier.setActiveAccount('account-2');
      await tester.pumpAndSettle();

      expect(find.text('Created a gift card'), findsNothing);
      expect(find.byType(PaymentLinkGiftCard), findsNothing);
      expect(find.text('Message'), findsNothing);
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
    },
  );

  testWidgets('Gift Card receipt resolves metadata the route did not carry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        _tx(),
        giftCardIndex: GiftCardActivityIndex(
          createdTxids: const {_txid},
          createdMetadataByTxid: {_txid: _giftCard()},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Created a gift card'), findsOneWidget);
    expect(find.text('0.001'), findsOneWidget);
    expect(find.text('Amount'), findsNothing);
    // Not the raw funding total the transaction carries.
    expect(find.text('123.12 ZEC'), findsNothing);
  });

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

  testWidgets('received tx from a saved contact shows the contact name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _tx(kind: 'received', fee: BigInt.zero),
        detail: _detail(
          kind: 'received',
          sourceAddress: _transparentSenderAddress,
          sourcePool: 'transparent',
        ),
        contacts: [
          AddressBookContact(
            id: 'contact-1',
            label: 'Mom',
            network: AddressBookNetwork.zcash,
            address: _transparentSenderAddress,
            profilePictureId: kDefaultProfilePictureId,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The From row headline becomes the contact name; the raw address is
    // demoted to the pool strip below (parity with the desktop receipt).
    expect(find.text('Mom'), findsOneWidget);
    expect(
      find.text(
        '${_transparentSenderAddress.substring(0, 6)} ... '
        '${_transparentSenderAddress.substring(_transparentSenderAddress.length - 5)}',
      ),
      findsOneWidget,
    );
    // The leading badge swaps from the wallet icon to the contact's avatar —
    // the visible half of the named-counterparty path (M1).
    expect(find.byType(AppProfilePicture), findsOneWidget);
  });

  testWidgets('shielding tx shows the transparent -> shielded balance flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_tx(kind: 'shielded', displayPool: 'shielded')),
    );
    await tester.pumpAndSettle();

    // Two-row flow mirroring the desktop ShieldedReceiptView (no external
    // counterparty): Amount/from-transparent above the shielded destination.
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('From transparent balance'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Shielded balance'), findsOneWidget);

    final amountY = tester.getTopLeft(find.text('Amount')).dy;
    final toY = tester.getTopLeft(find.text('To')).dy;
    expect(amountY, lessThan(toY));
  });

  testWidgets('migration tx shows the Orchard -> Ironwood balance flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _tx(kind: 'migration', displayPool: 'ironwood'),
        detail: _detail(kind: 'migration'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Migrated to Ironwood'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('From Orchard balance'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Ironwood balance'), findsOneWidget);
    expect(find.text('Ironwood'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text(_address), findsNothing);
  });

  testWidgets('tapping the tx fee help opens the fee info sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    expect(find.textContaining('ZIP 317'), findsNothing);

    // The Tx fee help glyph renders in the muted icon tint the session added:
    // icon.regular @ 0.72 alpha, NOT the default accent color.
    final helpIcon = tester.widget<AppIcon>(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.help,
      ),
    );
    final iconColors = AppThemeData.light.colors.icon;
    expect(helpIcon.color, isNotNull);
    expect(helpIcon.color, isNot(iconColors.accent));
    expect(helpIcon.color, iconColors.regular.withValues(alpha: 0.72));
    expect(helpIcon.color!.a, closeTo(0.72, 0.005));

    // The fee value wraps the help icon in a tap target wired to the shared
    // fee-info bottom sheet.
    await tester.tap(find.text('0.00015 ZEC'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ZIP 317'), findsOneWidget);
  });
}

class _SwitchableAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
      AccountInfo(
        uuid: 'account-2',
        name: 'Account2',
        order: 1,
        profilePictureId: kDefaultProfilePictureId,
      ),
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

Future<void> _loadAppFonts() async {
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));

  await Future.wait([youngSerif.load(), geist.load()]);
}

class _FixedPrivacy extends PrivacyModeNotifier {
  _FixedPrivacy(this.enabled);
  final bool enabled;
  @override
  bool build() => enabled;
}
