import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
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
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('swap_queue_row_${intent.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected
                ? colors.state.selectedOpacity
                : colors.background.raised,
            border: Border.all(
              color: selected ? colors.border.regular : colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(width: AppSpacing.xs),
                  if (selected) ...[
                    const _QueueViewingBadge(),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  _QueueStatusBadge(
                    label: intent.statusLabel,
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _QueueProgressSegments(status: intent.status),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${intent.sellAmount} -> ${intent.receiveEstimate}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _queueStageLabel(intent.status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    final colors = context.colors;
    final activeIndex = _queueActiveIndex(status);
    final terminalIssue =
        status == SwapIntentStatus.failed || status == SwapIntentStatus.expired;
    final warning =
        status == SwapIntentStatus.incompleteDeposit ||
        status == SwapIntentStatus.shieldingFailed ||
        status == SwapIntentStatus.refunded;
    return Row(
      children: [
        for (var index = 0; index < 3; index++) ...[
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: index < activeIndex
                    ? colors.text.success
                    : index == activeIndex && terminalIssue
                    ? colors.text.destructive
                    : index == activeIndex && warning
                    ? colors.text.warning
                    : index == activeIndex
                    ? colors.text.accent
                    : colors.border.subtle,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          if (index != 2) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _QueueStatusBadge extends StatelessWidget {
  const _QueueStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: color),
      ),
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

int _queueActiveIndex(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => 0,
    SwapIntentStatus.depositObserved || SwapIntentStatus.processing => 1,
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming ||
    SwapIntentStatus.shieldingFailed ||
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded => 2,
  };
}

String _queueStageLabel(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => '1/3',
    SwapIntentStatus.depositObserved || SwapIntentStatus.processing => '2/3',
    SwapIntentStatus.incompleteDeposit => 'Check deposit',
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming ||
    SwapIntentStatus.shieldingFailed ||
    SwapIntentStatus.complete => '3/3',
    SwapIntentStatus.refunded => 'Refund',
    SwapIntentStatus.expired => 'Expired',
    SwapIntentStatus.failed => 'Failed',
  };
}
