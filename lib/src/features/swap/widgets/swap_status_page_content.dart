import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../address_book/widgets/address_book_network_icon.dart';
import '../models/swap_detail_tooltips.dart';
import '../models/swap_models.dart';
import '../models/swap_status_presentation.dart';
import 'swap_review_info.dart';

export '../models/swap_status_presentation.dart';

const swapStatusDefaultProgressAdvanceInterval = Duration(milliseconds: 520);
const _swapStatusDetailIconSize = 16.0;

/// In-progress / details / completed surface for a swap intent.
///
/// Layout (all states):
/// title → [SwapReviewInfo] → then, for non-terminal intents, the centered
/// Simple Tabs over the progress route or the detail card; for terminal
/// intents a single detail card that leads with the Status row.
class SwapStatusPageContent extends StatefulWidget {
  const SwapStatusPageContent({
    required this.title,
    required this.payAsset,
    required this.receiveAsset,
    required this.payAmountText,
    required this.receiveAmountText,
    required this.payDetailText,
    required this.receiveDetailText,
    required this.statusLabel,
    required this.badgeKind,
    this.payDetailCopyText,
    this.receiveDetailCopyText,
    this.progressIndex = 0,
    this.progressAdvanceInterval = swapStatusDefaultProgressAdvanceInterval,
    this.activeTab = SwapStatusTab.progress,
    this.steps = const [],
    this.details = const [],
    this.showTabs = true,
    this.onTabChanged,
    this.onCopy,
    super.key,
  });

  final String title;
  final SwapAsset payAsset;
  final SwapAsset receiveAsset;
  final String payAmountText;
  final String receiveAmountText;

  /// Bottom line of the pay summary row: fiat value, or the refund address
  /// line for external→ZEC swaps.
  final String payDetailText;

  /// Bottom line of the receive summary row: fiat value, or the recipient
  /// address line for ZEC→external swaps.
  final String receiveDetailText;

  /// Full address copied by the pay/receive row's copy affordance, when the
  /// line shows an address rather than a fiat value.
  final String? payDetailCopyText;
  final String? receiveDetailCopyText;

  /// User-facing status label shown in the terminal Status row.
  final String statusLabel;
  final SwapStatusBadgeKind badgeKind;
  final int progressIndex;
  final Duration progressAdvanceInterval;
  final SwapStatusTab activeTab;
  final List<SwapStatusStepData> steps;
  final List<SwapStatusDetailRowData> details;
  final bool showTabs;
  final ValueChanged<SwapStatusTab>? onTabChanged;

  /// Copy callback for the [SwapReviewInfo] address lines (clipboard + toast).
  final ValueChanged<String>? onCopy;

  @override
  State<SwapStatusPageContent> createState() => _SwapStatusPageContentState();
}

class _SwapStatusPageContentState extends State<SwapStatusPageContent> {
  Timer? _progressAdvanceTimer;
  late int _displayProgressIndex;

