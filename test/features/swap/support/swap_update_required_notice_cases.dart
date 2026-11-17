import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_payout_discovery_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../../fakes/fake_sync_notifier.dart';
import '../../../support/test_l10n.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

/// Registers the swap detail's update notice tests for `layout`, so the
/// desktop and mobile lanes check the same cases.
void swapUpdateRequiredNoticeTests(SwapActivityDetailLayout layout) {
  Future<void> pump(
    WidgetTester tester,
    SwapIntent intent, {
    bool updateRequired = true,
  }) async {
    final size = layout == SwapActivityDetailLayout.mobile
        ? const Size(393, 852)
        : const Size(1280, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(_AccountNotifier.new),
          addressBookProvider.overrideWith(_EmptyAddressBookNotifier.new),
          swapStateProvider.overrideWith(() => _SwapNotifier(intent)),
          syncProvider.overrideWith(FakeSyncNotifier.new),
          swapRecoveryUpdateRequiredProvider.overrideWith(
            (ref) async => updateRequired,
          ),
          // The payout is not in the wallet yet.
          swapPayoutRowsLoaderProvider.overrideWithValue(
            (_, _) async => const [],
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          builder: (_, navigator) =>
              AppTheme(data: AppThemeData.light, child: navigator!),
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: Consumer(
              builder: (context, ref, _) => SwapActivityDetailPagePanel(
                state: ref.watch(swapStateProvider),
                intent: intent,
                layout: layout,
                depositChecking: false,
                depositCheckWarning: null,
                onRefreshStatus: () {},
                onMarkDeposited: () {},
                onDepositTxHashChanged: (_) {},
                onSubmitDepositTransaction: () {},
                onReviewFreshQuote: () {},
                onSignZecDeposit: (_) {},
                intentIsHardware: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a pending private swap says to update for its payout', (
    tester,
  ) async {
    await pump(tester, _incoming);
    expect(find.text(testL10n.swapPayoutUpdateRequired), findsOneWidget);
  });

  testWidgets('a completed private swap still finding its payout says so', (
    tester,
  ) async {
    await pump(
      tester,
      _incoming.copyWith(
        status: SwapIntentStatus.complete,
        completedAt: DateTime.now().toUtc(),
        destinationChainTxHash: 'ab' * 32,
      ),
    );
    expect(find.text(testL10n.swapPayoutUpdateRequired), findsOneWidget);
  });

  testWidgets('an eight-day-old missing payout keeps its notice', (
    tester,
  ) async {
    await pump(
      tester,
      _incoming.copyWith(
        status: SwapIntentStatus.complete,
        completedAt: DateTime.now().toUtc().subtract(const Duration(days: 8)),
        destinationChainTxHash: 'ab' * 32,
      ),
    );
    expect(find.text(testL10n.swapPayoutUpdateRequired), findsOneWidget);
    expect(find.text(testL10n.swapFindingPayout), findsWidgets);
  });

  testWidgets('a pending private swap out of ZEC says refund', (tester) async {
    await pump(tester, _outgoing);
    expect(find.text(testL10n.swapRefundUpdateRequired), findsOneWidget);
  });

  testWidgets('no notice once the update flag clears', (tester) async {
    await pump(tester, _incoming, updateRequired: false);
    expect(find.text(testL10n.swapPayoutUpdateRequired), findsNothing);
  });

  testWidgets('no notice on an ordinary swap', (tester) async {
    await pump(tester, _incoming.copyWith(privateAddress: false));
    await pump(tester, _outgoing.copyWith(privateAddress: false));
    expect(find.text(testL10n.swapPayoutUpdateRequired), findsNothing);
    expect(find.text(testL10n.swapRefundUpdateRequired), findsNothing);
  });

  testWidgets('no notice on a completed private swap', (tester) async {
    // No payout hash to look for, so the payout counts as found.
    await pump(tester, _incoming.copyWith(status: SwapIntentStatus.complete));
    expect(find.text(testL10n.swapPayoutUpdateRequired), findsNothing);
    await pump(tester, _outgoing.copyWith(status: SwapIntentStatus.complete));
    expect(find.text(testL10n.swapRefundUpdateRequired), findsNothing);
  });
}

final _incoming = SwapIntent(
  id: '0xincoming-deposit',
  pair: 'USDC -> ZEC',
  sellAmount: '25 USDC',
  receiveEstimate: '0.5 ZEC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.processing,
  nextAction: 'Processing',
  direction: SwapDirection.externalToZec,
  externalAsset: SwapAsset.usdc,
  depositAddress: '0xincoming-deposit',
  oneClickRecipient: 'u1payout',
  oneClickRefundTo: '0xrefund',
  accountUuid: 'account-1',
  privateAddress: true,
);

final _outgoing = SwapIntent(
  id: '0xoutgoing-deposit',
  pair: 'ZEC -> USDC',
  sellAmount: '0.5 ZEC',
  receiveEstimate: '25 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.processing,
  nextAction: 'Processing',
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1outgoing',
  oneClickRecipient: '0xrecipient',
  oneClickRefundTo: 'u1refund',
  accountUuid: 'account-1',
  privateAddress: true,
);

class _SwapNotifier extends SwapNotifier {
  _SwapNotifier(this._intent);

  final SwapIntent _intent;

  @override
  SwapState build() => SwapState(
    direction: _intent.direction ?? SwapDirection.externalToZec,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [_intent],
    selectedIntentId: _intent.id,
  );
}

class _AccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1account',
  );
}

class _EmptyAddressBookNotifier extends AddressBookNotifier {
  @override
  AddressBookState build() => const AddressBookState();
}
