import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/swap/models/swap_activity_navigation.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_state_provider.dart';
import '../src/features/swap/widgets/swap_activity_panel.dart';
import '../src/providers/account_provider.dart';

Widget buildSwapActivityProcessingCapture(BuildContext context) =>
    _capture(context, payMode: false);

Widget buildPayActivityProcessingCapture(BuildContext context) =>
    _capture(context, payMode: true);

/// Uses the production Activity surface and mapper, with local intent data.
/// In particular, explorer callbacks and the initial tab come from app code.
Widget _capture(BuildContext context, {required bool payMode}) {
  final intent = SwapIntent(
    id: payMode ? 'capture-pay-processing' : 'capture-swap-processing',
    pair: 'ZEC -> USDC',
    sellAmount: '2.0000 ZEC',
    receiveEstimate: '140.00 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.processing,
    nextAction: 'Swap is processing',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1V7jJp2rH2X8Qg7KDNpKc3Vn2m8yL9aBcD',
    depositTxHash:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    nearIntentHash: 'capture-near-intent',
    oneClickRecipient: '0x52908400098527886E0F7030069857D2E4169EE7',
    oneClickRefundTo: 'u1capturewalletrefundaddress',
    minimumReceiveText: '139.30 USDC',
    slippageToleranceText: '0.5%',
    fiatValueBasis: SwapFiatValueBasis(
      sellUsdUnitPrice: 70,
      receiveUsdUnitPrice: 1,
      capturedAt: DateTime.utc(2026, 11, 3, 4, 30),
    ),
    createdAt: DateTime.utc(2026, 11, 3, 4, 30),
    payMode: payMode,
  );
  return ProviderScope(
    overrides: [
      accountProvider.overrideWith(_CaptureAccounts.new),
      addressBookProvider.overrideWith(_CaptureAddressBook.new),
      swapStateProvider.overrideWith(() => _CaptureSwap(intent)),
    ],
    child: kAppFormFactor == AppFormFactor.mobile
        ? MobileSwapActivityDetailScreen(swapIntentId: intent.id)
        : ColoredBox(
            color: context.colors.background.window,
            child: AppDesktopPane(
              padding: EdgeInsets.zero,
              child: SwapActivityDetailSurface(
                intentId: intent.id,
                returnTarget: SwapActivityReturnTarget.activity,
              ),
            ),
          ),
  );
}

class _CaptureSwap extends SwapNotifier {
  _CaptureSwap(this.intent);
  final SwapIntent intent;

  @override
  SwapState build() => SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [intent],
    selectedIntentId: intent.id,
    payMode: intent.payMode,
  );

  @override
  void selectIntent(String intentId) {}
}

class _CaptureAccounts extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState();
}

class _CaptureAddressBook extends AddressBookNotifier {
  @override
  FutureOr<AddressBookState> build() => const AddressBookState();
}
