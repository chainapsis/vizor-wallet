// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_layout.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/swap/models/swap_fiat_amount.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_state_provider.dart';
import '../src/features/swap/providers/pay_selected_asset_store.dart';
import '../src/features/swap/providers/swap_composer_preferences_store.dart';
import '../src/features/swap/screens/swap_review_screen.dart';
import '../src/features/swap/screens/swap_screen.dart';
import '../src/features/swap/screens/mobile/mobile_swap_screen.dart';
import '../src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import '../src/features/activity/screens/swap_activity_detail_screen.dart';
import '../src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import '../src/features/swap/models/swap_activity_navigation.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_address_edit_modal.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_asset_selector_modal.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import '../src/features/swap/widgets/swap_address_edit_modal.dart';
import '../src/features/swap/widgets/swap_asset_selector_modal.dart';
import '../src/features/swap/widgets/swap_composer_panel.dart';
import '../src/features/swap/widgets/swap_deposit_tokens_page_content.dart';
import '../src/features/swap/widgets/swap_near_intents_attribution.dart';
import '../src/features/swap/widgets/swap_review_page_content.dart';
import '../src/features/swap/widgets/swap_slippage_modal.dart';
import '../src/features/swap/widgets/swap_status_page_content.dart';
import 'support/wb_layout.dart';
import 'support/wb_address_book_repository.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/privacy_mode_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';

/// Which fixture frame the composer preview sits in: the desktop swap page
/// shell, or the standalone widget card.
enum SwapComposerFrame { page, widget, screen }

/// Deterministic provider outcomes used by the real Swap screen gallery.
enum SwapScreenSimulationScenario {
  happyPath,
  quoteFailure,
  invalidInput,
  expiredQuote,
}

String swapScreenSimulationScenarioLabel(SwapScreenSimulationScenario value) =>
    switch (value) {
      SwapScreenSimulationScenario.happyPath => 'Happy path',
      SwapScreenSimulationScenario.quoteFailure => 'Quote failure and retry',
      SwapScreenSimulationScenario.invalidInput => 'Invalid input',
      SwapScreenSimulationScenario.expiredQuote => 'Expired quote',
    };

/// The composer fixture states the Figma nodes pinned.
enum SwapComposerFixture {
  payAmountActive,
  receiveAmountActive,
  amountEntered,
  directionSwitched,
  fiatValueInput,
  unsupportedFiatPrice,
  torBlocked,
  savedContactAddress,
  overAvailableBalance,
  maxAmountFailed,
  quoteLoading,
  rateUnavailable,
  assetPillOpen,
  slippagePillOpen,
  wrongDestinationFormat,
}

/// Shared body of the composer twins: the same fixture states in either frame.
/// Every `build*UseCase` below delegates here so the fixtures keep their names
/// and renders while the gallery can reach any frame/state pair.
Widget swapComposerFixture({
  required SwapComposerFrame frame,
  required SwapComposerFixture fixture,
}) {
  final preview = switch (fixture) {
    SwapComposerFixture.payAmountActive => _SwapComposerPreview(
      initialState: _figmaNode1State,
      actionLabel: 'Add refund address',
    ),
    SwapComposerFixture.receiveAmountActive => _SwapComposerPreview(
      initialState: _figmaNode2State,
      actionLabel: 'Add refund address',
    ),
    SwapComposerFixture.amountEntered => _SwapComposerPreview(
      initialState: _figmaNode3State,
      actionLabel: 'Add refund address',
    ),
    SwapComposerFixture.directionSwitched => _SwapComposerPreview(
      initialState: _figmaNode5State,
      actionLabel: 'Add recipient address',
      zecAvailableText: '128 ZEC',
      zecAvailableZatoshi: BigInt.from(12800000000),
      maxAmountText: '128',
    ),
    SwapComposerFixture.fiatValueInput => _SwapComposerPreview(
      initialState: _figmaNode6State,
      actionLabel: 'Add refund address',
    ),
    SwapComposerFixture.unsupportedFiatPrice => _SwapComposerPreview(
      initialState: _unsupportedFiatState,
      actionLabel: 'Add refund address',
    ),
    SwapComposerFixture.torBlocked => _SwapComposerPreview(
      initialState: _torBlockedState,
      actionLabel: 'Add refund address',
    ),
    SwapComposerFixture.savedContactAddress => _SwapComposerPreview(
      initialState: _savedContactState,
      actionLabel: 'Review swap',
      destinationContactName: kSwapPreviewContactLabel,
    ),
    SwapComposerFixture.overAvailableBalance => _SwapComposerPreview(
      initialState: _overAvailableState,
      actionLabel: 'Not enough ZEC',
    ),
    SwapComposerFixture.maxAmountFailed => _SwapComposerPreview(
      initialState: _maxAmountFailedState,
      actionLabel: 'Review swap',
    ),
    SwapComposerFixture.quoteLoading => _SwapComposerPreview(
      initialState: _quoteLoadingState,
      actionLabel: 'Getting quote',
    ),
    SwapComposerFixture.rateUnavailable => _SwapComposerPreview(
      initialState: _rateUnavailableState,
      actionLabel: 'Add refund address',
    ),
    SwapComposerFixture.assetPillOpen => _SwapComposerPreview(
      initialState: _figmaNode3State,
      actionLabel: 'Add refund address',
      initialAssetSelectorOpen: true,
    ),
    SwapComposerFixture.slippagePillOpen => _SwapComposerPreview(
      initialState: _figmaNode3State,
      actionLabel: 'Add refund address',
      initialSlippageOpen: true,
    ),
    SwapComposerFixture.wrongDestinationFormat => _SwapComposerPreview(
      initialState: _wrongFormatDestinationState,
      actionLabel: 'Enter a valid USDC address',
    ),
  };
  return switch (frame) {
    SwapComposerFrame.page => _SwapPageFrame(child: preview),
    SwapComposerFrame.widget => _SwapWidgetFrame(child: preview),
    // The real screen is reached through [swapScreenFixture], which needs the
    // overlay/pane axes the mock frames have no notion of.
    SwapComposerFrame.screen => swapScreenFixture(fixture: fixture),
  };
}

