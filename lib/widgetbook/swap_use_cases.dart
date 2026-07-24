// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/swap/models/swap_fiat_amount.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/address_scan/widgets/address_qr_scan_modal.dart';
import '../src/features/address_scan/widgets/mobile_address_scan_card.dart';
import '../src/features/swap/widgets/swap_address_edit_modal.dart';
import '../src/features/swap/widgets/swap_asset_selector_modal.dart';
import '../src/features/swap/widgets/swap_composer_panel.dart';
import '../src/features/swap/widgets/swap_deposit_tokens_page_content.dart';
import '../src/features/swap/widgets/swap_near_intents_attribution.dart';
import '../src/features/swap/widgets/swap_review_page_content.dart';
import '../src/features/swap/widgets/swap_slippage_modal.dart';
import '../src/features/swap/widgets/swap_status_page_content.dart';

Widget buildSwapPageFigmaNode1UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode1State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapPageFigmaNode2UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode2State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapPageFigmaNode3UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode3State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapPageFigmaNode5UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode5State,
      actionLabel: 'Add recipient address',
      zecAvailableText: '128 ZEC',
      zecAvailableZatoshi: BigInt.from(12800000000),
      maxAmountText: '128',
    ),
  );
}

Widget buildSwapPageFigmaNode6UseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode6State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapPageUnsupportedFiatUseCase(BuildContext context) {
  return _SwapPageFrame(
    child: _SwapComposerPreview(
      initialState: _unsupportedFiatState,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapAddressModalFigmaNode7UseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAddressEditModal(
      state: _figmaNode3State,
      onSubmitted: (_, _) {},
      onScan: () {},
      onOpenContacts: () {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalPermissionUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: AddressQrScanModalContent(
      status: AddressQrCameraStatus.requesting,
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalDeniedUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: AddressQrScanModalContent(
      status: AddressQrCameraStatus.denied,
      onRetry: () {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalActiveUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: AddressQrScanModalContent(
      status: AddressQrCameraStatus.active,
      cameraView: const _AddressQrCameraPreview(),
      onCancel: () {},
    ),
  );
}

Widget buildSwapAddressScanModalLoadingUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: AddressQrScanModalContent(
      status: AddressQrCameraStatus.loading,
      cameraView: const _AddressQrCameraPreview(),
      onCancel: () {},
    ),
  );
}

Widget buildMobileSwapAddressScanRequestingUseCase(BuildContext context) {
  return const _MobileScanCardFrame(
    child: MobileAddressScanCardContent(
      status: AddressQrCameraStatus.requesting,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileSwapAddressScanDeniedUseCase(BuildContext context) {
  return const _MobileScanCardFrame(
    child: MobileAddressScanCardContent(
      status: AddressQrCameraStatus.denied,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileSwapAddressScanActiveUseCase(BuildContext context) {
  return const _MobileScanCardFrame(
    child: MobileAddressScanCardContent(
      status: AddressQrCameraStatus.active,
      cameraView: _MobileScanCameraPreview(),
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileSwapAddressScanLoadingUseCase(BuildContext context) {
  return const _MobileScanCardFrame(
    child: MobileAddressScanCardContent(
      status: AddressQrCameraStatus.loading,
      cameraView: _MobileScanCameraPreview(),
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

void _noop() {}

Widget buildSwapSlippageModalUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapSlippageModal(
      slippageBps: 50,
      onSubmitted: (_) {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapSlippageModalCustomUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapSlippageModal(
      slippageBps: 125,
      onSubmitted: (_) {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapSlippageModalInvalidUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapSlippageModal(
      slippageBps: 50,
      initialCustomText: '15',
      onSubmitted: (_) {},
      onCancel: () {},
    ),
  );
}

Widget buildSwapAssetModalUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAssetSelectorModal(
      assets: _figmaAssetModalAssets,
      selected: _figmaUsdc,
      onSelected: (_) {},
    ),
  );
}

Widget buildSwapAssetModalEmptyUseCase(BuildContext context) {
  return _SwapPageModalFrame(
    child: SwapAssetSelectorModal(
      assets: _figmaAssetModalAssets,
      selected: _figmaUsdc,
      initialQuery: 'Value',
      onSelected: (_) {},
    ),
  );
}

Widget buildSwapReviewDefaultUseCase(BuildContext context) {
  return _SwapReviewPageFrame(
    backLabel: 'Swap',
    child: _SwapReviewPreview(
      quote: _figmaReviewDefaultQuote,
      addressPlan: _figmaExternalToZecAddressPlan,
      slippageToleranceText: '0.25 USDC (0.5%)',
    ),
  );
}

Widget buildSwapReviewZecToExternalUseCase(BuildContext context) {
  return _SwapReviewPageFrame(
    backLabel: 'Swap',
    child: _SwapReviewPreview(
      quote: _figmaReviewZecToExternalQuote,
      addressPlan: _figmaZecToExternalAddressPlan,
      slippageToleranceText: '0.001 ZEC (0.5%)',
    ),
  );
}

Widget buildSwapReviewLargeLeftAmountUseCase(BuildContext context) {
  return _SwapReviewPageFrame(
    backLabel: 'Swap',
    child: _SwapReviewPreview(
      quote: _figmaReviewLargeQuote,
      addressPlan: _figmaExternalShitToZecAddressPlan,
      slippageToleranceText: r'0.25 $SHIT (0.5%)',
      payFiatText: r'$999.123M',
      receiveFiatText: r'$110.24',
    ),
  );
}

Widget buildSwapReviewLargeRightAmountUseCase(BuildContext context) {
  return _SwapReviewPageFrame(
    backLabel: 'Swap',
    child: _SwapReviewPreview(
      quote: _figmaReviewLargeRightQuote,
      addressPlan: _figmaZecToShitAddressPlan,
      slippageToleranceText: '0.001 ZEC (0.5%)',
      payFiatText: r'$110.24',
      receiveFiatText: r'$999.123M',
    ),
  );
}

Widget buildSwapReviewLargeAmountsUseCase(BuildContext context) {
  return _SwapReviewPageFrame(
    backLabel: 'Swap',
    child: _SwapReviewPreview(
      quote: _figmaReviewLargeBothQuote,
      addressPlan: _figmaExternalShitToZecAddressPlan,
      slippageToleranceText: r'0.25 $SHIT (0.5%)',
      payFiatText: r'$999.123M',
      receiveFiatText: r'$999.123M',
    ),
  );
}

Widget buildSwapDepositDurationUseCase(BuildContext context) {
  return _SwapFlowPageFrame(
    backLabel: 'Review',
    child: SwapDepositTokensPageContent(
      asset: SwapAsset.usdc,
      amountText: '999.99 USDC',
      depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
      expiresInLabel: '2hrs',
      onDeposited: () {},
    ),
  );
}

Widget buildSwapDepositCountdownUseCase(BuildContext context) {
  return _SwapFlowPageFrame(
    backLabel: 'Review',
    child: SwapDepositTokensPageContent(
      asset: SwapAsset.usdc,
      amountText: '999.99 USDC',
      depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
      expiresInLabel: '14:59',
      expiresAt: DateTime.now().add(const Duration(minutes: 14, seconds: 59)),
      onDeposited: () {},
    ),
  );
}

Widget buildSwapDepositMemoQrUseCase(BuildContext context) {
  return _SwapFlowPageFrame(
    backLabel: 'Review',
    child: SwapDepositTokensPageContent(
      asset: SwapAsset.usdc,
      amountText: '999.99 USDC',
      depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
      memo: 'memo with & routing=value?',
      expiresInLabel: '14:59',
      onDeposited: () {},
    ),
  );
}

Widget buildSwapDepositHardwareZecUseCase(BuildContext context) {
  return _SwapFlowPageFrame(
    backLabel: 'Review',
    child: SwapHardwareZecDepositPageContent(
      asset: SwapAsset.zec,
      amountText: '0.251 ZEC',
      depositAddress: 't1figmareviewdepositaddress',
      expiresInLabel: '2hrs',
      onDepositZec: () {},
    ),
  );
}

Widget buildSwapDepositTimeoutUseCase(BuildContext context) {
  return _SwapFlowPageFrame(
    backLabel: 'Swap',
    child: SwapDepositTimeoutPageContent(onRestart: () {}),
  );
}

Widget buildSwapStatusProgressUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap in progress...',
      badgeKind: SwapStatusBadgeKind.liveQuote,
      activeTab: SwapStatusTab.progress,
      progressIndex: 0,
      steps: _designProgressSteps,
      details: _designTransactionDetails,
    ),
  );
}

Widget buildSwapStatusProgressNextStepUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap in progress...',
      badgeKind: SwapStatusBadgeKind.liveQuote,
      activeTab: SwapStatusTab.progress,
      progressIndex: 1,
      steps: _designProgressSteps,
      details: _designTransactionDetails,
    ),
  );
}

Widget buildSwapStatusLargeLeftAmountUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap in progress...',
      badgeKind: SwapStatusBadgeKind.liveQuote,
      activeTab: SwapStatusTab.progress,
      progressIndex: 0,
      steps: _designProgressSteps,
      details: _designTransactionDetails,
      payAsset: _figmaReviewLargeQuote.sellAsset,
      receiveAsset: _figmaReviewLargeQuote.receiveAsset,
      payFiatText: r'$999.123M',
      receiveFiatText: r'$110.24',
      payAmountText: r'999,123,000.123456 $SHIT',
      receiveAmountText: '0.251 ZEC',
    ),
  );
}

Widget buildSwapStatusLargeRightAmountUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap in progress...',
      badgeKind: SwapStatusBadgeKind.liveQuote,
      activeTab: SwapStatusTab.progress,
      progressIndex: 0,
      steps: _designProgressSteps,
      details: _designTransactionDetails,
      payAsset: SwapAsset.zec,
      receiveAsset: _figmaReviewLargeQuote.sellAsset,
      payFiatText: r'$110.24',
      receiveFiatText: r'$999.123M',
      payAmountText: '0.251 ZEC',
      receiveAmountText: r'999,123,000.123456 $SHIT',
    ),
  );
}

Widget buildSwapStatusLargeAmountsUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap in progress...',
      badgeKind: SwapStatusBadgeKind.liveQuote,
      activeTab: SwapStatusTab.progress,
      progressIndex: 0,
      steps: _designProgressSteps,
      details: _designTransactionDetails,
      payAsset: _figmaReviewLargeQuote.sellAsset,
      receiveAsset: SwapAsset.usdc,
      payFiatText: r'$999.123M',
      receiveFiatText: r'$999.123M',
      payAmountText: r'999,123,000.123456 $SHIT',
      receiveAmountText: '999,999.99 USDC',
    ),
  );
}

Widget buildSwapStatusCapturedFiatUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap completed',
      badgeKind: SwapStatusBadgeKind.completed,
      showTabs: false,
      steps: const [],
      details: _designCompletedDetails,
      payAsset: SwapAsset.zec,
      receiveAsset: SwapAsset.usdc,
      payFiatText: r'$140.00',
      receiveFiatText: r'$123.45',
      payAmountText: '2.0000 ZEC',
      receiveAmountText: '123.45 USDC',
    ),
  );
}

