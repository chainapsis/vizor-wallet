// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:typed_data';
import 'support/wb_address_book_repository.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/swap/models/swap_activity_navigation.dart';
import '../src/features/swap/models/swap_activity_status_mapper.dart';
import '../src/features/swap/models/swap_models.dart';
import '../src/features/swap/providers/swap_hardware_signing_service.dart';
import '../src/features/swap/providers/swap_state_provider.dart';
import '../src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import '../src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import '../src/features/swap/screens/mobile/mobile_swap_screen.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_composer_ticket.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_review_content.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_status_content.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_timeout_content.dart';
import '../src/features/swap/widgets/swap_activity_panel.dart';
import '../src/features/swap/widgets/swap_asset_icon.dart';
import '../src/features/swap/widgets/swap_keystone_signing_overlay.dart';
import '../src/features/swap/widgets/swap_modal_controls.dart';
import '../src/features/swap/widgets/swap_near_intents_attribution.dart';
import '../src/features/swap/widgets/swap_review_info.dart';
import '../src/features/swap/widgets/swap_status_page_content.dart';
import '../src/providers/account_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import '../src/services/qr_scanner.dart';

// --- Shared fixture data ---------------------------------------------------

const _swapMobileAccountUuid = 'widgetbook-swap-account';
const _swapMobileWalletZecAddress = 'u1widgetbookswapwalletzecaddress';

/// Lowercase 0x hex, so the EVM format check passes without EIP-55 casing.
const _swapMobilePlainAddress = '0x1111111111111111111111111111111111111111';
const _swapMobileContactAddress = '0x52908400098527886e0f7030069857d2e4169ee7';
const _swapMobileMalformedAddress = '0xnot-an-address';

/// 128 ZEC — the same headroom the desktop composer fixtures use.
final _swapMobileSpendableZatoshi = BigInt.from(12800000000);

/// 0.1 ZEC: below every review quote, so the 'not enough ZEC' gate fires.
final _swapMobileDepletedZatoshi = BigInt.from(10000000);

const _swapMobileAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: _swapMobileAccountUuid,
      name: 'John',
      order: 0,
      profilePictureId: 'pfp-01',
    ),
  ],
  activeAccountUuid: _swapMobileAccountUuid,
  activeAddress: _swapMobileWalletZecAddress,
);

const _swapMobileContacts = <AddressBookContact>[
  AddressBookContact(
    id: 'widgetbook-swap-mike',
    label: 'Mike',
    network: AddressBookNetwork.ethereum,
    address: _swapMobileContactAddress,
    profilePictureId: 'pfp-02',
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
];

final _swapMobileUsdPrices = <SwapAsset, double>{
  SwapAsset.zec: 70.17,
  SwapAsset.usdc: 1,
};

final _swapMobileUsdcPerZec = <SwapAsset, double>{SwapAsset.usdc: 70.17};

// --- Mobile swap screen ----------------------------------------------------

/// The review button's label ladder, which is the composer's primary state.
enum SwapMobileCta {
  addRecipientAddress,
  addRefundAddress,
  addressFormatError,
  notEnoughZec,
  gettingQuote,
  continueToReview,
}

/// The error line under the CTA row: the three sources the screen collapses
/// into one message, in the order it reads them.
enum SwapMobileQuoteError {
  none,
  amountPrecision,
  unsupportedAsset,
  noQuoteAvailable,
}

/// Base composer state; every CTA case is a copy of it.
final _swapMobileComposerState = SwapState(
  direction: SwapDirection.zecToExternal,
  amountText: '0.25',
  receiveAmountText: '17.54',
  destinationText: '',
  externalAsset: SwapAsset.usdc,
  reviewVisible: false,
  intents: const [],
  slippageBps: 50,
  indicativeExternalPerZec: _swapMobileUsdcPerZec,
  indicativeUsdPrices: _swapMobileUsdPrices,
);

SwapState _swapMobileCtaState(SwapMobileCta cta) {
  return switch (cta) {
    SwapMobileCta.addRecipientAddress => _swapMobileComposerState,
    SwapMobileCta.addRefundAddress => _swapMobileComposerState.copyWith(
      direction: SwapDirection.externalToZec,
      amountText: '100',
      receiveAmountText: '1.42',
    ),
    SwapMobileCta.addressFormatError => _swapMobileComposerState.copyWith(
      destinationText: _swapMobileMalformedAddress,
    ),
    SwapMobileCta.notEnoughZec => _swapMobileComposerState.copyWith(
      amountText: '999',
      receiveAmountText: '70099.99',
      destinationText: _swapMobilePlainAddress,
    ),
    SwapMobileCta.gettingQuote => _swapMobileComposerState.copyWith(
      destinationText: _swapMobilePlainAddress,
      quoteLoading: true,
    ),
    SwapMobileCta.continueToReview => _swapMobileComposerState.copyWith(
      destinationText: _swapMobilePlainAddress,
    ),
  };
}

SwapState _swapMobileWithQuoteError(
  SwapState state,
  SwapMobileQuoteError error,
) {
  return switch (error) {
    SwapMobileQuoteError.none => state,
    // The precision error is derived from the entered amount, so this option
    // also replaces it (nine decimals exceeds both ZEC's 8 and USDC's 6).
    SwapMobileQuoteError.amountPrecision => state.copyWith(
      amountText: '0.123456789',
    ),
    SwapMobileQuoteError.unsupportedAsset => state.copyWith(
      supportedExternalAssets: const [SwapAsset.eth],
    ),
    SwapMobileQuoteError.noQuoteAvailable => state.copyWith(
      quoteError:
          'No quote is available for this route or amount.\n'
          'Adjust the amount, slippage, or asset and try again.',
    ),
  };
}

/// The mobile swap composer screen on a pinned [SwapState].
///
/// [keyboardOpen] feeds the bottom `viewInsets` the screen reads to swap its
/// leading back chevron for the keyboard-dismissing close button.
Widget swapMobileScreenFixture({
  required SwapMobileCta cta,
  SwapMobileQuoteError quoteError = SwapMobileQuoteError.none,
  bool keyboardOpen = false,
}) {
  final state = _swapMobileWithQuoteError(_swapMobileCtaState(cta), quoteError);
  return _swapMobileScope(
    state: state,
    spendableZatoshi: _swapMobileSpendableZatoshi,
    child: _SwapMobileRouterHarness(
      location: '/swap',
      screen: _swapMobileKeyboardInsets(
        open: keyboardOpen,
        child: const MobileSwapScreen(),
      ),
    ),
  );
}

// --- Mobile swap composer ticket -------------------------------------------

enum SwapMobileTicketDirection { zecToUsdc, usdcToZec }

/// Which card drives the quote; the ticket reads it from the quote mode while
/// neither amount field holds focus.
enum SwapMobileTicketSide { pay, receive }

enum SwapMobileTicketAmountMode { token, fiat }

/// The max trigger's two rendered states; `maxAmountLoading` only disables the
/// tap, so it has no preview of its own.
enum SwapMobileTicketMax { balance, error }

enum SwapMobileTicketDestination { empty, address, contact }

/// The composer ticket on its own, driven entirely by props.
Widget swapMobileComposerTicketFixture({
  SwapMobileTicketDirection direction = SwapMobileTicketDirection.zecToUsdc,
  SwapMobileTicketSide side = SwapMobileTicketSide.pay,
  SwapMobileTicketAmountMode amountMode = SwapMobileTicketAmountMode.token,
  SwapMobileTicketMax max = SwapMobileTicketMax.balance,
  SwapMobileTicketDestination destination = SwapMobileTicketDestination.empty,
}) {
  final fiat = amountMode == SwapMobileTicketAmountMode.fiat;
  final state = _swapMobileComposerState.copyWith(
    direction: direction == SwapMobileTicketDirection.zecToUsdc
        ? SwapDirection.zecToExternal
        : SwapDirection.externalToZec,
    amountText: direction == SwapMobileTicketDirection.zecToUsdc
        ? '0.25'
        : '100',
    receiveAmountText: direction == SwapMobileTicketDirection.zecToUsdc
        ? '17.54'
        : '1.42',
    amountFiatText: '17.54',
    receiveFiatText: '17.54',
    amountInputMode: fiat
        ? SwapAmountInputMode.fiat
        : SwapAmountInputMode.token,
    receiveAmountInputMode: fiat
        ? SwapAmountInputMode.fiat
        : SwapAmountInputMode.token,
    quoteMode: side == SwapMobileTicketSide.pay
        ? SwapQuoteMode.exactInput
        : SwapQuoteMode.exactOutput,
    destinationText: switch (destination) {
      SwapMobileTicketDestination.empty => '',
      SwapMobileTicketDestination.address => _swapMobilePlainAddress,
      SwapMobileTicketDestination.contact => _swapMobileContactAddress,
    },
    maxAmountError: max == SwapMobileTicketMax.error
        ? 'Max amount unavailable'
        : null,
  );
  return _SwapMobilePad(
    child: MobileSwapComposerTicket(
      state: state,
      onAmountChanged: _swapMobileIgnoreText,
      onAmountFiatChanged: _swapMobileIgnoreText,
      onReceiveAmountChanged: _swapMobileIgnoreText,
      onReceiveAmountFiatChanged: _swapMobileIgnoreText,
      onToggleFiatInputMode: (_) {},
      onToggleDirection: _swapMobileNoop,
      onOpenExternalAssetPicker: _swapMobileNoop,
      onOpenDestinationAddress: _swapMobileNoop,
      onUseMaxZecAmount: _swapMobileNoop,
      zecAvailableText: '128 ZEC',
      destinationContactName: destination == SwapMobileTicketDestination.contact
          ? 'Mike'
          : null,
    ),
  );
}

// --- Mobile swap review ----------------------------------------------------

enum SwapMobileReviewMode { swap, payment }

enum SwapMobileReviewQuoteCase { live, expired }

enum SwapMobileReviewBlocked { none, notEnoughZec }

final _swapMobileZecToUsdcPlan = SwapAddressPlan.fromUserInput(
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  userExternalAddress: _swapMobileContactAddress,
  walletZecAddress: _swapMobileWalletZecAddress,
);

/// `quoteExpiresAt` / deposit `deadline` stay null on purpose: the review
/// screen's countdown ticker reads `DateTime.now()`, and expiry is previewed
/// through `quoteExpired` instead.
final _swapMobileZecToUsdcQuote = SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  sellAmount: 1.12,
  receiveAmount: 78.59,
  minimumReceiveAmount: 78.2,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '2hrs',
  depositInstruction: const SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: _swapMobileWalletZecAddress,
    expiresInLabel: '2hrs',
    reuseWarning: 'Do not reuse this address',
  ),
);

