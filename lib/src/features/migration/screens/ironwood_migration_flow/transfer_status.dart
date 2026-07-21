part of '../ironwood_migration_flow_screen.dart';

// ignore: unused_element
class _PrivateDenominationWaitingStatusContent extends StatelessWidget {
  const _PrivateDenominationWaitingStatusContent({
    required this.status,
    required this.presentation,
    required this.footerText,
  });

  final rust_sync.MigrationStatus status;
  final _StatusPresentation presentation;
  final String footerText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final targetTotal = _sumTargetValues(status);
    final amountText = targetTotal > BigInt.zero
        ? '${_formatZecAmountCompact(targetTotal)} ZEC'
        : '${status.preparedNoteCount} notes';

    return SizedBox(
      key: const ValueKey(
        'ironwood_migration_status_waiting_denom_confirmations',
      ),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 22,
            top: 16,
            width: 376,
            height: 130,
            child: CustomPaint(
              painter: _PreparingArcPainter(
                dotColor: colors.icon.muted.withValues(alpha: 0.24),
                primaryDotColor: colors.icon.muted.withValues(alpha: 0.16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 102,
            width: 420,
            child: Column(
              children: [
                Text(
                  amountText,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: appSerifDisplayStyle(
                    color: colors.text.secondary,
                  ).copyWith(fontSize: 39, height: 42 / 39),
                ),
                const SizedBox(height: 12),
                Text(
                  presentation.body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 246,
            width: 396,
            child: _MigrationPreparationStepsCard(status: status),
          ),
          Positioned(
            left: 70,
            top: 510,
            width: 280,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _PrivateMigrationTransferStatusContent extends StatelessWidget {
  const _PrivateMigrationTransferStatusContent({
    required this.status,
    required this.presentation,
    required this.footerText,
  });

  final rust_sync.MigrationStatus status;
  final _StatusPresentation presentation;
  final String footerText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = _transferProgress(status);
    final percent = (progress * 100).round().clamp(0, 100);
    final plannedBatchCount = _plannedTransferBatchCount(status);
    final currentBatchIndex = _currentTransferBatchIndex(status);
    final currentBatchAmount = _currentTransferBatchAmount(
      status,
      plannedBatchCount: plannedBatchCount,
    );
    final leftToTransfer = _leftToTransferAmount(status, progress: progress);

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 38,
            top: 42,
            width: 344,
            height: 130,
            child: CustomPaint(
              painter: _MigrationProgressArcPainter(
                progress: progress,
                trackColor: colors.icon.muted.withValues(alpha: 0.20),
                progressColor: GreenPrimitives.p500Light,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 143,
            width: 420,
            child: Column(
              children: [
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$percent%',
                  textAlign: TextAlign.center,
                  style: appSerifDisplayStyle(
                    color: colors.text.accent,
                  ).copyWith(fontSize: 45, height: 48 / 45),
                ),
                const SizedBox(height: 4),
                Text(
                  'Left to transfer: '
                  '${leftToTransfer.isEstimated ? '~' : ''}'
                  '${_formatZecAmountCompact(leftToTransfer.value)} ZEC',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 278,
            width: 396,
            child: _MigrationTransferBatchCard(
              plannedBatchCount: plannedBatchCount,
              currentBatchIndex: currentBatchIndex,
              currentBatchValue: currentBatchAmount.value,
              currentBatchValueIsEstimated: currentBatchAmount.isEstimated,
              currentBatchStatus: _currentTransferBatchStatus(status),
              estimatedArrival: _transferEstimatedArrival(status),
            ),
          ),
          Positioned(
            left: 70,
            top: 552,
            width: 280,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationProgressArcPainter extends CustomPainter {
  const _MigrationProgressArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(18, 12, size.width - 36, size.height * 1.8);
    const startAngle = math.pi * 1.14;
    const sweepAngle = math.pi * 0.72;
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect, startAngle, sweepAngle, false, trackPaint);

    if (progress <= 0) return;
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MigrationProgressArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}

class _MigrationTransferBatchCard extends StatelessWidget {
  const _MigrationTransferBatchCard({
    required this.plannedBatchCount,
    required this.currentBatchIndex,
    required this.currentBatchValue,
    required this.currentBatchValueIsEstimated,
    required this.currentBatchStatus,
    required this.estimatedArrival,
  });

  final int plannedBatchCount;
  final int currentBatchIndex;
  final BigInt currentBatchValue;
  final bool currentBatchValueIsEstimated;
  final String currentBatchStatus;
  final String estimatedArrival;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.regular,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$plannedBatchCount Planned batches',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  'View',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(width: 8),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 16,
                  color: colors.icon.regular,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: colors.border.subtle),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Current Batch',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  currentBatchIndex.toString().padLeft(2, '0'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: GoldPrimitives.p300Light,
                    shape: OvalBorder(),
                  ),
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(
                      child: AppIcon(
                        AppIcons.zcashCurrency,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${currentBatchValueIsEstimated ? '~' : ''}'
                    '${_formatZecAmountCompact(currentBatchValue)} ZEC',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  currentBatchStatus,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: colors.border.subtle),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated arrival time',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  estimatedArrival,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
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

class _PreparingArcPainter extends CustomPainter {
  const _PreparingArcPainter({
    required this.dotColor,
    required this.primaryDotColor,
  });

  final Color dotColor;
  final Color primaryDotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 23);
    final xRadius = size.width * 0.49;
    final yRadius = size.height * 0.82;
    final dotPaint = Paint()..color = dotColor;
    for (var i = 0; i <= 28; i++) {
      final t = i / 28;
      final angle = math.pi + (math.pi * t);
      final wave = math.sin(t * math.pi * 6) * 2.8;
      final r = 2.2 + (math.sin(t * math.pi * 9).abs() * 5.4);
      final point = Offset(
        center.dx + math.cos(angle) * (xRadius + wave),
        center.dy + math.sin(angle) * (yRadius + wave),
      );
      canvas.drawCircle(point, r, dotPaint);
    }

    final primaryPaint = Paint()..color = primaryDotColor;
    canvas
      ..drawCircle(Offset(center.dx, 14), 17, primaryPaint)
      ..drawCircle(Offset(center.dx - 39, 18), 9, primaryPaint)
      ..drawCircle(Offset(center.dx + 40, 19), 6.5, primaryPaint);
  }

  @override
  bool shouldRepaint(covariant _PreparingArcPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.primaryDotColor != primaryDotColor;
  }
}

class _MigrationPreparationStepsCard extends StatelessWidget {
  const _MigrationPreparationStepsCard({required this.status});

  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = status.denominationConfirmationTarget;
    final confirmationCount = target > 0
        ? math.min(status.denominationConfirmationCount, target)
        : status.denominationConfirmationCount;
    final confirmationComplete = target > 0 && confirmationCount >= target;
    final scheduleReady =
        status.denominationSplitTotalCount > 0 &&
        status.denominationSplitCompletedCount >=
            status.denominationSplitTotalCount;
    final confirmationLabel = target > 0
        ? '$confirmationCount/$target'
        : '$confirmationCount confirmations';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.regular,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 50, 18, 54),
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 62,
              height: 112,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.border.subtle,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: const SizedBox(width: 2),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MigrationPreparationStepRow(
                  state: _MigrationPreparationStepState.complete,
                  label: 'Transaction splits submitted',
                ),
                const SizedBox(height: 32),
                _MigrationPreparationStepRow(
                  state: confirmationComplete
                      ? _MigrationPreparationStepState.complete
                      : _MigrationPreparationStepState.active,
                  label: 'Waiting for confirmation ...',
                  trailing: confirmationLabel,
                ),
                const SizedBox(height: 32),
                _MigrationPreparationStepRow(
                  state: scheduleReady
                      ? _MigrationPreparationStepState.complete
                      : confirmationComplete
                      ? _MigrationPreparationStepState.active
                      : _MigrationPreparationStepState.pending,
                  stepNumber: 3,
                  label: 'Migration schedule',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _MigrationPreparationStepState { complete, active, pending }

class _MigrationPreparationStepRow extends StatelessWidget {
  const _MigrationPreparationStepRow({
    required this.state,
    required this.label,
    this.stepNumber,
    this.trailing,
  });

  final _MigrationPreparationStepState state;
  final String label;
  final int? stepNumber;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        _MigrationPreparationStepBadge(state: state, stepNumber: stepNumber),
        const SizedBox(width: 16),
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
        if (trailing != null) ...[
          const SizedBox(width: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.raised,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Text(
                trailing!,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MigrationPreparationStepBadge extends StatelessWidget {
  const _MigrationPreparationStepBadge({
    required this.state,
    required this.stepNumber,
  });

  final _MigrationPreparationStepState state;
  final int? stepNumber;

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
            _MigrationPreparationStepState.pending => Text(
              '${stepNumber ?? ''}',
              style: AppTypography.labelMedium.copyWith(color: foregroundColor),
            ),
          },
        ),
      ),
    );
  }
}

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
) {
  final estimatedBlocks = _estimatedMigrationCompletionBlocks(plan);
  if (estimatedBlocks <= 0) return 'Not scheduled';
  return _formatMigrationBlockDurationEstimate(estimatedBlocks);
}

int _estimatedMigrationCompletionBlocks(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final scheduleBlocks = plan.scheduledTransfers.fold<int>(
    0,
    (maxOffset, transfer) => math.max(maxOffset, transfer.blockOffset),
  );
  final fallbackBatchCount = plan.plannedBatchCount < 1
      ? 1
      : plan.plannedBatchCount;
  final fallbackScheduleBlocks =
      plan.scheduleMeanDelayBlocks * fallbackBatchCount;
  final preparedScheduleBlocks = scheduleBlocks > 0
      ? scheduleBlocks
      : fallbackScheduleBlocks;
  if (preparedScheduleBlocks <= 0) return 0;

  final int prepareBlocks = plan.denominationSplitStageCount <= 0
      ? 0
      : plan.denominationSplitStageCount * _migrationPrepareConfirmationBlocks +
            _migrationPrepareBroadcastBufferBlocks;
  return preparedScheduleBlocks + prepareBlocks;
}

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
