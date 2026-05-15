import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_prototype_models.dart';

class SwapQueuePanel extends StatelessWidget {
  const SwapQueuePanel({
    required this.intents,
    this.selectedIntentId,
    this.onIntentSelected,
    super.key,
  });

  final List<SwapPrototypeIntent> intents;
  final String? selectedIntentId;
  final ValueChanged<String>? onIntentSelected;

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
      _QueueGroup(
        id: 'completed',
        label: 'Completed',
        intents: completedIntents,
      ),
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
              _QueueCountChip(label: 'Open', count: openIntents.length),
              const SizedBox(width: AppSpacing.xxs),
              _QueueCountChip(
                label: 'Attention',
                count: attentionIntents.length,
              ),
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
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_queue_row_${intent.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected
                ? colors.state.selectedOpacity
                : colors.background.raised,
            border: Border.all(
              color: selected
                  ? statusColor.withValues(alpha: 0.42)
                  : colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _QueueStatusGlyph(
                status: intent.status,
                color: statusColor,
                selected: selected,
              ),
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
                        if (selected) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          const _QueueViewingBadge(),
                        ],
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

class _QueueStatusGlyph extends StatelessWidget {
  const _QueueStatusGlyph({
    required this.status,
    required this.color,
    required this.selected,
  });

  final SwapIntentStatus status;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconName = _queueStatusIcon(status);
    return SizedBox(
      width: 30,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 4,
            bottom: 4,
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
          Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: selected ? 28 : 24,
              height: selected ? 28 : 24,
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
          ),
        ],
      ),
    );
  }
}

class _QueueViewingBadge extends StatelessWidget {
  const _QueueViewingBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_queue_viewing_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        'Viewing',
        style: AppTypography.labelSmall.copyWith(color: colors.text.accent),
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
    return Text(
      '${intent.sellAmount} -> ${intent.receiveEstimate}',
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

class _QueueProgressSegments extends StatelessWidget {
  const _QueueProgressSegments({required this.status});

  final SwapIntentStatus status;

  @override
  Widget build(BuildContext context) {
    final states = _queueSegmentStates(status);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Row(
      children: [
        for (var index = 0; index < states.length; index++) ...[
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin:
                    states[index] == _QueueSegmentState.active && !reduceMotion
                    ? 0.48
                    : 1,
                end: 1,
              ),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              builder: (context, opacity, child) {
                return Opacity(opacity: opacity, child: child);
              },
              child: Container(
                key: ValueKey(
                  'swap_queue_progress_segment_${status.name}_$index',
                ),
                height: 6,
                decoration: BoxDecoration(
                  color: _queueSegmentColor(context, states[index]),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
              ),
            ),
          ),
          if (index != states.length - 1) const SizedBox(width: 3),
        ],
      ],
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
    ],
    SwapIntentStatus.depositObserved || SwapIntentStatus.processing => const [
      _QueueSegmentState.success,
      _QueueSegmentState.active,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.providerStatusUnknown => const [
      _QueueSegmentState.success,
      _QueueSegmentState.warning,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.incompleteDeposit => const [
      _QueueSegmentState.warning,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming => const [
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.active,
    ],
    SwapIntentStatus.shieldingFailed => const [
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.warning,
    ],
    SwapIntentStatus.complete => const [
      _QueueSegmentState.success,
      _QueueSegmentState.success,
      _QueueSegmentState.success,
    ],
    SwapIntentStatus.refunded => const [
      _QueueSegmentState.success,
      _QueueSegmentState.warning,
      _QueueSegmentState.pending,
    ],
    SwapIntentStatus.expired || SwapIntentStatus.failed => const [
      _QueueSegmentState.destructive,
      _QueueSegmentState.pending,
      _QueueSegmentState.pending,
    ],
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