final _swapMobileUsdcToZecQuote = SwapQuote(
  direction: SwapDirection.externalToZec,
  sellAsset: SwapAsset.usdc,
  receiveAsset: SwapAsset.zec,
  externalAsset: SwapAsset.usdc,
  sellAmount: 110.24,
  receiveAmount: 1.57,
  minimumReceiveAmount: 1.55,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '2hrs',
  depositInstruction: const SwapDepositInstruction(
    asset: SwapAsset.usdc,
    address: _swapMobilePlainAddress,
    expiresInLabel: '2hrs',
    reuseWarning: 'Do not reuse this address',
  ),
);

SwapState _swapMobileReviewState({
  required bool payMode,
  required bool expired,
}) {
  return _swapMobileComposerState.copyWith(
    amountText: '1.12',
    receiveAmountText: '78.59',
    destinationText: _swapMobileContactAddress,
    reviewVisible: true,
    reviewQuote: _swapMobileZecToUsdcQuote,
    reviewAddressPlan: _swapMobileZecToUsdcPlan,
    reviewAccountUuid: _swapMobileAccountUuid,
    quoteExpired: expired,
    payMode: payMode,
  );
}

/// The mobile review screen in either mode, on a pinned review snapshot.
Widget swapMobileReviewScreenFixture({
  SwapMobileReviewMode mode = SwapMobileReviewMode.swap,
  SwapMobileReviewQuoteCase quote = SwapMobileReviewQuoteCase.live,
  SwapMobileReviewBlocked blocked = SwapMobileReviewBlocked.none,
}) {
  final payMode = mode == SwapMobileReviewMode.payment;
  return _swapMobileScope(
    state: _swapMobileReviewState(
      payMode: payMode,
      expired: quote == SwapMobileReviewQuoteCase.expired,
    ),
    spendableZatoshi: blocked == SwapMobileReviewBlocked.notEnoughZec
        ? _swapMobileDepletedZatoshi
        : _swapMobileSpendableZatoshi,
    child: _SwapMobileRouterHarness(
      location: payMode ? '/pay/review' : '/swap/review',
      screen: MobileSwapReviewScreen(payMode: payMode),
    ),
  );
}

// --- Mobile swap review content --------------------------------------------

enum SwapMobileReviewDirection { zecToUsdc, usdcToZec }

/// The notice lines under the details card, in the order the content renders
/// them. One at a time: each is a separate product situation.
enum SwapMobileReviewNotice {
  none,
  amountDrift,
  expired,
  startError,
  notEnoughZec,
  noLongerActive,
}

enum SwapMobileReviewAddressLabel { plain, contact }

