// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/features/address_scan/widgets/address_qr_scan_modal.dart';
import '../../src/features/send/screens/mobile/mobile_send_screen.dart';
import '../../src/features/send/services/send_flow.dart';
import '../send_compose_view.dart';
import '../../src/features/send/widgets/send_status_content_view.dart';
import '../../src/features/send/widgets/verify_address_modal.dart';
import '../address_verify_use_cases.dart';
import '../payment_request_use_cases.dart';
import '../send_review_status_use_cases.dart';
import '../send_screen_use_cases.dart';
import '../send_use_cases.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';

/// The Send gallery: one use case per surface, each knob dispatching to the
/// fixtures in `send_use_cases.dart`, `send_review_status_use_cases.dart`,
/// `address_verify_use_cases.dart` and `payment_request_use_cases.dart`, so
/// figma_compare and the tests keep every `build*UseCase` they bind to.
final List<WidgetbookNode> sendGalleryNodes = [
  WidgetbookComponent(
    name: 'Send screen',
    // The desktop screen and the mobile wizard are the same surface in two
    // widget classes, so they are one case with a `Layout` knob; the wizard's
    // steps are states of that one mobile screen, so they are a knob too.
    useCases: [
      WidgetbookUseCase(name: 'Screen', builder: buildSendScreenGalleryCase),
    ],
  ),
  WidgetbookComponent(
    // Desktop-only: the mobile wizard reviews inside the send screen itself, so
    // its review step is a knob on that surface rather than a case here.
    name: 'Send review screen',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildSendReviewScreenGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Send status screen',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildSendStatusScreenGalleryCase,
      ),
    ],
  ),
  WidgetbookComponent(
    // Mobile-only surface: desktop signs through the Keystone modal.
    name: 'Keystone sign',
    useCases: [
      WidgetbookUseCase(
        name: 'Playground',
        builder: buildSendMobileKeystoneSignGalleryCase,
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Send compose',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSendComposeGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Send review',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSendReviewGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Send status',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSendStatusGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Payment request card',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSendPaymentRequestGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Modals',
    children: [
      WidgetbookComponent(
        name: 'Verify address',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildSendVerifyAddressGalleryCase,
          ),
          // Not a layout of the modal but a second desktop composition: the modal
          // plus the live recipient lookup the review and status screens wrap it
          // in, which no provider can supply alongside the Playground's static
          // previous-transaction counts.
          WidgetbookUseCase(
            name: 'Overlay',
            builder: buildSendVerifyAddressOverlayGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Sapling params',
        useCases: [
          WidgetbookUseCase(
            name: 'Prompt',
            builder: buildSendSaplingParamsGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Send compose ----------------------------------------------------------

/// Which currency the amount field takes.
enum SendComposeUnit { zec, usd }

/// Whether the ZEC price behind the conversion line has arrived.
enum SendComposePrice { loaded, loading }

/// The amount field's validation state.
enum SendComposeAmountError { none, notEnough }

/// How the message area is presented; `SendMemoMode.expanded` splits in two
/// because the over-limit state is the same mode with error props.
enum SendComposeMessage { prompt, expanded, tooLong, transparentUnavailable }

Widget buildSendComposeGalleryCase(BuildContext context) {
  final route = wbStateKnob<SendPoolRoute>(
    context,
    label: 'Pool route',
    options: SendPoolRoute.values,
    labelBuilder: sendComposeRouteLabel,
  );
  final unit = wbStateKnob<SendComposeUnit>(
    context,
    label: 'Unit',
    options: SendComposeUnit.values,
    labelBuilder: sendComposeUnitLabel,
  );
  final price = wbStateKnob<SendComposePrice>(
    context,
    label: 'Price',
    options: SendComposePrice.values,
    labelBuilder: sendComposePriceLabel,
  );
  final amountFocused = wbBoolKnob(context, label: 'Amount focused');
  final amountError = wbStateKnob<SendComposeAmountError>(
    context,
    label: 'Amount error',
    options: SendComposeAmountError.values,
    labelBuilder: sendComposeAmountErrorLabel,
  );
  final message = wbStateKnob<SendComposeMessage>(
    context,
    label: 'Message',
    options: SendComposeMessage.values,
    labelBuilder: sendComposeMessageLabel,
  );
  final reviewEnabled = wbBoolKnob(context, label: 'Review enabled');

  // The live screen derives the route from the recipient, so 'Unknown' is also
  // the state where nothing has been typed into the form yet.
  final entered = route != SendPoolRoute.unknown;
  final usd = unit == SendComposeUnit.usd;
  final tooLong = message == SendComposeMessage.tooLong;
  return sendComposeFixture(
    recipientText: entered ? kSendComposeFixtureAddress : '',
    route: route,
    amountText: entered ? (usd ? '512.24' : '125.12') : '',
    amountInputIsUsd: usd,
    amountConversionText: price == SendComposePrice.loading
        ? null
        : entered
        ? (usd ? '125.12 ZEC' : r'$ 8,758.40')
        : (usd ? '0 ZEC' : r'$ 0'),
    amountConversionLoading: price == SendComposePrice.loading,
    amountFocused: amountFocused,
    amountError: amountError == SendComposeAmountError.notEnough
        ? kSendComposeFixtureAmountError
        : null,
    memoMode: switch (message) {
      SendComposeMessage.prompt => SendMemoMode.prompt,
      SendComposeMessage.expanded ||
      SendComposeMessage.tooLong => SendMemoMode.expanded,
      SendComposeMessage.transparentUnavailable =>
        SendMemoMode.transparentUnavailable,
    },
    memoText: tooLong ? kSendComposeFixtureLongMemo : '',
    memoCounter: tooLong ? kSendComposeFixtureMemoCounter : '512/512',
    memoError: tooLong ? kSendComposeFixtureMemoError : null,
    reviewEnabled: reviewEnabled,
  );
}

String sendComposeRouteLabel(SendPoolRoute route) {
  return switch (route) {
    SendPoolRoute.unknown => 'Unknown',
    SendPoolRoute.shieldedToShielded => 'Shielded to shielded',
    SendPoolRoute.shieldedToTransparent => 'Shielded to transparent',
  };
}

String sendComposeUnitLabel(SendComposeUnit unit) {
  return switch (unit) {
    SendComposeUnit.zec => 'ZEC',
    SendComposeUnit.usd => 'USD',
  };
}

String sendComposePriceLabel(SendComposePrice price) {
  return switch (price) {
    SendComposePrice.loaded => 'Loaded',
    SendComposePrice.loading => 'Loading',
  };
}

String sendComposeAmountErrorLabel(SendComposeAmountError error) {
  return switch (error) {
    SendComposeAmountError.none => 'None',
    SendComposeAmountError.notEnough => 'Not enough ZEC',
  };
}

String sendComposeMessageLabel(SendComposeMessage message) {
  return switch (message) {
    SendComposeMessage.prompt => 'Prompt',
    SendComposeMessage.expanded => 'Expanded',
    SendComposeMessage.tooLong => 'Too long',
    SendComposeMessage.transparentUnavailable => 'Unavailable for transparent',
  };
}

// --- Send review -----------------------------------------------------------

/// Who the review names as the recipient.
enum SendReviewPanelRecipient { address, contact }

/// Which pool the recipient address belongs to.
enum SendReviewPanelPool { shielded, transparent }

/// Whether this send answers a ZIP-321 request, and whether the amount was
/// edited away from the one the request named.
enum SendReviewPanelRequest { none, requested, amountEdited }

/// How the Message row is presented.
enum SendReviewPanelMessage { none, truncated, expanded }

/// Which account signs; a Keystone send relabels the primary action.
enum SendReviewPanelConfirm { software, keystone }

/// Whether the actions can still be used: the live screen disables Confirm on
/// an abandoned proposal and both actions while a cancel is in flight.
enum SendReviewPanelConfirmState { enabled, disabled, cancelling }

Widget buildSendReviewGalleryCase(BuildContext context) {
  final recipient = wbStateKnob<SendReviewPanelRecipient>(
    context,
    label: 'Recipient',
    options: SendReviewPanelRecipient.values,
    labelBuilder: sendReviewPanelRecipientLabel,
  );
  final pool = wbStateKnob<SendReviewPanelPool>(
    context,
    label: 'Recipient pool',
    options: SendReviewPanelPool.values,
    labelBuilder: sendReviewPanelPoolLabel,
  );
  final request = wbStateKnob<SendReviewPanelRequest>(
    context,
    label: 'Payment request',
    options: SendReviewPanelRequest.values,
    labelBuilder: sendReviewPanelRequestLabel,
  );
  final message = wbStateKnob<SendReviewPanelMessage>(
    context,
    label: 'Message',
    options: SendReviewPanelMessage.values,
    labelBuilder: sendReviewPanelMessageLabel,
  );
  final fiat = wbBoolKnob(context, label: 'Fiat row', initial: true);
  final confirm = wbStateKnob<SendReviewPanelConfirm>(
    context,
    label: 'Confirm',
    options: SendReviewPanelConfirm.values,
    labelBuilder: sendReviewPanelConfirmLabel,
  );
  final confirmState = wbStateKnob<SendReviewPanelConfirmState>(
    context,
    label: 'Confirm state',
    options: SendReviewPanelConfirmState.values,
    labelBuilder: sendReviewPanelConfirmStateLabel,
  );

  final transparent = pool == SendReviewPanelPool.transparent;
  return sendReviewContentFixture(
    contactRecipient: recipient == SendReviewPanelRecipient.contact,
    isShieldedRecipient: !transparent,
    recipientAddressType: transparent ? 'transparent' : 'unified',
    isPaymentRequest: request != SendReviewPanelRequest.none,
    requestedAmountText: request == SendReviewPanelRequest.amountEdited
        ? '0.50 ZEC'
        : null,
    memoText: message == SendReviewPanelMessage.none
        ? null
        : kSendReviewFixtureLongMemo,
    memoExpanded: message == SendReviewPanelMessage.expanded,
    fiatText: fiat ? r'$250.12' : null,
    hardwareAccount: confirm == SendReviewPanelConfirm.keystone,
    confirmEnabled: confirmState == SendReviewPanelConfirmState.enabled,
    cancelling: confirmState == SendReviewPanelConfirmState.cancelling,
  );
}

String sendReviewPanelRecipientLabel(SendReviewPanelRecipient recipient) {
  return switch (recipient) {
    SendReviewPanelRecipient.address => 'Address',
    SendReviewPanelRecipient.contact => 'Saved contact',
  };
}

String sendReviewPanelPoolLabel(SendReviewPanelPool pool) {
  return switch (pool) {
    SendReviewPanelPool.shielded => 'Shielded',
    SendReviewPanelPool.transparent => 'Transparent',
  };
}

String sendReviewPanelRequestLabel(SendReviewPanelRequest request) {
  return switch (request) {
    SendReviewPanelRequest.none => 'Not a request',
    SendReviewPanelRequest.requested => 'Requested amount',
    SendReviewPanelRequest.amountEdited => 'Amount edited',
  };
}

String sendReviewPanelMessageLabel(SendReviewPanelMessage message) {
  return switch (message) {
    SendReviewPanelMessage.none => 'None',
    SendReviewPanelMessage.truncated => 'Truncated',
    SendReviewPanelMessage.expanded => 'Expanded',
  };
}

String sendReviewPanelConfirmLabel(SendReviewPanelConfirm confirm) {
  return switch (confirm) {
    SendReviewPanelConfirm.software => 'Software',
    SendReviewPanelConfirm.keystone => 'Keystone',
  };
}

String sendReviewPanelConfirmStateLabel(SendReviewPanelConfirmState state) {
  return switch (state) {
    SendReviewPanelConfirmState.enabled => 'Enabled',
    SendReviewPanelConfirmState.disabled => 'Disabled',
    SendReviewPanelConfirmState.cancelling => 'Cancelling',
  };
}

// --- Send status -----------------------------------------------------------

/// The extra line under the receipt rows.
enum SendStatusPanelNotice { none, queued, failureReason }

/// How the Message row is presented.
enum SendStatusPanelMessage { none, truncated, expanded }

/// Which flow's copy the receipt carries.
enum SendStatusPanelTitle { send, donation }

Widget buildSendStatusGalleryCase(BuildContext context) {
  final phase = wbStateKnob<SendStatusPhase>(
    context,
    label: 'Phase',
    options: SendStatusPhase.values,
    labelBuilder: sendStatusPhaseLabel,
  );
  final notice = wbStateKnob<SendStatusPanelNotice>(
    context,
    label: 'Notice',
    options: SendStatusPanelNotice.values,
    labelBuilder: sendStatusPanelNoticeLabel,
  );
  final transactionHash = wbBoolKnob(
    context,
    label: 'Transaction hash',
    initial: true,
  );
  final fiat = wbBoolKnob(context, label: 'Fiat row', initial: true);
  final message = wbStateKnob<SendStatusPanelMessage>(
    context,
    label: 'Message',
    options: SendStatusPanelMessage.values,
    labelBuilder: sendStatusPanelMessageLabel,
    initial: SendStatusPanelMessage.truncated,
  );
  final title = wbStateKnob<SendStatusPanelTitle>(
    context,
    label: 'Title',
    options: SendStatusPanelTitle.values,
    labelBuilder: sendStatusPanelTitleLabel,
  );

  return sendStatusContentFixture(
    phase: phase,
    fiatText: fiat ? r'$250.12' : null,
    memoText: message == SendStatusPanelMessage.none
        ? null
        : kSendReviewFixtureLongMemo,
    memoExpanded: message == SendStatusPanelMessage.expanded,
    txIdText: transactionHash ? kSendStatusFixtureTxId : null,
    noticeText: switch (notice) {
      SendStatusPanelNotice.none => null,
      SendStatusPanelNotice.queued => kSendStatusScreenBroadcastGuidance,
      SendStatusPanelNotice.failureReason => kSendStatusScreenFailureReason,
    },
    donation: title == SendStatusPanelTitle.donation,
  );
}

String sendStatusPhaseLabel(SendStatusPhase phase) {
  return switch (phase) {
    SendStatusPhase.inProgress => 'In progress',
    SendStatusPhase.completed => 'Completed',
    SendStatusPhase.failed => 'Failed',
  };
}

String sendStatusPanelNoticeLabel(SendStatusPanelNotice notice) {
  return switch (notice) {
    SendStatusPanelNotice.none => 'None',
    SendStatusPanelNotice.queued => 'Queued to send',
    SendStatusPanelNotice.failureReason => 'Failure reason',
  };
}

String sendStatusPanelMessageLabel(SendStatusPanelMessage message) {
  return switch (message) {
    SendStatusPanelMessage.none => 'None',
    SendStatusPanelMessage.truncated => 'Truncated',
    SendStatusPanelMessage.expanded => 'Expanded',
  };
}

String sendStatusPanelTitleLabel(SendStatusPanelTitle title) {
  return switch (title) {
    SendStatusPanelTitle.send => 'Send',
    SendStatusPanelTitle.donation => 'Donation',
  };
}

// --- Verify address --------------------------------------------------------

/// Whether the recipient is one the address book already knows.
enum SendVerifyAddressRecipient { unknown, savedContact }

/// The header the unknown recipient gets: its pool, or the off-chain wallet
/// header the Pay and swap payout rows use.
enum SendVerifyAddressKind { shielded, transparent, external }

/// How many transactions the saved contact has already been paid; the count
/// is absent while the caller is still resolving it.
enum SendVerifyAddressHistory { hidden, one, many }

/// Which string the address viewer renders.
enum SendVerifyAddressContent { sample, glyphShowcase }

Widget buildSendVerifyAddressGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  // Recipient carries the header variant; the kind and the count each belong
  // to one variant, which is why they are separate axes rather than one
  // flattened list of recipients.
  final recipient = wbStateKnob<SendVerifyAddressRecipient>(
    context,
    label: 'Recipient',
    options: SendVerifyAddressRecipient.values,
    labelBuilder: sendVerifyAddressRecipientLabel,
  );
  if (layout == WbLayout.mobile) {
    return _sendVerifyAddressMobileCase(context, recipient: recipient);
  }
  final kind = wbStateKnob<SendVerifyAddressKind>(
    context,
    label: 'Address kind',
    options: SendVerifyAddressKind.values,
    labelBuilder: sendVerifyAddressKindLabel,
  );
  final history = wbStateKnob<SendVerifyAddressHistory>(
    context,
    label: 'Previous transactions',
    options: SendVerifyAddressHistory.values,
    labelBuilder: sendVerifyAddressHistoryLabel,
  );
  final content = wbStateKnob<SendVerifyAddressContent>(
    context,
    label: 'Address',
    options: SendVerifyAddressContent.values,
    labelBuilder: sendVerifyAddressContentLabel,
  );
  return verifyAddressModalFixture(
    variant: recipient == SendVerifyAddressRecipient.savedContact
        ? VerifyAddressModalVariant.knownContact
        : VerifyAddressModalVariant.unknown,
    unknownAddressKind: switch (kind) {
      SendVerifyAddressKind.shielded => VerifyAddressModalAddressKind.shielded,
      SendVerifyAddressKind.transparent =>
        VerifyAddressModalAddressKind.transparent,
      SendVerifyAddressKind.external => VerifyAddressModalAddressKind.external,
    },
    previousTransactionCount: switch (history) {
      SendVerifyAddressHistory.hidden => null,
      SendVerifyAddressHistory.one => 1,
      SendVerifyAddressHistory.many => 12,
    },
    glyphShowcaseAddress: content == SendVerifyAddressContent.glyphShowcase,
  );
}

String sendVerifyAddressRecipientLabel(SendVerifyAddressRecipient recipient) {
  return switch (recipient) {
    SendVerifyAddressRecipient.unknown => 'Unknown address',
    SendVerifyAddressRecipient.savedContact => 'Saved contact',
  };
}

String sendVerifyAddressKindLabel(SendVerifyAddressKind kind) {
  return switch (kind) {
    SendVerifyAddressKind.shielded => 'Shielded',
    SendVerifyAddressKind.transparent => 'Transparent',
    SendVerifyAddressKind.external => 'Other chain',
  };
}

String sendVerifyAddressHistoryLabel(SendVerifyAddressHistory history) {
  return switch (history) {
    SendVerifyAddressHistory.hidden => 'Hidden',
    SendVerifyAddressHistory.one => 'One',
    SendVerifyAddressHistory.many => 'Twelve',
  };
}

String sendVerifyAddressContentLabel(SendVerifyAddressContent content) {
  return switch (content) {
    SendVerifyAddressContent.sample => 'Sample',
    SendVerifyAddressContent.glyphShowcase => 'O / 0 showcase',
  };
}

/// The mobile viewer of the same address, as the mobile send review and the
/// activity receipt open it.
///
/// The sheet's header takes its title and leading from the caller, so the
/// modal's address-kind and previous-transaction axes have nothing to drive
/// here and are not registered on this layout.
Widget _sendVerifyAddressMobileCase(
  BuildContext context, {
  required SendVerifyAddressRecipient recipient,
}) {
  final content = wbStateKnob<SendVerifyAddressContent>(
    context,
    label: 'Address',
    options: SendVerifyAddressContent.values,
    labelBuilder: sendVerifyAddressContentLabel,
  );
  return mobileAddressVerifySheetFixture(
    knownContact: recipient == SendVerifyAddressRecipient.savedContact,
    glyphShowcaseAddress: content == SendVerifyAddressContent.glyphShowcase,
  );
}

/// Which pool the overlay's recipient address belongs to.
enum SendVerifyOverlayKind { shielded, transparent }

Widget buildSendVerifyAddressOverlayGalleryCase(BuildContext context) {
  final recipient = wbStateKnob<SendVerifyOverlayRecipient>(
    context,
    label: 'Recipient',
    options: SendVerifyOverlayRecipient.values,
    labelBuilder: sendVerifyOverlayRecipientLabel,
  );
  final kind = wbStateKnob<SendVerifyOverlayKind>(
    context,
    label: 'Address kind',
    options: SendVerifyOverlayKind.values,
    labelBuilder: sendVerifyOverlayKindLabel,
  );
  return sendVerifyAddressOverlayFixture(
    recipient: recipient,
    shielded: kind == SendVerifyOverlayKind.shielded,
  );
}

String sendVerifyOverlayRecipientLabel(SendVerifyOverlayRecipient recipient) {
  return switch (recipient) {
    SendVerifyOverlayRecipient.address => 'Raw address',
    SendVerifyOverlayRecipient.contact => 'Saved contact',
    SendVerifyOverlayRecipient.ownAccount => 'Own account',
  };
}

String sendVerifyOverlayKindLabel(SendVerifyOverlayKind kind) {
  return switch (kind) {
    SendVerifyOverlayKind.shielded => 'Shielded',
    SendVerifyOverlayKind.transparent => 'Transparent',
  };
}

// --- Sapling params --------------------------------------------------------

/// The 50MB proving-parameter download prompt the send review, send status and
/// Keystone sign screens raise before a Sapling-bound transaction.
Widget buildSendSaplingParamsGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return saplingParamsPromptFixture(mobile: layout == WbLayout.mobile);
}

// --- Payment request card --------------------------------------------------

Widget buildSendPaymentRequestGalleryCase(BuildContext context) {
  // No `WbLaneOnly`: `PaymentRequestSurface` takes its form factor as a
  // parameter rather than from `kAppFormFactor`, so the off-lane preview is
  // the right arrangement with this lane's typography.
  final layout = wbLayoutKnob(context);
  final request = wbStateKnob<PaymentRequestFixture>(
    context,
    label: 'Request',
    options: PaymentRequestFixture.values,
    labelBuilder: sendPaymentRequestFixtureLabel,
  );
  final expansion = wbStateKnob<PaymentRequestExpansion>(
    context,
    label: 'Expanded',
    options: PaymentRequestExpansion.values,
    labelBuilder: sendPaymentRequestExpansionLabel,
  );
  final largeText = wbBoolKnob(context, label: 'Text scale 1.5x');
  final rtl = wbBoolKnob(context, label: 'RTL mirror');
  return paymentRequestFixture(
    fixture: request,
    mobile: layout == WbLayout.mobile,
    expansion: expansion,
    textScale: largeText ? 1.5 : 1,
    textDirection: rtl ? TextDirection.rtl : null,
  );
}

String sendPaymentRequestFixtureLabel(PaymentRequestFixture fixture) {
  return switch (fixture) {
    PaymentRequestFixture.full => 'Full',
    PaymentRequestFixture.minimal => 'Minimal',
    PaymentRequestFixture.longValues => 'Long values',
    PaymentRequestFixture.checking => 'Checking',
    PaymentRequestFixture.invalidAddress => 'Invalid address',
    PaymentRequestFixture.insufficientFunds => 'Not enough ZEC',
    PaymentRequestFixture.syncing => 'Syncing',
    PaymentRequestFixture.syncStalled => 'Syncing stalled',
    PaymentRequestFixture.failed => 'Check failed',
    PaymentRequestFixture.replaced => 'Replaced notice',
    PaymentRequestFixture.transparent => 'Transparent recipient',
    PaymentRequestFixture.contact => 'Saved contact',
    PaymentRequestFixture.ownAccount => 'Own account',
    PaymentRequestFixture.noteOnly => 'Note without message',
    PaymentRequestFixture.requesterNameOnly => 'Name without note',
    PaymentRequestFixture.whitespaceMemo => 'Whitespace memo',
    PaymentRequestFixture.noAmount => 'No amount',
  };
}

String sendPaymentRequestExpansionLabel(PaymentRequestExpansion expansion) {
  return switch (expansion) {
    PaymentRequestExpansion.none => 'Collapsed',
    PaymentRequestExpansion.address => 'Address',
    PaymentRequestExpansion.message => 'Message',
  };
}

// --- Send screen, mobile wizard steps --------------------------------------
//
// One step each of the single mobile send screen, selected by the `Step` knob
// of `buildSendScreenGalleryCase`.

Widget _sendScreenMobileRecipient(BuildContext context) {
  final address = wbStateKnob<MobileSendRecipientAddressCase>(
    context,
    label: 'Address',
    options: MobileSendRecipientAddressCase.values,
    labelBuilder: sendMobileRecipientAddressLabel,
  );
  final contacts = wbStateKnob<SendMobileContacts>(
    context,
    label: 'Contacts',
    options: SendMobileContacts.values,
    labelBuilder: sendMobileContactsLabel,
  );
  final field = wbStateKnob<SendMobileField>(
    context,
    label: 'Field',
    options: SendMobileField.values,
    labelBuilder: sendMobileFieldLabel,
  );
  return mobileSendFlowFixture(
    initialRecipient: mobileSendRecipientAddressFor(address),
    contacts: contacts == SendMobileContacts.listed
        ? kMobileSendPreviewContacts
        : const [],
    initialRecipientFocused: field == SendMobileField.focused,
  );
}

/// Whether the address book has anything to offer under the field.
enum SendMobileContacts { none, listed }

/// Whether the address field holds the keyboard.
enum SendMobileField { idle, focused }

String sendMobileRecipientAddressLabel(MobileSendRecipientAddressCase address) {
  return switch (address) {
    MobileSendRecipientAddressCase.empty => 'Empty',
    MobileSendRecipientAddressCase.unified => 'Unified',
    MobileSendRecipientAddressCase.sapling => 'Sapling',
    MobileSendRecipientAddressCase.transparent => 'Transparent',
    MobileSendRecipientAddressCase.tex => 'TEX',
    MobileSendRecipientAddressCase.invalid => 'Invalid',
    MobileSendRecipientAddressCase.wrongNetwork => 'Wrong network',
  };
}

String sendMobileContactsLabel(SendMobileContacts contacts) {
  return switch (contacts) {
    SendMobileContacts.none => 'None',
    SendMobileContacts.listed => 'Listed',
  };
}

String sendMobileFieldLabel(SendMobileField field) {
  return switch (field) {
    SendMobileField.idle => 'Idle',
    SendMobileField.focused => 'Focused',
  };
}

Widget _sendScreenMobileAmount(BuildContext context) {
  final amount = wbStateKnob<MobileSendAmountCase>(
    context,
    label: 'Amount',
    options: MobileSendAmountCase.values,
    labelBuilder: sendMobileAmountLabel,
  );
  final unit = wbStateKnob<MobileSendAmountInputMode>(
    context,
    label: 'Unit',
    options: MobileSendAmountInputMode.values,
    labelBuilder: sendMobileAmountUnitLabel,
  );
  final usd = unit == MobileSendAmountInputMode.usd;
  return mobileSendFlowFixture(
    initialRecipient: kMobileSendUnifiedAddress,
    initialAmount: switch (amount) {
      MobileSendAmountCase.empty => '',
      MobileSendAmountCase.entered => usd ? '12' : '24.312',
      MobileSendAmountCase.notEnough => '243.12',
    },
    initialFiatAmount: !usd
        ? null
        : switch (amount) {
            MobileSendAmountCase.empty => '',
            MobileSendAmountCase.entered => '120.12',
            MobileSendAmountCase.notEnough => '17018.40',
          },
    initialAmountInputMode: unit,
    initialAmountError: amount == MobileSendAmountCase.notEnough
        ? 'Not enough ZEC'
        : null,
    initialAmountReady: amount == MobileSendAmountCase.entered,
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

String sendMobileAmountLabel(MobileSendAmountCase amount) {
  return switch (amount) {
    MobileSendAmountCase.empty => 'Empty',
    MobileSendAmountCase.entered => 'Entered',
    MobileSendAmountCase.notEnough => 'Not enough ZEC',
  };
}

String sendMobileAmountUnitLabel(MobileSendAmountInputMode unit) {
  return switch (unit) {
    MobileSendAmountInputMode.zec => 'ZEC',
    MobileSendAmountInputMode.usd => 'USD',
  };
}

Widget _sendScreenMobileReview(BuildContext context) {
  final fee = wbStateKnob<MobileSendReviewFeeCase>(
    context,
    label: 'Fee',
    options: MobileSendReviewFeeCase.values,
    labelBuilder: sendMobileReviewFeeLabel,
  );
  final identity = wbStateKnob<MobileSendReviewIdentityCase>(
    context,
    label: 'Recipient identity',
    options: MobileSendReviewIdentityCase.values,
    labelBuilder: sendMobileReviewIdentityLabel,
  );
  final request = wbStateKnob<MobileSendReviewRequestCase>(
    context,
    label: 'Payment request',
    options: MobileSendReviewRequestCase.values,
    labelBuilder: sendMobileReviewRequestLabel,
  );
  final memo = wbBoolKnob(context, label: 'Message');
  final refreshes = fee != MobileSendReviewFeeCase.ready;
  return mobileSendFlowFixture(
    ownAccountAddresses: identity == MobileSendReviewIdentityCase.ownAccount
        ? kMobileSendOwnAccountAddresses
        : const {},
    initialRecipient: kMobileSendUnifiedAddress,
    initialAmount: '123.12',
    initialReview: true,
    refreshReviewFeeOnInit: refreshes,
    estimateFee: _sendScreenMobileReviewFeeEstimator(fee),
    initialMemo: memo ? 'Zcash is a privacy-focused digital currency' : null,
    initialContactLabel: identity == MobileSendReviewIdentityCase.contact
        ? 'Contact label'
        : null,
    initialContactPictureId: identity == MobileSendReviewIdentityCase.contact
        ? 'pfp-02'
        : null,
    isPaymentRequest: request != MobileSendReviewRequestCase.none,
    paymentRequestLabel: request == MobileSendReviewRequestCase.none
        ? null
        : 'Blue Door Coffee',
    requestedAmountZatoshi: switch (request) {
      MobileSendReviewRequestCase.none => null,
      MobileSendReviewRequestCase.matching => BigInt.from(12_312_000_000),
      MobileSendReviewRequestCase.differentAmount => BigInt.from(5_000_000),
    },
  );
}

MobileSendFeeEstimator _sendScreenMobileReviewFeeEstimator(
  MobileSendReviewFeeCase fee,
) {
  return ({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) {
    return switch (fee) {
      MobileSendReviewFeeCase.ready => Future<BigInt>.value(BigInt.from(10000)),
      MobileSendReviewFeeCase.refreshing => Completer<BigInt>().future,
      MobileSendReviewFeeCase.notEnough => Future<BigInt>.error(
        Exception('InsufficientFunds'),
      ),
      MobileSendReviewFeeCase.syncing => Future<BigInt>.error(
        Exception('Wallet sync is still finishing'),
      ),
      MobileSendReviewFeeCase.unavailable => Future<BigInt>.error(
        Exception('Fee estimation failed'),
      ),
    };
  };
}

String sendMobileReviewFeeLabel(MobileSendReviewFeeCase fee) {
  return switch (fee) {
    MobileSendReviewFeeCase.ready => 'Ready',
    MobileSendReviewFeeCase.refreshing => 'Refreshing',
    MobileSendReviewFeeCase.notEnough => 'Not enough ZEC',
    MobileSendReviewFeeCase.syncing => 'Sync in progress',
    MobileSendReviewFeeCase.unavailable => 'Unavailable, retry',
  };
}

String sendMobileReviewIdentityLabel(MobileSendReviewIdentityCase identity) {
  return switch (identity) {
    MobileSendReviewIdentityCase.address => 'Address',
    MobileSendReviewIdentityCase.contact => 'Saved contact',
    MobileSendReviewIdentityCase.ownAccount => 'Own account',
  };
}

String sendMobileReviewRequestLabel(MobileSendReviewRequestCase request) {
  return switch (request) {
    MobileSendReviewRequestCase.none => 'Not a request',
    MobileSendReviewRequestCase.matching => 'Requested amount',
    MobileSendReviewRequestCase.differentAmount => 'Amount edited',
  };
}

/// Camera states the send scan fixtures cover; `AddressQrCameraStatus
/// .unavailable` has no fixture, so it is deliberately absent.
enum SendScanCamera { active, loading, requesting, denied }

/// Why the last scan was refused; the card only prints this over a live
/// camera, in place of its caption.
enum SendScanOutcome { none, notZcash, wrongNetwork }

Widget _sendScreenMobileScan(BuildContext context) {
  final camera = wbStateKnob<SendScanCamera>(
    context,
    label: 'Camera',
    options: SendScanCamera.values,
    labelBuilder: sendScanCameraLabel,
  );
  final outcome = wbStateKnob<SendScanOutcome>(
    context,
    label: 'Scan outcome',
    options: SendScanOutcome.values,
    labelBuilder: sendScanOutcomeLabel,
  );
  if (outcome == SendScanOutcome.none) {
    return switch (camera) {
      SendScanCamera.active => buildMobileSendQrScanUseCase(context),
      SendScanCamera.loading => buildMobileSendQrScanLoadingUseCase(context),
      SendScanCamera.requesting => buildMobileSendQrScanRequestingUseCase(
        context,
      ),
      SendScanCamera.denied => buildMobileSendQrScanDeniedUseCase(context),
    };
  }
  return mobileSendQrScanFixture(
    status: switch (camera) {
      SendScanCamera.active => AddressQrCameraStatus.active,
      SendScanCamera.loading => AddressQrCameraStatus.loading,
      SendScanCamera.requesting => AddressQrCameraStatus.requesting,
      SendScanCamera.denied => AddressQrCameraStatus.denied,
    },
    error: outcome == SendScanOutcome.notZcash
        ? kMobileSendScanNotZcashMessage
        : kMobileSendScanWrongNetworkMessage,
  );
}

String sendScanCameraLabel(SendScanCamera camera) {
  return switch (camera) {
    SendScanCamera.active => 'Active',
    SendScanCamera.loading => 'Loading',
    SendScanCamera.requesting => 'Requesting',
    SendScanCamera.denied => 'Denied',
  };
}

String sendScanOutcomeLabel(SendScanOutcome outcome) {
  return switch (outcome) {
    SendScanOutcome.none => 'None',
    SendScanOutcome.notZcash => 'Not a Zcash address',
    SendScanOutcome.wrongNetwork => 'Wrong network',
  };
}

// --- Send status screen, mobile --------------------------------------------

/// Where the mobile receipt's broadcast has got to.
enum SendMobileStatusPhase { sending, queued, sent, failed }

/// Whether the queued receipt prints its own copy or the server's.
enum SendMobileStatusMessage { standard, serverSupplied }

Widget _sendStatusScreenMobileCase(BuildContext context) {
  final phase = wbStateKnob<SendMobileStatusPhase>(
    context,
    label: 'Phase',
    options: SendMobileStatusPhase.values,
    labelBuilder: sendMobileStatusPhaseLabel,
  );
  final message = wbStateKnob<SendMobileStatusMessage>(
    context,
    label: 'Status message',
    options: SendMobileStatusMessage.values,
    labelBuilder: sendMobileStatusMessageLabel,
  );
  final hardware = wbBoolKnob(context, label: 'Keystone account');
  return mobileSendStatusFixture(
    phase: switch (phase) {
      SendMobileStatusPhase.sending => null,
      SendMobileStatusPhase.queued => SendBroadcastPhase.pendingBroadcast,
      SendMobileStatusPhase.sent => SendBroadcastPhase.succeeded,
      SendMobileStatusPhase.failed => SendBroadcastPhase.failed,
    },
    statusMessage: message == SendMobileStatusMessage.serverSupplied
        ? kMobileSendStatusServerMessage
        : null,
    hardwareAccount: hardware,
  );
}

String sendMobileStatusPhaseLabel(SendMobileStatusPhase phase) {
  return switch (phase) {
    SendMobileStatusPhase.sending => 'Sending',
    SendMobileStatusPhase.queued => 'Queued to send',
    SendMobileStatusPhase.sent => 'Sent',
    SendMobileStatusPhase.failed => 'Failed',
  };
}

String sendMobileStatusMessageLabel(SendMobileStatusMessage message) {
  return switch (message) {
    SendMobileStatusMessage.standard => 'Default',
    SendMobileStatusMessage.serverSupplied => 'Server supplied',
  };
}

// --- Mobile Keystone sign --------------------------------------------------

/// How many device approvals this send needs; a TEX recipient is the only
/// address type that splits into two rounds.
///
/// The QR page heads every round 'Step 1/2' (its own two steps, scan then
/// sign), so the round title only reaches the screen as the failure title.
enum SendMobileKeystoneRound { single, texTwoRounds }

/// Whether the preparation is still running or already failed.
enum SendMobileKeystonePreparation { preparing, failed }

Widget buildSendMobileKeystoneSignGalleryCase(BuildContext context) {
  final round = wbStateKnob<SendMobileKeystoneRound>(
    context,
    label: 'Round',
    options: SendMobileKeystoneRound.values,
    labelBuilder: sendMobileKeystoneRoundLabel,
  );
  final preparation = wbStateKnob<SendMobileKeystonePreparation>(
    context,
    label: 'Preparation',
    options: SendMobileKeystonePreparation.values,
    labelBuilder: sendMobileKeystonePreparationLabel,
  );
  final failure = wbStateKnob<MobileKeystoneSignFailure>(
    context,
    label: 'Error',
    options: MobileKeystoneSignFailure.values,
    labelBuilder: sendMobileKeystoneFailureLabel,
  );
  return mobileKeystoneSignFixture(
    texSend: round == SendMobileKeystoneRound.texTwoRounds,
    failure: preparation == SendMobileKeystonePreparation.failed
        ? failure
        : null,
  );
}

String sendMobileKeystoneRoundLabel(SendMobileKeystoneRound round) {
  return switch (round) {
    SendMobileKeystoneRound.single => 'Single transaction',
    SendMobileKeystoneRound.texTwoRounds => '1 of 2 (TEX)',
  };
}

String sendMobileKeystonePreparationLabel(
  SendMobileKeystonePreparation preparation,
) {
  return switch (preparation) {
    SendMobileKeystonePreparation.preparing => 'Preparing',
    SendMobileKeystonePreparation.failed => 'Failed',
  };
}

String sendMobileKeystoneFailureLabel(MobileKeystoneSignFailure failure) {
  return switch (failure) {
    MobileKeystoneSignFailure.expiredProposal => 'Expired',
    MobileKeystoneSignFailure.batchSigning => 'Batch signing',
    MobileKeystoneSignFailure.provingParameters => 'Proving parameters',
    MobileKeystoneSignFailure.generic => 'Generic',
  };
}

// --- Send screen -----------------------------------------------------------
//
// The desktop branch here, the desktop review and the desktop status screen are
// `WbLaneOnly(desktop)`: they mount the real `AppMainSidebar`, which overflows
// the 1080x720 desktop window under mobile typography, so the off-lane render
// is wrong rather than merely approximate.

/// Which step of the mobile send wizard is on screen. The desktop composer
/// holds the recipient, the amount and its scanner in one pane, so the axis
/// exists on the mobile layout only.
enum SendScreenMobileStep { recipient, amount, review, qrScan }

String sendScreenMobileStepLabel(SendScreenMobileStep step) {
  return switch (step) {
    SendScreenMobileStep.recipient => 'Recipient',
    SendScreenMobileStep.amount => 'Amount',
    SendScreenMobileStep.review => 'Review',
    SendScreenMobileStep.qrScan => 'QR scan',
  };
}

/// What `walletProvider` hands the composer pane.
enum SendScreenWallet { ready, loading, failed }

/// What the composer has left to spend.
enum SendScreenBalance { funded, empty, ironwoodResume }

/// What the address field holds.
enum SendScreenRecipient { empty, validAddress, contactSuggestions }

/// What the amount field holds.
enum SendScreenAmount { empty, entered, overBalance }

/// Whether the ZEC price behind the conversion line has arrived.
enum SendScreenPrice { loaded, loading }

/// What the address book offers the composer.
enum SendScreenContacts { listed, none }

/// Whether the Contacts button has been used.
enum SendScreenContactPicker { closed, open }

Widget buildSendScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  if (layout == WbLayout.mobile) {
    return WbFrame(layout: layout, child: _sendScreenMobileCase(context));
  }
  return _sendScreenDesktopCase(context);
}

/// The mobile wizard: only the selected step's axes are registered, which
/// widgetbook re-reads on every build, so the panel follows the step.
Widget _sendScreenMobileCase(BuildContext context) {
  final step = wbStateKnob<SendScreenMobileStep>(
    context,
    label: 'Step',
    options: SendScreenMobileStep.values,
    labelBuilder: sendScreenMobileStepLabel,
  );
  return switch (step) {
    SendScreenMobileStep.recipient => _sendScreenMobileRecipient(context),
    SendScreenMobileStep.amount => _sendScreenMobileAmount(context),
    SendScreenMobileStep.review => _sendScreenMobileReview(context),
    SendScreenMobileStep.qrScan => _sendScreenMobileScan(context),
  };
}

Widget _sendScreenDesktopCase(BuildContext context) {
  final wallet = wbStateKnob<SendScreenWallet>(
    context,
    label: 'Wallet',
    options: SendScreenWallet.values,
    labelBuilder: sendScreenWalletLabel,
  );
  final balance = wbStateKnob<SendScreenBalance>(
    context,
    label: 'Balance',
    options: SendScreenBalance.values,
    labelBuilder: sendScreenBalanceLabel,
  );
  final privacyMode = wbBoolKnob(context, label: 'Privacy mode');
  final recipient = wbStateKnob<SendScreenRecipient>(
    context,
    label: 'Recipient',
    options: SendScreenRecipient.values,
    labelBuilder: sendScreenRecipientLabel,
  );
  final amount = wbStateKnob<SendScreenAmount>(
    context,
    label: 'Amount',
    options: SendScreenAmount.values,
    labelBuilder: sendScreenAmountLabel,
  );
  final contactPicker = wbStateKnob<SendScreenContactPicker>(
    context,
    label: 'Contact picker',
    options: SendScreenContactPicker.values,
    labelBuilder: sendScreenContactPickerLabel,
  );
  final price = amount == SendScreenAmount.empty
      ? SendScreenPrice.loaded
      : wbStateKnob<SendScreenPrice>(
          context,
          label: 'Price',
          options: SendScreenPrice.values,
          labelBuilder: sendScreenPriceLabel,
        );
  final contacts = contactPicker == SendScreenContactPicker.open
      ? wbStateKnob<SendScreenContacts>(
          context,
          label: 'Contacts',
          options: SendScreenContacts.values,
          labelBuilder: sendScreenContactsLabel,
        )
      : SendScreenContacts.listed;
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: sendScreenFixture(
      walletLoading: wallet == SendScreenWallet.loading,
      walletFailed: wallet == SendScreenWallet.failed,
      emptyBalance: balance == SendScreenBalance.empty,
      ironwoodResume: balance == SendScreenBalance.ironwoodResume,
      privacyMode: privacyMode,
      recipientPrefilled: recipient == SendScreenRecipient.validAddress,
      contactSearch: recipient == SendScreenRecipient.contactSuggestions,
      amountText: switch (amount) {
        SendScreenAmount.empty => null,
        SendScreenAmount.entered => kSendScreenFixtureAmountText,
        SendScreenAmount.overBalance => kSendScreenFixtureOverBalanceAmountText,
      },
      priceLoading: price == SendScreenPrice.loading,
      listContacts: contacts == SendScreenContacts.listed,
      contactPickerOpen: contactPicker == SendScreenContactPicker.open,
      simulateResult: true,
    ),
  );
}

String sendScreenRecipientLabel(SendScreenRecipient recipient) {
  return switch (recipient) {
    SendScreenRecipient.empty => 'Empty',
    SendScreenRecipient.validAddress => 'Valid address',
    SendScreenRecipient.contactSuggestions => 'Contact suggestions',
  };
}

String sendScreenAmountLabel(SendScreenAmount amount) {
  return switch (amount) {
    SendScreenAmount.empty => 'Empty',
    SendScreenAmount.entered => 'Entered',
    SendScreenAmount.overBalance => 'More than the balance',
  };
}

String sendScreenPriceLabel(SendScreenPrice price) {
  return switch (price) {
    SendScreenPrice.loaded => 'Loaded',
    SendScreenPrice.loading => 'Loading',
  };
}

String sendScreenContactsLabel(SendScreenContacts contacts) {
  return switch (contacts) {
    SendScreenContacts.listed => 'Listed',
    SendScreenContacts.none => 'None',
  };
}

String sendScreenContactPickerLabel(SendScreenContactPicker picker) {
  return switch (picker) {
    SendScreenContactPicker.closed => 'Closed',
    SendScreenContactPicker.open => 'Open',
  };
}

String sendScreenWalletLabel(SendScreenWallet wallet) {
  return switch (wallet) {
    SendScreenWallet.ready => 'Ready',
    SendScreenWallet.loading => 'Loading',
    SendScreenWallet.failed => 'Failed to load',
  };
}

String sendScreenBalanceLabel(SendScreenBalance balance) {
  return switch (balance) {
    SendScreenBalance.funded => 'Funded',
    SendScreenBalance.empty => 'Empty',
    SendScreenBalance.ironwoodResume => 'Ironwood resume',
  };
}

// --- Desktop send review ---------------------------------------------------

/// Who the review names as the recipient; `Own account` is the self-transfer
/// match `ownAccountAddressesProvider` resolves.
enum SendReviewScreenRecipient { address, contact, ownAccount }

/// Which pool the recipient address belongs to.
enum SendReviewScreenPool { shielded, transparent }

/// Whether this send answers a ZIP-321 request, and whether the amount was
/// edited away from the one the request named.
enum SendReviewScreenRequest { none, matching, edited }

Widget buildSendReviewScreenGalleryCase(BuildContext context) {
  // Donation renders `DonationReviewContentView`, which has no recipient,
  // request or message row — those three knobs describe the send flow.
  final flow = wbStateKnob<SendFlowKind>(
    context,
    label: 'Flow',
    options: SendFlowKind.values,
    labelBuilder: sendReviewScreenFlowLabel,
  );
  final hardware = wbBoolKnob(context, label: 'Keystone account');
  final recipient = wbStateKnob<SendReviewScreenRecipient>(
    context,
    label: 'Recipient',
    options: SendReviewScreenRecipient.values,
    labelBuilder: sendReviewScreenRecipientLabel,
  );
  final pool = wbStateKnob<SendReviewScreenPool>(
    context,
    label: 'Recipient pool',
    options: SendReviewScreenPool.values,
    labelBuilder: sendReviewScreenPoolLabel,
  );
  final request = wbStateKnob<SendReviewScreenRequest>(
    context,
    label: 'Payment request',
    options: SendReviewScreenRequest.values,
    labelBuilder: sendReviewScreenRequestLabel,
  );
  final message = wbBoolKnob(context, label: 'Message');
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: sendReviewScreenFixture(
      flowKind: flow,
      hardwareAccount: hardware,
      contactRecipient: recipient == SendReviewScreenRecipient.contact,
      ownAccountRecipient: recipient == SendReviewScreenRecipient.ownAccount,
      transparentRecipient: pool == SendReviewScreenPool.transparent,
      paymentRequest: request != SendReviewScreenRequest.none,
      differingRequestedAmount: request == SendReviewScreenRequest.edited,
      memo: message,
    ),
  );
}

String sendReviewScreenFlowLabel(SendFlowKind flow) {
  return switch (flow) {
    SendFlowKind.send => 'Send',
    SendFlowKind.donation => 'Donation',
  };
}

String sendReviewScreenRecipientLabel(SendReviewScreenRecipient recipient) {
  return switch (recipient) {
    SendReviewScreenRecipient.address => 'Address',
    SendReviewScreenRecipient.contact => 'Saved contact',
    SendReviewScreenRecipient.ownAccount => 'Own account',
  };
}

String sendReviewScreenPoolLabel(SendReviewScreenPool pool) {
  return switch (pool) {
    SendReviewScreenPool.shielded => 'Shielded',
    SendReviewScreenPool.transparent => 'Transparent',
  };
}

String sendReviewScreenRequestLabel(SendReviewScreenRequest request) {
  return switch (request) {
    SendReviewScreenRequest.none => 'Not a request',
    SendReviewScreenRequest.matching => 'Requested amount',
    SendReviewScreenRequest.edited => 'Amount edited',
  };
}

// --- Send status screen ----------------------------------------------------

/// Where the receipt's broadcast has got to.
enum SendStatusScreenPhase { sending, queued, sent, failed }

/// The extra line under the receipt rows.
enum SendStatusScreenNotice { none, broadcastGuidance, failureReason }

Widget buildSendStatusScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  if (layout == WbLayout.mobile) return _sendStatusScreenMobileCase(context);
  return _sendStatusScreenDesktopCase(context);
}

/// The desktop receipt. Its notice and Tx ID rows have no mobile counterpart,
/// and the mobile receipt's server-supplied copy no desktop one, so the two
/// layouts register their own axes either side of the shared phase.
Widget _sendStatusScreenDesktopCase(BuildContext context) {
  final phase = wbStateKnob<SendStatusScreenPhase>(
    context,
    label: 'Phase',
    options: SendStatusScreenPhase.values,
    labelBuilder: sendStatusScreenPhaseLabel,
  );
  final hardware = wbBoolKnob(context, label: 'Keystone account');
  final transactionHash = wbBoolKnob(context, label: 'Transaction hash');
  // Guidance only shows while the send can still land; a reason only shows
  // once it failed, so the two never compete for the same line.
  final notice = wbStateKnob<SendStatusScreenNotice>(
    context,
    label: 'Notice',
    options: SendStatusScreenNotice.values,
    labelBuilder: sendStatusScreenNoticeLabel,
  );
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: sendStatusScreenFixture(
      phase: switch (phase) {
        SendStatusScreenPhase.sending => null,
        SendStatusScreenPhase.queued => SendBroadcastPhase.pendingBroadcast,
        SendStatusScreenPhase.sent => SendBroadcastPhase.succeeded,
        SendStatusScreenPhase.failed => SendBroadcastPhase.failed,
      },
      hardwareAccount: hardware,
      transactionHash: transactionHash,
      statusMessage: notice == SendStatusScreenNotice.broadcastGuidance
          ? kSendStatusScreenBroadcastGuidance
          : null,
      failureReason: notice == SendStatusScreenNotice.failureReason
          ? kSendStatusScreenFailureReason
          : null,
    ),
  );
}

String sendStatusScreenPhaseLabel(SendStatusScreenPhase phase) {
  return switch (phase) {
    SendStatusScreenPhase.sending => 'Sending',
    SendStatusScreenPhase.queued => 'Queued to send',
    SendStatusScreenPhase.sent => 'Sent',
    SendStatusScreenPhase.failed => 'Failed',
  };
}

String sendStatusScreenNoticeLabel(SendStatusScreenNotice notice) {
  return switch (notice) {
    SendStatusScreenNotice.none => 'None',
    SendStatusScreenNotice.broadcastGuidance => 'Broadcast guidance',
    SendStatusScreenNotice.failureReason => 'Failure reason',
  };
}
