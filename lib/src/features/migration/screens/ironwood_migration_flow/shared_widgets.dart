part of '../ironwood_migration_flow_screen.dart';

class _ReviewMetricRow extends StatelessWidget {
  const _ReviewMetricRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: const Color(0xFFE3FBEE),
              shape: const OvalBorder(),
            ),
            child: Center(
              child: AppIcon(icon, size: 16, color: GreenPrimitives.p500Light),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatZecAmountCompact(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(
    zatoshi,
  ).compactBalancePretty(minFractionDigits: 0, maxFractionDigits: 4).amountText;
}

double _transferProgress(rust_sync.MigrationStatus status) {
  final partProgress = _migrationPartProgress(status);
  if (partProgress != null) return partProgress;

  if (status.totalCount > 0) {
    final transferredCount = _transferCompletedCountForPhase(status);
    final progress = (transferredCount / status.totalCount)
        .clamp(0, 1)
        .toDouble();
    if (_isWaitingForTrustedMigrationComplete(status)) {
      return math.min(progress, 0.99);
    }
    return progress;
  }

  final explicitProgress = _statusProgress(status);
  if (explicitProgress != null) return explicitProgress.clamp(0, 1);

  return switch (status.phase) {
    kIronwoodMigrationBroadcastScheduledPhase => 0.45,
    kIronwoodMigrationBroadcastingPhase => 0.65,
    kIronwoodMigrationWaitingConfirmationsPhase => 0.85,
    _ => 0,
  };
}

bool _isWaitingForTrustedMigrationComplete(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) {
    return status.phase == kIronwoodMigrationWaitingConfirmationsPhase &&
        status.parts.every(
          (part) =>
              part.state == rust_sync.MigrationPartState.confirming ||
              part.state == rust_sync.MigrationPartState.completed,
        ) &&
        status.parts.any(
          (part) => part.state == rust_sync.MigrationPartState.confirming,
        );
  }
  return status.phase == kIronwoodMigrationWaitingConfirmationsPhase &&
      status.totalCount > 0 &&
      status.confirmedTxCount >= status.totalCount;
}

int _transferCompletedCountForPhase(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) {
    return status.parts
        .where(
          (part) =>
              part.state == rust_sync.MigrationPartState.confirming ||
              part.state == rust_sync.MigrationPartState.completed,
        )
        .length;
  }
  return switch (status.phase) {
    kIronwoodMigrationWaitingConfirmationsPhase => status.confirmedTxCount,
    kIronwoodMigrationBroadcastingPhase => status.broadcastedTxCount,
    _ => math.max(status.confirmedTxCount, status.broadcastedTxCount),
  };
}

_TransferAmount _leftToTransferAmount(
  rust_sync.MigrationStatus status, {
  required double progress,
}) {
  final total = _sumTargetValues(status);
  if (total <= BigInt.zero) {
    return _TransferAmount(value: BigInt.zero, isEstimated: false);
  }

  if (status.totalCount > 0) {
    if (_isWaitingForTrustedMigrationComplete(status)) {
      return _leftToTransferAmountFromProgress(total, progress);
    }
    final completedCount = math.min(
      status.totalCount,
      _transferCompletedCountForPhase(status),
    );
    final transferred =
        (total * BigInt.from(completedCount)) ~/ BigInt.from(status.totalCount);
    final left = total - transferred;
    return _TransferAmount(
      value: left > BigInt.zero ? left : BigInt.zero,
      isEstimated: completedCount > 0 && completedCount < status.totalCount,
    );
  }

  return _leftToTransferAmountFromProgress(total, progress);
}

_TransferAmount _leftToTransferAmountFromProgress(
  BigInt total,
  double progress,
) {
  final scaledProgress = BigInt.from((progress.clamp(0, 1) * 10000).round());
  final transferred = (total * scaledProgress) ~/ BigInt.from(10000);
  final left = total - transferred;
  return _TransferAmount(
    value: left > BigInt.zero ? left : BigInt.zero,
    isEstimated:
        scaledProgress > BigInt.zero && scaledProgress < BigInt.from(10000),
  );
}

