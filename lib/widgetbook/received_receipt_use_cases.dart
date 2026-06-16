// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/activity/widgets/received_receipt_view.dart';
import '../src/features/send/widgets/send_review_layout.dart';

const _transparentFromAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

const _transparentReceivingAddress = 't1Z9N3oVYrYDpnbqDcXJpuLrGpcSLDgHXyo';

const _shieldedReceivingAddress =
    'u1j9g9dnk7f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190592';

const _sampleMemo = 'Zcash is a privacy-focused ...';

/// t-address -> t-address receive with a memo — the full Figma `received`
/// frame. (Toggle the Widgetbook theme for dark mode.)
Widget buildReceivedReceiptUseCase(BuildContext context) {
  return buildReceivedReceiptTransparentToTransparentUseCase(context);
}

Widget buildReceivedReceiptTransparentToTransparentUseCase(
  BuildContext context,
) {
  return _ReceivedReceiptFrame(
    child: ReceivedReceiptView(
      fromRecipient: const SendReviewAddressRecipient(
        address: _transparentFromAddress,
      ),
      isShieldedSource: false,
      amountText: '120 ZEC',
      receivingAddress: _transparentReceivingAddress,
      isShieldedReceivingAddress: false,
      memoText: _sampleMemo,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: '0.012 ZEC',
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onTxIdPressed: () {},
      onFeeHelpPressed: () {},
    ),
  );
}

Widget buildReceivedReceiptTransparentToShieldedUseCase(BuildContext context) {
  return _ReceivedReceiptFrame(
    child: ReceivedReceiptView(
      fromRecipient: const SendReviewAddressRecipient(
        address: _transparentFromAddress,
      ),
      isShieldedSource: false,
      amountText: '120 ZEC',
      receivingAddress: _shieldedReceivingAddress,
      isShieldedReceivingAddress: true,
      memoText: _sampleMemo,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: '0.012 ZEC',
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onTxIdPressed: () {},
      onFeeHelpPressed: () {},
    ),
  );
}

/// Memo-less shielded receive — the common Vizor case: the sender address is
/// not revealed, while both visible pool badges use the shielded glyph.
Widget buildReceivedReceiptShieldedToShieldedUseCase(BuildContext context) {
  return _ReceivedReceiptFrame(
    child: ReceivedReceiptView(
      unknownFromKind: ReceivedReceiptUnknownFromKind.shieldedSender,
      isShieldedSource: true,
      amountText: '120 ZEC',
      receivingAddress: _shieldedReceivingAddress,
      isShieldedReceivingAddress: true,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: '0.012 ZEC',
      onTxIdPressed: () {},
      onFeeHelpPressed: () {},
    ),
  );
}

Widget buildReceivedReceiptKnownSenderUseCase(BuildContext context) {
  return _ReceivedReceiptFrame(
    child: ReceivedReceiptView(
      fromRecipient: const SendReviewContactRecipient(
        address: _transparentFromAddress,
        name: 'Mike',
        profilePictureId: 'pfp-03',
      ),
      isShieldedSource: false,
      amountText: '120 ZEC',
      receivingAddress: _shieldedReceivingAddress,
      isShieldedReceivingAddress: true,
      memoText: _sampleMemo,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: '0.012 ZEC',
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onTxIdPressed: () {},
      onFeeHelpPressed: () {},
    ),
  );
}

/// Unconfirmed inbound transaction as it actually renders in the app:
/// loader status row per the send-in-progress spec, unknown sender, and no
/// network fee row until the wallet knows the transaction-level fee.
Widget buildReceivedReceiptInProgressUseCase(BuildContext context) {
  return _ReceivedReceiptFrame(
    child: ReceivedReceiptView(
      status: ReceivedReceiptStatus.inProgress,
      unknownFromKind: ReceivedReceiptUnknownFromKind.unknownSender,
      amountText: '120 ZEC',
      receivingAddress: _transparentReceivingAddress,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      onTxIdPressed: () {},
    ),
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