Widget swapMobileReviewContentFixture({
  SwapMobileReviewDirection direction = SwapMobileReviewDirection.zecToUsdc,
  SwapMobileReviewNotice notice = SwapMobileReviewNotice.none,
  SwapMobileReviewAddressLabel addressLabel =
      SwapMobileReviewAddressLabel.plain,
}) {
  final sendsZec = direction == SwapMobileReviewDirection.zecToUsdc;
  final contactLabelled = addressLabel == SwapMobileReviewAddressLabel.contact;
  final quote = sendsZec
      ? _swapMobileZecToUsdcQuote
      : _swapMobileUsdcToZecQuote;
  final plan = SwapAddressPlan.fromUserInput(
    direction: sendsZec
        ? SwapDirection.zecToExternal
        : SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    userExternalAddress: contactLabelled
        ? _swapMobileContactAddress
        : _swapMobilePlainAddress,
    walletZecAddress: _swapMobileWalletZecAddress,
  );
  return _SwapMobilePad(
    child: MobileSwapReviewContent(
      quote: quote,
      addressPlan: plan,
      addressBookContacts: contactLabelled
          ? _swapMobileContacts
          : const <AddressBookContact>[],
      accountLabel: 'John',
      accountProfilePictureId: 'pfp-01',
      expired: notice == SwapMobileReviewNotice.expired,
      amountWarning: notice == SwapMobileReviewNotice.amountDrift
          ? 'Live quote is 7% lower than the earlier estimate. Check the '
                'guaranteed minimum before you continue.'
          : null,
      startError: notice == SwapMobileReviewNotice.startError
          ? 'Swap could not be started.\nTry again in a moment.'
          : null,
      startBlockedReason: notice == SwapMobileReviewNotice.notEnoughZec
          ? "You don't have enough ZEC for this swap. Try a smaller amount."
          : null,
      inactiveMessage: notice == SwapMobileReviewNotice.noLongerActive
          ? 'This quote is no longer active.'
          : null,
      payFiatTextOverride: r'$78.59',
      receiveFiatTextOverride: r'$78.59',
    ),
  );
}

// --- Mobile swap review actions --------------------------------------------

/// The primary button's state; the starting label itself depends on the
/// direction, so [SwapMobileActionsDirection] carries that axis.
enum SwapMobileReviewAction {
  confirm,
  reviewAgain,
  notEnoughZec,
  starting,
  noLongerActive,
}

enum SwapMobileActionsDirection { sendsZec, receivesZec }

Widget swapMobileReviewActionsFixture({
  SwapMobileReviewAction action = SwapMobileReviewAction.confirm,
  SwapMobileActionsDirection direction = SwapMobileActionsDirection.sendsZec,
}) {
  return _SwapMobilePad(
    child: MobileSwapReviewActions(
      expired: action == SwapMobileReviewAction.reviewAgain,
      starting: action == SwapMobileReviewAction.starting,
      inactive: action == SwapMobileReviewAction.noLongerActive,
      startBlockedReason: action == SwapMobileReviewAction.notEnoughZec
          ? "You don't have enough ZEC for this swap. Try a smaller amount."
          : null,
      sendsZec: direction == SwapMobileActionsDirection.sendsZec,
      onCancelReview: _swapMobileNoop,
      onReviewAgain: _swapMobileNoop,
      onStartIntent: _swapMobileNoop,
    ),
  );
}

// --- Mobile swap review header row -----------------------------------------

enum SwapMobileHeaderBottomLine { fiat, toAddress, none }

enum SwapMobileHeaderAsset { zec, usdc }

/// The paying/receiving header pair. The knobs drive the receiving row; the
/// paying row stays a plain ZEC row so the axes read against a fixed baseline.
Widget swapMobileReviewHeaderFixture({
  SwapMobileHeaderBottomLine bottomLine = SwapMobileHeaderBottomLine.fiat,
  bool fullAddressAction = false,
  SwapMobileHeaderAsset asset = SwapMobileHeaderAsset.usdc,
}) {
  return _SwapMobilePad(
    child: MobileSwapReviewHeader(
      pay: const MobileSwapReviewHeaderRow(
        label: "You're paying",
        amountText: '1.12 ZEC',
        asset: SwapAsset.zec,
        bottomText: r'$78.59',
      ),
      receive: MobileSwapReviewHeaderRow(
        label: "You're receiving",
        amountText: asset == SwapMobileHeaderAsset.zec
            ? '1.57 ZEC'
            : '78.59 USDC',
        asset: asset == SwapMobileHeaderAsset.zec
            ? SwapAsset.zec
            : SwapAsset.usdc,
        bottomText: switch (bottomLine) {
          SwapMobileHeaderBottomLine.fiat => r'$78.59',
          SwapMobileHeaderBottomLine.toAddress => 'To: 0x5290 ... 69ee7',
          SwapMobileHeaderBottomLine.none => null,
        },
        fullAddress: fullAddressAction ? _swapMobileContactAddress : null,
      ),
    ),
  );
}

// --- Mobile swap status ----------------------------------------------------

enum SwapMobileStatusMode { swap, payment }

/// The intent status the mapper reads; it decides the badge kind, the step
/// the timeline sits on, and whether the tabs show at all.
enum SwapMobileStatusCase { inProgress, incompleteDeposit, completed, failed }

enum SwapMobileStatusTab { progress, details }

enum SwapMobileStatusRecipient { contact, address }

/// Whether the deposit transaction is on record: it advances the progress
/// step and adds the copyable, explorer-linked tx row to the details.
enum SwapMobileStatusDepositTx { pending, recorded }

/// Fixed points in time — the details rows date the swap, and a `now()` here
/// would make the preview drift.
final _swapMobileStatusCreatedAt = DateTime.utc(2026, 5, 14, 9, 41);
final _swapMobileStatusCompletedAt = DateTime.utc(2026, 5, 14, 9, 58);

const _swapMobileStatusDepositAddress = 'u1widgetbookswapdepositaddress';
const _swapMobileStatusDepositTxHash =
    '9f2c4a1b7e5d3c8a6f0b2d4e6a8c0e2f4a6b8d0c2e4f6a8b0d2c4e6f8a0b2d4e';

SwapIntent _swapMobileStatusIntent({
  required SwapMobileStatusMode mode,
  required SwapMobileStatusCase status,
  required SwapMobileStatusRecipient recipient,
  required SwapMobileStatusDepositTx depositTx,
}) {
  final knownContact = recipient == SwapMobileStatusRecipient.contact;
  final recorded = depositTx == SwapMobileStatusDepositTx.recorded;
  final completed = status == SwapMobileStatusCase.completed;
  return SwapIntent(
    id: 'widgetbook-swap-status',
    pair: 'ZEC -> USDC',
    sellAmount: '1.12 ZEC',
    receiveEstimate: '78.59 USDC',
    provider: 'NEAR Intents',
    status: switch (status) {
      SwapMobileStatusCase.inProgress => SwapIntentStatus.awaitingDeposit,
      SwapMobileStatusCase.incompleteDeposit =>
        SwapIntentStatus.incompleteDeposit,
      SwapMobileStatusCase.completed => SwapIntentStatus.complete,
      SwapMobileStatusCase.failed => SwapIntentStatus.failed,
    },
    nextAction: 'Waiting for the provider',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    accountUuid: _swapMobileAccountUuid,
    depositAddress: _swapMobileStatusDepositAddress,
    depositTxHash: recorded ? _swapMobileStatusDepositTxHash : null,
    nearIntentHash: recorded ? 'widgetbook-near-intent-hash' : null,
    totalFeesText: '0.0012 ZEC',
    realisedSlippageText: '0.12%',
    oneClickRecipient: knownContact
        ? _swapMobileContactAddress
        : _swapMobilePlainAddress,
    oneClickRefundTo: _swapMobileWalletZecAddress,
    userExternalContactId: knownContact ? 'widgetbook-swap-mike' : null,
    createdAt: _swapMobileStatusCreatedAt,
    completedAt: completed ? _swapMobileStatusCompletedAt : null,
    payMode: mode == SwapMobileStatusMode.payment,
  );
}