Widget buildSwapPageFigmaNode5UseCase(BuildContext context) {
  return swapComposerFixture(
    frame: SwapComposerFrame.page,
    fixture: SwapComposerFixture.directionSwitched,
  );
}

Widget buildSwapPageTorBlockedUseCase(BuildContext context) {
  return swapComposerFixture(
    frame: SwapComposerFrame.page,
    fixture: SwapComposerFixture.torBlocked,
  );
}

/// Which side of the swap the address belongs to; the modal derives its
/// title, field label, description and remember copy from the direction.
enum SwapAddressModalDirection { refund, recipient }

/// What the entered address makes the format check say. `empty` is the
/// pinned Figma state (focused field, no message line).
enum SwapAddressModalFormat { empty, valid, unusual, invalid }

/// Whether a saved contact holds the entered address. A finding outranks the
/// match, so this only shows on [SwapAddressModalFormat.valid].
enum SwapAddressModalContact { none, matched }

/// The swap address editor in either form factor.
///
/// [rememberAddress] only reaches the mobile modal: the desktop toggle is
/// internal state with no prop, so it can only be turned on by tapping it.
Widget swapAddressEditFixture({
  bool mobile = false,
  SwapAddressModalDirection direction = SwapAddressModalDirection.refund,
  SwapAddressModalFormat format = SwapAddressModalFormat.empty,
  SwapAddressModalContact contact = SwapAddressModalContact.none,
  bool rememberAddress = false,
}) {
  // The only warning-severity finding is a bare NEAR name, so the unusual
  // option also moves the asset to NEAR (and with it the title).
  final asset =
      format == SwapAddressModalFormat.unusual ? SwapAsset.near : _figmaUsdc;
  final address = switch (format) {
    SwapAddressModalFormat.empty => '',
    SwapAddressModalFormat.valid => _swapModalContactAddress,
    SwapAddressModalFormat.unusual => 'alice',
    SwapAddressModalFormat.invalid => '0xnot-an-address',
  };
  final state = _figmaNode3State.copyWith(
    direction:
        direction == SwapAddressModalDirection.recipient
            ? SwapDirection.zecToExternal
            : SwapDirection.externalToZec,
    externalAsset: asset,
    destinationText: address,
  );
  final contacts =
      contact == SwapAddressModalContact.matched
          ? [
            AddressBookContact(
              id: 'widgetbook-swap-modal-contact',
              label: 'Mike',
              network:
                  AddressBookNetwork.tryFromChainTicker(asset.chainTicker) ??
                  AddressBookNetwork.ethereum,
              address: address,
              profilePictureId: 'pfp-02',
              createdAtMs: 0,
              updatedAtMs: 0,
            ),
          ]
          : const <AddressBookContact>[];
  if (mobile) {
    return _MobileSwapModalFrame(
      child: MobileSwapAddressEditModal(
        state: state,
        contacts: contacts,
        initialRememberAddress: rememberAddress,
        onSubmitted: (_, _) {},
        onScan: (_, _) {},
        onOpenContacts: (_, _) {},
        onCancel: _noop,
      ),
    );
  }
  return _SwapPageModalFrame(
    child: SwapAddressEditModal(
      state: state,
      contacts: contacts,
      onSubmitted: (_, _) {},
      onScan: () {},
      onOpenContacts: () {},
      onCancel: () {},
    ),
  );
}

/// Lowercase 0x hex so the EVM check passes without EIP-55 casing.
const _swapModalContactAddress = '0x52908400098527886e0f7030069857d2e4169ee7';

void _noop() {}

/// Tolerance the modal opens on: the three presets plus the custom-field
/// bounds. `outOfRange` is desktop-only — see [swapSlippageFixture].
enum SwapSlippageValue {
  minimum,
  presetHalf,
  presetOne,
  presetTwo,
  custom,
  maximum,
  outOfRange,
}

/// Basis points each option pins; the desktop presets are 50/100/200.
int _swapSlippageBps(SwapSlippageValue value) {
  return switch (value) {
    SwapSlippageValue.minimum => 10,
    SwapSlippageValue.presetHalf => 50,
    SwapSlippageValue.presetOne => 100,
    SwapSlippageValue.presetTwo => 200,
    SwapSlippageValue.custom => 125,
    SwapSlippageValue.maximum => 500,
    // Desktop seeds the custom field instead, so the stored value stays valid.
    SwapSlippageValue.outOfRange => 1500,
  };
}

/// The slippage editor in either form factor.
///
/// The mobile stepper clamps its input to 0.1–5% on entry, so `outOfRange`
/// only renders as out of range on desktop (which seeds the custom field);
/// on mobile it shows the clamped 5% with Update still enabled.
Widget swapSlippageFixture({
  bool mobile = false,
  bool paymentMode = false,
  SwapSlippageValue value = SwapSlippageValue.presetHalf,
}) {
  final bps = _swapSlippageBps(value);
  if (mobile) {
    return _MobileSwapModalFrame(
      child: MobileSwapSlippageStepperModal(
        slippageBps: bps,
        paymentMode: paymentMode,
        onSubmitted: (_) {},
        onCancel: _noop,
      ),
    );
  }
  return _SwapPageModalFrame(
    child: SwapSlippageModal(
      slippageBps: value == SwapSlippageValue.outOfRange ? 50 : bps,
      initialCustomText: value == SwapSlippageValue.outOfRange ? '15' : null,
      paymentMode: paymentMode,
      onSubmitted: (_) {},
      onCancel: () {},
    ),
  );
}

