import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_prototype_models.dart';
import 'swap_amount_text.dart';
import 'swap_asset_icon.dart';

class SwapQueuePanel extends StatelessWidget {
  const SwapQueuePanel({
    required this.intents,
    this.selectedIntentId,
    this.onIntentSelected,
    this.statusRefreshing = false,
    this.onRefresh,
    super.key,
  });

  final List<SwapPrototypeIntent> intents;
  final String? selectedIntentId;
  final ValueChanged<String>? onIntentSelected;
  final bool statusRefreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final openIntents = [
      for (final intent in intents)
        if (!intent.status.isTerminal) intent,
    ];
    final completedIntents = [
      for (final intent in intents)
        if (intent.status == SwapIntentStatus.complete) intent,
    ];
    final attentionIntents = [
      for (final intent in intents)
        if (intent.status == SwapIntentStatus.failed ||
            intent.status == SwapIntentStatus.expired ||
            intent.status == SwapIntentStatus.refunded)
          intent,
    ];
    final groups = [
      _QueueGroup(id: 'open', label: 'Open', intents: openIntents),
      _QueueGroup(id: 'completed', label: 'Closed', intents: completedIntents),
      _QueueGroup(id: 'failed', label: 'Attention', intents: attentionIntents),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Activity',
                  key: const ValueKey('swap_queue_title'),
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              _QueueRefreshButton(
                refreshing: statusRefreshing,
                onTap: onRefresh,
              ),
              const SizedBox(width: AppSpacing.xs),
              _QueueCountChip(label: 'Open', count: openIntents.length),
              if (attentionIntents.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.xxs),
                _QueueCountChip(
                  label: 'Attention',
                  count: attentionIntents.length,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (intents.isEmpty)
            Text(
              'No recent swaps',
              key: const ValueKey('swap_queue_empty_state'),
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          for (final group in groups)
            if (group.intents.isNotEmpty) ...[
              Text(
                group.label,
                key: ValueKey('swap_queue_group_${group.id}'),
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              for (final intent in group.intents) ...[
                _QueueRow(
                  intent: intent,
                  selected: intent.id == selectedIntentId,
                  onTap: onIntentSelected == null
                      ? null
                      : () => onIntentSelected!(intent.id),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
            ],
        ],
      ),
    );
  }
}

class _QueueGroup {
  const _QueueGroup({
    required this.id,
    required this.label,
    required this.intents,
  });

  final String id;
  final String label;
  final List<SwapPrototypeIntent> intents;
}

class _QueueRefreshButton extends StatelessWidget {
  const _QueueRefreshButton({required this.refreshing, required this.onTap});

  final bool refreshing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null && !refreshing;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        key: const ValueKey('swap_queue_refresh_button'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.background.raised,
            border: Border.all(color: colors.border.subtle),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                refreshing ? AppIcons.loader : AppIcons.renew,
                size: 16,
                color: refreshing
                    ? colors.icon.brandCrimson
                    : colors.icon.muted,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                refreshing ? 'Checking' : 'Refresh',
                style: AppTypography.labelMedium.copyWith(
                  color: refreshing
                      ? colors.text.brandCrimson
                      : colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.intent, required this.selected, this.onTap});

  final SwapPrototypeIntent intent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusColor = _statusColor(context, intent.status);
    final actionLabel = _queueActionLabel(intent);
    final live = _isLiveStatus(intent.status);
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_queue_row_${intent.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.state.selectedOpacity
                : colors.background.raised,
            border: Border.all(
              color: selected
                  ? statusColor.withValues(alpha: 0.42)
                  : live
                  ? statusColor.withValues(alpha: 0.28)
                  : colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _QueueStatusGlyph(
                intentId: intent.id,
                status: intent.status,
                color: statusColor,
                selected: selected,
                live: live,
              ),
              const SizedBox(width: AppSpacing.xs),
              _QueueAssetPair(intent: intent, selected: selected),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            intent.pair,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      actionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _QueueProgressSegments(status: intent.status),
                    const SizedBox(height: AppSpacing.xxs),
                    _QueueAmountFlow(intent: intent),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 14,
                  color: selected ? statusColor : colors.icon.muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueAssetPair extends StatelessWidget {
  const _QueueAssetPair({required this.intent, required this.selected});

  final SwapPrototypeIntent intent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final sellAsset = _intentSellAsset(intent);
    final receiveAsset = _intentReceiveAsset(intent);
    if (sellAsset == null || receiveAsset == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      key: ValueKey('swap_queue_asset_pair_${intent.id}'),
      width: 56,
      height: 38,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 4,
            child: SwapAssetIcon(
              asset: sellAsset,
              selected: selected,
              size: 32,
            ),
          ),
          Positioned(
            left: 24,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: context.colors.background.base,
                border: Border.all(color: context.colors.border.subtle),
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: SwapAssetIcon(
                asset: receiveAsset,
                selected: selected,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueStatusGlyph extends StatelessWidget {
  const _QueueStatusGlyph({
    required this.intentId,
    required this.status,
    required this.color,
    required this.selected,
    required this.live,
  });

  final String intentId;
  final SwapIntentStatus status;
  final Color color;
  final bool selected;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconName = _queueStatusIcon(status);
    return SizedBox(
      width: 34,
      height: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (live)
                  _QueueLivePulse(
                    key: ValueKey('swap_queue_live_pulse_$intentId'),
                    color: color,
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: selected ? 30 : 26,
                  height: selected ? 30 : 26,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? 0.16 : 0.1),
                    border: Border.all(color: color.withValues(alpha: 0.36)),
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                  child: Center(
                    child: AppIcon(
                      iconName,
                      size: selected ? 15 : 13,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: selected ? 3 : 2,
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.58)
                    : colors.border.subtle,
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueLivePulse extends StatelessWidget {
  const _QueueLivePulse({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.9, end: 1.14),
      duration: const Duration(milliseconds: 760),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final opacity = ((1.14 - value) / 0.24).clamp(0.0, 1.0).toDouble();
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.24)),
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      ),
    );
  }
}

class _QueueAmountFlow extends StatelessWidget {
  const _QueueAmountFlow({required this.intent});

  final SwapPrototypeIntent intent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amountStyle = AppTypography.bodyExtraSmall.copyWith(
      color: colors.text.muted,
    );
    final sellAmount = compactSwapAmountText(intent.sellAmount);
    final receiveEstimate = compactSwapAmountText(intent.receiveEstimate);
    return Text(
      '$sellAmount -> $receiveEstimate',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: amountStyle,
    );
  }
}

class _QueueCountChip extends StatelessWidget {
  const _QueueCountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        '$label $count',
        style: AppTypography.labelSmall.copyWith(color: colors.text.secondary),
      ),
    );
  }
}

class _QueueProgressSegments extends StatefulWidget {
  const _QueueProgressSegments({required this.status});

  final SwapIntentStatus status;

  @override
  State<_QueueProgressSegments> createState() => _QueueProgressSegmentsState();
}

class _QueueProgressSegmentsState extends State<_QueueProgressSegments> {
  Timer? _advanceTimer;
  late int _displayProgressIndex;

  @override
  void initState() {
    super.initState();
    _displayProgressIndex = _queueProgressIndex(widget.status);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDisplayProgress();
  }

  @override
  void didUpdateWidget(covariant _QueueProgressSegments oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDisplayProgress();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _syncDisplayProgress() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetIndex = _queueProgressIndex(widget.status);
    if (reduceMotion ||
        !_queueCanAnimateProgress(widget.status) ||
        targetIndex <= _displayProgressIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    if (targetIndex == _displayProgressIndex + 1) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      setState(() => _displayProgressIndex = targetIndex);
      return;
    }

    _advanceDisplayProgress();
    _advanceTimer ??= Timer.periodic(
      _queueSegmentAdvanceTempo,
      (_) => _advanceDisplayProgress(),
    );
  }

  void _advanceDisplayProgress() {
    if (!mounted) return;
    final targetIndex = _queueProgressIndex(widget.status);
    if (!_queueCanAnimateProgress(widget.status) ||
        targetIndex <= _displayProgressIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    final nextIndex = _displayProgressIndex + 1;
    setState(() => _displayProgressIndex = nextIndex);
    if (nextIndex >= targetIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = _queueSegmentStatesForDisplay(
      widget.status,
      _displayProgressIndex,
    );
    return Row(
      children: [
        for (var index = 0; index < states.length; index++) ...[
          Expanded(
            child: _QueueProgressSegment(
              status: widget.status,
              index: index,
              state: states[index],
            ),
          ),
          if (index != states.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _QueueProgressSegment extends StatelessWidget {
  const _QueueProgressSegment({
    required this.status,
    required this.index,
    required this.state,
  });

  final SwapIntentStatus status;
  final int index;
  final _QueueSegmentState state;

  @override
  Widget build(BuildContext context) {
    final segment = Container(
      key: ValueKey('swap_queue_progress_segment_${status.name}_$index'),
      height: 6,
      decoration: BoxDecoration(
        color: _queueSegmentColor(context, state),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
    );
    if (state != _QueueSegmentState.active) return segment;
    return _QueueSegmentBlinkOpacity(
      key: ValueKey('swap_queue_progress_segment_blink_${status.name}_$index'),
      child: segment,
    );
  }
}

const _queueSegmentBlinkTempo = Duration(milliseconds: 2200);
const _queueSegmentBlinkDuration = Duration(milliseconds: 1000);
const _queueSegmentAdvanceTempo = Duration(milliseconds: 420);

class _QueueSegmentBlinkOpacity extends StatefulWidget {
  const _QueueSegmentBlinkOpacity({required this.child, super.key});

  final Widget child;

  @override
  State<_QueueSegmentBlinkOpacity> createState() =>
      _QueueSegmentBlinkOpacityState();
}

class _QueueSegmentBlinkOpacityState extends State<_QueueSegmentBlinkOpacity> {
  Timer? _timer;
  var _pulse = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_queueSegmentBlinkTempo, (_) => _triggerPulse());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _triggerPulse() {
    if (!mounted) return;
    setState(() => _pulse += 1);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_pulse),
      tween: Tween<double>(begin: 0, end: 1),
      duration: _queueSegmentBlinkDuration,
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) {
        final pulse = math.sin(value * math.pi);
        return Opacity(opacity: 0.62 + (pulse * 0.38), child: child);
      },
      child: widget.child,
    );
  }
}

Color _statusColor(BuildContext context, SwapIntentStatus status) {
  final colors = context.colors;
  return switch (status) {
    SwapIntentStatus.complete => colors.text.success,
    SwapIntentStatus.failed ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.refunded => colors.text.destructive,
    _ => colors.text.warning,
  };
}

bool _isLiveStatus(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming => true,
    _ => false,
  };
}

SwapAsset? _intentSellAsset(SwapPrototypeIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _assetFromPair(intent.pair, 0);
  }
  return direction.fromAsset(externalAsset);
}

SwapAsset? _intentReceiveAsset(SwapPrototypeIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _assetFromPair(intent.pair, 1);
  }
  return direction.toAsset(externalAsset);
}

SwapAsset? _assetFromPair(String pair, int index) {
  final parts = pair.split('->');
  if (index < 0 || index >= parts.length) return null;
  final tokens = parts[index].trim().split(RegExp(r'\s+'));
  final symbol = tokens.isEmpty ? '' : tokens.first;
  if (symbol.isEmpty) return null;
  return SwapAsset.byName(symbol.toLowerCase());
}

String _queueStatusIcon(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => AppIcons.link,
    SwapIntentStatus.depositObserved => AppIcons.eye,
    SwapIntentStatus.processing => AppIcons.renew,
    SwapIntentStatus.providerStatusUnknown => AppIcons.warning,
    SwapIntentStatus.incompleteDeposit => AppIcons.warning,
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming => AppIcons.shieldKeyhole,
    SwapIntentStatus.shieldingFailed => AppIcons.warning,
    SwapIntentStatus.complete => AppIcons.check,
    SwapIntentStatus.refunded => AppIcons.arrowBack,
    SwapIntentStatus.expired || SwapIntentStatus.failed => AppIcons.block,
  };
}

enum _QueueSegmentState { pending, active, success, warning, destructive }

List<_QueueSegmentState> _queueSegmentStates(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => const [
      _QueueSegmentState.active,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.depositObserved || SwapIntentStatus.processing => const [
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.active,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.providerStatusUnknown => const [
      _QueueSegmentState.success,
      _QueueSegmentState.warning,
      _QueueSegmentState.active,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.incompleteDeposit => const [
      _QueueSegmentState.warning,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming => const [
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.active,
    ],
    SwapIntentStatus.shieldingFailed => const [
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.warning,
    ],
    SwapIntentStatus.complete => const [
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.success,
    ],
    SwapIntentStatus.refunded => const [
      _QueueSegmentState.success,
      _QueueSegmentState.warning,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.expired || SwapIntentStatus.failed => const [
      _QueueSegmentState.destructive,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
    ],
  };
}

List<_QueueSegmentState> _queueSegmentStatesForDisplay(
  SwapIntentStatus status,
  int progressIndex,
) {
  if (!_queueCanAnimateProgress(status) ||
      progressIndex >= _queueProgressIndex(status)) {
    return _queueSegmentStates(status);
  }
  final clampedIndex = progressIndex.clamp(0, 4).toInt();
  if (clampedIndex >= 4) return _queueSegmentStates(status);
  return [
    for (var index = 0; index < 4; index++)
      index < clampedIndex
          ? _QueueSegmentState.success
          : index == clampedIndex
          ? _QueueSegmentState.active
          : _QueueSegmentState.pending,
  ];
}

bool _queueCanAnimateProgress(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming ||
    SwapIntentStatus.complete => true,
    _ => false,
  };
}

int _queueProgressIndex(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => 0,
    SwapIntentStatus.depositObserved || SwapIntentStatus.processing => 2,
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming => 3,
    SwapIntentStatus.complete => 4,
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.incompleteDeposit => 1,
    SwapIntentStatus.shieldingFailed => 3,
    SwapIntentStatus.expired || SwapIntentStatus.failed => 0,
  };
}

Color _queueSegmentColor(BuildContext context, _QueueSegmentState state) {
  final colors = context.colors;
  return switch (state) {
    _QueueSegmentState.success => colors.text.success,
    _QueueSegmentState.warning => colors.text.warning,
    _QueueSegmentState.destructive => colors.text.destructive,
    _QueueSegmentState.active => colors.text.accent,
    _QueueSegmentState.pending => colors.border.subtle,
  };
}

String _queueActionLabel(SwapPrototypeIntent intent) {
  return switch (intent.status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => 'Waiting for deposit',
    SwapIntentStatus.depositObserved => 'Deposit found',
    SwapIntentStatus.processing => 'Swapping through provider',
    SwapIntentStatus.providerStatusUnknown => 'Check provider status',
    SwapIntentStatus.incompleteDeposit => 'Check deposit amount',
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming => 'Shielding in wallet',
    SwapIntentStatus.shieldingFailed => 'Shielding needs retry',
    SwapIntentStatus.complete => 'Swap delivered',
    SwapIntentStatus.refunded => 'Refund sent back',
    SwapIntentStatus.expired => 'Quote expired',
    SwapIntentStatus.failed => 'Provider route stopped',
  };
}