int _plannedTransferBatchCount(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) return status.parts.length;
  if (status.totalCount > 0) return status.totalCount;

  final progressedCount = status.broadcastedTxCount > status.confirmedTxCount
      ? status.broadcastedTxCount
      : status.confirmedTxCount;
  final countFromProgress = status.pendingTxCount + progressedCount;
  if (countFromProgress > 0) return countFromProgress;
  if (status.scheduledBroadcasts.isNotEmpty) {
    return status.scheduledBroadcasts.length;
  }

  return math.max(1, status.denominationSplitTotalCount);
}

int _currentTransferBatchIndex(rust_sync.MigrationStatus status) {
  final planned = _plannedTransferBatchCount(status);
  if (status.parts.isNotEmpty) {
    final firstIncomplete = status.parts.indexWhere(
      (part) => part.state != rust_sync.MigrationPartState.completed,
    );
    return firstIncomplete < 0 ? planned : firstIncomplete + 1;
  }
  final completedOrSubmitted = switch (status.phase) {
    kIronwoodMigrationWaitingConfirmationsPhase => status.confirmedTxCount,
    kIronwoodMigrationBroadcastingPhase => status.broadcastedTxCount,
    _ => math.max(status.confirmedTxCount, status.broadcastedTxCount),
  };
  return math.min(planned, math.max(1, completedOrSubmitted + 1));
}

double? _migrationPartProgress(rust_sync.MigrationStatus status) {
  if (status.parts.isEmpty) return null;
  var progress = 0.0;
  for (final part in status.parts) {
    progress += switch (part.state) {
      rust_sync.MigrationPartState.completed => 1,
      rust_sync.MigrationPartState.confirming
          when part.confirmationTarget > 0 =>
        (part.confirmationCount / part.confirmationTarget).clamp(0, 1),
      _ => 0,
    };
  }
  return (progress / status.parts.length).clamp(0, 1);
}

class _TransferAmount {
  const _TransferAmount({required this.value, required this.isEstimated});

  final BigInt value;
  final bool isEstimated;
}

_TransferAmount _currentTransferBatchAmount(
  rust_sync.MigrationStatus status, {
  required int plannedBatchCount,
}) {
  final total = _sumTargetValues(status);
  if (total <= BigInt.zero) {
    return _TransferAmount(value: BigInt.zero, isEstimated: false);
  }
  return _TransferAmount(
    value: total ~/ BigInt.from(math.max(1, plannedBatchCount)),
    isEstimated: true,
  );
}

String _currentTransferBatchStatus(rust_sync.MigrationStatus status) {
  return switch (status.phase) {
    kIronwoodMigrationBroadcastScheduledPhase => 'Scheduled',
    kIronwoodMigrationBroadcastingPhase => 'Broadcasting...',
    kIronwoodMigrationWaitingConfirmationsPhase => 'Confirming...',
    _ => 'In progress',
  };
}

String _transferEstimatedArrival(rust_sync.MigrationStatus status) {
  if (status.phase == kIronwoodMigrationCompletePhase) {
    return 'Completed';
  }

  final nextScheduledBroadcast = _nextScheduledBroadcast(status);
  if (nextScheduledBroadcast != null) {
    return 'Block ${nextScheduledBroadcast.scheduledHeight}';
  }

  if (status.phase == kIronwoodMigrationWaitingConfirmationsPhase) {
    return 'Confirming';
  }

  return '~${status.scheduleMeanDelayBlocks} blocks';
}

String _transferEstimatedCompletion(
  rust_sync.MigrationStatus status, {
  required int currentHeight,
  bool needsInput = false,
  List<rust_sync.MigrationPartStatus>? parts,
}) {
  if (status.phase == kIronwoodMigrationCompletePhase) {
    return 'Completed';
  }
  final displayParts = parts ?? _displayMigrationParts(status);
  if (needsInput || _migrationNeedsUserInput(status, parts: displayParts)) {
    return 'After signing';
  }

  final remainingBlocks = _remainingMigrationCompletionBlocks(
    status,
    currentHeight: currentHeight,
    parts: displayParts,
  );
  if (remainingBlocks == null) {
    return _formatMigrationBlockDurationEstimate(
      _fallbackRemainingMigrationBlocks(status),
    );
  }
  return _formatMigrationBlockDurationEstimate(math.max(1, remainingBlocks));
}

