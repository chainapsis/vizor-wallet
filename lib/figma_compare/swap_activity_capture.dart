import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'
    show Material, MaterialType, MaterialPageRoute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/l10n/l10n.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/swap/models/swap_activity_navigation.dart';
import '../src/features/swap/models/swap_activity_status_mapper.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_state_provider.dart';
import '../src/features/swap/widgets/swap_activity_panel.dart';
import '../src/features/swap/widgets/swap_status_page_content.dart';
import '../src/providers/account_provider.dart';

Widget buildSwapActivityProcessingCapture(BuildContext context) =>
    _capture(context, payMode: false);

Widget buildPayActivityProcessingCapture(BuildContext context) =>
    _capture(context, payMode: true);

Widget buildSwapActivityFailedCapture(
  BuildContext context, {
  bool hasDeposit = true,
}) => _capture(
  context,
  payMode: false,
  status: SwapIntentStatus.failed,
  hasDeposit: hasDeposit,
);

Widget buildPayActivityFailedCapture(BuildContext context) =>
    _capture(context, payMode: true, status: SwapIntentStatus.failed);

/// Pay records show a rate row only without a Pay status phase, i.e. after an
/// incomplete deposit (desktop only). Priced from the NEAR Intents token list of 2026-11-23
/// (ZEC $796.27) plus a 0.4% cost.
Widget buildPayActivityRateUsdcCapture(BuildContext context) => _payRateCapture(
  context,
  asset: SwapAsset.usdc,
  sellAmount: '0.126015 ZEC',
  receiveEstimate: '100 USDC',
  receiveUsdUnitPrice: 0.999422,
);

Widget buildPayActivityRateDogeCapture(BuildContext context) => _payRateCapture(
  context,
  asset: SwapAsset.doge,
  sellAmount: '0.070353 ZEC',
  receiveEstimate: '1000 DOGE',
  receiveUsdUnitPrice: 0.055797,
);