/// The mobile status panel, driven by the production status mapper so the
/// badge, the steps and every detail row are the real routing.
Widget swapMobileStatusFixture({
  SwapMobileStatusMode mode = SwapMobileStatusMode.swap,
  SwapMobileStatusCase status = SwapMobileStatusCase.inProgress,
  SwapMobileStatusTab tab = SwapMobileStatusTab.progress,
  SwapMobileStatusRecipient recipient = SwapMobileStatusRecipient.contact,
  SwapMobileStatusDepositTx depositTx = SwapMobileStatusDepositTx.pending,
  SwapExternalUriLauncher launchExternalUri = _swapMobileExternalUriNoop,
}) {
  final knownContact = recipient == SwapMobileStatusRecipient.contact;
  final intent = _swapMobileStatusIntent(
    mode: mode,
    status: status,
    recipient: recipient,
    depositTx: depositTx,
  );
  final contacts = knownContact
      ? _swapMobileContacts
      : const <AddressBookContact>[];
  final presentation = swapActivityStatusPresentationForIntent(
    _swapMobileComposerState,
    intent,
    addressBookContacts: contacts,
  );
  final recipientAddress = intent.oneClickRecipient!;
  final terminal = status != SwapMobileStatusCase.inProgress;
  final paymentMode = presentation.paymentMode;
  final payStatus = presentation.payStatus;
  return _SwapMobilePad(
    child: SingleChildScrollView(
      child: MobileSwapStatusContent(
        presentation: presentation,
        paymentHeader: paymentMode && payStatus != null
            ? MobilePayStatusHeader(
                asset: presentation.receiveAsset,
                amountText: trimSwapAmountText(presentation.receiveAmountText),
                fiatText: presentation.receiveFiatText,
                label: payStatus.phase == PayActivityStatusPhase.completed
                    ? 'You paid'
                    : "You're paying",
                recipientAddress: recipientAddress,
                recipientName: knownContact ? 'Mike' : null,
                recipientProfilePictureId: knownContact ? 'pfp-02' : null,
              )
            : null,
        payHeaderRow: MobileSwapReviewHeaderRow(
          label: !paymentMode && terminal ? 'You paid' : presentation.payLabel,
          amountText: trimSwapAmountText(presentation.payAmountText),
          asset: presentation.payAsset,
          bottomText: presentation.payDetailText,
        ),
        receiveHeaderRow: MobileSwapReviewHeaderRow(
          label: !paymentMode && terminal
              ? 'You received'
              : presentation.receiveLabel,
          amountText: trimSwapAmountText(presentation.receiveAmountText),
          asset: presentation.receiveAsset,
          // The mapper already resolved the recipient line (contact name when
          // one matches, compacted address otherwise).
          bottomText: presentation.receiveDetailText,
          fullAddress: recipientAddress,
        ),
        activeTab: tab == SwapMobileStatusTab.progress
            ? SwapStatusTab.progress
            : SwapStatusTab.details,
        detailsExpanded: false,
        onTabChanged: (_) {},
        onToggleDetails: _swapMobileNoop,
        launchExternalUri: launchExternalUri,
      ),
    ),
  );
}

Future<void> _swapMobileExternalUriNoop(Uri _) async {}

// --- Mobile swap deposit timeout -------------------------------------------

/// The mobile sibling of the desktop deposit-timeout page content.
Widget swapMobileTimeoutFixture() {
  return _SwapMobilePad(
    child: MobileSwapTimeoutContent(onRestart: _swapMobileNoop),
  );
}

// --- Mobile swap Keystone sign ---------------------------------------------

/// Where the signing session opens. The scanner step and the broadcast wait
/// are reached by tapping through (Next step, then the fake camera), so they
/// are interactions rather than knob options.
enum SwapMobileKeystonePhase { preparing, qrCode }

/// The failure the fake signing service raises. The panel copy is whatever
/// the screen's own `_friendlyError` maps that error text to.
enum SwapMobileKeystoneError {
  none,
  texUnsupported,
  saplingParams,
  proposalExpired,
  signatureNotApplied,
  broadcastFailed,
  generic,
}

Object? _swapMobileKeystoneErrorFor(SwapMobileKeystoneError error) {
  return switch (error) {
    SwapMobileKeystoneError.none => null,
    SwapMobileKeystoneError.texUnsupported => UnsupportedError(
      'Keystone does not support TEX sends yet.',
    ),
    SwapMobileKeystoneError.saplingParams => StateError(
      'Sapling parameters could not be downloaded.',
    ),
    SwapMobileKeystoneError.proposalExpired => StateError(
      'Proposal not found (expired or already consumed)',
    ),
    SwapMobileKeystoneError.signatureNotApplied => StateError(
      'PCZT signature could not be applied to the transaction.',
    ),
    SwapMobileKeystoneError.broadcastFailed => StateError(
      'SendTransaction failed: the broadcast was rejected.',
    ),
    SwapMobileKeystoneError.generic => StateError('Unexpected signing fault.'),
  };
}

const _swapMobileKeystoneIntent = SwapIntent(
  id: 'widgetbook-swap-keystone',
  pair: 'ZEC -> USDC',
  sellAmount: '1.12 ZEC',
  receiveEstimate: '78.59 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Sign the deposit on Keystone',
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  accountUuid: _swapMobileAccountUuid,
  depositAddress: _swapMobileStatusDepositAddress,
);

/// The mobile Keystone deposit-signing screen on a fake signing service.
Widget swapMobileKeystoneSignFixture({
  SwapMobileKeystonePhase phase = SwapMobileKeystonePhase.qrCode,
  SwapMobileKeystoneError error = SwapMobileKeystoneError.none,
}) {
  final failure = _swapMobileKeystoneErrorFor(error);
  return _swapMobileScope(
    state: _swapMobileComposerState,
    spendableZatoshi: _swapMobileSpendableZatoshi,
    overrides: [
      swapHardwareSigningServiceProvider.overrideWithValue(
        _SwapMobileKeystoneSigningService(
          hangOnCreate:
              failure == null && phase == SwapMobileKeystonePhase.preparing,
          createError: failure,
        ),
      ),
    ],
    child: _SwapMobileRouterHarness(
      location: '/swap/keystone-sign',
      screen: MobileSwapKeystoneSignScreen(
        args: const MobileSwapKeystoneSignArgs(
          intent: _swapMobileKeystoneIntent,
        ),
        scannerBuilder: _swapMobileKeystoneScannerPreview,
        signedPcztDecoder: (_) async => Uint8List.fromList(const [7, 7, 7]),
        forceScannerActiveForTesting: true,
      ),
    ),
  );
}

