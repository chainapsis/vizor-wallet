// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/send/widgets/send_review_content_view.dart';
import '../src/features/send/widgets/send_review_layout.dart';
import '../src/features/send/widgets/send_status_content_view.dart';

const _sampleAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _sampleMemo = 'Zcash is a privacy-focused ...';

const _addressRecipient = SendReviewAddressRecipient(address: _sampleAddress);

const _contactRecipient = SendReviewContactRecipient(
  address: _sampleAddress,
  name: 'Mike',
  profilePictureId: 'pfp-02',
);

/// Review send — raw shielded address recipient. (Toggle the Widgetbook
/// theme for dark mode.)
Widget buildSendReviewAddressUseCase(BuildContext context) {
  return _SendReviewStatusFrame(
    child: SendReviewContentView(
      amountText: '123.12 ZEC',
      fiatText: r'$250.12',
      recipient: _addressRecipient,
      memoText: _sampleMemo,
      feeText: '0.012 ZEC',
      onConfirm: () {},
      onCancel: () {},
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onFeeHelp: () {},
    ),
  );
}

/// Review send — address-book contact recipient (avatar + name headline,
/// truncated address sub-line).
Widget buildSendReviewContactUseCase(BuildContext context) {
  return _SendReviewStatusFrame(
    child: SendReviewContentView(
      amountText: '123.12 ZEC',
      fiatText: r'$250.12',
      recipient: _contactRecipient,
      memoText: _sampleMemo,
      feeText: '0.012 ZEC',
      onConfirm: () {},
      onCancel: () {},
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onFeeHelp: () {},
    ),
  );
}

/// Send status — in progress: loader status row, no CTA.
Widget buildSendStatusInProgressUseCase(BuildContext context) {
  return _SendReviewStatusFrame(
    child: SendStatusContentView(
      phase: SendStatusPhase.inProgress,
      amountText: '123.12 ZEC',
      fiatText: r'$250.12',
      recipient: _addressRecipient,
      memoText: _sampleMemo,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: '0.012 ZEC',
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onOpenExplorer: () {},
      onFeeHelp: () {},
    ),
  );
}

/// Send status — completed: green check status row.
Widget buildSendStatusCompletedUseCase(BuildContext context) {
  return _SendReviewStatusFrame(
    child: SendStatusContentView(
      phase: SendStatusPhase.completed,
      amountText: '123.12 ZEC',
      fiatText: r'$250.12',
      recipient: _addressRecipient,
      memoText: _sampleMemo,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: '0.012 ZEC',
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onOpenExplorer: () {},
      onFeeHelp: () {},
    ),
  );
}

/// Send status — failed: uturn-up connector, struck-through recipient, and
/// the wrap card pinned dark in both themes.
Widget buildSendStatusFailedUseCase(BuildContext context) {
  return _SendReviewStatusFrame(
    child: SendStatusContentView(
      phase: SendStatusPhase.failed,
      amountText: '123.12 ZEC',
      fiatText: r'$250.12',
      recipient: _addressRecipient,
      memoText: _sampleMemo,
      timestampText: '25 May, 13:30',
      txIdText: '0123123124512512',
      feeText: '0.012 ZEC',
      onShowFullAddress: () {},
      onExpandMemo: () {},
      onOpenExplorer: () {},
      onFeeHelp: () {},
    ),
  );
}

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