/// What the search field is seeded with; the modal filters as it is typed, so
/// a query is a fixture input rather than an interaction.
enum SwapAssetModalQuery { none, matching, noMatch }

/// Whether the pinned selection is one of the listed assets.
enum SwapAssetModalSelection { none, usdc }

enum SwapAssetModalLength { short, long }

/// The external-asset picker in either form factor.
Widget swapAssetSelectorFixture({
  bool mobile = false,
  SwapAssetModalQuery query = SwapAssetModalQuery.none,
  SwapAssetModalSelection selection = SwapAssetModalSelection.usdc,
  SwapAssetModalLength length = SwapAssetModalLength.long,
}) {
  final assets =
      length == SwapAssetModalLength.long
          ? _figmaAssetModalAssets
          : _figmaAssetModalAssets.take(3).toList();
  // ZEC is never in the external list, so it reads as "nothing selected".
  final selected =
      selection == SwapAssetModalSelection.usdc ? _figmaUsdc : SwapAsset.zec;
  final initialQuery = switch (query) {
    SwapAssetModalQuery.none => '',
    SwapAssetModalQuery.matching => 'us',
    SwapAssetModalQuery.noMatch => 'Value',
  };
  if (mobile) {
    return _MobileSwapModalFrame(
      child: MobileSwapAssetSelectorModal(
        assets: assets,
        selected: selected,
        initialQuery: initialQuery,
        onSelected: (_) {},
        onClose: _noop,
      ),
    );
  }
  return _SwapPageModalFrame(
    child: SwapAssetSelectorModal(
      assets: assets,
      selected: selected,
      initialQuery: initialQuery,
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

/// Pay-mode progress: the payment summary card, 'Payment progress' tab and
/// the recipient-facing labels the status mapper produces for `payMode`.
Widget buildSwapStatusPaymentProgressUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Payment in progress',
      badgeKind: SwapStatusBadgeKind.liveQuote,
      activeTab: SwapStatusTab.progress,
      progressIndex: 1,
      steps: _designProgressSteps,
      details: _designTransactionDetails,
      paymentMode: true,
      progressTabLabel: 'Payment progress',
      payLabel: 'You pay',
      receiveLabel: 'Recipient gets',
      payAsset: SwapAsset.zec,
      receiveAsset: SwapAsset.usdc,
      payAmountText: '2.0000 ZEC',
      receiveAmountText: '123.45 USDC',
      payFiatText: 'Privately, from shielded balance',
      receiveFiatText: 'To: 0x123kjhc ... 4x98g20 on Ethereum',
    ),
  );
}

Widget buildSwapStatusPaymentCompletedUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Payment complete',
      badgeKind: SwapStatusBadgeKind.completed,
      showTabs: false,
      steps: const [],
      details: _designCompletedDetails,
      paymentMode: true,
      progressTabLabel: 'Payment progress',
      payLabel: 'You paid',
      receiveLabel: 'Recipient received',
      payAsset: SwapAsset.zec,
      receiveAsset: SwapAsset.usdc,
      payAmountText: '2.0000 ZEC',
      receiveAmountText: '123.45 USDC',
      payFiatText: 'Privately, from shielded balance',
      receiveFiatText: 'To: 0x123kjhc ... 4x98g20 on Ethereum',
    ),
  );
}

/// Refunded is a terminal failure: same 'Swap failed' title as `failed`, with
/// the Status row reading 'Refunded' and the refund detail rows.
Widget buildSwapStatusRefundedUseCase(BuildContext context) {
  return _SwapStatusPageFrame(
    backLabel: 'Activity',
    child: _SwapStatusPreview(
      title: 'Swap failed',
      badgeKind: SwapStatusBadgeKind.failed,
      statusLabel: 'Refunded',
      showTabs: false,
      steps: const [],
      details: _designRefundedDetails,
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

final _torBlockedState = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '0',
  receiveAmountText: '0',
  destinationText: '',
  externalAsset: _figmaUsdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  supportedAssetsError:
      'Swap is unavailable over Tor because the service blocked this connection.\n'
      'Turn off Tor in Settings to use swap.',
);

/// Address and label the saved-contact composer/screen previews match on.
const kSwapPreviewContactLabel = 'Bea';
const kSwapPreviewContactAddress = '0x52908400098527886E0F7030069857D2E4169EE7';

final _savedContactState = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  receiveAmountText: '0.25',
  destinationText: kSwapPreviewContactAddress,
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _previewUsdcPerZec,
);

final _overAvailableState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '99',
  receiveAmountText: '6510',
  destinationText: kSwapPreviewContactAddress,
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _previewUsdcPerZec,
);

final _maxAmountFailedState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '0.25',
  receiveAmountText: '16.44',
  destinationText: kSwapPreviewContactAddress,
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _previewUsdcPerZec,
  maxAmountError: "Couldn't read balance",
);

final _quoteLoadingState = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  receiveAmountText: '0.25',
  destinationText: kSwapPreviewContactAddress,
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _previewUsdcPerZec,
  quoteLoading: true,
);

// A zero indicative rate is the only input that makes the ticket footer fall
// back to '--'; every asset's static fallback is positive.
final _rateUnavailableState = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  receiveAmountText: '',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: {SwapAsset.usdc: 0},
);

final _wrongFormatDestinationState = SwapState(
  direction: SwapDirection.externalToZec,
  amountText: '100',
  receiveAmountText: '0.25',
  destinationText: 'not-an-evm-address',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: [],
  slippageBps: 50,
  indicativeExternalPerZec: _previewUsdcPerZec,
);