bool _migrationNeedsUserInput(
  rust_sync.MigrationStatus status, {
  List<rust_sync.MigrationPartStatus>? parts,
}) {
  final displayParts = parts ?? _displayMigrationParts(status);
  return displayParts.any(
    (part) => part.state == rust_sync.MigrationPartState.needsInput,
  );
}

int? _remainingMigrationCompletionBlocks(
  rust_sync.MigrationStatus status, {
  required int currentHeight,
  List<rust_sync.MigrationPartStatus>? parts,
}) {
  final displayParts = parts ?? _displayMigrationParts(status);
  if (displayParts.isNotEmpty) {
    var remainingBlocks = 0;
    for (final part in displayParts) {
      final partRemaining = _remainingMigrationPartCompletionBlocks(
        part,
        currentHeight: currentHeight,
        fallbackDelayBlocks: status.scheduleMeanDelayBlocks,
      );
      if (partRemaining == null) return null;
      remainingBlocks = math.max(remainingBlocks, partRemaining);
    }
    return remainingBlocks;
  }

  final scheduledBroadcasts = status.scheduledBroadcasts
      .where((broadcast) => broadcast.status == 'scheduled')
      .toList();
  if (scheduledBroadcasts.isNotEmpty) {
    final confirmationTarget = _legacyMigrationConfirmationTarget(status);
    var remainingBlocks = 0;
    for (final broadcast in scheduledBroadcasts) {
      final scheduledBlocks = _remainingScheduledMigrationBlocks(
        scheduledHeight: broadcast.scheduledHeight,
        scheduleStartHeight: broadcast.scheduleStartHeight,
        currentHeight: currentHeight,
        fallbackDelayBlocks: status.scheduleMeanDelayBlocks,
      );
      remainingBlocks = math.max(
        remainingBlocks,
        scheduledBlocks + confirmationTarget,
      );
    }
    return remainingBlocks;
  }

  if (status.phase == kIronwoodMigrationWaitingConfirmationsPhase) {
    final target = _legacyMigrationConfirmationTarget(status);
    final remainingConfirmations = math.max(
      0,
      target - status.confirmedTxCount,
    );
    return remainingConfirmations;
  }

  return null;
}

int? _remainingMigrationPartCompletionBlocks(
  rust_sync.MigrationPartStatus part, {
  required int currentHeight,
  required int fallbackDelayBlocks,
}) {
  return switch (part.state) {
    rust_sync.MigrationPartState.preparing =>
      _migrationPrepareConfirmationBlocks,
    rust_sync.MigrationPartState.scheduled =>
      _remainingScheduledMigrationBlocks(
            scheduledHeight: part.scheduledHeight,
            scheduleStartHeight: part.scheduleStartHeight,
            currentHeight: currentHeight,
            fallbackDelayBlocks: fallbackDelayBlocks,
          ) +
          _migrationPartConfirmationTarget(part),
    rust_sync.MigrationPartState.migrating => _migrationPartConfirmationTarget(
      part,
    ),
    rust_sync.MigrationPartState.confirming => math.max(
      0,
      _migrationPartConfirmationTarget(part) - part.confirmationCount,
    ),
    rust_sync.MigrationPartState.completed => 0,
    rust_sync.MigrationPartState.needsInput => null,
  };
}

int _remainingScheduledMigrationBlocks({
  required int? scheduledHeight,
  required int? scheduleStartHeight,
  required int currentHeight,
  required int fallbackDelayBlocks,
}) {
  if (scheduledHeight == null) return math.max(1, fallbackDelayBlocks);
  final fromHeight = currentHeight > 0 ? currentHeight : scheduleStartHeight;
  if (fromHeight == null) return math.max(1, fallbackDelayBlocks);
  return math.max(0, scheduledHeight - fromHeight);
}

int _migrationPartConfirmationTarget(rust_sync.MigrationPartStatus part) {
  return math.max(1, part.confirmationTarget);
}

