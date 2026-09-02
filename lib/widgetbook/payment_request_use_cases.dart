// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/send/widgets/payment_request_card.dart';
import '../src/features/send/widgets/payment_request_surface.dart';

const _sampleAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

/// A transparent (`t1…`) recipient — the pool the "To" badge has to call out,
/// because paying it is the one detail on this card the review step cannot
/// undo for you.
const _transparentAddress = 't1PZ4vMuLdt2wRfDGGKS1qXfBpJt5CJHhNz';

const _sampleMemo =
    'Table 4 — two flat whites and a pastry. Thanks for stopping by, '
    'see you next week.';

const _sampleNote = 'Saved from the invoice link you opened.';

/// 80 characters, the worst realistic label a link can carry.
const _longLabel =
    'Shielded Coffee Roasters International Wholesale and Retail Trading '
    'Company Ltd';

/// A 512-byte memo — the Zcash protocol maximum.
final _longMemo = () {
  const paragraph =
      'Invoice 2026-0917. Settlement for the September wholesale order, '
      'including the two pallets held over from August and the revised '
      'delivery surcharge we agreed on the call. Payment in ZEC is due '
      'within seven days; the reference above must stay attached to the '
      'transaction or reconciliation will miss it. Questions go to the '
      'accounts desk, not to the shop. ';
  final buffer = StringBuffer();
  while (buffer.length < 512) {
    buffer.write(paragraph);
  }
  return buffer.toString().substring(0, 512).trim();
}();

const _longNote =
    'This link replaced an earlier one from the same sender, and the amount '
    'was recalculated against the exchange rate quoted at the time the '
    'invoice was issued rather than the rate showing right now.';

const _fullRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Blue Door Coffee',
  amountZecText: '0.5 ZEC',
  fiatText: r'$35.00',
  address: _sampleAddress,
  memo: _sampleMemo,
  note: _sampleNote,
  spendableText: '0.21 ZEC',
);

const _minimalRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  amountZecText: '0.5 ZEC',
  address: _sampleAddress,
);

final _longValuesRequest = PaymentRequestView(
  source: PaymentRequestSource.qrCode,
  requesterLabel: _longLabel,
  amountZecText: '1234.567891234567 ZEC',
  fiatText: r'$86,419.075308642 (indicative, refreshed a moment ago)',
  address: _sampleAddress,
  memo: _longMemo,
  note: _longNote,
);

PaymentRequestView _statusRequest(
  PaymentRequestStatus status, {
  String? statusMessage,
}) {
  return PaymentRequestView(
    source: _fullRequest.source,
    requesterLabel: _fullRequest.requesterLabel,
    amountZecText: _fullRequest.amountZecText,
    fiatText: _fullRequest.fiatText,
    address: _fullRequest.address,
    memo: _fullRequest.memo,
    note: _fullRequest.note,
    spendableText: _fullRequest.spendableText,
    status: status,
    statusMessage: statusMessage,
  );
}

/// A check that could not complete. Every real failure overrides the default
/// message with its own reason, so the gallery shows one that does.
const _failedStatusMessage =
    "Couldn't check this request — open Edit to review the details";

const _replacedRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Blue Door Coffee',
  amountZecText: '0.75 ZEC',
  fiatText: r'$52.50',
  address: _sampleAddress,
  memo: _sampleMemo,
  replacedNotice: true,
);

/// A link that carried no `amount`. There is no hero to render and nothing
/// to review yet, so the primary becomes the edit action.
const _noAmountRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Blue Door Coffee',
  address: _sampleAddress,
  memo: _sampleMemo,
);

/// Transparent recipient — the badge under the address is the only place the
/// pool is stated.
const _transparentRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Hardware supplier',
  amountZecText: '2.4 ZEC',
  fiatText: r'$168.00',
  address: _transparentAddress,
  note: 'Transparent payout address from the supplier portal.',
);

/// The recipient is saved in the address book: the contact's name and avatar
/// take the "To" headline and the address drops to the sub-line.
const _contactRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Blue Door Coffee',
  amountZecText: '0.5 ZEC',
  fiatText: r'$35.00',
  address: _sampleAddress,
  memo: _sampleMemo,
  recipientIdentity: PaymentRequestRecipientIdentity.contact(
    name: 'Blue Door Coffee',
    profilePictureId: 'pfp-03',
  ),
);

