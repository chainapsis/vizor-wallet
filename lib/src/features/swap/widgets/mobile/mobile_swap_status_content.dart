import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_copy_feedback.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../models/swap_address_formatting.dart';
import '../../models/swap_activity_status_mapper.dart'
    show SwapActivityStatusPresentation;
import '../../models/swap_detail_tooltips.dart';
import '../../models/swap_status_presentation.dart';
import '../swap_status_page_content.dart' show SwapAnimatedProgressRoute;
import 'mobile_swap_review_header.dart';

const _mobileStatusDetailIconSize = 16.0;
const _mobileStatusHeaderToBodyGap = AppSpacing.sm + AppSpacing.s;

/// Mobile swap status — Figma `Review Progress` (4752:30028) and
/// `Swap Completed` (4752:82692): the serif paying/receiving header
/// over either the Swap progress | Transaction details tabs with the
/// step timeline, or (terminal states) the rounded status card. The
/// title renders in the host's top nav, not here.
///
/// Purely presentational: consumes the same [SwapActivityStatusPresentation]
/// the desktop status page does, so the status logic stays
/// single-sourced.
class MobileSwapStatusContent extends StatelessWidget {
  const MobileSwapStatusContent({
    required this.presentation,
    required this.payHeaderRow,
    required this.receiveHeaderRow,
    required this.activeTab,
    required this.detailsExpanded,
    required this.onTabChanged,
    required this.onToggleDetails,
    super.key,
  });

  final SwapActivityStatusPresentation presentation;
  final MobileSwapReviewHeaderRow payHeaderRow;
  final MobileSwapReviewHeaderRow receiveHeaderRow;
  final SwapStatusTab activeTab;
  final bool detailsExpanded;
  final ValueChanged<SwapStatusTab> onTabChanged;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('mobile_swap_status_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSwapReviewHeader(pay: payHeaderRow, receive: receiveHeaderRow),
        const SizedBox(height: _mobileStatusHeaderToBodyGap),
        if (presentation.showTabs) ...[
          _MobileStatusTabs(
            activeTab: activeTab,
            progressLabel: presentation.progressTabLabel,
            onChanged: onTabChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatusCard(
            key: const ValueKey('mobile_swap_status_card'),
            child: activeTab == SwapStatusTab.progress
                ? SwapAnimatedProgressRoute(
                    steps: presentation.steps,
                    progressIndex: presentation.progressIndex,
                    badgeKind: presentation.badgeKind,
                  )
                : _MobileTransactionDetails(rows: presentation.details),
          ),
        ] else
          _StatusCard(
            key: const ValueKey('mobile_swap_status_card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileStatusChipRow(badgeKind: presentation.badgeKind),
                const SizedBox(height: AppSpacing.sm),
                _MobileFinalDetails(
                  rows: presentation.details,
                  hideSuccessAddressRows:
                      presentation.badgeKind == SwapStatusBadgeKind.completed,
                ),
              ],
            ),
          ),
        // No global "View on Near Intents" link on mobile. Figma keeps the
        // external route on the Tx ID row inside transaction details.
      ],
    );
  }
}

/// White rounded surface hosting the tab content — the Figma frames
/// put the timeline and the detail rows on `foreground.neutral.ground`.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: child,
    );
  }
}

class _MobileStatusTabs extends StatelessWidget {
  const _MobileStatusTabs({
    required this.activeTab,
    required this.progressLabel,
    required this.onChanged,
  });

