@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FontLoader, rootBundle, MethodChannel, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/zcash/spendable_wait.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart'
    show kPaymentLinkMobileCardHeight, kPaymentLinkMobileCardWidth;
import 'package:zcash_wallet/src/features/activity/widgets/mobile/transaction_type_hero.dart';
import 'package:zcash_wallet/src/features/activity/activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/spendable_wait_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/core/privacy/privacy_mask.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../fakes/fake_enhance_pir_notifier.dart';
import '../../support/test_l10n.dart';

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
  String? activityPool,
  BigInt? blockTime,
  BigInt? createdTime,
  rust_sync.TransactionFeeState feeState = rust_sync.TransactionFeeState.known,
  bool detailsComplete = true,
  bool provisional = false,
  bool awaitsPrivateCheck = false,
  bool amountIncludesFee = false,
  BigInt? displayAmount,
  int accountBalanceDelta = 0,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: minedHeight ?? BigInt.from(2500000),
    expiredUnmined: expired,
    accountBalanceDelta: accountBalanceDelta,
    fee: fee ?? BigInt.from(15000),
    feeState: feeState,
    detailsComplete: detailsComplete,
    provisional: provisional,
    awaitsPrivateCheck: awaitsPrivateCheck,
    amountIncludesFee: amountIncludesFee,
    blockTime: blockTime ?? BigInt.from(1750000000),
    isTransparent: displayPool == 'transparent',
    txKind: kind,
    displayAmount: displayAmount ?? BigInt.from(12312000000),
    displayPool: displayPool,
    activityPool: activityPool,
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
  bool hasRecipient = true,
  BigInt? networkFee,
}) {
  return rust_sync.TransactionDetail(
    txidHex: txid,
    networkFee: networkFee,
    detailsComplete: true,
    provisional: false,
    txKind: kind,
    primaryAddress: hasRecipient ? primaryAddress ?? _address : null,
    sourceAddress: sourceAddress,
    sourcePool: sourcePool,
    memo: memo,
    outputs: outputs,
    transparentRecipients: const [],
    transparentOmissions: const [],
  );
}

GiftCardActivityMetadata _giftCard({
  GiftCardActivityKind kind = GiftCardActivityKind.created,
  BigInt? amountZatoshi,
  String? message,
  DateTime? activityTimestamp,
  bool isClaimInFlight = false,
  PaymentLinkFiatSnapshot? fiatSnapshot,
  String? displayPool,
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
    displayPool: displayPool,
  );
}