/// The link is asking the user to pay one of their own accounts. Same shape
/// as the contact case plus the one muted line that says which relationship
/// this is — the card's only way to tell the user that.
const _ownAccountRequest = PaymentRequestView(
  source: PaymentRequestSource.qrCode,
  amountZecText: '1.25 ZEC',
  fiatText: r'$87.50',
  address: _sampleAddress,
  note: 'Moving funds between your own accounts.',
  recipientIdentity: PaymentRequestRecipientIdentity.ownAccount(
    name: 'Savings',
    profilePictureId: 'pfp-07',
  ),
);

/// Note without a message — the pair is otherwise only ever seen together.
const _noteOnlyRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Blue Door Coffee',
  amountZecText: '0.5 ZEC',
  fiatText: r'$35.00',
  address: _sampleAddress,
  note: _sampleNote,
);

// ─── Desktop ─────────────────────────────────────────────────────────

Widget buildPaymentRequestFullUseCase(BuildContext context) =>
    _desktop(_fullRequest);

Widget buildPaymentRequestAddressExpandedUseCase(BuildContext context) =>
    _desktop(_fullRequest, addressExpanded: true);

Widget buildPaymentRequestMinimalUseCase(BuildContext context) =>
    _desktop(_minimalRequest);

Widget buildPaymentRequestLongValuesUseCase(BuildContext context) =>
    _desktop(_longValuesRequest);

Widget buildPaymentRequestLongValuesExpandedUseCase(BuildContext context) =>
    _desktop(_longValuesRequest, messageExpanded: true);

Widget buildPaymentRequestCheckingUseCase(BuildContext context) =>
    _desktop(_statusRequest(PaymentRequestStatus.checking));

Widget buildPaymentRequestInvalidAddressUseCase(BuildContext context) =>
    _desktop(_statusRequest(PaymentRequestStatus.invalidAddress));

Widget buildPaymentRequestInsufficientUseCase(BuildContext context) =>
    _desktop(_statusRequest(PaymentRequestStatus.insufficientFunds));

Widget buildPaymentRequestSyncingUseCase(BuildContext context) =>
    _desktop(_statusRequest(PaymentRequestStatus.syncing));

Widget buildPaymentRequestFailedUseCase(BuildContext context) => _desktop(
  _statusRequest(
    PaymentRequestStatus.failed,
    statusMessage: _failedStatusMessage,
  ),
);

Widget buildPaymentRequestReplacedUseCase(BuildContext context) =>
    _desktop(_replacedRequest);

Widget buildPaymentRequestTransparentUseCase(BuildContext context) =>
    _desktop(_transparentRequest);

Widget buildPaymentRequestContactUseCase(BuildContext context) =>
    _desktop(_contactRequest);

Widget buildPaymentRequestOwnAccountUseCase(BuildContext context) =>
    _desktop(_ownAccountRequest);

Widget buildPaymentRequestOwnAccountExpandedUseCase(BuildContext context) =>
    _desktop(_ownAccountRequest, addressExpanded: true);

Widget buildPaymentRequestNoteOnlyUseCase(BuildContext context) =>
    _desktop(_noteOnlyRequest);

Widget buildPaymentRequestNoAmountUseCase(BuildContext context) =>
    _desktop(_noAmountRequest);

Widget buildPaymentRequestLargeTextUseCase(BuildContext context) =>
    _desktop(_fullRequest, textScale: 1.5);

Widget buildPaymentRequestRtlUseCase(BuildContext context) =>
    _desktop(_fullRequest, textDirection: TextDirection.rtl);

// ─── Mobile ──────────────────────────────────────────────────────────

Widget buildMobilePaymentRequestFullUseCase(BuildContext context) =>
    _mobile(_fullRequest);

Widget buildMobilePaymentRequestAddressExpandedUseCase(BuildContext context) =>
    _mobile(_fullRequest, addressExpanded: true);

Widget buildMobilePaymentRequestMinimalUseCase(BuildContext context) =>
    _mobile(_minimalRequest);

Widget buildMobilePaymentRequestLongValuesUseCase(BuildContext context) =>
    _mobile(_longValuesRequest);

Widget buildMobilePaymentRequestLongValuesExpandedUseCase(
  BuildContext context,
) => _mobile(_longValuesRequest, messageExpanded: true);

Widget buildMobilePaymentRequestCheckingUseCase(BuildContext context) =>
    _mobile(_statusRequest(PaymentRequestStatus.checking));

