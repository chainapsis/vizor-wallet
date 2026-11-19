@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _hash =
    '4f2c9a1e7b3d5f8a0c6e2b9d4f1a7c3e5b8d0f2a6c9e1b4d7f0a3c5e8b2d6f9a';

void main() {
  testWidgets('a claimed deposit offers its hash, and the sheet sends a '
      'pasted one', (tester) async {
    final swap = _RecordingSwap(_claimedIntent());
    await tester.pumpWidget(_screen(swap));
    await _settle(tester);
    _mockClipboard(tester, ' $_hash\n');

    await _openEntry(tester);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('swap_deposit_tx_hash_field')),
    );
    // The keyboard neither suggests nor learns a hash.
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);

    await tester.tap(find.byKey(const ValueKey('swap_deposit_tx_hash_paste')));
    await tester.pump();
    expect(field.controller!.text, _hash);
    await tester.tap(find.byKey(const ValueKey('swap_deposit_tx_hash_submit')));
    await _settle(tester);

    expect(swap.submitted, [('claimed-ltc', _hash)]);
    expect(
      find.byKey(const ValueKey('swap_deposit_tx_hash_entry')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('swap_deposit_tx_hash_prompt')),
      findsNothing,
    );
  });

  testWidgets('a refused hash keeps the sheet open until it is edited', (
    tester,
  ) async {
    final swap = _RecordingSwap(
      _claimedIntent(),
      result: SwapUserDepositTxHashResult.failed,
    );
    await tester.pumpWidget(_screen(swap));
    await _settle(tester);

    await _openEntry(tester);
    await tester.enterText(_input(), _hash);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('swap_deposit_tx_hash_submit')));
    await _settle(tester);

    expect(_error(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swap_deposit_tx_hash_entry')),
      findsOneWidget,
    );
    await tester.enterText(_input(), '${_hash}0');
    await tester.pump();
    expect(_error(), findsNothing);
  });

  testWidgets('the entry keeps its text whole at 200% on a narrow phone', (
    tester,
  ) async {
    await loadFigmaCompareFonts();
    tester.view.physicalSize = const Size(320, 693);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final swap = _RecordingSwap(
      _claimedIntent(),
      result: SwapUserDepositTxHashResult.failed,
    );
    await tester.pumpWidget(_screen(swap, textScale: 2));
    await _settle(tester);

    await _openEntry(tester);
    await tester.enterText(_input(), _hash);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('swap_deposit_tx_hash_submit')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(_error(), findsOneWidget);
  });
}

// The active step's loader never stops, so frames are pumped instead of
// settled; a second covers the sheet's entrance and exit.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _openEntry(WidgetTester tester) async {
  final prompt = find.byKey(const ValueKey('swap_deposit_tx_hash_prompt'));
  await tester.ensureVisible(prompt);
  await _settle(tester);
  await tester.tap(prompt);
  await _settle(tester);
  expect(
    find.byKey(const ValueKey('swap_deposit_tx_hash_entry')),
    findsOneWidget,
  );
}

Finder _input() => find.descendant(
  of: find.byKey(const ValueKey('swap_deposit_tx_hash_field')),
  matching: find.byType(EditableText),
);

Finder _error() => find.byKey(const ValueKey('swap_deposit_tx_hash_error'));

void _mockClipboard(WidgetTester tester, String text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData' ? {'text': text} : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Widget _screen(_RecordingSwap swap, {double textScale = 1}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    accountProvider.overrideWith(_Accounts.new),
    addressBookProvider.overrideWith(_AddressBook.new),
    swapStateProvider.overrideWith(() => swap),
  ],
  child: MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appSupportedLocales(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: AppTheme(data: AppThemeData.light, child: child!),
    ),
    home: const MobileSwapActivityDetailScreen(swapIntentId: 'claimed-ltc'),
  ),
);

final _ltc = SwapAsset.live(
  assetId: 'nep141:ltc.omft.near',
  symbol: 'LTC',
  blockchain: 'ltc',
  decimals: 8,
);

SwapIntent _claimedIntent() {
  final now = DateTime.now().toUtc();
  return SwapIntent(
    id: 'claimed-ltc',
    pair: 'LTC -> ZEC',
    sellAmount: '11.31900656 LTC',
    receiveEstimate: '0.55495667 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.awaitingExternalDeposit,
    nextAction: 'Deposit LTC',
    direction: SwapDirection.externalToZec,
    externalAsset: _ltc,
    depositAddress: 'claimed-ltc',
    providerQuoteId: 'quote-ltc',
    oneClickRecipient: 'u1claimedrecipient',
    oneClickRefundTo: 'ltc1qclaimedrefund',
    depositDeadline: now.add(const Duration(hours: 1)),
    createdAt: now.subtract(const Duration(minutes: 20)),
    lastStatusCheckedAt: now,
    depositClaimedAt: now.subtract(const Duration(minutes: 10)),
  );
}

class _RecordingSwap extends SwapNotifier {
  _RecordingSwap(
    this.intent, {
    this.result = SwapUserDepositTxHashResult.submitted,
  });

  final SwapIntent intent;
  final SwapUserDepositTxHashResult result;
  final submitted = <(String, String)>[];

  @override
  SwapState build() => SwapState(
    direction: SwapDirection.externalToZec,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: _ltc,
    reviewVisible: false,
    intents: [intent],
    selectedIntentId: intent.id,
  );

  @override
  void selectIntent(String intentId) {}

  @override
  Future<SwapUserDepositTxHashResult> submitUserDepositTxHash({
    required String intentId,
    required String txHash,
  }) async {
    submitted.add((intentId, txHash.trim()));
    if (result == SwapUserDepositTxHashResult.submitted) {
      state = state.copyWith(
        intents: [intent.copyWith(userDepositTxHash: txHash.trim())],
      );
    }
    return result;
  }
}

class _Accounts extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState();
}

class _AddressBook extends AddressBookNotifier {
  @override
  FutureOr<AddressBookState> build() => const AddressBookState();
}