/// Renders the production Pay record presentation on its Transaction details
/// tab, where the rate row sits.
Widget _payRateCapture(
  BuildContext context, {
  required SwapAsset asset,
  required String sellAmount,
  required String receiveEstimate,
  required double receiveUsdUnitPrice,
}) {
  final intent = SwapIntent(
    id: 'capture-pay-rate-${asset.name}',
    pair: 'ZEC -> ${asset.symbol}',
    sellAmount: sellAmount,
    receiveEstimate: receiveEstimate,
    provider: 'NEAR Intents',
    status: SwapIntentStatus.incompleteDeposit,
    providerStatusRaw: 'INCOMPLETE_DEPOSIT',
    nextAction: 'Incomplete deposit',
    direction: SwapDirection.zecToExternal,
    externalAsset: asset,
    depositAddress: 't1V7jJp2rH2X8Qg7KDNpKc3Vn2m8yL9aBcD',
    nearIntentHash: 'capture-near-intent',
    oneClickRecipient: '0x52908400098527886E0F7030069857D2E4169EE7',
    oneClickRefundTo: 'u1capturewalletrefundaddress',
    fiatValueBasis: SwapFiatValueBasis(
      sellUsdUnitPrice: 796.27,
      receiveUsdUnitPrice: receiveUsdUnitPrice,
      capturedAt: DateTime.utc(2026, 11, 23, 5, 50),
    ),
    createdAt: DateTime.utc(2026, 11, 23, 5, 50),
    payMode: true,
  );
  final presentation = swapActivityStatusPresentationForIntent(
    context.l10n,
    SwapState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      receiveAmountText: '',
      destinationText: '',
      externalAsset: asset,
      reviewVisible: false,
      intents: [intent],
      payMode: true,
    ),
    intent,
  );
  return ColoredBox(
    color: context.colors.background.window,
    child: AppDesktopPane(
      padding: EdgeInsets.zero,
      // Mirrors the Activity detail surface's desktop scaffold.
      child: AppPaneScrollScaffold(
        toolbar: AppPaneToolbar(
          leading: AppBackLink(label: 'Activity', minWidth: 60, onTap: () {}),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        // The surface centers its content in a column, as here.
        child: Column(
          children: [
            SwapStatusPageContent(
              title: presentation.title,
              payAsset: presentation.payAsset,
              receiveAsset: presentation.receiveAsset,
              payAmountText: presentation.payAmountText,
              receiveAmountText: presentation.receiveAmountText,
              payLabel: presentation.payLabel,
              receiveLabel: presentation.receiveLabel,
              payDetailText: presentation.payDetailText,
              receiveDetailText: presentation.receiveDetailText,
              statusLabel: presentation.statusLabel,
              badgeKind: presentation.badgeKind,
              progressIndex: presentation.progressIndex,
              activeTab: SwapStatusTab.details,
              steps: presentation.steps,
              details: presentation.details,
              progressTabLabel: presentation.progressTabLabel,
              paymentMode: presentation.paymentMode,
              showTabs: presentation.showTabs,
              onTabChanged: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
}

// Keep the route-owned mobile sheet inside the widget capture boundary.
Widget buildSwapActivityFailedSupportCapture(BuildContext context) =>
    _supportCapture(payMode: false);
Widget buildPayActivityFailedSupportCapture(BuildContext context) =>
    _supportCapture(payMode: true);

Widget buildSwapDepositRecoveryCapture(BuildContext context) => _supportCapture(
  payMode: false,
  status: SwapIntentStatus.awaitingExternalDeposit,
);

Widget _supportCapture({
  required bool payMode,
  SwapIntentStatus status = SwapIntentStatus.failed,
}) => Material(
  type: MaterialType.transparency,
  child: Navigator(
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (context) => _capture(context, payMode: payMode, status: status),
    ),
  ),
);

Widget buildSwapActivityExpiredCapture(BuildContext context) =>
    _capture(context, payMode: false, status: SwapIntentStatus.expired);

Widget buildSwapActivityRefundedCapture(BuildContext context) =>
    _capture(context, payMode: false, status: SwapIntentStatus.refunded);

/// Uses the production Activity surface and mapper, with local intent data.
/// In particular, explorer callbacks and the initial tab come from app code.
Widget _capture(
  BuildContext context, {
  required bool payMode,
  SwapIntentStatus status = SwapIntentStatus.processing,
  bool hasDeposit = true,
}) {
  final awaitingDeposit = status == SwapIntentStatus.awaitingExternalDeposit;
  final intent = awaitingDeposit
      ? const SwapIntent(
          id: 'capture-external-deposit',
          pair: 'USDC -> ZEC',
          sellAmount: '150 USDC',
          receiveEstimate: '2 ZEC',
          provider: 'NEAR Intents',
          status: SwapIntentStatus.awaitingExternalDeposit,
          nextAction: 'Deposit USDC',
          direction: SwapDirection.externalToZec,
          externalAsset: SwapAsset.usdc,
          depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
        )
      : SwapIntent(
          id: payMode ? 'capture-pay-processing' : 'capture-swap-processing',
          pair: 'ZEC -> USDC',
          sellAmount: '2.0000 ZEC',
          receiveEstimate: '140.00 USDC',
          provider: 'NEAR Intents',
          status: status,
          providerStatusRaw: status.name.toUpperCase(),
          nextAction: 'Swap is processing',
          providerRefundInfo: SwapProviderRefundInfo(
            refundedAmountText: status == SwapIntentStatus.refunded
                ? '1.99 ZEC'
                : '0 ZEC',
          ),
          direction: SwapDirection.zecToExternal,
          externalAsset: SwapAsset.usdc,
          depositAddress: 't1V7jJp2rH2X8Qg7KDNpKc3Vn2m8yL9aBcD',
          depositTxHash: hasDeposit
              ? '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
              : null,
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
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
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