int _legacyMigrationConfirmationTarget(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) {
    return status.parts.fold<int>(
      1,
      (maxTarget, part) =>
          math.max(maxTarget, _migrationPartConfirmationTarget(part)),
    );
  }
  if (status.totalCount > 0) return status.totalCount;
  return _migrationPrepareConfirmationBlocks;
}

int _fallbackRemainingMigrationBlocks(rust_sync.MigrationStatus status) {
  final totalCount = status.totalCount > 0
      ? status.totalCount
      : math.max(1, status.targetValuesZatoshi.length);
  final completedCount = status.parts.isNotEmpty
      ? status.parts
            .where(
              (part) => part.state == rust_sync.MigrationPartState.completed,
            )
            .length
      : math.max(status.confirmedTxCount, status.broadcastedTxCount);
  final remainingCount = math.max(1, totalCount - completedCount);
  return math.max(1, status.scheduleMeanDelayBlocks) * remainingCount +
      _migrationPrepareConfirmationBlocks;
}

rust_sync.MigrationScheduledBroadcast? _nextScheduledBroadcast(
  rust_sync.MigrationStatus status,
) {
  rust_sync.MigrationScheduledBroadcast? fallbackScheduled;
  for (final broadcast in status.scheduledBroadcasts) {
    if (broadcast.status != 'scheduled') continue;
    fallbackScheduled ??= broadcast;
  }
  return fallbackScheduled;
}

String _estimatedMigrationArrivalLabel(
  rust_sync.OrchardMigrationPrivatePlan plan,
) => migrationPlanCompletionDurationLabel(plan);

String _formatMigrationBlockDurationEstimate(int blocks) {
  if (blocks <= 0) return 'Not scheduled';
  final duration = Duration(
    seconds: blocks * _migrationEstimatedSecondsPerBlock,
  );
  final minutes = (duration.inSeconds / Duration.secondsPerMinute).ceil();
  if (minutes < 60) {
    return minutes == 1 ? '~1 min' : '~$minutes mins';
  }

  final hours = (duration.inSeconds / Duration.secondsPerHour).ceil();
  if (hours < 48) {
    return hours == 1 ? '~1 hr' : '~$hours hrs';
  }

  final days = (duration.inSeconds / Duration.secondsPerDay).ceil();
  return days == 1 ? '~1 day' : '~$days days';
}

class _FlowButtons extends StatelessWidget {
  const _FlowButtons({
    this.primaryKey,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.secondaryLeading,
    this.secondaryFirst = false,
    this.spacing = 20,
  });

  final Key? primaryKey;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final Widget? secondaryLeading;
  final bool secondaryFirst;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final primaryButton = AppButton(
      key: primaryKey,
      onPressed: onPrimary,
      height: 44,
      minWidth: 230,
      expand: true,
      constrainContent: true,
      trailing: const AppIcon(AppIcons.chevronForward, size: 20),
      child: Text(primaryLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final secondaryButton = AppButton(
      onPressed: onSecondary,
      variant: AppButtonVariant.ghost,
      height: 36,
      minWidth: 230,
      expand: true,
      constrainContent: true,
      leading: secondaryLeading,
      child: Text(secondaryLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final children = secondaryFirst
        ? [secondaryButton, SizedBox(height: spacing), primaryButton]
        : [primaryButton, SizedBox(height: spacing), secondaryButton];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _DarkBadge extends StatelessWidget {
  const _DarkBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.colors.background.inverse,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: context.colors.text.inverse,
          ),
        ),
      ),
    );
  }
}