// --- Fixture plumbing ------------------------------------------------------

void _swapMobileNoop() {}

void _swapMobileIgnoreText(String _) {}

/// Provider scope shared by the two mobile swap screens.
///
/// The spendable override is mandatory: unoverridden it watches `syncProvider`
/// and pulls the real Rust sync into the preview.
Widget _swapMobileScope({
  required SwapState state,
  required BigInt spendableZatoshi,
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      swapStateProvider.overrideWith(() => _SwapMobilePreviewNotifier(state)),
      accountProvider.overrideWith(_SwapMobileAccountNotifier.new),
      addressBookProvider.overrideWith(_SwapMobileAddressBookNotifier.new),
      addressBookRepositoryProvider.overrideWith(
        (ref) => WbAddressBookRepository(),
      ),
      ironwoodMigrationAwareDisplaySpendableProvider.overrideWith(
        (ref, accountUuid) => spendableZatoshi,
      ),
      ...overrides,
    ],
    child: child,
  );
}

/// Dev-only stand-in for the Rust signing service: no proposal, no proving
/// params, no broadcast. The broadcast future never completes, which is what
/// parks the flow on "Broadcasting ZEC deposit...".
class _SwapMobileKeystoneSigningService implements SwapHardwareSigningService {
  _SwapMobileKeystoneSigningService({
    this.hangOnCreate = false,
    this.createError,
  });

  final bool hangOnCreate;
  final Object? createError;

  static final _draft = SwapHardwarePcztDraft(
    accountUuid: _swapMobileAccountUuid,
    pcztBytes: const [1, 2, 3],
    // False keeps `loadSaplingParamsStatus()` (a real file read) off the path.
    needsSaplingParams: false,
    feeZatoshi: BigInt.from(15000),
    proposalId: BigInt.one,
    sendFlowId: 'widgetbook-swap-keystone-flow',
  );

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) {
    final error = createError;
    if (error != null) return Future.error(error);
    if (hangOnCreate) return Completer<SwapHardwarePcztDraft>().future;
    return Future.value(_draft);
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async => const [
    'ur:zcash-sign-batch/1-1/widgetbookswapkeystonedepositsigningrequest',
  ];

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => const [4, 5, 6];

  @override
  Future<List<int>> decodeSigningResponse({
    required SwapHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async => const [7, 7, 7];

  @override
  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft}) async {}

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => Completer<rust_sync.ExtractAndBroadcastPcztResult>().future;
}

Widget _swapMobileKeystoneScannerPreview(
  BuildContext context,
  ValueChanged<ScanResult> onComplete,
  ValueChanged<int> onProgress,
  Object? scanSessionResetToken,
) {
  return _SwapMobileKeystoneCameraPreview(
    onProgress: onProgress,
    onComplete: onComplete,
  );
}

/// Stand-in camera: reports a half-read animated QR, and completes the read
/// on tap so the broadcast wait is reachable without a device.
class _SwapMobileKeystoneCameraPreview extends StatefulWidget {
  const _SwapMobileKeystoneCameraPreview({
    required this.onProgress,
    required this.onComplete,
  });

  final ValueChanged<int> onProgress;
  final ValueChanged<ScanResult> onComplete;

  @override
  State<_SwapMobileKeystoneCameraPreview> createState() =>
      _SwapMobileKeystoneCameraPreviewState();
}

class _SwapMobileKeystoneCameraPreviewState
    extends State<_SwapMobileKeystoneCameraPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onProgress(50);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('swap_mobile_keystone_camera_preview'),
      onTap: () => widget.onComplete(
        const ScanResult(urType: 'zcash-batch-sig-result', data: [1, 2, 3]),
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF060707), Color(0xFF141313), Color(0xFF080808)],
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}

/// Pins the composer/review state and neutralises every action the previewed
/// screens wire up — the real ones fetch quotes, hit the provider and persist.
/// `selectIntent` / `updateDepositTxHash` stay live: they only move state, and
/// the activity surface needs `selectIntent` to pick its intent at all.
class _SwapMobilePreviewNotifier extends SwapNotifier {
  _SwapMobilePreviewNotifier(this._state);

  final SwapState _state;

  @override
  SwapState build() => _state;

  @override
  void prepareSwapComposer() {}

  @override
  void toggleDirection() {}

  @override
  void updateAmount(String value) {}

  @override
  void updateAmountFiat(String value) {}

  @override
  void updateReceiveAmount(String value) {}

  @override
  void updateReceiveAmountFiat(String value) {}

  @override
  void toggleFiatInputMode(SwapAmountInputSide side) {}

  @override
  void updateDestination(String value) {}

  @override
  void selectDestinationContact({
    required String address,
    required String contactId,
  }) {}

  @override
  void selectExternalAsset(SwapAsset asset) {}

  @override
  void updateSlippageBps(int value) {}

  @override
  Future<void> useMaxZecAmount() async {}

  @override
  Future<void> showReview({bool preserveCurrentReview = false}) async {}

  @override
  Future<SwapStartResult?> startIntent() async => null;

  @override
  void cancelReviewQuote() {}

  @override
  void expireReviewQuote() {}

  // The activity detail surface's four action buttons: the real ones reach the
  // status client, `DateTime.now()` and the intent store.
  @override
  Future<void> refreshSelectedIntentStatus() async {}

  @override
  Future<void> markSelectedDepositClaimed() async {}

  @override
  Future<void> submitSelectedDepositTransaction() async {}

  @override
  void prepareRetryFromSelectedIntent() {}

  @override
  Future<void> removeIntent(String intentId) async {}
}

class _SwapMobileAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _swapMobileAccountState;
}

class _SwapMobileAddressBookNotifier extends AddressBookNotifier {
  @override
  FutureOr<AddressBookState> build() =>
      const AddressBookState(contacts: _swapMobileContacts);
}

/// Bottom `viewInsets` stand in for the open number pad.
Widget _swapMobileKeyboardInsets({required bool open, required Widget child}) {
  if (!open) return child;
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(viewInsets: const EdgeInsets.only(bottom: 336)),
      child: child,
    ),
  );
}

/// Router for the two screens: they read no route during build, but their
/// back / review / cancel taps call `go`, `push` and `canPop`, which need a
/// real router rather than the widgetbook host.
class _SwapMobileRouterHarness extends StatefulWidget {
  const _SwapMobileRouterHarness({
    required this.location,
    required this.screen,
  });

  final String location;
  final Widget screen;

  @override
  State<_SwapMobileRouterHarness> createState() =>
      _SwapMobileRouterHarnessState();
}