Widget buildSwapStatusDetailsCollapsedUseCase(BuildContext context) {
  return const _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusDetailsPreview(),
  );
}

Widget buildSwapStatusDetailsExpandedUseCase(BuildContext context) {
  return const _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusDetailsPreview(),
  );
}

Widget buildSwapStatusCompletedUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap completed',
      badgeKind: SwapStatusBadgeKind.completed,
      showTabs: false,
      steps: const [],
      details: _designCompletedDetails,
    ),
  );
}

Widget buildSwapStatusFailedUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap failed',
      badgeKind: SwapStatusBadgeKind.failed,
      statusLabel: 'Failed',
      showTabs: false,
      steps: const [],
      details: _designFailedDetails,
    ),
  );
}

Widget buildSwapStatusIncompleteDepositUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Incomplete deposit',
      badgeKind: SwapStatusBadgeKind.warning,
      activeTab: SwapStatusTab.details,
      progressIndex: 2,
      steps: _designProgressSteps,
      details: _designIncompleteDepositDetails,
      payAsset: SwapAsset.usdc,
      receiveAsset: SwapAsset.zec,
      payFiatText: r'$100.00',
      receiveFiatText: r'$71.25',
      payAmountText: '100 USDC',
      receiveAmountText: '1.425 ZEC',
    ),
  );
}

