part of '../ironwood_migration_flow_screen.dart';

class _MigrationPreparingStatusContent extends StatelessWidget {
  const _MigrationPreparingStatusContent({
    super.key,
    required this.status,
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
    required this.progressKeys,
  });

  final rust_sync.MigrationStatus status;
  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final List<String> progressKeys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            top: 61,
            left: 12,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Migration in Progress',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _migrationPreparingDurationLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 164,
            width: 396,
            height: 65,
            child: _MigrationStatusBatchChart(
              values: values,
              totalZatoshi: totalZatoshi,
              statuses: statuses,
              progresses: progresses,
              progressKeys: progressKeys,
              preparingStyle: true,
            ),
          ),
          Positioned(
            left: 12,
            top: 264,
            width: 396,
            child: _MigrationPreparingStepsCard(
              status: status,
              partCount: values.length,
            ),
          ),
          const Positioned(
            left: 83,
            top: 460,
            width: 254,
            child: _MigrationPreparingInfo(),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: Center(
              child: AppButton(
                key: const ValueKey('ironwood_migration_status_action_button'),
                onPressed: () => context.go('/home'),
                variant: AppButtonVariant.secondary,
                height: 36,
                minWidth: 96,
                expand: false,
                child: const SizedBox(
                  width: 64,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Go home'),
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

class _MigrationPreparingStepsCard extends StatelessWidget {
  const _MigrationPreparingStepsCard({
    required this.status,
    required this.partCount,
  });

  final rust_sync.MigrationStatus status;
  final int partCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final splitComplete = _migrationPreparingSplitComplete(status);
    final confirmationsComplete = _migrationPreparingConfirmationsComplete(
      status,
    );
    final remainingBlocks = _migrationPreparingRemainingConfirmationBlocks(
      status,
    );
    final effectivePartCount = math.max(1, partCount);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Note split',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _MigrationPreparingStepRow(
              stepKey: 'split',
              state: splitComplete
                  ? _MigrationPreparationStepState.complete
                  : _MigrationPreparationStepState.active,
              label:
                  'Split notes into $effectivePartCount migration '
                  '${effectivePartCount == 1 ? 'part' : 'parts'}',
            ),
            const _MigrationPreparingStepConnector(),
            _MigrationPreparingStepRow(
              stepKey: 'confirmations',
              state: confirmationsComplete
                  ? _MigrationPreparationStepState.complete
                  : splitComplete
                  ? _MigrationPreparationStepState.active
                  : _MigrationPreparationStepState.pending,
              showPendingLoader: true,
              stepNumber: 2,
              label: remainingBlocks <= 0
                  ? 'Waiting for confirmation'
                  : 'Wait $remainingBlocks '
                        '${remainingBlocks == 1 ? 'block' : 'blocks'} '
                        'for confirmation',
            ),
          ],
        ),
      ),
    );
  }
}

class _MigrationPreparingStepRow extends StatelessWidget {
  const _MigrationPreparingStepRow({
    required this.stepKey,
    required this.state,
    required this.label,
    this.stepNumber,
    this.showPendingLoader = false,
  });

  final String stepKey;
  final _MigrationPreparationStepState state;
  final String label;
  final int? stepNumber;
  final bool showPendingLoader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: ValueKey('ironwood_migration_prepare_step_${stepKey}_${state.name}'),
      children: [
        _MigrationPreparingStepBadge(
          state: state,
          stepNumber: stepNumber,
          showPendingLoader: showPendingLoader,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: state == _MigrationPreparationStepState.pending
                  ? colors.text.secondary
                  : colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _MigrationPreparingStepBadge extends StatelessWidget {
  const _MigrationPreparingStepBadge({
    required this.state,
    required this.stepNumber,
    this.showPendingLoader = false,
  });

  final _MigrationPreparationStepState state;
  final int? stepNumber;
  final bool showPendingLoader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final animateLoader =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final backgroundColor = switch (state) {
      _MigrationPreparationStepState.complete => GreenPrimitives.p500Light,
      _MigrationPreparationStepState.active => colors.background.inverse,
      _MigrationPreparationStepState.pending => colors.background.raised,
    };
    final foregroundColor = switch (state) {
      _MigrationPreparationStepState.complete => Colors.white,
      _MigrationPreparationStepState.active => colors.icon.inverse,
      _MigrationPreparationStepState.pending => colors.text.secondary,
    };

    return SizedBox(
      width: 24,
      height: 24,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: const OvalBorder(),
        ),
        child: Center(
          child: switch (state) {
            _MigrationPreparationStepState.complete => AppIcon(
              AppIcons.check,
              size: 14,
              color: foregroundColor,
            ),
            _MigrationPreparationStepState.active => AppIcon(
              AppIcons.loader,
              size: 15,
              color: foregroundColor,
              animated: animateLoader,
            ),
            _MigrationPreparationStepState.pending =>
              showPendingLoader
                  ? AppIcon(
                      AppIcons.loader,
                      size: 15,
                      color: foregroundColor,
                      animated: animateLoader,
                    )
                  : Text(
                      '${stepNumber ?? ''}',
                      style: AppTypography.labelMedium.copyWith(
                        color: foregroundColor,
                      ),
                    ),
          },
        ),
      ),
    );
  }
}

