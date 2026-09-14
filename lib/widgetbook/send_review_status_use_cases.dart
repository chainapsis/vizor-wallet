// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/donation/widgets/donation_views.dart';
import '../src/features/send/widgets/send_review_content_view.dart';
import '../src/features/send/widgets/send_review_layout.dart';
import '../src/features/send/widgets/send_status_content_view.dart';

const _sampleAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _sampleMemo = 'Zcash is a privacy-focused ...';

/// A memo long enough that the Message row actually truncates, so the
/// expanded/truncated axis has something to show.
const kSendReviewFixtureLongMemo =
    'Zcash is a privacy-focused digital currency built on strong science. '
    'Thanks for the coffee — see you at the meetup next week.';

const _addressRecipient = SendReviewAddressRecipient(address: _sampleAddress);

const _contactRecipient = SendReviewContactRecipient(
  address: _sampleAddress,
  name: 'Mike',
  profilePictureId: 'pfp-02',
);

const _requestContactRecipient = SendReviewContactRecipient(
  address: _sampleAddress,
  name: 'Blue Door Coffee',
  profilePictureId: 'pfp-02',
);

/// Timestamp every status preview shows; a literal, never `DateTime.now()`.
const kSendStatusFixtureTimestamp = '25 May, 13:30';

/// Transaction id the status previews show in their Tx ID row.
const kSendStatusFixtureTxId = '0123123124512512';

/// Donation title `send_status_screen.dart` overrides the send copy with.
String sendStatusDonationTitleFor(SendStatusPhase phase) {
  return phase == SendStatusPhase.failed
      ? 'Donation failed'
      : 'Donation in progress...';
}

// --- Review send ------------------------------------------------------------

/// Parameterised review preview: the real [SendReviewContentView] on the
/// trailing-pane stand-in.
///
/// Defaults mirror the four builders below, which stay one-line delegates so
/// their renders are unchanged. [confirmEnabled] / [cancelling] reproduce the
/// live screen's two disabled paths (abandoned proposal, cancel in flight),
/// including the label it swaps in — see `send_review_screen.dart`. A payment
/// request names its contact after the requester, which is why
/// [isPaymentRequest] also picks which contact [contactRecipient] resolves to.
Widget sendReviewContentFixture({
  String amountText = '123.12 ZEC',
  String? fiatText = r'$250.12',
  bool contactRecipient = false,
  bool isShieldedRecipient = true,
  String? recipientAddressType,
  String? memoText = _sampleMemo,
  bool memoExpanded = false,
  String feeText = '0.012 ZEC',
  bool isPaymentRequest = false,
  String? requestedAmountText,
  bool hardwareAccount = false,
  bool confirmEnabled = true,
  bool cancelling = false,
  String recipientAddress = _sampleAddress,
  VoidCallback? onCancel,
  VoidCallback? onConfirm,
}) {
  return _SendReviewStatusFrame(
    child: SendReviewContentView(
      amountText: amountText,
      fiatText: fiatText,
      recipient:
          contactRecipient
              ? (isPaymentRequest
                  ? _requestContactRecipient
                  : _contactRecipient)
              : recipientAddress == _sampleAddress
              ? _addressRecipient
              : SendReviewAddressRecipient(address: recipientAddress),
      isShieldedRecipient: isShieldedRecipient,
      recipientAddressType: recipientAddressType,
      memoText: memoText,
      memoExpanded: memoExpanded,
      feeText: feeText,
      isPaymentRequest: isPaymentRequest,
      requestedAmountText: requestedAmountText,
      confirmLabel:
          cancelling
              ? 'Cancelling…'
              : hardwareAccount
              ? 'Confirm with Keystone'
              : 'Confirm & send',
      confirmLeadingIconName: hardwareAccount ? AppIcons.qr : AppIcons.plane,
      onConfirm: confirmEnabled && !cancelling ? onConfirm ?? _noop : null,
      onCancel: cancelling ? null : onCancel ?? _noop,
      onShowFullAddress: _noop,
      onExpandMemo: _noop,
      onFeeHelp: _noop,
    ),
  );
}