Widget buildSwapWidgetFigmaNode1UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode1State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapWidgetFigmaNode2UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode2State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapWidgetFigmaNode3UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode3State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapWidgetFigmaNode5UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode5State,
      actionLabel: 'Add recipient address',
      zecAvailableText: '128 ZEC',
      zecAvailableZatoshi: BigInt.from(12800000000),
      maxAmountText: '128',
    ),
  );
}

Widget buildSwapWidgetFigmaNode6UseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _figmaNode6State,
      actionLabel: 'Add refund address',
    ),
  );
}

Widget buildSwapWidgetUnsupportedFiatUseCase(BuildContext context) {
  return _SwapWidgetFrame(
    child: _SwapComposerPreview(
      initialState: _unsupportedFiatState,
      actionLabel: 'Add refund address',
    ),
  );
}

final _figmaUsdc = SwapAsset.live(
  assetId: 'figma-usdc-op',
  symbol: 'USDC',
  blockchain: 'op',
  decimals: 6,
);

final _figmaShit = SwapAsset.live(
  assetId: 'figma-shit-sol',
  symbol: r'$SHIT',
  blockchain: 'sol',
  decimals: 6,
);

final _figmaAssetModalAssets = <SwapAsset>[
  _figmaUsdc,
  SwapAsset.eth,
  SwapAsset.usdc,
  SwapAsset.usdt,
  SwapAsset.dai,
  SwapAsset.wbtc,
  SwapAsset.near,
  SwapAsset.btc,
  SwapAsset.sol,
];

final _figmaExternalToZecAddressPlan = SwapAddressPlan.fromUserInput(
  direction: SwapDirection.externalToZec,
  externalAsset: SwapAsset.usdc,
  userExternalAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
  walletZecAddress: 'u1figmareviewwalletzecaddresspreview',
);

final _figmaZecToExternalAddressPlan = SwapAddressPlan.fromUserInput(
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  userExternalAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
  walletZecAddress: 'u1figmareviewwalletzecaddresspreview',
);

final _figmaExternalShitToZecAddressPlan = SwapAddressPlan.fromUserInput(
  direction: SwapDirection.externalToZec,
  externalAsset: _figmaShit,
  userExternalAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
  walletZecAddress: 'u1figmareviewwalletzecaddresspreview',
);

final _figmaZecToShitAddressPlan = SwapAddressPlan.fromUserInput(
  direction: SwapDirection.zecToExternal,
  externalAsset: _figmaShit,
  userExternalAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
  walletZecAddress: 'u1figmareviewwalletzecaddresspreview',
);

final _figmaReviewDefaultQuote = SwapQuote(
  direction: SwapDirection.externalToZec,
  sellAsset: SwapAsset.usdc,
  receiveAsset: SwapAsset.zec,
  externalAsset: SwapAsset.usdc,
  sellAmount: 110.24,
  receiveAmount: 0.251,
  minimumReceiveAmount: 0.249,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '2hrs',
  depositInstruction: SwapDepositInstruction(
    asset: SwapAsset.usdc,
    address: '0x123kjhc4e984ac1832f10aa4x98g20',
    expiresInLabel: '2hrs',
    reuseWarning: 'Do not reuse this address',
  ),
  sellAmountTextOverride: '999,999.99 USDC',
  receiveEstimateTextOverride: '0.251 ZEC',
  minimumReceiveTextOverride: '0.249 ZEC',
);