class _SwapMobileRouterHarnessState extends State<_SwapMobileRouterHarness> {
  static const _paths = [
    '/home',
    '/swap',
    '/swap/review',
    '/swap/keystone-sign',
    '/pay',
    '/pay/review',
    '/activity',
    '/activity/swap/detail',
  ];

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.location,
      routes: [
        for (final path in _paths)
          GoRoute(
            path: path,
            builder: (_, _) => path == widget.location
                ? widget.screen
                : _SwapMobileRoutePlaceholder(label: path),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

class _SwapMobileRoutePlaceholder extends StatelessWidget {
  const _SwapMobileRoutePlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.window,
      child: Center(
        child: Text(
          label,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.muted),
        ),
      ),
    );
  }
}

/// Phone-width padding for the component fixtures, matching the gutter the
/// review and composer screens give their content.
class _SwapMobilePad extends StatelessWidget {
  const _SwapMobilePad({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
    );
  }
}

// --- Desktop Keystone signing overlay --------------------------------------

/// Where the overlay's own preparation sits. `broadcasting` and the Sapling
/// download prompt are only reachable by scanning a device response, and
/// `failed` is produced by [SwapKeystoneOverlayError], so neither is an option.
enum SwapKeystoneOverlayPhase { preparing, ready }

/// The failure raised while preparing the deposit PCZT; the panel shows
/// whatever the overlay's own `_friendlyError` maps it to.
enum SwapKeystoneOverlayError {
  none,
  texUnsupported,
  provingParameters,
  proposalExpired,
  signatureNotApplied,
  broadcastFailed,
  generic,
}

SwapMobileKeystoneError _swapKeystoneOverlayErrorSource(
  SwapKeystoneOverlayError error,
) {
  return switch (error) {
    SwapKeystoneOverlayError.none => SwapMobileKeystoneError.none,
    SwapKeystoneOverlayError.texUnsupported =>
      SwapMobileKeystoneError.texUnsupported,
    SwapKeystoneOverlayError.provingParameters =>
      SwapMobileKeystoneError.saplingParams,
    SwapKeystoneOverlayError.proposalExpired =>
      SwapMobileKeystoneError.proposalExpired,
    SwapKeystoneOverlayError.signatureNotApplied =>
      SwapMobileKeystoneError.signatureNotApplied,
    SwapKeystoneOverlayError.broadcastFailed =>
      SwapMobileKeystoneError.broadcastFailed,
    SwapKeystoneOverlayError.generic => SwapMobileKeystoneError.generic,
  };
}

/// The desktop pane overlay on the same fake signing service the mobile
/// screen uses. Rendered on a plain pane, never over a live composer.
Widget swapKeystoneOverlayFixture({
  SwapKeystoneOverlayPhase phase = SwapKeystoneOverlayPhase.ready,
  SwapKeystoneOverlayError error = SwapKeystoneOverlayError.none,
}) {
  final failure = _swapMobileKeystoneErrorFor(
    _swapKeystoneOverlayErrorSource(error),
  );
  return _swapMobileScope(
    state: _swapMobileComposerState,
    spendableZatoshi: _swapMobileSpendableZatoshi,
    overrides: [
      swapHardwareSigningServiceProvider.overrideWithValue(
        _SwapMobileKeystoneSigningService(
          hangOnCreate:
              failure == null && phase == SwapKeystoneOverlayPhase.preparing,
          createError: failure,
        ),
      ),
    ],
    child: _SwapMobileRouterHarness(
      location: '/swap',
      screen: SwapKeystoneSigningOverlay(
        intent: _swapMobileKeystoneIntent,
        onCancel: _swapMobileNoop,
        onDepositBroadcast: (_) async {},
      ),
    ),
  );
}

// --- Swap activity detail --------------------------------------------------

/// The ten intent statuses the activity surface routes on.
enum SwapActivityStatusCase {
  awaitingDeposit,
  awaitingExternalDeposit,
  depositObserved,
  processing,
  // Renders exactly like [processing] here: the mapper gives both the same
  // progress index and pay phase, and the 'Checking status' label only prints
  // for terminal statuses. Kept so the ten routed statuses stay listed.
  statusUnknown,
  incompleteDeposit,
  complete,
  refunded,
  expired,
  failed,
}

/// A payment intent always sends ZEC, so pairing [payment] with the
/// 'Awaiting external deposit' status is a state the product cannot reach.
enum SwapActivityMode { swap, payment }

/// Whether the requested intent id is in the state; a miss renders the
/// "couldn't load this swap" panel.
enum SwapActivityIntentCase { found, missing }

enum SwapActivityNotice { none, statusRefreshError }

/// Which page the panel picks: a deposit instruction page (centered) or the
/// status page (top-aligned).
enum SwapActivityPagePanelContent { depositPage, statusPage }

const _swapActivityIntentId = 'widgetbook-swap-activity';
const _swapActivityMissingIntentId = 'widgetbook-swap-activity-missing';
const _swapActivityHardwareAccountUuid = 'widgetbook-swap-hardware-account';
const _swapActivityExternalDepositAddress =
    '0x9e4c1f2a7b3d5e6f8a0b2c4d6e8f0a2b4c6d8e00';
const _swapActivityZecDepositAddress = 'u1widgetbookswapactivitydeposit';
const _swapActivityStatusErrorMessage =
    'Could not refresh the swap status. Check your connection and try again.';

/// Fixed timestamps — the detail rows date the swap, so a `now()` here would
/// make the preview drift.
final _swapActivityCreatedAt = DateTime.utc(2026, 5, 14, 9, 41);
final _swapActivityCompletedAt = DateTime.utc(2026, 5, 14, 9, 58);

/// Two accounts so the hardware axis can flip `intentIsHardware` through the
/// real account lookup instead of a prop.
const _swapActivityAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: _swapMobileAccountUuid,
      name: 'John',
      order: 0,
      profilePictureId: 'pfp-01',
    ),
    AccountInfo(
      uuid: _swapActivityHardwareAccountUuid,
      name: 'Keystone',
      order: 1,
      isHardware: true,
      profilePictureId: 'pfp-02',
    ),
  ],
  activeAccountUuid: _swapMobileAccountUuid,
  activeAddress: _swapMobileWalletZecAddress,
);

SwapIntentStatus _swapActivityIntentStatus(SwapActivityStatusCase status) {
  return switch (status) {
    SwapActivityStatusCase.awaitingDeposit => SwapIntentStatus.awaitingDeposit,
    SwapActivityStatusCase.awaitingExternalDeposit =>
      SwapIntentStatus.awaitingExternalDeposit,
    SwapActivityStatusCase.depositObserved => SwapIntentStatus.depositObserved,
    SwapActivityStatusCase.processing => SwapIntentStatus.processing,
    SwapActivityStatusCase.statusUnknown =>
      SwapIntentStatus.providerStatusUnknown,
    SwapActivityStatusCase.incompleteDeposit =>
      SwapIntentStatus.incompleteDeposit,
    SwapActivityStatusCase.complete => SwapIntentStatus.complete,
    SwapActivityStatusCase.refunded => SwapIntentStatus.refunded,
    SwapActivityStatusCase.expired => SwapIntentStatus.expired,
    SwapActivityStatusCase.failed => SwapIntentStatus.failed,
  };
}

