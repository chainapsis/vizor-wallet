import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../transaction_completeness.dart';

/// The transparent outputs of a transparent or mixed transaction, as loop 4
/// (transparent txid enhancement) knows them: every output when available,
/// otherwise a notice that they will arrive or that private mode cannot look
/// them up. Renders nothing for a transaction without a transparent part.
class TransparentDetailsSection extends StatelessWidget {
  const TransparentDetailsSection({
    required this.detail,
    required this.privacyModeEnabled,
    this.debugLookupText,
    this.onDebugLookup,
    super.key,
  });

  final rust_sync.TransactionDetail? detail;
  final bool privacyModeEnabled;

  /// Development builds only: the result of the last private lookup.
  final String? debugLookupText;

  /// Development builds only: looks the transaction up privately without
  /// storing anything.
  final VoidCallback? onDebugLookup;

  @override
  Widget build(BuildContext context) {
    final state = detail?.transparentDetailsState;
    if (state == null) return const SizedBox.shrink();
    final colors = context.colors;
    final rows = <Widget>[
      switch (state) {
        rust_sync.TransparentDetailsState.available => ReviewListRow(
          label: 'Transparent outputs',
          value: '${detail!.transparentRecipients.length}',
        ),
        rust_sync.TransparentDetailsState.pending ||
        rust_sync.TransparentDetailsState.unavailable => ReviewListRow(
          key: const ValueKey('transparent_details_unavailable'),
          label: 'Details',
          value: kTransparentDetailsUnavailableText,
          valueColor: colors.text.secondary,
          leadingIconName: AppIcons.loader,
          scaleValueToFit: true,
        ),
        rust_sync.TransparentDetailsState.notCovered => ReviewListRow(
          key: const ValueKey('transparent_details_not_covered'),
          label: 'Details',
          value: kTransparentDetailsNotCoveredText,
          valueColor: colors.text.secondary,
        ),
      },
      if (state == rust_sync.TransparentDetailsState.available)
        for (final recipient in detail!.transparentRecipients)
          ReviewListRow(
            key: ValueKey('transparent_recipient_${recipient.outputIndex}'),
            label: transparentRecipientLabel(recipient),
            value:
                '${recipient.address == null ? 'Script' : truncatedAddress(recipient.address!)}'
                '  ${hideAmountIfPrivacyMode(ZecAmount.fromZatoshi(recipient.amountZatoshi).activityDetail.toString(), privacyModeEnabled: privacyModeEnabled)}',
            copyText: recipient.address,
            scaleValueToFit: true,
          ),
      if (onDebugLookup != null)
        ReviewListRow(
          key: const ValueKey('transparent_details_debug_lookup'),
          label: 'Private lookup (dev)',
          value: debugLookupText == null
              ? 'Look up'
              : hideIfPrivacyMode(
                  debugLookupText!,
                  privacyModeEnabled: privacyModeEnabled,
                ),
          trailingIconName: AppIcons.arrowTopRight,
          onPressed: onDebugLookup,
          scaleValueToFit: true,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.base),
      child: ReviewWrapCard(
        key: const ValueKey('transparent_details_section'),
        children: rows,
      ),
    );
  }
}
