// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/activity/widgets/received_receipt_view.dart';
import '../src/features/activity/widgets/shielded_receipt_view.dart';
import '../src/features/send/widgets/send_review_layout.dart';

const _transparentFromAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

const _transparentReceivingAddress = 't1Z9N3oVYrYDpnbqDcXJpuLrGpcSLDgHXyo';

const _shieldedReceivingAddress =
    'u1j9g9dnk7f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190592';

const _sampleMemo = 'Zcash is a privacy-focused ...';

/// Who the receipt names in its From row.
enum ReceivedReceiptFromSource {
  /// A raw t-address sender.
  transparentAddress,

  /// A saved contact.
  contact,

  /// Sender hidden by a shielded source pool.
  shieldedSender,

  /// Sender not resolvable at all.
  unknownSender,
}

/// Pool the funds landed in, shown as the amount sub-line.
enum ReceivedReceiptReceivingPool { transparent, shielded }

/// Shared body of the received-receipt fixtures.
///
/// Every `build*UseCase` below is one parameter set of this helper, so the
/// gallery can offer the axes as knobs while each builder keeps its name and
/// its existing render.
Widget receivedReceiptFixture({
  ReceivedReceiptStatus status = ReceivedReceiptStatus.completed,
  ReceivedReceiptFromSource from = ReceivedReceiptFromSource.transparentAddress,
  ReceivedReceiptReceivingPool receivingPool =
      ReceivedReceiptReceivingPool.transparent,
  bool memo = true,
  bool memoExpanded = false,
  bool fee = true,
}) {
  final recipient = switch (from) {
    ReceivedReceiptFromSource.transparentAddress =>
      const SendReviewAddressRecipient(address: _transparentFromAddress),
    ReceivedReceiptFromSource.contact => const SendReviewContactRecipient(
      address: _transparentFromAddress,
      name: 'Mike',
      profilePictureId: 'pfp-03',
    ),
    _ => null,
  };
  final unknownFromKind = switch (from) {
    ReceivedReceiptFromSource.shieldedSender =>
      ReceivedReceiptUnknownFromKind.shieldedSender,
    ReceivedReceiptFromSource.unknownSender =>
      ReceivedReceiptUnknownFromKind.unknownSender,
    _ => null,
  };
  final isShieldedReceiving =
      receivingPool == ReceivedReceiptReceivingPool.shielded;

  return _ReceivedReceiptFrame(
    child: ReceivedReceiptView(
      status: status,
      fromRecipient: recipient,
      unknownFromKind: unknownFromKind,
      isShieldedSource: from == ReceivedReceiptFromSource.shieldedSender,
      amountText: '120 ZEC',
      receivingAddress: isShieldedReceiving
          ? _shieldedReceivingAddress
          : _transparentReceivingAddress,
      isShieldedReceivingAddress: isShieldedReceiving,
      memoText: memo ? _sampleMemo : null,
      memoExpanded: memoExpanded,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: fee ? '0.012 ZEC' : null,
      // The affordances only exist when the row they belong to does.
      onShowFullAddress: recipient == null ? null : () {},
      onExpandMemo: memo ? () {} : null,
      onTxIdPressed: () {},
      onFeeHelpPressed: fee ? () {} : null,
    ),
  );
}

/// Self-shield receipt on the same 420px content column as the received
/// receipt: both are the trailing pane's transaction detail.
Widget shieldedReceiptFixture({
  ShieldedReceiptStatus status = ShieldedReceiptStatus.completed,
  bool fee = true,
  bool memo = false,
  bool memoExpanded = false,
}) {
  return _ReceivedReceiptFrame(
    child: ShieldedReceiptView(
      status: status,
      amountText: '12.5 ZEC',
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: fee ? '0.0001 ZEC' : null,
      memoText: memo ? _sampleMemo : null,
      memoExpanded: memoExpanded,
      // The affordances only exist when the row they belong to does.
      onExpandMemo: memo ? () {} : null,
      onTxIdPressed: () {},
      onFeeHelpPressed: fee ? () {} : null,
    ),
  );
}

/// t-address -> t-address receive with a memo — the full Figma `received`
/// frame. (Toggle the Widgetbook theme for dark mode.)
Widget buildReceivedReceiptUseCase(BuildContext context) {
  return buildReceivedReceiptTransparentToTransparentUseCase(context);
}

Widget buildReceivedReceiptTransparentToTransparentUseCase(
  BuildContext context,
) {
  return receivedReceiptFixture();
}

Widget buildReceivedReceiptTransparentToShieldedUseCase(BuildContext context) {
  return receivedReceiptFixture(
    receivingPool: ReceivedReceiptReceivingPool.shielded,
  );
}

/// Memo-less shielded receive — the common Vizor case: the sender address is
/// not revealed, while both visible pool badges use the shielded glyph.
Widget buildReceivedReceiptShieldedToShieldedUseCase(BuildContext context) {
  return receivedReceiptFixture(
    from: ReceivedReceiptFromSource.shieldedSender,
    receivingPool: ReceivedReceiptReceivingPool.shielded,
    memo: false,
  );
}

Widget buildReceivedReceiptKnownSenderUseCase(BuildContext context) {
  return receivedReceiptFixture(
    from: ReceivedReceiptFromSource.contact,
    receivingPool: ReceivedReceiptReceivingPool.shielded,
  );
}

/// Unconfirmed inbound transaction as it actually renders in the app:
/// loader status row per the send-in-progress spec, unknown sender, and no
/// network fee row until the wallet knows the transaction-level fee.
Widget buildReceivedReceiptInProgressUseCase(BuildContext context) {
  return receivedReceiptFixture(
    status: ReceivedReceiptStatus.inProgress,
    from: ReceivedReceiptFromSource.unknownSender,
    memo: false,
    fee: false,
  );
}

/// 420px content-column frame on the window background, mirroring the
/// trailing-pane Content Area the receipt renders in.
class _ReceivedReceiptFrame extends StatelessWidget {
  const _ReceivedReceiptFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: AppWindowSizing.contentAreaMaxWidth,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.sm,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