/// `depositDeadline` stays null so the deposit page's countdown never ticks.
SwapIntent _swapActivityIntent({
  required SwapActivityStatusCase status,
  required SwapActivityMode mode,
  required SwapActivityNotice notice,
  required bool hardwareAccount,
}) {
  // Only the external-deposit status deposits an external asset; every other
  // case sends ZEC, which is also what pay mode requires.
  final receivesZec = status == SwapActivityStatusCase.awaitingExternalDeposit;
  final complete = status == SwapActivityStatusCase.complete;
  return SwapIntent(
    id: _swapActivityIntentId,
    pair: receivesZec ? 'USDC -> ZEC' : 'ZEC -> USDC',
    sellAmount: receivesZec ? '110.24 USDC' : '1.12 ZEC',
    receiveEstimate: receivesZec ? '1.57 ZEC' : '78.59 USDC',
    provider: 'NEAR Intents',
    status: _swapActivityIntentStatus(status),
    nextAction: 'Waiting for the provider',
    direction: receivesZec
        ? SwapDirection.externalToZec
        : SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    accountUuid: hardwareAccount
        ? _swapActivityHardwareAccountUuid
        : _swapMobileAccountUuid,
    depositAddress: receivesZec
        ? _swapActivityExternalDepositAddress
        : _swapActivityZecDepositAddress,
    totalFeesText: '0.0012 ZEC',
    realisedSlippageText: '0.12%',
    oneClickRecipient: receivesZec ? null : _swapMobileContactAddress,
    oneClickRefundTo: receivesZec
        ? _swapMobilePlainAddress
        : _swapMobileWalletZecAddress,
    userExternalContactId: 'widgetbook-swap-mike',
    statusError: notice == SwapActivityNotice.statusRefreshError
        ? _swapActivityStatusErrorMessage
        : null,
    createdAt: _swapActivityCreatedAt,
    completedAt: complete ? _swapActivityCompletedAt : null,
    payMode: mode == SwapActivityMode.payment,
  );
}

SwapState _swapActivityState(SwapIntent intent) {
  return _swapMobileComposerState.copyWith(intents: [intent]);
}

/// The activity detail surface on a pinned intent.
///
/// The back link takes its label from the return target, which follows the
/// mode; `SwapActivityReturnTarget.activity` and `.home` differ only in that
/// label, so they stay with the return-target enum rather than a knob.
Widget swapActivityDetailSurfaceFixture({
  bool mobile = false,
  SwapActivityStatusCase status = SwapActivityStatusCase.processing,
  SwapActivityMode mode = SwapActivityMode.swap,
  SwapActivityIntentCase intentCase = SwapActivityIntentCase.found,
  SwapActivityNotice notice = SwapActivityNotice.none,
  bool hardwareAccount = false,
}) {
  final intent = _swapActivityIntent(
    status: status,
    mode: mode,
    notice: notice,
    hardwareAccount: hardwareAccount,
  );
  return _swapActivityScope(
    state: _swapActivityState(intent),
    child: _SwapMobileRouterHarness(
      location: '/activity/swap/detail',
      screen: SwapActivityDetailSurface(
        intentId: intentCase == SwapActivityIntentCase.found
            ? _swapActivityIntentId
            : _swapActivityMissingIntentId,
        returnTarget: mode == SwapActivityMode.payment
            ? SwapActivityReturnTarget.pay
            : SwapActivityReturnTarget.swap,
        layout: mobile
            ? SwapActivityDetailLayout.mobile
            : SwapActivityDetailLayout.desktop,
      ),
    ),
  );
}

/// The page panel on its own props, in the two alignments it switches between.
Widget swapActivityDetailPagePanelFixture({
  SwapActivityPagePanelContent content =
      SwapActivityPagePanelContent.statusPage,
  bool mobile = false,
}) {
  final depositPage = content == SwapActivityPagePanelContent.depositPage;
  final intent = _swapActivityIntent(
    status: depositPage
        ? SwapActivityStatusCase.awaitingExternalDeposit
        : SwapActivityStatusCase.processing,
    mode: SwapActivityMode.swap,
    notice: SwapActivityNotice.none,
    hardwareAccount: false,
  );
  final state = _swapActivityState(intent);
  return _swapActivityScope(
    state: state,
    child: SwapActivityDetailPagePanel(
      state: state,
      intent: intent,
      layout: mobile
          ? SwapActivityDetailLayout.mobile
          : SwapActivityDetailLayout.desktop,
      depositChecking: false,
      depositCheckWarning: null,
      onRefreshStatus: _swapMobileNoop,
      onMarkDeposited: _swapMobileNoop,
      onDepositTxHashChanged: _swapMobileIgnoreText,
      onSubmitDepositTransaction: _swapMobileNoop,
      onReviewFreshQuote: _swapMobileNoop,
      onSignZecDeposit: (_) {},
      intentIsHardware: false,
    ),
  );
}

// --- Swap progress route ---------------------------------------------------

/// `Animated` is the live-quote wrapper. It starts on its target step, so the
/// walk only shows once a live status pushes the index forward.
enum SwapProgressRouteVariant { plain, animated }

enum SwapProgressRouteLength { three, four }

/// The copy the active step can carry beside its title.
enum SwapProgressRouteCopy { none, lastChecked, description }

const _swapProgressRouteTitles = <String>[
  'USDC source deposit',
  'Deposit confirmation',
  'Swap',
  'Send ZEC',
];

List<SwapStatusStepData> swapProgressRouteSteps({
  required int count,
  required int activeStep,
  SwapProgressRouteCopy copy = SwapProgressRouteCopy.none,
}) {
  final active = activeStep.clamp(0, count - 1);
  return [
    for (var index = 0; index < count; index++)
      SwapStatusStepData(
        title: _swapProgressRouteTitles[index],
        state: index < active
            ? SwapStatusStepState.complete
            : index == active
            ? SwapStatusStepState.active
            : SwapStatusStepState.pending,
        activeTitle: '${_swapProgressRouteTitles[index]}...',
        lastCheckedLabel: copy == SwapProgressRouteCopy.lastChecked
            ? 'Last check: 1m ago'
            : null,
        description: copy == SwapProgressRouteCopy.description
            ? 'The provider is executing the swap route.'
            : null,
      ),
  ];
}

/// No layout knob: the route branches on `kAppFormFactor` itself (step inset,
/// active-step height, loader size, completed glyph), so the compiled lane
/// decides the geometry — the mobile metrics only show in the mobile lane.
Widget swapProgressRouteFixture({
  SwapProgressRouteVariant variant = SwapProgressRouteVariant.plain,
  SwapProgressRouteLength length = SwapProgressRouteLength.four,
  int activeStep = 1,
  SwapProgressRouteCopy copy = SwapProgressRouteCopy.none,
}) {
  final count = length == SwapProgressRouteLength.three ? 3 : 4;
  final steps = swapProgressRouteSteps(
    count: count,
    activeStep: activeStep,
    copy: copy,
  );
  return _SwapComponentPad(
    width: 400,
    child: variant == SwapProgressRouteVariant.animated
        ? SwapAnimatedProgressRoute(
            steps: steps,
            progressIndex: activeStep.clamp(0, count - 1),
            badgeKind: SwapStatusBadgeKind.liveQuote,
          )
        : SwapProgressRoute(steps: steps),
  );
}

