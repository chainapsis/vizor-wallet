import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../address_book/widgets/address_book_network_icon.dart';
import '../domain/swap_contract.dart';
import '../models/swap_detail_tooltips.dart';
import '../models/swap_status_presentation.dart';
import 'swap_amount_text.dart';
import 'swap_asset_icon.dart';
import 'swap_summary_amount_text.dart';

export '../models/swap_status_presentation.dart';

const swapStatusDefaultProgressAdvanceInterval = Duration(milliseconds: 520);
const _swapStatusSummaryMaxAmountChars = 10;
const _swapStatusProgressHeight = 580.0;
const _swapStatusSummaryCardHeight = 120.0;
const _swapStatusBadgeOverlap = 1.0;
const _swapStatusDetailIconSize = 14.0;

class SwapStatusPageContent extends StatefulWidget {
  const SwapStatusPageContent({
    required this.title,
    required this.payAsset,
    required this.receiveAsset,
    required this.payFiatText,
    required this.receiveFiatText,
    required this.payAmountText,
    required this.receiveAmountText,
    required this.badgeKind,
    this.progressIndex = 0,
    this.progressAdvanceInterval = swapStatusDefaultProgressAdvanceInterval,
    this.activeTab = SwapStatusTab.progress,
    this.steps = const [],
    this.details = const [],
    this.detailsExpanded = false,
    this.showTabs = true,
    this.onTabChanged,
    this.onToggleDetails,
    this.onOpenExplorer,
    super.key,
  });