class _PoolMigrationHero extends StatelessWidget {
  const _PoolMigrationHero({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = '${data.amountText} $kZcashDefaultCurrencyTicker';
    final isDark = colors.background.window == AppColors.dark.background.window;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xLarge),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: colors.background.ground,
            child: Image.asset(
              isDark
                  ? _ironwoodMigrationIntroBannerDarkAsset
                  : _ironwoodMigrationIntroBannerLightAsset,
              key: ValueKey(
                'ironwood_migration_intro_banner_${isDark ? 'dark' : 'light'}',
              ),
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            left: 24,
            top: 24,
            child: AppProfilePicture(
              profilePictureId: data.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
          ),
          Positioned(
            right: 24,
            top: 24,
            child: AppProfilePicture(
              profilePictureId: data.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
          ),
          Positioned(
            left: 24,
            top: 116,
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '(Legacy)',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Orchard Pool',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  amount,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            top: 136,
            width: 116,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Ironwood Pool',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.positiveStrong,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  amount,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
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

class _ProcessCard extends StatelessWidget {
  const _ProcessCard({required this.steps});

  final List<_ProcessStepData> steps;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              _ProcessStep(step: steps[index]),
              if (index != steps.length - 1) const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessStepData {
  const _ProcessStepData({
    required this.number,
    required this.title,
    required this.body,
  });

  final int number;
  final String title;
  final String body;
}

class _ProcessStep extends StatelessWidget {
  const _ProcessStep({required this.step});

  final _ProcessStepData step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProcessStepNumber(number: step.number),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.body,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProcessStepNumber extends StatelessWidget {
  const _ProcessStepNumber({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 24,
      height: 24,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.background.base,
          shape: const CircleBorder(),
        ),
        child: Center(
          child: Text(
            '$number',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpendAsFundsArriveCard extends StatelessWidget {
  const _SpendAsFundsArriveCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: AppIcon(
                AppIcons.wallet,
                size: 20,
                color: GreenPrimitives.p400Light,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: colors.text.homeCard),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spend as funds arrive',
                      style: AppTypography.labelMedium,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Each confirmed Ironwood amount is available to '
                      'spend while the rest continues.',
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MigrationMode { private, fast }

class _MigrationOptionCard extends StatelessWidget {
  const _MigrationOptionCard({
    super.key,
    required this.mode,
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
    this.badge,
  });

  final _MigrationMode mode;
  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 104,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(24),
              boxShadow: selected
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x10000000),
                        offset: Offset(0, 2),
                        blurRadius: 10,
                      ),
                    ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _OptionIcon(mode: mode, selected: selected),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyLarge.copyWith(
                                      color: colors.text.accent,
                                    ),
                                  ),
                                ),
                                if (badge != null) ...[
                                  const SizedBox(width: 8),
                                  _RecommendedBadge(label: badge!),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Flexible(
                              child: Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SelectionMark(selected: selected),
                    ],
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colors.text.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionIcon extends StatelessWidget {
  const _OptionIcon({required this.mode, required this.selected});

  final _MigrationMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colors.text.accent
        : context.colors.icon.disabled;
    return SizedBox(
      width: 16,
      height: 16,
      child: CustomPaint(
        painter: _OptionIconPainter(mode: mode, color: color),
      ),
    );
  }
}

class _OptionIconPainter extends CustomPainter {
  const _OptionIconPainter({required this.mode, required this.color});

  final _MigrationMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (mode == _MigrationMode.private) {
      final path = Path()
        ..moveTo(8, 1.5)
        ..lineTo(14, 4)
        ..lineTo(13, 10)
        ..quadraticBezierTo(11, 14, 8, 15)
        ..quadraticBezierTo(5, 14, 3, 10)
        ..lineTo(2, 4)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawLine(const Offset(8, 6), const Offset(8, 10), paint);
      canvas.drawLine(const Offset(6, 8), const Offset(10, 8), paint);
    } else {
      canvas.drawLine(const Offset(3, 5), const Offset(11, 5), paint);
      canvas.drawLine(const Offset(8, 2), const Offset(12, 5), paint);
      canvas.drawLine(const Offset(8, 8), const Offset(12, 5), paint);
      canvas.drawLine(const Offset(5, 11), const Offset(13, 11), paint);
      canvas.drawLine(const Offset(8, 8), const Offset(5, 11), paint);
      canvas.drawLine(const Offset(8, 14), const Offset(5, 11), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OptionIconPainter oldDelegate) {
    return oldDelegate.mode != mode || oldDelegate.color != color;
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: GreenPrimitives.p500Light,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: const Color(0xFFEAFEEF),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? context.colors.background.inverse
        : context.colors.background.raised;
    return Container(
      width: 20,
      height: 20,
      decoration: ShapeDecoration(color: fill, shape: const OvalBorder()),
      child: selected
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: context.colors.icon.inverse,
              ),
            )
          : null,
    );
  }
}