final _figmaReviewZecToExternalQuote = SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  sellAmount: 0.251,
  receiveAmount: 110.24,
  minimumReceiveAmount: 109.99,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '2hrs',
  depositInstruction: SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 't1figmareviewdepositaddress',
    expiresInLabel: '2hrs',
    reuseWarning: 'Do not reuse this address',
  ),
  sellAmountTextOverride: '0.251 ZEC',
  receiveEstimateTextOverride: '999,999.99 USDC',
  minimumReceiveTextOverride: '999,999.74 USDC',
);

final _figmaReviewLargeQuote = SwapQuote(
  direction: SwapDirection.externalToZec,
  sellAsset: _figmaShit,
  receiveAsset: SwapAsset.zec,
  externalAsset: _figmaShit,
  sellAmount: 999123000,
  receiveAmount: 0.251,
  minimumReceiveAmount: 0.249,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '2hrs',
  depositInstruction: SwapDepositInstruction(
    asset: _figmaUsdc,
    address: '0x123kjhc4e984ac1832f10aa4x98g20',
    expiresInLabel: '2hrs',
    reuseWarning: 'Do not reuse this address',
  ),
  receiveEstimateTextOverride: '0.251 ZEC',
  minimumReceiveTextOverride: '0.249 ZEC',
);

final _figmaReviewLargeRightQuote = SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: _figmaShit,
  externalAsset: _figmaShit,
  sellAmount: 0.251,
  receiveAmount: 999123000,
  minimumReceiveAmount: 999122000,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '2hrs',
  depositInstruction: SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 't1figmareviewdepositaddress',
    expiresInLabel: '2hrs',
    reuseWarning: 'Do not reuse this address',
  ),
  sellAmountTextOverride: '0.251 ZEC',
  receiveEstimateTextOverride: r'999,123,000.123456 $SHIT',
  minimumReceiveTextOverride: r'999,122,000 $SHIT',
);

final _figmaReviewLargeBothQuote = SwapQuote(
  direction: SwapDirection.externalToZec,
  sellAsset: _figmaShit,
  receiveAsset: SwapAsset.zec,
  externalAsset: _figmaShit,
  sellAmount: 999123000,
  receiveAmount: 888888.88,
  minimumReceiveAmount: 888000,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '2hrs',
  depositInstruction: SwapDepositInstruction(
    asset: _figmaShit,
    address: '0x123kjhc4e984ac1832f10aa4x98g20',
    expiresInLabel: '2hrs',
    reuseWarning: 'Do not reuse this address',
  ),
  sellAmountTextOverride: r'999,123,000.123456 $SHIT',
  receiveEstimateTextOverride: '888,888.88 ZEC',
  minimumReceiveTextOverride: '888,000 ZEC',
);

final _figmaUsdcPerZec = <SwapAsset, double>{_figmaUsdc: 6.57894737};
final _figmaZecPerUsdc = <SwapAsset, double>{_figmaUsdc: 512};

final _unsupportedFiatState = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '1.2345',
  receiveAmountText: '0.0521',
  destinationText: '',
  externalAsset: SwapAsset.eth,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
);

const _designProgressSteps = <SwapStatusStepData>[
  SwapStatusStepData(
    title: 'USDC source deposit',
    state: SwapStatusStepState.pending,
    completeTitle: 'USDC Deposited',
    activeTitle: 'Depositing USDC...',
    pendingTitle: 'Deposit USDC',
    lastCheckedLabel: 'Last check: 1m ago',
    description:
        'Confirm waiting for the source chain and provider to recognise the deposit',
  ),
  SwapStatusStepData(
    title: 'Deposit confirmation',
    state: SwapStatusStepState.pending,
    activeTitle: 'Deposit confirmation...',
    lastCheckedLabel: 'Last check: 1m ago',
    description:
        'Confirm waiting for the source chain and provider to recognise the deposit',
  ),
  SwapStatusStepData(
    title: 'Swap',
    state: SwapStatusStepState.pending,
    activeTitle: 'Swap...',
    lastCheckedLabel: 'Last check: 1m ago',
    description: 'The provider is executing the swap route.',
  ),
  SwapStatusStepData(
    title: 'Send ZEC',
    state: SwapStatusStepState.pending,
    activeTitle: 'Send ZEC...',
    lastCheckedLabel: 'Last check: 1m ago',
    description: 'Delivering ZEC to the recipient address.',
  ),
];

const _designAccountProfilePictureId = 'pfp-01';

const _designTransactionDetails = <SwapStatusDetailRowData>[
  SwapStatusDetailRowData(
    label: 'Account',
    value: 'John',
    accountProfilePictureId: _designAccountProfilePictureId,
  ),
  SwapStatusDetailRowData(
    label: 'USDC refund address',
    value: '0x123kjhc ... 4x98g20',
  ),
  SwapStatusDetailRowData(
    label: 'Deposit USDC to',
    value: '0x123kjhc ... 4x98g20',
    copyable: true,
  ),
  SwapStatusDetailRowData(
    label: 'Swap fee',
    value: 'Included in shown rate',
    help: true,
  ),
  SwapStatusDetailRowData(
    label: 'Slippage tolerance',
    value: '0.25 USDC (0.5%)',
  ),
  SwapStatusDetailRowData(
    label: 'Guaranteed minimum',
    value: '0.249 ZEC',
    help: true,
  ),
];