final _previewUsdcPerZec = <SwapAsset, double>{SwapAsset.usdc: 6.57894737};

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

const _designRefundedDetails = <SwapStatusDetailRowData>[
  SwapStatusDetailRowData(
    label: 'Account',
    value: 'John',
    accountProfilePictureId: _designAccountProfilePictureId,
  ),
  SwapStatusDetailRowData(
    label: 'USDC refunded to',
    value: '0x123kjhc ... 4x98g20',
    copyable: true,
  ),
  SwapStatusDetailRowData(label: 'Refunded amount', value: '99.75 USDC'),
  SwapStatusDetailRowData(label: 'Refund fee', value: '0.25 USDC'),
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
    return WbDesktopWindowBox(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 1080.0;
          final height =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 720.0;

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
      ),
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
    this.paymentMode = false,
    this.progressTabLabel = 'Swap progress',
    this.payLabel = "You're paying",
    this.receiveLabel = "You're receiving",
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
  final bool paymentMode;
  final String progressTabLabel;
  final String payLabel;
  final String receiveLabel;

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
      paymentMode: widget.paymentMode,
      progressTabLabel: widget.progressTabLabel,
      payLabel: widget.payLabel,
      receiveLabel: widget.receiveLabel,
      payDetailText: widget.payFiatText,
      receiveDetailText: widget.receiveFiatText,
      statusLabel: widget.statusLabel,
      badgeKind: widget.badgeKind,
      progressIndex: widget.progressIndex,
      activeTab: _activeTab,
      steps: widget.steps,
      details: widget.details,
      showTabs: widget.showTabs,
      launchExternalUri: (_) async {},
      onTabChanged:
          widget.showTabs
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
    return WbDesktopWindowBox(
      size: const Size(1080, 720),
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

/// Phone-sized scrim frame that bottom-anchors a swap modal in the shared
/// [MobileModalCard], the way the mobile swap routes present these sheets.
class _MobileSwapModalFrame extends StatelessWidget {
  const _MobileSwapModalFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: WbScaleDownBox(
        size: const Size(393, 852),
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
                  children: [const Spacer(), MobileModalCard(child: child)],
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
    return WbDesktopWindowBox(
      size: const Size(1080, 720),
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
                    label: 'Pay',
                    iconName: AppIcons.paid,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Vote',
                    iconName: AppIcons.vote,
                    onTap: () {},
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
                              color: colors.sync.lightSuccess,
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
    this.destinationContactName,
    this.initialAssetSelectorOpen = false,
    this.initialSlippageOpen = false,
  });

  final SwapState initialState;
  final String actionLabel;
  final String zecAvailableText;
  final BigInt? zecAvailableZatoshi;
  final String maxAmountText;
  final bool showActionButton;

  /// Address-book label the destination chip shows instead of the truncated
  /// address; the real screen resolves it from the address book.
  final String? destinationContactName;
  final bool initialAssetSelectorOpen;
  final bool initialSlippageOpen;

  @override
  State<_SwapComposerPreview> createState() => _SwapComposerPreviewState();
}

class _SwapComposerPreviewState extends State<_SwapComposerPreview> {
  late SwapState _state;
  late var _assetSelectorOpen = widget.initialAssetSelectorOpen;
  late var _slippageModalOpen = widget.initialSlippageOpen;

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
          amountInputMode:
              _state.amountInputMode == SwapAmountInputMode.token
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
                destinationText:
                    _state.direction.sendsZec ? '0xrecipient' : '0xrefund',
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
          destinationContactName: widget.destinationContactName,
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
    amountFiatText:
        preserveAmountFiatInput
            ? state.amountFiatText
            : swapFiatInputTextFromTokenText(
              state,
              asset: state.direction.fromAsset(state.externalAsset),
              tokenAmountText: state.amountText,
            ),
    receiveFiatText:
        preserveReceiveFiatInput
            ? state.receiveFiatText
            : swapFiatInputTextFromTokenText(
              state,
              asset: state.direction.toAsset(state.externalAsset),
              tokenAmountText: state.receiveAmountText,
            ),
  );
}

// ===========================================================================
// Desktop swap screens over preview providers
// ===========================================================================

/// Screen-hosted modal the desktop swap screen opens over its composer.
enum SwapScreenOverlay {
  none,
  assetSelector,
  addressEditor,
  contactPicker,
  slippage,
}

/// Which quote the review screen is confirming, and what is blocking it.
enum SwapReviewScreenCase {
  review,
  payment,
  expired,
  amountDrift,
  startError,
  notEnoughZec,
  submitting,
}

const _swapScreenAccountUuid = 'widgetbook-swap-screen-account';
const _swapScreenWindowSize = Size(1080, 720);

/// Pane height below the screen's 624 pinned threshold, so the packed option
/// really exercises the scrolling branch.
///
/// Deliberately *below* the app's 1080×720 minimum (`app_layout.dart`): the
/// threshold is on the pane, and shortening the window is how the preview
/// crosses it. The sub-minimum height is the point — do not "correct" it
/// to 720.
const Size _swapScreenPackedWindowSize = Size(1080, 560);

/// The real [SwapScreen] on `/swap`, with its screen-hosted modal surfaces.
///
/// [fixture] seeds the same composer states the panel previews use, so the
/// footer ladder ('Add refund address' / 'Getting quote' / 'Not enough ZEC')
/// is derived by the real screen rather than posed.
Widget swapScreenFixture({
  SwapComposerFixture fixture = SwapComposerFixture.amountEntered,
  SwapScreenOverlay overlay = SwapScreenOverlay.none,
  bool packedPane = false,
  bool hideAmounts = false,
}) {
  return _swapScreenScope(
    swapState: _swapScreenState(fixture),
    hideAmounts: hideAmounts,
    location: '/swap',
    child: _SwapScreenHarness(
      location: '/swap',
      windowSize:
          packedPane ? _swapScreenPackedWindowSize : _swapScreenWindowSize,
      child: _SwapTapOnMount(
        keys: _swapScreenOverlayKeys(_swapScreenOverlayFor(fixture, overlay)),
        child: const SwapScreen(),
      ),
    ),
  );
}

/// The single connected Swap gallery screen. It keeps the existing fixture
/// state knob meaningful, but inputs, review and result all run through the
/// production screen and route widgets with an in-memory notifier.
Widget swapInteractiveScreenFixture({
  required bool mobile,
  required SwapComposerFixture fixture,
  required bool hideAmounts,
  required SwapScreenSimulationScenario scenario,
}) {
  final fixtureState = _swapScreenState(fixture);
  // Figma fixtures can use an asset deliberately outside the live default
  // list. The connected preview needs its selected fixture asset quoteable.
  final initialState = fixtureState.copyWith(
    supportedExternalAssets: [
      fixtureState.externalAsset,
      ...swapExternalAssets.where(
        (asset) => asset != fixtureState.externalAsset,
      ),
    ],
  );
  return _swapScreenScope(
    swapState: initialState,
    hideAmounts: hideAmounts,
    location: '/swap',
    swapNotifierBuilder: () => _SwapInteractiveNotifier(initialState, scenario),
    child: _SwapScreenHarness(
      location: '/swap',
      windowSize: _swapScreenWindowSize,
      mobile: mobile,
      interactive: true,
      child: mobile ? const MobileSwapScreen() : const SwapScreen(),
    ),
  );
}

/// An open pill is a hosted modal on the real screen, so the two pill-open
/// composer states open it instead of rendering as a plain amount entry.
SwapScreenOverlay _swapScreenOverlayFor(
  SwapComposerFixture fixture,
  SwapScreenOverlay overlay,
) {
  if (overlay != SwapScreenOverlay.none) return overlay;
  return switch (fixture) {
    SwapComposerFixture.assetPillOpen => SwapScreenOverlay.assetSelector,
    SwapComposerFixture.slippagePillOpen => SwapScreenOverlay.slippage,
    _ => overlay,
  };
}

/// The real [SwapReviewScreen] with its own toolbar and back link.
Widget swapReviewScreenFixture({
  SwapReviewScreenCase state = SwapReviewScreenCase.review,
}) {
  final payMode = state == SwapReviewScreenCase.payment;
  return _swapScreenScope(
    swapState: _swapReviewScreenState(state),
    // 'Not enough ZEC' is the screen's own comparison of the review quote
    // against the migration-aware spendable balance, so a smaller balance
    // drives it rather than a posed label.
    spendableZatoshi:
        state == SwapReviewScreenCase.notEnoughZec
            ? BigInt.from(10000000)
            : BigInt.from(1234560000),
    location: payMode ? '/pay/review' : '/swap/review',
    child: _SwapScreenHarness(
      location: payMode ? '/pay/review' : '/swap/review',
      windowSize: _swapScreenWindowSize,
      child: SwapReviewScreen(payMode: payMode),
    ),
  );
}

List<Key> _swapScreenOverlayKeys(SwapScreenOverlay overlay) {
  return switch (overlay) {
    SwapScreenOverlay.none => const [],
    SwapScreenOverlay.assetSelector => const [
      ValueKey('swap_external_asset_selector'),
    ],
    SwapScreenOverlay.addressEditor => const [ValueKey('swap_address_summary')],
    SwapScreenOverlay.contactPicker => const [
      ValueKey('swap_address_summary'),
      ValueKey('swap_address_contacts_button'),
    ],
    SwapScreenOverlay.slippage => const [ValueKey('swap_settings_button')],
  };
}

SwapState _swapScreenState(SwapComposerFixture fixture) {
  return switch (fixture) {
    SwapComposerFixture.payAmountActive => _figmaNode1State,
    SwapComposerFixture.receiveAmountActive => _figmaNode2State,
    SwapComposerFixture.amountEntered => _figmaNode3State,
    SwapComposerFixture.directionSwitched => _figmaNode5State,
    SwapComposerFixture.fiatValueInput => _figmaNode6State,
    SwapComposerFixture.unsupportedFiatPrice => _unsupportedFiatState,
    SwapComposerFixture.torBlocked => _torBlockedState,
    SwapComposerFixture.savedContactAddress => _savedContactState,
    SwapComposerFixture.overAvailableBalance => _overAvailableState,
    SwapComposerFixture.maxAmountFailed => _maxAmountFailedState,
    SwapComposerFixture.quoteLoading => _quoteLoadingState,
    SwapComposerFixture.rateUnavailable => _rateUnavailableState,
    // The pill-open poses carry no composer state of their own; the screen
    // opens the matching modal instead (see [_swapScreenOverlayFor]).
    SwapComposerFixture.assetPillOpen => _figmaNode3State,
    SwapComposerFixture.slippagePillOpen => _figmaNode3State,
    SwapComposerFixture.wrongDestinationFormat => _wrongFormatDestinationState,
  };
}

SwapState _swapReviewScreenState(SwapReviewScreenCase state) {
  final payMode = state == SwapReviewScreenCase.payment;
  // Only a ZEC-spending quote can be blocked on the wallet's own balance, so
  // the 'Not enough ZEC' case has to sell ZEC like the pay quote does.
  final sendsZec = payMode || state == SwapReviewScreenCase.notEnoughZec;
  final quote =
      sendsZec ? _figmaReviewZecToExternalQuote : _figmaReviewDefaultQuote;
  final addressPlan =
      sendsZec
          ? _figmaZecToExternalAddressPlan
          : _figmaExternalToZecAddressPlan;
  return SwapState(
    direction: quote.direction,
    // The drift notice compares the live review quote against the composer's
    // own indicative estimate, so only that case seeds a diverging rate.
    amountText: state == SwapReviewScreenCase.amountDrift ? '110.24' : '',
    receiveAmountText: '',
    destinationText: kSwapPreviewContactAddress,
    externalAsset: SwapAsset.usdc,
    reviewVisible: true,
    intents: const [],
    slippageBps: 50,
    indicativeExternalPerZec:
        state == SwapReviewScreenCase.amountDrift
            ? {SwapAsset.usdc: 200.0}
            : _previewUsdcPerZec,
    reviewQuote: quote,
    reviewAddressPlan: addressPlan,
    reviewAccountUuid: _swapScreenAccountUuid,
    quoteExpired: state == SwapReviewScreenCase.expired,
    statusError:
        state == SwapReviewScreenCase.startError
            ? 'The provider could not lock this quote. Try again.'
            : null,
    startSubmitting: state == SwapReviewScreenCase.submitting,
    payMode: payMode,
  );
}

Widget _swapScreenScope({
  required Widget child,
  required SwapState swapState,
  required String location,
  BigInt? spendableZatoshi,
  bool hideAmounts = false,
  SwapNotifier Function()? swapNotifierBuilder,
}) {
  const migration = IronwoodHomeMigrationCtaState.hidden();
  final balance = spendableZatoshi ?? BigInt.from(1234560000);
  final syncState = SyncState(
    accountUuid: _swapScreenAccountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: 3428143,
    chainTipHeight: 3428143,
    orchardBalance: balance,
    spendableBalance: balance,
    totalBalance: balance,
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _swapScreenBootstrap(location: location, hideAmounts: hideAmounts),
      ),
      // `AppLayoutNotifier.setMode` reshapes the native window through
      // `window_manager`, which belongs to the app rather than a preview.
      appLayoutProvider.overrideWith(_SwapPreviewLayoutNotifier.new),
      accountProvider.overrideWith(
        () => _SwapPreviewAccountNotifier(_swapScreenAccountState),
      ),
      syncProvider.overrideWith(() => _SwapPreviewSyncNotifier(syncState)),
      addressBookRepositoryProvider.overrideWith(
        (ref) => WbAddressBookRepository(),
      ),
      addressBookProvider.overrideWith(
        () => _SwapPreviewAddressBookNotifier(_swapScreenContacts),
      ),
      swapStateProvider.overrideWith(
        swapNotifierBuilder ?? () => _SwapPreviewNotifier(swapState),
      ),
      paySelectedAssetStoreProvider.overrideWithValue(
        _SwapWidgetbookPaySelectedAssetStore(),
      ),
      swapComposerPreferencesStoreProvider.overrideWithValue(
        _SwapWidgetbookComposerPreferencesStore(),
      ),
      privacyModeProvider.overrideWith(_SwapPreviewPrivacyModeNotifier.new),
      networkPrivacyProvider.overrideWith(
        _SwapPreviewNetworkPrivacyNotifier.new,
      ),
      swapFeatureEnabledProvider.overrideWithValue(true),
      zecLiveUsdUnitPriceProvider.overrideWithValue(70),
      ironwoodHomeMigrationCtaProvider.overrideWith((ref) async => migration),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(migration),
      ironwoodMigrationAnnouncementProvider.overrideWith(
        (ref) async => const IronwoodMigrationAnnouncementState.hidden(),
      ),
    ],
    child: child,
  );
}

