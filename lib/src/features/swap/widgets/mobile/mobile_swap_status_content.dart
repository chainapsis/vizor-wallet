import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_copy_feedback.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_tooltip.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../../../../core/widgets/review_info_row.dart';
import '../../domain/swap_contract.dart';
import '../../models/swap_address_formatting.dart';
import '../../models/swap_activity_status_mapper.dart'
    show PayActivityStatusPhase, SwapActivityStatusPresentation;
import '../../models/swap_status_presentation.dart';
import '../swap_asset_icon.dart';
import '../swap_status_page_content.dart' show SwapAnimatedProgressRoute;
import '../swap_progress_explorer_footer.dart';
import 'mobile_swap_review_header.dart';
import '../../../../core/l10n/l10n.dart';

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
    this.paymentHeader,
    this.flowConnector,
    super.key,
  });

  final SwapActivityStatusPresentation presentation;
  final MobileSwapReviewHeaderRow payHeaderRow;
  final MobileSwapReviewHeaderRow receiveHeaderRow;
  final SwapStatusTab activeTab;
  final bool detailsExpanded;
  final ValueChanged<SwapStatusTab> onTabChanged;
  final VoidCallback onToggleDetails;
  final Widget? paymentHeader;

  /// Optional replacement for the paying/receiving flow arrow row.
  final Widget? flowConnector;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('mobile_swap_status_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (presentation.paymentMode) const SizedBox(height: AppSpacing.s),
        paymentHeader ??
            MobileSwapReviewHeader(
              pay: payHeaderRow,
              receive: receiveHeaderRow,
              flowConnector: flowConnector,
            ),
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
            hasExplorerFooter:
                activeTab == SwapStatusTab.progress &&
                presentation.explorerUri != null,
            child: activeTab == SwapStatusTab.progress
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwapAnimatedProgressRoute(
                        steps: presentation.steps,
                        progressIndex: presentation.progressIndex,
                        badgeKind: presentation.badgeKind,
                      ),
                      if (presentation.explorerUri case final uri?)
                        SwapProgressExplorerFooter(uri: uri),
                    ],
                  )
                : presentation.paymentMode && presentation.payStatus != null
                ? _MobilePaymentDetails(presentation: presentation)
                : _MobileTransactionDetails(rows: presentation.details),
          ),
        ] else ...[
          if (presentation.paymentMode) const SizedBox(height: 48),
          _StatusCard(
            key: const ValueKey('mobile_swap_status_card'),
            child: presentation.paymentMode && presentation.payStatus != null
                ? _MobilePaymentDetails(presentation: presentation)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _MobileStatusChipRow(badgeKind: presentation.badgeKind),
                      const SizedBox(height: AppSpacing.sm),
                      _MobileFinalDetails(
                        rows: presentation.details,
                        hideSuccessAddressRows:
                            presentation.badgeKind ==
                            SwapStatusBadgeKind.completed,
                      ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

/// Pay activity header from the mobile `Paying` / `Paid` frames. Unlike the
/// swap header, the primary amount is the delivered payment asset and the
/// second row identifies the recipient rather than repeating another asset.
class MobilePayStatusHeader extends StatelessWidget {
  const MobilePayStatusHeader({
    required this.asset,
    required this.amountText,
    required this.fiatText,
    required this.recipientAddress,
    this.label,
    this.recipientName,
    this.recipientProfilePictureId,
    this.flowConnector,
    super.key,
  });

  final SwapAsset asset;
  final String amountText;
  final String fiatText;
  final String recipientAddress;
  final String? label;
  final String? recipientName;
  final String? recipientProfilePictureId;

  /// Optional replacement for the amount-to-recipient arrow.
  final Widget? flowConnector;

  @override
  Widget build(BuildContext context) {
    final compactAddress = compactSwapAddress(
      recipientAddress,
      maxLength: 15,
      prefixLength: 7,
      suffixLength: 5,
      separator: '...',
    );
    final name = recipientName?.trim();
    final profilePictureId = recipientProfilePictureId?.trim();
    return ConstrainedBox(
      key: const ValueKey('mobile_pay_status_header'),
      constraints: const BoxConstraints(minHeight: 252),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ReviewInfoFlow(
          connector: flowConnector,
          rows: [
            ReviewInfoRow(
              key: const ValueKey('mobile_pay_status_asset_row'),
              leading: SwapAssetIcon(
                asset: asset,
                size: 40,
                showChainBadge: !asset.isNativeZec,
              ),
              label: label ?? context.l10n.commonYourePaying,
              value: amountText,
              valueFit: BoxFit.scaleDown,
              bottomLeftText: fiatText,
            ),
            ReviewInfoRow(
              key: const ValueKey('mobile_pay_status_recipient_row'),
              leading: profilePictureId != null && profilePictureId.isNotEmpty
                  ? AppProfilePicture(
                      profilePictureId: profilePictureId,
                      size: AppProfilePictureSize.navLarge,
                    )
                  : _MobilePayRecipientPlaceholder(),
              label: context.l10n.commonTo,
              value: name == null || name.isEmpty ? compactAddress : name,
              bottomLeftText: name == null || name.isEmpty
                  ? null
                  : compactAddress,
              trailingActionLabel: context.l10n.commonFullAddress,
              trailingActionKey: const ValueKey(
                'mobile_pay_status_full_address',
              ),
              onTrailingAction: () => showMobileAddressVerifySheet(
                context,
                title: context.l10n.commonAddressForChain(asset.chainLabel),
                address: recipientAddress,
                leading: SwapAssetIcon(
                  asset: asset,
                  size: 32,
                  showChainBadge: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobilePayRecipientPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          AppIcons.user,
          size: 20,
          color: context.colors.icon.muted,
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.child,
    this.hasExplorerFooter = false,
    super.key,
  });

  final Widget child;
  final bool hasExplorerFooter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
        hasExplorerFooter ? AppSpacing.sm : AppSpacing.base,
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
              label: context.l10n.swapStatusDetailsTab,
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
  const _MobileStatusChipRow({
    required this.badgeKind,
    this.paymentMode = false,
  });

  final SwapStatusBadgeKind badgeKind;
  final bool paymentMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (iconName, defaultText, defaultColor) = switch (badgeKind) {
      SwapStatusBadgeKind.completed => (
        AppIcons.checkCircle,
        context.l10n.commonCompleted,
        colors.text.positiveStrong,
      ),
      SwapStatusBadgeKind.refunded => (
        AppIcons.uturnUp,
        context.l10n.commonRefunded,
        colors.text.positiveStrong,
      ),
      SwapStatusBadgeKind.failed => (
        AppIcons.cross,
        context.l10n.commonFailed,
        colors.text.destructive,
      ),
      SwapStatusBadgeKind.warning => (
        AppIcons.warning,
        context.l10n.swapStatusBadgeNeedsAttention,
        colors.text.warning,
      ),
      SwapStatusBadgeKind.liveQuote => (
        AppIcons.loader,
        context.l10n.commonInProgress,
        colors.text.secondary,
      ),
    };
    final paymentInProgress =
        paymentMode && badgeKind == SwapStatusBadgeKind.liveQuote;
    final text = defaultText;
    final textColor = paymentInProgress ? colors.text.primary : defaultColor;
    final iconColor = paymentInProgress ? colors.icon.regular : defaultColor;
    final labelStyle = paymentMode
        ? AppTypography.labelLarge
        : AppTypography.labelMedium;
    return SizedBox(
      key: paymentMode ? const ValueKey('mobile_pay_status_row') : null,
      height: 32,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              context.l10n.swapStatusRowLabel,
              style: labelStyle.copyWith(
                color: badgeKind == SwapStatusBadgeKind.failed
                    ? colors.text.destructive
                    : colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.xxs,
                AppSpacing.xxs,
                AppSpacing.xxs,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    key: paymentMode
                        ? const ValueKey('mobile_pay_status_value')
                        : null,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(iconName, size: 20, color: iconColor),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        text,
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: paymentMode
                              ? FontWeight.w500
                              : FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePaymentDetails extends StatelessWidget {
  const _MobilePaymentDetails({required this.presentation});

  final SwapActivityStatusPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final payStatus = presentation.payStatus;
    final timestamp = payStatus == null
        ? _paymentDetailRow(
            presentation.details,
            SwapStatusDetailKind.timestamp,
          )
        : SwapStatusDetailRowData(
            label: context.l10n.commonTimestamp,
            kind: SwapStatusDetailKind.timestamp,
            value: payStatus.timestampText,
          );
    final txId = payStatus == null
        ? _paymentDetailRow(presentation.details, SwapStatusDetailKind.txId)
        : SwapStatusDetailRowData(
            label: context.l10n.commonTxId,
            kind: SwapStatusDetailKind.txId,
            value: payStatus.txIdText,
            linkUri: payStatus.txIdUri,
            copyable: payStatus.txIdCopyText != null,
            copyText: payStatus.txIdCopyText,
          );
    final convertedFrom = SwapStatusDetailRowData(
      label: context.l10n.swapPayStatusConvertedFrom,
      value: payStatus?.convertedFromText ?? presentation.payAmountText,
    );
    final displayFee = payStatus == null
        ? null
        : SwapStatusDetailRowData(
            label: context.l10n.txFeeInfoTitle,
            kind: SwapStatusDetailKind.txFee,
            value: payStatus.transactionFeeText,
            help: true,
            helpTooltip: context.l10n.txFeeHelpTooltip,
          );
    final terminalOutcome =
        payStatus?.phase == PayActivityStatusPhase.failed ||
        payStatus?.phase == PayActivityStatusPhase.refunded;
    final outcomeRows = <SwapStatusDetailRowData>[
      if (payStatus?.phase == PayActivityStatusPhase.failed)
        SwapStatusDetailRowData(
          label: context.l10n.swapPayStatusSourceAmount,
          value: payStatus!.convertedFromText,
        ),
      if (payStatus?.phase == PayActivityStatusPhase.refunded &&
          payStatus?.refundedAmountText?.isNotEmpty == true)
        SwapStatusDetailRowData(
          label: context.l10n.commonRefundedAmount,
          kind: SwapStatusDetailKind.refundedAmount,
          value: payStatus!.refundedAmountText!,
        ),
      if (terminalOutcome && payStatus?.refundAddress?.isNotEmpty == true)
        SwapStatusDetailRowData(
          label: context.l10n.commonRefundTo,
          kind: SwapStatusDetailKind.refundTo,
          value: compactSwapAddress(payStatus!.refundAddress!),
          copyable: true,
          copyText: payStatus.refundAddress,
        ),
      if (payStatus?.phase == PayActivityStatusPhase.refunded &&
          payStatus?.refundFeeText?.isNotEmpty == true)
        SwapStatusDetailRowData(
          label: context.l10n.commonRefundFee,
          kind: SwapStatusDetailKind.refundFee,
          value: payStatus!.refundFeeText!,
        ),
    ];
    return Column(
      key: const ValueKey('mobile_pay_status_details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileStatusChipRow(
          badgeKind: presentation.badgeKind,
          paymentMode: true,
        ),
        if (timestamp != null || txId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          if (timestamp != null)
            _MobileFinalDetailRow(row: timestamp, paymentMode: true),
          if (timestamp != null && txId != null)
            const SizedBox(height: AppSpacing.xs),
          if (txId != null)
            _MobileFinalDetailRow(
              row: txId,
              paymentMode: true,
              actionIconSize: 20,
              actionIconColor: context.colors.icon.muted,
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Container(height: 1, color: context.colors.border.regular),
        const SizedBox(height: AppSpacing.sm),
        if (terminalOutcome)
          for (final row in outcomeRows)
            _MobileFinalDetailRow(row: row, paymentMode: true)
        else ...[
          _MobileFinalDetailRow(
            row: convertedFrom,
            paymentMode: true,
            trailingIcon: AppIcons.shieldKeyhole,
            actionIconSize: 20,
            actionIconColor: context.colors.icon.accent,
          ),
          if (displayFee != null)
            _MobileFinalDetailRow(
              row: displayFee,
              paymentMode: true,
              actionIconSize: 20,
              actionIconColor: context.colors.icon.muted,
            ),
        ],
      ],
    );
  }
}

SwapStatusDetailRowData? _paymentDetailRow(
  Iterable<SwapStatusDetailRowData> rows,
  SwapStatusDetailKind kind,
) {
  for (final row in rows) {
    if (row.kind == kind) return row;
  }
  return null;
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
    // Like desktop, a recorded refund starts the outcome group so its amount
    // and fee stay together below the transaction metadata.
    final refundIndex = visibleRows.indexWhere(
      (row) => row.kind == SwapStatusDetailKind.refundedAmount,
    );
    final dividerIndex = refundIndex > 0
        ? refundIndex
        : visibleRows.indexWhere(_isMobileFeeDetailRow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visibleRows.length; i++) ...[
          if (i > 0 && i != dividerIndex) const SizedBox(height: AppSpacing.xs),
          if (i == dividerIndex) ...[
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
        return !row.kind.hiddenOnMobile &&
            (!hideSuccessAddressRows || !_isMobileSuccessAddressDetailRow(row));
      })
      .toList(growable: false);
  final nonFeeRows = visible
      .where((row) => !_isMobileFeeDetailRow(row))
      .toList(growable: false);
  final feeRows = visible.where(_isMobileFeeDetailRow).toList(growable: false);
  return [...nonFeeRows, ...feeRows];
}

bool _isMobileProgressTransactionDetailRow(SwapStatusDetailRowData row) =>
    row.kind.inMobileProgressTransactionDetails;

bool _isMobileSuccessAddressDetailRow(SwapStatusDetailRowData row) =>
    row.kind.isSuccessAddress;

bool _isMobileFeeDetailRow(SwapStatusDetailRowData row) => row.kind.isFee;

class _MobileFinalDetailRow extends StatelessWidget {
  const _MobileFinalDetailRow({
    required this.row,
    this.trailingIcon,
    this.paymentMode = false,
    this.actionIconSize = _mobileStatusDetailIconSize,
    this.actionIconColor,
  });

  final SwapStatusDetailRowData row;
  final String? trailingIcon;
  final bool paymentMode;
  final double actionIconSize;
  final Color? actionIconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayLabel = _mobileStatusDetailLabel(context.l10n, row);
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
                    toastMessage: context.l10n.commonCopied,
                  );
                }
              }
            : null,
        child: LayoutBuilder(
          builder: (context, constraints) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            // The padding fits inside the default 32px row, so only wrapped
            // labels gain separation from the neighbouring rows.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      displayLabel,
                      style:
                          (paymentMode
                                  ? AppTypography.labelLarge
                                  : AppTypography.labelMedium)
                              .copyWith(color: colors.text.secondary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (constraints.maxWidth - AppSpacing.s) / 2,
                    ),
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
                        if (linkUri != null ||
                            row.copyable ||
                            row.help ||
                            trailingIcon != null) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          _MobileStatusDetailActionIcon(
                            icon:
                                trailingIcon ??
                                (linkUri != null
                                    ? AppIcons.arrowTopRight
                                    : row.copyable
                                    ? AppIcons.copy
                                    : AppIcons.help),
                            size: actionIconSize,
                            color: actionIconColor,
                            tooltipMessage: row.help
                                ? row.helpTooltip ??
                                      row.kind.helpTooltipFor(context.l10n)
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

String _mobileStatusDetailLabel(
  AppLocalizations l10n,
  SwapStatusDetailRowData row,
) {
  if (row.kind == SwapStatusDetailKind.totalFees) {
    return l10n.commonSwapFee;
  }
  return row.label;
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
  return row.kind.compactsValue;
}

class _MobileStatusDetailActionIcon extends StatelessWidget {
  const _MobileStatusDetailActionIcon({
    required this.icon,
    required this.tooltipMessage,
    this.size = _mobileStatusDetailIconSize,
    this.color,
  });

  final String icon;
  final String? tooltipMessage;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = MouseRegion(
      cursor: tooltipMessage == null
          ? SystemMouseCursors.click
          : SystemMouseCursors.help,
      child: AppIcon(
        icon,
        size: size,
        color: color ?? colors.icon.regular.withValues(alpha: 0.72),
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