const _designCompletedDetails = <SwapStatusDetailRowData>[
  SwapStatusDetailRowData(
    label: 'Account',
    value: 'John',
    accountProfilePictureId: _designAccountProfilePictureId,
  ),
  SwapStatusDetailRowData(
    label: 'USDC deposit to',
    value: '0x123kjhc ... 4x98g20',
    copyable: true,
  ),
  SwapStatusDetailRowData(label: 'Total fees', value: '~0.25 USDC', help: true),
  SwapStatusDetailRowData(
    label: 'Realized slippage',
    value: '0.25 USDC (0.27%)',
  ),
  SwapStatusDetailRowData(label: 'Timestamp', value: 'May 20, 2026 13:20'),
];

const _designFailedDetails = <SwapStatusDetailRowData>[
  SwapStatusDetailRowData(
    label: 'Account',
    value: 'John',
    accountProfilePictureId: _designAccountProfilePictureId,
  ),
  SwapStatusDetailRowData(
    label: 'USDC refunded to',
    value: '0x123kjhc ... 4x98g20',
  ),
  SwapStatusDetailRowData(label: 'Total fees', value: '~0.25 USDC', help: true),
  SwapStatusDetailRowData(label: 'Timestamp', value: 'May 20, 2026 13:20'),
];

const _designIncompleteDepositDetails = <SwapStatusDetailRowData>[
  SwapStatusDetailRowData(
    label: 'Account',
    value: 'John',
    accountProfilePictureId: _designAccountProfilePictureId,
  ),
  SwapStatusDetailRowData(label: 'Missing deposit', value: '40 USDC'),
  SwapStatusDetailRowData(
    label: 'Memo',
    value: 'memo-underpaid',
    copyable: true,
  ),
  SwapStatusDetailRowData(
    label: 'Deposit USDC to',
    value: '0x123kjhc ... 4x98g20',
    copyable: true,
  ),
  SwapStatusDetailRowData(label: 'Required deposit', value: '100 USDC'),
  SwapStatusDetailRowData(label: 'Detected deposit', value: '60 USDC'),
  SwapStatusDetailRowData(
    label: 'Deposit deadline',
    value: 'May 20, 2026 13:20',
  ),
  SwapStatusDetailRowData(label: 'Refund fee', value: '0.25 USDC'),
  SwapStatusDetailRowData(
    label: 'USDC refund address',
    value: '0x123kjhc ... 4x98g20',
    copyable: true,
  ),
];

final _figmaNode1State = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '0',
  receiveAmountText: '0',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

final _figmaNode2State = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '0',
  receiveAmountText: '0',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  quoteMode: SwapQuoteMode.exactOutput,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

final _figmaNode3State = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  receiveAmountText: '0.25',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

final _figmaNode5State = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '0.25',
  receiveAmountText: '100',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _figmaZecPerUsdc,
);

final _figmaNode6State = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  amountFiatText: '100',
  amountInputMode: SwapAmountInputMode.fiat,
  receiveAmountText: '0.25',
  receiveFiatText: '100',
  receiveAmountInputMode: SwapAmountInputMode.fiat,
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _figmaUsdcPerZec,
);

class _SwapFlowPageFrame extends StatelessWidget {
  const _SwapFlowPageFrame({
    required this.backLabel,
    required this.child,
    this.childAlignment = Alignment.center,
  });

