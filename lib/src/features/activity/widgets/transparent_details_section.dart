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

/// What the receipt adds from loop 4 (transparent txid enhancement) beyond
/// its shared shell: every payee of a send paying several transparent
/// recipients, or a notice while a recipient is not known yet or cannot be
/// looked up in private mode. Renders nothing otherwise, so a receipt shows
/// the same rows whether its details came from a stored transaction or from
/// private queries.
class TransparentDetailsSection extends StatelessWidget {
  const TransparentDetailsSection({
    required this.detail,
    required this.privacyModeEnabled,
    this.debugLookupText,
    this.onDebugLookup,
    this.spaced = true,
    super.key,
  });

  final rust_sync.TransactionDetail? detail;
  final bool privacyModeEnabled;

  /// Development builds only: the result of the last private lookup.
  final String? debugLookupText;

  /// Development builds only: looks the transaction up privately without
  /// storing anything.
  final VoidCallback? onDebugLookup;

  /// Whether the card keeps its own gap from the card above. Off where the
  /// host column already spaces its cards.
  final bool spaced;

  @override
  Widget build(BuildContext context) {
    final notice = transparentDetailsNotice(detail);
    final payees = listedTransparentPayees(detail);
    if (notice == null && payees.isEmpty && onDebugLookup == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final rows = <Widget>[
      if (notice == rust_sync.TransparentDetailsState.notCovered)
        ReviewListRow(
          key: const ValueKey('transparent_details_not_covered'),
          label: 'Details',
          value: kTransparentDetailsNotCoveredText,
          valueColor: colors.text.secondary,
        )
      else if (notice != null)
        ReviewListRow(
          key: const ValueKey('transparent_details_unavailable'),
          label: 'Details',
          value: kTransparentDetailsUnavailableText,
          valueColor: colors.text.secondary,
          leadingIconName: AppIcons.loader,
          scaleValueToFit: true,
        ),
      for (final payee in payees)
        ReviewListRow(
          key: ValueKey('transparent_recipient_${payee.outputIndex}'),
          label: 'Recipient',
          value:
              '${payee.address == null ? 'Script' : truncatedAddress(payee.address!)}'
              '  ${hideAmountIfPrivacyMode(ZecAmount.fromZatoshi(payee.amountZatoshi).activityDetail.toString(), privacyModeEnabled: privacyModeEnabled)}',
          copyText: payee.address,
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
      padding: EdgeInsets.only(top: spaced ? AppSpacing.base : 0),
      child: ReviewWrapCard(
        key: const ValueKey('transparent_details_section'),
        children: rows,
      ),
    );
  }
}