/// Review send — raw shielded address recipient. (Toggle the Widgetbook
/// theme for dark mode.)
Widget buildSendReviewAddressUseCase(BuildContext context) {
  return sendReviewContentFixture();
}

/// Review send — address-book contact recipient (avatar + name headline,
/// truncated address sub-line).
Widget buildSendReviewContactUseCase(BuildContext context) {
  return sendReviewContentFixture(contactRecipient: true);
}

/// Review Payment — the recipient is a saved contact. Only the row
/// title changes; the link's own `label=` is never shown on the review.
Widget buildSendReviewPaymentRequestContactUseCase(BuildContext context) {
  return sendReviewContentFixture(
    amountText: '0.50 ZEC',
    fiatText: r'$35.00',
    contactRecipient: true,
    isPaymentRequest: true,
  );
}

/// Review Payment — no address-book match, so the truncated address
/// and its pool badge head the "Requested by" row.
Widget buildSendReviewPaymentRequestAddressUseCase(BuildContext context) {
  return sendReviewContentFixture(
    amountText: '0.50 ZEC',
    fiatText: r'$35.00',
    isPaymentRequest: true,
  );
}

// --- Send status ------------------------------------------------------------

/// Parameterised status preview: the real [SendStatusContentView] on the
/// trailing-pane stand-in.
///
/// [donation] applies the flow-specific title and recipient row exactly as
/// `send_status_screen.dart` does for the donation flow.
Widget sendStatusContentFixture({
  SendStatusPhase phase = SendStatusPhase.inProgress,
  String amountText = '123.12 ZEC',
  String? fiatText = r'$250.12',
  bool isShieldedRecipient = true,
  String? memoText = _sampleMemo,
  bool memoExpanded = false,
  String? txIdText = kSendStatusFixtureTxId,
  String feeText = '0.012 ZEC',
  String? noticeText,
  bool donation = false,
}) {
  return _SendReviewStatusFrame(
    child: SendStatusContentView(
      phase: phase,
      amountText: amountText,
      fiatText: fiatText,
      recipient: _addressRecipient,
      isShieldedRecipient: isShieldedRecipient,
      memoText: memoText,
      memoExpanded: memoExpanded,
      timestampText: kSendStatusFixtureTimestamp,
      txIdText: txIdText,
      feeText: feeText,
      noticeText: noticeText,
      titleOverride: donation ? sendStatusDonationTitleFor(phase) : null,
      recipientRow:
          donation
              ? DonationRecipientInfoRow(
                struckThrough: phase == SendStatusPhase.failed,
              )
              : null,
      onShowFullAddress: donation ? null : _noop,
      onExpandMemo: _noop,
      onOpenExplorer: _noop,
      onFeeHelp: _noop,
    ),
  );
}

/// Send status — in progress: loader status row, no CTA.
Widget buildSendStatusInProgressUseCase(BuildContext context) {
  return sendStatusContentFixture();
}

/// Send status — completed: green check status row.
Widget buildSendStatusCompletedUseCase(BuildContext context) {
  return sendStatusContentFixture(phase: SendStatusPhase.completed);
}

/// Send status — failed: uturn-up connector, struck-through recipient, and
/// the wrap card pinned dark in both themes.
Widget buildSendStatusFailedUseCase(BuildContext context) {
  return sendStatusContentFixture(phase: SendStatusPhase.failed);
}

void _noop() {}

/// Window-colored backdrop standing in for the trailing pane; the content
/// views center their own 420px column, mirroring how `SendComposeView`
/// fills the pane on the live screen.
class _SendReviewStatusFrame extends StatelessWidget {
  const _SendReviewStatusFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.colors.background.window, child: child);
  }
}