  final String backLabel;
  final Widget child;
  final Alignment childAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1080.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 720.0;

        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: colors.background.base,
            child: AppDesktopShell(
              sidebar: const _PreviewSwapSidebar(),
              pane: AppDesktopPane(
                padding: EdgeInsets.zero,
                child: AppPaneScrollScaffold(
                  toolbar: AppPaneToolbar(
                    leading: AppBackLink(
                      label: backLabel,
                      minWidth: 60,
                      onTap: () {},
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Align(alignment: childAlignment, child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

typedef _SwapReviewPageFrame = _SwapFlowPageFrame;

class _SwapStatusPageFrame extends StatelessWidget {
  const _SwapStatusPageFrame({required this.backLabel, required this.child});

  final String backLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _SwapFlowPageFrame(
      backLabel: backLabel,
      childAlignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _SwapReviewPreview extends StatelessWidget {
  const _SwapReviewPreview({
    required this.quote,
    required this.addressPlan,
    this.slippageToleranceText,
    this.payFiatText,
    this.receiveFiatText,
  });

  final SwapQuote quote;
  final SwapAddressPlan addressPlan;
  final String? slippageToleranceText;
  final String? payFiatText;
  final String? receiveFiatText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwapReviewPageContent(
          quote: quote,
          addressPlan: addressPlan,
          expired: false,
          amountWarning: null,
          startError: null,
          slippageToleranceTextOverride: slippageToleranceText,
          payFiatTextOverride: payFiatText,
          receiveFiatTextOverride: receiveFiatText,
          onCopy: (_) {},
        ),
        const SizedBox(height: AppSpacing.base),
        SwapReviewPageActions(
          expired: false,
          starting: false,
          sendsZec: quote.direction.sendsZec,
          onCancelReview: () {},
          onReviewAgain: () {},
          onStartIntent: () {},
        ),
      ],
    );
  }
}

class _SwapStatusPreview extends StatefulWidget {
  const _SwapStatusPreview({
    required this.title,
    required this.badgeKind,
    required this.steps,
    required this.details,
    this.activeTab = SwapStatusTab.progress,
    this.progressIndex = 0,
    this.showTabs = true,
    this.statusLabel = 'Completed',
    this.payAsset = SwapAsset.usdc,
    this.receiveAsset = SwapAsset.zec,
    this.payFiatText = '\$110.24',
    this.receiveFiatText = '\$110.24',
    this.payAmountText = '999,999.99 USDC',
    this.receiveAmountText = '0.251 ZEC',
  });

  final String title;
  final SwapStatusBadgeKind badgeKind;
  final List<SwapStatusStepData> steps;
  final List<SwapStatusDetailRowData> details;
  final SwapStatusTab activeTab;
  final int progressIndex;
  final bool showTabs;
  final String statusLabel;
  final SwapAsset payAsset;
  final SwapAsset receiveAsset;
  final String payFiatText;
  final String receiveFiatText;
  final String payAmountText;
  final String receiveAmountText;

  @override
  State<_SwapStatusPreview> createState() => _SwapStatusPreviewState();
}

class _SwapStatusPreviewState extends State<_SwapStatusPreview> {
  late var _activeTab = widget.activeTab;

  @override
  void didUpdateWidget(covariant _SwapStatusPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab) {
      _activeTab = widget.activeTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwapStatusPageContent(
      title: widget.title,
      payAsset: widget.payAsset,
      receiveAsset: widget.receiveAsset,
      payAmountText: widget.payAmountText,
      receiveAmountText: widget.receiveAmountText,
      payDetailText: widget.payFiatText,
      receiveDetailText: widget.receiveFiatText,
      statusLabel: widget.statusLabel,
      badgeKind: widget.badgeKind,
      progressIndex: widget.progressIndex,
      activeTab: _activeTab,
      steps: widget.steps,
      details: widget.details,
      showTabs: widget.showTabs,
      onTabChanged: widget.showTabs
          ? (tab) {
              setState(() {
                _activeTab = tab;
              });
            }
          : null,
      onCopy: (_) {},
    );
  }
}

class _SwapStatusDetailsPreview extends StatelessWidget {
  const _SwapStatusDetailsPreview();

  @override
  Widget build(BuildContext context) {
    return _SwapStatusPreview(
      title: 'Swap in progress...',
      badgeKind: SwapStatusBadgeKind.liveQuote,
      activeTab: SwapStatusTab.details,
      steps: _designProgressSteps,
      details: _designTransactionDetails,
    );
  }
}

class _SwapWidgetFrame extends StatelessWidget {
  const _SwapWidgetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.ground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Swap',
                          style: AppTypography.displaySmall.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwapPreviewPageTitle extends StatelessWidget {
  const _SwapPreviewPageTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      'Swap',
      textAlign: TextAlign.center,
      style: appSerifDisplayStyle(color: colors.text.accent),
    );
  }
}

class _SwapPageFrame extends StatelessWidget {
  const _SwapPageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 1080,
      height: 720,
      child: ColoredBox(
        color: colors.background.base,
        child: AppDesktopShell(
          sidebar: const _PreviewSwapSidebar(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: AppPaneScrollScaffold(
              toolbar: const AppPaneToolbar(
                leading: AppBackLink(label: 'Back', minWidth: 60, onTap: _noop),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SwapPreviewPageTitle(),
                        const SizedBox(height: AppSpacing.md),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone-sized scrim frame that bottom-anchors the scan card in the shared
/// [MobileModalCard], mirroring the live swap dialog so the camera card fills
/// the rounded surface and the permission card hugs its height. Scaled to fit
/// the widgetbook viewport.
class _MobileScanCardFrame extends StatelessWidget {
  const _MobileScanCardFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 393,
          height: 852,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(393, 852)),
            child: ColoredBox(
              color: colors.background.neutralScrim,
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    MobileModalCard(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwapPageModalFrame extends StatelessWidget {
  const _SwapPageModalFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 1080,
      height: 720,
      child: ColoredBox(
        color: colors.background.base,
        child: AppDesktopShell(
          sidebar: const _PreviewSwapSidebar(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                AppPaneScrollScaffold(
                  toolbar: const AppPaneToolbar(
                    leading: AppBackLink(
                      label: 'Back',
                      minWidth: 60,
                      onTap: _noop,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s,
                          vertical: AppSpacing.sm,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _SwapPreviewPageTitle(),
                            const SizedBox(height: AppSpacing.md),
                            _SwapComposerPreview(
                              initialState: _figmaNode3State,
                              actionLabel: 'Add refund address',
                              showActionButton: false,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            const SwapNearIntentsAttribution(centered: true),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                AppPaneModalOverlay(onDismiss: _noop, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewSwapSidebar extends StatelessWidget {
  const _PreviewSwapSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Username',
                    iconName: AppIcons.user,
                    leadingGap: AppSpacing.xs,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Home',
                    iconName: AppIcons.home,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Swap',
                    iconName: AppIcons.swapArrows,
                    active: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Activity',
                    iconName: AppIcons.history,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Sign out',
                    iconName: AppIcons.logOut,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -AppSpacing.md,
                          top: 1,
                          bottom: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.sync.lightSyncing,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(AppRadii.full),
                              ),
                            ),
                            child: const SizedBox(width: 5),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '34% Syncing...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.sync.textSyncing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapComposerPreview extends StatefulWidget {
  const _SwapComposerPreview({
    required this.initialState,
    required this.actionLabel,
    this.zecAvailableText = '12.3456 ZEC',
    this.zecAvailableZatoshi,
    this.maxAmountText = '12.3456',
    this.showActionButton = true,
  });

  final SwapState initialState;
  final String actionLabel;
  final String zecAvailableText;
  final BigInt? zecAvailableZatoshi;
  final String maxAmountText;
  final bool showActionButton;

  @override
  State<_SwapComposerPreview> createState() => _SwapComposerPreviewState();
}

class _SwapComposerPreviewState extends State<_SwapComposerPreview> {
  late SwapState _state;
  var _assetSelectorOpen = false;
  var _slippageModalOpen = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
  }

  void _updateAmount(String value) {
    setState(() {
      final next = _state.copyWith(
        amountText: value,
        quoteMode: SwapQuoteMode.exactInput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          receiveAmountText: _estimateCounterpart(next),
          quoteMode: SwapQuoteMode.exactInput,
        ),
      );
    });
  }

  void _updateAmountFiat(String value) {
    setState(() {
      final amountText = swapTokenAmountTextFromFiatText(
        _state,
        asset: _state.direction.fromAsset(_state.externalAsset),
        fiatAmountText: value,
      );
      final next = _state.copyWith(
        amountText: amountText ?? '',
        amountFiatText: value,
        amountInputMode: SwapAmountInputMode.fiat,
        receiveAmountInputMode: SwapAmountInputMode.fiat,
        quoteMode: SwapQuoteMode.exactInput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(receiveAmountText: _estimateCounterpart(next)),
        preserveAmountFiatInput: true,
      );
    });
  }

  void _updateReceiveAmount(String value) {
    setState(() {
      final next = _state.copyWith(
        receiveAmountText: value,
        quoteMode: SwapQuoteMode.exactOutput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          amountText: _estimateCounterpart(next),
          quoteMode: SwapQuoteMode.exactOutput,
        ),
      );
    });
  }

  void _updateReceiveAmountFiat(String value) {
    setState(() {
      final receiveAmountText = swapTokenAmountTextFromFiatText(
        _state,
        asset: _state.direction.toAsset(_state.externalAsset),
        fiatAmountText: value,
      );
      final next = _state.copyWith(
        receiveAmountText: receiveAmountText ?? '',
        amountInputMode: SwapAmountInputMode.fiat,
        receiveFiatText: value,
        receiveAmountInputMode: SwapAmountInputMode.fiat,
        quoteMode: SwapQuoteMode.exactOutput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(amountText: _estimateCounterpart(next)),
        preserveReceiveFiatInput: true,
      );
    });
  }

  void _toggleFiatInputMode(SwapAmountInputSide side) {
    setState(() {
      _state = switch (side) {
        SwapAmountInputSide.pay => _state.copyWith(
          amountInputMode: _state.amountInputMode == SwapAmountInputMode.token
              ? SwapAmountInputMode.fiat
              : SwapAmountInputMode.token,
          receiveAmountInputMode:
              _state.amountInputMode == SwapAmountInputMode.token
              ? SwapAmountInputMode.fiat
              : SwapAmountInputMode.token,
          amountFiatText: swapFiatInputTextFromTokenText(
            _state,
            asset: _state.direction.fromAsset(_state.externalAsset),
            tokenAmountText: _state.amountText,
          ),
          receiveFiatText: swapFiatInputTextFromTokenText(
            _state,
            asset: _state.direction.toAsset(_state.externalAsset),
            tokenAmountText: _state.receiveAmountText,
          ),
        ),
        SwapAmountInputSide.receive => _state.copyWith(
          amountInputMode:
              _state.receiveAmountInputMode == SwapAmountInputMode.token
              ? SwapAmountInputMode.fiat
              : SwapAmountInputMode.token,
          receiveAmountInputMode:
              _state.receiveAmountInputMode == SwapAmountInputMode.token
              ? SwapAmountInputMode.fiat
              : SwapAmountInputMode.token,
          amountFiatText: swapFiatInputTextFromTokenText(
            _state,
            asset: _state.direction.fromAsset(_state.externalAsset),
            tokenAmountText: _state.amountText,
          ),
          receiveFiatText: swapFiatInputTextFromTokenText(
            _state,
            asset: _state.direction.toAsset(_state.externalAsset),
            tokenAmountText: _state.receiveAmountText,
          ),
        ),
      };
    });
  }

  void _toggleDirection() {
    setState(() {
      _state = _withDerivedFiatTexts(
        _state.copyWith(
          direction: _state.direction.toggled,
          amountText: '',
          receiveAmountText: '',
          amountInputMode: SwapAmountInputMode.token,
          receiveAmountInputMode: SwapAmountInputMode.token,
          amountFiatText: '',
          receiveFiatText: '',
          destinationText: '',
          quoteMode: SwapQuoteMode.exactInput,
        ),
      );
    });
  }

  void _useMaxZecAmount() {
    setState(() {
      final maxAmountText = widget.maxAmountText;
      final next = _state.copyWith(
        amountText: maxAmountText,
        quoteMode: SwapQuoteMode.exactInput,
      );
      _state = _withDerivedFiatTexts(
        next.copyWith(
          receiveAmountText: _estimateCounterpart(next),
          quoteMode: SwapQuoteMode.exactInput,
          amountInputMode: SwapAmountInputMode.token,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwapComposerPanel(
          state: _state,
          onAmountChanged: _updateAmount,
          onAmountFiatChanged: _updateAmountFiat,
          onReceiveAmountChanged: _updateReceiveAmount,
          onReceiveAmountFiatChanged: _updateReceiveAmountFiat,
          onToggleFiatInputMode: _toggleFiatInputMode,
          onToggleDirection: _toggleDirection,
          onOpenExternalAssetPicker: () {
            setState(() => _assetSelectorOpen = !_assetSelectorOpen);
          },
          onOpenDestinationAddress: () {
            setState(() {
              _state = _state.copyWith(
                destinationText: _state.direction.sendsZec
                    ? '0xrecipient'
                    : '0xrefund',
              );
            });
          },
          onOpenSlippageSettings: () {
            setState(() => _slippageModalOpen = !_slippageModalOpen);
          },
          onUseMaxZecAmount: _useMaxZecAmount,
          assetSelectorOpen: _assetSelectorOpen,
          slippageSettingsOpen: _slippageModalOpen,
          zecAvailableText: widget.zecAvailableText,
          zecAvailableZatoshi:
              widget.zecAvailableZatoshi ?? BigInt.from(1234560000),
        ),
        if (widget.showActionButton) ...[
          const SizedBox(height: AppSpacing.md),
          const SwapNearIntentsAttribution(centered: true),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: SizedBox(
              width: 232,
              child: AppButton(
                onPressed: () {},
                variant: AppButtonVariant.primary,
                size: AppButtonSize.large,
                minWidth: 232,
                child: SizedBox(
                  width: 168,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(widget.actionLabel, maxLines: 1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AddressQrCameraPreview extends StatelessWidget {
  const _AddressQrCameraPreview();

  @override
  Widget build(BuildContext context) {
    final overlayColor = const Color(0xFF141818).withValues(alpha: 0.18);
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF2E3232)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 8,
            right: 8,
            top: 10,
            child: Text(
              'Scan your external wallet transaction QR code.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 196,
              height: 142,
              padding: const EdgeInsets.all(6),
              color: const Color(0xFFFFFFFF),
              child: PrettyQrView.data(
                data: 'ethereum:0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
                decoration: const PrettyQrDecoration(
                  quietZone: PrettyQrQuietZone.zero,
                  shape: PrettyQrSmoothSymbol(
                    roundFactor: 0,
                    color: Color(0xFF141818),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2E3232),
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: const SizedBox(width: 64, height: 64),
            ),
          ),
          DecoratedBox(decoration: BoxDecoration(color: overlayColor)),
        ],
      ),
    );
  }
}

/// Stand-in for the live camera feed in the mobile scan-card use cases
/// (widgetbook has no camera): just a Zcash QR on a dark surface for the
/// card's viewfinder to frame — no caption (the card owns its own caption).
class _MobileScanCameraPreview extends StatelessWidget {
  const _MobileScanCameraPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF2E3232)),
      child: Center(
        child: Container(
          width: 200,
          height: 200,
          padding: const EdgeInsets.all(10),
          color: const Color(0xFFFFFFFF),
          child: PrettyQrView.data(
            data: 'zcash:u1examplezcashaddressforpreviewonly',
            decoration: const PrettyQrDecoration(
              quietZone: PrettyQrQuietZone.zero,
              shape: PrettyQrSmoothSymbol(
                roundFactor: 0,
                color: Color(0xFF141818),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _estimateCounterpart(SwapState state) {
  final quote = state.draftQuote;
  if (quote == null) return '';
  return state.quoteMode == SwapQuoteMode.exactInput
      ? quote.receiveAsset.formatAmountDown(quote.receiveAmount)
      : quote.sellAsset.formatAmountUp(quote.sellAmount);
}

SwapState _withDerivedFiatTexts(
  SwapState state, {
  bool preserveAmountFiatInput = false,
  bool preserveReceiveFiatInput = false,
}) {
  return state.copyWith(
    amountFiatText: preserveAmountFiatInput
        ? state.amountFiatText
        : swapFiatInputTextFromTokenText(
            state,
            asset: state.direction.fromAsset(state.externalAsset),
            tokenAmountText: state.amountText,
          ),
    receiveFiatText: preserveReceiveFiatInput
        ? state.receiveFiatText
        : swapFiatInputTextFromTokenText(
            state,
            asset: state.direction.toAsset(state.externalAsset),
            tokenAmountText: state.receiveAmountText,
          ),
  );
}