Widget buildMobilePaymentRequestInvalidAddressUseCase(BuildContext context) =>
    _mobile(_statusRequest(PaymentRequestStatus.invalidAddress));

Widget buildMobilePaymentRequestInsufficientUseCase(BuildContext context) =>
    _mobile(_statusRequest(PaymentRequestStatus.insufficientFunds));

Widget buildMobilePaymentRequestSyncingUseCase(BuildContext context) =>
    _mobile(_statusRequest(PaymentRequestStatus.syncing));

Widget buildMobilePaymentRequestFailedUseCase(BuildContext context) => _mobile(
  _statusRequest(
    PaymentRequestStatus.failed,
    statusMessage: _failedStatusMessage,
  ),
);

Widget buildMobilePaymentRequestReplacedUseCase(BuildContext context) =>
    _mobile(_replacedRequest);

Widget buildMobilePaymentRequestTransparentUseCase(BuildContext context) =>
    _mobile(_transparentRequest);

Widget buildMobilePaymentRequestContactUseCase(BuildContext context) =>
    _mobile(_contactRequest);

Widget buildMobilePaymentRequestOwnAccountUseCase(BuildContext context) =>
    _mobile(_ownAccountRequest);

Widget buildMobilePaymentRequestOwnAccountExpandedUseCase(
  BuildContext context,
) => _mobile(_ownAccountRequest, addressExpanded: true);

Widget buildMobilePaymentRequestNoteOnlyUseCase(BuildContext context) =>
    _mobile(_noteOnlyRequest);

Widget buildMobilePaymentRequestNoAmountUseCase(BuildContext context) =>
    _mobile(_noAmountRequest);

Widget buildMobilePaymentRequestLargeTextUseCase(BuildContext context) =>
    _mobile(_fullRequest, textScale: 1.5);

Widget buildMobilePaymentRequestRtlUseCase(BuildContext context) =>
    _mobile(_fullRequest, textDirection: TextDirection.rtl);

// ─── Frames ──────────────────────────────────────────────────────────

Widget _desktop(
  PaymentRequestView request, {
  double textScale = 1,
  TextDirection? textDirection,
  bool addressExpanded = false,
  bool messageExpanded = false,
}) {
  return _PaymentRequestFrame(
    // A desktop pane is the surface a payment link interrupts.
    size: const Size(AppWindowSizing.contentAreaMaxWidth + AppSpacing.xl2, 720),
    textScale: textScale,
    textDirection: textDirection,
    child: PaymentRequestSurface(
      layout: PaymentRequestLayout.desktop,
      request: request,
      initialAddressExpanded: addressExpanded,
      initialMessageExpanded: messageExpanded,
      onContinue: () {},
      onEdit: () {},
      onCancel: () {},
    ),
  );
}

Widget _mobile(
  PaymentRequestView request, {
  double textScale = 1,
  TextDirection? textDirection,
  bool addressExpanded = false,
  bool messageExpanded = false,
}) {
  return _PaymentRequestFrame(
    size: const Size(393, 852),
    textScale: textScale,
    textDirection: textDirection,
    child: PaymentRequestSurface(
      layout: PaymentRequestLayout.mobile,
      request: request,
      initialAddressExpanded: addressExpanded,
      initialMessageExpanded: messageExpanded,
      onContinue: () {},
      onEdit: () {},
      onCancel: () {},
    ),
  );
}

/// Fixed preview viewport so the modal is measured against a real screen
/// rather than the Widgetbook chrome.
///
/// [textScale] and [textDirection] exist so the two environment variants the
/// card is riskiest in — a large accessibility text size and an RTL mirror —
/// are inspectable states rather than assumptions.
class _PaymentRequestFrame extends StatelessWidget {
  const _PaymentRequestFrame({
    required this.size,
    required this.child,
    this.textScale = 1,
    this.textDirection,
  });

  final Size size;
  final Widget child;
  final double textScale;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final direction = textDirection;
    Widget framed = MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(size: size, textScaler: TextScaler.linear(textScale)),
      child: child,
    );
    if (direction != null) {
      framed = Directionality(textDirection: direction, child: framed);
    }
    return Center(
      child: SizedBox(
        key: const ValueKey('payment_request_preview_frame'),
        width: size.width,
        height: size.height,
        child: framed,
      ),
    );
  }
}
