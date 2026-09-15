// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/send/widgets/payment_request_card.dart';
import '../src/features/send/widgets/payment_request_surface.dart';
import 'support/wb_layout.dart';

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
    "Couldn't check this request — try again or edit the details";

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

/// Requester note without a requester name or transaction memo.
const _noteOnlyRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  amountZecText: '0.5 ZEC',
  fiatText: r'$35.00',
  address: _sampleAddress,
  note: _sampleNote,
);

/// Requester name without a note: the requester block collapses to its
/// summary line with nothing to disclose, which is the shape a bare
/// `label=` link produces.
const _requesterNameOnlyRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Blue Door Coffee',
  amountZecText: '0.5 ZEC',
  fiatText: r'$35.00',
  address: _sampleAddress,
);

/// A memo of nothing but spaces. Those bytes are still paid, so the memo row
/// stays and the card draws a placeholder in the value slot rather than an
/// empty row indistinguishable from a request that carried no memo.
const _whitespaceMemoRequest = PaymentRequestView(
  source: PaymentRequestSource.link,
  requesterLabel: 'Blue Door Coffee',
  amountZecText: '0.5 ZEC',
  fiatText: r'$35.00',
  address: _sampleAddress,
  memo: '    ',
  note: _sampleNote,
);

// ─── Parameterised fixture ─────────────────────────────

/// Which request payload a payment-request preview renders.
///
/// Its own axis, so the gallery can cross it with layout, expansion, text
/// scale and direction instead of registering a builder per permutation.
enum PaymentRequestFixture {
  full,
  minimal,
  longValues,
  checking,
  invalidAddress,
  insufficientFunds,
  syncing,
  syncStalled,
  failed,
  replaced,
  transparent,
  contact,
  ownAccount,
  noteOnly,
  requesterNameOnly,
  whitespaceMemo,
  noAmount,
}

/// Which expandable block of the card starts open.
enum PaymentRequestExpansion { none, address, message }

/// The request payload behind [fixture].
PaymentRequestView paymentRequestViewFor(PaymentRequestFixture fixture) {
  return switch (fixture) {
    PaymentRequestFixture.full => _fullRequest,
    PaymentRequestFixture.minimal => _minimalRequest,
    PaymentRequestFixture.longValues => _longValuesRequest,
    PaymentRequestFixture.checking => _statusRequest(
      PaymentRequestStatus.checking,
    ),
    PaymentRequestFixture.invalidAddress => _statusRequest(
      PaymentRequestStatus.invalidAddress,
    ),
    PaymentRequestFixture.insufficientFunds => _statusRequest(
      PaymentRequestStatus.insufficientFunds,
    ),
    PaymentRequestFixture.syncing => _statusRequest(
      PaymentRequestStatus.syncing,
    ),
    PaymentRequestFixture.syncStalled => _statusRequest(
      PaymentRequestStatus.syncStalled,
    ),
    PaymentRequestFixture.failed => _statusRequest(
      PaymentRequestStatus.failed,
      statusMessage: _failedStatusMessage,
    ),
    PaymentRequestFixture.replaced => _replacedRequest,
    PaymentRequestFixture.transparent => _transparentRequest,
    PaymentRequestFixture.contact => _contactRequest,
    PaymentRequestFixture.ownAccount => _ownAccountRequest,
    PaymentRequestFixture.noteOnly => _noteOnlyRequest,
    PaymentRequestFixture.requesterNameOnly => _requesterNameOnlyRequest,
    PaymentRequestFixture.whitespaceMemo => _whitespaceMemoRequest,
    PaymentRequestFixture.noAmount => _noAmountRequest,
  };
}

/// One payment-request preview; every builder below delegates here so the
/// gallery and figma_compare render the same tree.
Widget paymentRequestFixture({
  required PaymentRequestFixture fixture,
  bool mobile = false,
  PaymentRequestExpansion expansion = PaymentRequestExpansion.none,
  double textScale = 1,
  TextDirection? textDirection,
}) {
  final request = paymentRequestViewFor(fixture);
  final addressExpanded = expansion == PaymentRequestExpansion.address;
  final messageExpanded = expansion == PaymentRequestExpansion.message;
  if (mobile) {
    return _mobile(
      request,
      textScale: textScale,
      textDirection: textDirection,
      addressExpanded: addressExpanded,
      messageExpanded: messageExpanded,
    );
  }
  return _desktop(
    request,
    textScale: textScale,
    textDirection: textDirection,
    addressExpanded: addressExpanded,
    messageExpanded: messageExpanded,
  );
}

// ─── Desktop ─────────────────────────────────────────

Widget buildPaymentRequestFullUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.full);

Widget buildPaymentRequestAddressExpandedUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.full,
      expansion: PaymentRequestExpansion.address,
    );

Widget buildPaymentRequestMinimalUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.minimal);

Widget buildPaymentRequestLongValuesUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.longValues);

Widget buildPaymentRequestLongValuesExpandedUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.longValues,
      expansion: PaymentRequestExpansion.message,
    );

Widget buildPaymentRequestCheckingUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.checking);

Widget buildPaymentRequestInvalidAddressUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.invalidAddress);

Widget buildPaymentRequestInsufficientUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.insufficientFunds);

Widget buildPaymentRequestSyncingUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.syncing);

/// The syncing card once it has run out of ways to answer itself: same
/// blocked request, but the primary action becomes an enabled "Check again"
/// rather than a Review that can never fire.
Widget buildPaymentRequestSyncStalledUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.syncStalled);

Widget buildPaymentRequestFailedUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.failed);

Widget buildPaymentRequestReplacedUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.replaced);

Widget buildPaymentRequestTransparentUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.transparent);

Widget buildPaymentRequestContactUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.contact);

Widget buildPaymentRequestOwnAccountUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.ownAccount);

Widget buildPaymentRequestOwnAccountExpandedUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.ownAccount,
      expansion: PaymentRequestExpansion.address,
    );

Widget buildPaymentRequestNoteOnlyUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.noteOnly);

Widget buildPaymentRequestNoAmountUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.noAmount);

Widget buildPaymentRequestLargeTextUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.full, textScale: 1.5);

Widget buildPaymentRequestRtlUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.full,
      textDirection: TextDirection.rtl,
    );

// ─── Mobile ──────────────────────────────────────────

Widget buildMobilePaymentRequestFullUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.full, mobile: true);

Widget buildMobilePaymentRequestAddressExpandedUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.full,
      mobile: true,
      expansion: PaymentRequestExpansion.address,
    );

Widget buildMobilePaymentRequestMinimalUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.minimal, mobile: true);

Widget buildMobilePaymentRequestLongValuesUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.longValues,
      mobile: true,
    );

Widget buildMobilePaymentRequestLongValuesExpandedUseCase(
  BuildContext context,
) => paymentRequestFixture(
  fixture: PaymentRequestFixture.longValues,
  mobile: true,
  expansion: PaymentRequestExpansion.message,
);

Widget buildMobilePaymentRequestCheckingUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.checking,
      mobile: true,
    );

Widget buildMobilePaymentRequestInvalidAddressUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.invalidAddress,
      mobile: true,
    );

Widget buildMobilePaymentRequestInsufficientUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.insufficientFunds,
      mobile: true,
    );

Widget buildMobilePaymentRequestSyncingUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.syncing, mobile: true);

Widget buildMobilePaymentRequestFailedUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.failed, mobile: true);

Widget buildMobilePaymentRequestReplacedUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.replaced,
      mobile: true,
    );

Widget buildMobilePaymentRequestTransparentUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.transparent,
      mobile: true,
    );

Widget buildMobilePaymentRequestContactUseCase(BuildContext context) =>
    paymentRequestFixture(fixture: PaymentRequestFixture.contact, mobile: true);

Widget buildMobilePaymentRequestOwnAccountUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.ownAccount,
      mobile: true,
    );

Widget buildMobilePaymentRequestOwnAccountExpandedUseCase(
  BuildContext context,
) => paymentRequestFixture(
  fixture: PaymentRequestFixture.ownAccount,
  mobile: true,
  expansion: PaymentRequestExpansion.address,
);

Widget buildMobilePaymentRequestNoteOnlyUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.noteOnly,
      mobile: true,
    );

Widget buildMobilePaymentRequestNoAmountUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.noAmount,
      mobile: true,
    );

Widget buildMobilePaymentRequestLargeTextUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.full,
      mobile: true,
      textScale: 1.5,
    );

Widget buildMobilePaymentRequestRtlUseCase(BuildContext context) =>
    paymentRequestFixture(
      fixture: PaymentRequestFixture.full,
      mobile: true,
      textDirection: TextDirection.rtl,
    );

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
      // Non-null so the stalled card's primary renders the way it does in the
      // app — enabled. A preview that left it null would show the one status
      // whose whole point is an actionable button with a dead one.
      onRecheck: () {},
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
  // Phone box: `scaleDown` fits it to a shorter canvas and stays scale 1.0 at
  // the 393×852 capture viewport, so the figma_compare render is unchanged.
  return WbScaleDownBox(
    size: const Size(393, 852),
    child: _PaymentRequestFrame(
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
        // Non-null so the stalled card's primary renders the way it does in the
        // app — enabled. A preview that left it null would show the one status
        // whose whole point is an actionable button with a dead one.
        onRecheck: () {},
      ),
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