class _MigrationPreparingStepConnector extends StatelessWidget {
  const _MigrationPreparingStepConnector();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 34,
      child: CustomPaint(
        painter: _MigrationPreparingStepConnectorPainter(
          color: context.colors.border.regular,
        ),
      ),
    );
  }
}

class _MigrationPreparingStepConnectorPainter extends CustomPainter {
  const _MigrationPreparingStepConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    var y = 4.0;
    const dash = 3.5;
    const gap = 3.0;
    final x = size.width / 2;
    while (y < size.height - 4) {
      final nextY = math.min(y + dash, size.height - 4);
      canvas.drawLine(Offset(x, y), Offset(x, nextY), paint);
      y = nextY + gap;
    }
  }

  @override
  bool shouldRepaint(
    covariant _MigrationPreparingStepConnectorPainter oldDelegate,
  ) => oldDelegate.color != color;
}

class _MigrationPreparingInfo extends StatelessWidget {
  const _MigrationPreparingInfo();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Text(
          'Migration will start automatically once note split is complete.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'You can leave this screen, but keep Vizor open & running.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

bool _migrationPreparingSplitComplete(rust_sync.MigrationStatus status) {
  if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
    return true;
  }

  final total = status.denominationSplitTotalCount;
  if (total > 0) {
    return status.denominationSplitCompletedCount >= total &&
        status.pendingSplitStageCount <= 0;
  }
  return status.pendingSplitStageCount <= 0;
}

bool _migrationPreparingConfirmationsComplete(
  rust_sync.MigrationStatus status,
) {
  final target = status.denominationConfirmationTarget;
  return target > 0 && status.denominationConfirmationCount >= target;
}

int _migrationPreparingRemainingConfirmationBlocks(
  rust_sync.MigrationStatus status,
) {
  final target = status.denominationConfirmationTarget > 0
      ? status.denominationConfirmationTarget
      : _migrationPrepareConfirmationBlocks;
  return math.max(0, target - status.denominationConfirmationCount);
}

String _migrationPreparingDurationLabel() => 'This will take 10-20 min';

_MigrationBatchStatus _migrationBatchStatus(
  rust_sync.MigrationPartState state,
) => switch (state) {
  rust_sync.MigrationPartState.preparing => _MigrationBatchStatus.preparing,
  rust_sync.MigrationPartState.scheduled => _MigrationBatchStatus.scheduled,
  rust_sync.MigrationPartState.migrating => _MigrationBatchStatus.migrating,
  rust_sync.MigrationPartState.confirming => _MigrationBatchStatus.confirming,
  rust_sync.MigrationPartState.completed => _MigrationBatchStatus.complete,
  rust_sync.MigrationPartState.needsInput => _MigrationBatchStatus.needsInput,
};

List<_MigrationBatchStatus> _legacyMigrationBatchStatuses(
  rust_sync.MigrationStatus status,
  int count,
) {
  if (status.phase == kIronwoodMigrationCompletePhase) {
    return List<_MigrationBatchStatus>.filled(
      count,
      _MigrationBatchStatus.complete,
    );
  }

  final hasTransferProgress =
      status.pendingTxCount > 0 ||
      status.broadcastedTxCount > 0 ||
      status.confirmedTxCount > 0 ||
      status.scheduledBroadcasts.isNotEmpty;
  if (status.phase == kIronwoodMigrationReadyToMigratePhase &&
      !hasTransferProgress) {
    return List<_MigrationBatchStatus>.filled(
      count,
      _MigrationBatchStatus.none,
    );
  }

  final hasBroadcastSchedule =
      status.scheduledBroadcasts.isNotEmpty ||
      status.phase == kIronwoodMigrationBroadcastScheduledPhase ||
      status.phase == kIronwoodMigrationBroadcastingPhase ||
      status.phase == kIronwoodMigrationWaitingConfirmationsPhase;
  final submittedCount = status.confirmedTxCount + status.broadcastedTxCount;
  return [
    for (var i = 0; i < count; i++)
      if (i < status.confirmedTxCount)
        _MigrationBatchStatus.confirming
      else if (i < submittedCount)
        _MigrationBatchStatus.migrating
      else if (hasBroadcastSchedule)
        _MigrationBatchStatus.scheduled
      else
        _MigrationBatchStatus.preparing,
  ];
}

int _currentMigrationHeight(SyncState? syncState) {
  if (syncState == null) return 0;
  final scannedHeight = syncState.scannedHeight;
  final chainTipHeight = syncState.chainTipHeight;
  if (scannedHeight > 0 && chainTipHeight > 0) {
    return math.min(scannedHeight, chainTipHeight);
  }
  return math.max(scannedHeight, chainTipHeight);
}

List<double> _migrationBatchProgresses({
  required rust_sync.MigrationStatus status,
  required List<rust_sync.MigrationPartStatus> parts,
  required List<_MigrationBatchStatus> statuses,
  required int currentHeight,
  required bool isAdvancing,
}) {
  if (statuses.isEmpty) return const [];

  if (status.phase == kIronwoodMigrationCompletePhase) {
    return List<double>.filled(statuses.length, 1);
  }

  if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
    final hasDenominationPartProgress =
        parts.isNotEmpty &&
        parts.any(
          (part) => part.state != rust_sync.MigrationPartState.preparing,
        );
    if (hasDenominationPartProgress) {
      return [
        for (var i = 0; i < parts.length; i++)
          _migrationPartStatusProgress(
            part: parts[i],
            visualStatus: i < statuses.length
                ? statuses[i]
                : _migrationBatchStatus(parts[i].state),
            currentHeight: currentHeight,
            isAdvancing: isAdvancing,
            preparePhase: true,
          ),
      ];
    }

    final progress = _prepareMigrationProgress(
      status,
      isAdvancing: isAdvancing,
    );
    return List<double>.filled(statuses.length, progress);
  }

