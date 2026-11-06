@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_deposit_tokens_page_content.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

// Mobile Activity for an incoming private swap whose wallet start is pending.
// Desktop runs the same detail surface from a held start in
// swap_screen_test.dart.

void main() {
  testWidgets('a starting swap shows no deposit instructions, then a refused '
      'start leaves nothing to fund', (tester) async {
    final notifier = await _pumpDetail(tester, _starting);
    expect(
      find.byKey(const ValueKey('swap_activity_start_pending')),
      findsOneWidget,
    );
    expect(find.text(swapStartingText), findsOneWidget);
    expect(find.byType(SwapDepositTokensPageContent), findsNothing);

    // A refused start removes the swap by id.
    notifier.show(const []);
    await tester.pump();
    expect(find.text('removed'), findsOneWidget);
    expect(find.byType(SwapDepositTokensPageContent), findsNothing);
  });

  testWidgets('a started swap shows its deposit instructions', (tester) async {
    final notifier = await _pumpDetail(tester, _starting);
    notifier.show([_starting.copyWith(startPending: false)]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('swap_activity_start_pending')),
      findsNothing,
    );
    expect(find.byType(SwapDepositTokensPageContent), findsOneWidget);
  });

  testWidgets('a swap that never finished starting stays hidden', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      _starting.copyWith(
        status: SwapIntentStatus.failed,
        statusError: swapStartFailedText,
      ),
    );
    expect(find.text(swapStartFailedText), findsOneWidget);
    expect(find.byType(SwapDepositTokensPageContent), findsNothing);
  });

  testWidgets('the Activity row says the swap is starting', (tester) async {
    late String? statusText;
    await tester.pumpWidget(
      _themed(
        Builder(
          builder: (context) {
            statusText = buildSwapActivityRow(
              context: context,
              item: SwapActivityRowItem.fromRecord(
                SwapIntentRecord.fromIntent(_starting),
              ),
            ).statusText;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(statusText, swapStartingText);
  });
}

final _starting = SwapIntent(
  id: '0xstarting-deposit',
  pair: 'USDC -> ZEC',
  sellAmount: '25 USDC',
  receiveEstimate: '0.5 ZEC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingExternalDeposit,
  nextAction: 'Send USDC',
  direction: SwapDirection.externalToZec,
  externalAsset: SwapAsset.usdc,
  depositAddress: '0xstarting-deposit',
  providerQuoteId: 'quote-1',
  oneClickRecipient: 'u1swap',
  oneClickRefundTo: '0xrefund',
  accountUuid: 'account-1',
  privateAddress: true,
  startPending: true,
);

/// Swap state the test replaces as the start progresses.
class _DrivenSwapNotifier extends SwapNotifier {
  _DrivenSwapNotifier(this._initial);

  final SwapIntent _initial;

  @override
  SwapState build() => _stateWith([_initial]);

  /// Shows `intents` as the screen's swaps.
  void show(List<SwapIntent> intents) => state = _stateWith(intents);
}

SwapState _stateWith(List<SwapIntent> intents) => SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: intents,
  selectedIntentId: intents.isEmpty ? null : intents.first.id,
);

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

/// `child` under the app theme at phone size.
Widget _themed(Widget child) => MaterialApp(
  builder: (_, navigator) =>
      AppTheme(data: AppThemeData.light, child: navigator!),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(393, 852), disableAnimations: true),
    child: child,
  ),
);

/// Pumps the mobile swap detail for `intent`, rebuilt from the swap state, and
/// returns the notifier that drives it.
Future<_DrivenSwapNotifier> _pumpDetail(
  WidgetTester tester,
  SwapIntent intent,
) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final notifier = _DrivenSwapNotifier(intent);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountProvider.overrideWith(_AccountNotifier.new),
        addressBookProvider.overrideWith(_EmptyAddressBookNotifier.new),
        swapStateProvider.overrideWith(() => notifier),
        syncProvider.overrideWith(FakeSyncNotifier.new),
      ],
      child: _themed(
        Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(swapStateProvider);
            final shown = [
              for (final candidate in state.intents)
                if (candidate.id == intent.id) candidate,
            ];
            if (shown.isEmpty) return const Text('removed');
            return SwapActivityDetailPagePanel(
              state: state,
              intent: shown.single,
              layout: SwapActivityDetailLayout.mobile,
              depositChecking: false,
              depositCheckWarning: null,
              onRefreshStatus: () {},
              onMarkDeposited: () {},
              onDepositTxHashChanged: (_) {},
              onSubmitDepositTransaction: () {},
              onReviewFreshQuote: () {},
              onSignZecDeposit: (_) {},
              intentIsHardware: false,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return notifier;
}
