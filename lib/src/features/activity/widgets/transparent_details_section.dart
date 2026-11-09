import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../transaction_completeness.dart';

/// What the receipt adds from loop 4 (transparent txid enhancement) beyond
/// its shared shell, for a receipt with no recorded recipient: the
/// transaction's other transparent outputs, attributed to no one, or a notice
/// while they are not known yet or cannot be looked up in private mode. When
/// the private details leave something out, it names what, and offers to
/// load the full details publicly.
/// Renders nothing otherwise, so a receipt with a recorded recipient shows
/// the same rows whether its details came from a stored transaction or from
/// private queries.
class TransparentDetailsSection extends StatelessWidget {
  const TransparentDetailsSection({
    required this.detail,
    required this.privacyModeEnabled,
    this.publicLookupText,
    this.onLoadPublicly,
    this.spaced = true,
    super.key,
  });

  final rust_sync.TransactionDetail? detail;
  final bool privacyModeEnabled;

  /// The state of the last public load, while it runs or after it failed.
  final String? publicLookupText;

  /// Loads the full details from the server, after the user confirms; null
  /// when the receipt does not offer it.
  final VoidCallback? onLoadPublicly;

  /// Whether the card keeps its own gap from the card above. Off where the
  /// host column already spaces its cards.
  final bool spaced;

  @override
  Widget build(BuildContext context) {
    final notice = transparentDetailsNotice(detail);
    final outputs = listedTransactionOutputs(detail);
    final l10n = context.l10n;
    final omissions = transparentOmissionPhrases(l10n, detail);
    if (notice == null &&
        outputs.isEmpty &&
        omissions.isEmpty &&
        onLoadPublicly == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final rows = <Widget>[
      if (notice == rust_sync.TransparentDetailsState.notCovered)
        ReviewListRow(
          key: const ValueKey('transparent_details_not_covered'),
          label: l10n.activityReceiptDetails,
          value: l10n.activityDetailsNotCovered,
          valueColor: colors.text.secondary,
        )
      else if (notice != null)
        ReviewListRow(
          key: const ValueKey('transparent_details_unavailable'),
          label: l10n.activityReceiptDetails,
          value: l10n.activityDetailsUnavailable,
          valueColor: colors.text.secondary,
          leadingIconName: AppIcons.loader,
          scaleValueToFit: true,
        ),
      // The outputs are the transaction's; none is named a recipient.
      if (outputs.isNotEmpty)
        Column(
          key: const ValueKey('transaction_outputs'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewListRow(
              label: l10n.activityDetailsOutputsLabel,
              value: l10n.activityDetailsOutputsUnattributed,
              valueColor: colors.text.secondary,
              scaleValueToFit: true,
            ),
            for (final output in outputs)
              ReviewListRow(
                key: ValueKey('transaction_output_${output.outputIndex}'),
                label: l10n.activityReceiptOutput,
                value:
                    '${output.address == null ? 'Script' /* l10n-ignore: protocol term */ : truncatedAddress(output.address!)}'
                    '  ${hideAmountIfPrivacyMode(ZecAmount.fromZatoshi(output.amountZatoshi).activityDetail.toString(), privacyModeEnabled: privacyModeEnabled)}',
                copyText: output.address,
                scaleValueToFit: true,
              ),
          ],
        ),
      if (omissions.isNotEmpty)
        ReviewListRow(
          key: const ValueKey('transparent_details_omissions'),
          label: l10n.activityDetailsOmittedLabel,
          value: omissions.join(', '),
          valueColor: colors.text.secondary,
          scaleValueToFit: true,
        ),
      if (onLoadPublicly != null)
        ReviewListRow(
          key: const ValueKey('transparent_details_load_publicly'),
          label: l10n.activityDetailsLoadPubliclyLabel,
          value: publicLookupText ?? l10n.activityDetailsLoadPublicly,
          trailingIconName: AppIcons.arrowTopRight,
          onPressed: onLoadPublicly,
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