  final SwapStatusTab activeTab;
  final String progressLabel;
  final ValueChanged<SwapStatusTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MobileStatusTabLabel(
              key: const ValueKey('mobile_swap_status_tab_progress'),
              label: progressLabel,
              selected: activeTab == SwapStatusTab.progress,
              onTap: () => onChanged(SwapStatusTab.progress),
            ),
            const SizedBox(width: AppSpacing.sm),
            _MobileStatusTabLabel(
              key: const ValueKey('mobile_swap_status_tab_details'),
              label: 'Transaction details',
              selected: activeTab == SwapStatusTab.details,
              onTap: () => onChanged(SwapStatusTab.details),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileStatusTabLabel extends StatelessWidget {
  const _MobileStatusTabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            label,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: selected ? colors.text.accent : colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Status chip row of the terminal card — same chip language as the
/// transaction status screen.
class _MobileStatusChipRow extends StatelessWidget {
  const _MobileStatusChipRow({required this.badgeKind});

  final SwapStatusBadgeKind badgeKind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (iconName, text, color) = switch (badgeKind) {
      SwapStatusBadgeKind.completed => (
        AppIcons.checkCircle,
        'Completed',
        colors.text.positiveStrong,
      ),
      SwapStatusBadgeKind.failed => (
        AppIcons.cross,
        'Failed',
        colors.text.destructive,
      ),
      SwapStatusBadgeKind.warning => (
        AppIcons.warning,
        'Needs attention',
        colors.text.warning,
      ),
      SwapStatusBadgeKind.liveQuote => (
        AppIcons.loader,
        'In progress',
        colors.text.secondary,
      ),
    };
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              'Status',
              style: AppTypography.labelMedium.copyWith(
                color: badgeKind == SwapStatusBadgeKind.failed
                    ? colors.text.destructive
                    : colors.text.secondary,
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xxs,
              AppSpacing.xxs,
              AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(iconName, size: 20, color: color),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  text,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Terminal-state rows in the transaction-status card style: small
/// grey label left, value right, a divider before the fee section.
class _MobileTransactionDetails extends StatelessWidget {
  const _MobileTransactionDetails({required this.rows});

  final List<SwapStatusDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return _MobileDetailRows(
      key: const ValueKey('mobile_swap_transaction_details'),
      rows: rows,
      compactTransactionDetails: true,
    );
  }
}

class _MobileFinalDetails extends StatelessWidget {
  const _MobileFinalDetails({
    required this.rows,
    required this.hideSuccessAddressRows,
  });

  final List<SwapStatusDetailRowData> rows;
  final bool hideSuccessAddressRows;

  @override
  Widget build(BuildContext context) {
    return _MobileDetailRows(
      rows: rows,
      hideSuccessAddressRows: hideSuccessAddressRows,
    );
  }
}

class _MobileDetailRows extends StatelessWidget {
  const _MobileDetailRows({
    required this.rows,
    this.hideSuccessAddressRows = false,
    this.compactTransactionDetails = false,
    super.key,
  });

  final List<SwapStatusDetailRowData> rows;
  final bool hideSuccessAddressRows;
  final bool compactTransactionDetails;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visibleRows = _mobileVisibleDetailRows(
      rows,
      hideSuccessAddressRows: hideSuccessAddressRows,
      compactTransactionDetails: compactTransactionDetails,
    );
    final firstFeeIndex = visibleRows.indexWhere(_isMobileFeeDetailRow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibleRows.length; i++) ...[
          if (i > 0 && i != firstFeeIndex)
            const SizedBox(height: AppSpacing.xs),
          if (i == firstFeeIndex) ...[
            const SizedBox(height: AppSpacing.sm),
            // Figma `border/neutral/default`.
            Container(height: 1, color: colors.border.regular),
            const SizedBox(height: AppSpacing.sm),
          ],
          _MobileFinalDetailRow(row: visibleRows[i]),
        ],
      ],
    );
  }
}

List<SwapStatusDetailRowData> _mobileVisibleDetailRows(
  List<SwapStatusDetailRowData> rows, {
  bool hideSuccessAddressRows = false,
  bool compactTransactionDetails = false,
}) {
  final visible = rows
      .where((row) {
        if (compactTransactionDetails &&
            !_isMobileProgressTransactionDetailRow(row)) {
          return false;
        }
        return row.label != 'Price protection' &&
            row.label != 'Account' &&
            (!hideSuccessAddressRows || !_isMobileSuccessAddressDetailRow(row));
      })
      .toList(growable: false);
  final nonFeeRows = visible
      .where((row) => !_isMobileFeeDetailRow(row))
      .toList(growable: false);
  final feeRows = visible.where(_isMobileFeeDetailRow).toList(growable: false);
  return [...nonFeeRows, ...feeRows];
}

bool _isMobileProgressTransactionDetailRow(SwapStatusDetailRowData row) {
  final label = row.label.toLowerCase();
  return _isMobileDepositAddressDetailRow(row) ||
      label == 'slippage tolerance' ||
      label == 'guaranteed minimum' ||
      label == 'memo' ||
      label == 'missing deposit' ||
      label == 'required deposit' ||
      label == 'detected deposit' ||
      label == 'deposit deadline' ||
      label == 'refund fee' ||
      label == 'timestamp' ||
      label == 'tx id';
}

bool _isMobileDepositAddressDetailRow(SwapStatusDetailRowData row) {
  final label = row.label.toLowerCase();
  return label.contains(' deposit to') ||
      (label.startsWith('deposit ') && label.endsWith(' to'));
}

bool _isMobileSuccessAddressDetailRow(SwapStatusDetailRowData row) {
  final label = row.label.toLowerCase();
  return label.contains('recipient') || _isMobileDepositAddressDetailRow(row);
}

bool _isMobileFeeDetailRow(SwapStatusDetailRowData row) {
  final label = row.label.toLowerCase();
  return label == 'swap fee' ||
      label == 'total fees' ||
      label == 'tx fee' ||
      label == 'refund fee';
}

class _MobileFinalDetailRow extends StatelessWidget {
  const _MobileFinalDetailRow({required this.row});