AppBootstrapState _swapScreenBootstrap({
  required String location,
  required bool hideAmounts,
}) {
  return AppBootstrapState(
    initialLocation: location,
    initialAccountState: _swapScreenAccountState,
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: hideAmounts,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

final _swapScreenAccountState = AccountState(
  accounts: const [
    AccountInfo(
      uuid: _swapScreenAccountUuid,
      name: 'Account Name',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: _swapScreenAccountUuid,
  activeAddress: 'u1widgetbookswapscreenaddress',
);

const _swapScreenContacts = AddressBookState(
  contacts: [
    AddressBookContact(
      id: 'widgetbook-swap-screen-bea',
      label: kSwapPreviewContactLabel,
      network: AddressBookNetwork.ethereum,
      address: kSwapPreviewContactAddress,
      profilePictureId: 'pfp-04',
      createdAtMs: 0,
      updatedAtMs: 0,
    ),
  ],
);

/// `AppMainSidebar` and `AppPaneToolbar` resolve their active item and back
/// label through `GoRouterState.of`, which needs a real matched route.
class _SwapScreenHarness extends StatefulWidget {
  const _SwapScreenHarness({
    required this.child,
    required this.windowSize,
    required this.location,
    this.mobile = false,
    this.interactive = false,
  });

  final Widget child;
  final Size windowSize;
  final String location;
  final bool mobile;
  final bool interactive;

  @override
  State<_SwapScreenHarness> createState() => _SwapScreenHarnessState();
}

class _SwapScreenHarnessState extends State<_SwapScreenHarness> {
  static const _exitRoutes = ['/home', '/activity', '/pay', '/settings'];

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.location,
      routes: [
        GoRoute(path: widget.location, builder: (_, _) => widget.child),
        if (widget.location != '/swap/review')
          GoRoute(
            path: '/swap/review',
            builder:
                (_, _) =>
                    widget.mobile
                        ? const MobileSwapReviewScreen()
                        : const SwapReviewScreen(),
          ),
        GoRoute(
          path: '/activity/swap/:swapId',
          builder:
              (_, state) =>
                  widget.mobile
                      ? MobileSwapActivityDetailScreen(
                        swapIntentId: state.pathParameters['swapId'] ?? '',
                        returnTarget: SwapActivityReturnTarget.swap,
                        launchExternalUri: (_) async {},
                      )
                      : SwapActivityDetailScreen(
                        swapIntentId: state.pathParameters['swapId'] ?? '',
                        returnTarget: SwapActivityReturnTarget.swap,
                        launchExternalUri: (_) async {},
                      ),
        ),
        for (final path in _exitRoutes)
          if (path != widget.location)
            GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobile) {
      final mediaQuery = MediaQuery.of(context);
      return Center(
        child: WbScaleDownBox(
          size: const Size(393, 852),
          child: SizedBox(
            width: 393,
            height: 852,
            child: ClipRect(
              child: MediaQuery(
                data: mediaQuery.copyWith(
                  size: const Size(393, 852),
                  padding: const EdgeInsets.only(top: 55, bottom: 24),
                  viewPadding: const EdgeInsets.only(top: 55, bottom: 24),
                ),
                child: Router.withConfig(config: _router),
              ),
            ),
          ),
        ),
      );
    }
    return Center(
      child: WbDesktopWindowBox(
        size: widget.windowSize,
        child: ColoredBox(
          color: context.colors.macosUtility.window,
          child:
              widget.interactive
                  ? Router.withConfig(config: _router)
                  : IgnorePointer(child: Router.withConfig(config: _router)),
        ),
      ),
    );
  }
}

/// Invokes the keyed triggers' own `onTap` callbacks one frame apart, which
/// is how a screen-hosted modal with no preview prop is reached.
class _SwapTapOnMount extends StatefulWidget {
  const _SwapTapOnMount({required this.keys, required this.child});

  final List<Key> keys;
  final Widget child;

  @override
  State<_SwapTapOnMount> createState() => _SwapTapOnMountState();
}

class _SwapTapOnMountState extends State<_SwapTapOnMount> {
  static const _maxAttemptsPerKey = 8;
  var _index = 0;
  var _attempts = 0;

  @override
  void initState() {
    super.initState();
    if (widget.keys.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tapNext());
  }

  void _tapNext() {
    if (!mounted || _index >= widget.keys.length) return;
    final onTap = _callbackFor(widget.keys[_index]);
    if (onTap == null) {
      if (++_attempts >= _maxAttemptsPerKey) return;
      // Nothing repainted, so the retry has to ask for the frame it waits on.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tapNext());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _index++;
    _attempts = 0;
    onTap();
    if (_index >= widget.keys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tapNext());
  }

  /// The trigger's own `onTap`, not a synthetic pointer: the harness wraps the
  /// screen in an `IgnorePointer`, and hit-testing from the root would be
  /// intercepted by the widgetbook chrome anyway.
  VoidCallback? _callbackFor(Key key) {
    Element? target;
    void findTarget(Element element) {
      if (target != null) return;
      if (element.widget.key == key) {
        target = element;
        return;
      }
      element.visitChildren(findTarget);
    }

    context.visitChildElements(findTarget);
    final found = target;
    if (found == null) return null;

    final self = found.widget;
    if (self is GestureDetector && self.onTap != null) return self.onTap;

    VoidCallback? onTap;
    void findDetector(Element element) {
      if (onTap != null) return;
      final child = element.widget;
      if (child is GestureDetector && child.onTap != null) {
        onTap = child.onTap;
        return;
      }
      element.visitChildren(findDetector);
    }

    found.visitChildren(findDetector);
    return onTap;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The real `SwapNotifier.build` loads supported assets over the network,
/// restores persisted composer state and starts two polling timers.
class _SwapPreviewNotifier extends SwapNotifier {
  _SwapPreviewNotifier(this.initialState);

  final SwapState initialState;

  @override
  SwapState build() => initialState;

  @override
  Future<void> useMaxZecAmount() async {}

  @override
  Future<void> showReview({bool preserveCurrentReview = false}) async {}

  @override
  Future<void> refreshSelectedIntentStatus() async {}
}

class _SwapWidgetbookPaySelectedAssetStore implements PaySelectedAssetStore {
  final Map<String, SwapAsset> _assets = {};

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async =>
      _assets[accountUuid];

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {
    _assets[accountUuid] = asset;
  }
}

class _SwapWidgetbookComposerPreferencesStore
    implements SwapComposerPreferencesStore {
  final Map<String, SwapComposerPreferences> _preferences = {};

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async => _preferences[accountUuid];

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {
    _preferences[accountUuid] = preferences;
  }
}

class _SwapInteractiveNotifier extends _SwapPreviewNotifier {
  _SwapInteractiveNotifier(super.initialState, this.scenario);

  final SwapScreenSimulationScenario scenario;
  var _quoteFailedOnce = false;

  @override
  void prepareSwapComposer() {
    // The fixture-state knob is the initial real composer state. Do not reset
    // it when SwapScreen performs its normal first-frame preparation.
  }

  @override
  Future<void> showReview({bool preserveCurrentReview = false}) async {
    if (!state.canReviewQuote) return;
    if (scenario == SwapScreenSimulationScenario.invalidInput) {
      state = state.copyWith(
        quoteError: 'Enter a valid address.',
        reviewVisible: false,
        clearReview: true,
      );
      return;
    }
    if (scenario == SwapScreenSimulationScenario.quoteFailure &&
        !_quoteFailedOnce) {
      _quoteFailedOnce = true;
      state = state.copyWith(
        quoteError: 'No quote is available. Try again.',
        reviewVisible: false,
        clearReview: true,
      );
      return;
    }
    final quote = SwapQuote.estimate(
      direction: state.direction,
      mode: state.quoteMode,
      externalAsset: state.externalAsset,
      amount: state.quoteAmount!,
      externalPerZec: state.indicativeExternalPerZec[state.externalAsset],
      slippageBps: state.slippageBps,
      expiryLabel:
          scenario == SwapScreenSimulationScenario.expiredQuote
              ? 'Quote expired'
              : '1:30',
    );
    state = state.copyWith(
      reviewVisible: true,
      reviewQuote: quote,
      reviewAddressPlan: state.draftAddressPlan,
      reviewAccountUuid: _swapScreenAccountUuid,
      quoteExpired: scenario == SwapScreenSimulationScenario.expiredQuote,
      clearQuoteError: true,
    );
  }

  @override
  Future<SwapStartResult?> startIntent() async {
    final quote = state.reviewQuote;
    if (quote == null ||
        state.reviewAddressPlan == null ||
        state.quoteExpired) {
      return null;
    }
    const id = 'widgetbook-swap-simulated';
    final intent = SwapIntent(
      id: id,
      pair: quote.pairText,
      sellAmount: quote.sellAmountText,
      receiveEstimate: quote.receiveEstimateText,
      provider: 'Simulated Widgetbook',
      status: SwapIntentStatus.complete,
      nextAction: 'Complete',
      direction: quote.direction,
      externalAsset: quote.externalAsset,
      oneClickRecipient: state.destinationText,
      accountUuid: _swapScreenAccountUuid,
      depositTxHash: 'simulated-swap-tx',
      createdAt: DateTime.utc(2026, 9, 14),
      completedAt: DateTime.utc(2026, 9, 14),
    );
    state = state.copyWith(
      intents: [intent],
      selectedIntentId: id,
      startSubmitting: false,
    );
    return const SwapStartedActivity(id);
  }
}

class _SwapPreviewAccountNotifier extends AccountNotifier {
  _SwapPreviewAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;
}

class _SwapPreviewSyncNotifier extends SyncNotifier {
  _SwapPreviewSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}

class _SwapPreviewAddressBookNotifier extends AddressBookNotifier {
  _SwapPreviewAddressBookNotifier(this.initialState);

  final AddressBookState initialState;

  @override
  Future<AddressBookState> build() async => initialState;
}

class _SwapPreviewPrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _SwapPreviewLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {}
}

class _SwapPreviewNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();

  @override
  Future<void> setTorEnabled(bool enabled) async {}
}

// --- Deposit page states ---------------------------------------------------

/// What the deposit page is telling the user while it waits for the transfer.
///
/// The three pinned Figma states keep their own fixtures; these are the
/// states the activity detail drives through the same content widget.
enum SwapDepositWaitCase { checking, checkFailed, elapsed }

/// How the deposit page prints its deadline: the static duration label, or the
/// live countdown the last fifteen minutes switch to.
enum SwapDepositExpiryCase { staticLabel, countdown }

/// Fixed clock for the countdown states: `DateTime.now()` would make the
/// rendered minutes differ between runs.
final _swapDepositDeadline = DateTime.utc(2026, 5, 20, 13, 20);

/// The deposit page in either form factor. [state] is null while nothing is
/// being waited on, which is the plain Figma frame.
Widget swapDepositTokensFixture({
  SwapDepositWaitCase? state,
  SwapDepositExpiryCase expiry = SwapDepositExpiryCase.countdown,
  String? memo,
  bool mobile = false,
}) {
  final elapsed = state == SwapDepositWaitCase.elapsed;
  final countdown = elapsed || expiry == SwapDepositExpiryCase.countdown;
  final content = SwapDepositTokensPageContent(
    asset: SwapAsset.usdc,
    amountText: '999.99 USDC',
    depositAddress: '0x123kjhc4e984ac1832f10aa4x98g20',
    expiresInLabel: countdown ? '14:59' : '2hrs',
    expiresAt: countdown ? _swapDepositDeadline : null,
    now:
        () =>
            elapsed
                ? _swapDepositDeadline.add(const Duration(minutes: 1))
                : _swapDepositDeadline.subtract(const Duration(minutes: 9)),
    memo: memo,
    checking: state == SwapDepositWaitCase.checking,
    checkWarning:
        state == SwapDepositWaitCase.checkFailed
            ? "Couldn't check the deposit. Retrying."
            : null,
    onDeposited: () {},
    mobile: mobile,
  );
  return mobile
      ? _SwapMobileDepositFrame(child: content)
      : _SwapFlowPageFrame(backLabel: 'Review', child: content);
}

/// The hardware ZEC deposit page in either form factor, with or without the
/// memo row the staging address adds.
Widget swapHardwareZecDepositFixture({
  bool mobile = false,
  bool memo = false,
  SwapDepositExpiryCase expiry = SwapDepositExpiryCase.staticLabel,
}) {
  final countdown = expiry == SwapDepositExpiryCase.countdown;
  final content = SwapHardwareZecDepositPageContent(
    asset: SwapAsset.zec,
    amountText: '0.251 ZEC',
    depositAddress: 't1figmareviewdepositaddress',
    expiresInLabel: countdown ? '14:59' : '2hrs',
    expiresAt: countdown ? _swapDepositDeadline : null,
    now: () => _swapDepositDeadline.subtract(const Duration(minutes: 9)),
    memo: memo ? 'swap-staging-memo' : null,
    onDepositZec: () {},
    mobile: mobile,
  );
  return mobile
      ? _SwapMobileDepositFrame(child: content)
      : _SwapFlowPageFrame(backLabel: 'Review', child: content);
}

/// Phone box the mobile deposit frames render in; the mobile content is a
/// full-width card, so it needs the phone width rather than the desktop pane.
class _SwapMobileDepositFrame extends StatelessWidget {
  const _SwapMobileDepositFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WbFrame(
      layout: WbLayout.mobile,
      child: ColoredBox(
        color: context.colors.background.base,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: child,
        ),
      ),
    );
  }
}