/// A pool named by a row's glyph (its screen-reader label); the record's top
/// shows only the coin, status, amount and dollar value.
Finder _poolIcon(String label) =>
    find.byWidgetPredicate((w) => w is AppIcon && w.semanticLabel == label);

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
  bool privateQueriesEnabled = false,
  rust_sync.TransparentStopReason? transparentStop,
  String? routeTxid,
  List<rust_sync.TransactionInfo>? history,
  Map<String, ReceivedSpendableWait>? spendableWaits,
  double? zecUsdPrice,
}) {
  final resolvedDetail = detail ?? _detail(kind: tx.txKind);
  return ProviderScope(
    overrides: [
      if (spendableWaits != null)
        activeReceivedSpendableWaitsProvider.overrideWithValue(spendableWaits),
      if (zecUsdPrice != null)
        zecHomeUsdUnitPriceProvider.overrideWithValue(zecUsdPrice),
      swapFeatureEnabledProvider.overrideWithValue(pricingEnabled),
      privacyModeProvider.overrideWith(() => _FixedPrivacy(privacyEnabled)),
      enhancePirProvider.overrideWith(
        () => FakeEnhancePirNotifier(privateQueriesEnabled),
      ),
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            transparentStop: transparentStop,
          ),
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
      localizationsDelegates: appLocalizationsDelegates,
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
          historyLoader: (_, _) async => history ?? [tx],
          detailLoader: (_, _) async => resolvedDetail,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'recovered mobile receipt shows known network fee without attribution',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tx = _tx(
        fee: BigInt.zero,
        feeState: rust_sync.TransactionFeeState.unknown,
      );
      await tester.pumpWidget(
        _app(
          tx,
          privateQueriesEnabled: true,
          detail: _detail(networkFee: BigInt.from(15000)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Network fee'), findsOneWidget);
      expect(find.text('0.00015 ZEC'), findsOneWidget);
      expect(find.text(testL10n.commonUnknown), findsNothing);
      expect(tx.feeState, rust_sync.TransactionFeeState.unknown);
      expect(tx.fee, BigInt.zero);
      await tester.tap(find.text('0.00015 ZEC'));
      await tester.pumpAndSettle();
      expect(
        find.text(testL10n.activityReceiptUnattributedFeeHelp),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'older mobile receipt refreshes on sync completion without recent changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final initial = _tx(
        fee: BigInt.zero,
        feeState: rust_sync.TransactionFeeState.unknown,
        detailsComplete: false,
        provisional: true,
      );
      final history = [initial];
      await tester.pumpWidget(
        _app(initial, history: history, privateQueriesEnabled: true),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileTransactionStatusScreen)),
      );
      final notifier =
          container.read(syncProvider.notifier) as FakeSyncNotifier;
      final recent = List.generate(
        10,
        (i) => _tx(txid: '${i + 1}'.padLeft(64, '0')),
      );
      notifier.setSyncState(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
          recentTransactions: recent,
        ),
      );
      await tester.pumpAndSettle();
      history[0] = _tx(kind: 'shielded');
      notifier.setSyncState(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: false,
          isSyncComplete: true,
          recentTransactions: recent,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
        findsNothing,
      );
      expect(find.text(testL10n.commonUnknown), findsNothing);
      expect(find.text('Transparent balance'), findsOneWidget);
    },
  );

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
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        _tx(txid: protocolTxid, kind: 'receiving', minedHeight: BigInt.zero),
        giftCard: _giftCard(
          kind: GiftCardActivityKind.redeemed,
          isClaimInFlight: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(truncatedTxid(displayTxid)), findsOneWidget);
    await tester.tap(find.text(truncatedTxid(displayTxid)));
    await tester.pump();
    expect(launched, hasLength(1));
    expect(Uri.parse(launched.single).path, '/tx/$displayTxid');
    expect(copied, [displayTxid]);
  });

  testWidgets(
    'an expired claim leg stays pending while the card is receiving',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          _tx(kind: 'receiving', minedHeight: BigInt.zero, expired: true),
          giftCard: _giftCard(
            kind: GiftCardActivityKind.redeemed,
            isClaimInFlight: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Redeeming a card...'), findsOneWidget);
      expect(find.text('Redeeming…'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byWidgetPredicate(
            (w) => w is AppIcon && w.name == AppIcons.loader,
          ),
          matching: find.byType(RotationTransition),
        ),
        findsNothing,
      );
      expect(find.text('Failed'), findsNothing);
      expect(find.text('Refunded'), findsNothing);
    },
  );

  for (final feeState in rust_sync.TransactionFeeState.values) {
    testWidgets('ordinary receive shows no fee: $feeState', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          _tx(kind: 'received', fee: BigInt.from(15000), feeState: feeState),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tx fee'), findsNothing);
      expect(find.text('0.00015 ZEC'), findsNothing);
    });
  }

  testWidgets('a receipt that cannot be spent yet says when and counts its '
      'confirmations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final received = _tx(
      kind: 'received',
      fee: BigInt.zero,
      minedHeight: BigInt.from(2500000),
    );
    await tester.pumpWidget(
      _app(
        received,
        spendableWaits: {
          received.txidHex: (
            wait: const AvailableIn.minutes(1, 2),
            confirmations: 2,
            requiredConfirmations: 6,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available in 1–2 min'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    expect(find.text('Confirmations'), findsOneWidget);
    expect(find.text('2 of 6'), findsOneWidget);
  });

  testWidgets('ordinary receive shows no fee even when history is enriched', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final initial = _tx(kind: 'received', fee: BigInt.zero);
    final history = [initial];
    await tester.pumpWidget(_app(initial, history: history));
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
    expect(find.text('Tx fee'), findsNothing);
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
    expect(find.text('Tx fee'), findsNothing);
    expect(find.text('0.00015 ZEC'), findsNothing);
  });

  testWidgets('redeemed receipt shows no fee before or after the fee arrives', (
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
    expect(find.text('Tx fee'), findsNothing);
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
    expect(find.text('Tx fee'), findsNothing);
    expect(find.text('0.00015 ZEC'), findsNothing);
  });

  for (final fee in [0, 15000]) {
    testWidgets('redeemed card shows no fee row with fee $fee', (tester) async {
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
      // Redeeming a card is a receive, so it shows no network fee.
      expect(find.text('Tx fee'), findsNothing);
      expect(find.text('Card fee'), findsNothing);
      expect(find.text('0.00015 ZEC'), findsNothing);
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
        if (settings.$2) {
          final card = find.byType(PaymentLinkGiftCard);
          // The card shows its art alone; the masked amount sits under it.
          expect(tester.widget<PaymentLinkGiftCard>(card).showAmount, isFalse);
          expect(_heroAmount(tester), isNot(contains('0.001')));
          const captureDir = String.fromEnvironment('GIFT_CARD_CAPTURE_DIR');
          if (captureDir.isNotEmpty) {
            await expectLater(
              card,
              matchesGoldenFile('$captureDir/mobile-private-detail.png'),
            );
          }
        }
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

    // The record opens on its type's icon in liquid metal: a send's plane.
    expect(find.byKey(const ValueKey('mobile_tx_type_hero')), findsOneWidget);
    expect(
      tester
          .widget<TransactionTypeHero>(find.byType(TransactionTypeHero))
          .iconName,
      AppIcons.plane,
    );
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('123.12 ZEC'), findsOneWidget);
    expect(find.text('Recipient'), findsOneWidget);
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
      expect(
        find.text(formatActivityTimestamp(testL10n, claimTime)),
        findsOneWidget,
      );
      expect(_heroAmount(tester), contains('0.001'));
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
      expect(find.text('Redeeming…'), findsOneWidget);
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

    expect(_heroAmount(tester), contains('0.001'));
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
    expect(find.text('Sent ZEC'), findsNothing);
    // The single-use link address is not a counterparty worth verifying.
    expect(find.text('Recipient'), findsNothing);
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
    // The card replaces the type icon, at 70% of the full-width card.
    expect(find.byType(TransactionTypeHero), findsNothing);
    // Drawn size: the card lays out full size and is scaled down.
    final cardSize = tester.getRect(find.byType(PaymentLinkGiftCard)).size;
    expect(cardSize.width, closeTo(kPaymentLinkMobileCardWidth * 0.7, 0.5));
    expect(cardSize.height, closeTo(kPaymentLinkMobileCardHeight * 0.7, 0.5));

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
      expect(find.text('Sent ZEC'), findsOneWidget);
      expect(find.text('Recipient'), findsOneWidget);
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
    expect(_heroAmount(tester), contains('0.001'));
    expect(find.text('Amount'), findsNothing);
    // Not the raw funding total the transaction carries.
    expect(find.text('123.12 ZEC'), findsNothing);
  });

  testWidgets('the dollar value sits under the amount in place of the pool', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx(), zecUsdPrice: 2));
    await tester.pumpAndSettle();

    final fiat = find.byKey(const ValueKey('mobile_tx_status_fiat'));
    expect(fiat, findsOneWidget);
    expect(tester.widget<Text>(fiat).data, startsWith(r'$'));
    // Below the amount, above the card.
    expect(
      tester.getTopLeft(fiat).dy,
      greaterThan(
        tester
                .getBottomLeft(
                  find.byKey(const ValueKey('mobile_tx_status_amount')),
                )
                .dy -
            1,
      ),
    );
    // A send's pool stays on the recipient row's icon.
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('privacy mode masks the dollar value with the amount', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx(), zecUsdPrice: 2, privacyEnabled: true));
    await tester.pumpAndSettle();

    final fiat = find.byKey(const ValueKey('mobile_tx_status_fiat'));
    expect(fiat, findsOneWidget);
    expect(tester.widget<Text>(fiat).data, fixedPrivacyMask());
  });

  testWidgets('the castle engraving fades in behind a light record', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_tx_status_backdrop')),
      findsOneWidget,
    );
  });

  testWidgets('mined sent tx shows success title, chip, fee, and address', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    expect(find.text('Sent ZEC'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    // The amount heads the hero without a row label.
    expect(find.text('Amount'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('mobile_tx_status_amount')))
          .textSpan!
          .toPlainText(),
      '123.12 ZEC',
    );
    expect(find.text('Recipient'), findsOneWidget);
    // Figma-style 6 ... 5 truncation of the recipient.
    expect(find.text('u1l8xu ... d5gh'.replaceAll('  ', ' ')), findsNothing);
    expect(
      find.text(
        '${_address.substring(0, 6)} ... ${_address.substring(_address.length - 5)}',
      ),
      findsOneWidget,
    );
    expect(_poolIcon('Shielded'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.00015 ZEC'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('efcdab89...67452301'), findsOneWidget);
  });

  testWidgets(
    'a provisional debit shows an unknown fee and incomplete details',
    (tester) async {
      await tester.pumpWidget(
        _app(
          _tx(
            fee: BigInt.zero,
            displayPool: 'unknown',
            feeState: rust_sync.TransactionFeeState.unknown,
            detailsComplete: false,
            provisional: true,
          ),
          privateQueriesEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tx fee'), findsOneWidget);
      expect(find.text(testL10n.commonUnknown), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
        findsOneWidget,
      );
      expect(find.text('Incomplete'), findsOneWidget);
    },
  );

  testWidgets('a fee-only entry remains one neutral net change line', (
    tester,
  ) async {
    // Reconstructed zero external payment; recipient details can be missing.
    final tx = _tx(
      fee: BigInt.from(65000),
      displayAmount: BigInt.from(65000),
      displayPool: 'transparent',
      amountIncludesFee: true,
      detailsComplete: false,
      accountBalanceDelta: -65000,
    );
    await tester.pumpWidget(
      _app(
        tx,
        detail: _detail(hasRecipient: false),
        privateQueriesEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('Sent ZEC'), findsNothing);
    expect(find.text(testL10n.activityReceiptNetChange), findsOneWidget);
    expect(find.text('0.00065 ZEC'), findsNWidgets(2)); // hero + Net change row
    expect(find.text('Amount'), findsNothing);
    expect(find.text('Tx fee'), findsNothing);
    expect(find.text('Recipient'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a provisional fee-sized movement keeps its net change and fee explanation',
    (tester) async {
      // A mixed-pool balance decrease does not establish a fee-only activity.
      final tx = _tx(
        fee: BigInt.from(20000),
        displayAmount: BigInt.from(20000),
        displayPool: 'unknown',
        amountIncludesFee: true,
        detailsComplete: false,
        provisional: true,
        accountBalanceDelta: -20000,
      );
      await tester.pumpWidget(
        _app(
          tx,
          detail: _detail(hasRecipient: false),
          privateQueriesEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('Sent ZEC'), findsNothing);
      expect(find.text('Network fee'), findsNothing);
      expect(find.text(testL10n.activityReceiptNetChange), findsOneWidget);
      expect(find.text('0.0002 ZEC'), findsNWidgets(3));
      expect(find.text('Amount'), findsNothing);
      expect(find.text('Tx fee'), findsOneWidget);
      expect(find.text('Recipient'), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
        findsOneWidget,
      );
    },
  );

  testWidgets('an amount that includes the fee is labelled a net change', (
    tester,
  ) async {
    final tx = _tx(
      fee: BigInt.from(10000),
      displayAmount: BigInt.from(70000000),
      displayPool: 'unknown',
      amountIncludesFee: true,
      detailsComplete: false,
      provisional: true,
    );
    await tester.pumpWidget(_app(tx, detail: _detail()));
    await tester.pumpAndSettle();

    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('Sent ZEC'), findsNothing);
    expect(find.text(testL10n.activityReceiptNetChange), findsOneWidget);
    expect(find.text('Amount'), findsNothing);
    // Nothing is subtracted, and the fee keeps its own line.
    expect(find.text('0.70 ZEC'), findsNWidgets(2)); // hero + Net change row
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.0001 ZEC'), findsOneWidget);
    expect(find.text('Network fee'), findsNothing);
  });

  for (final kind in ['sent', 'received', 'shielded', 'migration']) {
    for (final privateQueriesEnabled in [false, true]) {
      testWidgets(
        'feedback for $kind is private-only: $privateQueriesEnabled',
        (tester) async {
          await tester.pumpWidget(
            _app(
              _tx(
                kind: kind,
                fee: BigInt.zero,
                feeState: rust_sync.TransactionFeeState.unknown,
                detailsComplete: false,
                provisional: true,
              ),
              privateQueriesEnabled: privateQueriesEnabled,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
            privateQueriesEnabled ? findsOneWidget : findsNothing,
          );
          expect(
            find.text(testL10n.commonUnknown),
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
    await tester.pumpWidget(
      _app(
        _tx(
          fee: BigInt.zero,
          feeState: rust_sync.TransactionFeeState.unknown,
          provisional: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileTransactionStatusScreen)),
    );
    for (final enabled in [true, false]) {
      await container.read(enhancePirProvider.notifier).set(enabled);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
        enabled ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(testL10n.commonUnknown),
        enabled ? findsOneWidget : findsNothing,
      );
      expect(find.text('Tx fee'), enabled ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('a provisional entry follows its transaction to a new role', (
    tester,
  ) async {
    final provisional = _tx(
      displayPool: 'unknown',
      feeState: rust_sync.TransactionFeeState.unknown,
      detailsComplete: false,
      provisional: true,
    );
    await tester.pumpWidget(
      _app(
        provisional,
        history: [_tx(kind: 'shielded', displayPool: 'shielded')],
        privateQueriesEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transparent balance'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
      findsNothing,
    );
  });

  testWidgets('a provisional entry never picks one leg of several', (
    tester,
  ) async {
    final provisional = _tx(
      displayPool: 'unknown',
      feeState: rust_sync.TransactionFeeState.unknown,
      detailsComplete: false,
      provisional: true,
    );
    await tester.pumpWidget(
      _app(
        provisional,
        history: [
          _tx(kind: 'shielded', displayPool: 'shielded'),
          _tx(kind: 'received', displayPool: 'shielded'),
        ],
        privateQueriesEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('From transparent balance'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
      findsOneWidget,
    );
  });

  testWidgets('known payment details still mark unsettled effects', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_tx(provisional: true), privateQueriesEnabled: true),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
      findsOneWidget,
    );
  });

  testWidgets('a receipt waiting on the private check says so', (tester) async {
    await tester.pumpWidget(
      _app(
        // Not read again yet: nothing known, as right after Private queries
        // is turned on.
        _tx(
          provisional: true,
          awaitsPrivateCheck: true,
          detailsComplete: false,
        ),
        privateQueriesEnabled: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
      findsOneWidget,
    );
    expect(
      find.text(testL10n.activityReceiptCheckingPrivately),
      findsOneWidget,
    );

    await tester.tap(find.text(testL10n.activityReceiptCheckingPrivately));
    await tester.pumpAndSettle();
    expect(
      find.text(testL10n.activityReceiptCheckingPrivatelyHelp),
      findsOneWidget,
    );
  });

  testWidgets('a stopped private recovery keeps the incomplete row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _tx(provisional: true, awaitsPrivateCheck: true),
        privateQueriesEnabled: true,
        transparentStop: rust_sync.TransparentStopReason.stalled,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Incomplete'), findsOneWidget);
    expect(find.text(testL10n.activityReceiptCheckingPrivately), findsNothing);

    // Its help says why.
    await tester.tap(find.text('Incomplete'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(testL10n.homeTransparentStopStalled),
      findsOneWidget,
    );
  });

  testWidgets('a complete receipt has no incomplete-details row', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx(), privateQueriesEnabled: true));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_tx_status_details_incomplete')),
      findsNothing,
    );
    expect(find.text(testL10n.commonUnknown), findsNothing);
  });

  testWidgets('sent TEX tx keeps a TEX recipient label', (tester) async {
    await tester.pumpWidget(
      _app(
        _tx(displayPool: 'transparent'),
        detail: _detail(primaryAddress: _texAddress),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sent ZEC'), findsOneWidget);
    expect(_poolIcon('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(
      find.text(
        '${_texAddress.substring(0, 6)} ... ${_texAddress.substring(_texAddress.length - 5)}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sent receipt shows the exact pool without adding rows', (
    tester,
  ) async {
    for (final (pool, label) in [
      ('ironwood', 'Shielded'),
      ('orchard', 'Orchard'),
      ('sapling', 'Sapling'),
      ('mixed', 'Mixed'),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(_tx(activityPool: pool)));
      await tester.pumpAndSettle();
      expect(_poolIcon(label), findsOneWidget);
      expect(find.text('Recipient'), findsOneWidget);
      expect(find.text('From'), findsNothing);
      expect(find.text('Sent ZEC'), findsOneWidget);
    }
  });

  testWidgets('TEX address badge takes precedence over the pool label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _tx(displayPool: 'transparent', activityPool: 'transparent'),
        detail: _detail(primaryAddress: _texAddress),
      ),
    );
    await tester.pumpAndSettle();
    expect(_poolIcon('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
  });

  testWidgets('gift card receipt keeps pool details hidden', (tester) async {
    for (final pool in ['ironwood', 'shielded', 'orchard', 'sapling']) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(
          _tx(activityPool: 'ironwood'),
          giftCard: _giftCard(displayPool: pool),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Created a gift card'), findsOneWidget);
      expect(find.text('Ironwood'), findsNothing);
      expect(find.text('Shielded'), findsNothing);
      expect(find.text('Orchard'), findsNothing);
      expect(find.text('Sapling'), findsNothing);
      expect(find.text('Recipient'), findsNothing);
    }
  });

  testWidgets('sent receipt updates when only the exact pool is enriched', (
    tester,
  ) async {
    final initial = _tx();
    final history = [initial];
    await tester.pumpWidget(_app(initial, history: history));
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
    expect(_poolIcon('Shielded'), findsOneWidget);

    final enriched = _tx(activityPool: 'orchard');
    history[0] = enriched;
    notifier.setSyncState(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        recentTransactions: [enriched],
      ),
    );
    await tester.pumpAndSettle();
    expect(_poolIcon('Orchard'), findsOneWidget);
    expect(_poolIcon('Shielded'), findsNothing);
    expect(find.text('Sent ZEC'), findsOneWidget);
  });

  testWidgets('unmined sent tx shows the in-progress state', (tester) async {
    await tester.pumpWidget(_app(_tx(minedHeight: BigInt.zero)));
    // No pumpAndSettle — the in-progress loader spins forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sending ZEC...'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('expired tx shows the failed state with strikethrough', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_tx(minedHeight: BigInt.zero, expired: true)));
    await tester.pumpAndSettle();

    expect(find.text('Send ZEC failed'), findsOneWidget);
    expect(find.text('Failed, funds returned'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is AppIcon && w.name == AppIcons.cancel),
      findsOneWidget,
    );

    final addressText = tester.widget<Text>(
      find.text(
        '${_address.substring(0, 6)} ... ${_address.substring(_address.length - 5)}',
      ),
    );
    expect(addressText.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('received tx names the sender in the detail card', (
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Received ZEC'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    // Hero amount first, then the card that opens with the sender.
    final amountY = tester
        .getTopLeft(find.byKey(const ValueKey('mobile_tx_status_amount')))
        .dy;
    final fromY = tester.getTopLeft(find.text('From')).dy;
    expect(amountY, lessThan(fromY));
    expect(fromY, lessThan(tester.getTopLeft(find.text('Tx ID')).dy));
    // The row's glyph names the pool; the top shows only coin, status,
    // amount and dollar value.
    expect(find.text('Transparent'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.semanticLabel == 'Transparent',
      ),
      findsOneWidget,
    );
    // Received txs report no fee — the fee section is dropped.
    expect(find.text('Tx fee'), findsNothing);
  });

  testWidgets('a received amount reads as money in', (tester) async {
    await tester.pumpWidget(
      _app(
        _tx(kind: 'received', fee: BigInt.zero),
        detail: _detail(kind: 'received'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('mobile_tx_status_amount')))
          .textSpan!
          .toPlainText(),
      '+123.12 ZEC',
    );
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
    expect(find.text(_address), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
  });

  testWidgets('recipient row fits on mobile width and names its action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app(_tx()));
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey('mobile_tx_status_show_full_address'),
    );
    expect(action, findsOneWidget);
    // Figma `Recipient` row: pool glyph, truncated address, chevron.
    for (final icon in [AppIcons.shieldKeyhole, AppIcons.chevronForward]) {
      expect(
        find.descendant(
          of: action,
          matching: find.byWidgetPredicate(
            (w) => w is AppIcon && w.name == icon,
          ),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Show full address'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Show full address')), findsOneWidget);
    expect(tester.getRect(action).right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    semantics.dispose();
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
              usesOrchardReceiver: false,
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
    // The wallet's own receiving address is not shown: under the amount it
    // read as the sender, whom Zcash never reveals.
    expect(
      find.text(
        '${_receivingShieldedAddress.substring(0, 6)} ... '
        '${_receivingShieldedAddress.substring(_receivingShieldedAddress.length - 5)}',
      ),
      findsNothing,
    );
    // The sender's pool is named by its row glyph alone.
    expect(find.text('Transparent'), findsNothing);
    expect(_poolIcon('Transparent'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('mobile_tx_status_amount')))
          .dy,
      lessThan(tester.getTopLeft(find.text('From')).dy),
    );
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

  testWidgets('zero-value receipt shows 0 ZEC and its memo', (tester) async {
    const memo = 'Zcash is a privacy protecting digital currency.';
    await tester.pumpWidget(
      _app(
        _tx(kind: 'received', fee: BigInt.zero, displayAmount: BigInt.zero),
        detail: _detail(kind: 'received', sourcePool: 'shielded', memo: memo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Received ZEC'), findsOneWidget);
    expect(find.text('0.00 ZEC'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_tx_status_message_toggle')),
    );
    await tester.pump();
    expect(find.text(memo), findsOneWidget);
  });

  testWidgets('zero-value send shows 0 ZEC with its fee and memo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _tx(displayAmount: BigInt.zero),
        detail: _detail(memo: 'Memo-only payment'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sent ZEC'), findsOneWidget);
    expect(find.text('0.00 ZEC'), findsOneWidget);
    expect(find.text('0.00015 ZEC'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('unknown tx keeps a neutral title instead of a send outcome', (
    tester,
  ) async {
    for (final minedHeight in [BigInt.from(2500000), BigInt.zero]) {
      final tx = _tx(
        kind: 'unknown',
        minedHeight: minedHeight,
        displayAmount: BigInt.zero,
      );
      await tester.pumpWidget(
        _app(
          tx,
          detail: rust_sync.TransactionDetail(
            txidHex: tx.txidHex,
            txKind: 'unknown',
            outputs: const [],
            detailsComplete: true,
            provisional: false,
            transparentRecipients: const [],
            transparentOmissions: const [],
          ),
        ),
      );
      // A pending tx spins a loader, so pump instead of settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('Sent ZEC'), findsNothing);
      expect(find.text('Sending ZEC...'), findsNothing);
      expect(find.text('Recipient'), findsNothing);
      expect(find.text('--'), findsOneWidget);
    }
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

    // The From row names the contact in place of the address (parity with
    // the desktop receipt); its chevron still opens the full address.
    expect(find.text('Mom'), findsOneWidget);
    expect(
      find.text(
        '${_transparentSenderAddress.substring(0, 6)} ... '
        '${_transparentSenderAddress.substring(_transparentSenderAddress.length - 5)}',
      ),
      findsNothing,
    );
    expect(_poolIcon('Transparent'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_tx_status_show_full_address')),
    );
    await tester.pumpAndSettle();
    expect(find.text(_transparentSenderAddress), findsOneWidget);
  });

  testWidgets('shielding tx shows the transparent -> shielded balance flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_tx(kind: 'shielded', displayPool: 'shielded')),
    );
    await tester.pumpAndSettle();

    // Mirrors the desktop ShieldedReceiptView (no external counterparty):
    // the amount from the transparent balance above the shielded destination.
    expect(find.text('Transparent balance'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Shielded balance'), findsOneWidget);

    final amountY = tester
        .getTopLeft(find.byKey(const ValueKey('mobile_tx_status_amount')))
        .dy;
    final sourceY = tester.getTopLeft(find.text('Transparent balance')).dy;
    final toY = tester.getTopLeft(find.text('To')).dy;
    expect(amountY, lessThan(sourceY));
    expect(sourceY, lessThan(toY));
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
    expect(find.text('Orchard balance'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Ironwood balance'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIcon && w.semanticLabel == 'Ironwood',
      ),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text(_address), findsNothing);
  });

  for (final privacyEnabled in [false, true]) {
    testWidgets('hero amount and fee follow privacy mode: $privacyEnabled', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_tx(), privacyEnabled: privacyEnabled));
      await tester.pumpAndSettle();

      expect(
        find.text('123.12 ZEC'),
        privacyEnabled ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('0.00015 ZEC'),
        privacyEnabled ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('•••••• ZEC'),
        privacyEnabled ? findsNWidgets(2) : findsNothing,
      );
    });
  }

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
    expect(helpIcon.color, iconColors.muted);

    // The fee value wraps the help icon in a tap target wired to the shared
    // fee-info bottom sheet. It sits below the hero, so scroll it into view.
    await tester.ensureVisible(find.text('0.00015 ZEC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0.00015 ZEC'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ZIP 317'), findsOneWidget);
  });
  group('saving the recipient', () {
    const addContact = ValueKey('mobile_tx_status_add_contact');

    testWidgets('a sent receipt offers to save an unsaved recipient', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_tx()));
      await tester.pumpAndSettle();

      expect(find.text('Add address to contacts'), findsOneWidget);
      expect(
        tester.widget<AppButton>(find.byKey(addContact)).variant,
        AppButtonVariant.primary,
      );

      await tester.tap(find.byKey(addContact));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile_pay_add_contact_card')),
        findsOneWidget,
      );
    });

    testWidgets('a recipient that is already a contact is not offered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _tx(),
          contacts: [
            AddressBookContact(
              id: 'contact-1',
              label: 'Mom',
              network: AddressBookNetwork.zcash,
              address: _address,
              profilePictureId: kDefaultProfilePictureId,
              createdAtMs: 1,
              updatedAtMs: 1,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mom'), findsOneWidget);
      expect(find.byKey(addContact), findsNothing);
    });

    testWidgets('received and failed receipts are not offered', (tester) async {
      await tester.pumpWidget(_app(_tx(kind: 'received')));
      await tester.pumpAndSettle();
      expect(find.byKey(addContact), findsNothing);

      await tester.pumpWidget(_app(_tx(expired: true)));
      await tester.pumpAndSettle();
      expect(find.byKey(addContact), findsNothing);
    });
  });
  testWidgets('each record type opens on its own icon', (tester) async {
    for (final (kind, icon) in [
      ('received', AppIcons.arrowDownCircle),
      ('shielded', AppIcons.shieldKeyhole),
    ]) {
      // A fresh record each time, not the previous one updated.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(_tx(kind: kind)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TransactionTypeHero>(find.byType(TransactionTypeHero))
            .iconName,
        icon,
        reason: kind,
      );
    }
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

/// The record's hero amount, which a Gift Card shows under its card.
String _heroAmount(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('mobile_tx_status_amount')))
    .textSpan!
    .toPlainText();
