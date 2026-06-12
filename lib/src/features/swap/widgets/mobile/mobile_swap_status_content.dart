import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../models/swap_activity_status_mapper.dart'
    show SwapActivityStatusPresentation;
import '../../models/swap_status_presentation.dart';
import '../swap_status_page_content.dart'
    show SwapAnimatedProgressRoute, SwapTransactionDetails;
import 'mobile_swap_review_header.dart';

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
    required this.onOpenExplorer,
    super.key,
  });

  final SwapActivityStatusPresentation presentation;
  final MobileSwapReviewHeaderRow payHeaderRow;
  final MobileSwapReviewHeaderRow receiveHeaderRow;
  final SwapStatusTab activeTab;
  final bool detailsExpanded;
  final ValueChanged<SwapStatusTab> onTabChanged;
  final VoidCallback onToggleDetails;
  final VoidCallback onOpenExplorer;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('mobile_swap_status_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSwapReviewHeader(pay: payHeaderRow, receive: receiveHeaderRow),
        const SizedBox(height: AppSpacing.s),
        if (presentation.showTabs) ...[
          _MobileStatusTabs(activeTab: activeTab, onChanged: onTabChanged),
          const SizedBox(height: AppSpacing.sm),
          _StatusCard(
            child: activeTab == SwapStatusTab.progress
                ? SwapAnimatedProgressRoute(
                    steps: presentation.steps,
                    progressIndex: presentation.progressIndex,
                    badgeKind: presentation.badgeKind,
                  )
                : SwapTransactionDetails(
                    rows: presentation.details,
                    expanded: detailsExpanded,
                    onToggleExpanded: onToggleDetails,
                  ),
          ),
        ] else
          _StatusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileStatusChipRow(badgeKind: presentation.badgeKind),
                const SizedBox(height: AppSpacing.sm),
                _MobileFinalDetails(rows: presentation.details),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: _NearIntentsExplorerLink(onTap: onOpenExplorer),
        ),
      ],
    );
  }
}

/// White rounded surface hosting the tab content — the Figma frames
/// put the timeline and the detail rows on `foreground.neutral.ground`.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
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
  const _MobileStatusTabs({required this.activeTab, required this.onChanged});

  final SwapStatusTab activeTab;
  final ValueChanged<SwapStatusTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          _MobileStatusTabLabel(
            key: const ValueKey('mobile_swap_status_tab_progress'),
            label: 'Swap progress',
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
class _MobileFinalDetails extends StatelessWidget {
  const _MobileFinalDetails({required this.rows});

  final List<SwapStatusDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final feeIndex = rows.indexWhere(
      (row) => row.label.toLowerCase().contains('fee'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0 && i != feeIndex) const SizedBox(height: AppSpacing.xs),
          if (i == feeIndex) ...[
            const SizedBox(height: AppSpacing.sm),
            // Figma `border/neutral/default`.
            Container(height: 1, color: colors.border.regular),
            const SizedBox(height: AppSpacing.sm),
          ],
          _MobileFinalDetailRow(row: rows[i]),
        ],
      ],
    );
  }
}

class _MobileFinalDetailRow extends StatelessWidget {
  const _MobileFinalDetailRow({required this.row});

  final SwapStatusDetailRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              row.label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
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
              child: Text(
                row.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearIntentsExplorerLink extends StatelessWidget {
  const _NearIntentsExplorerLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('mobile_swap_status_explorer_link'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View on Near Intents',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                AppIcons.arrowTopRight,
                size: AppIconSize.medium,
                color: colors.icon.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