  @override
  void initState() {
    super.initState();
    _displayProgressIndex = _boundedProgressIndex(widget.progressIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDisplayedProgress();
  }

  @override
  void didUpdateWidget(covariant SwapStatusPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stepsChanged = oldWidget.steps.length != widget.steps.length;
    final resetTarget =
        oldWidget.badgeKind != widget.badgeKind ||
        oldWidget.activeTab != widget.activeTab ||
        oldWidget.showTabs != widget.showTabs ||
        stepsChanged;
    if (resetTarget) {
      _progressAdvanceTimer?.cancel();
      _progressAdvanceTimer = null;
      _displayProgressIndex = _boundedProgressIndex(widget.progressIndex);
      return;
    }
    _syncDisplayedProgress();
  }

  @override
  void dispose() {
    _progressAdvanceTimer?.cancel();
    super.dispose();
  }

  int _boundedProgressIndex(int index) {
    if (widget.steps.isEmpty) return 0;
    return index.clamp(0, widget.steps.length - 1);
  }

  bool get _shouldAnimateProgress {
    if (!widget.showTabs || widget.activeTab != SwapStatusTab.progress) {
      return false;
    }
    if (widget.badgeKind != SwapStatusBadgeKind.liveQuote) return false;
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  void _syncDisplayedProgress() {
    final targetIndex = _boundedProgressIndex(widget.progressIndex);
    if (!_shouldAnimateProgress || targetIndex <= _displayProgressIndex) {
      _progressAdvanceTimer?.cancel();
      _progressAdvanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    if (targetIndex == _displayProgressIndex + 1) {
      _progressAdvanceTimer?.cancel();
      _progressAdvanceTimer = null;
      setState(() => _displayProgressIndex = targetIndex);
      return;
    }

    _advanceDisplayedProgress();
    _progressAdvanceTimer ??= Timer.periodic(
      widget.progressAdvanceInterval,
      (_) => _advanceDisplayedProgress(),
    );
  }

  void _advanceDisplayedProgress() {
    if (!mounted) return;
    final targetIndex = _boundedProgressIndex(widget.progressIndex);
    if (!_shouldAnimateProgress || targetIndex <= _displayProgressIndex) {
      _progressAdvanceTimer?.cancel();
      _progressAdvanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    final nextIndex = _displayProgressIndex + 1;
    setState(() => _displayProgressIndex = nextIndex);
    if (nextIndex >= targetIndex) {
      _progressAdvanceTimer?.cancel();
      _progressAdvanceTimer = null;
    }
  }

  List<SwapStatusStepData> _displayedSteps() {
    if (widget.steps.isEmpty) return const [];
    return [
      for (var index = 0; index < widget.steps.length; index++)
        widget.steps[index].copyWithState(
          index < _displayProgressIndex
              ? SwapStatusStepState.complete
              : index == _displayProgressIndex
              ? SwapStatusStepState.active
              : SwapStatusStepState.pending,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('swap_status_page_content'),
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            key: const ValueKey('swap_status_title'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          SwapReviewInfo(
            pay: SwapReviewInfoSideData(
              asset: widget.payAsset,
              label: "You're paying",
              amountText: widget.payAmountText,
              detailText: widget.payDetailText,
              detailCopyText: widget.payDetailCopyText,
            ),
            receive: SwapReviewInfoSideData(
              asset: widget.receiveAsset,
              label: "You're receiving",
              amountText: widget.receiveAmountText,
              detailText: widget.receiveDetailText,
              detailCopyText: widget.receiveDetailCopyText,
            ),
            onCopy: widget.onCopy,
          ),
          const SizedBox(height: AppSpacing.base),
          if (widget.showTabs) ...[
            // The Figma `Swap Tabs` frame nominally adds a 12px inset above
            // the tabs, but the design frame overflows its own 720px window
            // by more than that — reproducing the inset makes the progress
            // tab scroll at the reference window height. The page must fit
            // without a scrollbar (all status frames hide the Scrollbar
            // instance), so the inset is intentionally dropped.
            _StatusTabs(
              activeTab: widget.activeTab,
              onChanged: widget.onTabChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (widget.activeTab == SwapStatusTab.progress)
              _SwapDetailCard(
                child: _SwapProgressRoute(steps: _displayedSteps()),
              )
            else
              _SwapDetailCard(child: _SwapDetailRows(rows: widget.details)),
          ] else
            _SwapDetailCard(
              child: _SwapTerminalDetails(
                statusLabel: widget.statusLabel,
                badgeKind: widget.badgeKind,
                rows: widget.details,
              ),
            ),
        ],
      ),
    );
  }
}

/// Figma 'Review Wrap': the raised, rounded detail card that wraps the
/// progress route and the detail rows. Built on the core [ReviewWrapCard].
class _SwapDetailCard extends StatelessWidget {
  const _SwapDetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ReviewWrapCard(
      key: const ValueKey('swap_status_detail_card'),
      children: [child],
    );
  }
}

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.activeTab, required this.onChanged});

  final SwapStatusTab activeTab;
  final ValueChanged<SwapStatusTab>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('swap_status_tabs'),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusTabLabel(
              label: 'Swap Progress',
              active: activeTab == SwapStatusTab.progress,
              onTap: () => onChanged?.call(SwapStatusTab.progress),
            ),
            const SizedBox(width: AppSpacing.xs),
            _StatusTabLabel(
              label: 'Transaction details',
              active: activeTab == SwapStatusTab.details,
              onTap: () => onChanged?.call(SwapStatusTab.details),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTabLabel extends StatelessWidget {
  const _StatusTabLabel({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = active
        ? AppTypography.bodyMediumStrong.copyWith(color: colors.text.accent)
        : AppTypography.bodyMedium.copyWith(
            color: colors.text.accent.withValues(alpha: 0.5),
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey(
          label == 'Transaction details'
              ? 'swap_status_tab_details'
              : 'swap_status_tab_progress',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: active ? null : onTap,
        child: Padding(
          // Figma `tab`: 4px horizontal / 2px vertical inset (25px row).
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: 2,
          ),
          child: Text(label, maxLines: 1, softWrap: false, style: style),
        ),
      ),
    );
  }
}

class _SwapProgressRoute extends StatelessWidget {
  const _SwapProgressRoute({required this.steps});

  final List<SwapStatusStepData> steps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('swap_progress_route'),
      // Figma `_Swap Route`: 12px vertical inset inside the card, full width.
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            _ProgressStep(
              index: index,
              count: steps.length,
              step: steps[index],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.index,
    required this.count,
    required this.step,
  });

  final int index;
  final int count;
  final SwapStatusStepData step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = step.state == SwapStatusStepState.active;
    final isLast = index == count - 1;
    // Fixed per-step heights reproduce the Figma connector lengths: the active
    // step reserves room for its 2-line description (24 title + 8 gap + 58
    // padded description), pending/complete steps a single title row, and the
    // last step has no trailing connector.
    final height = active ? 90.0 : (isLast ? 24.0 : 37.0);
    final title = step.titleForState(step.state);
    return SizedBox(
      key: ValueKey('swap_activity_route_step_${index}_${step.state.name}'),
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: height,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _ProgressStepIcon(step: step),
                ),
                if (!isLast)
                  Positioned(
                    key: ValueKey('swap_activity_route_step_${index}_line'),
                    // The icon is 24 high; the connector starts 8px below it
                    // and runs to the bottom of the step.
                    top: 32,
                    bottom: 0,
                    left: 10.5,
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.border.subtle,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  key: ValueKey('swap_activity_route_step_${index}_title_row'),
                  height: 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Figma keeps every step title on the accent color
                          // (light #141818 / dark #FFFFFF); only the weight
                          // distinguishes the active step.
                          style: AppTypography.labelLarge.copyWith(
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      if (active && step.lastCheckedLabel != null) ...[
                        const SizedBox(width: AppSpacing.s),
                        Text(
                          step.lastCheckedLabel!,
                          style: AppTypography.labelMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (active && step.description != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  // Figma pads the description block vertically (8px above
                  // and below the 2-line text), flush with the title column.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      step.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStepIcon extends StatelessWidget {
  const _ProgressStepIcon({required this.step});

  final SwapStatusStepData step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final complete = step.state == SwapStatusStepState.complete;
    final active = step.state == SwapStatusStepState.active;
    final animateLoader =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active || complete
            ? colors.background.inverse
            : colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: active
          ? AppIcon(
              AppIcons.loader,
              key: const ValueKey('swap_status_active_step_loader'),
              size: 16,
              color: colors.icon.inverse,
              animated: animateLoader,
            )
          : complete
          ? AppIcon(AppIcons.check, size: 16, color: colors.icon.inverse)
          : AppIcon(
              _pendingProgressIcon(step),
              size: 16,
              color: colors.icon.muted,
            ),
    );
  }
}

String _pendingProgressIcon(SwapStatusStepData step) {
  final title = step.title.toLowerCase();
  if (title.contains('swap')) return AppIcons.swapArrows;
  if (title.contains('send')) return AppIcons.arrowDownCircle;
  return AppIcons.check;
}

/// Detail-rows column for the non-terminal Transaction details tab. The fee
/// row (the last row) is separated from the rows above by a hairline divider.
class _SwapDetailRows extends StatelessWidget {
  const _SwapDetailRows({required this.rows});

  final List<SwapStatusDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('swap_status_detail_rows'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _detailRowsWithFeeDivider(rows),
    );
  }
}

/// Terminal (completed / failed) detail card: a leading Status row, the
/// presentation detail rows, and the fee row separated by a hairline divider.
class _SwapTerminalDetails extends StatelessWidget {
  const _SwapTerminalDetails({
    required this.statusLabel,
    required this.badgeKind,
    required this.rows,
  });

  final String statusLabel;
  final SwapStatusBadgeKind badgeKind;
  final List<SwapStatusDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('swap_final_details'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusRow(label: statusLabel, badgeKind: badgeKind),
        // Figma keeps the Status row in its own `List` group, separated from
        // the metadata rows by the card's 16px group gap.
        const SizedBox(height: AppSpacing.sm),
        ..._detailRowsWithFeeDivider(rows),
      ],
    );
  }
}

/// Renders [rows] as detail rows, inserting the shared hairline divider before
/// the final fee row when the last row is one — the in-progress and terminal
/// detail lists end with `Swap fee` / `Total fees`, but the incomplete-deposit
/// list ends with a deposit-tx row and gets no divider.
List<Widget> _detailRowsWithFeeDivider(List<SwapStatusDetailRowData> rows) {
  if (rows.isEmpty) return const [];
  final lastIndex = rows.length - 1;
  final dividerBeforeLast = rows.length > 1 && _isFeeRow(rows[lastIndex].label);
  return [
    for (var index = 0; index < rows.length; index++) ...[
      if (index == lastIndex && dividerBeforeLast) const _DetailDivider(),
      _DetailRow(row: rows[index]),
    ],
  ];
}

bool _isFeeRow(String label) {
  return label == 'Swap fee' ||
      label == 'Total fees' ||
      label == 'Tx fee' ||
      label == 'Refund fee';
}

class _DetailDivider extends StatelessWidget {
  const _DetailDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      key: const ValueKey('swap_status_detail_divider'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: SizedBox(
        height: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.border.regular),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.badgeKind});

  final String label;
  final SwapStatusBadgeKind badgeKind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failed = badgeKind == SwapStatusBadgeKind.failed;
    final signalColor = failed
        ? colors.text.destructive
        : colors.text.positiveStrong;
    return ReviewListRow(
      key: const ValueKey('swap_status_summary_row'),
      label: 'Status',
      value: label,
      valueColor: signalColor,
      leadingIconName: failed ? AppIcons.warning : AppIcons.checkCircle,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.row});