  final String title;
  final SwapAsset payAsset;
  final SwapAsset receiveAsset;
  final String payFiatText;
  final String receiveFiatText;
  final String payAmountText;
  final String receiveAmountText;
  final SwapStatusBadgeKind badgeKind;
  final int progressIndex;
  final Duration progressAdvanceInterval;
  final SwapStatusTab activeTab;
  final List<SwapStatusStepData> steps;
  final List<SwapStatusDetailRowData> details;
  final bool detailsExpanded;
  final bool showTabs;
  final ValueChanged<SwapStatusTab>? onTabChanged;
  final VoidCallback? onToggleDetails;
  final VoidCallback? onOpenExplorer;

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
    final tabContent = widget.activeTab == SwapStatusTab.progress
        ? SwapProgressRoute(steps: _displayedSteps())
        : SwapTransactionDetails(
            rows: widget.details,
            expanded: widget.detailsExpanded,
            onToggleExpanded: widget.onToggleDetails,
          );
    return SizedBox(
      key: const ValueKey('swap_status_page_content'),
      width: 400,
      height: _swapStatusProgressHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    key: const ValueKey('swap_status_title'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.displaySmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _StatusSummaryCard(
                    payAsset: widget.payAsset,
                    receiveAsset: widget.receiveAsset,
                    payFiatText: widget.payFiatText,
                    receiveFiatText: widget.receiveFiatText,
                    payAmountText: widget.payAmountText,
                    receiveAmountText: widget.receiveAmountText,
                    badgeKind: widget.badgeKind,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (widget.showTabs) ...[
                    _StatusTabs(
                      activeTab: widget.activeTab,
                      onChanged: widget.onTabChanged,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (widget.activeTab == SwapStatusTab.details)
                      Flexible(fit: FlexFit.loose, child: tabContent)
                    else
                      tabContent,
                  ] else
                    Flexible(
                      fit: FlexFit.loose,
                      child: _SwapFinalDetails(rows: widget.details),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.center,
            child: _NearIntentsLink(onPressed: widget.onOpenExplorer),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
      ),
    );
  }
}

class _StatusSummaryCard extends StatelessWidget {
  const _StatusSummaryCard({
    required this.payAsset,
    required this.receiveAsset,
    required this.payFiatText,
    required this.receiveFiatText,
    required this.payAmountText,
    required this.receiveAmountText,
    required this.badgeKind,
  });

  final SwapAsset payAsset;
  final SwapAsset receiveAsset;
  final String payFiatText;
  final String receiveFiatText;
  final String payAmountText;
  final String receiveAmountText;
  final SwapStatusBadgeKind badgeKind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final failed = badgeKind == SwapStatusBadgeKind.failed;
    final payNeedsCompact = isLongSwapSummaryAmountText(payAmountText);
    final receiveNeedsCompact = isLongSwapSummaryAmountText(receiveAmountText);
    final bothSidesNeedCompact = payNeedsCompact && receiveNeedsCompact;
    final compactPayAmountText = compactSwapSummaryAmountText(
      payAmountText,
      forceCompactThousands: payNeedsCompact,
      maxCharacters: _swapStatusSummaryMaxAmountChars,
    );
    final compactReceiveAmountText = compactSwapSummaryAmountText(
      receiveAmountText,
      forceCompactThousands: receiveNeedsCompact,
      maxCharacters: _swapStatusSummaryMaxAmountChars,
    );
    final receiveNeedsWideSide =
        compactReceiveAmountText.length > compactPayAmountText.length;
    final leftWidth = bothSidesNeedCompact
        ? 184.0
        : receiveNeedsWideSide
        ? 160.0
        : 205.0;
    final arrowLeft = bothSidesNeedCompact
        ? 184.0
        : receiveNeedsWideSide
        ? 161.5
        : 206.5;
    final rightLeft = bothSidesNeedCompact
        ? 216.0
        : receiveNeedsWideSide
        ? 195.0
        : 240.0;
    final rightWidth = bothSidesNeedCompact
        ? 184.0
        : receiveNeedsWideSide
        ? 205.0
        : 160.0;
    return SizedBox(
      width: 400,
      height: 145,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            key: const ValueKey('swap_status_summary_card'),
            width: 400,
            height: _swapStatusSummaryCardHeight,
            decoration: BoxDecoration(
              color: colors.background.homeCard,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: leftWidth,
                  child: _SummarySide(
                    label: 'Pay',
                    fiatText: payFiatText,
                    amountText: compactPayAmountText,
                    asset: payAsset,
                  ),
                ),
                Positioned(
                  left: arrowLeft,
                  top: 0,
                  bottom: 0,
                  width: 32,
                  child: Opacity(
                    key: const ValueKey('swap_status_summary_divider_opacity'),
                    opacity: failed ? 0.5 : 1,
                    child: Center(
                      child: AppIcon(
                        AppIcons.arrowForwardIos,
                        size: 20,
                        color: colors.text.homeCard,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: rightLeft,
                  top: 0,
                  bottom: 0,
                  width: rightWidth,
                  child: Opacity(
                    key: const ValueKey('swap_status_summary_receive_opacity'),
                    opacity: failed ? 0.5 : 1,
                    child: _SummarySide(
                      label: 'Receive',
                      fiatText: receiveFiatText,
                      amountText: compactReceiveAmountText,
                      asset: receiveAsset,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: _swapStatusSummaryCardHeight - _swapStatusBadgeOverlap,
            child: _StatusBadge(kind: badgeKind),
          ),
        ],
      ),
    );
  }
}

class _SummarySide extends StatelessWidget {
  const _SummarySide({
    required this.label,
    required this.fiatText,
    required this.amountText,
    required this.asset,
  });

  final String label;
  final String fiatText;
  final String amountText;
  final SwapAsset asset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final baseColor = colors.text.homeCard;
    final mutedColor = colors.text.homeCard.withValues(alpha: 0.58);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(color: baseColor),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    fiatText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: mutedColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwapAssetIcon(
                  asset: asset,
                  size: 32,
                  showChainBadge: !asset.isNativeZec,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwapSummaryAmountText(
                        amountText: amountText,
                        asset: asset,
                        keyPrefix:
                            'swap_status_${label.toLowerCase()}_summary_amount',
                        style: AppTypography.labelLarge.copyWith(
                          color: baseColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        asset.chainLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: mutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.kind});

  final SwapStatusBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = switch (kind) {
      SwapStatusBadgeKind.liveQuote => 'In progress',
      SwapStatusBadgeKind.completed => 'Completed',
      SwapStatusBadgeKind.warning => 'Incomplete',
      SwapStatusBadgeKind.failed => 'Failed',
    };
    final icon = switch (kind) {
      SwapStatusBadgeKind.liveQuote => null,
      SwapStatusBadgeKind.completed => AppIcons.checkCircle,
      SwapStatusBadgeKind.warning => AppIcons.warning,
      SwapStatusBadgeKind.failed => AppIcons.skull,
    };
    final signalColor = switch (kind) {
      SwapStatusBadgeKind.liveQuote => colors.sync.lightSuccess,
      SwapStatusBadgeKind.completed => colors.sync.lightSuccess,
      SwapStatusBadgeKind.warning => colors.icon.warning,
      SwapStatusBadgeKind.failed => colors.text.destructive,
    };

    return SizedBox(
      key: ValueKey('swap_status_badge_${kind.name}'),
      width: 167,
      height: 25,
      child: CustomPaint(
        painter: _StatusBadgeNotchPainter(colors.background.homeCard),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 16,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon == null)
                    _LiveQuoteLed(color: signalColor)
                  else
                    AppIcon(icon, size: 16, color: signalColor),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.homeCard,
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

class _StatusBadgeNotchPainter extends CustomPainter {
  const _StatusBadgeNotchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(18, 0, 22, 0, 29, 13)
      ..cubicTo(33, 21, 41, size.height, 53, size.height)
      ..lineTo(size.width - 53, size.height)
      ..cubicTo(
        size.width - 41,
        size.height,
        size.width - 33,
        21,
        size.width - 29,
        13,
      )
      ..cubicTo(size.width - 22, 0, size.width - 18, 0, size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StatusBadgeNotchPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _LiveQuoteLed extends StatefulWidget {
  const _LiveQuoteLed({required this.color});

  final Color color;

  @override
  State<_LiveQuoteLed> createState() => _LiveQuoteLedState();
}

class _LiveQuoteLedState extends State<_LiveQuoteLed> {
  Timer? _timer;
  var _lit = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() => _lit = !_lit);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final dot = Container(
      key: const ValueKey('swap_status_live_quote_led'),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(AppRadii.full),
        boxShadow: [
          BoxShadow(color: widget.color.withValues(alpha: 0.42), blurRadius: 6),
        ],
      ),
    );
    if (reduceMotion) {
      return Opacity(
        key: const ValueKey('swap_status_live_quote_led_opacity'),
        opacity: 1,
        child: dot,
      );
    }
    return AnimatedOpacity(
      key: const ValueKey('swap_status_live_quote_led_opacity'),
      opacity: _lit ? 1 : 0.42,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubic,
      child: dot,
    );
  }
}

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.activeTab, required this.onChanged});

  static const _progressTabMinWidth = 94.0;
  static const _detailsTabMinWidth = 123.0;

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
              minWidth: _progressTabMinWidth,
              label: 'Swap Progress',
              active: activeTab == SwapStatusTab.progress,
              onTap: () => onChanged?.call(SwapStatusTab.progress),
            ),
            const SizedBox(width: AppSpacing.sm),
            _StatusTabLabel(
              minWidth: _detailsTabMinWidth,
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
    required this.minWidth,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final double minWidth;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: active ? colors.text.accent : colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class SwapProgressRoute extends StatelessWidget {
  const SwapProgressRoute({required this.steps, super.key});

  final List<SwapStatusStepData> steps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('swap_progress_route'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
    final complete = step.state == SwapStatusStepState.complete;
    final active = step.state == SwapStatusStepState.active;
    final isLast = index == count - 1;
    const isMobile = kAppFormFactor == AppFormFactor.mobile;
    final height = active ? (isMobile ? 112.0 : 84.0) : (isLast ? 24.0 : 37.0);
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
                          style: AppTypography.labelLarge.copyWith(
                            color: active || complete
                                ? colors.text.accent
                                : colors.text.secondary,
                          ),
                        ),
                      ),
                      if (!isMobile &&
                          active &&
                          step.lastCheckedLabel != null) ...[
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
                if (isMobile && active && step.lastCheckedLabel != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    step.lastCheckedLabel!,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
                if (active && step.description != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  if (isMobile)
                    Text(
                      step.description!,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    )
                  else
                    SizedBox(
                      width: 256,
                      child: Text(
                        step.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
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
              size: 20,
              color: colors.icon.inverse,
              animated: animateLoader,
            )
          : AppIcon(
              _inactiveProgressIcon(step),
              size: 16,
              color: complete ? colors.icon.inverse : colors.icon.muted,
            ),
    );
  }
}

String _inactiveProgressIcon(SwapStatusStepData step) {
  final title = step.title.toLowerCase();
  if (title.contains('swap')) return AppIcons.swapArrows;
  if (title.contains('send')) return AppIcons.arrowDownCircle;
  return AppIcons.check;
}

class SwapTransactionDetails extends StatefulWidget {
  const SwapTransactionDetails({
    required this.rows,
    required this.expanded,
    super.key,
    required this.onToggleExpanded,
  });

  final List<SwapStatusDetailRowData> rows;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  State<SwapTransactionDetails> createState() => SwapTransactionDetailsState();
}

class SwapTransactionDetailsState extends State<SwapTransactionDetails> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.expanded) {
      _scrollToExpandedContentAfterLayout();
    }
  }

  @override
  void didUpdateWidget(covariant SwapTransactionDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.expanded && widget.expanded) {
      _scrollToExpandedContentAfterLayout();
    }
  }

  void _scrollToExpandedContentAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final anchorIndex = _transactionDetailsAnchorIndex(widget.rows);
    final anchorRow = anchorIndex == -1 ? null : widget.rows[anchorIndex];
    final leadingRows = anchorIndex == -1
        ? widget.rows
        : widget.rows.take(anchorIndex).toList();
    final extraRows = anchorIndex == -1
        ? const <SwapStatusDetailRowData>[]
        : widget.rows.skip(anchorIndex + 1).toList();
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.expanded
          ? [
              for (final row in leadingRows) _InsetDetailRow(row: row),
              if (leadingRows.isNotEmpty) const SizedBox(height: AppSpacing.sm),
              if (anchorRow != null) _InsetDetailRow(row: anchorRow),
              const SizedBox(height: AppSpacing.sm),
              _InsetDetailRow(
                row: const SwapStatusDetailRowData(
                  label: 'Less details',
                  value: '',
                ),
                chevronUp: true,
                onTap: widget.onToggleExpanded,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final row in extraRows) _InsetDetailRow(row: row),
            ]
          : [
              for (final row in leadingRows) _InsetDetailRow(row: row),
              if (anchorRow != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _InsetDetailRow(row: anchorRow),
              ],
              if (extraRows.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _InsetDetailRow(
                  row: const SwapStatusDetailRowData(
                    label: 'More details',
                    value: '',
                  ),
                  onTap: widget.onToggleExpanded,
                ),
              ],
            ],
    );