  if (parts.isNotEmpty) {
    return [
      for (var i = 0; i < parts.length; i++)
        _migrationPartStatusProgress(
          part: parts[i],
          visualStatus: i < statuses.length
              ? statuses[i]
              : _migrationBatchStatus(parts[i].state),
          currentHeight: currentHeight,
          isAdvancing: isAdvancing,
        ),
    ];
  }

  return [
    for (var i = 0; i < statuses.length; i++)
      _legacyMigrationBatchProgress(
        status: status,
        visualStatus: statuses[i],
        index: i,
        currentHeight: currentHeight,
        isAdvancing: isAdvancing,
      ),
  ];
}

double _prepareMigrationProgress(
  rust_sync.MigrationStatus status, {
  required bool isAdvancing,
}) {
  final totalStages = status.denominationSplitTotalCount;
  final stageProgress = totalStages > 0
      ? (status.denominationSplitCompletedCount / totalStages).clamp(0, 1)
      : 0.0;

  if (status.pendingSplitStageCount > 0) {
    return math.max(stageProgress.toDouble(), isAdvancing ? 0.18 : 0.12);
  }

  final confirmationTarget = status.denominationConfirmationTarget;
  if (confirmationTarget > 0) {
    final confirmationProgress =
        (status.denominationConfirmationCount / confirmationTarget).clamp(0, 1);
    final combined =
        _prepareBroadcastCommitProgress +
        (1 - _prepareBroadcastCommitProgress) * confirmationProgress;
    return math.max(stageProgress.toDouble(), combined);
  }

  return math.max(stageProgress.toDouble(), isAdvancing ? 0.24 : 0.16);
}

double _prepareConfirmationProgress({
  required int confirmationCount,
  required int confirmationTarget,
}) {
  if (confirmationTarget <= 0) return _prepareBroadcastCommitProgress;
  final confirmationProgress = (confirmationCount / confirmationTarget)
      .clamp(0, 1)
      .toDouble();
  return _prepareBroadcastCommitProgress +
      (1 - _prepareBroadcastCommitProgress) * confirmationProgress;
}