  final SwapStatusDetailRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayLabel = _mobileStatusDetailLabel(row);
    final displayValue = _mobileStatusDetailDisplayValue(row);
    final linkUri = row.linkUri;
    final canTap = linkUri != null || row.copyable;
    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap
            ? () {
                if (linkUri != null) {
                  unawaited(_launchExternalUri(linkUri));
                } else {
                  copyTextWithToast(
                    context,
                    text: row.copyText ?? row.value,
                    toastMessage: 'Copied',
                  );
                }
              }
            : null,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Flexible(
                fit: FlexFit.loose,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: _MobileScaledDetailValueText(
                        value: displayValue,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    if (linkUri != null || row.copyable || row.help) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      _MobileStatusDetailActionIcon(
                        icon: linkUri != null
                            ? AppIcons.arrowTopRight
                            : row.copyable
                            ? AppIcons.copy
                            : AppIcons.help,
                        tooltipMessage: row.help
                            ? row.helpTooltip ??
                                  _mobileStatusHelpTooltip(row.label)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileScaledDetailValueText extends StatelessWidget {
  const _MobileScaledDetailValueText({
    required this.value,
    required this.style,
  });

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        value,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.end,
        style: style,
      ),
    );
  }
}

Future<void> _launchExternalUri(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Opening the system browser is best effort; the row still exposes the ID.
  }
}

String _mobileStatusDetailLabel(SwapStatusDetailRowData row) {
  final label = row.label;
  if (label == 'Total fees') return 'Swap fee';
  return label;
}

String _mobileStatusDetailDisplayValue(SwapStatusDetailRowData row) {
  final source = row.copyText?.trim();
  if (source == null || source.isEmpty) return row.value;
  if (!_shouldCompactMobileStatusDetailValue(row, source)) return row.value;
  return compactSwapAddress(
    source,
    maxLength: 14,
    prefixLength: 6,
    suffixLength: 5,
    separator: '…',
  );
}

bool _shouldCompactMobileStatusDetailValue(
  SwapStatusDetailRowData row,
  String source,
) {
  if (source.length <= 18) return false;
  final label = row.label.toLowerCase();
  return label.contains('address') ||
      label.contains('recipient') ||
      label.contains('refund') ||
      label == 'tx id' ||
      label.contains(' tx') ||
      (label.startsWith('deposit ') && label.endsWith(' to'));
}

class _MobileStatusDetailActionIcon extends StatelessWidget {
  const _MobileStatusDetailActionIcon({
    required this.icon,
    required this.tooltipMessage,
  });

  final String icon;
  final String? tooltipMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = MouseRegion(
      cursor: tooltipMessage == null
          ? SystemMouseCursors.click
          : SystemMouseCursors.help,
      child: AppIcon(
        icon,
        size: _mobileStatusDetailIconSize,
        color: colors.icon.regular.withValues(alpha: 0.72),
      ),
    );
    final message = tooltipMessage;
    if (message == null ||
        message.isEmpty ||
        Overlay.maybeOf(context) == null) {
      return child;
    }
    return AppTooltip(message: message, tapToShow: true, child: child);
  }
}

String _mobileStatusHelpTooltip(String label) {
  return switch (label) {
    'Swap fee' => swapFeeTooltip,
    'Guaranteed minimum' => swapGenericMinimumReceiveTooltip,
    'Total fees' => swapTotalFeesTooltip,
    _ => swapStatusDetailTooltip,
  };
}