  final SwapStatusDetailRowData row;

  @override
  Widget build(BuildContext context) {
    // The matched address-book identity cell keeps its bespoke two-line layout.
    if (row.addressBookLabel != null) {
      final cell = _matchedAddressCell(context);
      if (!row.copyable) return cell;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => copyTextWithToast(
            context,
            text: row.copyText ?? row.value,
            toastMessage: 'Copied',
          ),
          child: cell,
        ),
      );
    }

    final colors = context.colors;
    final linkUri = row.linkUri;
    // A row may be both copyable and linkable (e.g. the terminal deposit-tx
    // row). The Figma shows the external-link arrow there, so the link
    // affordance wins for both the icon and the tap target — no copy glyph.
    if (linkUri != null) {
      return ReviewListRow(
        label: row.label,
        value: row.value,
        trailingIconName: AppIcons.arrowTopRight,
        trailingIconColor: colors.icon.muted,
        onPressed: () =>
            unawaited(launchUrl(linkUri, mode: LaunchMode.externalApplication)),
      );
    }

    if (row.help) {
      return ReviewListRow(
        label: row.label,
        value: row.value,
        trailingIconName: AppIcons.help,
        trailingIconColor: colors.icon.muted,
        trailingIconTooltip:
            row.helpTooltip ?? _swapStatusHelpTooltip(row.label),
      );
    }

    return ReviewListRow(
      label: row.label,
      value: row.value,
      copyText: row.copyable ? (row.copyText ?? row.value) : null,
    );
  }

  /// Renders an address row that matches a saved address-book contact. The
  /// first line keeps the regular two-column detail-row geometry; the metadata
  /// line below is right-aligned across the full row so the network and compact
  /// address are not squeezed into the value column.
  Widget _matchedAddressCell(BuildContext context) {
    final colors = context.colors;
    final network = row.addressNetwork;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            row.addressBookLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        AppIcon(
                          AppIcons.user,
                          size: 14,
                          color: colors.icon.brandCrimson,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (network != null) ...[
                      AddressBookNetworkIcon(network: network, size: 14),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        network.label,
                        maxLines: 1,
                        style: AppTypography.labelSmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Text(
                      row.value,
                      maxLines: 1,
                      style: AppTypography.codeSmall.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                    if (row.copyable) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      const _StatusDetailActionIcon(
                        icon: AppIcons.copy,
                        tooltipMessage: null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDetailActionIcon extends StatelessWidget {
  const _StatusDetailActionIcon({
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
        size: _swapStatusDetailIconSize,
        color: colors.icon.muted,
      ),
    );
    final message = tooltipMessage;
    if (message == null ||
        message.isEmpty ||
        Overlay.maybeOf(context) == null) {
      return child;
    }
    return AppTooltip(message: message, child: child);
  }
}

String _swapStatusHelpTooltip(String label) {
  return switch (label) {
    'Swap fee' => swapFeeTooltip,
    'Guaranteed minimum' => swapGenericMinimumReceiveTooltip,
    'Total fees' => swapTotalFeesTooltip,
    _ => swapStatusDetailTooltip,
  };
}