double _migrationPartStatusProgress({
  required rust_sync.MigrationPartStatus part,
  required _MigrationBatchStatus visualStatus,
  required int currentHeight,
  required bool isAdvancing,
  bool preparePhase = false,
}) {
  if (visualStatus == _MigrationBatchStatus.needsInput) {
    return math.max(
      _scheduledBlockProgress(
        startHeight: part.scheduleStartHeight,
        targetHeight: part.scheduledHeight,
        currentHeight: currentHeight,
      ),
      _scheduledBlockProgressCap,
    );
  }

  return switch (part.state) {
    rust_sync.MigrationPartState.preparing => 0.12,
    rust_sync.MigrationPartState.scheduled => _scheduledBlockProgress(
      startHeight: part.scheduleStartHeight,
      targetHeight: part.scheduledHeight,
      currentHeight: currentHeight,
    ),
    rust_sync.MigrationPartState.migrating =>
      preparePhase
          ? _prepareBroadcastCommitProgress
          : isAdvancing
          ? _broadcastCommitProgressCap
          : _scheduledBlockProgressCap,
    rust_sync.MigrationPartState.confirming =>
      preparePhase
          ? _prepareConfirmationProgress(
              confirmationCount: part.confirmationCount,
              confirmationTarget: part.confirmationTarget,
            )
          : _confirmationProgress(
              confirmationCount: part.confirmationCount,
              confirmationTarget: part.confirmationTarget,
            ),
    rust_sync.MigrationPartState.completed => 1,
    rust_sync.MigrationPartState.needsInput => _scheduledBlockProgressCap,
  };
}

double _legacyMigrationBatchProgress({
  required rust_sync.MigrationStatus status,
  required _MigrationBatchStatus visualStatus,
  required int index,
  required int currentHeight,
  required bool isAdvancing,
}) {
  return switch (visualStatus) {
    _MigrationBatchStatus.none => 0,
    _MigrationBatchStatus.preparing => isAdvancing ? 0.18 : 0.12,
    _MigrationBatchStatus.scheduled => _legacyScheduledProgress(
      status,
      index,
      currentHeight: currentHeight,
    ),
    _MigrationBatchStatus.migrating =>
      isAdvancing ? _broadcastCommitProgressCap : _scheduledBlockProgressCap,
    _MigrationBatchStatus.confirming =>
      status.totalCount > 0
          ? _confirmationProgress(
              confirmationCount: status.confirmedTxCount,
              confirmationTarget: status.totalCount,
            )
          : _broadcastCommitProgressCap,
    _MigrationBatchStatus.complete => 1,
    _MigrationBatchStatus.needsInput => _scheduledBlockProgressCap,
  };
}

double _legacyScheduledProgress(
  rust_sync.MigrationStatus status,
  int index, {
  required int currentHeight,
}) {
  final scheduled = [...status.scheduledBroadcasts]
    ..sort((a, b) => a.scheduledHeight.compareTo(b.scheduledHeight));
  if (index >= scheduled.length) return 0;
  final broadcast = scheduled[index];
  return _scheduledBlockProgress(
    startHeight: broadcast.scheduleStartHeight,
    targetHeight: broadcast.scheduledHeight,
    currentHeight: currentHeight,
  );
}

double _scheduledBlockProgress({
  required int? startHeight,
  required int? targetHeight,
  required int currentHeight,
}) {
  if (targetHeight == null || currentHeight <= 0) return 0;
  final effectiveStart = startHeight ?? math.max(0, targetHeight - 1);
  if (targetHeight <= effectiveStart) {
    return currentHeight >= targetHeight ? _scheduledBlockProgressCap : 0;
  }
  final elapsed = (currentHeight - effectiveStart).clamp(
    0,
    targetHeight - effectiveStart,
  );
  return _scheduledBlockProgressCap *
      (elapsed / (targetHeight - effectiveStart));
}

double _confirmationProgress({
  required int confirmationCount,
  required int confirmationTarget,
}) {
  if (confirmationTarget <= 0) return _broadcastCommitProgressCap;
  final confirmationRatio = (confirmationCount / confirmationTarget).clamp(
    0,
    1,
  );
  return _broadcastCommitProgressCap +
      (1 - _broadcastCommitProgressCap) * confirmationRatio;
}