    if (!widget.expanded) {
      return _StatusDetailsScrollView(
        key: const ValueKey('swap_transaction_details_collapsed_scroll_view'),
        child: KeyedSubtree(
          key: const ValueKey('swap_transaction_details_collapsed'),
          child: content,
        ),
      );
    }

    return SizedBox(
      key: const ValueKey('swap_transaction_details_expanded'),
      height: 192,
      child: RawScrollbar(
        key: const ValueKey('swap_transaction_details_scrollbar'),
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 6,
        radius: const Radius.circular(AppRadii.full),
        mainAxisMargin: 3,
        crossAxisMargin: 3,
        thumbColor: colors.background.overlay,
        child: SingleChildScrollView(
          key: const ValueKey('swap_transaction_details_scroll_view'),
          controller: _scrollController,
          child: content,
        ),
      ),
    );
  }
}

int _transactionDetailsAnchorIndex(List<SwapStatusDetailRowData> rows) {
  final swapFeeIndex = rows.indexWhere((row) => row.label == 'Swap fee');
  if (swapFeeIndex != -1) return swapFeeIndex;

  final depositAddressIndex = rows.indexWhere((row) {
    return row.label.startsWith('Deposit ') && row.label.endsWith(' to');
  });
  if (depositAddressIndex != -1) return depositAddressIndex;

  return rows.indexWhere((row) => row.label == 'Required deposit');
}