// --- Swap review info ------------------------------------------------------

/// The bottom line of the receiving side: a plain fiat value, or the
/// counterparty address with its Copy affordance.
enum SwapReviewInfoDetail { fiat, copyableAddress }

enum SwapReviewInfoAsset { zec, external, letterFallback }

/// An asset whose icon path does not resolve, so `Image.asset` falls back to
/// the letter tile.
final swapUnknownAsset = SwapAsset.live(
  assetId: 'widgetbook:unknown',
  symbol: 'QQQ',
  blockchain: 'qqq',
  decimals: 6,
);

SwapAsset _swapReviewInfoAsset(SwapReviewInfoAsset asset) {
  return switch (asset) {
    SwapReviewInfoAsset.zec => SwapAsset.zec,
    SwapReviewInfoAsset.external => SwapAsset.usdc,
    SwapReviewInfoAsset.letterFallback => swapUnknownAsset,
  };
}

/// The paying/receiving summary. The paying side stays a plain ZEC fiat row so
/// each axis reads against a fixed baseline.
Widget swapReviewInfoFixture({
  SwapReviewInfoDetail detail = SwapReviewInfoDetail.fiat,
  SwapReviewInfoAsset asset = SwapReviewInfoAsset.external,
}) {
  final copyable = detail == SwapReviewInfoDetail.copyableAddress;
  final receiveAsset = _swapReviewInfoAsset(asset);
  return _SwapComponentPad(
    width: 400,
    child: SwapReviewInfo(
      pay: const SwapReviewInfoSideData(
        asset: SwapAsset.zec,
        label: "You're paying",
        amountText: '1.12 ZEC',
        detailText: r'$78.59',
      ),
      receive: SwapReviewInfoSideData(
        asset: receiveAsset,
        label: "You're receiving",
        amountText: '78.59 ${receiveAsset.symbol}',
        detailText: copyable
            ? 'To: 0x5290 ... 69ee7 on ${receiveAsset.chainLabel}'
            : r'$78.59',
        detailCopyText: copyable ? _swapMobileContactAddress : null,
      ),
      onCopy: _swapMobileIgnoreText,
    ),
  );
}

// --- Swap asset icon -------------------------------------------------------

enum SwapAssetIconAsset { zec, usdc, unknown }

/// Desktop draws a 32px asset with a 5/8 badge; the mobile composer draws 40px
/// and keeps the chain circle at the same absolute 20px.
enum SwapAssetIconSize { desktop, mobile }

Widget swapAssetIconFixture({
  SwapAssetIconAsset asset = SwapAssetIconAsset.usdc,
  bool chainBadge = true,
  bool selected = false,
  SwapAssetIconSize size = SwapAssetIconSize.desktop,
}) {
  final mobile = size == SwapAssetIconSize.mobile;
  return _SwapComponentPad(
    width: 160,
    child: Center(
      child: SwapAssetIcon(
        asset: switch (asset) {
          SwapAssetIconAsset.zec => SwapAsset.zec,
          SwapAssetIconAsset.usdc => SwapAsset.usdc,
          SwapAssetIconAsset.unknown => swapUnknownAsset,
        },
        size: mobile ? 40 : 32,
        selected: selected,
        showChainBadge: chainBadge,
        badgeScale: mobile ? 0.5 : 0.625,
        overhangScale: mobile ? 0.1 : 0.125,
      ),
    ),
  );
}

// --- NEAR Intents attribution ----------------------------------------------

enum SwapAttributionAlignment { left, centered, end }

Widget swapAttributionFixture({
  SwapAttributionAlignment alignment = SwapAttributionAlignment.left,
}) {
  return _SwapComponentPad(
    width: 200,
    child: SwapNearIntentsAttribution(
      centered: alignment == SwapAttributionAlignment.centered,
      alignEnd: alignment == SwapAttributionAlignment.end,
    ),
  );
}

// --- Swap modal controls ---------------------------------------------------

/// One axis: each control carries its own variants, because a size only
/// applies to the inline button and an enablement only to the button row.
/// The inline button's tap target is 20 on the desktop field and 24 in the
/// mobile modal fields (`AppInputSizing.iconSize`).
enum SwapModalControl {
  iconBadge,
  inlineIconButtonDesktop,
  inlineIconButtonMobile,
  modalButtons,
  modalButtonsPrimaryDisabled,
}

Widget swapModalControlsFixture({
  SwapModalControl control = SwapModalControl.modalButtons,
}) {
  return _SwapComponentPad(
    width: 320,
    child: Center(
      child: switch (control) {
        SwapModalControl.iconBadge => Builder(
          builder: (context) => SwapModalIconBadge(
            iconName: AppIcons.warning,
            iconColor: context.colors.icon.accent,
          ),
        ),
        SwapModalControl.inlineIconButtonDesktop ||
        SwapModalControl.inlineIconButtonMobile => SwapInlineIconButton(
          iconName: AppIcons.camera,
          onTap: _swapMobileNoop,
          size: control == SwapModalControl.inlineIconButtonMobile ? 24 : 20,
        ),
        SwapModalControl.modalButtons ||
        SwapModalControl.modalButtonsPrimaryDisabled => SwapModalButtons(
          primaryKey: const ValueKey('swap_modal_buttons_primary'),
          cancelKey: const ValueKey('swap_modal_buttons_cancel'),
          onPrimary: _swapMobileNoop,
          onCancel: _swapMobileNoop,
          primaryEnabled: control == SwapModalControl.modalButtons,
        ),
      },
    ),
  );
}

// --- Fixture plumbing (activity + components) ------------------------------

/// Provider scope for the activity surfaces: the same pinned swap state as the
/// mobile screens, plus the two-account list the hardware routing reads.
Widget _swapActivityScope({required SwapState state, required Widget child}) {
  return ProviderScope(
    overrides: [
      swapStateProvider.overrideWith(() => _SwapMobilePreviewNotifier(state)),
      accountProvider.overrideWith(_SwapActivityAccountNotifier.new),
      addressBookProvider.overrideWith(_SwapMobileAddressBookNotifier.new),
      addressBookRepositoryProvider.overrideWith(
        (ref) => WbAddressBookRepository(),
      ),
      ironwoodMigrationAwareDisplaySpendableProvider.overrideWith(
        (ref, accountUuid) => _swapMobileSpendableZatoshi,
      ),
    ],
    child: child,
  );
}

class _SwapActivityAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => _swapActivityAccountState;
}

/// Bounded box for the component fixtures: they are stretch / min-width
/// children that take their width from the host.
class _SwapComponentPad extends StatelessWidget {
  const _SwapComponentPad({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Center(
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: child,
          ),
        ),
      ),
    );
  }
}
