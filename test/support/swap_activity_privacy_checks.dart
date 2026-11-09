import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_deposit_transaction_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../fakes/fake_sync_notifier.dart';

const _recipient = '0x12351aBcDeF01234567890123456789076123';
const _refundTo = '0x9876543210aBcDeF01234567890123456789fedc';
final _depositTxid = 'ab' * 32;
final _deadline = DateTime.now().add(const Duration(hours: 2));

/// Swap and Pay detail pages are record screens: privacy mode masks every
/// recorded amount and fee in text and semantics, keeps each leg's own symbol,
/// and updates in place when toggled (docs/privacy-mode.md).
void registerSwapActivityPrivacyChecks({required bool mobile}) {
  final layout = mobile
      ? SwapActivityDetailLayout.mobile
      : SwapActivityDetailLayout.desktop;
  final size = mobile ? const Size(390, 1400) : const Size(1080, 1400);

  Future<_Privacy> pump(
    WidgetTester tester,
    SwapIntent intent, {
    bool hardwareAccount = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final privacy = _Privacy();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          privacyModeProvider.overrideWith(() => privacy),
          swapStateProvider.overrideWith(() => _StaticSwapNotifier(intent)),
          accountProvider.overrideWith(
            () => _Accounts(hardware: hardwareAccount),
          ),
          addressBookProvider.overrideWith(_EmptyAddressBook.new),
          syncProvider.overrideWith(FakeSyncNotifier.new),
          payDepositTransactionLoaderProvider.overrideWithValue(
            ({required accountUuid, required walletTxid}) async =>
                _depositTransaction(walletTxid),
          ),
        ],
        child: MaterialApp(
          builder: (_, navigator) =>
              AppTheme(data: AppThemeData.light, child: navigator!),
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: AppToastHost(
              child: SwapActivityDetailSurface(
                intentId: intent.id,
                layout: layout,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return privacy;
  }

  Future<void> setPrivacy(
    WidgetTester tester,
    _Privacy privacy,
    bool enabled,
  ) async {
    await privacy.set(enabled);
    await tester.pump();
  }

  Future<void> openDetailsTab(WidgetTester tester) async {
    await tester.tap(
      find.byKey(
        ValueKey(
          mobile ? 'mobile_swap_status_tab_details' : 'swap_status_tab_details',
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('completed swap record masks amounts, fiat and fees', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final privacy = await pump(
      tester,
      _swapIntent(
        status: SwapIntentStatus.complete,
        totalFeesText: '0.0013 ZEC',
        realisedSlippageText: '0.37%',
      ),
    );

    _expectShown(['1.2468', '87.53', '0.0013', r'$62.34']);

    await setPrivacy(tester, privacy, true);

    _expectHidden(['1.2468', '87.53', '0.0013', '62.34']);
    // Pay leg and its fee are ZEC; the receive leg keeps USDC.
    expect(find.text('****** ZEC'), findsNWidgets(2));
    expect(find.text('****** USDC'), findsOneWidget);
    expect(find.text('******'), findsNWidgets(2));
    expect(find.text('0.37%'), findsOneWidget);
    _expectNoDenominationMix();
    semantics.dispose();
  });

  testWidgets('in-progress swap details mask the guaranteed minimum', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final privacy = await pump(
      tester,
      _swapIntent(
        status: SwapIntentStatus.processing,
        minimumReceiveText: '86.42 USDC',
        slippageToleranceText: '1.5%',
        swapFeeText: 'Included in shown rate',
      ),
    );
    await openDetailsTab(tester);

    _expectShown(['86.42', '87.53']);

    await setPrivacy(tester, privacy, true);

    _expectHidden(['1.2468', '87.53', '86.42']);
    // Header receive leg plus the guaranteed minimum, both USDC.
    expect(find.text('****** USDC'), findsNWidgets(2));
    expect(find.text('****** ZEC'), findsOneWidget);
    expect(find.text('1.5%'), findsOneWidget);
    if (!mobile) {
      // Fixed copy has no amount to hide.
      expect(find.text('Included in shown rate'), findsOneWidget);
    }
    _expectNoDenominationMix();
    semantics.dispose();
  });

  testWidgets('refunded external swap masks the USDC refund with USDC', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final privacy = await pump(
      tester,
      SwapIntent(
        id: 'privacy-usdc-refund',
        pair: 'USDC -> ZEC',
        sellAmount: '100.37 USDC',
        receiveEstimate: '1.4253 ZEC',
        provider: 'NEAR Intents',
        status: SwapIntentStatus.refunded,
        nextAction: 'Refunded',
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        depositAddress: '0xdeposit1234567890abcdef1234567890abcdef',
        oneClickRefundTo: _refundTo,
        providerRefundInfo: const SwapProviderRefundInfo(
          refundedAmountText: '99.81 USDC',
          recordedRefundFeeText: '0.56 USDC',
        ),
        accountUuid: 'account-1',
        completedAt: DateTime.utc(2026, 9, 1, 12),
      ),
    );

    _expectShown(['100.37', '1.4253', '99.81', '0.56']);

    await setPrivacy(tester, privacy, true);

    _expectHidden(['100.37', '1.4253', '99.81', '0.56']);
    expect(find.text('****** USDC'), findsNWidgets(3));
    expect(find.text('****** ZEC'), findsOneWidget);
    expect(find.text(r'$--'), findsOneWidget);
    _expectNoDenominationMix();
    semantics.dispose();
  });

  testWidgets('completed Pay record masks amount, source and tx fee', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final privacy = await pump(
      tester,
      _payIntent(status: SwapIntentStatus.complete),
    );
    await tester.pump();

    _expectShown(['990.37', r'$990.37', '4.1253', '0.0001']);

    await setPrivacy(tester, privacy, true);

    _expectHidden(['990.37', '4.1253', '0.0001']);
    expect(find.text('****** USDC'), findsOneWidget);
    // Converted from and the confirmed tx fee are ZEC.
    expect(find.text('****** ZEC'), findsNWidgets(2));
    expect(find.text('******'), findsOneWidget);
    _expectNoDenominationMix();
    semantics.dispose();
  });

  for (final status in [SwapIntentStatus.refunded, SwapIntentStatus.failed]) {
    testWidgets('${status.name} Pay record masks its outcome amounts', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final privacy = await pump(tester, _payIntent(status: status));
      final refunded = status == SwapIntentStatus.refunded;

      _expectShown([
        '990.37',
        if (refunded) ...['4.0833', '0.042'] else '4.1253',
      ]);

      await setPrivacy(tester, privacy, true);

      _expectHidden(['990.37', '4.1253', '4.0833', '0.042']);
      expect(find.text('****** USDC'), findsOneWidget);
      // Refunded amount + refund fee, or the failed source amount; all ZEC.
      expect(find.text('****** ZEC'), findsNWidgets(refunded ? 2 : 1));
      _expectNoDenominationMix();
      semantics.dispose();
    });
  }

  testWidgets('awaiting-deposit page shows the amount to send', (
    tester,
  ) async {
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(args['text']! as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final semantics = tester.ensureSemantics();
    final privacy = await pump(
      tester,
      SwapIntent(
        id: 'privacy-usdc-deposit',
        pair: 'USDC -> ZEC',
        sellAmount: '100.37 USDC',
        receiveEstimate: '1.4253 ZEC',
        provider: 'NEAR Intents',
        status: SwapIntentStatus.awaitingExternalDeposit,
        nextAction: 'Deposit USDC',
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        depositAddress: '0xdeposit1234567890abcdef1234567890abcdef',
        depositDeadline: _deadline,
        accountUuid: 'account-1',
      ),
    );

    expect(find.text('100.37 USDC'), findsNWidgets(2));

    await setPrivacy(tester, privacy, true);

    // The user may send it from another device, so privacy mode keeps the
    // QR card headline and the amount row visible (docs/privacy-mode.md).
    expect(find.text('100.37 USDC'), findsNWidgets(2));
    expect(find.textContaining('******'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_copy_deposit_amount')));
    await tester.pump();
    expect(clipboardWrites, ['100.37']);

    semantics.dispose();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hardware ZEC deposit page shows the ZEC amount', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final privacy = await pump(
      tester,
      SwapIntent(
        id: 'privacy-hardware-deposit',
        pair: 'ZEC -> USDC',
        sellAmount: '0.0037 ZEC',
        receiveEstimate: '0.26 USDC',
        provider: 'NEAR Intents',
        status: SwapIntentStatus.awaitingDeposit,
        nextAction: 'Sign the ZEC deposit',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1hardwaredeposit',
        depositDeadline: _deadline,
        accountUuid: 'account-1',
      ),
      hardwareAccount: true,
    );

    expect(find.text('0.0037 ZEC'), findsNWidgets(2));

    await setPrivacy(tester, privacy, true);

    expect(find.text('0.0037 ZEC'), findsNWidgets(2));
    expect(find.textContaining('******'), findsNothing);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

SwapIntent _swapIntent({
  required SwapIntentStatus status,
  String? totalFeesText,
  String? swapFeeText,
  String? realisedSlippageText,
  String? slippageToleranceText,
  String? minimumReceiveText,
}) {
  return SwapIntent(
    id: 'privacy-swap-${status.name}',
    pair: 'ZEC -> USDC',
    sellAmount: '1.2468 ZEC',
    receiveEstimate: '87.53 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Swap',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1swapdeposit',
    totalFeesText: totalFeesText,
    swapFeeText: swapFeeText,
    realisedSlippageText: realisedSlippageText,
    slippageToleranceText: slippageToleranceText,
    minimumReceiveText: minimumReceiveText,
    fiatValueBasis: SwapFiatValueBasis(
      capturedAt: DateTime.utc(2026, 9, 1),
      sellUsdUnitPrice: 50,
      receiveUsdUnitPrice: 1,
    ),
    accountUuid: 'account-1',
    createdAt: DateTime.utc(2026, 9, 1, 11),
    completedAt: status.isTerminal ? DateTime.utc(2026, 9, 1, 12) : null,
  );
}

SwapIntent _payIntent({required SwapIntentStatus status}) {
  return SwapIntent(
    id: 'privacy-pay-${status.name}',
    pair: 'ZEC -> USDC',
    sellAmount: '4.1253 ZEC',
    receiveEstimate: '990.37 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Pay',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: '0123123124512512',
    depositTxHash: _depositTxid,
    nearIntentHash: 'near-intent-hash',
    oneClickRecipient: _recipient,
    oneClickRefundTo: 'u1refundaddress0000000000000000000000000',
    providerRefundInfo: status == SwapIntentStatus.refunded
        ? const SwapProviderRefundInfo(
            refundedAmountText: '4.0833 ZEC',
            recordedRefundFeeText: '0.042 ZEC',
          )
        : null,
    fiatValueBasis: SwapFiatValueBasis(
      capturedAt: DateTime.utc(2026, 9, 1),
      sellUsdUnitPrice: 240,
      receiveUsdUnitPrice: 1,
    ),
    accountUuid: 'account-1',
    payMode: true,
    createdAt: DateTime.utc(2026, 9, 1, 11),
    completedAt: status.isTerminal ? DateTime.utc(2026, 9, 1, 12) : null,
  );
}

rust_sync.TransactionInfo _depositTransaction(String txidHex) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000000),
    expiredUnmined: false,
    accountBalanceDelta: -412530000,
    fee: BigInt.from(10000),
    feeState: rust_sync.TransactionFeeState.known,
    detailsComplete: true,
    provisional: false,
    amountIncludesFee: false,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'sent',
    displayAmount: BigInt.from(412530000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

Finder _semanticsContaining(String text) =>
    find.bySemanticsLabel(RegExp(RegExp.escape(text)));

void _expectShown(List<String> amounts) {
  for (final amount in amounts) {
    expect(find.textContaining(amount), findsWidgets, reason: amount);
  }
}

void _expectHidden(List<String> amounts) {
  for (final amount in amounts) {
    expect(find.textContaining(amount), findsNothing, reason: amount);
    expect(_semanticsContaining(amount), findsNothing, reason: amount);
  }
}

/// A masked amount must never carry two symbols or another leg's symbol.
void _expectNoDenominationMix() {
  final mixed = RegExp(r'\b(ZEC|USDC) (ZEC|USDC)\b');
  expect(find.textContaining(mixed), findsNothing);
  expect(find.bySemanticsLabel(mixed), findsNothing);
}

class _Privacy extends PrivacyModeNotifier {
  @override
  bool build() => false;

  @override
  Future<void> set(bool enabled) async => state = enabled;
}

class _StaticSwapNotifier extends SwapNotifier {
  _StaticSwapNotifier(this.intent);

  final SwapIntent intent;

  @override
  SwapState build() => SwapState(
    direction: intent.direction ?? SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [intent],
    payMode: intent.payMode,
  );
}

class _Accounts extends AccountNotifier {
  _Accounts({required this.hardware});

  final bool hardware;

  @override
  AccountState build() => AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        isHardware: hardware,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1privacyaccount',
  );
}

class _EmptyAddressBook extends AddressBookNotifier {
  @override
  AddressBookState build() => const AddressBookState();
}