class _InsetDetailRow extends StatelessWidget {
  const _InsetDetailRow({
    required this.row,
    this.chevronUp = false,
    this.onTap,
  });

  final SwapStatusDetailRowData row;
  final bool chevronUp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: _DetailRow(row: row, chevronUp: chevronUp, onTap: onTap),
    );
  }
}

class _SwapFinalDetails extends StatelessWidget {
  const _SwapFinalDetails({required this.rows});

  final List<SwapStatusDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return _StatusDetailsScrollView(
      key: const ValueKey('swap_final_details_scroll_view'),
      child: Column(
        key: const ValueKey('swap_final_details'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            _InsetDetailRow(row: rows[index]),
            if (_finalDetailSectionGapAfter(rows, index))
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _StatusDetailsScrollView extends StatelessWidget {
  const _StatusDetailsScrollView({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(primary: false, child: child);
  }
}

bool _finalDetailSectionGapAfter(
  List<SwapStatusDetailRowData> rows,
  int index,
) {
  if (index >= rows.length - 1) return false;
  final label = rows[index].label.toLowerCase();
  return label.contains('deposit to') ||
      label.contains('refunded to') ||
      label == 'total fees';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.row, this.chevronUp = false, this.onTap});

  final SwapStatusDetailRowData row;
  final bool chevronUp;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showAccountAvatar = row.label == 'Account' && row.value.isNotEmpty;
    final enabled = onTap != null || row.copyable;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            onTap ??
            (row.copyable
                ? () {
                    copyTextWithToast(
                      context,
                      text: row.copyText ?? row.value,
                      toastMessage: 'Copied',
                    );
                  }
                : null),
        child: row.addressBookLabel != null
            ? _matchedAddressCell(context)
            : SizedBox(
                height: 32,
                child: row.value.isEmpty
                    ? Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              row.label,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            AppIcon(
                              chevronUp ? AppIcons.collapsed : AppIcons.expand,
                              size: 16,
                              color: colors.icon.regular.withValues(
                                alpha: 0.72,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Row(
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
                                  if (showAccountAvatar) ...[
                                    AppProfilePicture(
                                      profilePictureId:
                                          row.accountProfilePictureId ??
                                          kDefaultProfilePictureId,
                                      size: AppProfilePictureSize.medium,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                  ],
                                  Flexible(
                                    child: Text(
                                      row.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: AppTypography.labelLarge.copyWith(
                                        color: colors.text.accent,
                                      ),
                                    ),
                                  ),
                                  if (row.copyable || row.help) ...[
                                    const SizedBox(width: AppSpacing.xxs),
                                    _StatusDetailActionIcon(
                                      icon: row.copyable
                                          ? AppIcons.copy
                                          : AppIcons.help,
                                      tooltipMessage: row.help
                                          ? row.helpTooltip ??
                                                _swapStatusHelpTooltip(
                                                  row.label,
                                                )
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
      ),
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
        color: colors.icon.regular.withValues(alpha: 0.72),
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

class _NearIntentsLink extends StatelessWidget {
  const _NearIntentsLink({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('swap_activity_copy_near_intents_explorer_button'),
      width: 256,
      height: 44,
      child: AppButton(
        onPressed: onPressed ?? () {},
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.large,
        minWidth: 256,
        trailing: AppIcon(AppIcons.arrowTopRight, color: colors.icon.regular),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 184),
          child: const Text(
            'View on Near Intents',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Animated wrapper around [SwapProgressRoute]: walks the displayed
/// active step toward [progressIndex] one step per [interval], exactly
/// like the desktop status page does, so far-along intents still show
/// the route "travelling". Shared by the mobile status content.
class SwapAnimatedProgressRoute extends StatefulWidget {
  const SwapAnimatedProgressRoute({
    required this.steps,
    required this.progressIndex,
    required this.badgeKind,
    this.interval = swapStatusDefaultProgressAdvanceInterval,
    super.key,
  });

  final List<SwapStatusStepData> steps;
  final int progressIndex;
  final SwapStatusBadgeKind badgeKind;
  final Duration interval;

  @override
  State<SwapAnimatedProgressRoute> createState() =>
      _SwapAnimatedProgressRouteState();
}

class _SwapAnimatedProgressRouteState extends State<SwapAnimatedProgressRoute> {
  Timer? _timer;
  late int _displayIndex = _bounded(widget.progressIndex);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SwapAnimatedProgressRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.steps.length != widget.steps.length ||
        oldWidget.badgeKind != widget.badgeKind) {
      _timer?.cancel();
      _timer = null;
      _displayIndex = _bounded(widget.progressIndex);
      return;
    }
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _bounded(int index) {
    if (widget.steps.isEmpty) return 0;
    return index.clamp(0, widget.steps.length - 1);
  }

  bool get _animate {
    if (widget.badgeKind != SwapStatusBadgeKind.liveQuote) return false;
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  void _sync() {
    final target = _bounded(widget.progressIndex);
    if (!_animate || target <= _displayIndex) {
      _timer?.cancel();
      _timer = null;
      if (_displayIndex != target) {
        setState(() => _displayIndex = target);
      }
      return;
    }
    if (target == _displayIndex + 1) {
      _timer?.cancel();
      _timer = null;
      setState(() => _displayIndex = target);
      return;
    }
    _advance();
    _timer ??= Timer.periodic(widget.interval, (_) => _advance());
  }

  void _advance() {
    if (!mounted) return;
    final target = _bounded(widget.progressIndex);
    if (!_animate || target <= _displayIndex) {
      _timer?.cancel();
      _timer = null;
      if (_displayIndex != target) {
        setState(() => _displayIndex = target);
      }
      return;
    }
    final next = _displayIndex + 1;
    setState(() => _displayIndex = next);
    if (next >= target) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    return SwapProgressRoute(
      steps: [
        for (var index = 0; index < widget.steps.length; index++)
          widget.steps[index].copyWithState(
            index < _displayIndex
                ? SwapStatusStepState.complete
                : index == _displayIndex
                ? SwapStatusStepState.active
                : SwapStatusStepState.pending,
          ),
      ],
    );
  }
}
